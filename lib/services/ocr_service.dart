import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// Saiz kotak kuning (pecahan daripada preview kamera). Dikongsi oleh
/// skrin kamera (untuk lukis) dan OCR (untuk potong gambar), supaya
/// apa yang dibaca = apa yang ada dalam kotak.
const double kFrameWidth = 0.86;
const double kFrameHeight = 0.62;

/// Satu perenggan teks yang dikesan.
class OcrBlock {
  final String text;
  const OcrBlock(this.text);
}

/// Keputusan satu imbasan.
class OcrResult {
  final List<OcrBlock> blocks;
  final int latencyMs;
  const OcrResult({required this.blocks, required this.latencyMs});

  bool get isEmpty => blocks.isEmpty;
  String get fullText => blocks.map((b) => b.text).join('\n\n');
  int get wordCount =>
      blocks.fold(0, (n, b) => n + b.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length);
}

/// OCR dalam telefon guna Google ML Kit (skrip Latin: BM + English).
/// Tiada internet. Gambar dipadam sejurus selepas diproses (janji privasi).
///
/// Langkah:
///  1. Potong gambar ikut kotak kuning (teks di luar kotak diabaikan).
///  2. ML Kit baca teks.
///  3. Susun BARIS ikut cara orang membaca (atas -> bawah, kiri -> kanan),
///     kemudian cantum baris yang rapat jadi satu perenggan.
class OcrService {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// [previewAspect] = lebar / tinggi preview kamera (mod portrait).
  /// Fail gambar asal DAN yang dipotong DIPADAM selepas itu.
  Future<OcrResult> readImage(String imagePath, {required double previewAspect}) async {
    final sw = Stopwatch()..start();
    String? cropped;
    try {
      cropped = await compute(_cropToFrame, (imagePath, previewAspect));
      final input = InputImage.fromFilePath(cropped ?? imagePath);
      final recognized = await _recognizer.processImage(input);

      final paragraphs = _toParagraphs(recognized);
      final blocks = <OcrBlock>[];
      for (final para in paragraphs) {
        final clean = _clean(para);
        if (clean.length >= 2) blocks.add(OcrBlock(clean));
      }

      sw.stop();
      debugPrint('📝 OCR: ${blocks.length} perenggan, ${sw.elapsedMilliseconds} ms, potong=${cropped != null}');
      return OcrResult(blocks: blocks, latencyMs: sw.elapsedMilliseconds);
    } finally {
      _deleteQuietly(imagePath);
      if (cropped != null) _deleteQuietly(cropped);
    }
  }

  // ------------------------- susunan bacaan -------------------------
  List<String> _toParagraphs(RecognizedText recognized) {
    final lines = <TextLine>[
      for (final b in recognized.blocks)
        for (final l in b.lines)
          if (l.text.trim().isNotEmpty) l,
    ];
    if (lines.isEmpty) return [];

    // tinggi baris biasa (median) = ukuran untuk "dekat" / "jauh"
    final heights = lines.map((l) => l.boundingBox.height).toList()..sort();
    final lineH = max(1.0, heights[heights.length ~/ 2]);

    // 1. kumpul baris yang sama ketinggian jadi satu "row"
    lines.sort((a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));
    final rows = <List<TextLine>>[];
    for (final l in lines) {
      final last = rows.isEmpty ? null : rows.last;
      if (last != null && (l.boundingBox.center.dy - last.first.boundingBox.center.dy).abs() < lineH * 0.5) {
        last.add(l);
      } else {
        rows.add([l]);
      }
    }
    // 2. dalam setiap row: kiri -> kanan
    for (final r in rows) {
      r.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
    }

    // 3. cantum row yang rapat jadi perenggan
    final paragraphs = <String>[];
    var current = StringBuffer();
    Rect? prev;
    for (final r in rows) {
      final box = r.map((l) => l.boundingBox).reduce((a, b) => a.expandToInclude(b));
      final text = r.map((l) => l.text.trim()).join(' ');
      final sameParagraph = prev != null &&
          box.top - prev.bottom < lineH * 0.9 && // jarak antara baris kecil
          box.left < prev.right &&
          box.right > prev.left; // bertindih secara mendatar
      if (prev != null && !sameParagraph) {
        paragraphs.add(current.toString());
        current = StringBuffer();
      }
      if (current.isNotEmpty) {
        // "pela-" + "jar" -> "pelajar"
        final s = current.toString();
        if (s.endsWith('-')) {
          current = StringBuffer(s.substring(0, s.length - 1));
        } else {
          current.write(' ');
        }
      }
      current.write(text);
      prev = box;
    }
    if (current.isNotEmpty) paragraphs.add(current.toString());
    return paragraphs;
  }

  /// Buang ruang berganda & sempang terapung ("pela- jar" -> "pelajar").
  String _clean(String s) => s
      .replaceAllMapped(RegExp(r'(\w)- (\w)'), (m) => '${m[1]}${m[2]}')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void _deleteQuietly(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (e) {
      debugPrint('⚠️ Gagal padam gambar sementara: $e');
    }
  }

  Future<void> dispose() => _recognizer.close();
}

/// Dijalankan dalam isolate lain (tak lag UI).
/// Pulangkan laluan gambar yang dipotong, atau null jika gagal (guna gambar penuh).
String? _cropToFrame((String, double) args) {
  final (path, previewAspect) = args;
  try {
    final decoded = img.decodeJpg(File(path).readAsBytesSync());
    if (decoded == null) return null;
    final photo = img.bakeOrientation(decoded); // pusing ikut EXIF -> tegak
    final w = photo.width.toDouble();
    final h = photo.height.toDouble();

    // Kawasan gambar yang kelihatan dalam preview (nisbah gambar & preview
    // mungkin berbeza; preview = potongan tengah).
    double visW = w, visH = h;
    if (w / h > previewAspect) {
      visW = h * previewAspect;
    } else {
      visH = w / previewAspect;
    }
    // kotak kuning + 4% ruang tambahan supaya huruf di tepi tak terpotong
    final fw = min(visW, visW * (kFrameWidth + 0.04));
    final fh = min(visH, visH * (kFrameHeight + 0.04));
    final x = ((w - fw) / 2).round();
    final y = ((h - fh) / 2).round();

    var out = img.copyCrop(photo, x: x, y: y, width: fw.round(), height: fh.round());
    if (out.width > 1600) out = img.copyResize(out, width: 1600); // cukup untuk OCR, lebih pantas
    final outPath = path.replaceFirst(RegExp(r'\.(jpe?g)$', caseSensitive: false), '_frame.jpg');
    final target = outPath == path ? '${path}_frame.jpg' : outPath;
    File(target).writeAsBytesSync(img.encodeJpg(out, quality: 92));
    return target;
  } catch (_) {
    return null;
  }
}
