import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/route_provider.dart';
import '../../data/providers/vessel_provider.dart';

// ---------------------------------------------------------------------------
// XTE thresholds
// ---------------------------------------------------------------------------

const double _kXteGreen = 0.05; // nm — on track
const double _kXteOrange = 0.2; // nm — slight deviation
// beyond 0.2 nm = red

const double _kXteMaxDisplay = 0.5; // nm — full bar deflection

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class CdiScreen extends ConsumerWidget {
  const CdiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navData = ref.watch(routeNavProvider);
    final vessel = ref.watch(vesselProvider);

    final xteNm = navData?.xteNm ?? 0.0;
    final xteAbs = xteNm.abs();
    final xteColor = _xteColor(xteAbs);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'CDI — Course Deviation',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: navData == null
            ? _noRoute()
            : OrientationBuilder(
                builder: (context, orientation) {
                  return orientation == Orientation.landscape
                      ? _buildLandscape(
                          context, navData, vessel, xteNm, xteColor)
                      : _buildPortrait(
                          context, navData, vessel, xteNm, xteColor);
                },
              ),
      ),
    );
  }

  Widget _noRoute() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.linear_scale, size: 64, color: Colors.white24),
          SizedBox(height: 16),
          Text(
            'No active route',
            style: TextStyle(color: Colors.white54, fontSize: 20),
          ),
          SizedBox(height: 8),
          Text(
            'Set a route to see CDI',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Color _xteColor(double xteAbs) {
    if (xteAbs < _kXteGreen) return Colors.green;
    if (xteAbs < _kXteOrange) return Colors.orange;
    return Colors.red;
  }

  // ---------------------------------------------------------------------------
  // Landscape layout (primary helm view)
  // ---------------------------------------------------------------------------

  Widget _buildLandscape(
    BuildContext context,
    dynamic navData,
    dynamic vessel,
    double xteNm,
    Color xteColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          // Left: CDI highway graphic
          Expanded(
            flex: 4,
            child: _CdiHighway(xteNm: xteNm, xteColor: xteColor),
          ),
          const SizedBox(width: 24),
          // Right: numeric readouts
          Expanded(
            flex: 5,
            child: _NumericPanel(
              navData: navData,
              vessel: vessel,
              xteNm: xteNm,
              xteColor: xteColor,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Portrait layout
  // ---------------------------------------------------------------------------

  Widget _buildPortrait(
    BuildContext context,
    dynamic navData,
    dynamic vessel,
    double xteNm,
    Color xteColor,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // CDI highway graphic
          Expanded(
            flex: 5,
            child: _CdiHighway(xteNm: xteNm, xteColor: xteColor),
          ),
          const SizedBox(height: 16),
          // Numeric readouts
          Expanded(
            flex: 6,
            child: _NumericPanel(
              navData: navData,
              vessel: vessel,
              xteNm: xteNm,
              xteColor: xteColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CDI Highway graphic
// ---------------------------------------------------------------------------

class _CdiHighway extends StatelessWidget {
  final double xteNm;
  final Color xteColor;

  const _CdiHighway({required this.xteNm, required this.xteColor});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HighwayPainter(xteNm: xteNm, xteColor: xteColor),
    );
  }
}

class _HighwayPainter extends CustomPainter {
  final double xteNm;
  final Color xteColor;

  _HighwayPainter({required this.xteNm, required this.xteColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const roadHalfW = 40.0;
    const dashH = 14.0;
    const dashGap = 10.0;

    // Road edges — white
    final roadPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
        Offset(cx - roadHalfW, 0), Offset(cx - roadHalfW, size.height),
        roadPaint);
    canvas.drawLine(
        Offset(cx + roadHalfW, 0), Offset(cx + roadHalfW, size.height),
        roadPaint);

    // Dashed centre line — yellow
    final dashPaint = Paint()
      ..color = Colors.yellow.withValues(alpha: 0.8)
      ..strokeWidth = 2;

    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(cx, y), Offset(cx, math.min(y + dashH, size.height)),
          dashPaint);
      y += dashH + dashGap;
    }

    // Vessel position indicator — offset from centre based on XTE
    // XTE > 0 = vessel is to the right of track (show dot to the left of road centre)
    final fraction =
        (xteNm / _kXteMaxDisplay).clamp(-1.0, 1.0);
    final vesselX =
        cx - fraction * (roadHalfW * 2.5); // invert: positive XTE = move left
    final vesselY = cy;

    // Draw vessel dot with colour
    final vesselPaint = Paint()
      ..color = xteColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(vesselX, vesselY), 16, vesselPaint);

    // Arrow pointing up
    final arrowPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(vesselX, vesselY + 8),
      Offset(vesselX, vesselY - 8),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(vesselX - 6, vesselY - 2),
      Offset(vesselX, vesselY - 8),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(vesselX + 6, vesselY - 2),
      Offset(vesselX, vesselY - 8),
      arrowPaint,
    );

    // XTE scale tick marks
    final tickPaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;

    for (final t in [-0.4, -0.3, -0.2, -0.1, 0.1, 0.2, 0.3, 0.4]) {
      final tx = cx - (t / _kXteMaxDisplay) * roadHalfW * 2.5;
      canvas.drawLine(
        Offset(tx, cy - 4),
        Offset(tx, cy + 4),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_HighwayPainter oldDelegate) =>
      oldDelegate.xteNm != xteNm || oldDelegate.xteColor != xteColor;
}

// ---------------------------------------------------------------------------
// Numeric panel
// ---------------------------------------------------------------------------

class _NumericPanel extends StatelessWidget {
  final dynamic navData;
  final dynamic vessel;
  final double xteNm;
  final Color xteColor;

  const _NumericPanel({
    required this.navData,
    required this.vessel,
    required this.xteNm,
    required this.xteColor,
  });

  @override
  Widget build(BuildContext context) {
    final xteAbs = xteNm.abs();
    final xteDir = xteNm >= 0 ? 'R' : 'L';

    final vmg = vessel.vmg;

    String etaStr = '--';
    if (navData.etaToNext != null) {
      final d = navData.etaToNext as Duration;
      if (d.inHours > 0) {
        etaStr = '${d.inHours}h ${d.inMinutes.remainder(60)}m';
      } else {
        etaStr = '${d.inMinutes}m';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Waypoint name
        Text(
          navData.nextWaypointName as String,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        // XTE large display
        _BigValue(
          label: 'XTE',
          value: '${xteAbs.toStringAsFixed(3)} nm $xteDir',
          color: xteColor,
          large: true,
        ),
        const SizedBox(height: 8),
        // XTE bar
        _XteBar(xteNm: xteNm, xteColor: xteColor),
        const SizedBox(height: 16),
        // Grid of values
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _BigValue(
                label: 'DTW',
                value: '${(navData.distanceToNextNm as double).toStringAsFixed(2)} nm',
              ),
              _BigValue(
                label: 'BTW',
                value: '${(navData.bearingToNextDeg as double).toStringAsFixed(0)}°',
              ),
              _BigValue(
                label: 'VMG',
                value: vmg != null ? '${vmg.toStringAsFixed(1)} kn' : '--',
              ),
              _BigValue(
                label: 'ETA',
                value: etaStr,
              ),
              _BigValue(
                label: 'SOG',
                value: vessel.sog != null
                    ? '${(vessel.sog as double).toStringAsFixed(1)} kn'
                    : '--',
              ),
              _BigValue(
                label: 'COG',
                value: vessel.cog != null
                    ? '${(vessel.cog as double).toStringAsFixed(0)}°'
                    : '--',
              ),
              _BigValue(
                label: 'HDG',
                value: vessel.heading != null
                    ? '${(vessel.heading as double).toStringAsFixed(0)}°'
                    : '--',
              ),
              _BigValue(
                label: 'REM',
                value:
                    '${(navData.remainingDistanceNm as double).toStringAsFixed(1)} nm',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BigValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool large;

  const _BigValue({
    required this.label,
    required this.value,
    this.color = Colors.white,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: large ? 28 : 22,
            fontWeight: FontWeight.bold,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _XteBar extends StatelessWidget {
  final double xteNm;
  final Color xteColor;

  const _XteBar({required this.xteNm, required this.xteColor});

  @override
  Widget build(BuildContext context) {
    final fraction = (xteNm / _kXteMaxDisplay).clamp(-1.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cx = w / 2;
        final barW = (fraction.abs() * cx).clamp(0.0, cx);

        return SizedBox(
          height: 28,
          child: Stack(
            children: [
              // Background track
              Container(
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // Centre line
              Positioned(
                left: cx - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: Colors.white54),
              ),
              // Fill bar
              if (fraction > 0)
                Positioned(
                  left: cx - barW,
                  top: 4,
                  bottom: 4,
                  width: barW,
                  child: Container(
                    decoration: BoxDecoration(
                      color: xteColor.withValues(alpha: 0.8),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(3),
                        bottomLeft: Radius.circular(3),
                      ),
                    ),
                  ),
                )
              else if (fraction < 0)
                Positioned(
                  left: cx,
                  top: 4,
                  bottom: 4,
                  width: barW,
                  child: Container(
                    decoration: BoxDecoration(
                      color: xteColor.withValues(alpha: 0.8),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(3),
                        bottomRight: Radius.circular(3),
                      ),
                    ),
                  ),
                ),
              // Port / Stbd labels
              const Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(
                    'P',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(
                    'S',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
