import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF6750A4);
  static const Color secondaryColor = Color(0xFF625B71);
  static const Color tertiaryColor = Color(0xFF7D5260);
  static const Color errorColor = Color(0xFFBA1A1A);

  // Dark theme colors
  static const Color darkSurfaceColor = Color(0xFF1C1B1F);
  static const Color darkOnSurfaceColor = Color(0xFFE6E1E5);
  static const Color darkSurfaceVariantColor = Color(0xFF49454F);
  static const Color darkBackgroundColor = Color(0xFF121212);
  static const Color darkCardColor = Color(0xFF2C2C2C);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
        background: darkBackgroundColor,
        surface: darkSurfaceColor,
        onSurface: darkOnSurfaceColor,
        surfaceVariant: darkSurfaceVariantColor,
      ),
      scaffoldBackgroundColor: darkBackgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurfaceColor,
        foregroundColor: darkOnSurfaceColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: darkOnSurfaceColor),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkSurfaceVariantColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkSurfaceVariantColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor),
        ),
        filled: true,
        fillColor: darkSurfaceVariantColor.withOpacity(0.3),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        hintStyle: TextStyle(color: darkOnSurfaceColor.withOpacity(0.6)),
      ),
      cardTheme: CardThemeData(
        color: darkCardColor,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: darkOnSurfaceColor),
        bodyMedium: TextStyle(color: darkOnSurfaceColor),
        bodySmall: TextStyle(color: darkOnSurfaceColor),
        titleLarge: TextStyle(color: darkOnSurfaceColor),
        titleMedium: TextStyle(color: darkOnSurfaceColor),
        titleSmall: TextStyle(color: darkOnSurfaceColor),
      ),
      iconTheme: const IconThemeData(color: darkOnSurfaceColor),
      dividerTheme: const DividerThemeData(color: darkSurfaceVariantColor),
    );
  }
}
