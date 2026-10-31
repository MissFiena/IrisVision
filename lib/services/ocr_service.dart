import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Satu perenggan / blok teks yang dikesan.
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
class OcrService {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Baca teks daripada fail gambar. Fail gambar DIPADAM selepas itu.
  Future<OcrResult> readImage(String imagePath) async {
    final sw = Stopwatch()..start();
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognized = await _recognizer.processImage(input);

      // Susun ikut cara orang membaca: atas -> bawah, kiri -> kanan.
      final raw = recognized.blocks.toList()
        ..sort((a, b) {
          final dy = a.boundingBox.top - b.boundingBox.top;
          // blok yang hampir sebaris (beza < 20px) disusun ikut kiri -> kanan
          if (dy.abs() < 20) return a.boundingBox.left.compareTo(b.boundingBox.left);
          return dy.sign.toInt();
        });

      final blocks = <OcrBlock>[];
      for (final b in raw) {
        // gabung baris dalam satu blok jadi satu ayat (buang pemisah baris)
        final text = b.lines.map((l) => l.text.trim()).where((t) => t.isNotEmpty).join(' ');
        final clean = _clean(text);
        if (clean.length >= 2) blocks.add(OcrBlock(clean));
      }

      sw.stop();
      debugPrint('📝 OCR: ${blocks.length} blok, ${sw.elapsedMilliseconds} ms');
      return OcrResult(blocks: blocks, latencyMs: sw.elapsedMilliseconds);
    } finally {
      _deleteQuietly(imagePath);
    }
  }

  /// Buang ruang berganda & sempang hujung baris ("pela- jar" -> "pelajar").
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
