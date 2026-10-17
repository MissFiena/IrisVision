import 'package:flutter/material.dart';

/// Palet IrisVision (Versi C).
///
/// CERAH (default): latar kelabu cair, teal gelap dari logo, kuning sebagai
/// "lencana" tandatangan IrisVision.
/// GELAP: latar navy, cyan logo, kuning. Untuk pengguna yang sensitif cahaya.
///
/// Semua pasangan teks/latar lepas WCAG 2.2 AAA (kontras >= 7:1), dan maksud
/// tidak bergantung pada warna sahaja (sentiasa ada ikon + teks).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color background;
  final Color surface; // kad putih / panel
  final Color surfaceAlt; // latar kawalan segmen
  final Color border; // sempadan lembut kad & butang kecil
  final Color inputBorder; // sempadan medan input (kontras tinggi)
  final Color primary; // butang utama & kad Kesan Objek
  final Color onPrimary;
  final Color highlight; // kuning: lencana, kad Imbas Teks
  final Color onHighlight;
  final Color tint; // latar ikon lembut
  final Color accent; // pautan & ikon aktif
  final Color textPrimary;
  final Color textSecondary;
  final Color error;
  final Color success;
  final Color successBg;

  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.inputBorder,
    required this.primary,
    required this.onPrimary,
    required this.highlight,
    required this.onHighlight,
    required this.tint,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.error,
    required this.success,
    required this.successBg,
  });

  /// Kontras: teks 15.9:1, putih atas teal 8.6:1, teks sekunder 8.4:1,
  /// navy atas kuning 13:1, ralat 7.5:1.
  static const light = AppPalette(
    background: Color(0xFFF4F7F8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE4E9EE),
    border: Color(0xFFC9D1D6),
    inputBorder: Color(0xFF1C2B33),
    primary: Color(0xFF00507A),
    onPrimary: Color(0xFFFFFFFF),
    highlight: Color(0xFFFFD60A),
    onHighlight: Color(0xFF0B1B24),
    tint: Color(0xFFD6ECF4),
    accent: Color(0xFF00507A),
    textPrimary: Color(0xFF0B1B24),
    textSecondary: Color(0xFF3A4A52),
    error: Color(0xFF9A1C14),
    success: Color(0xFF0A5A2F),
    successBg: Color(0xFFE3F3EA),
  );

  /// Kontras: teks 18.7:1, navy atas cyan 11.9:1, navy atas kuning 13.3:1,
  /// teks sekunder 14.3:1, ralat 11.0:1.
  static const dark = AppPalette(
    background: Color(0xFF04141C),
    surface: Color(0xFF0B2733),
    surfaceAlt: Color(0xFF0B2733),
    border: Color(0xFF1C4A5C),
    inputBorder: Color(0xFF5FB7CC),
    primary: Color(0xFF3DE0FF),
    onPrimary: Color(0xFF04141C),
    highlight: Color(0xFFFFD60A),
    onHighlight: Color(0xFF04141C),
    tint: Color(0xFF12394A),
    accent: Color(0xFF3DE0FF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFC9E6EE),
    error: Color(0xFFFFB4A1),
    success: Color(0xFF7CF5B0),
    successBg: Color(0xFF0F3A2A),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      border: l(border, other.border),
      inputBorder: l(inputBorder, other.inputBorder),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      highlight: l(highlight, other.highlight),
      onHighlight: l(onHighlight, other.onHighlight),
      tint: l(tint, other.tint),
      accent: l(accent, other.accent),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      error: l(error, other.error),
      success: l(success, other.success),
      successBg: l(successBg, other.successBg),
    );
  }
}

/// Akses ringkas: `context.pal.primary`
extension PaletteX on BuildContext {
  AppPalette get pal => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

/// Nama font (disimpan dalam app, berfungsi offline).
class AppFonts {
  AppFonts._();
  static const String heading = 'Lexend';
  static const String body = 'Atkinson';
}

class AppTheme {
  AppTheme._();

  static const double minTapHeight = 64;
  static const double radius = 22;

  static ThemeData light() => _build(AppPalette.light, Brightness.light);
  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: p.highlight,
      onSecondary: p.onHighlight,
      error: p.error,
      onError: p.surface,
      surface: p.surface,
      onSurface: p.textPrimary,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      fontFamily: AppFonts.body,
      extensions: [p],
    );
    final text = base.textTheme.apply(
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
      fontFamily: AppFonts.body,
    );
    TextStyle? head(TextStyle? s, double size, FontWeight w) =>
        s?.copyWith(fontFamily: AppFonts.heading, fontSize: size, fontWeight: w, height: 1.12);

    return base.copyWith(
      textTheme: text.copyWith(
        displaySmall: head(text.displaySmall, 38, FontWeight.w800),
        headlineLarge: head(text.headlineLarge, 32, FontWeight.w800),
        headlineMedium: head(text.headlineMedium, 28, FontWeight.w800),
        titleLarge: head(text.titleLarge, 22, FontWeight.w700),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 18, height: 1.42),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 16, height: 1.4),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.heading,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        labelStyle: TextStyle(fontSize: 18, color: p.textSecondary),
        floatingLabelStyle: TextStyle(fontSize: 18, color: p.accent, fontWeight: FontWeight.w700),
        helperStyle: TextStyle(fontSize: 15, color: p.textSecondary),
        helperMaxLines: 3,
        errorStyle: TextStyle(fontSize: 16, color: p.error, fontWeight: FontWeight.w700),
        errorMaxLines: 3,
        prefixIconColor: p.accent,
        suffixIconColor: p.accent,
        border: _box(p.inputBorder, 2),
        enabledBorder: _box(p.inputBorder, 2),
        focusedBorder: _box(p.primary, 3),
        errorBorder: _box(p.error, 2),
        focusedErrorBorder: _box(p.error, 3),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.textPrimary,
        contentTextStyle: TextStyle(fontFamily: AppFonts.body, fontSize: 18, color: p.background, fontWeight: FontWeight.w700),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontFamily: AppFonts.heading, fontSize: 22, fontWeight: FontWeight.w700, color: p.textPrimary),
        contentTextStyle: TextStyle(fontFamily: AppFonts.body, fontSize: 18, height: 1.42, color: p.textPrimary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1.5, space: 1),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.highlight : p.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primary : p.surfaceAlt,
        ),
      ),
    );
  }

  static OutlineInputBorder _box(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c, width: w),
      );
}
