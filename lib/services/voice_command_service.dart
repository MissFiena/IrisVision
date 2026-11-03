import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'app_settings.dart';

/// Arahan yang app faham.
enum VoiceAction {
  detect, // buka Kesan Objek
  scan, // buka Imbas Teks
  profile, // buka Profil
  history, // buka Sejarah
  help, // senarai arahan
  langBm, // tukar ke Bahasa Melayu
  langEn, // tukar ke English
  faster, // suara lebih laju
  slower, // suara lebih perlahan
  repeat, // ulang ayat terakhir
  time, // sebut masa sekarang
  unknown, // tak faham
  cancelled, // pengguna tekan Batal / tutup (tiada tindakan)
}

/// Keputusan satu kali mendengar.
class VoiceResult {
  final VoiceAction action;
  final String words; // apa yang didengar
  final int latencyMs; // masa dari mula dengar -> keputusan akhir
  const VoiceResult(this.action, this.words, this.latencyMs);
}

/// Speech-to-Text + pengecam arahan (BM dan English).
///
/// - Guna enjin pengecaman suara dalam telefon (Google).
/// - Arahan BM dan English sentiasa diterima, tak kira bahasa app.
///   Bahasa app cuma tentukan enjin dengar dalam bahasa apa dahulu.
class VoiceCommandService {
  VoiceCommandService._();
  static final VoiceCommandService instance = VoiceCommandService._();

  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  String? _bmLocale;
  String? _enLocale;

  Completer<void>? _done;
  String? _lastError;

  /// Mula enjin (minta kebenaran mikrofon kali pertama).
  /// false = tiada kebenaran / telefon tiada enjin suara.
  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onStatus: _onStatus,
        onError: _onError,
        debugLogging: false,
      );
      if (_ready) {
        final locales = await _stt.locales();
        String? find(String prefix) {
          for (final l in locales) {
            if (l.localeId.toLowerCase().startsWith(prefix)) return l.localeId;
          }
          return null;
        }

        _bmLocale = find('ms');
        _enLocale = find('en_us') ?? find('en-us') ?? find('en');
        debugPrint('🎤 STT sedia. BM=$_bmLocale EN=$_enLocale');
      }
    } catch (e) {
      debugPrint('⚠️ STT init: $e');
      _ready = false;
    }
    return _ready;
  }

  bool get isListening => _stt.isListening;

  /// Dengar satu arahan. [onPartial] = perkataan semasa (untuk dipapar).
  /// Pulang null jika tiada suara langsung / dibatalkan.
  Future<VoiceResult?> listen({void Function(String words)? onPartial}) async {
    if (!await init()) return null;
    final sw = Stopwatch()..start();
    var words = '';
    var finished = false;
    _lastError = null;
    _done = Completer<void>();

    final bm = AppSettings.instance.isBm;
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) {
        words = r.recognizedWords;
        onPartial?.call(words);
        if (r.finalResult) {
          finished = true;
          _complete();
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: bm ? _bmLocale : _enLocale,
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation, // ayat pendek
      ),
    );

    // tunggu keputusan akhir, ralat, atau tamat masa
    await _done!.future.timeout(const Duration(seconds: 10), onTimeout: () {});
    if (_stt.isListening) await _stt.stop();
    sw.stop();

    if (words.trim().isEmpty) {
      debugPrint('🎤 Tiada suara ($_lastError)');
      return null;
    }
    final action = parse(words);
    debugPrint('🎤 "$words" -> $action, ${sw.elapsedMilliseconds} ms, final=$finished');
    return VoiceResult(action, words, sw.elapsedMilliseconds);
  }

  Future<void> cancel() async {
    try {
      await _stt.cancel();
    } catch (_) {}
    _complete();
  }

  void _onStatus(String status) {
    // 'done' / 'notListening' = enjin berhenti mendengar
    if (status == 'done' || status == 'notListening') {
      Future.delayed(const Duration(milliseconds: 300), _complete);
    }
  }

  void _onError(SpeechRecognitionError e) {
    _lastError = e.errorMsg;
    _complete();
  }

  void _complete() {
    final d = _done;
    if (d != null && !d.isCompleted) d.complete();
  }

  // ======================== PENGECAM ARAHAN ========================
  // Susunan penting: yang lebih spesifik disemak dahulu.
  static const List<(VoiceAction, List<String>)> _rules = [
    (VoiceAction.langEn, ['bahasa inggeris', 'bahasa english', 'english', 'inggeris']),
    (VoiceAction.langBm, ['bahasa melayu', 'bahasa malaysia', 'malay', 'melayu']),
    (VoiceAction.faster, ['laju', 'cepat', 'faster', 'speed up']),
    (VoiceAction.slower, ['perlahan', 'lambat', 'slower', 'slow down']),
    (VoiceAction.detect, ['kesan objek', 'objek', 'object', 'detect', 'kesan', 'apa depan', 'apa di depan']),
    (VoiceAction.scan, ['imbas teks', 'imbas', 'teks', 'text', 'scan', 'baca', 'read']),
    (VoiceAction.history, ['sejarah', 'history', 'rekod']),
    (VoiceAction.profile, ['profil', 'profile', 'tetapan', 'setting', 'settings']),
    (VoiceAction.time, ['pukul berapa', 'jam berapa', 'masa', 'what time', 'time']),
    (VoiceAction.repeat, ['ulang', 'repeat', 'again']),
    (VoiceAction.help, ['bantuan', 'tolong', 'help', 'arahan', 'command']),
  ];

  static VoiceAction parse(String words) {
    final w = ' ${words.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';
    for (final (action, keys) in _rules) {
      for (final k in keys) {
        if (w.contains(' $k ')) return action;
      }
    }
    return VoiceAction.unknown;
  }
}
