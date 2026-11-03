import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/app_settings.dart';
import '../../services/auth_service.dart';
import '../../services/lang.dart';
import '../../services/tts_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../live_detection_view.dart';
import '../profile/profile_view.dart';
import '../scan/scan_text_view.dart';

/// C4 · Utama.
/// Skrin belah dua: ATAS = Kesan Objek, BAWAH = Imbas Teks.
/// Pengguna buta cuma perlu ingat "atas objek, bawah teks"; setiap separuh
/// skrin ialah satu butang yang sangat besar.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  @override
  void initState() {
    super.initState();
    // sebut susun atur skrin sekali bila mula masuk
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      TtsService.instance.announceScreen(
        context,
        'Skrin utama. Atas, kesan objek. Bawah, imbas teks.',
        'Home screen. Top, object detection. Bottom, scan text.',
      );
    });
  }

  @override
  Widget build(BuildContext context) => const _HomeBody();
}

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  String _greeting(BuildContext context) {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return context.tr('Selamat pagi', 'Good morning');
    if (h >= 12 && h < 14) return context.tr('Selamat tengah hari', 'Good afternoon');
    if (h >= 14 && h < 19) return context.tr('Selamat petang', 'Good evening');
    return context.tr('Selamat malam', 'Good night');
  }

  void _soon(BuildContext context, String what) {
    final msg = t('$what akan datang dalam kemas kini seterusnya.', '$what is coming in the next update.');
    showInfo(context, msg);
    TtsService.instance.say(msg, lang: TtsService.instance.uiLang);
  }

  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    // balik ke skrin utama -> beritahu pengguna di mana dia sekarang
    if (context.mounted) {
      TtsService.instance.announceScreen(context, 'Skrin utama.', 'Home screen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final name = (AuthService.instance.currentUser?.displayName ?? '').trim().split(' ').first;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---------------- header ----------------
                  Row(
                    children: [
                      const AppLogo(size: 48),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Semantics(
                          header: true,
                          label: '${_greeting(context)}, ${name.isEmpty ? context.tr('pengguna', 'user') : name}',
                          excludeSemantics: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_greeting(context), style: TextStyle(fontSize: 15, color: p.textSecondary)),
                              Text(
                                name.isEmpty ? context.tr('Hai!', 'Hi!') : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: AppFonts.heading,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: p.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const _ReadyPill(),
                      const SizedBox(width: 8),
                      const _LanguageChip(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        ExcludeSemantics(child: Icon(Icons.lock_outline, size: 16, color: p.textSecondary)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            context.tr('Semua diproses dalam telefon. Tiada internet diperlukan.',
                                'Everything runs on your phone. No internet needed.'),
                            style: TextStyle(fontSize: 15, color: p.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ---------------- dua kad besar ----------------
                  Expanded(
                    child: _ModeCard(
                      title: context.tr('Kesan Objek', 'Detect Objects'),
                      subtitle: context.tr('Kenal apa di depan anda', 'Know what is in front of you'),
                      icon: Icons.center_focus_strong,
                      background: p.primary,
                      foreground: p.onPrimary,
                      iconBox: p.surface,
                      iconColor: p.accent,
                      onTap: () => _open(context, const LiveDetectionView()),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _ModeCard(
                      title: context.tr('Imbas Teks', 'Scan Text'),
                      subtitle: context.tr('Dengar buku dan nota', 'Listen to books and notes'),
                      icon: Icons.description_outlined,
                      background: p.highlight,
                      foreground: p.onHighlight,
                      iconBox: p.surface,
                      iconColor: p.textPrimary,
                      onTap: () => _open(context, const ScanTextView()),
                    ),
                  ),
                  const SizedBox(height: 110), // ruang untuk dok
                ],
              ),
            ),
            // ---------------- dok terapung ----------------
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _Dock(
                onHistory: () => _soon(context, t('Sejarah', 'History')),
                onVoice: () => _soon(context, t('Arahan suara', 'Voice command')),
                onHelp: () => _soon(context, t('Bantuan', 'Help')),
                onProfile: () => _open(context, const ProfileView()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lencana status. TODO: tukar ke kuning "Memuatkan..." bila model / suara
/// offline belum sedia (semak TFLite + flutter_tts isLanguageInstalled).
class _ReadyPill extends StatelessWidget {
  const _ReadyPill();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      label: context.tr('Status: sedia, berfungsi tanpa internet', 'Status: ready, works offline'),
      excludeSemantics: true,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: p.successBg, borderRadius: BorderRadius.circular(22)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: p.success,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: p.success.withValues(alpha: 0.3), spreadRadius: 4)],
              ),
            ),
            const SizedBox(width: 8),
            Text(context.tr('Sedia', 'Ready'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.success)),
          ],
        ),
      ),
    );
  }
}

