import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Dipaparkan selepas daftar, sehingga pengguna tekan pautan dalam e-mel.
/// App semak status secara automatik setiap 5 saat (pengguna tak perlu
/// cari butang selepas kembali dari app e-mel).
class VerifyEmailView extends StatefulWidget {
  const VerifyEmailView({super.key});

  @override
  State<VerifyEmailView> createState() => _VerifyEmailViewState();
}

class _VerifyEmailViewState extends State<VerifyEmailView> with WidgetsBindingObserver {
  final _auth = AuthService.instance;
  Timer? _poll;
  Timer? _cooldownTimer;
  int _cooldown = 60; // elak spam butang "hantar semula"
  bool _checking = false;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCooldown();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _check(silent: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // pengguna baru balik dari app e-mel -> terus semak
    if (state == AppLifecycleState.resumed) _check(silent: true);
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldown = 60;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    _checking = true;
    if (!silent) setState(() {});
    final verified = await _auth.reloadAndCheckVerified();
    _checking = false;
    if (!mounted) return;
    if (verified) {
      HapticFeedback.mediumImpact();
      // userChanges() dalam AuthGate akan tukar ke Home
      return;
    }
    if (!silent) {
      HapticFeedback.heavyImpact();
      setState(() {
        _isError = true;
        _message = 'E-mel belum disahkan. Sila tekan pautan dalam e-mel dahulu.';
      });
    }
  }

  Future<void> _resend() async {
    final r = await _auth.resendVerification();
    if (!mounted) return;
    setState(() {
      _isError = !r.ok;
      _message = r.ok ? 'E-mel pengesahan telah dihantar semula.' : r.message;
    });
    if (r.ok) setState(_startCooldown);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final email = _auth.currentUser?.email ?? '';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
          children: [
            Center(
              child: ExcludeSemantics(
                child: Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(color: p.tint, shape: BoxShape.circle),
                  child: Icon(Icons.mark_email_unread_outlined, size: 64, color: p.accent),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Center(child: Headline('Semak e-mel anda', size: 28)),
            const SizedBox(height: 10),
            Text(
              'Kami telah hantar pautan pengesahan ke $email. '
              'Tekan pautan itu, dan IrisVision akan terus dibuka.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, height: 1.45, color: p.textSecondary),
            ),
            const SizedBox(height: 20),
            StatusBanner(
              message: _message ?? 'App semak secara automatik setiap 5 saat. Tak perlu tekan apa-apa.',
              isError: _message != null && _isError,
            ),
            const SizedBox(height: 24),
            BadgeButton(
              label: 'Saya sudah sahkan',
              badgeIcon: Icons.check,
              loading: _checking,
              onPressed: () => _check(),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _cooldown > 0 ? null : _resend,
                child: Text(_cooldown > 0 ? 'Hantar semula dalam $_cooldown saat' : 'Hantar semula e-mel'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => _auth.signOut(),
                child: const Text('Guna e-mel lain / Log keluar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
