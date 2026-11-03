import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/app_settings.dart';
import '../../services/auth_service.dart';
import '../../services/lang.dart';
import '../../services/tts_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../auth/privacy_view.dart';

/// C7 · Profil & Tetapan: kawalan terus di skrin (tiada menu bertingkat).
class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  static void _say(String bm, String en) {
    final tts = TtsService.instance;
    tts.say(t(bm, en), lang: tts.uiLang, remember: false);
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    HapticFeedback.mediumImpact();
    _say('Log keluar? Anda perlu log masuk semula selepas ini.', 'Sign out? You will need to sign in again.');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final cancel = context.tr('Batal', 'Cancel');
        final out = context.tr('Log keluar', 'Sign out');
        return AlertDialog(
          title: Text(context.tr('Log keluar?', 'Sign out?')),
          content: Text(context.tr('Anda perlu log masuk semula untuk guna IrisVision selepas ini.',
              'You will need to sign in again to use IrisVision.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(out),
            ),
          ],
        );
      },
    );
    if (ok != true || !context.mounted) return;
    await AuthService.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = AppSettings.instance;
    final user = AuthService.instance.currentUser;
    final name = user?.displayName?.trim().isNotEmpty == true ? user!.displayName!.trim() : context.tr('Pengguna', 'User');
    final viaGoogle = user?.providerData.any((i) => i.providerId == 'google.com') ?? false;

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 18),
          child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.textSecondary)),
        );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            TopBar(title: Headline(context.tr('Profil', 'Profile'), size: 26)),
            const SizedBox(height: 16),
            // ---------------- kad profil ----------------
            Semantics(
              label: context.tr(
                'Akaun: $name, ${user?.email ?? ''}, ${viaGoogle ? 'akaun Google' : 'e-mel dan kata laluan'}',
                'Account: $name, ${user?.email ?? ''}, ${viaGoogle ? 'Google account' : 'email and password'}',
              ),
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(22)),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle),
                      child: Text(
                        name.characters.first.toUpperCase(),
                        style: TextStyle(fontFamily: AppFonts.heading, fontSize: 26, fontWeight: FontWeight.w800, color: p.onPrimary),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.textPrimary)),
                          const SizedBox(height: 2),
                          Text(
                            '${user?.email ?? '-'} · ${viaGoogle ? context.tr('Akaun Google', 'Google account') : context.tr('E-mel', 'Email')}',
                            style: TextStyle(fontSize: 15, color: p.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ---------------- bahasa ----------------
            label(context.tr('Bahasa app dan suara', 'App and voice language')),
            ValueListenableBuilder<VoiceLanguage>(
              valueListenable: s.language,
              builder: (context, v, _) => Segmented<VoiceLanguage>(
                semanticLabel: context.tr('Bahasa app dan suara', 'App and voice language'),
                options: const [(VoiceLanguage.bm, 'Bahasa Melayu'), (VoiceLanguage.en, 'English')],
                value: v,
                onChanged: (x) {
                  s.language.value = x;
                  _say('Bahasa Melayu dipilih.', 'English selected.');
                },
              ),
            ),
            // ---------------- kelajuan ----------------
            label(context.tr('Kelajuan suara', 'Voice speed')),
            ValueListenableBuilder<double>(
              valueListenable: s.speechRate,
              builder: (context, r, _) => Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(18)),
                child: Row(
                  children: [
                    _StepButton(
                      symbol: '−',
                      tooltip: context.tr('Perlahankan suara', 'Slower voice'),
                      onTap: r > 0.5 ? () => _setRate(s, r - 0.25) : null,
                    ),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          s.speechRateLabel(r),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: AppFonts.heading, fontSize: 18, fontWeight: FontWeight.w700, color: p.textPrimary),
                        ),
                      ),
                    ),
                    _StepButton(
                      symbol: '+',
                      tooltip: context.tr('Lajukan suara', 'Faster voice'),
                      onTap: r < 1.5 ? () => _setRate(s, r + 0.25) : null,
                    ),
                  ],
                ),
              ),
            ),
            // ---------------- tema ----------------
            label(context.tr('Tema paparan (untuk penglihatan terhad)', 'Display theme (for low vision)')),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: s.themeMode,
              builder: (context, m, _) => Segmented<ThemeMode>(
                semanticLabel: context.tr('Tema paparan', 'Display theme'),
                highlightSelected: true,
                options: [
                  (ThemeMode.system, context.tr('Ikut telefon', 'Same as phone')),
                  (ThemeMode.dark, context.tr('Gelap', 'Dark')),
                  (ThemeMode.light, context.tr('Cerah', 'Light')),
                ],
                value: m,
                onChanged: (x) {
                  s.themeMode.value = x;
                  switch (x) {
                    case ThemeMode.dark:
                      _say('Tema gelap dipilih.', 'Dark theme selected.');
                    case ThemeMode.light:
                      _say('Tema cerah dipilih.', 'Light theme selected.');
                    case ThemeMode.system:
                      _say('Tema ikut telefon.', 'Theme follows your phone.');
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
            // ---------------- suis ----------------
            _Toggle(
              value: s.autoAnnounce,
              title: context.tr('Sebut nama skrin bila dibuka', 'Say the screen name when opened'),
              subtitle: context.tr('Senyap bila TalkBack aktif', 'Silent when TalkBack is on'),
            ),
            const SizedBox(height: 12),
            _Toggle(
              value: s.speakDetections,
              title: context.tr('Sebut objek yang dikesan', 'Say detected objects'),
            ),
            const SizedBox(height: 12),
            _Toggle(
              value: s.vibrate,
              title: context.tr('Getaran bila objek dikesan', 'Vibrate when an object is found'),
            ),
            const SizedBox(height: 12),
            // ---------------- privasi ----------------
            Material(
              color: p.surface,
              borderRadius: BorderRadius.circular(18),
              child: ListTile(
                minTileHeight: 64,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                title: Text(context.tr('Privasi dan bantuan', 'Privacy and help'),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.textPrimary)),
                trailing: Icon(Icons.chevron_right, size: 30, color: p.accent),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrivacyView(requireAgreement: false)),
                ),
              ),
            ),
            const SizedBox(height: 28),
            // ---------------- log keluar ----------------
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
                foregroundColor: p.error,
                side: BorderSide(color: p.error, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                textStyle: const TextStyle(fontFamily: AppFonts.heading, fontSize: 19, fontWeight: FontWeight.w700),
              ),
              icon: const Icon(Icons.logout, size: 26),
              label: Text(context.tr('Log keluar', 'Sign out')),
              onPressed: () => _confirmSignOut(context),
            ),
          ],
        ),
      ),
    );
  }
}

