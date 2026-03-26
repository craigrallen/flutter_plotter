import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ais/messages/static_voyage.dart';
import '../../data/models/ais_target.dart';
import '../../data/providers/ais_provider.dart';
import '../../data/providers/vessel_provider.dart';

/// AIS target list, sorted by CPA (closest first).
class TargetListScreen extends ConsumerWidget {
  const TargetListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(aisProvider);
    final vessel = ref.watch(vesselProvider);

    // Build sorted list with CPA
    final entries = <_TargetEntry>[];
    for (final target in targets.values) {
      if (target.isStale) continue;
      CpaResult? cpa;
      if (vessel.position != null) {
        cpa = target.computeCpa(
          vessel.position!,
          vessel.sog ?? 0,
          vessel.cog ?? 0,
        );
      }
      entries.add(_TargetEntry(target: target, cpa: cpa));
    }

    // Sort by CPA ascending (closest first), diverging targets last
    entries.sort((a, b) {
      final aCpa = a.cpa?.cpaNm ?? double.infinity;
      final bCpa = b.cpa?.cpaNm ?? double.infinity;
      return aCpa.compareTo(bCpa);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('AIS Targets')),
      body: entries.isEmpty
          ? const Center(child: Text('No AIS targets'))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final e = entries[index];
                return _TargetTile(entry: e);
              },
            ),
    );
  }
}

class _TargetEntry {
  final AisTarget target;
  final CpaResult? cpa;

  _TargetEntry({required this.target, this.cpa});
}

class _TargetTile extends StatelessWidget {
  final _TargetEntry entry;

  const _TargetTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final target = entry.target;
    final cpa = entry.cpa;
    final threat = cpa?.threatLevel ?? ThreatLevel.safe;

    final color = switch (threat) {
      ThreatLevel.safe => Colors.green,
      ThreatLevel.caution => Colors.orange,
      ThreatLevel.danger => Colors.red,
    };

    final shipType = target.shipType != null
        ? AisStaticVoyage.shipTypeName(target.shipType!)
        : '';

    final cpaStr = cpa != null ? '${cpa.cpaNm.toStringAsFixed(2)} nm' : '--';
    final tcpaStr = cpa != null
        ? (cpa.tcpaMinutes < 0
            ? 'Div'
            : cpa.tcpaMinutes == double.infinity
                ? '--'
                : '${cpa.tcpaMinutes.toStringAsFixed(0)} min')
        : '--';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        child: target.isAtoN
            ? const Icon(Icons.location_on, color: Colors.white, size: 20)
            : const Icon(Icons.sailing, color: Colors.white, size: 20),
      ),
      title: Text(target.displayName),
      subtitle: Text(
        '${target.sogKnots.toStringAsFixed(1)} kn  '
        '${target.cogDegrees.toStringAsFixed(0)}°  '
        '$shipType',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('CPA $cpaStr', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          Text('TCPA $tcpaStr', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
