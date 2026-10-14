import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';

// ======================= SETTINGS (tukar kat sini je) =======================
const String kModelAsset = 'assets/models/yolov8n.tflite';
const String kLabelsAsset = 'assets/labels/campus_labels.txt';

const double kConfThreshold = 0.30; // naikkan (0.35/0.40) kalau masih banyak false positive
const double kLowThreshold = 0.15; // untuk prompt "sila dekatkan kamera"
const double kIouThreshold = 0.45;
const int kMaxDetections = 3; // paling banyak berapa objek dilapor serentak
const int kNumThreads = 4;
const int kSmoothWindow = 5; // label mesti muncul...
const int kSmoothMinAgreement = 2; // ...sekurang-kurangnya 2 dari 5 frame terakhir

// true  = hanya objek kampus dalam senarai kAllowedCoco (kurangkan false positive)
// false = semua 80 kelas COCO (guna untuk test dengan kucing, mouse, dll)
const bool kUseWhitelist = true;

// true  = hantar input sebagai bytes (LAJU).
// Kalau keluar error "Input error" masa run, tukar jadi false.
const bool kFastInput = true;

// Objek COCO yang relevan untuk kampus -> nama paparan
const Map<String, String> kAllowedCoco = {
  'person': 'PERSON',
  'bicycle': 'BICYCLE',
  'motorcycle': 'MOTORCYCLE',
  'car': 'CAR',
  'bench': 'BENCH',
  'chair': 'CHAIR',
  'couch': 'COUCH',
  'potted plant': 'PLANT',
  'dining table': 'TABLE',
  'refrigerator': 'REFRIGERATOR',
  'tv': 'TV',
  'laptop': 'LAPTOP',
  'backpack': 'BACKPACK',
  'suitcase': 'SUITCASE',
};

const List<String> _kCocoLabels = [
  'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train', 'truck', 'boat', 'traffic light',
  'fire hydrant', 'stop sign', 'parking meter', 'bench', 'bird', 'cat', 'dog', 'horse', 'sheep', 'cow',
  'elephant', 'bear', 'zebra', 'giraffe', 'backpack', 'umbrella', 'handbag', 'tie', 'suitcase', 'frisbee',
  'skis', 'snowboard', 'sports ball', 'kite', 'baseball bat', 'baseball glove', 'skateboard', 'surfboard',
  'tennis racket', 'bottle', 'wine glass', 'cup', 'fork', 'knife', 'spoon', 'bowl', 'banana', 'apple',
  'sandwich', 'orange', 'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake', 'chair', 'couch',
  'potted plant', 'bed', 'dining table', 'toilet', 'tv', 'laptop', 'mouse', 'remote', 'keyboard', 'cell phone',
  'microwave', 'oven', 'toaster', 'sink', 'refrigerator', 'book', 'clock', 'vase', 'scissors', 'teddy bear',
  'hair drier', 'toothbrush'
];

// ============================== DATA CLASSES ==============================
class Detection {
  final String label;
  final double confidence;

  /// Koordinat 0..1 relatif kepada frame yang dah tegak (upright)
  final double left, top, right, bottom;

