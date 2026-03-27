import 'dart:math';
import 'package:latlong2/latlong.dart';

enum PositionSource { none, deviceGps, nmeaGps, signalK }

class VesselState {
  final LatLng? position;
  final double? sog; // knots
  final double? cog; // degrees true
  final double? heading; // degrees true
  final double? depth; // metres (below transducer)
  final double? windSpeed; // knots (apparent)
  final double? windAngle; // degrees (apparent)
  final bool windIsRelative;
  final double? trueWindSpeed; // knots
  final double? trueWindAngle; // degrees
  final double? gpsAccuracy; // metres
  final PositionSource source;
  final DateTime? timestamp;

  const VesselState({
    this.position,
    this.sog,
    this.cog,
    this.heading,
    this.depth,
    this.windSpeed,
    this.windAngle,
    this.windIsRelative = true,
    this.trueWindSpeed,
    this.trueWindAngle,
    this.gpsAccuracy,
    this.source = PositionSource.none,
    this.timestamp,
  });

  /// VMG (Velocity Made Good) towards wind.
  /// Positive = making good progress upwind/downwind.
  double? get vmg {
    if (sog == null || windAngle == null) return null;
    return sog! * cos(windAngle! * pi / 180);
  }

  VesselState copyWith({
    LatLng? position,
    double? sog,
    double? cog,
    double? heading,
    double? depth,
    double? windSpeed,
    double? windAngle,
    bool? windIsRelative,
    double? trueWindSpeed,
    double? trueWindAngle,
    double? gpsAccuracy,
    PositionSource? source,
    DateTime? timestamp,
  }) {
    return VesselState(
      position: position ?? this.position,
      sog: sog ?? this.sog,
      cog: cog ?? this.cog,
      heading: heading ?? this.heading,
      depth: depth ?? this.depth,
      windSpeed: windSpeed ?? this.windSpeed,
      windAngle: windAngle ?? this.windAngle,
      windIsRelative: windIsRelative ?? this.windIsRelative,
      trueWindSpeed: trueWindSpeed ?? this.trueWindSpeed,
      trueWindAngle: trueWindAngle ?? this.trueWindAngle,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      source: source ?? this.source,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
