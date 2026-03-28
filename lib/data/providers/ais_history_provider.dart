import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/ais_target.dart';
import 'ais_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

/// A single historical position fix for a vessel.
class AisTrailPoint {
  final LatLng position;
  final DateTime timestamp;
  final double sogKnots;
  final double cogDegrees;

  const AisTrailPoint({
    required this.position,
    required this.timestamp,
    required this.sogKnots,
    required this.cogDegrees,
  });
}

/// Complete history record for one AIS target.
class AisVesselTrail {
  final int mmsi;
  final String? vesselName;
  final List<AisTrailPoint> points;

  const AisVesselTrail({
    required this.mmsi,
    this.vesselName,
    required this.points,
  });

  String get displayName {
    if (vesselName != null && vesselName!.isNotEmpty) return vesselName!;
    return mmsi.toString();
  }

  AisVesselTrail copyWith({
    String? vesselName,
    List<AisTrailPoint>? points,
  }) =>
      AisVesselTrail(
        mmsi: mmsi,
        vesselName: vesselName ?? this.vesselName,
        points: points ?? this.points,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class AisHistoryState {
  /// Map of MMSI → trail data.
  final Map<int, AisVesselTrail> trails;

  /// How many hours of history to retain and display.
  final int windowHours;

  const AisHistoryState({
    required this.trails,
    this.windowHours = 6,
  });

  AisHistoryState copyWith({
    Map<int, AisVesselTrail>? trails,
    int? windowHours,
  }) =>
      AisHistoryState(
        trails: trails ?? this.trails,
        windowHours: windowHours ?? this.windowHours,
      );

  /// Returns trails filtered to [windowHours], with at least 2 points.
  List<AisVesselTrail> get visibleTrails {
    final cutoff =
        DateTime.now().subtract(Duration(hours: windowHours));
    final result = <AisVesselTrail>[];
    for (final trail in trails.values) {
      final recent =
          trail.points.where((p) => p.timestamp.isAfter(cutoff)).toList();
      if (recent.length >= 2) {
        result.add(trail.copyWith(points: recent));
      }
    }
    return result;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

/// Max history retention: 24 hours, max 500 points per vessel.
const _kMaxHistoryHours = 24;
const _kMaxPointsPerVessel = 500;
/// Minimum distance (metres) before a new point is added (reduce noise).
const _kMinDistanceMetres = 20.0;

class AisHistoryNotifier extends StateNotifier<AisHistoryState> {
  Timer? _cleanupTimer;

  AisHistoryNotifier() : super(const AisHistoryState(trails: {})) {
    // Periodic cleanup to evict old data.
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _pruneOldPoints(),
    );
  }

  /// Called by a listener whenever the aisProvider state changes.
  void recordSnapshot(Map<int, AisTarget> targets) {
    final now = DateTime.now();
    final updated = Map<int, AisVesselTrail>.from(state.trails);
    bool changed = false;

    for (final entry in targets.entries) {
      final mmsi = entry.key;
      final target = entry.value;

      // Skip stale or stationary anchored vessels.
      if (target.position.latitude == 0 && target.position.longitude == 0) {
        continue;
      }

      final existing = updated[mmsi];
      final newPoint = AisTrailPoint(
        position: target.position,
        timestamp: now,
        sogKnots: target.sogKnots,
        cogDegrees: target.cogDegrees,
      );

      if (existing == null) {
        updated[mmsi] = AisVesselTrail(
          mmsi: mmsi,
          vesselName: target.vesselName,
          points: [newPoint],
        );
        changed = true;
      } else {
        // Check minimum distance to avoid filling with near-static points.
        final lastPoint = existing.points.last;
        final distMetres = const Distance().as(
          LengthUnit.Meter,
          lastPoint.position,
          target.position,
        );

        if (distMetres >= _kMinDistanceMetres) {
          var pts = [...existing.points, newPoint];
          // Cap at max points per vessel.
          if (pts.length > _kMaxPointsPerVessel) {
            pts = pts.sublist(pts.length - _kMaxPointsPerVessel);
          }
          updated[mmsi] = existing.copyWith(
            vesselName: target.vesselName ?? existing.vesselName,
            points: pts,
          );
          changed = true;
        } else if (target.vesselName != null &&
            target.vesselName != existing.vesselName) {
          // Update name even when position unchanged.
          updated[mmsi] = existing.copyWith(vesselName: target.vesselName);
          changed = true;
        }
      }
    }

    if (changed) state = state.copyWith(trails: updated);
  }

  void setWindowHours(int hours) {
    state = state.copyWith(windowHours: hours);
  }

  void clearTrail(int mmsi) {
    final updated = Map<int, AisVesselTrail>.from(state.trails)
      ..remove(mmsi);
    state = state.copyWith(trails: updated);
  }

  void clearAll() {
    state = state.copyWith(trails: {});
  }

  void _pruneOldPoints() {
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: _kMaxHistoryHours));
    final updated = <int, AisVesselTrail>{};
    for (final trail in state.trails.values) {
      final fresh =
          trail.points.where((p) => p.timestamp.isAfter(cutoff)).toList();
      if (fresh.isNotEmpty) {
        updated[trail.mmsi] = trail.copyWith(points: fresh);
      }
    }
    if (updated.length != state.trails.length) {
      state = state.copyWith(trails: updated);
    }
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final aisHistoryProvider =
    StateNotifierProvider<AisHistoryNotifier, AisHistoryState>((ref) {
  final notifier = AisHistoryNotifier();

  // Watch aisProvider and record every change.
  ref.listen<Map<int, AisTarget>>(aisProvider, (_, targets) {
    notifier.recordSnapshot(targets);
  });

  return notifier;
});
