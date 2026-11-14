import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/app_settings.dart';
import '../../services/lang.dart';
import '../../services/tts_service.dart';
import '../../services/voice_command_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../auth/privacy_view.dart';
import '../voice/voice_command_sheet.dart';

// =============================== KANDUNGAN ===============================
// Setiap topik: 3–4 ayat pendek sahaja. Satu blok, supaya pengguna
// TalkBack cuma perlu satu leret untuk dengar semuanya.

class HelpTopic {
  final IconData icon;
  final String titleBm, titleEn;
  final String subBm, subEn; // keterangan 3–4 perkataan di menu
  final List<String> bm, en; // ayat-ayat bantuan
  final bool practice; // tunjuk butang Cuba arahan suara

  const HelpTopic({
    required this.icon,
    required this.titleBm,
    required this.titleEn,
    required this.subBm,
    required this.subEn,
    required this.bm,
    required this.en,
    this.practice = false,
  });

  String title(bool isBm) => isBm ? titleBm : titleEn;
  String sub(bool isBm) => isBm ? subBm : subEn;
  List<String> lines(bool isBm) => isBm ? bm : en;
}

const List<HelpTopic> kHelpTopics = [
  HelpTopic(
    icon: Icons.flag_outlined,
    titleBm: 'Mula guna',
    titleEn: 'Getting started',
    subBm: 'Susun atur skrin utama',
    subEn: 'Home screen layout',
    bm: [
      'Skrin utama ada dua bahagian. Atas untuk Kesan Objek. Bawah untuk Imbas Teks.',
      'Di bawah sekali: Utama, Sejarah, Mikrofon, Bantuan, Profil.',
      'App ini alat bantuan. Teruskan guna tongkat putih.',
    ],
    en: [
      'The home screen has two parts. Top is Object Detection. Bottom is Scan Text.',
      'At the very bottom: Home, History, Microphone, Help, Profile.',
      'This app is an assistive tool. Keep using your white cane.',
    ],
  ),
  HelpTopic(
    icon: Icons.center_focus_strong,
    titleBm: 'Kesan Objek',
    titleEn: 'Object Detection',
    subBm: 'Kenal objek di depan',
    subEn: 'Know what is ahead',
    bm: [
      'Pegang telefon di paras dada, halakan ke depan.',
      'App sebut nama objek dan arahnya: kiri, depan atau kanan.',
      'Jika app minta, jalan lebih dekat.',
    ],
    en: [
      'Hold the phone at chest level and point it ahead.',
      'The app says the object and where it is: left, ahead or right.',
      'If the app asks, move a little closer.',
    ],
  ),
  HelpTopic(
    icon: Icons.description_outlined,
    titleBm: 'Imbas Teks',
    titleEn: 'Scan Text',
    subBm: 'Dengar buku dan nota',
    subEn: 'Listen to books and notes',
    bm: [
      'Pegang telefon sejengkal dari kertas.',
      'Ketik di mana-mana pada skrin.',
      'App baca teks satu perenggan demi satu.',
      'Tempat gelap? Tekan butang lampu.',
    ],
    en: [
      'Hold the phone one hand-span from the paper.',
      'Tap anywhere on the screen.',
      'The app reads the text one paragraph at a time.',
      'Too dark? Press the light button.',
    ],
  ),
  HelpTopic(
    icon: Icons.mic_none,
    titleBm: 'Arahan suara',
    titleEn: 'Voice commands',
    subBm: 'Guna app dengan suara',
    subEn: 'Use the app by voice',
    practice: true,
    bm: [
      'Tekan butang mikrofon di tengah bawah.',
      'Tunggu app sebut "Ya?", kemudian cakap.',
      'Contoh: kesan objek, imbas teks, sejarah, ulang, pukul berapa.',
      'Sebut "bantuan" untuk senarai penuh.',
    ],
    en: [
      'Press the microphone button at the bottom centre.',
      'Wait for the app to say "Yes?", then speak.',
      'For example: detect object, scan text, history, repeat, what time.',
      'Say "help" for the full list.',
    ],
  ),
  HelpTopic(
    icon: Icons.history,
    titleBm: 'Sejarah',
    titleEn: 'History',
    subBm: 'Dengar teks lama',
    subEn: 'Listen to old scans',
    bm: [
      'Setiap teks yang diimbas disimpan di sini.',
      'Ketik satu untuk dengar semula.',
      'Boleh namakan semula atau padam.',
    ],
    en: [
      'Every text you scan is saved here.',
      'Tap one to listen again.',
      'You can rename or delete it.',
    ],
  ),
  HelpTopic(
    icon: Icons.person_outline,
    titleBm: 'Profil',
    titleEn: 'Profile',
    subBm: 'Bahasa, suara, tema',
    subEn: 'Language, voice, theme',
    bm: [
      'Tukar bahasa, kelajuan suara dan tema di sini.',
      'Tetapan kekal walaupun app ditutup.',
      'Log keluar juga di sini.',
    ],
    en: [
      'Change the language, voice speed and theme here.',
      'Settings stay even after the app is closed.',
      'Sign out is here too.',
    ],
  ),
  HelpTopic(
    icon: Icons.build_outlined,
    titleBm: 'Masalah biasa',
    titleEn: 'Common problems',
    subBm: 'Jika app tak berfungsi',
    subEn: 'If something does not work',
    bm: [
      'Objek tak dikesan: tambah cahaya, pegang telefon stabil.',
      'Teks salah dibaca: hidupkan lampu, letak semua teks dalam kotak.',
      'Suara Melayu bunyi pelik: muat turun suara Melayu dalam tetapan Text-to-speech telefon.',
      'Mikrofon tak jalan: benarkan mikrofon dalam tetapan telefon.',
    ],
    en: [
      'Objects not found: add more light, hold the phone steady.',
      'Text read wrongly: turn on the light, keep all text in the frame.',
      'Malay voice sounds odd: download the Malay voice in the phone Text-to-speech settings.',
      'Microphone not working: allow the microphone in phone settings.',
    ],
  ),
];

