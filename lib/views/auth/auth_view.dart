import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/lang.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import 'forgot_password_view.dart';
import 'privacy_view.dart';

enum _Mode { login, register }

/// C3 · Masuk / Daftar dalam SATU skrin (langkah 3 daripada 3).
/// Google di atas (paling pantas untuk pengguna TalkBack: tiada kata laluan).
class AuthView extends StatefulWidget {
  final bool startWithRegister;
  const AuthView({super.key, this.startWithRegister = false});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late _Mode _mode = widget.startWithRegister ? _Mode.register : _Mode.login;
  bool _loading = false;
  bool _googleLoading = false;
  String? _error;

  bool get _isRegister => _mode == _Mode.register;
  bool get _busy => _loading || _googleLoading;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _switchMode(_Mode m) {
    if (m == _mode) return;
    // Daftar baharu mesti lalu Janji Privasi dahulu (persetujuan PDPA)
    if (m == _Mode.register && !widget.startWithRegister) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PrivacyView()));
      return;
    }
    setState(() {
      _mode = m;
      _error = null;
      _password.clear();
      _confirm.clear();
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _loading = true);
    final auth = AuthService.instance;
    final result = _isRegister
        ? await auth.register(name: _name.text, email: _email.text, password: _password.text)
        : await auth.signIn(email: _email.text, password: _password.text);
    if (!mounted) return;

    if (result.ok) {
      TextInput.finishAutofillContext(); // tawar simpan dalam Password Manager
      // AuthGate (skrin paling bawah) tukar ke Utama / Sahkan E-mel sendiri
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      HapticFeedback.heavyImpact();
      if (!_isRegister) _password.clear();
      setState(() {
        _loading = false;
        _error = result.message;
      });
    }
  }

  Future<void> _google() async {
    if (_busy) return;
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    final r = await AuthService.instance.signInWithGoogle();
    if (!mounted) return;
    if (r.ok) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _googleLoading = false;
        _error = r.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      body: SafeArea(
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              children: [
                TopBar(step: widget.startWithRegister ? 3 : null),
                const SizedBox(height: 18),
                Headline(_isRegister
                    ? context.tr('Cipta akaun, sekali sahaja.', 'Create an account, just once.')
                    : context.tr('Selamat kembali.', 'Welcome back.')),
                const SizedBox(height: 16),
                Segmented<_Mode>(
                  semanticLabel: context.tr('Pilih log masuk atau daftar', 'Choose sign in or register'),
                  options: [
                    (_Mode.login, context.tr('Log Masuk', 'Sign In')),
                    (_Mode.register, context.tr('Daftar', 'Register')),
                  ],
                  value: _mode,
                  onChanged: _switchMode,
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  StatusBanner(message: _error!),
                  const SizedBox(height: 16),
                ],
                _GoogleCard(loading: _googleLoading, onTap: _busy ? null : _google),
                const SizedBox(height: 16),
                ExcludeSemantics(
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: p.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(context.tr('atau guna e-mel', 'or use email'), style: TextStyle(fontSize: 15, color: p.textSecondary)),
                      ),
                      Expanded(child: Divider(color: p.border)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_isRegister) ...[
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    maxLength: Validators.nameMax,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    style: const TextStyle(fontSize: 20),
                    validator: Validators.name,
                    decoration: InputDecoration(
                      labelText: context.tr('Nama penuh', 'Full name'),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: _isRegister
                      ? const [AutofillHints.email]
                      : const [AutofillHints.email, AutofillHints.username],
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(fontSize: 20),
                  validator: Validators.email,
                  decoration: InputDecoration(
                    labelText: context.tr('E-mel', 'Email'),
                    helperText: _isRegister
                        ? context.tr('Pautan pengesahan akan dihantar ke e-mel ini.', 'A verification link will be sent to this email.')
                        : null,
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _password,
                  label: context.tr('Kata laluan', 'Password'),
                  helper: _isRegister
                      ? context.tr('Sekurang-kurangnya 8 aksara, dengan huruf dan nombor.', 'At least 8 characters, with letters and numbers.')
                      : null,
                  action: _isRegister ? TextInputAction.next : TextInputAction.done,
                  autofillHints: _isRegister ? const [AutofillHints.newPassword] : const [AutofillHints.password],
                  validator: _isRegister
                      ? (v) => Validators.newPassword(v, email: _email.text)
                      : Validators.loginPassword,
                  onSubmitted: _isRegister ? null : _submit,
                ),
                if (_isRegister) ...[
                  const SizedBox(height: 16),
                  PasswordField(
                    controller: _confirm,
                    label: context.tr('Taip semula kata laluan', 'Type password again'),
                    autofillHints: const [AutofillHints.newPassword],
                    validator: (v) => Validators.confirmPassword(v, _password.text),
                    onSubmitted: _submit,
                  ),
                ] else
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ForgotPasswordView(initialEmail: _email.text.trim()),
                              ),
                            ),
                      child: Text(context.tr('Lupa kata laluan?', 'Forgot password?')),
                    ),
                  ),
                const SizedBox(height: 20),
                BadgeButton(
                  label: _isRegister ? context.tr('Daftar', 'Register') : context.tr('Log Masuk', 'Sign In'),
                  loading: _loading,
                  onPressed: _googleLoading ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleCard extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _GoogleCard({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: loading
          ? context.tr('Teruskan dengan Google. Sedang diproses', 'Continue with Google. Processing')
          : context.tr('Teruskan dengan Google. Paling pantas, tiada kata laluan.',
              'Continue with Google. Fastest, no password.'),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          side: BorderSide(color: p.border, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  onTap!();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: p.tint, shape: BoxShape.circle),
                  child: loading
                      ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: p.accent))
                      : Text('G',
                          style: TextStyle(
                              fontFamily: AppFonts.heading, fontSize: 22, fontWeight: FontWeight.w800, color: p.accent)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('Teruskan dengan Google', 'Continue with Google'),
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.textPrimary)),
                      const SizedBox(height: 2),
                      Text(context.tr('Paling pantas. Tiada kata laluan.', 'Fastest. No password.'),
                          style: TextStyle(fontSize: 15, color: p.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
