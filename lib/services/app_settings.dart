import 'package:flutter/material.dart';

enum VoiceLanguage { bm, en }

/// Tetapan app (dalam memori buat masa ini).
/// TODO(Increment 3): simpan dalam jadual `user_settings` (SQLite) supaya
/// kekal selepas app ditutup.
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);
  final ValueNotifier<VoiceLanguage> language = ValueNotifier(VoiceLanguage.bm);
  final ValueNotifier<double> speechRate = ValueNotifier(1.0); // 0.5 – 1.5
  final ValueNotifier<bool> vibrate = ValueNotifier(true);

  void toggleLanguage() {
    language.value = language.value == VoiceLanguage.bm ? VoiceLanguage.en : VoiceLanguage.bm;
  }

  String get languageCode => language.value == VoiceLanguage.bm ? 'BM' : 'EN';

  String speechRateLabel(double r) {
    if (r <= 0.6) return 'Sangat perlahan (${r.toStringAsFixed(1)}x)';
    if (r <= 0.85) return 'Perlahan (${r.toStringAsFixed(1)}x)';
    if (r <= 1.15) return 'Biasa (${r.toStringAsFixed(1)}x)';
    return 'Laju (${r.toStringAsFixed(1)}x)';
  }
}
