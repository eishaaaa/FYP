// lib/theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Primary teal gradient colors
  static const Color primaryStart = Color(0xFF006D77); // Unified Premium Teal
  static const Color primaryStartDark = Color(0xFF004D54);
  static const Color primaryEnd = Color(0xFF83C5BE);
  static const Color primaryLight = Color(0xFFE8F4F6);
  static const Color darkBackground = Color(0xFF0F1719);
  static const Color darkSurface = Color(0xFF162125);
  static const Color darkSurfaceAlt = Color(0xFF1D2A2E);
  static const Color darkSurfaceSoft = Color(0xFF223237);
  static const Color darkBorder = Color(0xFF2D4348);
  static const Color darkTextPrimary = Color(0xFFF3F7F8);
  static const Color darkTextSecondary = Color(0xFF9FB2B7);

  static const Gradient primaryGradient = LinearGradient(
    colors: [primaryStartDark, primaryStart, primaryEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Accent, surface and error colors
  static const Color accent = Color(0xFFE29578); // Soft Coral Accent
  static const Color surface = Colors.white;
  static const Color error = Color(0xFFD90429);
  static const Color background = Color(0xFFF8F9FA);

  // Text colors
  static const Color textPrimary = Color(0xFF2B2D42);
  static const Color textMid = Color(0xFF8D99AE);
  static const Color textSecondary = Color(0xFFADB5BD);
  static const Color textLight = Color(0xFFADB5BD);

  // Typography – all using Poppins
  static TextStyle heading(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color color = textPrimary,
  }) => GoogleFonts.poppins(color: color, fontSize: size, fontWeight: weight);

  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = textMid,
  }) => GoogleFonts.poppins(color: color, fontSize: size, fontWeight: weight);

  static TextStyle button(double size, {Color color = Colors.white}) =>
      GoogleFonts.poppins(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w700,
      );

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color scaffoldColor(BuildContext context) =>
      isDark(context) ? darkBackground : background;

  static Color surfaceColor(BuildContext context) =>
      isDark(context) ? darkSurface : surface;

  static Color elevatedSurfaceColor(BuildContext context) =>
      isDark(context) ? darkSurfaceAlt : surface;

  static Color mutedSurfaceColor(BuildContext context) =>
      isDark(context) ? darkSurfaceSoft : const Color(0xFFF0F4F4);

  static Color inputFillColor(BuildContext context) =>
      isDark(context) ? darkSurfaceSoft : background;

  static Color primaryTextColor(BuildContext context) =>
      isDark(context) ? darkTextPrimary : textPrimary;

  static Color secondaryTextColor(BuildContext context) =>
      isDark(context) ? darkTextSecondary : textSecondary;

  static Color subduedTextColor(BuildContext context) =>
      isDark(context) ? darkTextSecondary.withOpacity(0.88) : textMid;

  static Color borderColor(BuildContext context) =>
      isDark(context) ? darkBorder : const Color(0xFFCAE8E8);

  static Color shadowColor(BuildContext context) => isDark(context)
      ? Colors.black.withOpacity(0.28)
      : Colors.black.withOpacity(0.05);

  static BoxDecoration panelDecoration(
    BuildContext context, {
    Color? color,
    double radius = 16,
    Gradient? gradient,
    List<BoxShadow>? shadows,
  }) {
    final hasGradient = gradient != null;
    return BoxDecoration(
      color: hasGradient ? null : (color ?? surfaceColor(context)),
      borderRadius: BorderRadius.circular(radius),
      gradient: gradient,
      border: hasGradient ? null : Border.all(color: borderColor(context)),
      boxShadow:
          shadows ??
          [
            BoxShadow(
              color: shadowColor(context),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
    );
  }

  // Helper decorations
  static BoxDecoration roundedBox({
    Color? color,
    double radius = 12,
    List<BoxShadow>? shadows,
    Gradient? gradient,
  }) => BoxDecoration(
    color: color ?? (gradient == null ? surface : null),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: shadows,
    gradient: gradient,
  );

  static ButtonStyle elevatedButtonStyle({
    Color? background,
    Color? foreground,
    double radius = 14,
  }) => ElevatedButton.styleFrom(
    backgroundColor: background ?? primaryStart,
    foregroundColor: foreground ?? Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    elevation: 4,
    shadowColor: primaryStart.withOpacity(0.3),
  );
}

extension AppThemeContext on BuildContext {
  bool get isDarkMode => AppTheme.isDark(this);
  Color get appScaffold => AppTheme.scaffoldColor(this);
  Color get appSurface => AppTheme.surfaceColor(this);
  Color get appSurfaceAlt => AppTheme.elevatedSurfaceColor(this);
  Color get appSurfaceMuted => AppTheme.mutedSurfaceColor(this);
  Color get appInputFill => AppTheme.inputFillColor(this);
  Color get appTextPrimary => AppTheme.primaryTextColor(this);
  Color get appTextSecondary => AppTheme.secondaryTextColor(this);
  Color get appTextMuted => AppTheme.subduedTextColor(this);
  Color get appBorder => AppTheme.borderColor(this);
  Color get appShadow => AppTheme.shadowColor(this);
}
