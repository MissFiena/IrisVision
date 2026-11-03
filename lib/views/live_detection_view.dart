import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/app_settings.dart';
import '../services/lang.dart';
import '../services/tflite_service.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class LiveDetectionView extends StatefulWidget {
  const LiveDetectionView({super.key});

  @override
  State<LiveDetectionView> createState() => _LiveDetectionViewState();
}

class _LiveDetectionViewState extends State<LiveDetectionView> with WidgetsBindingObserver {
  CameraController? _cameraController;
  CameraDescription? _camera;
  bool _isCameraInitialized = false;
  bool _permissionDenied = false;
  bool _disposed = false;
  bool _starting = false;
  bool _initializing = false;
  String? _errorMessage;

  final TFLiteService _tfLiteService = TFLiteService();

  // Hanya overlay + teks yang rebuild setiap frame (bukan seluruh skrin) -> kurang lag
  final ValueNotifier<DetectionResult> _result =
      ValueNotifier<DetectionResult>(const DetectionResult.empty());

  bool _isProcessingFrame = false;
  int _lastFrameMs = 0;
  static const int _minFrameGapMs = 100; // had ~10 FPS supaya telefon tak panas
  int _sensorRotation = 90;

  // ============================ SUARA ============================
  final TtsService _tts = TtsService.instance;
  final AppSettings _settings = AppSettings.instance;
  bool _announced = false;
  String _sceneKey = ''; // objek yang terakhir disebut
  String _pendingKey = ''; // objek dalam frame terkini (belum tentu stabil)
  int _pendingCount = 0;
  int _lastSpokenMs = 0;
  int _lastTooFarMs = 0;
  int _emptySinceMs = 0;
  static const int _stableFrames = 2; // mesti sama 2 frame berturut baru disebut
  static const int _minGapMs = 1500; // jarak minimum antara dua ayat
  static const int _repeatSameMs = 10000; // objek sama disebut semula selepas 10 s
  static const int _forgetMs = 1500; // kosong selama ini -> objek dianggap hilang
  static const int _maxSpoken = 3; // sebut paling banyak 3 objek sekali gus

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSystem();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_disposed) setState(fn);
  }

  // ============================ INIT ============================
  Future<void> _initializeSystem() async {
    // dialog kebenaran pun trigger inactive->resumed, jadi elak init berganda
    if (_initializing || _disposed) return;
    _initializing = true;
    _safeSetState(() {
      _errorMessage = null;
      _permissionDenied = false;
    });

    try {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        _safeSetState(() => _permissionDenied = true);
        return;
      }

      if (!_tfLiteService.isModelLoaded) {
        await _tfLiteService.loadModel();
      }
      if (!_tfLiteService.isModelLoaded) {
        throw t('Model AI gagal dimuatkan.', 'The AI model failed to load.');
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw t('Tiada kamera dijumpai pada peranti ini.', 'No camera found on this device.');
      }

      // pilih kamera BELAKANG
      _camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _sensorRotation = _camera!.sensorOrientation;

      await _startCamera();
    } catch (e) {
      debugPrint('❌ Ralat init: $e');
      _safeSetState(() => _errorMessage = '${t('Gagal memulakan kamera.', 'Failed to start the camera.')}\n$e');
    } finally {
      _initializing = false;
    }
  }

  // ======================== CAMERA START / STOP ========================
  Future<void> _startCamera() async {
    final camera = _camera;
    if (camera == null || _starting || _cameraController != null || _disposed) return;
    _starting = true;

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _cameraController = controller;

    try {
      await controller.initialize();
      if (_disposed || _cameraController != controller) {
        await controller.dispose();
        return;
      }
      await controller.startImageStream(_onFrame);
      _safeSetState(() {
        _isCameraInitialized = true;
        _errorMessage = null;
      });
      if (!_announced && mounted) {
        _announced = true;
        _tts.announceScreen(
          context,
          'Kesan objek. Halakan kamera ke hadapan.',
          'Object detection. Point the camera ahead.',
        );
      }
    } catch (e) {
      debugPrint('❌ Ralat kamera: $e');
      if (_cameraController == controller) _cameraController = null;
      try {
        await controller.dispose();
      } catch (_) {}
      _safeSetState(() {
        _isCameraInitialized = false;
        _errorMessage =
            '${t('Kamera tidak dapat dibuka. Mungkin sedang digunakan oleh aplikasi lain.', 'The camera could not open. Another app may be using it.')}\n$e';
      });
    } finally {
      _starting = false;
    }
  }

  /// Stop stream DULU, baru dispose -> elak crash bila frame masih diproses
  Future<void> _stopCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    _safeSetState(() => _isCameraInitialized = false);
    if (controller == null) return;

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
    try {
      await controller.dispose();
    } catch (_) {}
  }

  // ===================== APP MINIMIZE / RESUME =====================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // app ke background -> lepaskan kamera supaya app lain boleh guna
      _tts.stop();
      _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (_permissionDenied || _camera == null) {
        // user mungkin baru balik dari Tetapan selepas bagi kebenaran
        if (!_initializing && !_starting) _initializeSystem();
      } else {
        _startCamera();
      }
    }
  }

  // ============================ FRAMES ============================
  Future<void> _onFrame(CameraImage image) async {
    if (_disposed || _isProcessingFrame) return;

    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFrameMs < _minFrameGapMs) return;
    _lastFrameMs = now;

    _isProcessingFrame = true;
    try {
      final result = await _tfLiteService.processCameraFrame(image, _sensorRotation);
      if (!_disposed) {
        _result.value = result;
        _maybeSpeak(result);
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  // ======================== SUARA: LOGIK ========================
  /// Pilih objek untuk disebut: unik, keyakinan tertinggi, maks 3,
  /// disusun kiri -> tengah -> kanan supaya ayat mudah dibayangkan.
  List<Detection> _top(DetectionResult r) {
    final sorted = [...r.detections]..sort((a, b) => b.confidence.compareTo(a.confidence));
    final seen = <String>{};
    final out = <Detection>[];
    for (final d in sorted) {
      if (seen.add('${d.label}@${d.position}')) out.add(d);
      if (out.length == _maxSpoken) break;
    }
    const order = {'kiri': 0, 'tengah': 1, 'kanan': 2};
    out.sort((a, b) => (order[a.position] ?? 1).compareTo(order[b.position] ?? 1));
    return out;
  }

  void _maybeSpeak(DetectionResult r) {
    if (!_settings.speakDetections.value || !_announced) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final top = _top(r);

    if (top.isEmpty) {
      _pendingKey = '';
      _pendingCount = 0;
      if (_emptySinceMs == 0) _emptySinceMs = now;
      // kosong cukup lama -> bila objek sama muncul semula, sebut lagi
      if (now - _emptySinceMs > _forgetMs) _sceneKey = '';
      if (r.tooFar && !_tts.isSpeaking && now - _lastTooFarMs > 8000) {
        _lastTooFarMs = now;
        _lastSpokenMs = now;
        _tts.announce('Dekatkan kamera.', 'Move the camera closer.');
      }
      return;
    }
    _emptySinceMs = 0;

    final key = top.map((d) => '${d.label}@${d.position}').join('|');
    if (key == _pendingKey) {
      _pendingCount++;
    } else {
      _pendingKey = key;
      _pendingCount = 1;
    }
    if (_pendingCount < _stableFrames) return; // tunggu stabil, elak berkelip
    if (_tts.isSpeaking) return; // jangan potong ayat yang sedang dibaca
    if (now - _lastSpokenMs < _minGapMs) return;

    final isNew = key != _sceneKey;
    if (!isNew && now - _lastSpokenMs < _repeatSameMs) return;

    _sceneKey = key;
    _lastSpokenMs = now;
    if (isNew && _settings.vibrate.value) HapticFeedback.mediumImpact();
    unawaited(_tts.speak(_spoken(top), lang: _tts.uiLang));
  }

  void _toggleVoice() {
    final on = !_settings.speakDetections.value;
    _settings.speakDetections.value = on;
    HapticFeedback.selectionClick();
    if (on) {
      _sceneKey = ''; // sebut semula objek semasa
      _tts.announce('Suara dihidupkan.', 'Voice on.', remember: false);
    } else {
      _tts.announce('Suara dimatikan.', 'Voice off.', remember: false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _tts.stop();
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera(); // stop stream dulu, kemudian dispose kamera
    _tfLiteService.dispose(); // tunggu frame semasa siap sebelum tutup model
    _result.dispose();
    super.dispose();
  }

  // ============================== UI ==============================
  /// Nama paparan BM ringkas untuk label model (yang tiada -> huruf kecil biasa).
  static const Map<String, String> _bm = {
    'PERSON': 'Orang', 'BICYCLE': 'Basikal', 'CAR': 'Kereta', 'MOTORCYCLE': 'Motosikal',
    'BUS': 'Bas', 'BENCH': 'Bangku', 'CHAIR': 'Kerusi', 'COUCH': 'Sofa', 'PLANT': 'Pokok pasu',
    'TABLE': 'Meja', 'REFRIGERATOR': 'Peti sejuk', 'TV': 'TV', 'LAPTOP': 'Laptop',
    'BACKPACK': 'Beg galas', 'SUITCASE': 'Beg pakaian', 'BOTTLE': 'Botol', 'CUP': 'Cawan',
    'MOUSE': 'Tetikus', 'KEYBOARD': 'Papan kekunci', 'CELL PHONE': 'Telefon', 'BOOK': 'Buku',
    'CLOCK': 'Jam', 'SCISSORS': 'Gunting', 'UMBRELLA': 'Payung', 'HANDBAG': 'Beg tangan',
    'TOILET': 'Tandas', 'SINK': 'Sinki', 'DOG': 'Anjing', 'CAT': 'Kucing',
  };

  bool get _isBm => _settings.language.value == VoiceLanguage.bm;

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Nama untuk kotak dan panel (ikut bahasa pilihan).
  String _name(String label) {
    if (_isBm) {
      final bm = _bm[label];
      if (bm != null) return bm;
    }
    if (label == 'TV') return 'TV';
    return _cap(label.toLowerCase());
  }

  String _posPhrase(String pos) {
    if (_isBm) {
      return switch (pos) { 'kiri' => 'di sebelah kiri', 'kanan' => 'di sebelah kanan', _ => 'di hadapan' };
    }
    return switch (pos) { 'kiri' => 'on your left', 'kanan' => 'on your right', _ => 'ahead' };
  }

  /// Ayat yang dipaparkan DAN dibaca. Contoh:
  /// "Kerusi di sebelah kiri. Meja dan laptop di hadapan."
  String _spoken(List<Detection> top) {
    final and = _isBm ? ' dan ' : ' and ';
    final groups = <String, List<String>>{};
    for (final d in top) {
      final n = _name(d.label);
      groups.putIfAbsent(d.position, () => []).add(n == 'TV' ? n : n.toLowerCase());
    }
    final sentences = groups.entries.map((e) => _cap('${e.value.join(and)} ${_posPhrase(e.key)}.'));
    return sentences.join(' ');
  }

  String _sentence(DetectionResult r) {
    final top = _top(r);
    if (top.isNotEmpty) return _spoken(top);
    if (r.tooFar) {
      return _isBm ? 'Ada objek tetapi tidak jelas. Sila dekatkan kamera.' : 'Something is there but unclear. Move the camera closer.';
    }
    return _isBm ? 'Halakan kamera ke hadapan...' : 'Point the camera ahead...';
  }

  @override
  Widget build(BuildContext context) {
    context.isBm; // bina semula bila bahasa ditukar
    final Widget body;
    if (_permissionDenied) {
      body = _buildMessage(
        icon: Icons.videocam_off_outlined,
        text: context.tr('Kebenaran kamera diperlukan untuk mengesan objek.', 'Camera permission is needed to detect objects.'),
        action: context.tr('Buka tetapan', 'Open settings'),
        onAction: () => openAppSettings(),
      );
    } else if (_errorMessage != null) {
      body = _buildMessage(
        icon: Icons.error_outline,
        text: _errorMessage!,
        action: context.tr('Cuba lagi', 'Try again'),
        onAction: (_starting || _initializing) ? null : _initializeSystem,
      );
    } else if (_isCameraInitialized && _cameraController != null) {
      body = _buildCameraView(_cameraController!);
    } else {
      body = _buildMessage(icon: null, text: context.tr('Memuatkan kamera dan model AI...', 'Loading camera and AI model...'));
    }
    return Scaffold(body: body);
  }

  Widget _buildMessage({IconData? icon, required String text, String? action, VoidCallback? onAction}) {
    final p = context.pal;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TopBar(title: Headline(context.tr('Kesan Objek', 'Detect Objects'), size: 24)),
            const Spacer(),
            if (icon == null)
              const Center(child: CircularProgressIndicator())
            else
              Center(
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(color: p.tint, shape: BoxShape.circle),
                  child: Icon(icon, size: 56, color: p.accent),
                ),
              ),
            const SizedBox(height: 20),
            Semantics(
              liveRegion: true,
              child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 19, height: 1.4, color: p.textPrimary)),
            ),
            const Spacer(),
            if (action != null) BadgeButton(label: action, badgeIcon: Icons.refresh, onPressed: onAction),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView(CameraController controller) {
    final p = context.pal;
    // mod portrait: nisbah preview = 1 / nisbah landscape kamera
    final double previewAspect = 1 / controller.value.aspectRatio;

    return SizedBox.expand(
      child: Stack(
        children: [
        Positioned.fill(child: Container(color: Colors.black)),
        // Preview + kotak dalam widget yang SAMA saiz -> kotak sentiasa sejajar
        Positioned.fill(
          child: Align(
            alignment: Alignment.topCenter,
            child: AspectRatio(
              aspectRatio: previewAspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(child: CameraPreview(controller)),
                  ValueListenableBuilder<DetectionResult>(
                    valueListenable: _result,
                    builder: (context, r, _) => CustomPaint(
                      painter: _BoxPainter(r.detections, _name, p.highlight, p.onHighlight),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // butang kembali + latency
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const BackSquare(),
                const Spacer(),
                ValueListenableBuilder<bool>(
                  valueListenable: _settings.speakDetections,
                  builder: (context, on, _) => Semantics(
                    button: true,
                    toggled: on,
                    label: context.tr('Suara objek', 'Object voice'),
                    excludeSemantics: true,
                    child: Material(
                      color: on ? p.highlight : p.surface,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _toggleVoice,
                        child: SizedBox(
                          width: 56,
                          height: 48,
                          child: Icon(
                            on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                            color: on ? p.onHighlight : p.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<DetectionResult>(
                  valueListenable: _result,
                  builder: (context, r, _) {
                    final ok = r.latencyMs <= 1500;
                    return Semantics(
                      label: context.tr('Kelajuan ${r.latencyMs} milisaat', 'Speed ${r.latencyMs} milliseconds'),
                      excludeSemantics: true,
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: ok ? p.success : p.error, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Text('${r.latencyMs} ms',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.textPrimary)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        // panel bawah: ayat + KIRI / TENGAH / KANAN
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ValueListenableBuilder<DetectionResult>(
            valueListenable: _result,
            builder: (context, r, _) => _ResultPanel(
              sentence: _sentence(r),
              bm: _isBm,
              // suara app aktif -> TalkBack tak perlu baca juga (elak bertindih)
              live: !_settings.speakDetections.value,
              left: _firstAt(r, 'kiri'),
              center: _firstAt(r, 'tengah'),
              right: _firstAt(r, 'kanan'),
            ),
          ),
        ),
      ],
      ),
    );
  }

  String? _firstAt(DetectionResult r, String pos) {
    for (final d in r.detections) {
      if (d.position == pos) return _name(d.label);
    }
    return null;
  }
}

class _ResultPanel extends StatelessWidget {
  final String sentence;
  final bool bm;
  final bool live;
  final String? left, center, right;
  const _ResultPanel({
    required this.sentence,
    required this.bm,
    required this.live,
    this.left,
    this.center,
    this.right,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget cell(String pos, String? name) => Expanded(
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: name == null ? p.surfaceAlt : p.tint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(pos, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.textSecondary, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(
                  name ?? '–',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: name == null ? p.textSecondary : p.accent),
                ),
              ],
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 12),
            Text(bm ? 'Di hadapan anda' : 'In front of you', style: TextStyle(fontSize: 15, color: p.textSecondary)),
            const SizedBox(height: 2),
            // liveRegion: TalkBack baca bila ayat berubah
            Semantics(
              liveRegion: live,
              child: Text(
                sentence,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: AppFonts.heading, fontSize: 24, fontWeight: FontWeight.w700, height: 1.2, color: p.textPrimary),
              ),
            ),
            const SizedBox(height: 14),
            ExcludeSemantics(
              child: Row(
                children: [
                  cell(bm ? 'KIRI' : 'LEFT', left),
                  const SizedBox(width: 8),
                  cell(bm ? 'TENGAH' : 'CENTRE', center),
                  const SizedBox(width: 8),
                  cell(bm ? 'KANAN' : 'RIGHT', right),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lukis kotak. Koordinat detection dah 0..1 relatif kepada frame tegak,
/// jadi cuma darab dengan saiz canvas (tak perlu rotate lagi).
class _BoxPainter extends CustomPainter {
  final List<Detection> detections;
  final String Function(String) nameOf;
  final Color boxColor;
  final Color labelColor;
  _BoxPainter(this.detections, this.nameOf, this.boxColor, this.labelColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = boxColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    for (final d in detections) {
      final rect = Rect.fromLTRB(
        d.left * size.width,
        d.top * size.height,
        d.right * size.width,
        d.bottom * size.height,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(14)), paint);

      final tp = TextPainter(
        text: TextSpan(
          text: ' ${nameOf(d.label)} ${(d.confidence * 100).toStringAsFixed(0)}% ',
          style: TextStyle(
            color: labelColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFamily: AppFonts.body,
            backgroundColor: boxColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final double dy = rect.top - tp.height < 0 ? rect.top : rect.top - tp.height;
      tp.paint(canvas, Offset(rect.left + 6, dy));
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter oldDelegate) => oldDelegate.detections != detections;
}
