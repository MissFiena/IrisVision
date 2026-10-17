import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'auth_view.dart';

/// C2 · Janji Privasi (langkah 2 daripada 3).
///  - requireAgreement: true  -> sebelum daftar, ada butang "Setuju dan teruskan"
///  - requireAgreement: false -> dibuka dari Profil, baca sahaja
class PrivacyView extends StatelessWidget {
  final bool requireAgreement;
  const PrivacyView({super.key, this.requireAgreement = true});

  static const String fullNotice =
      'Notis ini selaras dengan Akta Perlindungan Data Peribadi 2010 (PDPA).\n\n'
      '1. Data yang dikumpul: nama dan alamat e-mel, untuk tujuan akaun sahaja.\n\n'
      '2. Gambar kamera dan teks yang diimbas diproses dalam telefon anda. '
      'Ia tidak dimuat naik ke mana-mana pelayan.\n\n'
      '3. Akaun diurus oleh Google Firebase Authentication. Kata laluan disimpan '
      'dalam bentuk hash dan tidak boleh dilihat oleh sesiapa, termasuk pembangun.\n\n'
      '4. Data tidak dijual, disewa atau dikongsi dengan pihak ketiga.\n\n'
      '5. Anda boleh minta akaun dan data anda dipadam pada bila-bila masa.\n\n'
      '6. IrisVision ialah alat bantuan. Ia tidak menggantikan tongkat putih, '
      'anjing pemandu atau latihan orientasi dan mobiliti.';

  static const _promises = <(IconData, String)>[
    (Icons.directions_walk, 'Alat bantuan sahaja. Teruskan guna tongkat putih atau anjing pemandu.'),
    (Icons.photo_camera_outlined, 'Kamera dan teks diproses dalam telefon. Tiada gambar dihantar ke internet.'),
    (Icons.lock_outline, 'Hanya nama dan e-mel disimpan, dengan selamat, untuk akaun anda.'),
    (Icons.delete_outline, 'Data tidak dikongsi. Padam akaun bila-bila masa (PDPA 2010).'),
  ];

  void _showFull(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notis Privasi Penuh'),
        content: const SingleChildScrollView(child: Text(fullNotice)),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tutup'))],
      ),
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
                    const Headline('Janji kami kepada anda'),
                    const SizedBox(height: 8),
                    Text('Empat perkara penting sebelum anda mula.',
                        style: TextStyle(fontSize: 17, height: 1.4, color: p.textSecondary)),
                    const SizedBox(height: 16),
                    for (var i = 0; i < _promises.length; i++)
                      _PromiseCard(number: i + 1, icon: _promises[i].$1, text: _promises[i].$2),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _showFull(context),
                        child: const Text('Baca notis privasi penuh'),
                      ),
                    ),
                  ],
                ),
              ),
              if (requireAgreement)
                BadgeButton(
                  label: 'Setuju dan teruskan',
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
      label: 'Janji $number. $text',
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
