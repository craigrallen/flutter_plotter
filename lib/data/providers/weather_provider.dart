import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/weather/weather_service.dart';
import '../../data/models/weather_forecast.dart';
import 'vessel_provider.dart';

final weatherServiceProvider =
    Provider<WeatherService>((ref) => WeatherService());

/// The active weather overlay mode.
enum WeatherOverlay { off, wind, waves }

final weatherOverlayProvider =
    StateProvider<WeatherOverlay>((ref) => WeatherOverlay.off);

/// The time index into the hourly forecast (0 = now, up to 47).
final weatherTimeIndexProvider = StateProvider<int>((ref) => 0);

/// Fetched weather grid around current vessel position.
final weatherGridProvider =
    FutureProvider<List<WeatherForecast>>((ref) async {
  final vessel = ref.watch(vesselProvider);
  final pos = vessel.position;
  if (pos == null) return [];
  final svc = ref.read(weatherServiceProvider);
  return svc.fetchGrid(pos);
});

/// Weather points at the currently selected time index.
final weatherPointsAtTimeProvider =
    Provider<List<WeatherPoint>>((ref) {
  final grid = ref.watch(weatherGridProvider);
  final timeIdx = ref.watch(weatherTimeIndexProvider);

  return grid.when(
    data: (forecasts) {
      final points = <WeatherPoint>[];
      for (final fc in forecasts) {
        if (timeIdx < fc.hourly.length) {
          points.add(fc.hourly[timeIdx]);
        }
      }
      return points;
    },
    loading: () => [],
    error: (_, _) => [],
  );
});
