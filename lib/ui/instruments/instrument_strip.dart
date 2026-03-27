import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/settings_provider.dart';
import '../../data/providers/vessel_provider.dart';

/// Narrow vertical instrument strip for phone landscape mode.
/// Shows icon + value only, no labels. 80dp wide, collapsible.
class InstrumentStrip extends ConsumerStatefulWidget {
  const InstrumentStrip({super.key});

  @override
  ConsumerState<InstrumentStrip> createState() => _InstrumentStripState();
}

class _InstrumentStripState extends ConsumerState<InstrumentStrip> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final vessel = ref.watch(vesselProvider);
    final settings = ref.watch(appSettingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_collapsed) {
      return GestureDetector(
        onTap: () => setState(() => _collapsed = false),
        child: Container(
          width: 24,
          color: isDark
              ? Colors.black.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.8),
          child: Center(
            child: Icon(
              Icons.chevron_left,
              color: isDark ? Colors.red.shade300 : Colors.blueGrey,
              size: 20,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
          setState(() => _collapsed = true);
        }
      },
      child: Container(
        width: 80,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.85),
          border: Border(
            left: BorderSide(
              color: isDark ? Colors.red.shade900 : Colors.blueGrey.shade200,
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          left: false,
          child: Column(
            children: [
              // Collapse button
              GestureDetector(
                onTap: () => setState(() => _collapsed = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Icon(
                    Icons.chevron_right,
                    color: isDark ? Colors.red.shade300 : Colors.blueGrey,
                    size: 18,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    _StripItem(
                      icon: Icons.speed,
                      value: vessel.sog != null
                          ? _fmtSpeed(vessel.sog!, settings)
                          : '--',
                      isDark: isDark,
                    ),
                    _StripItem(
                      icon: Icons.explore,
                      value: vessel.cog != null
                          ? '${vessel.cog!.toStringAsFixed(0)}°'
                          : '--',
                      isDark: isDark,
                    ),
                    _StripItem(
                      icon: Icons.navigation,
                      value: vessel.heading != null
                          ? '${vessel.heading!.toStringAsFixed(0)}°'
                          : '--',
                      isDark: isDark,
                    ),
                    _StripItem(
                      icon: Icons.water,
                      value: vessel.depth != null
                          ? _fmtDepth(vessel.depth!, settings)
                          : '--',
                      isDark: isDark,
                    ),
                    _StripItem(
                      icon: Icons.air,
                      value: vessel.windSpeed != null
                          ? _fmtSpeed(vessel.windSpeed!, settings)
                          : '--',
                      isDark: isDark,
                    ),
                    _StripItem(
                      icon: Icons.rotate_right,
                      value: vessel.windAngle != null
                          ? '${vessel.windAngle!.toStringAsFixed(0)}°'
                          : '--',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtSpeed(double knots, AppSettings s) {
    switch (s.units) {
      case UnitSystem.nautical:
        return knots.toStringAsFixed(1);
      case UnitSystem.metric:
        return (knots * 1.852).toStringAsFixed(1);
      case UnitSystem.imperial:
        return (knots * 1.15078).toStringAsFixed(1);
    }
  }

  String _fmtDepth(double metres, AppSettings s) {
    switch (s.units) {
      case UnitSystem.nautical:
      case UnitSystem.metric:
        return metres.toStringAsFixed(1);
      case UnitSystem.imperial:
        return (metres * 3.28084).toStringAsFixed(1);
    }
  }
}

class _StripItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final bool isDark;

  const _StripItem({
    required this.icon,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.red.shade900.withValues(alpha: 0.3)
                : Colors.blueGrey.shade100,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isDark ? Colors.red.shade300 : Colors.blueGrey,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: isDark ? Colors.red.shade100 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
