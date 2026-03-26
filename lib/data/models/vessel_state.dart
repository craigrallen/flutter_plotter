import 'package:latlong2/latlong.dart';

enum PositionSource { none, deviceGps, nmeaGps }

class VesselState {
  final LatLng? position;
  final double? sog; // knots
  final double? cog; // degrees true
  final double? heading; // degrees true
  final PositionSource source;
  final DateTime? timestamp;

  const VesselState({
    this.position,
    this.sog,
    this.cog,
    this.heading,
    this.source = PositionSource.none,
    this.timestamp,
  });

  VesselState copyWith({
    LatLng? position,
    double? sog,
    double? cog,
    double? heading,
    PositionSource? source,
    DateTime? timestamp,
  }) {
    return VesselState(
      position: position ?? this.position,
      sog: sog ?? this.sog,
      cog: cog ?? this.cog,
      heading: heading ?? this.heading,
      source: source ?? this.source,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
