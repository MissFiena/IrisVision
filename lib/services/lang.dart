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
