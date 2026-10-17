import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/app_settings.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../auth/privacy_view.dart';

/// C7 · Profil & Tetapan: kawalan terus di skrin (tiada menu bertingkat).
class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  Future<void> _confirmSignOut(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log keluar?'),
        content: const Text('Anda perlu log masuk semula untuk guna IrisVision selepas ini.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Log keluar')),
        ],
      ),
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
    final name = user?.displayName?.trim().isNotEmpty == true ? user!.displayName!.trim() : 'Pengguna';
    final viaGoogle = user?.providerData.any((i) => i.providerId == 'google.com') ?? false;

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 18),
          child: Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.textSecondary)),
        );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            const TopBar(title: Headline('Profil', size: 26)),
            const SizedBox(height: 16),
            // ---------------- kad profil ----------------
            Semantics(
              label: 'Akaun: $name, ${user?.email ?? ''}, ${viaGoogle ? 'akaun Google' : 'e-mel dan kata laluan'}',
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
                            '${user?.email ?? '-'} · ${viaGoogle ? 'Akaun Google' : 'E-mel'}',
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
            label('Bahasa suara'),
            ValueListenableBuilder<VoiceLanguage>(
              valueListenable: s.language,
              builder: (context, v, _) => Segmented<VoiceLanguage>(
                semanticLabel: 'Bahasa suara',
                options: const [(VoiceLanguage.bm, 'Bahasa Melayu'), (VoiceLanguage.en, 'English')],
                value: v,
                onChanged: (x) => s.language.value = x,
              ),
            ),
            // ---------------- kelajuan ----------------
            label('Kelajuan suara'),
            ValueListenableBuilder<double>(
              valueListenable: s.speechRate,
              builder: (context, r, _) => Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(18)),
                child: Row(
                  children: [
                    _StepButton(
                      symbol: '−',
                      tooltip: 'Perlahankan suara',
                      onTap: r > 0.5 ? () => s.speechRate.value = (r - 0.25).clamp(0.5, 1.5) : null,
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
                      tooltip: 'Lajukan suara',
                      onTap: r < 1.5 ? () => s.speechRate.value = (r + 0.25).clamp(0.5, 1.5) : null,
                    ),
                  ],
                ),
              ),
            ),
            // ---------------- tema ----------------
            label('Tema'),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: s.themeMode,
              builder: (context, m, _) => Segmented<ThemeMode>(
                semanticLabel: 'Tema paparan',
                highlightSelected: true,
                options: const [
                  (ThemeMode.system, 'Ikut telefon'),
                  (ThemeMode.dark, 'Gelap'),
                  (ThemeMode.light, 'Cerah'),
                ],
                value: m,
                onChanged: (x) => s.themeMode.value = x,
              ),
            ),
            const SizedBox(height: 16),
            // ---------------- getaran ----------------
            ValueListenableBuilder<bool>(
              valueListenable: s.vibrate,
              builder: (context, on, _) => Container(
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18)),
                child: SwitchListTile(
                  value: on,
                  onChanged: (x) {
                    HapticFeedback.selectionClick();
                    s.vibrate.value = x;
                  },
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text('Getaran bila objek dikesan',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.textPrimary)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ---------------- privasi ----------------
            Material(
              color: p.surface,
              borderRadius: BorderRadius.circular(18),
              child: ListTile(
                minTileHeight: 64,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                title: Text('Privasi dan bantuan',
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
              label: const Text('Log keluar'),
              onPressed: () => _confirmSignOut(context),
            ),
          ],
        ),
      ),
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
