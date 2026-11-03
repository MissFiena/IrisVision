import 'package:flutter/material.dart';

enum VoiceLanguage { bm, en }

/// Tetapan app (dalam memori buat masa ini).
/// TODO(Increment 3 Step 3): simpan dalam jadual `user_settings` (SQLite)
/// supaya kekal selepas app ditutup.
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  /// Bahasa app DAN suara (BM / English). Tukar satu, semua ikut.
  final ValueNotifier<VoiceLanguage> language = ValueNotifier(VoiceLanguage.bm);
  final ValueNotifier<double> speechRate = ValueNotifier(1.0); // 0.5 – 1.5
  final ValueNotifier<bool> vibrate = ValueNotifier(true);

  /// Sebut nama skrin bila dibuka. Tidak berbunyi bila TalkBack aktif
  /// (TalkBack sendiri sudah membaca skrin).
  final ValueNotifier<bool> autoAnnounce = ValueNotifier(true);

  /// Sebut objek yang dikesan di skrin Kesan Objek.
  final ValueNotifier<bool> speakDetections = ValueNotifier(true);

  bool get isBm => language.value == VoiceLanguage.bm;

  void toggleLanguage() {
    language.value = isBm ? VoiceLanguage.en : VoiceLanguage.bm;
  }

  String get languageCode => isBm ? 'BM' : 'EN';

  String speechRateLabel(double r) {
    final x = '(${r.toStringAsFixed(1)}x)';
    if (r <= 0.6) return isBm ? 'Sangat perlahan $x' : 'Very slow $x';
    if (r <= 0.85) return isBm ? 'Perlahan $x' : 'Slow $x';
    if (r <= 1.15) return isBm ? 'Biasa $x' : 'Normal $x';
    return isBm ? 'Laju $x' : 'Fast $x';
  }
}
