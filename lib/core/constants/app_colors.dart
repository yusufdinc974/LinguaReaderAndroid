import 'package:flutter/material.dart';

class AppColors {
  // Fox-inspired primary accents.
  static const Color primary = Color(0xFFDF7B31);
  static const Color primaryDark = Color(0xFFAF4E1D);
  static const Color primaryLight = Color(0xFFF2A76A);
  
  // Secondary action (Muted Teal to contrast Orange).
  static const Color secondary = Color(0xFF3D8E86);

  // Dark mode surfaces (Slate / Blue-Grey).
  static const Color background = Color(0xFF161920);
  static const Color surface = Color(0xFF1F232D);
  static const Color surfaceHighlight = Color(0xFF2C3240);
  static const Color border = Color(0xFF3A4254);

  // Light mode surfaces (Clean Off-White Slate).
  static const Color lightBackground = Color(0xFFF3F4F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceHighlight = Color(0xFFE5E7EB);
  static const Color lightBorder = Color(0xFFD1D5DB);

  // Text colors.
  static const Color textPrimary = Color(0xFFF9FAFB);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textTertiary = Color(0xFF6B7280);
  static const Color lightTextPrimary = Color(0xFF111827);
  static const Color lightTextSecondary = Color(0xFF374151); // Darkened for contrast
  static const Color lightTextTertiary = Color(0xFF4B5563);

  // Functional Colors
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFDF7B31), Color(0xFFCF6422)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFF1F232D), Color(0xFF1A1D25)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
