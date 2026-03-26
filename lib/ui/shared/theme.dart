import 'package:flutter/material.dart';

/// Day theme — standard marine chart look.
final ThemeData dayTheme = ThemeData(
  brightness: Brightness.light,
  colorSchemeSeed: Colors.blue,
  useMaterial3: true,
  scaffoldBackgroundColor: Colors.white,
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
  navigationBarTheme: NavigationBarThemeData(
    indicatorColor: Colors.red.shade900,
    backgroundColor: const Color(0xFF200000),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF200000),
  ),
);
