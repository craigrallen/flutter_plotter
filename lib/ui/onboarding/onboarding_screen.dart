import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../core/nmea/nmea_stream.dart';
import '../../data/providers/nmea_config_provider.dart';

const _kOnboardingCompleteKey = 'onboarding_complete';

/// Check whether onboarding has been completed.
Future<bool> isOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kOnboardingCompleteKey) ?? false;
}

/// Mark onboarding as done.
Future<void> setOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kOnboardingCompleteKey, true);
}

class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  final _hostController = TextEditingController(text: '');
  final _portController = TextEditingController(text: '10110');
  NmeaProtocol _protocol = NmeaProtocol.tcp;
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < 2) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finish() async {
    // Save NMEA config if host was provided
    final host = _hostController.text.trim();
    if (host.isNotEmpty) {
      final port = int.tryParse(_portController.text) ?? 10110;
      ref.read(nmeaConfigProvider.notifier).update(
            NmeaConfig(host: host, port: port, protocol: _protocol),
          );
    }

    await setOnboardingComplete();
    widget.onComplete();
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (mounted) {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _currentPage = i),
                physics: const ClampingScrollPhysics(),
                children: [
                  _buildWelcomePage(theme),
                  _buildNmeaPage(theme),
                  _buildGpsPage(theme),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SmoothPageIndicator(
                    controller: _controller,
                    count: 3,
                    effect: WormEffect(
                      dotColor: theme.colorScheme.surfaceContainerHighest,
                      activeDotColor: theme.colorScheme.primary,
                      dotHeight: 10,
                      dotWidth: 10,
                    ),
                  ),
                  if (_currentPage < 2)
                    FilledButton(
                      onPressed: _next,
                      child: const Text('Next'),
                    )
                  else
                    FilledButton(
                      onPressed: _requestLocationPermission,
                      child: const Text('Get Started'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sailing, size: 96, color: theme.colorScheme.primary),
          const SizedBox(height: 32),
          Text(
            'Welcome to Floatilla',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'A touch-first marine chart plotter for sailors.\n\n'
            'View charts, track your position, monitor AIS targets, '
            'and navigate routes — all from your phone or tablet.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNmeaPage(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          Icon(Icons.router, size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text(
            'NMEA Data Source',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Connect to your boat\'s NMEA network to receive AIS, '
            'depth, wind, and heading data. You can skip this and '
            'configure it later in Settings.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Host / IP address',
              hintText: 'e.g. 192.168.1.100',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: 'Port',
              hintText: '10110',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          SegmentedButton<NmeaProtocol>(
            segments: const [
              ButtonSegment(value: NmeaProtocol.tcp, label: Text('TCP')),
              ButtonSegment(value: NmeaProtocol.udp, label: Text('UDP')),
            ],
            selected: {_protocol},
            onSelectionChanged: (v) => setState(() => _protocol = v.first),
          ),
        ],
      ),
    );
  }

  Widget _buildGpsPage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.gps_fixed, size: 96, color: theme.colorScheme.primary),
          const SizedBox(height: 32),
          Text(
            'Location Access',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Floatilla needs GPS access to show your vessel '
            'position on the chart.\n\n'
            'Tap "Get Started" to grant permission and begin navigating.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
