import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/tflite_service.dart';

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
  String _statusText(DetectionResult r) {
    if (r.detections.isNotEmpty) {
      return r.detections
          .map((d) => '${d.label} (${d.position}, ${(d.confidence * 100).toStringAsFixed(0)}%)')
          .join('\n');
    }
    if (r.tooFar) {
      return 'Objek dikesan tetapi tidak jelas -- sila dekatkan kamera';
    }
    return 'Sila halakan kamera ke arah objek kampus (Kerusi, Meja, Sofa, Orang)...';
  }

  Color _statusColor(DetectionResult r) {
    if (r.detections.isNotEmpty) return Colors.greenAccent;
    if (r.tooFar) return Colors.amber;
    return Colors.orangeAccent;
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_permissionDenied) {
      body = _buildPermissionDenied();
    } else if (_errorMessage != null) {
      body = _buildError(_errorMessage!);
    } else if (_isCameraInitialized && _cameraController != null) {
      body = _buildCameraView(_cameraController!);
    } else {
      body = _buildLoading();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('IrisVision - Campus Object Detection'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text('Kebenaran kamera diperlukan untuk pengesanan objek.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => openAppSettings(), child: const Text('Buka Tetapan')),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_starting || _initializing) ? null : _initializeSystem,
              child: const Text('Cuba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Memuatkan Kamera & Model AI...'),
        ],
      ),
    );
  }

  Widget _buildCameraView(CameraController controller) {
    // mod portrait: nisbah preview = 1 / nisbah landscape kamera
    final double previewAspect = 1 / controller.value.aspectRatio;

    return Stack(
      children: [
        // Preview + kotak dalam widget yang SAMA saiz -> kotak sentiasa sejajar
        Positioned.fill(
          child: Center(
            child: AspectRatio(
              aspectRatio: previewAspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(controller),
                  ValueListenableBuilder<DetectionResult>(
                    valueListenable: _result,
                    builder: (context, r, _) =>
                        CustomPaint(painter: _BoxPainter(r.detections)),
                  ),
                ],
              ),
            ),
          ),
        ),

        // badge latency
        Positioned(
          top: 16,
          left: 16,
          child: ValueListenableBuilder<DetectionResult>(
            valueListenable: _result,
            builder: (context, r, _) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration:
                  BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.greenAccent, size: 10),
                      SizedBox(width: 6),
                      Text('YOLOv8 Active',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Latency: ${r.latencyMs} ms (Limit: ≤1500 ms)',
                    style: TextStyle(
                      color: r.latencyMs <= 1500 ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // status teks bawah
        Positioned(
          bottom: 32,
          left: 16,
          right: 16,
          child: ValueListenableBuilder<DetectionResult>(
            valueListenable: _result,
            builder: (context, r, _) {
              final color = _statusColor(r);
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color, width: 2),
                ),
                child: Text(
                  _statusText(r),
                  style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Lukis kotak. Koordinat detection dah 0..1 relatif kepada frame tegak,
/// jadi cuma darab dengan saiz canvas (tak perlu rotate lagi).
class _BoxPainter extends CustomPainter {
  final List<Detection> detections;
  _BoxPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    for (final d in detections) {
      final rect = Rect.fromLTRB(
        d.left * size.width,
        d.top * size.height,
        d.right * size.width,
        d.bottom * size.height,
      );
      canvas.drawRect(rect, paint);

      final tp = TextPainter(
        text: TextSpan(
          text: ' ${d.label} ${(d.confidence * 100).toStringAsFixed(0)}% ',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.greenAccent,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final double dy = rect.top - tp.height < 0 ? rect.top : rect.top - tp.height;
      tp.paint(canvas, Offset(rect.left, dy));
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter oldDelegate) => oldDelegate.detections != detections;
}