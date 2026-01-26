import 'package:flutter/material.dart';

class AppColors {
  // Primary Palette (Vibrant Blue)
  static const Color primary = Color(0xFF2563EB); // blue-600
  static const Color primaryDark = Color(0xFF1D4ED8); // blue-700
  static const Color primaryLight = Color(0xFF60A5FA); // blue-400
  
  // Secondary Palette (Teal/Emerald)
  static const Color secondary = Color(0xFF0D9488); // teal-600
  
  // Backgrounds (Deep Slate for Dark Mode)
  static const Color background = Color(0xFF0F172A); // slate-900
  static const Color surface = Color(0xFF1E293B); // slate-800
  static const Color surfaceHighlight = Color(0xFF334155); // slate-700
  
  // Text Colors
  static const Color textPrimary = Color(0xFFF8FAFC); // slate-50
  static const Color textSecondary = Color(0xFF94A3B8); // slate-400
  static const Color textTertiary = Color(0xFF64748B); // slate-500

  // Functional Colors
  static const Color error = Color(0xFFEF4444); // red-500
  static const Color success = Color(0xFF22C55E); // green-500
  static const Color warning = Color(0xFFEAB308); // yellow-500
  
  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF4F46E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