  const Detection({
    required this.label,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  String get position {
    final double cx = (left + right) / 2;
    if (cx < 0.33) return 'kiri';
    if (cx < 0.66) return 'tengah';
    return 'kanan';
  }
}

class DetectionResult {
  final List<Detection> detections;
  final int latencyMs;
  final bool tooFar;

  const DetectionResult({
    required this.detections,
    required this.latencyMs,
    required this.tooFar,
  });

  const DetectionResult.empty()
      : detections = const [],
        latencyMs = 0,
        tooFar = false;
}

// ================================ SERVICE ================================
class TFLiteService {
  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  List<String> _labels = [];
  bool _isModelLoaded = false;

  List<int> _inputShape = [];
  List<int> _outputShape = [];
  int _inputSize = 256;
  bool _isNCHW = false;
  bool _channelsFirst = true; // output [1, 84, N] (true) atau [1, N, 84] (false)
  int _numClasses = 80;
  int _anchors = 1344;

  List<List<List<double>>>? _output; // dipakai semula setiap frame
  List<bool> _allowed = [];

  bool? _coordsNormalized; // dikesan automatik

  final List<Set<String>> _history = [];
  final List<bool> _nearMissHistory = [];

  bool get isModelLoaded => _isModelLoaded;

  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions()..threads = kNumThreads;
      _interpreter = await Interpreter.fromAsset(kModelAsset, options: options);
      _interpreter!.allocateTensors();

      _inputShape = _interpreter!.getInputTensor(0).shape;
      _outputShape = _interpreter!.getOutputTensor(0).shape;
      debugPrint('📐 Shape Input Tensor: $_inputShape');
      debugPrint('📐 Shape Output Tensor: $_outputShape');

      _isNCHW = _inputShape.length == 4 && _inputShape[1] == 3;
      _inputSize = _isNCHW ? _inputShape[2] : _inputShape[1];

      // output: [1, 4+kelas, anchors] atau [1, anchors, 4+kelas]
      _channelsFirst = _outputShape[1] < _outputShape[2];
      final int channels = _channelsFirst ? _outputShape[1] : _outputShape[2];
      _anchors = _channelsFirst ? _outputShape[2] : _outputShape[1];
      _numClasses = channels - 4;

      _output = List.generate(
        _outputShape[0],
        (_) => List.generate(_outputShape[1], (_) => List.filled(_outputShape[2], 0.0)),
      );

      try {
        final labelData = await rootBundle.loadString(kLabelsAsset);
        _labels = labelData.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      } catch (_) {
        _labels = [];
      }

      // senarai kelas yang dibenarkan
      _allowed = List.generate(_numClasses, (i) {
        if (_numClasses == 80 && kUseWhitelist) {
          return kAllowedCoco.containsKey(_kCocoLabels[i]);
        }
        return true;
      });

      _isolateInterpreter = IsolateInterpreter(address: _interpreter!.address);

      _isModelLoaded = true;
      debugPrint('✅ TFLite Model Loaded! kelas=$_numClasses, anchors=$_anchors, '
          'input=$_inputSize, channelsFirst=$_channelsFirst');
    } catch (e) {
      debugPrint('❌ Ralat memuatkan model: $e');
      _isModelLoaded = false;
    }
  }

  String _labelFor(int id) {
    if (_numClasses == 80) {
      final String name = _kCocoLabels[id];
      return kAllowedCoco[name] ?? name.toUpperCase();
    }
    if (id >= 0 && id < _labels.length) return _labels[id].toUpperCase();
    return 'CAMPUS OBJECT';
  }

