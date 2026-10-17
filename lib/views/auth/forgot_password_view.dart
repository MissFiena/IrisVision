import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';

class ForgotPasswordView extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordView({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(text: widget.initialEmail);
  bool _loading = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _loading = true);
    final result = await AuthService.instance.sendPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _sent = result.ok;
      _error = result.ok ? null : result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            children: [
              const TopBar(),
              const SizedBox(height: 18),
              const Headline('Lupa kata laluan?'),
              const SizedBox(height: 8),
              Text(
                'Masukkan e-mel akaun anda. Kami hantar pautan untuk cipta kata laluan baharu.',
                style: TextStyle(fontSize: 18, height: 1.4, color: p.textSecondary),
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[
                StatusBanner(message: _error!),
                const SizedBox(height: 16),
              ],
              if (_sent) ...[
                // Mesej sama sama ada e-mel wujud atau tidak (elak account enumeration)
                const StatusBanner(
                  isError: false,
                  message: 'Jika e-mel ini berdaftar, pautan tetapan semula telah dihantar. '
                      'Semak peti masuk dan folder spam.',
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                style: const TextStyle(fontSize: 20),
                validator: Validators.email,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(labelText: 'E-mel', prefixIcon: Icon(Icons.email_outlined)),
              ),
              const SizedBox(height: 24),
              BadgeButton(
                label: _sent ? 'Hantar semula' : 'Hantar pautan',
                badgeIcon: Icons.send,
                loading: _loading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
