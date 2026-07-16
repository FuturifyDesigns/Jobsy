import 'package:flutter/material.dart';

class JobsyColors {
  // ── Core brand — aggressive recruitment agency ──
  static const Color primary = Color(0xFF0A0A0A);
  static const Color primaryLight = Color(0xFF121212);
  static const Color accent = Color(0xFF1A1A1A);
  static const Color accentLight = Color(0xFF52525B);

  // ── Role accents — Jobsy J logo palette ──
  /// Employer — bright white / silver (logo highlight).
  static const Color employerPrimary = Color(0xFFF8FAFC);
  static const Color employerDark = Color(0xFFE2E8F0);

  /// Worker — slate grey (logo body), bright enough to read on black.
  static const Color workerPrimary = Color(0xFFCBD5E1);
  static const Color workerDark = Color(0xFF94A3B8);

  // ── Surfaces — near-black ──
  static const Color background = Color(0xFF020204);
  static const Color surface = Color(0xFF08080C);
  static const Color surfaceLight = Color(0xFF0E0E14);
  static const Color surfaceElevated = Color(0xFF14141C);
  static const Color navBarBackground = Color(0xFF040406);
  static const Color agencyNavy = Color(0xFF0A0A10);

  // ── Text ──
  static const Color textPrimary = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textTertiary = Color(0xFF71717A);
  static const Color textOnPrimary = Color(0xFFFAFAFA);

  // ── Status ──
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF94A3B8);

  // ── Borders ──
  static const Color border = Color(0xFF27272A);
  static const Color borderLight = Color(0xFF3F3F46);
  static const Color divider = Color(0xFF18181B);

  static const List<Color> metallicGradient = [
    Color(0xFFE4E4E7),
    Color(0xFFA1A1AA),
    Color(0xFF52525B),
    Color(0xFF27272A),
  ];

  static const List<Color> employerGradient = [
    Color(0xFFFAFAFA),
    Color(0xFFE2E8F0),
    Color(0xFFCBD5E1),
  ];

  static const List<Color> workerGradient = [
    Color(0xFFE2E8F0),
    Color(0xFFCBD5E1),
    Color(0xFF94A3B8),
  ];

  /// Neutral auth / welcome (opening screens unchanged).
  static const List<Color> brandGradient = [
    Color(0xFF53789E),
    Color(0xFF0F3460),
    Color(0xFF1A1A2E),
  ];

  static const Color webJobsAccent = Color(0xFFA1A1AA);

  static const Color inputBackground = Color(0xFF0E0E14);
  static const Color inputBorder = Color(0xFF27272A);
  static const Color inputFocusBorder = Color(0xFF94A3B8);

  /// Text/icon on role accent fills — dark on white employer, light on grey worker.
  static Color onRoleAccent(Color accent) =>
      accent.computeLuminance() > 0.55 ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA);

  static const Color employerOnAccent = Color(0xFF0A0A0A);
  static const Color workerOnAccent = Color(0xFF0A0A0A);

  static bool isLightAccent(Color color) => color.computeLuminance() > 0.55;

  /// Filled CTA on a role accent — picks readable label color automatically.
  static ButtonStyle roleFilledButtonStyle(
    Color accent, {
    EdgeInsetsGeometry? padding,
    double radius = 12,
    double elevation = 0,
  }) =>
      ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onRoleAccent(accent),
        disabledBackgroundColor: accent.withValues(alpha: 0.5),
        disabledForegroundColor: onRoleAccent(accent).withValues(alpha: 0.5),
        padding: padding ?? const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        elevation: elevation,
      );

  /// Filled employer CTA — silver button, dark label.
  static ButtonStyle employerFilledButtonStyle({
    EdgeInsetsGeometry? padding,
    double radius = 12,
  }) =>
      roleFilledButtonStyle(employerPrimary, padding: padding, radius: radius);

  static ButtonStyle workerFilledButtonStyle({
    EdgeInsetsGeometry? padding,
    double radius = 12,
  }) =>
      roleFilledButtonStyle(workerPrimary, padding: padding, radius: radius);

  static const TextStyle employerGradientLabelStyle = TextStyle(
    fontWeight: FontWeight.w700,
    color: employerOnAccent,
  );

  static const TextStyle workerGradientLabelStyle = TextStyle(
    fontWeight: FontWeight.w700,
    color: workerOnAccent,
  );

  /// Chips / badges using a role accent on dark surfaces.
  static BoxDecoration roleChipDecoration(Color accent) => BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      );

  static TextStyle roleChipTextStyle(Color accent) => TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: accent,
        letterSpacing: 0.3,
      );

  /// Profile cover fallbacks — dark metallic (logo sits on charcoal).
  static const List<Color> employerCoverGradient = [
    Color(0xFF27272A),
    Color(0xFF3F3F46),
    Color(0xFF18181B),
  ];

  static const List<Color> workerCoverGradient = [
    Color(0xFF52525B),
    Color(0xFF3F3F46),
    Color(0xFF27272A),
  ];

  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;
  static const double spacingXl = 32;
  static const double spacingXxl = 48;

  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;
  static const double radiusFull = 100;
}
