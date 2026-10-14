import 'package:camera/camera.dart';
//import 'package:flutter/foundation.dart';

class CameraService {
  CameraController? _controller;
  bool _isProcessingFrame = false;

  Future<void> initializeCamera(Function(CameraImage image) onFrameCaptured) async {
    final cameras = await availableCameras();
    // Select rear-facing camera module [CR002]
    final rearCamera = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
    );

    // Medium resolution keeps memory usage strictly below 30 MB [CR003]
    _controller = CameraController(
      rearCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();

    // Stream continuous viewport image frames
    _controller!.startImageStream((CameraImage image) {
      if (!_isProcessingFrame) {
        _isProcessingFrame = true;
        
        // Pass frame array to TFLite background thread
        onFrameCaptured(image);
        
        _isProcessingFrame = false;
      }
    });
  }

  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
  }
}