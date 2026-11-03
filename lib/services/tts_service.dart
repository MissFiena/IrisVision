import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'app_settings.dart';

enum TextLang { bm, en }

/// Suara (Text-to-Speech) dwibahasa, guna enjin TTS dalam telefon.
///
/// - Setiap blok teks dikesan sendiri sama ada BM atau English, jadi nota
///   yang bercampur bahasa tetap dibaca dengan sebutan yang betul.
/// - Kelajuan ikut tetapan di skrin Profil.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool _bmAvailable = true;
  TextLang? _currentLang;

  bool _speaking = false;
  String? _lastText;
  TextLang? _lastLang;

  int _interruptions = 0;

  /// true semasa enjin sedang bercakap.
  bool get isSpeaking => _speaking;

  /// Bertambah setiap kali [say] menyampuk. Skrin yang membaca panjang
  /// (contoh: hasil imbasan) guna ini untuk tahu bacaannya dipotong.
  int get interruptions => _interruptions;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _tts.awaitSpeakCompletion(true); // speak() tunggu sampai habis
      final bm = await _tts.isLanguageAvailable('ms-MY');
      _bmAvailable = bm == true;
      if (!_bmAvailable) debugPrint('⚠️ Suara BM (ms-MY) tiada, guna suara English.');
    } catch (e) {
      debugPrint('⚠️ TTS init: $e');
    }
    _ready = true;
  }

  /// Bahasa antara muka (untuk mesej sistem seperti "Tiada teks dijumpai").
  TextLang get uiLang => AppSettings.instance.language.value == VoiceLanguage.bm ? TextLang.bm : TextLang.en;

  /// Baca satu teks. Tunggu sehingga selesai (atau dihentikan dengan [stop]).
  /// [lang] kosong = kesan automatik.
  /// [remember] false = jangan simpan untuk "ulang" (contoh: mesej "tiada apa untuk diulang").
  Future<void> speak(String text, {TextLang? lang, bool remember = true}) async {
    if (text.trim().isEmpty) return;
    await init();
    final l = lang ?? detectLanguage(text);
    if (remember) {
      _lastText = text;
      _lastLang = l;
    }
    await _applyLanguage(l);
    // Profil: 0.5x – 1.5x. Android: 0.5 = kelajuan biasa.
    await _tts.setSpeechRate((AppSettings.instance.speechRate.value * 0.5).clamp(0.2, 1.0));
    _speaking = true;
    try {
      await _tts.speak(text);
    } finally {
      _speaking = false;
    }
  }

  /// Sampuk suara semasa, terus cakap ayat baru.
  Future<void> say(String text, {TextLang? lang, bool remember = true}) async {
    _interruptions++;
    await stop();
    await speak(text, lang: lang, remember: remember);
  }

  /// Mesej sistem dalam bahasa pilihan pengguna (sampuk suara semasa).
  Future<void> announce(String bm, String en, {bool remember = true}) {
    final l = uiLang;
    return say(l == TextLang.bm ? bm : en, lang: l, remember: remember);
  }

  /// Pengumuman bila skrin dibuka. Senyap jika dimatikan di Profil, atau
  /// jika TalkBack aktif (elak dua suara bertindih).
  Future<void> announceScreen(BuildContext context, String bm, String en) async {
    if (!AppSettings.instance.autoAnnounce.value) return;
    if (MediaQuery.maybeOf(context)?.accessibleNavigation ?? false) return;
    await announce(bm, en);
  }

  /// Ulang ayat terakhir.
  Future<void> repeatLast() async {
    final t = _lastText;
    if (t == null) {
      await announce('Tiada apa untuk diulang.', 'Nothing to repeat.', remember: false);
      return;
    }
    await say(t, lang: _lastLang);
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _speaking = false;
  }

  Future<void> _applyLanguage(TextLang l) async {
    final target = (l == TextLang.bm && _bmAvailable) ? TextLang.bm : TextLang.en;
    if (_currentLang == target) return;
    await _tts.setLanguage(target == TextLang.bm ? 'ms-MY' : 'en-US');
    _currentLang = target;
  }

  // ------------------- pengesanan bahasa ringkas -------------------
  // Kira perkataan biasa BM vs English. Ringan, offline, cukup tepat untuk
  // nota kuliah dan buku teks.
  static const Set<String> _bmWords = {
    'dan', 'yang', 'di', 'ke', 'dari', 'daripada', 'ini', 'itu', 'untuk', 'dengan', 'adalah',
    'ialah', 'pada', 'tidak', 'akan', 'dalam', 'oleh', 'kepada', 'boleh', 'atau', 'juga',
    'saya', 'kami', 'kita', 'anda', 'mereka', 'ada', 'telah', 'sudah', 'sebagai', 'bagi',
    'serta', 'jika', 'kerana', 'tetapi', 'lebih', 'satu', 'dua', 'tiga', 'hari', 'masa',
    'pelajar', 'sila', 'bahawa', 'semua', 'seperti', 'antara', 'iaitu', 'setiap', 'bahagian',
  };
  static const Set<String> _enWords = {
    'the', 'and', 'of', 'to', 'in', 'is', 'are', 'for', 'on', 'with', 'that', 'this', 'it',
    'as', 'be', 'by', 'or', 'from', 'at', 'an', 'was', 'were', 'will', 'can', 'not', 'have',
    'has', 'you', 'we', 'they', 'which', 'what', 'their', 'there', 'these', 'those', 'should',
    'would', 'about', 'into', 'each', 'student', 'students', 'please', 'all', 'between',
  };

  TextLang detectLanguage(String text) {
    final words = text.toLowerCase().split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty);
    var bm = 0, en = 0;
    for (final w in words) {
      if (_bmWords.contains(w)) bm++;
      if (_enWords.contains(w)) en++;
    }
    if (bm == en) return uiLang; // tak pasti -> ikut bahasa pilihan pengguna
    return bm > en ? TextLang.bm : TextLang.en;
  }
}
