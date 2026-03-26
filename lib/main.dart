import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/shared/app_shell.dart';
import 'ui/shared/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FlutterPlotterApp()));
}

class FlutterPlotterApp extends StatelessWidget {
  const FlutterPlotterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlutterPlotter',
      theme: dayTheme,
      darkTheme: nightTheme,
      home: const AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}
