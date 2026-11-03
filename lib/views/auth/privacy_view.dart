import 'package:flutter/material.dart';
import '../../services/lang.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'auth_view.dart';

/// C2 · Janji Privasi (langkah 2 daripada 3).
///  - requireAgreement: true  -> sebelum daftar, ada butang "Setuju dan teruskan"
///  - requireAgreement: false -> dibuka dari Profil, baca sahaja
class PrivacyView extends StatelessWidget {
  final bool requireAgreement;
  const PrivacyView({super.key, this.requireAgreement = true});

  static String get fullNotice => t(
        'Notis ini selaras dengan Akta Perlindungan Data Peribadi 2010 (PDPA).\n\n'
            '1. Data yang dikumpul: nama dan alamat e-mel, untuk tujuan akaun sahaja.\n\n'
            '2. Gambar kamera dan teks yang diimbas diproses dalam telefon anda. '
            'Ia tidak dimuat naik ke mana-mana pelayan.\n\n'
            '3. Akaun diurus oleh Google Firebase Authentication. Kata laluan disimpan '
            'dalam bentuk hash dan tidak boleh dilihat oleh sesiapa, termasuk pembangun.\n\n'
            '4. Data tidak dijual, disewa atau dikongsi dengan pihak ketiga.\n\n'
            '5. Anda boleh minta akaun dan data anda dipadam pada bila-bila masa.\n\n'
            '6. IrisVision ialah alat bantuan. Ia tidak menggantikan tongkat putih, '
            'anjing pemandu atau latihan orientasi dan mobiliti.',
        'This notice follows the Personal Data Protection Act 2010 (PDPA).\n\n'
            '1. Data collected: your name and email address, for your account only.\n\n'
            '2. Camera images and scanned text are processed on your phone. '
            'They are not uploaded to any server.\n\n'
            '3. Accounts are managed by Google Firebase Authentication. Passwords are stored '
            'as a hash and cannot be seen by anyone, including the developer.\n\n'
            '4. Data is not sold, rented or shared with third parties.\n\n'
            '5. You can ask for your account and data to be deleted at any time.\n\n'
            '6. IrisVision is an assistive tool. It does not replace a white cane, '
            'a guide dog or orientation and mobility training.',
      );

  static List<(IconData, String)> get _promises => [
        (
          Icons.directions_walk,
          t('Alat bantuan sahaja. Teruskan guna tongkat putih atau anjing pemandu.',
              'An assistive tool only. Keep using your white cane or guide dog.')
        ),
        (
          Icons.photo_camera_outlined,
          t('Kamera dan teks diproses dalam telefon. Tiada gambar dihantar ke internet.',
              'Camera and text are processed on your phone. No photos are sent to the internet.')
        ),
        (
          Icons.lock_outline,
          t('Hanya nama dan e-mel disimpan, dengan selamat, untuk akaun anda.',
              'Only your name and email are stored, securely, for your account.')
        ),
        (
          Icons.delete_outline,
          t('Data tidak dikongsi. Padam akaun bila-bila masa (PDPA 2010).',
              'Data is never shared. Delete your account any time (PDPA 2010).')
        ),
      ];

  void _showFull(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final close = context.tr('Tutup', 'Close');
        return AlertDialog(
          title: Text(context.tr('Notis Privasi Penuh', 'Full Privacy Notice')),
          content: SingleChildScrollView(child: Text(fullNotice)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(close)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TopBar(step: requireAgreement ? 2 : null),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 18, bottom: 12),
                  children: [
                    Headline(context.tr('Janji kami kepada anda', 'Our promise to you')),
                    const SizedBox(height: 8),
                    Text(context.tr('Empat perkara penting sebelum anda mula.', 'Four important things before you start.'),
                        style: TextStyle(fontSize: 17, height: 1.4, color: p.textSecondary)),
                    const SizedBox(height: 16),
                    for (var i = 0; i < _promises.length; i++)
                      _PromiseCard(number: i + 1, icon: _promises[i].$1, text: _promises[i].$2),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _showFull(context),
                        child: Text(context.tr('Baca notis privasi penuh', 'Read the full privacy notice')),
                      ),
                    ),
                  ],
                ),
              ),
              if (requireAgreement)
                BadgeButton(
                  label: context.tr('Setuju dan teruskan', 'Agree and continue'),
                  badgeIcon: Icons.check,
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const AuthView(startWithRegister: true)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromiseCard extends StatelessWidget {
  final int number;
  final IconData icon;
  final String text;
  const _PromiseCard({required this.number, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      label: context.tr('Janji $number. $text', 'Promise $number. $text'),
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            ExcludeSemantics(
              child: SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(color: p.tint, borderRadius: BorderRadius.circular(16)),
                      child: Icon(icon, color: p.accent, size: 26),
                    ),
                    Positioned(
                      right: 0,
                      top: -4,
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: p.highlight, shape: BoxShape.circle),
                        child: Text('$number',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.onHighlight)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 16.5, height: 1.35, color: p.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}
