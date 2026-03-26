import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/vessel_state.dart';

/// Provides the current vessel state, streaming from device GPS.
/// When NMEA data is available it takes priority over device GPS.
class VesselNotifier extends StateNotifier<VesselState> {
  StreamSubscription<Position>? _gpsSub;
  DateTime? _lastNmeaUpdate;

  VesselNotifier() : super(const VesselState()) {
    _startGps();
  }

  /// True if we've received NMEA data in the last 5 seconds.
  bool get _nmeaActive =>
      _lastNmeaUpdate != null &&
      DateTime.now().difference(_lastNmeaUpdate!).inSeconds < 5;

  Future<void> _startGps() async {
    final permission = await _ensurePermission();
    if (!permission) return;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        // Only use device GPS if NMEA is not active.
        if (_nmeaActive) return;

        state = VesselState(
          position: LatLng(pos.latitude, pos.longitude),
          sog: pos.speed * 1.94384, // m/s → knots
          cog: pos.heading,
          heading: pos.heading,
          source: PositionSource.deviceGps,
          timestamp: pos.timestamp,
        );
      },
    );
  }

  /// Called by NMEA processor when navigation data is received.
  void updateFromNmea({
    double? latitude,
    double? longitude,
    double? sog,
    double? cog,
    double? heading,
  }) {
    _lastNmeaUpdate = DateTime.now();

    LatLng? pos;
    if (latitude != null && longitude != null) {
      pos = LatLng(latitude, longitude);
    }

    state = state.copyWith(
      position: pos ?? state.position,
      sog: sog ?? state.sog,
      cog: cog ?? state.cog,
      heading: heading ?? state.heading,
      source: PositionSource.nmeaGps,
      timestamp: DateTime.now(),
    );
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    super.dispose();
  }
}

final vesselProvider =
    StateNotifierProvider<VesselNotifier, VesselState>((ref) {
  return VesselNotifier();
});
