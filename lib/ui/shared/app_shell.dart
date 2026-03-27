import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/nmea/nmea_stream.dart';
import '../../core/signalk/signalk_source.dart';
import '../../data/providers/nmea_config_provider.dart';
import '../../data/providers/signalk_provider.dart';
import '../chart/chart_screen.dart';
import '../routes/route_list_screen.dart';
import '../ais/target_list_screen.dart';
import '../settings/settings_screen.dart';
import '../signalk/signalk_dashboard.dart';
import '../weather/weather_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;

  static const _screens = <Widget>[
    ChartScreen(),
    RouteListScreen(),
    TargetListScreen(),
    SignalKDashboard(),
    WeatherScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(nmeaConnectionStateProvider);
    final skConnState = ref.watch(signalKConnectionStateProvider);

    final isConnected = connState.when(
      data: (s) => s == NmeaConnectionState.connected,
      loading: () => false,
      error: (_, _) => false,
    );
    final skConnected = skConnState == SignalKConnectionState.connected;
    final anyConnected = isConnected || skConnected;

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.map), label: 'Chart'),
          const NavigationDestination(icon: Icon(Icons.route), label: 'Routes'),
          NavigationDestination(
            icon: Badge(
              smallSize: 8,
              backgroundColor:
                  anyConnected ? Colors.green : Colors.transparent,
              child: const Icon(Icons.sailing),
            ),
            label: 'AIS',
          ),
          NavigationDestination(
            icon: Badge(
              smallSize: 8,
              backgroundColor:
                  skConnected ? Colors.green : Colors.transparent,
              child: const Icon(Icons.speed),
            ),
            label: 'Signal K',
          ),
          const NavigationDestination(
              icon: Icon(Icons.cloud), label: 'Weather'),
          const NavigationDestination(
              icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