/// Tukar bahasa app + suara BM <-> EN.
/// Bila ditukar, app sebut bahasa baru dalam bahasa itu sendiri.
class _LanguageChip extends StatelessWidget {
  const _LanguageChip();

  static void _toggle() {
    final s = AppSettings.instance;
    s.toggleLanguage();
    final tts = TtsService.instance;
    tts.say(s.isBm ? 'Bahasa Melayu dipilih.' : 'English selected.', lang: tts.uiLang, remember: false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final settings = AppSettings.instance;
    return ValueListenableBuilder<VoiceLanguage>(
      valueListenable: settings.language,
      builder: (context, lang, _) {
        final isBm = lang == VoiceLanguage.bm;
        return Semantics(
          button: true,
          label: isBm
              ? 'Bahasa: Bahasa Melayu. Tukar ke English'
              : 'Language: English. Switch to Bahasa Melayu',
          excludeSemantics: true,
          onTap: _toggle,
          child: Material(
            color: p.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: p.border, width: 2),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _toggle,
              child: SizedBox(
                width: 52,
                height: 52,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(isBm ? 'BM' : 'EN',
                        style: TextStyle(
                            fontFamily: AppFonts.heading, fontSize: 16, fontWeight: FontWeight.w800, color: p.accent, height: 1)),
                    Text(isBm ? 'bahasa' : 'language',
                        style: TextStyle(fontSize: 10, color: p.textSecondary, height: 1.3)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Color iconBox;
  final Color iconColor;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.iconBox,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(30),
        elevation: 2,
        shadowColor: background.withValues(alpha: 0.5),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () {
            HapticFeedback.heavyImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: iconBox, borderRadius: BorderRadius.circular(22)),
                    child: Icon(icon, size: 40, color: iconColor),
                  ),
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: AppFonts.heading,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      color: foreground,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dok terapung: Utama · Sejarah · [Suara] · Bantuan · Profil
class _Dock extends StatelessWidget {
  final VoidCallback onHistory;
  final VoidCallback onVoice;
  final VoidCallback onHelp;
  final VoidCallback onProfile;

  const _Dock({required this.onHistory, required this.onVoice, required this.onHelp, required this.onProfile});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      height: 100,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            height: 84,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 24, offset: const Offset(0, 8)),
              ],
            ),
            child: Row(
              children: [
                _DockItem(
                  icon: Icons.home_rounded,
                  label: context.tr('Utama', 'Home'),
                  selected: true,
                  onTap: () => TtsService.instance.announce('Anda di skrin utama.', 'You are on the home screen.'),
                ),
                _DockItem(icon: Icons.history, label: context.tr('Sejarah', 'History'), onTap: onHistory),
                const Expanded(child: SizedBox()),
                _DockItem(icon: Icons.help_outline, label: context.tr('Bantuan', 'Help'), onTap: onHelp),
                _DockItem(icon: Icons.person_outline, label: context.tr('Profil', 'Profile'), onTap: onProfile),
              ],
            ),
          ),
          Positioned(
            top: 0,
            child: Semantics(
              button: true,
              label: context.tr('Arahan suara', 'Voice command'),
              excludeSemantics: true,
              onTap: onVoice,
              child: Material(
                color: p.primary,
                shape: CircleBorder(side: BorderSide(color: p.background, width: 5)),
                elevation: 6,
                shadowColor: p.primary.withValues(alpha: 0.6),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    onVoice();
                  },
                  child: SizedBox(width: 76, height: 76, child: Icon(Icons.mic, size: 34, color: p.onPrimary)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DockItem({required this.icon, required this.label, required this.onTap, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final color = selected ? p.accent : p.textSecondary;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            height: 84,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: color),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w400, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
