import 'package:flutter/material.dart';
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
                      label: 'Mata kedua di dalam poket.',
                      child: ExcludeSemantics(
                        child: Text.rich(
                          TextSpan(
                            text: 'Mata kedua\ndi dalam ',
                            children: [
                              TextSpan(
                                text: 'poket.',
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
                      'Kenal objek di kampus dan dengar teks bercetak. '
                      'Semuanya diproses dalam telefon anda.',
                      style: TextStyle(fontSize: 18, height: 1.45, color: p.textSecondary),
                    ),
                    const Spacer(),
                    const SizedBox(height: 24),
                    const Align(alignment: Alignment.centerLeft, child: StepDots(step: 1)),
                    const SizedBox(height: 18),
                    BadgeButton(
                      label: 'Mula sekarang',
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
                        child: const Text('Saya sudah ada akaun'),
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
