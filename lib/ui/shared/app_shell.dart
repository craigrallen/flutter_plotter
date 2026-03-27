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
import '../floatilla/floatilla_shell.dart';
import '../floatilla/mob_overlay.dart';
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
    RouteListScreen(),
    TargetListScreen(),
    SignalKDashboard(),
    WeatherScreen(),
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
          icon: Icon(Icons.groups), label: Text('Floatilla')),
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