  /// [rotationDegrees] = camera.sensorOrientation (biasanya 90 untuk kamera belakang)
  Future<DetectionResult> processCameraFrame(CameraImage image, int rotationDegrees) async {
    final output = _output;
    final iso = _isolateInterpreter;
    if (!_isModelLoaded || iso == null || output == null) {
      return const DetectionResult.empty();
    }

    final stopwatch = Stopwatch()..start();

    try {
      // 1) preprocess: putar frame supaya tegak + letterbox ke saiz model
      final prep = _preprocess(image, rotationDegrees);
      final Object input =
          kFastInput ? prep.buffer.buffer.asUint8List() : prep.buffer.reshape(_inputShape);

      // 2) inference (dalam isolate)
      await iso.run(input, output);

      // 3) baca output
      final bool cf = _channelsFirst;
      final List<List<double>> out = output[0];

      final List<_Raw> raws = [];
      bool nearMiss = false;

      for (int a = 0; a < _anchors; a++) {
        double best = 0.0;
        int bestId = -1;
        // cari kelas terbaik dalam SEMUA kelas, baru tapis dengan whitelist.
        // (Kalau tapis dulu, kucing 0.90 boleh jadi "chair 0.31" -> false positive)
        for (int c = 0; c < _numClasses; c++) {
          final double s = cf ? out[4 + c][a] : out[a][4 + c];
          if (s > best) {
            best = s;
            bestId = c;
          }
        }
        if (bestId < 0 || !_allowed[bestId]) continue;

        if (best >= kConfThreshold) {
          raws.add(_Raw(
            cf ? out[0][a] : out[a][0],
            cf ? out[1][a] : out[a][1],
            cf ? out[2][a] : out[a][2],
            cf ? out[3][a] : out[a][3],
            best,
            bestId,
          ));
        } else if (best >= kLowThreshold) {
          nearMiss = true;
        }
      }

      // koordinat model: 0..1 (normalized) atau pixel? Kesan sekali je.
      if (_coordsNormalized == null && raws.isNotEmpty) {
        double maxV = 0.0;
        for (final r in raws) {
          maxV = math.max(maxV, math.max(r.cx, r.cy));
        }
        _coordsNormalized = maxV <= 1.5;
        debugPrint('📐 Koordinat model: ${_coordsNormalized! ? "normalized 0-1" : "pixel"}');
      }
      final double mul = (_coordsNormalized ?? false) ? _inputSize.toDouble() : 1.0;

      final List<_Box> boxes = [
        for (final r in raws)
          _Box((r.cx - r.w / 2) * mul, (r.cy - r.h / 2) * mul, (r.cx + r.w / 2) * mul,
              (r.cy + r.h / 2) * mul, r.score, r.classId)
      ];

      final List<_Box> kept = _nms(boxes, kIouThreshold);
      final List<_Box> top = kept.length > kMaxDetections ? kept.sublist(0, kMaxDetections) : kept;

      // 4) smoothing: label mesti stabil beberapa frame
      final Set<String> labelsNow = {for (final b in top) _labelFor(b.classId)};
      _history.add(labelsNow);
      if (_history.length > kSmoothWindow) _history.removeAt(0);

      bool confirmed(String l) =>
          _history.where((s) => s.contains(l)).length >= kSmoothMinAgreement;

      double nx(double x) =>
          ((x - prep.padX) / prep.scale / prep.rotW).clamp(0.0, 1.0).toDouble();
      double ny(double y) =>
          ((y - prep.padY) / prep.scale / prep.rotH).clamp(0.0, 1.0).toDouble();

      final List<Detection> detections = [];
      for (final b in top) {
        final String label = _labelFor(b.classId);
        if (!confirmed(label)) continue;
        detections.add(Detection(
          label: label,
          confidence: b.score,
          left: nx(b.x1),
          top: ny(b.y1),
          right: nx(b.x2),
          bottom: ny(b.y2),
        ));
      }

      // 5) "sila dekatkan": ada tanda samar-samar tapi tiada objek, berulang beberapa frame
      _nearMissHistory.add(top.isEmpty && nearMiss);
      if (_nearMissHistory.length > kSmoothWindow) _nearMissHistory.removeAt(0);
      final bool tooFar = detections.isEmpty && _nearMissHistory.where((e) => e).length >= 3;

      stopwatch.stop();
      return DetectionResult(
        detections: detections,
        latencyMs: stopwatch.elapsedMilliseconds,
        tooFar: tooFar,
      );
    } catch (e) {
      debugPrint('Ralat Pemprosesan Frame: $e');
      stopwatch.stop();
      return DetectionResult(
        detections: const [],
        latencyMs: stopwatch.elapsedMilliseconds,
        tooFar: false,
      );
    }
  }

