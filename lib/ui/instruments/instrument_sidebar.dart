import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/signalk_state.dart';
import '../../data/providers/settings_provider.dart';
import '../../data/providers/signalk_provider.dart';
import '../../data/providers/vessel_provider.dart';

/// Collapsible vertical sidebar for tablets showing full instrument data.
///
/// Shows more data than the compact [InstrumentStrip] (right side):
/// navigation + wind + VMG + heading mag + battery + water temp + pressure.
/// The strip only shows SOG/COG/HDG/depth/AWS/AWA (compact, icon-only).
class InstrumentSidebar extends ConsumerWidget {
  const InstrumentSidebar({super.key});

  static const double _expandedWidth = 300;
  static const Duration _animDuration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vessel = ref.watch(vesselProvider);
    final settings = ref.watch(appSettingsProvider);
    final skState = ref.watch(signalKProvider);
    final livePaths = ref.watch(signalKLivePathsProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A0000) : Colors.grey.shade100;
    final borderColor =
        isDark ? Colors.red.shade900 : Colors.blueGrey.shade200;
    final visible = settings.sidebarVisible;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animated sidebar content
        AnimatedContainer(
          duration: _animDuration,
          curve: Curves.easeInOut,
          width: visible ? _expandedWidth : 0,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: bgColor,
            border:
                Border(right: BorderSide(color: borderColor, width: 0.5)),
          ),
          child: SizedBox(
            width: _expandedWidth,
            child: SafeArea(
              right: false,
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                children: [
                  _SidebarTile(
                    label: 'SOG',
                    value: vessel.sog != null
                        ? _speedValue(vessel.sog!, settings)
                        : '--',
                    unit: _speedUnit(settings),
                    isDark: isDark,
                    isLive: livePaths.contains('navigation.speedOverGround'),
                  ),
                  _SidebarTile(
                    label: 'COG',
                    value: vessel.cog != null
                        ? '${vessel.cog!.toStringAsFixed(0)}°'
                        : '--',
                    unit: 'true',
                    isDark: isDark,
                    isLive:
                        livePaths.contains('navigation.courseOverGroundTrue'),
                  ),
                  _SidebarTile(
                    label: 'HDG',
                    value: vessel.heading != null
                        ? '${vessel.heading!.toStringAsFixed(0)}°'
                        : '--',
                    unit: 'true',
                    isDark: isDark,
                    isLive: livePaths.contains('navigation.headingTrue'),
                  ),
                  _SidebarTile(
                    label: 'HDG MAG',
                    value: skState.ownVessel.navigation.headingMagnetic != null
                        ? '${skState.ownVessel.navigation.headingMagnetic!.toStringAsFixed(0)}°'
                        : '--',
                    unit: 'mag',
                    isDark: isDark,
                    isLive: livePaths.contains('navigation.headingMagnetic'),
                  ),
                  _SidebarTile(
                    label: 'DEPTH',
                    value: vessel.depth != null
                        ? _depthValue(vessel.depth!, settings)
                        : '--',
                    unit: _depthUnit(settings),
                    isDark: isDark,
                    isLive: livePaths.contains('environment.depth.belowKeel') ||
                        livePaths
                            .contains('environment.depth.belowTransducer') ||
                        livePaths.contains('environment.depth.belowSurface'),
                  ),
                  _SidebarTile(
                    label: 'AWS',
                    value: vessel.windSpeed != null
                        ? _speedValue(vessel.windSpeed!, settings)
                        : '--',
                    unit: _speedUnit(settings),
                    isDark: isDark,
                    isLive:
                        livePaths.contains('environment.wind.speedApparent'),
                  ),
                  _SidebarTile(
                    label: 'AWA',
                    value: vessel.windAngle != null
                        ? '${vessel.windAngle!.toStringAsFixed(0)}°'
                        : '--',
                    unit: 'apparent',
                    isDark: isDark,
                    isLive:
                        livePaths.contains('environment.wind.angleApparent'),
                  ),
                  _SidebarTile(
                    label: 'TWS',
                    value: vessel.trueWindSpeed != null
                        ? _speedValue(vessel.trueWindSpeed!, settings)
                        : '--',
                    unit: _speedUnit(settings),
                    isDark: isDark,
                    isLive: livePaths.contains('environment.wind.speedTrue'),
                  ),
                  _SidebarTile(
                    label: 'VMG',
                    value: vessel.vmg != null
                        ? _speedValue(vessel.vmg!.abs(), settings)
                        : '--',
                    unit: _speedUnit(settings),
                    isDark: isDark,
                    isLive: false,
                  ),
                  // Extra instruments not on the compact strip
                  ..._buildElectricalTiles(skState, isDark, livePaths),
                  if (skState.ownVessel.environment.waterTemp != null)
                    _SidebarTile(
                      label: 'WATER',
                      value: skState.ownVessel.environment.waterTemp!
                          .toStringAsFixed(1),
                      unit: '°C',
                      isDark: isDark,
                      isLive: livePaths
                          .contains('environment.water.temperature'),
                    ),
                  if (skState.ownVessel.environment.airTemp != null)
                    _SidebarTile(
                      label: 'AIR',
                      value: skState.ownVessel.environment.airTemp!
                          .toStringAsFixed(1),
                      unit: '°C',
                      isDark: isDark,
                      isLive: livePaths
                          .contains('environment.outside.temperature'),
                    ),
                  if (skState.ownVessel.environment.pressure != null)
                    _SidebarTile(
                      label: 'BARO',
                      value: skState.ownVessel.environment.pressure!
                          .toStringAsFixed(0),
                      unit: 'hPa',
                      isDark: isDark,
                      isLive: livePaths
                          .contains('environment.outside.pressure'),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Toggle button — always visible
        GestureDetector(
          onTap: () => ref.read(appSettingsProvider.notifier).toggleSidebar(),
          child: Container(
            width: 20,
            decoration: BoxDecoration(
              color: bgColor,
              border:
                  Border(right: BorderSide(color: borderColor, width: 0.5)),
            ),
            child: Center(
              child: Icon(
                visible ? Icons.chevron_left : Icons.chevron_right,
                size: 16,
                color: isDark ? Colors.red.shade300 : Colors.blueGrey,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildElectricalTiles(
      SignalKState skState, bool isDark, Set<String> livePaths) {
    final batteries = skState.ownVessel.electrical.batteries;
    if (batteries.isEmpty) return const [];

    return batteries.entries.map((entry) {
      final bat = entry.value;
      final label = batteries.length == 1 ? 'BATT' : 'BAT ${entry.key}';
      final parts = <String>[];
      if (bat.voltage != null) parts.add('${bat.voltage!.toStringAsFixed(1)}V');
      if (bat.socPercent != null) {
        parts.add('${bat.socPercent!.toStringAsFixed(0)}%');
      }
      return _SidebarTile(
        label: label,
        value: parts.isNotEmpty ? parts.join(' ') : '--',
        unit: '',
        isDark: isDark,
        isLive: livePaths.contains('electrical.batteries.${entry.key}.voltage'),
      );
    }).toList();
  }

  String _speedValue(double knots, AppSettings s) {
    switch (s.units) {
      case UnitSystem.nautical:
        return knots.toStringAsFixed(1);
      case UnitSystem.metric:
        return (knots * 1.852).toStringAsFixed(1);
      case UnitSystem.imperial:
        return (knots * 1.15078).toStringAsFixed(1);
    }
  }

  String _speedUnit(AppSettings s) {
    switch (s.units) {
      case UnitSystem.nautical:
        return 'kn';
      case UnitSystem.metric:
        return 'km/h';
      case UnitSystem.imperial:
        return 'mph';
    }
  }

  String _depthValue(double metres, AppSettings s) {
    switch (s.units) {
      case UnitSystem.nautical:
      case UnitSystem.metric:
        return metres.toStringAsFixed(1);
      case UnitSystem.imperial:
        return (metres * 3.28084).toStringAsFixed(1);
    }
  }

  String _depthUnit(AppSettings s) {
    switch (s.units) {
      case UnitSystem.nautical:
      case UnitSystem.metric:
        return 'm';
      case UnitSystem.imperial:
        return 'ft';
    }
  }
}

class _SidebarTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool isDark;
  final bool isLive;

  const _SidebarTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.isDark,
    this.isLive = false,
  });

  @override
  Widget build(BuildContext context) {
    final liveColor = isDark ? Colors.green.shade400 : Colors.green.shade700;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLive
              ? liveColor
              : (isDark ? Colors.red.shade900 : Colors.blueGrey.shade200),
          width: isLive ? 1.0 : 0.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.red.shade300 : Colors.blueGrey,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: isDark ? Colors.red.shade100 : Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              unit,
              style: TextStyle(
                fontSize: 12,
                color:
                    isDark ? Colors.red.shade400 : Colors.blueGrey.shade400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
