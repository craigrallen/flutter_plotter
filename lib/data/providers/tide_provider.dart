import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/tides/tide_service.dart';
import '../../core/tides/tide_station.dart';
import '../models/tide_prediction.dart';
import 'vessel_provider.dart';

final tideServiceProvider = Provider<TideService>((ref) => TideService());

/// Nearest tide stations to current vessel position.
final nearestTideStationsProvider =
    FutureProvider<List<TideStation>>((ref) async {
  final vessel = ref.watch(vesselProvider);
  final pos = vessel.position;
  if (pos == null) return [];
  final svc = ref.read(tideServiceProvider);
  return svc.nearestStations(pos, count: 5);
});

/// Predictions for a specific station.
final tidePredictionsProvider =
    FutureProvider.family<List<TidePrediction>, String>((ref, stationId) async {
  final svc = ref.read(tideServiceProvider);
  return svc.fetchPredictions(stationId);
});

/// Derived: nearest station (first in list).
final nearestTideStationProvider = Provider<TideStation?>((ref) {
  final stations = ref.watch(nearestTideStationsProvider);
  return stations.whenOrNull(data: (list) => list.isEmpty ? null : list.first);
});

/// Current interpolated tide height and next hi/lo event for nearest station.
final currentTideProvider =
    FutureProvider<CurrentTideInfo?>((ref) async {
  final station = ref.watch(nearestTideStationProvider);
  if (station == null) return null;

  final predictions =
      await ref.watch(tidePredictionsProvider(station.id).future);
  if (predictions.isEmpty) return null;

  final now = DateTime.now().toUtc();

  // Find bracketing hi/lo events around now.
  TidePrediction? prev;
  TidePrediction? next;
  for (final p in predictions) {
    if (p.time.isBefore(now)) {
      prev = p;
    } else {
      next = p;
      break;
    }
  }

  if (prev == null || next == null) {
    return CurrentTideInfo(
      stationName: station.name,
      interpolatedHeight: predictions.first.heightM,
      nextEvent: predictions.firstWhere((p) => p.time.isAfter(now),
          orElse: () => predictions.last),
      timeToNext: predictions
          .firstWhere((p) => p.time.isAfter(now),
              orElse: () => predictions.last)
          .time
          .difference(now),
    );
  }

  // Sinusoidal interpolation between prev and next.
  final totalDuration = next.time.difference(prev.time).inSeconds.toDouble();
  final elapsed = now.difference(prev.time).inSeconds.toDouble();
  final fraction = elapsed / totalDuration;

  // Cosine interpolation: smooth transition between hi/lo.
  final t = (1 - cos(fraction * pi)) / 2;
  final height = prev.heightM + (next.heightM - prev.heightM) * t;

  return CurrentTideInfo(
    stationName: station.name,
    interpolatedHeight: height,
    nextEvent: next,
    timeToNext: next.time.difference(now),
  );
});


class CurrentTideInfo {
  final String stationName;
  final double interpolatedHeight;
  final TidePrediction nextEvent;
  final Duration timeToNext;

  const CurrentTideInfo({
    required this.stationName,
    required this.interpolatedHeight,
    required this.nextEvent,
    required this.timeToNext,
  });
}
