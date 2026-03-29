import 'package:flutter/material.dart';
import '../chart/chart_screen.dart';
import '../floatilla/cdi_screen.dart';
import '../floatilla/fuel_range_screen.dart';
import '../floatilla/waypoint_calc_screen.dart';
import '../floatilla/ais_cpa_screen.dart';
import '../floatilla/ais_history_trail_screen.dart';
import '../floatilla/anchor_scope_screen.dart';
import '../floatilla/anchorage_screen.dart';
import '../floatilla/boat_health_screen.dart';
import '../floatilla/celestial_nav_screen.dart';
import '../floatilla/cloud_logbook_screen.dart';
import '../floatilla/dead_reckoning_screen.dart';
import '../floatilla/departure_planner_screen.dart';
import '../floatilla/deviation_table_screen.dart';
import '../floatilla/engine_dashboard_screen.dart';
import '../floatilla/floatilla_shell.dart';
import '../floatilla/daily_briefing_screen.dart';
import '../floatilla/grib_weather_screen.dart';
import '../floatilla/ocean_current_screen.dart';
import '../floatilla/swell_breakdown_screen.dart';
import '../floatilla/wind_history_screen.dart';
import '../floatilla/nmea_mux_screen.dart';
import '../floatilla/passage_briefing_screen.dart';
import '../floatilla/passage_plan_screen.dart';
import '../floatilla/polar_performance_screen.dart';
import '../floatilla/race_start_timer_screen.dart';
import '../floatilla/radar_simulator_screen.dart';
import '../floatilla/mob_drift_screen.dart';
import '../floatilla/sar_pattern_screen.dart';
import '../floatilla/tidal_currents_screen.dart';
import '../floatilla/tidal_gate_screen.dart';
import '../floatilla/track_comparison_screen.dart';
import '../floatilla/voyage_logger_screen.dart';
import '../routes/route_list_screen.dart';
import '../signalk/signalk_dashboard.dart';
import '../weather/weather_screen.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class _PluginEntry {
  const _PluginEntry({
    required this.name,
    required this.icon,
    required this.builder,
  });
  final String name;
  final IconData icon;
  final WidgetBuilder builder;
}

class _Category {
  const _Category({
    required this.name,
    required this.color,
    required this.plugins,
  });
  final String name;
  final Color color;
  final List<_PluginEntry> plugins;
}

// ---------------------------------------------------------------------------
// Plugin catalogue
// ---------------------------------------------------------------------------

