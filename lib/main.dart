import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/providers/settings_provider.dart';
import 'ui/shared/app_shell.dart';
import 'ui/shared/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FlutterPlotterApp()));
}

class FlutterPlotterApp extends ConsumerWidget {
  const FlutterPlotterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nightMode = ref.watch(
      appSettingsProvider.select((s) => s.nightMode),
    );

    return MaterialApp(
      title: 'FlutterPlotter',
      theme: nightMode ? nightTheme : dayTheme,
      home: const AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}