bool _talkBackOn(BuildContext context) => MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;

// ================================ MENU ================================
/// C9 · Bantuan: menu topik. Pengguna pilih apa yang dia nak tahu,
/// tak perlu leret melalui semua bantuan.
class HelpView extends StatefulWidget {
  const HelpView({super.key});

  @override
  State<HelpView> createState() => _HelpViewState();
}

class _HelpViewState extends State<HelpView> {
  final TtsService _tts = TtsService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final n = kHelpTopics.length;
      _tts.announceScreen(context, 'Bantuan. Pilih satu daripada $n topik.', 'Help. Choose one of $n topics.');
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _open(HelpTopic topic) async {
    await _tts.stop();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => HelpTopicView(topic: topic)));
    if (mounted) _tts.announceScreen(context, 'Bantuan.', 'Help.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final bm = context.isBm;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            TopBar(title: Headline(context.tr('Bantuan', 'Help'), size: 26)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 14),
              child: Text(
                context.tr('Pilih topik.', 'Choose a topic.'),
                style: TextStyle(fontSize: 17, color: p.textSecondary),
              ),
            ),
            for (var i = 0; i < kHelpTopics.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TopicButton(
                  topic: kHelpTopics[i],
                  number: i + 1,
                  total: kHelpTopics.length,
                  isBm: bm,
                  onTap: () => _open(kHelpTopics[i]),
                ),
              ),
            const SizedBox(height: 8),
            Material(
              color: p.surface,
              borderRadius: BorderRadius.circular(18),
              child: ListTile(
                minTileHeight: 60,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                leading: Icon(Icons.lock_outline, size: 26, color: p.textSecondary),
                title: Text(context.tr('Notis privasi', 'Privacy notice'),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.textSecondary)),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrivacyView(requireAgreement: false)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicButton extends StatelessWidget {
  final HelpTopic topic;
  final int number, total;
  final bool isBm;
  final VoidCallback onTap;
  const _TopicButton({
    required this.topic,
    required this.number,
    required this.total,
    required this.isBm,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      button: true,
      label: '${topic.title(isBm)}. ${topic.sub(isBm)}',
      hint: context.tr('Topik $number daripada $total', 'Topic $number of $total'),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: p.border, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 80),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: p.tint, borderRadius: BorderRadius.circular(16)),
                    child: Icon(topic.icon, size: 30, color: p.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(topic.title(isBm),
                            style: TextStyle(
                                fontFamily: AppFonts.heading, fontSize: 20, fontWeight: FontWeight.w700, color: p.textPrimary)),
                        const SizedBox(height: 2),
                        Text(topic.sub(isBm), style: TextStyle(fontSize: 15, color: p.textSecondary)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 30, color: p.accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================== SATU TOPIK ==============================
/// Halaman satu topik. Tanpa TalkBack: dibaca terus bila dibuka.
/// Dengan TalkBack: semua ayat dalam SATU blok (satu leret).
class HelpTopicView extends StatefulWidget {
  final HelpTopic topic;
  const HelpTopicView({super.key, required this.topic});

  @override
  State<HelpTopicView> createState() => _HelpTopicViewState();
}

class _HelpTopicViewState extends State<HelpTopicView> {
  final TtsService _tts = TtsService.instance;
  bool _playing = false;
  int _run = 0;
  String? _lastTry; // keputusan latihan terakhir
  int _tries = 0, _known = 0;

  String get _spoken {
    final bm = AppSettings.instance.isBm;
    return '${widget.topic.title(bm)}. ${widget.topic.lines(bm).join(' ')}';
  }

  @override
  void initState() {
    super.initState();
    // Sentiasa dibaca oleh suara app (sebutan BM lebih jelas daripada TalkBack).
    // TalkBack hidup: tunggu dia habis sebut bahagian atas dahulu.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_talkBackOn(context)) {
        await Future<void>.delayed(const Duration(milliseconds: 2000));
        if (!mounted) return;
      }
      _play();
    });
  }

  @override
  void dispose() {
    _run++;
    _tts.stop();
    super.dispose();
  }

  Future<void> _play() async {
    final run = ++_run;
    setState(() => _playing = true);
    await _tts.say(_spoken, lang: _tts.uiLang);
    if (run == _run && mounted) setState(() => _playing = false);
  }

  Future<void> _toggle() async {
    HapticFeedback.mediumImpact();
    if (_playing) {
      _run++;
      await _tts.stop();
      if (mounted) setState(() => _playing = false);
    } else {
      _play();
    }
  }

  /// Cuba arahan: app beritahu apa yang difahami, TIDAK buka skrin lain.
  Future<void> _practise() async {
    _run++;
    await _tts.stop();
    if (!mounted) return;
    setState(() => _playing = false);
    final r = await showVoiceCommandSheet(context);
    if (!mounted || r == null || r.action == VoiceAction.cancelled) {
      if (mounted && r == null) _tts.announce('Tiada suara didengar.', 'No voice heard.', remember: false);
      return;
    }
    final ok = r.action != VoiceAction.unknown;
    final secs = (r.latencyMs / 1000).toStringAsFixed(1);
    final msg = ok
        ? t('Betul. Saya dengar "${r.words}". $secs saat.', 'Correct. I heard "${r.words}". $secs seconds.')
        : t('Saya dengar "${r.words}". Ini bukan arahan.', 'I heard "${r.words}". This is not a command.');
    setState(() {
      _tries++;
      if (ok) _known++;
      _lastTry = msg;
    });
    _tts.announce(msg, msg, remember: false); // TalkBack hidup -> TalkBack sebut
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final bm = context.isBm;
    final topic = widget.topic;
    final lines = topic.lines(bm);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            TopBar(title: Headline(topic.title(bm), size: 26)),
            const SizedBox(height: 18),
            // Teks untuk dilihat sahaja (penglihatan terhad). TalkBack langkau
            // blok ini; kandungan dibaca oleh suara app supaya tak berganda.
            ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(22)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      Padding(
                        padding: EdgeInsets.only(bottom: i == lines.length - 1 ? 0 : 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: p.highlight, borderRadius: BorderRadius.circular(10)),
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      fontFamily: AppFonts.heading,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: p.onHighlight)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(lines[i],
                                  style: TextStyle(fontSize: 20, height: 1.4, color: p.textPrimary)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            BadgeButton(
              label: _playing ? context.tr('Berhenti', 'Stop') : context.tr('Dengar semula', 'Listen again'),
              badgeIcon: _playing ? Icons.stop_rounded : Icons.volume_up_rounded,
              onPressed: _toggle,
            ),
            if (topic.practice) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                  foregroundColor: p.accent,
                  side: BorderSide(color: p.accent, width: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  textStyle: const TextStyle(fontFamily: AppFonts.heading, fontSize: 19, fontWeight: FontWeight.w700),
                ),
                icon: const Icon(Icons.mic, size: 26),
                label: Text(context.tr('Cuba arahan suara', 'Try a voice command')),
                onPressed: _practise,
              ),
              if (_lastTry != null) ...[
                const SizedBox(height: 12),
                Text(
                  '$_lastTry\n${context.tr('Betul: $_known daripada $_tries', 'Correct: $_known of $_tries')}',
                  style: TextStyle(fontSize: 17, height: 1.4, fontWeight: FontWeight.w700, color: p.textSecondary),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