  // ------------------------------ PREPROCESS ------------------------------
  _Prepared _preprocess(CameraImage image, int rotationDegrees) {
    final int srcW = image.width;
    final int srcH = image.height;
    final int rot = ((rotationDegrees % 360) + 360) % 360;
    final bool swap = rot == 90 || rot == 270;

    // saiz frame selepas diputar (frame tegak)
    final int rotW = swap ? srcH : srcW;
    final int rotH = swap ? srcW : srcH;
    final int S = _inputSize;

    final double scale = math.min(S / rotW, S / rotH);
    final int newW = (rotW * scale).round();
    final int newH = (rotH * scale).round();
    final int padX = (S - newW) ~/ 2;
    final int padY = (S - newH) ~/ 2;

    final Uint8List yPlane = image.planes[0].bytes;
    final Uint8List uPlane = image.planes.length > 1 ? image.planes[1].bytes : yPlane;
    final Uint8List vPlane = image.planes.length > 2 ? image.planes[2].bytes : yPlane;
    final int yRowStride = image.planes[0].bytesPerRow;
    final int uvRowStride = image.planes.length > 1 ? image.planes[1].bytesPerRow : yRowStride;
    final int uvPixelStride =
        image.planes.length > 1 ? (image.planes[1].bytesPerPixel ?? 1) : 1;
    final int yLen = yPlane.length;
    final int uLen = uPlane.length;
    final int vLen = vPlane.length;

    final Float32List buf = Float32List(S * S * 3);
    buf.fillRange(0, buf.length, 114 / 255.0); // warna padding letterbox

    const double inv255 = 1.0 / 255.0;
    final int plane = S * S;

    for (int y = padY; y < padY + newH; y++) {
      final int ry = ((y - padY) * rotH) ~/ newH;
      for (int x = padX; x < padX + newW; x++) {
        final int rx = ((x - padX) * rotW) ~/ newW;

        // (rx, ry) dalam frame tegak -> (sx, sy) dalam frame asal kamera
        final int sx, sy;
        if (rot == 90) {
          sx = ry;
          sy = srcH - 1 - rx;
        } else if (rot == 270) {
          sx = srcW - 1 - ry;
          sy = rx;
        } else if (rot == 180) {
          sx = srcW - 1 - rx;
          sy = srcH - 1 - ry;
        } else {
          sx = rx;
          sy = ry;
        }

        final int yIdx = sy * yRowStride + sx;
        final int uvIdx = (sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride;

        final int yp = yIdx < yLen ? yPlane[yIdx] : 0;
        final int up = (uvIdx < uLen ? uPlane[uvIdx] : 128) - 128;
        final int vp = (uvIdx < vLen ? vPlane[uvIdx] : 128) - 128;

        final double r = _c01((yp + 1.402 * vp) * inv255);
        final double g = _c01((yp - 0.344136 * up - 0.714136 * vp) * inv255);
        final double b = _c01((yp + 1.772 * up) * inv255);

        if (_isNCHW) {
          final int p = y * S + x;
          buf[p] = r;
          buf[plane + p] = g;
          buf[2 * plane + p] = b;
        } else {
          final int base = (y * S + x) * 3;
          buf[base] = r;
          buf[base + 1] = g;
          buf[base + 2] = b;
        }
      }
    }

    return _Prepared(buf, scale, padX, padY, rotW, rotH);
  }

  // ---------------------------------- NMS ----------------------------------
  List<_Box> _nms(List<_Box> boxes, double iouThreshold) {
    boxes.sort((a, b) => b.score.compareTo(a.score));
    final List<_Box> keep = [];
    while (boxes.isNotEmpty) {
      final current = boxes.removeAt(0);
      keep.add(current);
      boxes.removeWhere((b) => b.classId == current.classId && _iou(current, b) > iouThreshold);
    }
    return keep;
  }

  double _iou(_Box a, _Box b) {
    final double ix1 = math.max(a.x1, b.x1);
    final double iy1 = math.max(a.y1, b.y1);
    final double ix2 = math.min(a.x2, b.x2);
    final double iy2 = math.min(a.y2, b.y2);
    final double inter = math.max(0.0, ix2 - ix1) * math.max(0.0, iy2 - iy1);
    final double areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
    final double areaB = (b.x2 - b.x1) * (b.y2 - b.y1);
    final double union = areaA + areaB - inter;
    return union <= 0 ? 0.0 : inter / union;
  }

  void dispose() {
    _isolateInterpreter?.close();
    _interpreter?.close();
    _isModelLoaded = false;
  }
}

double _c01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);

class _Prepared {
  final Float32List buffer;
  final double scale;
  final int padX, padY, rotW, rotH;
  _Prepared(this.buffer, this.scale, this.padX, this.padY, this.rotW, this.rotH);
}

class _Raw {
  final double cx, cy, w, h, score;
  final int classId;
  _Raw(this.cx, this.cy, this.w, this.h, this.score, this.classId);
}

class _Box {
  final double x1, y1, x2, y2, score;
  final int classId;
  _Box(this.x1, this.y1, this.x2, this.y2, this.score, this.classId);
}