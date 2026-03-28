import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/nav/geo.dart';
import '../models/ais_target.dart';
import 'ais_provider.dart';
import 'vessel_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

/// A single AIS target enriched with CPA data and bearing/distance.
class AisCpaEntry {
  final AisTarget target;
  final CpaResult cpa;
  final double bearingDeg;
  final double distanceNm;

  const AisCpaEntry({
    required this.target,
    required this.cpa,
    required this.bearingDeg,
    required this.distanceNm,
  });

  /// True when target has enough motion data for CPA calculation.
  bool get isMoving => target.sogKnots > 0.5;
}

// ─────────────────────────────────────────────────────────────────────────────
// Display threshold settings
// ─────────────────────────────────────────────────────────────────────────────

/// User-configurable display thresholds for the CPA screen.
class AisCpaScreenSettings {
  final double maxCpaNm;
  final double maxTcpaMin;

  const AisCpaScreenSettings({
    this.maxCpaNm = 1.0,
    this.maxTcpaMin = 30.0,
  });

  AisCpaScreenSettings copyWith({double? maxCpaNm, double? maxTcpaMin}) =>
      AisCpaScreenSettings(
        maxCpaNm: maxCpaNm ?? this.maxCpaNm,
        maxTcpaMin: maxTcpaMin ?? this.maxTcpaMin,
      );
}

final aisCpaScreenSettingsProvider =
    StateProvider<AisCpaScreenSettings>((ref) => const AisCpaScreenSettings());

// ─────────────────────────────────────────────────────────────────────────────
// CPA computation notifier — refreshes every 10 seconds
// ─────────────────────────────────────────────────────────────────────────────

class AisCpaNotifier extends StateNotifier<List<AisCpaEntry>> {
  final Ref _ref;
  Timer? _timer;

  AisCpaNotifier(this._ref) : super([]) {
    _compute();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _compute());
  }

  /// Force an immediate recompute (called after settings change, etc.).
  void forceRefresh() => _compute();

  void _compute() {
    final targets = _ref.read(aisProvider);
    final vessel = _ref.read(vesselProvider);
    final settings = _ref.read(aisCpaScreenSettingsProvider);

    final ownPos = vessel.position;
    final ownSog = vessel.sog ?? 0.0;
    final ownCog = vessel.cog ?? 0.0;

    if (ownPos == null) {
      state = [];
      return;
    }

    final entries = <AisCpaEntry>[];

    for (final target in targets.values) {
      if (target.isStale || target.isAtoN) continue;

      final cpa = target.computeCpa(ownPos, ownSog, ownCog);
      final bearing = initialBearing(ownPos, target.position);
      final dist = haversineDistanceNm(ownPos, target.position);

      final isMoving = target.sogKnots > 0.5;

      if (isMoving) {
        // Diverging targets — skip
        if (cpa.tcpaMinutes < 0) continue;
        // Past TCPA threshold — skip (allow infinity for no-relative-motion edge case)
        if (cpa.tcpaMinutes != double.infinity &&
            cpa.tcpaMinutes > settings.maxTcpaMin) {
          continue;
        }
        // CPA beyond display range — skip
        if (cpa.cpaNm > settings.maxCpaNm) continue;
      } else {
        // Stationary — show by current distance only
        if (dist > settings.maxCpaNm) continue;
      }

      entries.add(AisCpaEntry(
        target: target,
        cpa: cpa,
        bearingDeg: bearing,
        distanceNm: dist,
      ));
    }

    // Sort ascending by CPA distance
    entries.sort((a, b) => a.cpa.cpaNm.compareTo(b.cpa.cpaNm));

    state = entries;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final aisCpaProvider =
    StateNotifierProvider<AisCpaNotifier, List<AisCpaEntry>>((ref) {
  return AisCpaNotifier(ref);
});

/// True if any entry is in the red danger zone.
final aisCpaDangerProvider = Provider<bool>((ref) {
  return ref.watch(aisCpaProvider).any(
    (e) => e.cpa.threatLevel == ThreatLevel.danger,
  );
});
