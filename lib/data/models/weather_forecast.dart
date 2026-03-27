import 'package:latlong2/latlong.dart';

class WeatherPoint {
  final LatLng position;
  final DateTime time;
  final double windSpeedKn;
  final double windDirectionDeg;
  final double precipitationMm;
  final double? waveHeightM;

  const WeatherPoint({
    required this.position,
    required this.time,
    required this.windSpeedKn,
    required this.windDirectionDeg,
    required this.precipitationMm,
    this.waveHeightM,
  });
}

class WeatherForecast {
  final LatLng position;
  final List<WeatherPoint> hourly;
  final DateTime fetchedAt;

  const WeatherForecast({
    required this.position,
    required this.hourly,
    required this.fetchedAt,
  });
}
