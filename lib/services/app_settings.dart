import 'package:flutter/material.dart';
import 'database_service.dart';

enum VoiceLanguage { bm, en }

/// Tetapan app. Disimpan dalam jadual `user_settings` (SQLite) untuk
/// pengguna yang sedang log masuk, jadi kekal selepas app ditutup.
/// Setiap kali satu nilai ditukar, baris pengguna itu dikemas kini terus.
class AppSettings {
  AppSettings._() {
    for (final n in <Listenable>[
      themeMode,
      language,
      speechRate,
      vibrate,
      autoAnnounce,
      speakDetections,
      saveHistory,
    ]) {
      n.addListener(_persist);
    }
  }
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

  /// Simpan teks yang diimbas dalam Sejarah (dalam telefon sahaja).
  final ValueNotifier<bool> saveHistory = ValueNotifier(true);

  /// Firebase UID pengguna semasa (null = belum log masuk).
  String? _userId;
  String? get userId => _userId;
  bool _loading = false;

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

  // ============================ DATABASE ============================
  /// Dipanggil sekali selepas log masuk. Daftar pengguna dalam jadual `users`,
  /// kemudian muat tetapannya. Pengguna baru: simpan tetapan semasa
  /// (contohnya bahasa yang dipilih masa daftar) sebagai baris pertama.
  Future<void> bindUser({required String id, required String email, String? displayName}) async {
    _userId = id;
    final db = DatabaseService.instance;
    if (!db.isReady) return;
    try {
      await db.upsertUser(id: id, email: email, displayName: displayName);
      final row = await db.getSettings(id);
      if (row == null) {
        await db.saveSettings(id, _toRow());
      } else {
        _loading = true;
        _fromRow(row);
      }
    } catch (e) {
      debugPrint('❌ Ralat memuat tetapan: $e');
    } finally {
      _loading = false;
    }
  }

  /// Dipanggil bila log keluar: berhenti menyimpan untuk akaun lama.
  void unbindUser() => _userId = null;

  void _persist() {
    final id = _userId;
    if (id == null || _loading || !DatabaseService.instance.isReady) return;
    DatabaseService.instance.saveSettings(id, _toRow()).catchError((Object e) {
      debugPrint('❌ Ralat menyimpan tetapan: $e');
    });
  }

  Map<String, Object?> _toRow() => {
        'language': language.value.name, // 'bm' / 'en'
        'speech_rate': speechRate.value,
        'theme_mode': themeMode.value.name, // 'system' / 'light' / 'dark'
        'vibrate': vibrate.value ? 1 : 0,
        'auto_announce': autoAnnounce.value ? 1 : 0,
        'speak_detections': speakDetections.value ? 1 : 0,
        'save_history': saveHistory.value ? 1 : 0,
      };

  void _fromRow(Map<String, Object?> r) {
    language.value = r['language'] == 'en' ? VoiceLanguage.en : VoiceLanguage.bm;
    speechRate.value = ((r['speech_rate'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 1.5);
    themeMode.value = switch (r['theme_mode']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    vibrate.value = r['vibrate'] != 0;
    autoAnnounce.value = r['auto_announce'] != 0;
    speakDetections.value = r['speak_detections'] != 0;
    saveHistory.value = r['save_history'] != 0;
  }
}
