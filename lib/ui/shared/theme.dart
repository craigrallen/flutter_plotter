import 'package:flutter/material.dart';

/// Explicit text theme with minimum sizes for outdoor readability.
/// Body text >= 14sp, labels >= 12sp, instrument values >= 20sp.
const _textTheme = TextTheme(
  displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.w400),
  displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w400),
  displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w400),
  headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w400),
  headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w400),
  headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w400),
  titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
  titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
  titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
  bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
  bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
  bodySmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
  labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
  labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
  labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
);

/// Day theme — standard marine chart look.
final ThemeData dayTheme = ThemeData(
  brightness: Brightness.light,
  colorSchemeSeed: Colors.blue,
  useMaterial3: true,
  scaffoldBackgroundColor: Colors.white,
  textTheme: _textTheme,
  navigationBarTheme: const NavigationBarThemeData(
    indicatorColor: Colors.blueAccent,
  ),
);

/// Night theme — red-tinted to preserve dark adaptation.
final ThemeData nightTheme = ThemeData(
  brightness: Brightness.dark,
  colorSchemeSeed: Colors.red,
  useMaterial3: true,
  scaffoldBackgroundColor: const Color(0xFF1A0000),
  textTheme: _textTheme,
  navigationBarTheme: NavigationBarThemeData(
    indicatorColor: Colors.red.shade900,
    backgroundColor: const Color(0xFF200000),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF200000),
  ),
);

/// High-contrast theme for outdoor readability (white text on dark).
final ThemeData highContrastTheme = ThemeData(
  brightness: Brightness.dark,
  colorSchemeSeed: Colors.blue,
  useMaterial3: true,
  scaffoldBackgroundColor: Colors.black,
  textTheme: _textTheme.apply(
    bodyColor: Colors.white,
    displayColor: Colors.white,
  ),
  navigationBarTheme: NavigationBarThemeData(
    indicatorColor: Colors.blueAccent,
    backgroundColor: Colors.grey.shade900,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.grey.shade900,
    foregroundColor: Colors.white,
  ),
);
