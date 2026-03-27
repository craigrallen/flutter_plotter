import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/providers/settings_provider.dart';
import 'ui/onboarding/onboarding_screen.dart';
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
      home: const _Home(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final done = await isOnboardingComplete();
    if (mounted) setState(() => _onboardingDone = done);
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingDone == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_onboardingDone!) {
      return OnboardingScreen(
        onComplete: () => setState(() => _onboardingDone = true),
      );
    }
    return const AppShell();
  }
}
