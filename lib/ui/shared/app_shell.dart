import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/nmea/nmea_stream.dart';
import '../../data/providers/nmea_config_provider.dart';
import '../chart/chart_screen.dart';
import '../routes/route_list_screen.dart';
import '../ais/target_list_screen.dart';
import '../settings/settings_screen.dart';

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
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(nmeaConnectionStateProvider);
    final isConnected = connState.when(
      data: (s) => s == NmeaConnectionState.connected,
      loading: () => false,
      error: (_, _) => false,
    );

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
              backgroundColor: isConnected ? Colors.green : Colors.transparent,
              child: const Icon(Icons.sailing),
            ),
            label: 'AIS',
          ),
          const NavigationDestination(
              icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
