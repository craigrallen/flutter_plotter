import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/data_source_provider.dart';
import '../../data/providers/settings_provider.dart';
import '../../data/providers/signalk_provider.dart';
import '../../data/providers/vessel_provider.dart';
import 'instrument_tile.dart';

/// Slide-up instrument panel from the bottom of the chart screen.
class InstrumentPanel extends ConsumerWidget {
  const InstrumentPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vessel = ref.watch(vesselProvider);
    final settings = ref.watch(appSettingsProvider);
    final dataSource = ref.watch(dataSourceProvider);
    final skEnv = dataSource.isSignalK
        ? ref.watch(signalKEnvironmentProvider)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1A0000)
            : Colors.grey.shade100,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Instrument grid
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tile(
                  'SOG',
                  vessel.sog != null
                      ? _speedValue(vessel.sog!, settings)
                      : '--',
                  _speedUnit(settings),
                ),
                _tile(
                  'COG',
                  vessel.cog != null
                      ? '${vessel.cog!.toStringAsFixed(0)}°'
                      : '--',
                  'true',
                ),
                _tile(
                  'HDG',
                  vessel.heading != null
                      ? '${vessel.heading!.toStringAsFixed(0)}°'
                      : '--',
                  'true',
                ),
                _tile(
                  'DEPTH',
                  vessel.depth != null
                      ? _depthValue(vessel.depth!, settings)
                      : '--',
                  _depthUnit(settings),
                ),
                _tile(
                  'AWS',
                  vessel.windSpeed != null
                      ? _speedValue(vessel.windSpeed!, settings)
                      : '--',
                  'apparent',
                ),
                _tile(
                  'AWA',
                  vessel.windAngle != null
                      ? '${vessel.windAngle!.toStringAsFixed(0)}°'
                      : '--',
                  'apparent',
                ),
                // Show true wind if available (from Signal K or computed)
                if (vessel.trueWindSpeed != null ||
                    (skEnv != null && skEnv.windSpeedTrue != null))
                  _tile(
                    'TWS',
                    _speedValue(
                      vessel.trueWindSpeed ??
                          skEnv?.windSpeedTrue ??
                          0,
                      settings,
                    ),
                    'true',
                  ),
                if (vessel.trueWindAngle != null ||
                    (skEnv != null && skEnv.windAngleTrueWater != null))
                  _tile(
                    'TWA',
                    '${(vessel.trueWindAngle ?? skEnv?.windAngleTrueWater ?? 0).toStringAsFixed(0)}°',
                    'true',
                  ),
                _tile(
                  'VMG',
                  vessel.vmg != null
                      ? _speedValue(vessel.vmg!.abs(), settings)
                      : '--',
                  _speedUnit(settings),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(String label, String value, String unit) {
    return SizedBox(
      width: 100,
      child: InstrumentTile(label: label, value: value, unit: unit),
    );
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
