import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

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

// Kalau worker tak balas dalam masa ni, frame tu dianggap gagal (elak app tergantung)
const Duration kFrameTimeout = Duration(seconds: 3);

// true  = hanya objek kampus dalam senarai kAllowedCoco (kurangkan false positive)
// false = semua 80 kelas COCO (guna untuk test dengan kucing, mouse, dll)
const bool kUseWhitelist = false;

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
/// Semua kerja berat (convert YUV->RGB, inference, decode, NMS) jalan dalam
/// SATU worker isolate yang hidup sepanjang app. UI thread cuma hantar frame
/// dan terima hasil -> preview kamera tak tersekat.
class TFLiteService {
  Interpreter? _interpreter;
  Isolate? _worker;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  StreamSubscription<dynamic>? _sub;
  Completer<_FrameOutput>? _pending;

  List<String> _labels = [];
  int _numClasses = 80;

  bool _isModelLoaded = false;
  bool _busy = false;
  bool _closing = false;

  final List<Set<String>> _history = [];
  final List<bool> _nearMissHistory = [];

  bool get isModelLoaded => _isModelLoaded;

  Future<void> loadModel() async {
    if (_isModelLoaded) return;
    try {
      final options = InterpreterOptions()..threads = kNumThreads;
      final interpreter = await Interpreter.fromAsset(kModelAsset, options: options);
      interpreter.allocateTensors();
      _interpreter = interpreter;

      final List<int> inputShape = interpreter.getInputTensor(0).shape;
      final List<int> outputShape = interpreter.getOutputTensor(0).shape;
      debugPrint('📐 Shape Input Tensor: $inputShape');
      debugPrint('📐 Shape Output Tensor: $outputShape');

      final bool isNCHW = inputShape.length == 4 && inputShape[1] == 3;
      final int inputSize = isNCHW ? inputShape[2] : inputShape[1];

      // output: [1, 4+kelas, anchors] atau [1, anchors, 4+kelas]
      final bool channelsFirst = outputShape[1] < outputShape[2];
      final int channels = channelsFirst ? outputShape[1] : outputShape[2];
      final int anchors = channelsFirst ? outputShape[2] : outputShape[1];
      _numClasses = channels - 4;

      try {
        final labelData = await rootBundle.loadString(kLabelsAsset);
        _labels = labelData.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      } catch (_) {
        _labels = [];
      }

      // senarai kelas yang dibenarkan
      final List<bool> allowed = List.generate(_numClasses, (i) {
        if (_numClasses == 80 && kUseWhitelist) {
          return kAllowedCoco.containsKey(_kCocoLabels[i]);
        }
        return true;
      });

      // ---- start worker isolate ----
      final fromWorker = ReceivePort();
      _fromWorker = fromWorker;
      final ready = Completer<SendPort>();

      _sub = fromWorker.listen((msg) {
        if (msg is SendPort) {
          if (!ready.isCompleted) ready.complete(msg);
        } else if (msg is _FrameOutput) {
          final p = _pending;
          _pending = null;
          if (p != null && !p.isCompleted) p.complete(msg);
        }
      });

      _worker = await Isolate.spawn(
        _workerMain,
        _WorkerConfig(
          replyPort: fromWorker.sendPort,
          interpreterAddress: interpreter.address,
          inputShape: inputShape,
          outputShape: outputShape,
          inputSize: inputSize,
          isNCHW: isNCHW,
          channelsFirst: channelsFirst,
          numClasses: _numClasses,
          anchors: anchors,
          allowed: allowed,
        ),
      );
      _toWorker = await ready.future.timeout(const Duration(seconds: 10));

      _isModelLoaded = true;
      debugPrint('✅ TFLite Model Loaded! kelas=$_numClasses, anchors=$anchors, '
          'input=$inputSize, channelsFirst=$channelsFirst');
    } catch (e) {
      debugPrint('❌ Ralat memuatkan model: $e');
      _shutdown();
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
    final port = _toWorker;
    if (!_isModelLoaded || port == null || _busy || _closing) {
      return const DetectionResult.empty();
    }

    _busy = true;
    final stopwatch = Stopwatch()..start();

    try {
      // 1) hantar frame ke worker (preprocess + inference + NMS semua kat sana)
      final pending = Completer<_FrameOutput>();
      _pending = pending;
      port.send(_FrameInput.fromCamera(image, rotationDegrees));

      final _FrameOutput out = await pending.future.timeout(kFrameTimeout);
      if (out.error != null) {
        debugPrint('Ralat Pemprosesan Frame (worker): ${out.error}');
        return DetectionResult(
          detections: const [],
          latencyMs: stopwatch.elapsedMilliseconds,
          tooFar: false,
        );
      }

      // 2) smoothing: label mesti stabil beberapa frame
      final Set<String> labelsNow = {for (final b in out.boxes) _labelFor(b.classId)};
      _history.add(labelsNow);
      if (_history.length > kSmoothWindow) _history.removeAt(0);

      bool confirmed(String l) =>
          _history.where((s) => s.contains(l)).length >= kSmoothMinAgreement;

      final List<Detection> detections = [];
      for (final b in out.boxes) {
        final String label = _labelFor(b.classId);
        if (!confirmed(label)) continue;
        detections.add(Detection(
          label: label,
          confidence: b.score,
          left: b.left,
          top: b.top,
          right: b.right,
          bottom: b.bottom,
        ));
      }

      // 3) "sila dekatkan": ada tanda samar-samar tapi tiada objek, berulang beberapa frame
      _nearMissHistory.add(out.boxes.isEmpty && out.nearMiss);
      if (_nearMissHistory.length > kSmoothWindow) _nearMissHistory.removeAt(0);
      final bool tooFar = detections.isEmpty && _nearMissHistory.where((e) => e).length >= 3;

      return DetectionResult(
        detections: detections,
        latencyMs: stopwatch.elapsedMilliseconds,
        tooFar: tooFar,
      );
    } catch (e) {
      _pending = null;
      debugPrint('Ralat Pemprosesan Frame: $e');
      return DetectionResult(
        detections: const [],
        latencyMs: stopwatch.elapsedMilliseconds,
        tooFar: false,
      );
    } finally {
      stopwatch.stop();
      _busy = false;
      // kalau dispose() dipanggil masa frame tengah diproses, tutup sekarang
      if (_closing) _shutdown();
    }
  }

  /// Selamat dipanggil bila-bila masa. Kalau ada frame tengah diproses,
  /// interpreter hanya ditutup selepas frame itu siap (elak crash).
  void dispose() {
    _closing = true;
    if (!_busy) _shutdown();
  }

  void _shutdown() {
    _isModelLoaded = false;
    _toWorker = null;
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _sub?.cancel();
    _sub = null;
    _fromWorker?.close();
    _fromWorker = null;
    _interpreter?.close();
    _interpreter = null;
  }
}

// ============================ WORKER ISOLATE ============================
void _workerMain(_WorkerConfig cfg) {
  final Interpreter interpreter = Interpreter.fromAddress(cfg.interpreterAddress);

  // buffer output dipakai semula setiap frame
  final List<List<List<double>>> output = List.generate(
    cfg.outputShape[0],
    (_) => List.generate(cfg.outputShape[1], (_) => List<double>.filled(cfg.outputShape[2], 0.0)),
  );

  bool? coordsNormalized; // dikesan automatik pada frame pertama

  final ReceivePort inbox = ReceivePort();
  cfg.replyPort.send(inbox.sendPort);

  inbox.listen((msg) {
    if (msg is! _FrameInput) return;
    try {
      // 1) preprocess: putar frame supaya tegak + letterbox ke saiz model
      final prep = _preprocess(msg, cfg);
      final Object input =
          kFastInput ? prep.buffer.buffer.asUint8List() : prep.buffer.reshape(cfg.inputShape);

      // 2) inference
      interpreter.run(input, output);

      // 3) decode output
      final bool cf = cfg.channelsFirst;
      final List<List<double>> out = output[0];
      final List<_Raw> raws = [];
      bool nearMiss = false;

      for (int a = 0; a < cfg.anchors; a++) {
        double best = 0.0;
        int bestId = -1;
        // cari kelas terbaik dalam SEMUA kelas, baru tapis dengan whitelist.
        // (Kalau tapis dulu, kucing 0.90 boleh jadi "chair 0.31" -> false positive)
        for (int c = 0; c < cfg.numClasses; c++) {
          final double s = cf ? out[4 + c][a] : out[a][4 + c];
          if (s > best) {
            best = s;
            bestId = c;
          }
        }
        if (bestId < 0 || !cfg.allowed[bestId]) continue;

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
      if (coordsNormalized == null && raws.isNotEmpty) {
        double maxV = 0.0;
        for (final r in raws) {
          maxV = math.max(maxV, math.max(r.cx, r.cy));
        }
        coordsNormalized = maxV <= 1.5;
      }
      final double mul = (coordsNormalized ?? false) ? cfg.inputSize.toDouble() : 1.0;

      final List<_Box> boxes = [
        for (final r in raws)
          _Box((r.cx - r.w / 2) * mul, (r.cy - r.h / 2) * mul, (r.cx + r.w / 2) * mul,
              (r.cy + r.h / 2) * mul, r.score, r.classId)
      ];

      final List<_Box> kept = _nms(boxes, kIouThreshold);
      final List<_Box> top = kept.length > kMaxDetections ? kept.sublist(0, kMaxDetections) : kept;

      // 4) tukar ke koordinat 0..1 relatif kepada frame tegak
      double nx(double x) =>
          ((x - prep.padX) / prep.scale / prep.rotW).clamp(0.0, 1.0).toDouble();
      double ny(double y) =>
          ((y - prep.padY) / prep.scale / prep.rotH).clamp(0.0, 1.0).toDouble();

      cfg.replyPort.send(_FrameOutput(
        boxes: [
          for (final b in top)
            _OutBox(nx(b.x1), ny(b.y1), nx(b.x2), ny(b.y2), b.score, b.classId),
        ],
        nearMiss: nearMiss,
      ));
    } catch (e) {
      cfg.replyPort.send(_FrameOutput.failed(e.toString()));
    }
  });
}

// ------------------------------ PREPROCESS ------------------------------
_Prepared _preprocess(_FrameInput f, _WorkerConfig cfg) {
  final int srcW = f.width;
  final int srcH = f.height;
  final int rot = ((f.rotation % 360) + 360) % 360;
  final bool swap = rot == 90 || rot == 270;

  // saiz frame selepas diputar (frame tegak)
  final int rotW = swap ? srcH : srcW;
  final int rotH = swap ? srcW : srcH;
  final int S = cfg.inputSize;

  final double scale = math.min(S / rotW, S / rotH);
  final int newW = (rotW * scale).round();
  final int newH = (rotH * scale).round();
  final int padX = (S - newW) ~/ 2;
  final int padY = (S - newH) ~/ 2;

  final Uint8List yPlane = f.yPlane;
  final Uint8List uPlane = f.uPlane;
  final Uint8List vPlane = f.vPlane;
  final int yRowStride = f.yRowStride;
  final int uvRowStride = f.uvRowStride;
  final int uvPixelStride = f.uvPixelStride;
  final int yLen = yPlane.length;
  final int uLen = uPlane.length;
  final int vLen = vPlane.length;

  final Float32List buf = Float32List(S * S * 3);
  buf.fillRange(0, buf.length, 114 / 255.0); // warna padding letterbox

  const double inv255 = 1.0 / 255.0;
  final int plane = S * S;
  final bool nchw = cfg.isNCHW;

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

      if (nchw) {
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

double _c01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);

// ============================ MESSAGE CLASSES ============================
class _WorkerConfig {
  final SendPort replyPort;
  final int interpreterAddress;
  final List<int> inputShape;
  final List<int> outputShape;
  final int inputSize;
  final bool isNCHW;
  final bool channelsFirst;
  final int numClasses;
  final int anchors;
  final List<bool> allowed;

  _WorkerConfig({
    required this.replyPort,
    required this.interpreterAddress,
    required this.inputShape,
    required this.outputShape,
    required this.inputSize,
    required this.isNCHW,
    required this.channelsFirst,
    required this.numClasses,
    required this.anchors,
    required this.allowed,
  });
}

/// Data mentah satu frame kamera (hanya benda yang boleh dihantar ke isolate)
class _FrameInput {
  final Uint8List yPlane, uPlane, vPlane;
  final int yRowStride, uvRowStride, uvPixelStride;
  final int width, height, rotation;

  _FrameInput({
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.width,
    required this.height,
    required this.rotation,
  });

  factory _FrameInput.fromCamera(CameraImage image, int rotation) {
    final planes = image.planes;
    final Uint8List y = planes[0].bytes;
    final bool hasUV = planes.length > 2;
    return _FrameInput(
      yPlane: y,
      uPlane: hasUV ? planes[1].bytes : y,
      vPlane: hasUV ? planes[2].bytes : y,
      yRowStride: planes[0].bytesPerRow,
      uvRowStride: hasUV ? planes[1].bytesPerRow : planes[0].bytesPerRow,
      uvPixelStride: hasUV ? (planes[1].bytesPerPixel ?? 1) : 1,
      width: image.width,
      height: image.height,
      rotation: rotation,
    );
  }
}

class _FrameOutput {
  final List<_OutBox> boxes;
  final bool nearMiss;
  final String? error;

  _FrameOutput({required this.boxes, required this.nearMiss}) : error = null;
  _FrameOutput.failed(this.error)
      : boxes = const [],
        nearMiss = false;
}

/// Kotak akhir, koordinat 0..1 relatif kepada frame tegak
class _OutBox {
  final double left, top, right, bottom, score;
  final int classId;
  _OutBox(this.left, this.top, this.right, this.bottom, this.score, this.classId);
}

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