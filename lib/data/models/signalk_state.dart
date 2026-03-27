import '../../core/signalk/signalk_models.dart';
import '../../core/signalk/signalk_source.dart';

/// Full aggregated state from Signal K server.
class SignalKState {
  /// Own vessel data: navigation, environment, propulsion, tanks, electrical.
  final SignalKVesselData ownVessel;

  /// Other vessels keyed by MMSI.
  final Map<int, AisVesselData> otherVessels;

  /// Active notifications from the server.
  final List<SignalKNotification> notifications;

  /// Connection state.
  final SignalKConnectionState connectionState;

  /// Timestamp of last delta received.
  final DateTime? lastUpdateAt;

  const SignalKState({
    this.ownVessel = const SignalKVesselData(),
    this.otherVessels = const {},
    this.notifications = const [],
    this.connectionState = SignalKConnectionState.disconnected,
    this.lastUpdateAt,
  });

  SignalKState copyWith({
    SignalKVesselData? ownVessel,
    Map<int, AisVesselData>? otherVessels,
    List<SignalKNotification>? notifications,
    SignalKConnectionState? connectionState,
    DateTime? lastUpdateAt,
  }) {
    return SignalKState(
      ownVessel: ownVessel ?? this.ownVessel,
      otherVessels: otherVessels ?? this.otherVessels,
      notifications: notifications ?? this.notifications,
      connectionState: connectionState ?? this.connectionState,
      lastUpdateAt: lastUpdateAt ?? this.lastUpdateAt,
    );
  }
}
