import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/floatilla/floatilla_models.dart';
import '../../core/nmea/nmea_stream.dart';
import '../../core/signalk/signalk_source.dart';
import '../../data/providers/data_source_provider.dart';
import '../../data/providers/floatilla_provider.dart';
import '../../data/providers/nmea_config_provider.dart';
import '../../data/providers/route_provider.dart';
import '../../data/providers/signalk_provider.dart';
import '../../data/models/waypoint.dart';
import '../chart/chart_screen.dart';
import '../routes/route_list_screen.dart';
import '../ais/target_list_screen.dart';
import '../settings/settings_screen.dart';
import '../signalk/signalk_dashboard.dart';
import '../weather/weather_screen.dart';
import '../floatilla/logbook_screen.dart';
import '../floatilla/floatilla_shell.dart';
import '../floatilla/mob_overlay.dart';
import '../floatilla/polar_performance_screen.dart';
import '../floatilla/tidal_currents_screen.dart';
import '../floatilla/ais_cpa_screen.dart';
import '../floatilla/ais_history_trail_screen.dart';
import '../floatilla/deviation_table_screen.dart';
import '../floatilla/race_start_timer_screen.dart';
import '../floatilla/dead_reckoning_screen.dart';
import '../floatilla/celestial_nav_screen.dart';
import '../floatilla/sar_pattern_screen.dart';
import '../floatilla/radar_simulator_screen.dart';
import '../floatilla/nmea_mux_screen.dart';
import '../floatilla/passage_plan_screen.dart';
import '../floatilla/passage_briefing_screen.dart';
import '../floatilla/engine_dashboard_screen.dart';
import '../floatilla/anchor_scope_screen.dart';
import '../floatilla/anchorage_screen.dart';
import '../floatilla/departure_planner_screen.dart';
import '../floatilla/tidal_gate_screen.dart';
import '../floatilla/cloud_logbook_screen.dart';
import '../floatilla/boat_health_screen.dart';
import '../floatilla/track_comparison_screen.dart';
import '../floatilla/voyage_logger_screen.dart';
import '../instruments/instrument_sidebar.dart';
import 'responsive.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;
  bool _autoConnectDone = false;

  @override
  void initState() {
    super.initState();
    // Auto-reconnect Signal K / NMEA after the first frame, once the
    // DataSourceNotifier has finished loading from SharedPreferences.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoConnect();
    });
  }

  Future<void> _maybeAutoConnect() async {
    if (_autoConnectDone) return;
    _autoConnectDone = true;
    // Small delay to let DataSourceNotifier._load() complete.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    final config = ref.read(dataSourceProvider);
    if (config.isSignalK && config.host.isNotEmpty) {
      final skState = ref.read(signalKProvider).connectionState;
      if (skState == SignalKConnectionState.disconnected) {
        await ref.read(signalKProvider.notifier).connect(
              host: config.host,
              port: config.port,
              token: config.token,
            );
      }
    } else if (config.isNmea && config.host.isNotEmpty) {
      final nmea = ref.read(nmeaStreamProvider);
      nmea.connect(
        host: config.host,
        port: config.port,
        protocol: config.type == DataSourceType.nmeaTcp
            ? NmeaProtocol.tcp
            : NmeaProtocol.udp,
      );
      ref.read(nmeaProcessorProvider);
    }
  }

  static const _screens = <Widget>[
    ChartScreen(),
    FloatillaShell(),
    LogbookScreen(),
    RouteListScreen(),
    TargetListScreen(),
    SignalKDashboard(),
    WeatherScreen(),
    PolarPerformanceScreen(),
    TidalCurrentsScreen(),
    AisHistoryTrailScreen(),
    AisCpaScreen(),
    DeviationTableScreen(),
    RaceStartTimerScreen(),
    DeadReckoningScreen(),
    CelestialNavScreen(),
    SarPatternScreen(),
    RadarSimulatorScreen(),
    NmeaMuxScreen(),
    PassagePlanScreen(),
    PassageBriefingScreen(),
    EngineDashboardScreen(),
    AnchorScopeScreen(),
    AnchorageScreen(),
    DeparturePlannerScreen(),
    TidalGateScreen(),
    CloudLogbookScreen(),
    BoatHealthScreen(),
    TrackComparisonScreen(),
    VoyageLoggerScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Listen for incoming shared waypoints.
    ref.listen<List<FloatillaWaypoint>>(pendingWaypointsProvider,
        (prev, next) {
      if (next.length > (prev?.length ?? 0)) {
        final wp = next.last;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${wp.fromUsername} shared a waypoint: ${wp.name}'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _showWaypointAcceptDialog(context, wp),
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    });

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

  void _showWaypointAcceptDialog(
      BuildContext context, FloatillaWaypoint wp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Waypoint from ${wp.fromUsername}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(wp.name,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            if (wp.description != null && wp.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(wp.description!),
              ),
            const SizedBox(height: 8),
            Text(
              '${wp.position.latitude.toStringAsFixed(5)}, '
              '${wp.position.longitude.toStringAsFixed(5)}',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Remove from pending.
              final pending = ref.read(pendingWaypointsProvider);
              ref.read(pendingWaypointsProvider.notifier).state =
                  pending.where((w) => w.id != wp.id).toList();
            },
            child: const Text('Dismiss'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.add_location),
            label: const Text('Add to Routes'),
            onPressed: () {
              ref.read(waypointsProvider.notifier).add(Waypoint(
                    name: wp.name,
                    position: wp.position,
                    notes: 'Shared by ${wp.fromUsername}',
                    createdAt: wp.createdAt,
                  ));
              // Remove from pending.
              final pending = ref.read(pendingWaypointsProvider);
              ref.read(pendingWaypointsProvider.notifier).state =
                  pending.where((w) => w.id != wp.id).toList();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Waypoint "${wp.name}" added')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _wrapWithMobOverlay(Widget child) {
    return Stack(
      children: [
        child,
        const MobOverlay(),
      ],
    );
  }

  /// Phone: bottom NavigationBar.
  Widget _buildCompactLayout(bool anyConnected, bool skConnected) {
    return _wrapWithMobOverlay(
      Scaffold(
        body: IndexedStack(index: _selectedIndex, children: _screens),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) => setState(() => _selectedIndex = i),
          destinations: _navDestinations(anyConnected, skConnected),
        ),
      ),
    );
  }

  /// Medium tablet / large phone: NavigationRail on left, no bottom nav.
  Widget _buildMediumLayout(bool anyConnected, bool skConnected) {
    return _wrapWithMobOverlay(
      Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) =>
                  setState(() => _selectedIndex = i),
              labelType: NavigationRailLabelType.all,
              destinations: _railDestinations(anyConnected, skConnected),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child:
                  IndexedStack(index: _selectedIndex, children: _screens),
            ),
          ],
        ),
      ),
    );
  }

  /// Large tablet: NavigationRail + persistent InstrumentSidebar on chart tab.
  Widget _buildExpandedLayout(bool anyConnected, bool skConnected) {
    return _wrapWithMobOverlay(
      Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) =>
                  setState(() => _selectedIndex = i),
              labelType: NavigationRailLabelType.all,
              destinations: _railDestinations(anyConnected, skConnected),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            if (_selectedIndex == 0) const InstrumentSidebar(),
            Expanded(
              child:
                  IndexedStack(index: _selectedIndex, children: _screens),
            ),
          ],
        ),
      ),
    );
  }

  List<NavigationDestination> _navDestinations(
      bool anyConnected, bool skConnected) {
    return [
      const NavigationDestination(icon: Icon(Icons.map), label: 'Chart'),
      const NavigationDestination(
          icon: Icon(Icons.groups), label: 'Floatilla'),
      const NavigationDestination(icon: Icon(Icons.book), label: 'Logbook'),
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
          icon: Icon(Icons.show_chart), label: 'Polar'),
      const NavigationDestination(
          icon: Icon(Icons.waves), label: 'Currents'),
      const NavigationDestination(
          icon: Icon(Icons.history), label: 'AIS Trail'),
      const NavigationDestination(
          icon: Icon(Icons.warning_amber), label: 'Collision'),
      const NavigationDestination(
          icon: Icon(Icons.explore), label: 'Deviation'),
      const NavigationDestination(
          icon: Icon(Icons.flag), label: 'Race'),
      const NavigationDestination(
          icon: Icon(Icons.directions_boat), label: 'DR'),
      const NavigationDestination(
          icon: Icon(Icons.star), label: 'Celestial'),
      const NavigationDestination(
          icon: Icon(Icons.search), label: 'SAR'),
      const NavigationDestination(
          icon: Icon(Icons.radar), label: 'Radar'),
      const NavigationDestination(
          icon: Icon(Icons.cable), label: 'NMEA'),
      const NavigationDestination(
          icon: Icon(Icons.explore), label: 'Passage'),
      const NavigationDestination(
          icon: Icon(Icons.auto_awesome), label: 'Briefing'),
      const NavigationDestination(
          icon: Icon(Icons.engineering), label: 'Engine'),
      const NavigationDestination(
          icon: Icon(Icons.anchor), label: 'Anchor'),
      const NavigationDestination(
          icon: Icon(Icons.place), label: 'Anchorages'),
      const NavigationDestination(
          icon: Icon(Icons.calendar_today), label: 'Depart'),
      const NavigationDestination(
          icon: Icon(Icons.water), label: 'Tidal Gates'),
      const NavigationDestination(
          icon: Icon(Icons.menu_book), label: 'Log'),
      const NavigationDestination(
          icon: Icon(Icons.monitor_heart), label: 'Health'),
      const NavigationDestination(
          icon: Icon(Icons.compare_arrows), label: 'Compare'),
      const NavigationDestination(
          icon: Icon(Icons.directions_boat), label: 'Voyage'),
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
          icon: Icon(Icons.groups), label: Text('Floatilla')),
      const NavigationRailDestination(
          icon: Icon(Icons.book), label: Text('Logbook')),
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
          icon: Icon(Icons.show_chart), label: Text('Polar')),
      const NavigationRailDestination(
          icon: Icon(Icons.waves), label: Text('Currents')),
      const NavigationRailDestination(
          icon: Icon(Icons.history), label: Text('AIS Trail')),
      const NavigationRailDestination(
          icon: Icon(Icons.warning_amber), label: Text('Collision')),
      const NavigationRailDestination(
          icon: Icon(Icons.explore), label: Text('Deviation')),
      const NavigationRailDestination(
          icon: Icon(Icons.flag), label: Text('Race')),
      const NavigationRailDestination(
          icon: Icon(Icons.directions_boat), label: Text('DR')),
      const NavigationRailDestination(
          icon: Icon(Icons.star), label: Text('Celestial')),
      const NavigationRailDestination(
          icon: Icon(Icons.search), label: Text('SAR')),
      const NavigationRailDestination(
          icon: Icon(Icons.radar), label: Text('Radar')),
      const NavigationRailDestination(
          icon: Icon(Icons.cable), label: Text('NMEA')),
      const NavigationRailDestination(
          icon: Icon(Icons.explore), label: Text('Passage')),
      const NavigationRailDestination(
          icon: Icon(Icons.auto_awesome), label: Text('Briefing')),
      const NavigationRailDestination(
          icon: Icon(Icons.engineering), label: Text('Engine')),
      const NavigationRailDestination(
          icon: Icon(Icons.anchor), label: Text('Anchor')),
      const NavigationRailDestination(
          icon: Icon(Icons.place), label: Text('Anchorages')),
      const NavigationRailDestination(
          icon: Icon(Icons.calendar_today), label: Text('Depart')),
      const NavigationRailDestination(
          icon: Icon(Icons.water), label: Text('Tidal Gates')),
      const NavigationRailDestination(
          icon: Icon(Icons.menu_book), label: Text('Log')),
      const NavigationRailDestination(
          icon: Icon(Icons.monitor_heart), label: Text('Health')),
      const NavigationRailDestination(
          icon: Icon(Icons.compare_arrows), label: Text('Compare')),
      const NavigationRailDestination(
          icon: Icon(Icons.directions_boat), label: Text('Voyage')),
      const NavigationRailDestination(
          icon: Icon(Icons.settings), label: Text('Settings')),
    ];
  }
}
