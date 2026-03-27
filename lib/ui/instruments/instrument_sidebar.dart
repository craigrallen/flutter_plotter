import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/settings_provider.dart';
import '../../data/providers/vessel_provider.dart';

/// Vertical sidebar for tablets showing key instruments.
/// Always visible when layout is expanded (>840dp).
class InstrumentSidebar extends ConsumerWidget {
  const InstrumentSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vessel = ref.watch(vesselProvider);
    final settings = ref.watch(appSettingsProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A0000) : Colors.grey.shade100;
    final borderColor =
        isDark ? Colors.red.shade900 : Colors.blueGrey.shade200;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(right: BorderSide(color: borderColor, width: 0.5)),
      ),
      child: SafeArea(
        right: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          children: [
            _SidebarTile(
              label: 'SOG',
              value: vessel.sog != null
                  ? _speedValue(vessel.sog!, settings)
                  : '--',
              unit: _speedUnit(settings),
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'COG',
              value: vessel.cog != null
                  ? '${vessel.cog!.toStringAsFixed(0)}°'
                  : '--',
              unit: 'true',
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'HDG',
              value: vessel.heading != null
                  ? '${vessel.heading!.toStringAsFixed(0)}°'
                  : '--',
              unit: 'true',
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'DEPTH',
              value: vessel.depth != null
                  ? _depthValue(vessel.depth!, settings)
                  : '--',
              unit: _depthUnit(settings),
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'AWS',
              value: vessel.windSpeed != null
                  ? _speedValue(vessel.windSpeed!, settings)
                  : '--',
              unit: _speedUnit(settings),
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'AWA',
              value: vessel.windAngle != null
                  ? '${vessel.windAngle!.toStringAsFixed(0)}°'
                  : '--',
              unit: 'apparent',
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'VMG',
              value: vessel.vmg != null
                  ? _speedValue(vessel.vmg!.abs(), settings)
                  : '--',
              unit: _speedUnit(settings),
              isDark: isDark,
            ),
          ],
        ),
      ),
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

class _SidebarTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool isDark;

  const _SidebarTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.red.shade900 : Colors.blueGrey.shade200,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
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
