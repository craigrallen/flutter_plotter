import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ais/messages/static_voyage.dart';
import '../../data/models/ais_target.dart';
import '../../data/providers/ais_cpa_provider.dart';
import '../../data/providers/vessel_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CPA threshold options
// ─────────────────────────────────────────────────────────────────────────────

const _kCpaOptions = <double>[0.25, 0.5, 1.0, 2.0];
const _kTcpaOptions = <double>[5, 10, 20, 30, 60];

// ─────────────────────────────────────────────────────────────────────────────
// Screen root
// ─────────────────────────────────────────────────────────────────────────────

class AisCpaScreen extends ConsumerStatefulWidget {
  const AisCpaScreen({super.key});

  @override
  ConsumerState<AisCpaScreen> createState() => _AisCpaScreenState();
}

class _AisCpaScreenState extends ConsumerState<AisCpaScreen> {
  AisCpaEntry? _selected;
  bool _alarmAcknowledged = false;
  bool _settingsOpen = false;

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(aisCpaProvider);
    final inDanger = ref.watch(aisCpaDangerProvider);

    // Trigger vibration when a vessel enters the danger zone and alarm
    // has not yet been acknowledged this session.
    if (inDanger && !_alarmAcknowledged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HapticFeedback.vibrate();
      });
    }

    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 700;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collision Alerting'),
        actions: [
          if (inDanger && !_alarmAcknowledged)
            IconButton(
              icon: const Icon(Icons.notifications_active),
              color: Colors.red,
              tooltip: 'Acknowledge alarm',
              onPressed: () => setState(() => _alarmAcknowledged = true),
            ),
          IconButton(
            icon: Icon(_settingsOpen ? Icons.tune : Icons.tune_outlined),
            tooltip: 'Thresholds',
            onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
          ),
        ],
      ),
      body: Column(
        children: [
          // Danger banner
          if (inDanger && !_alarmAcknowledged)
            _DangerBanner(
              onAcknowledge: () =>
                  setState(() => _alarmAcknowledged = true),
            ),
          // Re-arm alarm when danger clears
          if (!inDanger && _alarmAcknowledged)
            Builder(builder: (_) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _alarmAcknowledged) {
                  setState(() => _alarmAcknowledged = false);
                }
              });
              return const SizedBox.shrink();
            }),
          // Settings panel
          if (_settingsOpen) const _SettingsPanel(),
          // Main content
          Expanded(
            child: isTablet
                ? _TabletLayout(
                    entries: entries,
                    selected: _selected,
                    onSelect: (e) => setState(() => _selected = e),
                  )
                : _PhoneLayout(entries: entries),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Danger banner
// ─────────────────────────────────────────────────────────────────────────────

class _DangerBanner extends StatelessWidget {
  final VoidCallback onAcknowledge;

  const _DangerBanner({required this.onAcknowledge});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.red.shade700,
      child: InkWell(
        onTap: onAcknowledge,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.white),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'COLLISION RISK — vessel within danger zone',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: onAcknowledge,
                child: const Text(
                  'ACK',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings panel
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsPanel extends ConsumerWidget {
  const _SettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(aisCpaScreenSettingsProvider);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Display thresholds',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.radar, size: 18),
                const SizedBox(width: 8),
                const Text('CPA limit'),
                const Spacer(),
                DropdownButton<double>(
                  value: settings.maxCpaNm,
                  items: _kCpaOptions
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text('${v.toStringAsFixed(2)} nm'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(aisCpaScreenSettingsProvider.notifier)
                          .state = settings.copyWith(maxCpaNm: v);
                      ref.read(aisCpaProvider.notifier).forceRefresh();
                    }
                  },
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.timer, size: 18),
                const SizedBox(width: 8),
                const Text('TCPA limit'),
                const Spacer(),
                DropdownButton<double>(
                  value: settings.maxTcpaMin,
                  items: _kTcpaOptions
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text('${v.toStringAsFixed(0)} min'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(aisCpaScreenSettingsProvider.notifier)
                          .state = settings.copyWith(maxTcpaMin: v);
                      ref.read(aisCpaProvider.notifier).forceRefresh();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phone layout — list only
// ─────────────────────────────────────────────────────────────────────────────

class _PhoneLayout extends StatelessWidget {
  final List<AisCpaEntry> entries;

  const _PhoneLayout({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
            SizedBox(height: 12),
            Text('No collision threats in range'),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, unused) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final entry = entries[i];
        return _TargetTile(
          entry: entry,
          onTap: () => _showDetailSheet(context, entry),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tablet layout — list + detail pane
// ─────────────────────────────────────────────────────────────────────────────

class _TabletLayout extends StatelessWidget {
  final List<AisCpaEntry> entries;
  final AisCpaEntry? selected;
  final ValueChanged<AisCpaEntry> onSelect;

  const _TabletLayout({
    required this.entries,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 340,
          child: entries.isEmpty
              ? const Center(child: Text('No collision threats in range'))
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, unused) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final entry = entries[i];
                    return _TargetTile(
                      entry: entry,
                      selected: selected?.target.mmsi == entry.target.mmsi,
                      onTap: () => onSelect(entry),
                    );
                  },
                ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const Center(
                  child: Text('Select a vessel to view CPA detail'),
                )
              : _CpaDetailPane(entry: selected!),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Target tile
// ─────────────────────────────────────────────────────────────────────────────

class _TargetTile extends StatelessWidget {
  final AisCpaEntry entry;
  final bool selected;
  final VoidCallback onTap;

  const _TargetTile({
    required this.entry,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final target = entry.target;
    final cpa = entry.cpa;
    final level = cpa.threatLevel;

    final rowColor = switch (level) {
      ThreatLevel.danger => Colors.red,
      ThreatLevel.caution => Colors.orange,
      ThreatLevel.safe => Colors.grey,
    };

    final tcpaStr = entry.isMoving
        ? (cpa.tcpaMinutes == double.infinity
            ? '--'
            : '${cpa.tcpaMinutes.toStringAsFixed(0)} min')
        : 'anchored';

    final shipTypeStr = target.shipType != null
        ? AisStaticVoyage.shipTypeName(target.shipType!)
        : '';

    return ListTile(
      selected: selected,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: rowColor,
        child: Icon(
          _shipIcon(target.shipType),
          color: Colors.white,
          size: 20,
        ),
      ),
      title: Text(
        target.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${target.sogKnots.toStringAsFixed(1)} kn  '
        '${target.cogDegrees.toStringAsFixed(0)}${String.fromCharCode(0x00B0)}  '
        '$shipTypeStr',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'CPA ${cpa.cpaNm.toStringAsFixed(2)} nm',
            style: TextStyle(
              color: rowColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          Text(
            'TCPA $tcpaStr',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'Brg ${entry.bearingDeg.toStringAsFixed(0)}${String.fromCharCode(0x00B0)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail sheet (phone) + detail pane (tablet)
// ─────────────────────────────────────────────────────────────────────────────

void _showDetailSheet(BuildContext context, AisCpaEntry entry) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        child: _CpaDetailPane(entry: entry),
      ),
    ),
  );
}

class _CpaDetailPane extends ConsumerWidget {
  final AisCpaEntry entry;

  const _CpaDetailPane({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vessel = ref.watch(vesselProvider);
    final target = entry.target;
    final cpa = entry.cpa;
    final theme = Theme.of(context);

    final ownSog = vessel.sog ?? 0.0;
    final ownCog = vessel.cog ?? 0.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                _shipIcon(target.shipType),
                size: 32,
                color: _threatColor(cpa.threatLevel),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target.displayName,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (target.vesselName != null)
                      Text(
                        'MMSI ${target.mmsi}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // CPA diagram
          SizedBox(
            height: 200,
            child: _CpaDiagram(
              ownCog: ownCog,
              ownSog: ownSog,
              targetCog: target.cogDegrees,
              targetSog: target.sogKnots,
              bearingToTarget: entry.bearingDeg,
              distanceNm: entry.distanceNm,
              cpaNm: cpa.cpaNm,
              tcpaMin: cpa.tcpaMinutes,
            ),
          ),
          const SizedBox(height: 16),

          // Stats grid
          _StatsRow('CPA', '${cpa.cpaNm.toStringAsFixed(3)} nm'),
          _StatsRow(
            'TCPA',
            cpa.tcpaMinutes < 0
                ? 'Diverging'
                : cpa.tcpaMinutes == double.infinity
                    ? 'No relative motion'
                    : '${cpa.tcpaMinutes.toStringAsFixed(1)} min',
          ),
          _StatsRow('Bearing', '${entry.bearingDeg.toStringAsFixed(1)} T'),
          _StatsRow('Distance', '${entry.distanceNm.toStringAsFixed(2)} nm'),
          _StatsRow('Target SOG', '${target.sogKnots.toStringAsFixed(1)} kn'),
          _StatsRow(
              'Target COG', '${target.cogDegrees.toStringAsFixed(1)} T'),
          if (target.navStatus != null)
            _StatsRow('Nav status', _navStatusStr(target.navStatus!)),
          if (target.shipType != null)
            _StatsRow(
                'Ship type', AisStaticVoyage.shipTypeName(target.shipType!)),

          const Divider(height: 24),

          // COLREGS guidance
          Text(
            'COLREGS Guidance',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _ColregsAdvice(
            ownCog: ownCog,
            targetCog: target.cogDegrees,
            bearingToTarget: entry.bearingDeg,
            threat: cpa.threatLevel,
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatsRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey)),
          ),
          Text(value),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CPA geometry diagram — custom painter
// ─────────────────────────────────────────────────────────────────────────────

class _CpaDiagram extends StatelessWidget {
  final double ownCog;
  final double ownSog;
  final double targetCog;
  final double targetSog;
  final double bearingToTarget;
  final double distanceNm;
  final double cpaNm;
  final double tcpaMin;

  const _CpaDiagram({
    required this.ownCog,
    required this.ownSog,
    required this.targetCog,
    required this.targetSog,
    required this.bearingToTarget,
    required this.distanceNm,
    required this.cpaNm,
    required this.tcpaMin,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CpaPainter(
        ownCog: ownCog,
        ownSog: ownSog,
        targetCog: targetCog,
        targetSog: targetSog,
        bearingToTarget: bearingToTarget,
        distanceNm: distanceNm,
        cpaNm: cpaNm,
        tcpaMin: tcpaMin,
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _CpaPainter extends CustomPainter {
  final double ownCog;
  final double ownSog;
  final double targetCog;
  final double targetSog;
  final double bearingToTarget;
  final double distanceNm;
  final double cpaNm;
  final double tcpaMin;
  final bool isDark;

  _CpaPainter({
    required this.ownCog,
    required this.ownSog,
    required this.targetCog,
    required this.targetSog,
    required this.bearingToTarget,
    required this.distanceNm,
    required this.cpaNm,
    required this.tcpaMin,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.65);
    final maxDimNm = distanceNm * 1.3;
    final scale = (size.height * 0.55) / (maxDimNm > 0 ? maxDimNm : 1.0);

    final textColor = isDark ? Colors.white : Colors.black87;

    // Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = isDark ? Colors.black12 : Colors.grey.shade100,
    );

    // Own vessel (center)
    final ownPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2;
    canvas.drawCircle(center, 6, ownPaint..style = PaintingStyle.fill);

    // Own course vector
    final ownVecLen = ownSog * scale * 1.5;
    final ownCogRad = (ownCog - 90) * math.pi / 180;
    final ownEnd = center +
        Offset(math.cos(ownCogRad) * ownVecLen, math.sin(ownCogRad) * ownVecLen);
    _drawArrow(canvas, center, ownEnd, Colors.blue, 2);

    // Target position
    final bearRad = (bearingToTarget - 90) * math.pi / 180;
    final tgtOffset = Offset(
      math.cos(bearRad) * distanceNm * scale,
      math.sin(bearRad) * distanceNm * scale,
    );
    final tgtCenter = center + tgtOffset;

    final tgtPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2;
    canvas.drawCircle(tgtCenter, 6, tgtPaint..style = PaintingStyle.fill);

    // Target course vector
    final tgtVecLen = targetSog * scale * 1.5;
    final tgtCogRad = (targetCog - 90) * math.pi / 180;
    final tgtEnd = tgtCenter +
        Offset(
            math.cos(tgtCogRad) * tgtVecLen, math.sin(tgtCogRad) * tgtVecLen);
    _drawArrow(canvas, tgtCenter, tgtEnd, Colors.red, 2);

    // CPA point — only meaningful when moving
    if (tcpaMin > 0 && tcpaMin != double.infinity) {
      // Own position at TCPA
      final ownAtCpa = center +
          Offset(math.cos(ownCogRad) * ownSog * tcpaMin * scale / 60,
              math.sin(ownCogRad) * ownSog * tcpaMin * scale / 60);
      // Tgt position at TCPA
      final tgtAtCpa = tgtCenter +
          Offset(math.cos(tgtCogRad) * targetSog * tcpaMin * scale / 60,
              math.sin(tgtCogRad) * targetSog * tcpaMin * scale / 60);

      // Dashed lines to CPA points
      _drawDashed(canvas, center, ownAtCpa, Colors.blue.withValues(alpha: 0.5));
      _drawDashed(canvas, tgtCenter, tgtAtCpa, Colors.red.withValues(alpha: 0.5));

      // CPA connector
      final cpaMidPaint = Paint()
        ..color = Colors.orange
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(ownAtCpa, tgtAtCpa, cpaMidPaint);

      // CPA distance label
      final mid = (ownAtCpa + tgtAtCpa) / 2;
      _drawLabel(canvas, '${cpaNm.toStringAsFixed(2)}nm', mid, textColor);
    }

    // Legend labels
    _drawLabel(canvas, 'Own', center + const Offset(8, 8), Colors.blue);
    _drawLabel(canvas, 'Target', tgtCenter + const Offset(8, 8), Colors.red);
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color,
      double width) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    canvas.drawLine(from, to, paint);

    // Arrowhead
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    const arrowLen = 10.0;
    const arrowAngle = 0.4;
    final p1 = to +
        Offset(math.cos(angle + math.pi - arrowAngle) * arrowLen,
            math.sin(angle + math.pi - arrowAngle) * arrowLen);
    final p2 = to +
        Offset(math.cos(angle + math.pi + arrowAngle) * arrowLen,
            math.sin(angle + math.pi + arrowAngle) * arrowLen);
    canvas.drawLine(to, p1, paint);
    canvas.drawLine(to, p2, paint);
  }

  void _drawDashed(Canvas canvas, Offset from, Offset to, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    const dashLen = 6.0;
    const gapLen = 4.0;
    double dist = 0;
    while (dist < len) {
      final t1 = dist / len;
      final t2 = math.min((dist + dashLen) / len, 1.0);
      canvas.drawLine(
        Offset(from.dx + dx * t1, from.dy + dy * t1),
        Offset(from.dx + dx * t2, from.dy + dy * t2),
        paint,
      );
      dist += dashLen + gapLen;
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(_CpaPainter old) =>
      old.ownCog != ownCog ||
      old.targetCog != targetCog ||
      old.distanceNm != distanceNm;
}

// ─────────────────────────────────────────────────────────────────────────────
// COLREGS advice
// ─────────────────────────────────────────────────────────────────────────────

class _ColregsAdvice extends StatelessWidget {
  final double ownCog;
  final double targetCog;
  final double bearingToTarget;
  final ThreatLevel threat;

  const _ColregsAdvice({
    required this.ownCog,
    required this.targetCog,
    required this.bearingToTarget,
    required this.threat,
  });

  @override
  Widget build(BuildContext context) {
    if (threat == ThreatLevel.safe) {
      return Row(
        children: const [
          Icon(Icons.check_circle, color: Colors.green, size: 20),
          SizedBox(width: 8),
          Expanded(child: Text('No immediate action required.')),
        ],
      );
    }

    // Relative bearing from own heading to target
    final relBearing = ((bearingToTarget - ownCog) + 360) % 360;
    final String advice;
    final IconData icon;

    if (relBearing >= 355 || relBearing < 5) {
      // Head-on — Rule 14
      advice = 'HEAD-ON (Rule 14): Both vessels must alter course to starboard.';
      icon = Icons.compare_arrows;
    } else if (relBearing >= 5 && relBearing < 112.5) {
      // Target on own starboard bow — Rule 15, you are the give-way vessel
      advice = 'CROSSING (Rule 15): Target is on your starboard side — '
          'YOU are the give-way vessel. Alter course to starboard or slow down.';
      icon = Icons.turn_right;
    } else if (relBearing >= 112.5 && relBearing < 247.5) {
      // Target overtaking from behind or broad on port quarter
      advice = 'OVERTAKING (Rule 13) or target on port side — '
          'you are the stand-on vessel. Maintain course and speed.';
      icon = Icons.straight;
    } else {
      // Target on port bow — you are stand-on
      advice = 'CROSSING (Rule 15): Target is on your port side — '
          'you are the stand-on vessel. Maintain course; be ready to manoeuvre.';
      icon = Icons.turn_left;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: threat == ThreatLevel.danger ? Colors.red : Colors.orange, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(advice)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Color _threatColor(ThreatLevel level) => switch (level) {
      ThreatLevel.danger => Colors.red,
      ThreatLevel.caution => Colors.orange,
      ThreatLevel.safe => Colors.grey,
    };

IconData _shipIcon(int? shipType) {
  if (shipType == null) return Icons.sailing;
  if (shipType >= 60 && shipType <= 69) return Icons.directions_ferry;
  if (shipType >= 70 && shipType <= 79) return Icons.local_shipping;
  if (shipType >= 80 && shipType <= 89) return Icons.oil_barrel;
  if (shipType == 30) return Icons.phishing;
  if (shipType == 36 || shipType == 37) return Icons.kitesurfing;
  return Icons.sailing;
}

String _navStatusStr(int status) => switch (status) {
      0 => 'Under way using engine',
      1 => 'At anchor',
      2 => 'Not under command',
      3 => 'Restricted manoeuvrability',
      5 => 'Moored',
      6 => 'Aground',
      7 => 'Engaged in fishing',
      8 => 'Under way sailing',
      _ => 'Status $status',
    };