void _setRate(AppSettings s, double r) {
  s.speechRate.value = r.clamp(0.5, 1.5);
  // sebut kelajuan baru PADA kelajuan baru, supaya pengguna terus dengar bezanya
  final tts = TtsService.instance;
  tts.say(s.speechRateLabel(s.speechRate.value), lang: tts.uiLang, remember: false);
}

/// Suis hidup/mati. Bila ditukar, app sebut nama + keadaan baru.
class _Toggle extends StatelessWidget {
  final ValueNotifier<bool> value;
  final String title;
  final String? subtitle;
  const _Toggle({required this.value, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ValueListenableBuilder<bool>(
      valueListenable: value,
      builder: (context, on, _) {
        return Container(
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18)),
          child: SwitchListTile(
            value: on,
            onChanged: (x) {
              HapticFeedback.selectionClick();
              value.value = x;
              final tts = TtsService.instance;
              tts.say('$title, ${x ? t('hidup', 'on') : t('mati', 'off')}', lang: tts.uiLang, remember: false);
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.textPrimary)),
            subtitle: subtitle == null ? null : Text(subtitle!, style: TextStyle(fontSize: 15, color: p.textSecondary)),
          ),
        );
      },
    );
  }
}

class _StepButton extends StatelessWidget {
  final String symbol;
  final String tooltip;
  final VoidCallback? onTap;
  const _StepButton({required this.symbol, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: tooltip,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: onTap == null ? Colors.transparent : p.tint,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: SizedBox(
            width: 56,
            height: 52,
            child: Center(
              child: Text(symbol,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: onTap == null ? p.textSecondary : p.accent)),
            ),
          ),
        ),
      ),
    );
  }
}
