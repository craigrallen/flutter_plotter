import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/vessel_state.dart';

/// Provides the current vessel state, streaming from device GPS.
/// In Phase 2 this will also accept NMEA input and prefer it over device GPS.
class VesselNotifier extends StateNotifier<VesselState> {
  StreamSubscription<Position>? _gpsSub;

  VesselNotifier() : super(const VesselState()) {
    _startGps();
  }

  Future<void> _startGps() async {
    final permission = await _ensurePermission();
    if (!permission) return;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
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
