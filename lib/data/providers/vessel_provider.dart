import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/vessel_state.dart';

/// Provides the current vessel state, streaming from device GPS.
/// When NMEA or Signal K data is available it takes priority over device GPS.
class VesselNotifier extends StateNotifier<VesselState> {
  StreamSubscription<Position>? _gpsSub;
  DateTime? _lastNmeaUpdate;
  DateTime? _lastSignalKUpdate;

  VesselNotifier() : super(const VesselState()) {
    _startGps();
  }

  /// True if we've received NMEA data in the last 5 seconds.
  bool get _nmeaActive =>
      _lastNmeaUpdate != null &&
      DateTime.now().difference(_lastNmeaUpdate!).inSeconds < 5;

  /// True if we've received Signal K data in the last 5 seconds.
  bool get _signalKActive =>
      _lastSignalKUpdate != null &&
      DateTime.now().difference(_lastSignalKUpdate!).inSeconds < 5;

  Future<void> _startGps() async {
    final permission = await _ensurePermission();
    if (!permission) return;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        // Only use device GPS if neither NMEA nor Signal K is active.
        if (_nmeaActive || _signalKActive) return;

        state = VesselState(
          position: LatLng(pos.latitude, pos.longitude),
          sog: pos.speed * 1.94384, // m/s → knots
          cog: pos.heading,
          heading: pos.heading,
          gpsAccuracy: pos.accuracy,
          source: PositionSource.deviceGps,
          timestamp: pos.timestamp,
          // Preserve instrument data from NMEA
          depth: state.depth,
          windSpeed: state.windSpeed,
          windAngle: state.windAngle,
          windIsRelative: state.windIsRelative,
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
    double? depth,
    double? windSpeed,
    double? windAngle,
    bool? windIsRelative,
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
      depth: depth ?? state.depth,
      windSpeed: windSpeed ?? state.windSpeed,
      windAngle: windAngle ?? state.windAngle,
      windIsRelative: windIsRelative ?? state.windIsRelative,
      source: PositionSource.nmeaGps,
      timestamp: DateTime.now(),
    );
  }

  /// Called by Signal K provider when own vessel data is received.
  void updateFromSignalK({
    LatLng? position,
    double? sog,
    double? cog,
    double? heading,
    double? depth,
    double? windSpeedApparent,
    double? windAngleApparent,
    double? windSpeedTrue,
    double? windAngleTrue,
  }) {
    _lastSignalKUpdate = DateTime.now();

    state = state.copyWith(
      position: position ?? state.position,
      sog: sog ?? state.sog,
      cog: cog ?? state.cog,
      heading: heading ?? state.heading,
      depth: depth ?? state.depth,
      windSpeed: windSpeedApparent ?? state.windSpeed,
      windAngle: windAngleApparent ?? state.windAngle,
      windIsRelative: windSpeedApparent != null ? true : state.windIsRelative,
      trueWindSpeed: windSpeedTrue ?? state.trueWindSpeed,
      trueWindAngle: windAngleTrue ?? state.trueWindAngle,
      source: PositionSource.signalK,
      timestamp: DateTime.now(),
    );
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return false;
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  /// Upgrade to "always" location permission — required for anchor watch
  /// to continue monitoring when the app is backgrounded.
  Future<bool> requestAlwaysPermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.always) return true;
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return false;
    }
    // On Android, requestPermission again while whileInUse triggers the
    // "Allow all the time" system dialog.
    perm = await Geolocator.requestPermission();
    return perm == LocationPermission.always;
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
