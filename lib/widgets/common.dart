import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Logo IrisVision. Hiasan sahaja: disembunyikan daripada TalkBack.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 140});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Image.asset(
        'assets/images/logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) =>
            Icon(Icons.visibility, size: size * 0.6, color: context.pal.accent),
      ),
    );
  }
}

/// Butang segi empat kecil (kembali, ikon header). Sasaran 52dp.
class SquareIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const SquareIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            onPressed();
          },
          child: SizedBox(width: 52, height: 52, child: Icon(icon, size: 28, color: p.textPrimary)),
        ),
      ),
    );
  }
}

/// Butang kembali standard IrisVision.
class BackSquare extends StatelessWidget {
  const BackSquare({super.key});

  @override
  Widget build(BuildContext context) => SquareIconButton(
        icon: Icons.chevron_left,
        tooltip: 'Kembali',
        onPressed: () => Navigator.of(context).maybePop(),
      );
}

/// Penunjuk langkah onboarding (1/2/3). TalkBack: "Langkah 2 daripada 3".
class StepDots extends StatelessWidget {
  final int step; // bermula 1
  final int total;
  const StepDots({super.key, required this.step, this.total = 3});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      label: 'Langkah $step daripada $total',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= total; i++) ...[
              if (i > 1) const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == step ? 32 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i <= step ? p.primary : p.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bar atas skrin onboarding: butang kembali + langkah.
class TopBar extends StatelessWidget {
  final int? step;
  final Widget? title;
  const TopBar({super.key, this.step, this.title});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const BackSquare(),
          if (title != null) ...[const SizedBox(width: 14), Expanded(child: title!)] else const Spacer(),
          if (step != null) StepDots(step: step!),
        ],
      ),
    );
  }
}

/// BUTANG TANDATANGAN IRISVISION: label di kiri, lencana kuning di kanan.
class BadgeButton extends StatelessWidget {
  final String label;
  final IconData badgeIcon;
  final VoidCallback? onPressed;
  final bool loading;

  const BadgeButton({
    super.key,
    required this.label,
    this.badgeIcon = Icons.arrow_forward,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final enabled = onPressed != null && !loading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? '$label. Sedang diproses' : label,
      excludeSemantics: true,
      onTap: enabled ? onPressed : null,
      child: Material(
        color: enabled ? p.primary : p.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        elevation: enabled ? 3 : 0,
        shadowColor: p.primary.withValues(alpha: 0.5),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: enabled
              ? () {
                  HapticFeedback.mediumImpact();
                  onPressed!();
                }
              : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: AppFonts.heading,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: enabled ? p.onPrimary : p.textSecondary,
                      ),
                    ),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: p.highlight, borderRadius: BorderRadius.circular(16)),
                    child: loading
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 3, color: p.onHighlight),
                          )
                        : Icon(badgeIcon, size: 28, color: p.onHighlight),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kawalan segmen (Log Masuk | Daftar, BM | EN, Tema).
class Segmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String semanticLabel;
  final bool highlightSelected; // true = kuning, false = warna utama

  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.highlightSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      label: semanticLabel,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            for (final (v, label) in options) ...[
              if (v != options.first.$1) const SizedBox(width: 6),
              Expanded(
                child: Semantics(
                  selected: v == value,
                  button: true,
                  child: Material(
                    color: v == value ? (highlightSelected ? p.highlight : p.primary) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onChanged(v);
                      },
                      child: SizedBox(
                        height: 52,
                        child: Center(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppFonts.heading,
                              fontSize: 17,
                              fontWeight: v == value ? FontWeight.w700 : FontWeight.w500,
                              color: v == value
                                  ? (highlightSelected ? p.onHighlight : p.onPrimary)
                                  : p.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kotak mesej ralat / berjaya. `liveRegion` = TalkBack terus baca bila muncul.
class StatusBanner extends StatelessWidget {
  final String message;
  final bool isError;
  const StatusBanner({super.key, required this.message, this.isError = true});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final color = isError ? p.error : p.success;
    return Semantics(
      liveRegion: true,
      container: true,
      label: '${isError ? 'Ralat' : 'Berjaya'}: $message',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isError ? color.withValues(alpha: 0.10) : p.successBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w700, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Medan kata laluan dengan butang tunjuk/sembunyi.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? helper;
  final String? Function(String?)? validator;
  final TextInputAction action;
  final Iterable<String> autofillHints;
  final VoidCallback? onSubmitted;

  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.validator,
    this.action = TextInputAction.done,
    this.autofillHints = const [AutofillHints.password],
    this.onSubmitted,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.action,
      autofillHints: widget.autofillHints,
      maxLength: 128,
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
      style: const TextStyle(fontSize: 20),
      validator: widget.validator,
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          iconSize: 28,
          tooltip: _obscure ? 'Tunjuk kata laluan' : 'Sembunyi kata laluan',
          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

/// Tajuk besar skrin (Lexend), ditanda heading untuk TalkBack.
class Headline extends StatelessWidget {
  final String text;
  final double size;
  const Headline(this.text, {super.key, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppFonts.heading,
          fontSize: size,
          fontWeight: FontWeight.w800,
          height: 1.12,
          color: context.pal.textPrimary,
        ),
      ),
    );
  }
}

/// SnackBar ringkas yang TalkBack akan baca.
void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
