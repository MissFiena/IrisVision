import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/tflite_service.dart';
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
        throw 'Model AI gagal dimuatkan.';
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw 'Tiada kamera dijumpai pada peranti ini.';
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
      _safeSetState(() => _errorMessage = 'Gagal memulakan kamera.\n$e');
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
    } catch (e) {
      debugPrint('❌ Ralat kamera: $e');
      if (_cameraController == controller) _cameraController = null;
      try {
        await controller.dispose();
      } catch (_) {}
      _safeSetState(() {
        _isCameraInitialized = false;
        _errorMessage = 'Kamera tidak dapat dibuka. Mungkin sedang digunakan oleh aplikasi lain.\n$e';
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
      if (!_disposed) _result.value = result;
    } finally {
      _isProcessingFrame = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera(); // stop stream dulu, kemudian dispose kamera
    _tfLiteService.dispose(); // tunggu frame semasa siap sebelum tutup model
    _result.dispose();
    super.dispose();
  }

  // ============================== UI ==============================
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

  String _name(String label) {
    final bm = _bm[label];
    if (bm != null) return bm;
    final l = label.toLowerCase();
    return l.isEmpty ? l : l[0].toUpperCase() + l.substring(1);
  }

  /// Ayat yang dipaparkan (dan nanti dibaca oleh TTS).
  String _sentence(DetectionResult r) {
    if (r.detections.isNotEmpty) {
      final parts = r.detections.map((d) => '${_name(d.label)} di ${d.position}').toList();
      final s = parts.join(', ');
      return s[0].toUpperCase() + s.substring(1);
    }
    if (r.tooFar) return 'Ada objek tetapi tidak jelas. Sila dekatkan kamera.';
    return 'Halakan kamera ke hadapan...';
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_permissionDenied) {
      body = _buildMessage(
        icon: Icons.videocam_off_outlined,
        text: 'Kebenaran kamera diperlukan untuk mengesan objek.',
        action: 'Buka tetapan',
        onAction: () => openAppSettings(),
      );
    } else if (_errorMessage != null) {
      body = _buildMessage(
        icon: Icons.error_outline,
        text: _errorMessage!,
        action: 'Cuba lagi',
        onAction: (_starting || _initializing) ? null : _initializeSystem,
      );
    } else if (_isCameraInitialized && _cameraController != null) {
      body = _buildCameraView(_cameraController!);
    } else {
      body = _buildMessage(icon: null, text: 'Memuatkan kamera dan model AI...');
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
            const TopBar(title: Headline('Kesan Objek', size: 24)),
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

    return Stack(
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
                ValueListenableBuilder<DetectionResult>(
                  valueListenable: _result,
                  builder: (context, r, _) {
                    final ok = r.latencyMs <= 1500;
                    return Semantics(
                      label: 'Kelajuan ${r.latencyMs} milisaat',
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
              left: _firstAt(r, 'kiri'),
              center: _firstAt(r, 'tengah'),
              right: _firstAt(r, 'kanan'),
            ),
          ),
        ),
      ],
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
  final String? left, center, right;
  const _ResultPanel({required this.sentence, this.left, this.center, this.right});

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
            Text('Di hadapan anda', style: TextStyle(fontSize: 15, color: p.textSecondary)),
            const SizedBox(height: 2),
            // liveRegion: TalkBack baca bila ayat berubah
            Semantics(
              liveRegion: true,
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
                  cell('KIRI', left),
                  const SizedBox(width: 8),
                  cell('TENGAH', center),
                  const SizedBox(width: 8),
                  cell('KANAN', right),
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
