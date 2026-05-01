// lib/theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Primary teal gradient colors
  static const Color primaryStart = Color(0xFF006D77); // Unified Premium Teal
  static const Color primaryStartDark = Color(0xFF004D54);
  static const Color primaryEnd = Color(0xFF83C5BE);
  static const Color primaryLight = Color(0xFFE8F4F6);
  
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
  static TextStyle heading(double size, {FontWeight weight = FontWeight.w700, Color color = textPrimary}) =>
      GoogleFonts.poppins(color: color, fontSize: size, fontWeight: weight);

  static TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color color = textMid}) =>
      GoogleFonts.poppins(color: color, fontSize: size, fontWeight: weight);

  static TextStyle button(double size, {Color color = Colors.white}) =>
      GoogleFonts.poppins(color: color, fontSize: size, fontWeight: FontWeight.w700);

  // Helper decorations
  static BoxDecoration roundedBox({Color? color, double radius = 12, List<BoxShadow>? shadows, Gradient? gradient}) =>
      BoxDecoration(
        color: color ?? (gradient == null ? surface : null),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadows,
        gradient: gradient,
      );

  static ButtonStyle elevatedButtonStyle({Color? background, Color? foreground, double radius = 14}) =>
      ElevatedButton.styleFrom(
        backgroundColor: background ?? primaryStart,
        foregroundColor: foreground ?? Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        elevation: 4,
        shadowColor: primaryStart.withOpacity(0.3),
      );
}
