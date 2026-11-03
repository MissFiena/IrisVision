import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart'; // dijana oleh: flutterfire configure
import 'services/app_settings.dart';
import 'services/lang.dart';
import 'theme/app_theme.dart';
import 'views/auth_gate.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // kunci portrait supaya kotak detection sentiasa sejajar
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const IrisVisionApp());
}

class IrisVisionApp extends StatelessWidget {
  const IrisVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Tema ikut pilihan di Profil (default: ikut telefon)
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.instance.themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'IrisVision',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        // Bahasa app: semua skrin dibina semula bila BM/EN ditukar
        builder: (context, child) => ValueListenableBuilder<VoiceLanguage>(
          valueListenable: AppSettings.instance.language,
          builder: (context, lang, _) => LangScope(lang: lang, child: child ?? const SizedBox()),
        ),
        home: const _Bootstrap(),
      ),
    );
  }
}

/// Papar splash sambil Firebase dimulakan, kemudian serah kepada AuthGate.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<void> _init = _start();

  Future<void> _start() async {
    await Future.wait([
      Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
      Future<void>.delayed(const Duration(milliseconds: 1200)), // splash minimum
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SplashView();
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      context.tr('IrisVision tidak dapat dimulakan. Sila cuba lagi.',
                          'IrisVision could not start. Please try again.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(height: 24),
                    BadgeButton(
                      label: context.tr('Cuba lagi', 'Try again'),
                      badgeIcon: Icons.refresh,
                      onPressed: () => setState(() => _init = _start()),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const AuthGate();
      },
    );
  }
}
