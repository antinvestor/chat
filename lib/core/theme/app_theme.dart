import 'package:flutter/material.dart';

/// App theme following the design system guidelines
class AppTheme {
  // Color Palette
  static const Color primaryGreen = Color(0xFF128C7E); // Teal Green - Identity
  static const Color brightGreen = Color(
    0xFF25D366,
  ); // Bright Green - Actions/Success
  static const Color surfaceLight = Color(0xFFFFFFFF); // Chat Background
  static const Color surfaceLightAlt = Color(
    0xFFECE5DD,
  ); // Alternative Light Surface
  static const Color surfaceDark = Color(0xFF121B22); // Dark Surface
  static const Color surfaceDarkAlt = Color(
    0xFF0B141A,
  ); // Alternative Dark Surface

  // Text Styles
  static const TextStyle headerText = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  static const TextStyle bodyText = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: Colors.white,
  );

  static const TextStyle metadataText = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: Colors.white70,
  );

  static const TextStyle buttonText = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: Colors.white,
  );

  // Spacing constants
  static const double standardMargin = 16.0;
  static const double elementGap = 8.0;
  static const double minTouchTarget = 48.0;

  // Light Theme
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryGreen,
      brightness: Brightness.light,
    ),
    textTheme: const TextTheme(
      bodyLarge: bodyText,
      bodyMedium: bodyText,
      bodySmall: metadataText,
      headlineLarge: headerText,
      headlineMedium: headerText,
      headlineSmall: headerText,
      labelLarge: buttonText,
      labelMedium: buttonText,
      labelSmall: buttonText,
    ),
    scaffoldBackgroundColor: surfaceLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryGreen,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: headerText,
    ),
    cardTheme: CardThemeData(
      color: surfaceLightAlt,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: surfaceDarkAlt, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryGreen,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: buttonText,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceLightAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: surfaceDarkAlt),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: surfaceDarkAlt),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primaryGreen, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    iconTheme: const IconThemeData(color: surfaceDark, size: 24),
    dividerTheme: const DividerThemeData(
      color: surfaceDarkAlt,
      thickness: 1,
      space: 1,
    ),
    splashFactory: InkRipple.splashFactory,
    highlightColor: Colors.transparent,
  );

  // Dark Theme
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryGreen,
      brightness: Brightness.dark,
    ),
    textTheme: const TextTheme(
      bodyLarge: bodyText,
      bodyMedium: bodyText,
      bodySmall: metadataText,
      headlineLarge: headerText,
      headlineMedium: headerText,
      headlineSmall: headerText,
      labelLarge: buttonText,
      labelMedium: buttonText,
      labelSmall: buttonText,
    ),
    scaffoldBackgroundColor: surfaceDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: surfaceDarkAlt,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: headerText,
    ),
    cardTheme: CardThemeData(
      color: surfaceDarkAlt,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: surfaceLightAlt, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: buttonText,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceDarkAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: surfaceLightAlt),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: surfaceLightAlt),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primaryGreen, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    iconTheme: const IconThemeData(color: Colors.white70, size: 24),
    dividerTheme: const DividerThemeData(
      color: surfaceLightAlt,
      thickness: 1,
      space: 1,
    ),
    splashFactory: InkRipple.splashFactory,
    highlightColor: Colors.transparent,
  );

  // Get theme based on system brightness
  static ThemeData getTheme(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    return brightness == Brightness.dark ? darkTheme : lightTheme;
  }

  // Get subtle color (10% opacity)
  static Color getSubtleColor(BuildContext context, Color baseColor) {
    return baseColor.withValues(alpha: 0.1);
  }

  // Get text color based on theme
  static Color getTextColor(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    return brightness == Brightness.dark ? Colors.white : surfaceDark;
  }

  // Get chat background color based on theme
  static Color getChatBackground(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    return brightness == Brightness.dark ? surfaceDarkAlt : surfaceLightAlt;
  }

  // Get message bubble color based on theme and ownership
  static Color getMessageBubbleColor(BuildContext context, bool isOwnMessage) {
    final brightness = MediaQuery.of(context).platformBrightness;
    if (isOwnMessage) {
      return primaryGreen;
    } else {
      return brightness == Brightness.dark
          ? const Color(0xFF2A3942)
          : const Color(0xFFE5DDD5);
    }
  }

  // Get message text color based on ownership
  static Color getMessageTextColor(BuildContext context, bool isOwnMessage) {
    if (isOwnMessage) {
      return Colors.white;
    } else {
      final brightness = MediaQuery.of(context).platformBrightness;
      return brightness == Brightness.dark ? Colors.white : surfaceDark;
    }
  }
}
