import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class AppTheme {
  static TextTheme _buildTextTheme(TextTheme base, Color textColor) {
    // Body font: Nunito for supreme legibility on long texts.
    final body = GoogleFonts.nunitoTextTheme(base).apply(
      bodyColor: textColor,
      displayColor: textColor,
    );
    return body.copyWith(
      // Game-style pixel font for headers
      displayLarge: GoogleFonts.vt323(
        fontSize: 34,
        color: textColor,
      ),
      displayMedium: GoogleFonts.vt323(
        fontSize: 28,
        color: textColor,
      ),
      titleLarge: GoogleFonts.vt323(
        fontSize: 24,
        color: textColor,
      ),
      titleMedium: GoogleFonts.vt323(
        fontSize: 20,
        color: textColor,
      ),
      // Clean readable font for bodies and small titles
      titleSmall: GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
      bodyLarge: GoogleFonts.nunito(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        color: textColor,
      ),
      bodyMedium: GoogleFonts.nunito(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: textColor,
      ),
      bodySmall: GoogleFonts.nunito(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: textColor,
      ),
    );
  }

  static OutlinedBorder _pixelShape([double radius = 8]) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: AppColors.border, width: 2),
      );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: false,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    primaryColor: AppColors.primary,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      error: AppColors.error,
      onPrimary: AppColors.textPrimary,
      onSecondary: AppColors.textPrimary,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceHighlight,
      outline: AppColors.border,
    ),
    textTheme:
        _buildTextTheme(ThemeData.dark().textTheme, AppColors.textPrimary),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      elevation: 0,
      centerTitle: false,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: _pixelShape(),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        shape: _pixelShape(6),
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        minimumSize: const Size(48, 50),
        textStyle:
            GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryLight,
        textStyle:
            GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.border, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.border, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.all(14),
      hintStyle: const TextStyle(color: AppColors.textSecondary),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.background,
      indicatorColor: AppColors.surface,
      labelTextStyle: MaterialStateProperty.resolveWith<TextStyle?>((states) {
        final color = states.contains(MaterialState.selected)
            ? AppColors.primaryLight
            : AppColors.textSecondary;
        return GoogleFonts.nunito(
            fontSize: 12, fontWeight: FontWeight.w700, color: color);
      }),
      iconTheme: MaterialStateProperty.resolveWith<IconThemeData?>((states) {
        return IconThemeData(
          color: states.contains(MaterialState.selected)
              ? AppColors.primary
              : AppColors.textSecondary,
        );
      }),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: AppColors.border, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: _pixelShape(),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.primary,
      textColor: AppColors.textPrimary,
      tileColor: Colors.transparent,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceHighlight,
      selectedColor: AppColors.primary.withOpacity(0.25),
      disabledColor: AppColors.surfaceHighlight.withOpacity(0.6),
      labelStyle: GoogleFonts.nunito(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      secondaryLabelStyle: GoogleFonts.nunito(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      shape: _pixelShape(6),
      side: const BorderSide(color: AppColors.border, width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.surfaceHighlight),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceHighlight,
      contentTextStyle: GoogleFonts.nunito(
        color: AppColors.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
      ),
    ),
  );

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: false,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightBackground,
    primaryColor: AppColors.primary,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primaryDark,
      secondary: AppColors.secondary,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightTextPrimary,
      error: AppColors.error,
      outline: AppColors.lightBorder,
      surfaceContainerHighest: AppColors.lightSurfaceHighlight,
    ),
    textTheme: _buildTextTheme(
      ThemeData.light().textTheme,
      AppColors.lightTextPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.lightBackground,
      elevation: 0,
      centerTitle: false,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: AppColors.lightTextPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: IconThemeData(color: AppColors.lightTextPrimary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.lightBorder, width: 2),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: AppColors.lightBorder, width: 2),
        ),
        minimumSize: const Size(48, 50),
        textStyle: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.lightTextPrimary,
        side: const BorderSide(color: AppColors.lightBorder, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        minimumSize: const Size(48, 50),
        textStyle:
            GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryDark,
        textStyle:
            GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.lightBorder, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.lightBorder, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.primaryDark, width: 2),
      ),
      contentPadding: const EdgeInsets.all(14),
      hintStyle: const TextStyle(color: AppColors.lightTextSecondary),
      labelStyle: const TextStyle(color: AppColors.lightTextSecondary),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.lightBackground,
      indicatorColor: AppColors.lightSurfaceHighlight,
      labelTextStyle: MaterialStateProperty.resolveWith<TextStyle?>((states) {
        final color = states.contains(MaterialState.selected)
            ? AppColors.primaryDark
            : AppColors.lightTextSecondary;
        return GoogleFonts.nunito(
            fontSize: 12, fontWeight: FontWeight.w700, color: color);
      }),
      iconTheme: MaterialStateProperty.resolveWith<IconThemeData?>((states) {
        return IconThemeData(
          color: states.contains(MaterialState.selected)
              ? AppColors.primaryDark
              : AppColors.lightTextSecondary,
        );
      }),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.lightBorder, width: 2),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.primaryDark,
      textColor: AppColors.lightTextPrimary,
      tileColor: Colors.transparent,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.lightSurfaceHighlight,
      selectedColor: AppColors.primary.withOpacity(0.2),
      disabledColor: AppColors.lightSurfaceHighlight.withOpacity(0.7),
      labelStyle: GoogleFonts.nunito(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.lightTextPrimary,
      ),
      secondaryLabelStyle: GoogleFonts.nunito(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.lightTextPrimary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppColors.lightBorder, width: 1.5),
      ),
      side: const BorderSide(color: AppColors.lightBorder, width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.lightBorder),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.lightSurfaceHighlight,
      contentTextStyle: GoogleFonts.nunito(
        color: AppColors.lightTextPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
      ),
    ),
  );
}
