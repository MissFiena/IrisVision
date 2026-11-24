import 'package:flutter/widgets.dart';
import 'app_settings.dart';

/// Bahasa app = bahasa suara. Tukar BM/EN -> semua tulisan dan suara ikut.
///
/// Dalam widget guna `context.tr('BM', 'EN')` supaya skrin dibina semula
/// bila bahasa ditukar. Di luar widget (servis, validasi) guna `t()`.
String t(String bm, String en) => AppSettings.instance.language.value == VoiceLanguage.bm ? bm : en;

extension LangContext on BuildContext {
  String tr(String bm, String en) {
    dependOnInheritedWidgetOfExactType<LangScope>(); // daftar untuk rebuild
    return t(bm, en);
  }

  bool get isBm {
    dependOnInheritedWidgetOfExactType<LangScope>();
    return AppSettings.instance.language.value == VoiceLanguage.bm;
  }
}

/// Diletak di atas semua skrin (dalam MaterialApp.builder).
class LangScope extends InheritedWidget {
  final VoiceLanguage lang;
  const LangScope({super.key, required this.lang, required super.child});

  @override
  bool updateShouldNotify(LangScope oldWidget) => oldWidget.lang != lang;
}

/// Tukar nombor ke perkataan BM, supaya TalkBack/TTS tak baca dalam English.
String nomborBm(int n) {
  const s = ['kosong', 'satu', 'dua', 'tiga', 'empat', 'lima', 'enam', 'tujuh', 'lapan', 'sembilan'];
  if (n < 0) return 'negatif ${nomborBm(-n)}';
  if (n < 10) return s[n];
  if (n == 10) return 'sepuluh';
  if (n == 11) return 'sebelas';
  if (n < 20) return '${s[n - 10]} belas';
  if (n < 100) {
    final r = n % 10;
    return r == 0 ? '${s[n ~/ 10]} puluh' : '${s[n ~/ 10]} puluh ${s[r]}';
  }
  if (n < 1000) {
    final h = n ~/ 100, r = n % 100;
    final hs = h == 1 ? 'seratus' : '${s[h]} ratus';
    return r == 0 ? hs : '$hs ${nomborBm(r)}';
  }
  if (n < 1000000) {
    final k = n ~/ 1000, r = n % 1000;
    final ks = k == 1 ? 'seribu' : '${nomborBm(k)} ribu';
    return r == 0 ? ks : '$ks ${nomborBm(r)}';
  }
  return '$n';
}