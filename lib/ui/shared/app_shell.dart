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
import '../instruments/instrument_sidebar.dart';
import 'responsive.dart';

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

    final layout = Responsive.of(context);

    switch (layout) {
      case LayoutSize.compact:
        return _buildCompactLayout(anyConnected, skConnected);
      case LayoutSize.medium:
        return _buildMediumLayout(anyConnected, skConnected);
      case LayoutSize.expanded:
        return _buildExpandedLayout(anyConnected, skConnected);
    }
  }

  /// Phone: bottom NavigationBar.
  Widget _buildCompactLayout(bool anyConnected, bool skConnected) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: _navDestinations(anyConnected, skConnected),
      ),
    );
  }

  /// Medium tablet / large phone: NavigationRail on left, no bottom nav.
  Widget _buildMediumLayout(bool anyConnected, bool skConnected) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            destinations: _railDestinations(anyConnected, skConnected),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: _screens),
          ),
        ],
      ),
    );
  }

  /// Large tablet: NavigationRail + persistent InstrumentSidebar on chart tab.
  Widget _buildExpandedLayout(bool anyConnected, bool skConnected) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            destinations: _railDestinations(anyConnected, skConnected),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          if (_selectedIndex == 0) const InstrumentSidebar(),
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: _screens),
          ),
        ],
      ),
    );
  }

  List<NavigationDestination> _navDestinations(
      bool anyConnected, bool skConnected) {
    return [
      const NavigationDestination(icon: Icon(Icons.map), label: 'Chart'),
      const NavigationDestination(icon: Icon(Icons.route), label: 'Routes'),
      NavigationDestination(
        icon: Badge(
          smallSize: 8,
          backgroundColor: anyConnected ? Colors.green : Colors.transparent,
          child: const Icon(Icons.sailing),
        ),
        label: 'AIS',
      ),
      NavigationDestination(
        icon: Badge(
          smallSize: 8,
          backgroundColor: skConnected ? Colors.green : Colors.transparent,
          child: const Icon(Icons.speed),
        ),
        label: 'Signal K',
      ),
      const NavigationDestination(icon: Icon(Icons.cloud), label: 'Weather'),
      const NavigationDestination(
          icon: Icon(Icons.settings), label: 'Settings'),
    ];
  }

  List<NavigationRailDestination> _railDestinations(
      bool anyConnected, bool skConnected) {
    return [
      const NavigationRailDestination(
          icon: Icon(Icons.map), label: Text('Chart')),
      const NavigationRailDestination(
          icon: Icon(Icons.route), label: Text('Routes')),
      NavigationRailDestination(
        icon: Badge(
          smallSize: 8,
          backgroundColor: anyConnected ? Colors.green : Colors.transparent,
          child: const Icon(Icons.sailing),
        ),
        label: const Text('AIS'),
      ),
      NavigationRailDestination(
        icon: Badge(
          smallSize: 8,
          backgroundColor: skConnected ? Colors.green : Colors.transparent,
          child: const Icon(Icons.speed),
        ),
        label: const Text('Signal K'),
      ),
      const NavigationRailDestination(
          icon: Icon(Icons.cloud), label: Text('Weather')),
      const NavigationRailDestination(
          icon: Icon(Icons.settings), label: Text('Settings')),
    ];
  }
}
