import 'package:flutter/material.dart';
import '../../services/lang.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'auth_view.dart';
import 'privacy_view.dart';

/// C1 · Selamat Datang (langkah 1 daripada 3).
class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - 48),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        'IRISVISION',
                        style: TextStyle(
                          fontFamily: AppFonts.heading,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: p.accent,
                        ),
                      ),
                    ),
                    const _Hero(),
                    Semantics(
                      header: true,
                      label: context.tr('Mata kedua di dalam poket.', 'A second pair of eyes in your pocket.'),
                      child: ExcludeSemantics(
                        child: Text.rich(
                          TextSpan(
                            text: context.tr('Mata kedua\ndi dalam ', 'A second pair of\neyes in your '),
                            children: [
                              TextSpan(
                                text: context.tr('poket.', 'pocket.'),
                                style: TextStyle(
                                  background: Paint()..color = p.highlight,
                                  color: p.onHighlight,
                                ),
                              ),
                            ],
                          ),
                          style: TextStyle(
                            fontFamily: AppFonts.heading,
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      context.tr(
                        'Kenal objek di kampus dan dengar teks bercetak. Semuanya diproses dalam telefon anda.',
                        'Recognise objects on campus and listen to printed text. Everything runs on your phone.',
                      ),
                      style: TextStyle(fontSize: 18, height: 1.45, color: p.textSecondary),
                    ),
                    const Spacer(),
                    const SizedBox(height: 24),
                    const Align(alignment: Alignment.centerLeft, child: StepDots(step: 1)),
                    const SizedBox(height: 18),
                    BadgeButton(
                      label: context.tr('Mula sekarang', 'Get started'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PrivacyView()),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AuthView(startWithRegister: false)),
                        ),
                        child: Text(context.tr('Saya sudah ada akaun', 'I already have an account')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo dalam gelang (seperti iris mata) + titik kuning. Hiasan sahaja.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget ring(double size, {Color? fill, Color? line}) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: line != null ? Border.all(color: line, width: 2) : null,
          ),
        );
    return ExcludeSemantics(
      child: SizedBox(
        height: 300,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ring(290, line: p.tint),
            ring(232, line: p.border),
            ring(180, fill: p.tint),
            Positioned(
              right: 0,
              left: 150,
              top: 52,
              child: Center(
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: p.highlight, shape: BoxShape.circle),
                ),
              ),
            ),
            const AppLogo(size: 162),
          ],
        ),
      ),
    );
  }
}
