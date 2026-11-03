import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/lang.dart';
import '../../services/ocr_service.dart';
import '../../services/tts_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'scan_result_view.dart';

/// C6 · Imbas Teks (mod tepat: ketik untuk tangkap gambar).
///
/// Untuk pengguna buta: KETIK DI MANA-MANA pada skrin untuk ambil gambar.
/// Butang besar di bawah juga buat benda yang sama.
class ScanTextView extends StatefulWidget {
  const ScanTextView({super.key});

  @override
  State<ScanTextView> createState() => _ScanTextViewState();
}

class _ScanTextViewState extends State<ScanTextView> with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  final OcrService _ocr = OcrService();
  final TtsService _tts = TtsService.instance;

  bool _ready = false;
  bool _busy = false;
  bool _torchOn = false;
  bool _permissionDenied = false;
  bool _initializing = false;
  bool _disposed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_disposed) setState(fn);
  }

  // ============================ INIT ============================
  Future<void> _init() async {
    if (_initializing || _disposed) return;
    _initializing = true;
    _safeSetState(() {
      _error = null;
      _permissionDenied = false;
    });
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        _safeSetState(() => _permissionDenied = true);
        return;
      }
      final cams = await availableCameras();
      if (cams.isEmpty) throw t('Tiada kamera dijumpai pada peranti ini.', 'No camera found on this device.');
      _camera = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      await _startCamera();
      _announce(); // beritahu pengguna cara guna skrin ini
    } catch (e) {
      debugPrint('❌ Ralat init imbas: $e');
      _safeSetState(() => _error = '${t('Gagal memulakan kamera.', 'Failed to start the camera.')}\n$e');
    } finally {
      _initializing = false;
    }
  }

  void _announce() {
    _tts.announce(
      'Imbas teks. Pegang telefon kira-kira sejengkal di atas kertas, kemudian ketik di mana-mana pada skrin.',
      'Scan text. Hold the phone about one hand span above the page, then tap anywhere on the screen.',
    );
  }

  Future<void> _startCamera() async {
    final cam = _camera;
    if (cam == null || _controller != null || _disposed) return;
    // resolusi tinggi = huruf lebih jelas untuk OCR
    final c = CameraController(cam, ResolutionPreset.high, enableAudio: false);
    _controller = c;
    try {
      await c.initialize();
      if (_disposed || _controller != c) {
        await c.dispose();
        return;
      }
      await c.setFlashMode(FlashMode.off);
      _torchOn = false;
      _safeSetState(() => _ready = true);
    } catch (e) {
      if (_controller == c) _controller = null;
      try {
        await c.dispose();
      } catch (_) {}
      _safeSetState(() {
        _ready = false;
        _error = '${t('Kamera tidak dapat dibuka. Mungkin sedang digunakan oleh aplikasi lain.', 'The camera could not open. Another app may be using it.')}\n$e';
      });
    }
  }

  Future<void> _stopCamera() async {
    final c = _controller;
    _controller = null;
    _safeSetState(() => _ready = false);
    if (c == null) return;
    try {
      await c.dispose();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _tts.stop();
      _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (_permissionDenied || _camera == null) {
        _init();
      } else {
        _startCamera();
      }
    }
  }

  // ============================ ACTIONS ============================
  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null || !_ready) return;
    try {
      final on = !_torchOn;
      await c.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      HapticFeedback.selectionClick();
      _safeSetState(() => _torchOn = on);
      _tts.speak(
        _tts.uiLang == TextLang.bm ? (on ? 'Lampu dihidupkan' : 'Lampu dimatikan') : (on ? 'Light on' : 'Light off'),
        lang: _tts.uiLang,
      );
    } catch (e) {
      debugPrint('⚠️ Lampu: $e');
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !_ready || _busy) return;
    _safeSetState(() => _busy = true);
    HapticFeedback.heavyImpact();
    await _tts.stop();
    final bm = _tts.uiLang == TextLang.bm;
    _tts.speak(bm ? 'Sedang membaca' : 'Reading', lang: _tts.uiLang);

    try {
      final shot = await c.takePicture();
      // hanya teks dalam kotak kuning dibaca; gambar dipadam dalam fungsi ini
      final result = await _ocr.readImage(shot.path, previewAspect: 1 / c.value.aspectRatio);
      if (_disposed || !mounted) return;

      if (result.isEmpty) {
        HapticFeedback.vibrate();
        await _tts.stop();
        _tts.speak(
          bm
              ? 'Tiada teks dalam kotak. Cuba angkat telefon sedikit, atau hidupkan lampu.'
              : 'No text in the frame. Try lifting the phone a little, or turn on the light.',
          lang: _tts.uiLang,
        );
        if (mounted) showInfo(context, bm ? 'Tiada teks dijumpai. Cuba lagi.' : 'No text found. Try again.');
        return;
      }

      // matikan lampu & kamera semasa di skrin keputusan (jimat bateri)
      await _stopCamera();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanResultView(result: result)));
      if (!_disposed) await _startCamera(); // balik ke skrin ini -> kamera hidup semula
    } catch (e) {
      debugPrint('❌ Ralat imbas: $e');
      if (mounted) showInfo(context, bm ? 'Gagal mengimbas. Sila cuba lagi.' : 'Scan failed. Please try again.');
    } finally {
      _safeSetState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _tts.stop();
    _stopCamera();
    _ocr.dispose();
    super.dispose();
  }

  // ============================== UI ==============================
  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_permissionDenied) {
      body = _message(
        icon: Icons.videocam_off_outlined,
        text: context.tr('Kebenaran kamera diperlukan untuk mengimbas teks.', 'Camera permission is needed to scan text.'),
        action: context.tr('Buka tetapan', 'Open settings'),
        onAction: () => openAppSettings(),
      );
    } else if (_error != null) {
      body = _message(icon: Icons.error_outline, text: _error!, action: context.tr('Cuba lagi', 'Try again'), onAction: _init);
    } else if (_ready && _controller != null) {
      body = _cameraView(_controller!);
    } else {
      body = _message(text: context.tr('Memuatkan kamera...', 'Loading camera...'));
    }
    return Scaffold(body: body);
  }

  Widget _message({IconData? icon, required String text, String? action, VoidCallback? onAction}) {
    final p = context.pal;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TopBar(title: Headline(context.tr('Imbas Teks', 'Scan Text'), size: 24)),
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

  Widget _cameraView(CameraController c) {
    final p = context.pal;
    final previewAspect = 1 / c.value.aspectRatio;

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.black)),
          // Seluruh kawasan preview = satu butang besar "ambil gambar"
          Positioned.fill(
            child: Semantics(
              button: true,
              label: context.tr('Kamera. Ketik dua kali untuk ambil gambar dan baca teks',
                  'Camera. Double tap to take a photo and read the text'),
              excludeSemantics: true,
              onTap: _capture,
              child: GestureDetector(
                onTap: _capture,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: AspectRatio(
                    aspectRatio: previewAspect,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(c),
                        // bingkai panduan
                        IgnorePointer(
                          child: Center(
                            child: FractionallySizedBox(
                              widthFactor: kFrameWidth,
                              heightFactor: kFrameHeight,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: p.highlight, width: 4),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // butang atas: kembali + lampu
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const BackSquare(),
                  const Spacer(),
                  SquareIconButton(
                    icon: _torchOn ? Icons.flashlight_off : Icons.flashlight_on,
                    tooltip: _torchOn
                        ? context.tr('Matikan lampu', 'Turn off light')
                        : context.tr('Hidupkan lampu', 'Turn on light'),
                    onPressed: _toggleTorch,
                  ),
                ],
              ),
            ),
          ),
          // panel bawah
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
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
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _busy
                            ? context.tr('Sedang membaca teks...', 'Reading text...')
                            : context.tr('Letak teks dalam kotak kuning, kemudian ketik skrin',
                                'Put the text inside the yellow frame, then tap the screen'),
                        style: TextStyle(
                          fontFamily: AppFonts.heading,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    BadgeButton(
                      label: _busy ? context.tr('Sedang membaca', 'Reading') : context.tr('Ambil gambar', 'Take photo'),
                      badgeIcon: Icons.camera_alt,
                      loading: _busy,
                      onPressed: _capture,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
