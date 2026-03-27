import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/ais/messages/static_voyage.dart';
import '../../../core/nav/geo.dart';
import '../../../data/models/ais_target.dart';
import '../../../data/providers/ais_provider.dart';
import '../../../data/providers/vessel_provider.dart';

/// Renders AIS targets on the chart as colour-coded icons with COG vector lines.
class AisLayer extends ConsumerWidget {
  final double mapRotation;

  const AisLayer({super.key, this.mapRotation = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(aisProvider);
    final vessel = ref.watch(vesselProvider);

    if (targets.isEmpty) return const SizedBox.shrink();

    final markers = <Marker>[];
    final polylines = <Polyline>[];

    for (final target in targets.values) {
      if (target.isStale) continue;

      // Compute CPA/threat level
      CpaResult? cpa;
      if (vessel.position != null) {
        cpa = target.computeCpa(
          vessel.position!,
          vessel.sog ?? 0,
          vessel.cog ?? 0,
        );
      }
      final threat = cpa?.threatLevel ?? ThreatLevel.safe;
      final color = _threatColor(threat);

      // COG vector line (5 min projection)
      if (target.sogKnots > 0.5) {
        final distNm = target.sogKnots * 5 / 60; // 5 minutes
        final endPoint = destinationPoint(
          target.position,
          target.cogDegrees,
          distNm * 1852,
        );
        polylines.add(Polyline(
          points: [target.position, endPoint],
          color: color.withValues(alpha: 0.7),
          strokeWidth: 2,
        ));
      }

      // Target marker — minimum 44dp tap area
      markers.add(Marker(
        point: target.position,
        width: 44,
        height: 44,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _showTargetSheet(context, target, cpa),
          child: Center(
            child: Transform.rotate(
              angle:
                  (target.cogDegrees * pi / 180) - (mapRotation * pi / 180),
              child: _TargetIcon(color: color, isAtoN: target.isAtoN),
            ),
          ),
        ),
      ));
    }

    return Stack(
      children: [
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Color _threatColor(ThreatLevel level) {
    switch (level) {
      case ThreatLevel.safe:
        return Colors.green;
      case ThreatLevel.caution:
        return Colors.orange;
      case ThreatLevel.danger:
        return Colors.red;
    }
  }

  void _showTargetSheet(
      BuildContext context, AisTarget target, CpaResult? cpa) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        minChildSize: 0.25,
        maxChildSize: 0.7,
        initialChildSize: 0.35,
        builder: (context, scrollController) => _TargetDetailSheet(
          target: target,
          cpa: cpa,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _TargetIcon extends StatelessWidget {
  final Color color;
  final bool isAtoN;

  const _TargetIcon({required this.color, this.isAtoN = false});

  @override
  Widget build(BuildContext context) {
    if (isAtoN) {
      return Icon(Icons.location_on, color: color, size: 24);
    }
    return CustomPaint(
      size: const Size(32, 32),
      painter: _TargetPainter(color: color),
    );
  }
}

class _TargetPainter extends CustomPainter {
  final Color color;

  _TargetPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final outline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Triangle pointing up (north direction)
    final path = ui.Path()
      ..moveTo(cx, cy - 12)
      ..lineTo(cx + 8, cy + 8)
      ..lineTo(cx - 8, cy + 8)
      ..close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, outline);
  }

  @override
  bool shouldRepaint(_TargetPainter old) => old.color != color;
}

class _TargetDetailSheet extends StatelessWidget {
  final AisTarget target;
  final CpaResult? cpa;
  final ScrollController scrollController;

  const _TargetDetailSheet({
    required this.target,
    this.cpa,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final shipTypeName = target.shipType != null
        ? AisStaticVoyage.shipTypeName(target.shipType!)
        : 'Unknown';

    final navStatus = target.navStatus != null
        ? _navStatusName(target.navStatus!)
        : null;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Text(
          target.displayName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        _row('MMSI', target.mmsi.toString()),
        if (target.callSign != null) _row('Call Sign', target.callSign!),
        _row('Ship Type', shipTypeName),
        if (navStatus != null) _row('Nav Status', navStatus),
        _row('SOG', '${target.sogKnots.toStringAsFixed(1)} kn'),
        _row('COG', '${target.cogDegrees.toStringAsFixed(1)}°'),
        if (target.headingTrue != null)
          _row('Heading', '${target.headingTrue!.toStringAsFixed(1)}°'),
        if (cpa != null) ...[
          const Divider(),
          _row('CPA', '${cpa!.cpaNm.toStringAsFixed(2)} nm'),
          _row(
            'TCPA',
            cpa!.tcpaMinutes < 0
                ? 'Diverging'
                : cpa!.tcpaMinutes == double.infinity
                    ? 'N/A'
                    : '${cpa!.tcpaMinutes.toStringAsFixed(1)} min',
          ),
        ],
        if (target.lengthMetres > 0)
          _row('Size', '${target.lengthMetres}m x ${target.beamMetres}m'),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _row(String label, String value) {
    return SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  String _navStatusName(int status) {
    const names = {
      0: 'Under way using engine',
      1: 'At anchor',
      2: 'Not under command',
      3: 'Restricted manoeuvrability',
      4: 'Constrained by draught',
      5: 'Moored',
      6: 'Aground',
      7: 'Engaged in fishing',
      8: 'Under way sailing',
      11: 'Power-driven towing astern',
      12: 'Power-driven pushing ahead',
      14: 'AIS-SART',
    };
    return names[status] ?? 'Unknown ($status)';
  }
}
