import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/nmea/nmea_stream.dart';
import '../../core/signalk/signalk_source.dart';
import '../../data/providers/nmea_config_provider.dart';
import '../../data/providers/signalk_provider.dart';
import '../ais/target_list_screen.dart';
import '../chart/chart_screen.dart';
import '../instruments/instrument_sidebar.dart';
import '../routes/route_list_screen.dart';
import '../settings/settings_screen.dart';
import '../signalk/signalk_dashboard.dart';
import '../weather/weather_screen.dart';

/// Provider to toggle the right panel visibility and content.
enum RightPanelContent { none, aisList, routeEditor, tidePanel }

final rightPanelProvider =
    StateProvider<RightPanelContent>((ref) => RightPanelContent.none);

/// Tablet shell layout with NavigationRail + InstrumentSidebar + chart + optional right panel.
class TabletShell extends ConsumerStatefulWidget {
  const TabletShell({super.key});

  @override
  ConsumerState<TabletShell> createState() => _TabletShellState();
}

class _TabletShellState extends ConsumerState<TabletShell> {
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
    final rightPanel = ref.watch(rightPanelProvider);

    return Scaffold(
      body: Row(
        children: [
          // Navigation Rail
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Icons.map),
                label: Text('Chart'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.route),
                label: Text('Routes'),
              ),
              NavigationRailDestination(
                icon: Badge(
                  smallSize: 8,
                  backgroundColor:
                      anyConnected ? Colors.green : Colors.transparent,
                  child: const Icon(Icons.sailing),
                ),
                label: const Text('AIS'),
              ),
              NavigationRailDestination(
                icon: Badge(
                  smallSize: 8,
                  backgroundColor:
                      skConnected ? Colors.green : Colors.transparent,
                  child: const Icon(Icons.speed),
                ),
                label: const Text('Signal K'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.cloud),
                label: Text('Weather'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),

          // Instrument sidebar (only visible on chart tab)
          if (_selectedIndex == 0) const InstrumentSidebar(),

          // Main content
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: _screens),
          ),

          // Optional right panel (280dp)
          if (_selectedIndex == 0 && rightPanel != RightPanelContent.none)
            SizedBox(
              width: 280,
              child: _buildRightPanel(rightPanel),
            ),
        ],
      ),
    );
  }

  Widget _buildRightPanel(RightPanelContent content) {
    switch (content) {
      case RightPanelContent.aisList:
        return const TargetListScreen();
      case RightPanelContent.routeEditor:
        return const RouteListScreen();
      case RightPanelContent.tidePanel:
        return const WeatherScreen();
      case RightPanelContent.none:
        return const SizedBox.shrink();
    }
  }
}
