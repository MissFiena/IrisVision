import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'auth/verify_email_view.dart';
import 'auth/welcome_view.dart';
import 'home/home_view.dart';

/// Pintu masuk app. Tentukan skrin pertama ikut status sesi:
///   tiada sesi           -> Welcome (Log Masuk / Daftar)
///   ada sesi, belum sah  -> Sahkan E-mel
///   ada sesi, sah        -> Home (terus, tak perlu log masuk lagi)
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AuthService.instance;

  @override
  void initState() {
    super.initState();
    // semak sekali di latar belakang: akaun disekat / dipadam?
    _auth.validateSession();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.userChanges(),
      initialData: _auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final Widget page;
        if (user == null) {
          page = const WelcomeView();
        } else if (_auth.needsVerification(user)) {
          page = const VerifyEmailView();
        } else {
          page = const HomeView();
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(key: ValueKey(page.runtimeType), child: page),
        );
      },
    );
  }
}

/// Skrin pembuka ringkas (dipakai semasa Firebase dimulakan).
class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(
        label: 'IrisVision sedang dibuka',
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 180),
              const SizedBox(height: 24),
              Text(
                'IrisVision',
                style: TextStyle(
                  fontFamily: AppFonts.heading,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: context.pal.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