final List<_Category> _categories = [
  _Category(
    name: 'Navigation & Planning',
    color: const Color(0xFF1565C0), // blue[800]
    plugins: [
      _PluginEntry(
        name: 'Passage Plan',
        icon: Icons.map_outlined,
        builder: (_) => const PassagePlanScreen(),
      ),
      _PluginEntry(
        name: 'Route Planner',
        icon: Icons.route,
        builder: (_) => const RouteListScreen(),
      ),
      _PluginEntry(
        name: 'Tidal Gates',
        icon: Icons.water,
        builder: (_) => const TidalGateScreen(),
      ),
      _PluginEntry(
        name: 'Departure Planner',
        icon: Icons.calendar_today,
        builder: (_) => const DeparturePlannerScreen(),
      ),
      _PluginEntry(
        name: 'Dead Reckoning',
        icon: Icons.directions_boat,
        builder: (_) => const DeadReckoningScreen(),
      ),
      _PluginEntry(
        name: 'Celestial Nav',
        icon: Icons.star_outline,
        builder: (_) => const CelestialNavScreen(),
      ),
      _PluginEntry(
        name: 'Waypoint\nCalc',
        icon: Icons.calculate,
        builder: (_) => const WaypointCalcScreen(),
      ),
      _PluginEntry(
        name: 'CDI',
        icon: Icons.linear_scale,
        builder: (_) => const CdiScreen(),
      ),
      _PluginEntry(
        name: 'Fuel Range',
        icon: Icons.local_gas_station,
        builder: (_) => const FuelRangeScreen(),
      ),
      _PluginEntry(
        name: 'Night Mode',
        icon: Icons.nightlight_round,
        builder: (_) => const ChartScreen(initialNightMode: true),
      ),
    ],
  ),
  _Category(
    name: 'Safety & Alerts',
    color: const Color(0xFFC62828), // red[800]
    plugins: [
      _PluginEntry(
        name: 'AIS Collision\n(CPA)',
        icon: Icons.warning_amber,
        builder: (_) => const AisCpaScreen(),
      ),
      _PluginEntry(
        name: 'Anchor Watch\n(Scope)',
        icon: Icons.anchor,
        builder: (_) => const AnchorScopeScreen(),
      ),
      _PluginEntry(
        name: 'Boat Health\nMonitor',
        icon: Icons.monitor_heart,
        builder: (_) => const BoatHealthScreen(),
      ),
      _PluginEntry(
        name: 'MOB',
        icon: Icons.person_off,
        builder: (_) => const MobDriftScreen(),
      ),
      _PluginEntry(
        name: 'SAR Patterns',
        icon: Icons.search,
        builder: (_) => const SarPatternScreen(),
      ),
    ],
  ),
  _Category(
    name: 'Weather & Environment',
    color: const Color(0xFF00695C), // teal[800]
    plugins: [
      _PluginEntry(
        name: 'GRIB Weather',
        icon: Icons.air,
        builder: (_) => const GribWeatherScreen(),
      ),
      _PluginEntry(
        name: 'Tidal Currents',
        icon: Icons.waves,
        builder: (_) => const TidalCurrentsScreen(),
      ),
      _PluginEntry(
        name: 'Weather Overlay',
        icon: Icons.cloud_outlined,
        builder: (_) => const WeatherScreen(),
      ),
      _PluginEntry(
        name: 'Briefing',
        icon: Icons.wb_cloudy,
        builder: (_) => const DailyBriefingScreen(),
      ),
      _PluginEntry(
        name: 'Wind',
        icon: Icons.air,
        builder: (_) => const WindHistoryScreen(),
      ),
      _PluginEntry(
        name: 'Currents',
        icon: Icons.water,
        builder: (_) => const OceanCurrentScreen(),
      ),
      _PluginEntry(
        name: 'Swell',
        icon: Icons.waves,
        builder: (_) => const SwellBreakdownScreen(),
      ),
    ],
  ),
  _Category(
    name: 'Instruments & Data',
    color: const Color(0xFF4527A0), // deep-purple[800]
    plugins: [
      _PluginEntry(
        name: 'Signal K\nDashboard',
        icon: Icons.speed,
        builder: (_) => const SignalKDashboard(),
      ),
      _PluginEntry(
        name: 'NMEA\nMultiplexer',
        icon: Icons.cable,
        builder: (_) => const NmeaMuxScreen(),
      ),
      _PluginEntry(
        name: 'Engine\nDashboard',
        icon: Icons.engineering,
        builder: (_) => const EngineDashboardScreen(),
      ),
      _PluginEntry(
        name: 'Polar\nPerformance',
        icon: Icons.show_chart,
        builder: (_) => const PolarPerformanceScreen(),
      ),
      _PluginEntry(
        name: 'Radar\nSimulator',
        icon: Icons.radar,
        builder: (_) => const RadarSimulatorScreen(),
      ),
    ],
  ),
  _Category(
    name: 'Voyage',
    color: const Color(0xFF2E7D32), // green[800]
    plugins: [
      _PluginEntry(
        name: 'Voyage Logger',
        icon: Icons.edit_note,
        builder: (_) => const VoyageLoggerScreen(),
      ),
      _PluginEntry(
        name: 'Cloud Logbook',
        icon: Icons.menu_book,
        builder: (_) => const CloudLogbookScreen(),
      ),
      _PluginEntry(
        name: 'AIS History\nTrail',
        icon: Icons.history,
        builder: (_) => const AisHistoryTrailScreen(),
      ),
      _PluginEntry(
        name: 'Track\nComparison',
        icon: Icons.compare_arrows,
        builder: (_) => const TrackComparisonScreen(),
      ),
    ],
  ),
  _Category(
    name: 'Social & Community',
    color: const Color(0xFFE65100), // orange[800]
    plugins: [
      _PluginEntry(
        name: 'Floatilla Feed',
        icon: Icons.groups,
        builder: (_) => const FloatillaShell(),
      ),
      _PluginEntry(
        name: 'Anchorages',
        icon: Icons.place,
        builder: (_) => const AnchorageScreen(),
      ),
      _PluginEntry(
        name: 'Passage\nBriefing (AI)',
        icon: Icons.auto_awesome,
        builder: (_) => const PassageBriefingScreen(),
      ),
    ],
  ),
  _Category(
    name: 'Racing',
    color: const Color(0xFF6A1B9A), // purple[800]
    plugins: [
      _PluginEntry(
        name: 'Race Start\nTimer',
        icon: Icons.flag,
        builder: (_) => const RaceStartTimerScreen(),
      ),
      _PluginEntry(
        name: 'Deviation\nTable',
        icon: Icons.explore,
        builder: (_) => const DeviationTableScreen(),
      ),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class PluginHubScreen extends StatefulWidget {
  const PluginHubScreen({super.key});

  @override
  State<PluginHubScreen> createState() => _PluginHubScreenState();
}

class _PluginHubScreenState extends State<PluginHubScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _buildFiltered();

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Features'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search features...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
        ),
      ),
      body: filtered.isEmpty
          ? const Center(child: Text('No matching features'))
          : CustomScrollView(
              slivers: [
                for (final cat in filtered) ...[
                  SliverToBoxAdapter(
                    child: _CategoryHeader(category: cat),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 120,
                        mainAxisExtent: 110,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _PluginCard(
                          entry: cat.plugins[index],
                          color: cat.color,
                        ),
                        childCount: cat.plugins.length,
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
    );
  }

  /// Returns categories filtered by the current search query.
  /// Empty categories are excluded.
  List<_Category> _buildFiltered() {
    if (_query.isEmpty) return _categories;
    return _categories
        .map((cat) {
          final plugins = cat.plugins
              .where((p) =>
                  p.name.toLowerCase().contains(_query) ||
                  cat.name.toLowerCase().contains(_query))
              .toList();
          return _Category(
              name: cat.name, color: cat.color, plugins: plugins);
        })
        .where((cat) => cat.plugins.isNotEmpty)
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.category});
  final _Category category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: category.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            category.name,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: category.color,
                ),
          ),
        ],
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard({required this.entry, required this.color});
  final _PluginEntry entry;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bg = color.withValues(alpha: 0.12);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: entry.builder),
      ),
      child: Ink(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(entry.icon, size: 36, color: color),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                entry.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
