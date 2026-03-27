import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/signalk/signalk_models.dart';
import '../../core/signalk/signalk_parser.dart';
import '../../core/signalk/signalk_source.dart';
import '../models/signalk_state.dart';

/// Manages Signal K connection and aggregated state.
///
/// Consumes the raw delta stream from [SignalKSource], parses each delta
/// via [SignalKParser], and maintains a full [SignalKState] including
/// own vessel data, AIS targets, and notifications.
///
/// Each incoming delta immediately emits a state update — no batching.
class SignalKNotifier extends StateNotifier<SignalKState> {
  SignalKSource? _source;
  final SignalKParser _parser = SignalKParser();
  StreamSubscription<String>? _messageSub;
  StreamSubscription<SignalKConnectionState>? _stateSub;
  Timer? _cleanupTimer;
  Timer? _livePathsTimer;
  Timer? _staleDataTimer;

  SignalKNotifier() : super(const SignalKState()) {
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _removeStaleTargets(),
    );
  }

  /// Connect to a Signal K server.
  Future<void> connect({
    required String host,
    required int port,
    String? token,
  }) async {
    await disconnect();

    _source = SignalKSource(host: host, port: port, token: token);

    _stateSub = _source!.connectionState.listen((connState) {
      state = state.copyWith(connectionState: connState);

      if (connState == SignalKConnectionState.disconnected ||
          connState == SignalKConnectionState.error) {
        _scheduleStaleDataClear();
      } else if (connState == SignalKConnectionState.connected) {
        _cancelStaleDataClear();
      }
    });

    _messageSub = _source!.messages.listen(_handleDelta);

    await _source!.connect();
  }

  Future<void> disconnect() async {
    _messageSub?.cancel();
    _messageSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _livePathsTimer?.cancel();
    _livePathsTimer = null;
    _cancelStaleDataClear();
    _source?.dispose();
    _source = null;
    state = state.copyWith(
      connectionState: SignalKConnectionState.disconnected,
    );
  }

  /// After 30s of disconnect, clear stale own-vessel data.
  void _scheduleStaleDataClear() {
    _staleDataTimer?.cancel();
    _staleDataTimer = Timer(const Duration(seconds: 30), () {
      if (state.connectionState == SignalKConnectionState.disconnected ||
          state.connectionState == SignalKConnectionState.error) {
        state = state.copyWith(
          ownVessel: const SignalKVesselData(),
          lastUpdatedPaths: const {},
        );
      }
    });
  }

  void _cancelStaleDataClear() {
    _staleDataTimer?.cancel();
    _staleDataTimer = null;
  }

  void _handleDelta(String raw) {
    final delta = _parser.parse(raw);
    if (delta == null) return;

    if (delta.isSelf) {
      _applyOwnVessel(delta);
    } else if (delta.mmsi != null && delta.aisVessel != null) {
      _applyAisVessel(delta.mmsi!, delta.aisVessel!);
    }
  }

  void _applyOwnVessel(ParsedDelta delta) {
    var vessel = state.ownVessel;

    if (delta.navigation != null) {
      vessel = vessel.copyWith(
        navigation: _mergeNav(vessel.navigation, delta.navigation!),
      );
    }
    if (delta.environment != null) {
      vessel = vessel.copyWith(
        environment: _mergeEnv(vessel.environment, delta.environment!),
      );
    }
    if (delta.propulsion != null) {
      vessel = vessel.copyWith(
        propulsion: _mergePropulsion(vessel.propulsion, delta.propulsion!),
      );
    }
    if (delta.tanks != null) {
      vessel = vessel.copyWith(
        tanks: _mergeTanks(vessel.tanks, delta.tanks!),
      );
    }
    if (delta.electrical != null) {
      vessel = vessel.copyWith(
        electrical: _mergeElectrical(vessel.electrical, delta.electrical!),
      );
    }

    // Emit a single state update for this delta — immediate, no batching.
    state = state.copyWith(
      ownVessel: vessel,
      lastUpdateAt: DateTime.now(),
      lastUpdatedPaths: delta.paths,
      notifications: delta.notifications?.notifications,
    );

    // Auto-clear lastUpdatedPaths after 2 seconds so UI can fade "live" indicators.
    _livePathsTimer?.cancel();
    _livePathsTimer = Timer(const Duration(seconds: 2), () {
      if (state.lastUpdatedPaths.isNotEmpty) {
        state = state.copyWith(lastUpdatedPaths: const {});
      }
    });
  }

  void _applyAisVessel(int mmsi, AisVesselData incoming) {
    final existing = state.otherVessels[mmsi];
    final merged = existing != null
        ? existing.copyWith(
            name: incoming.name ?? existing.name,
            callsign: incoming.callsign ?? existing.callsign,
            position: incoming.position ?? existing.position,
            sog: incoming.sog ?? existing.sog,
            cog: incoming.cog ?? existing.cog,
            heading: incoming.heading ?? existing.heading,
            navStatus: incoming.navStatus ?? existing.navStatus,
            shipType: incoming.shipType ?? existing.shipType,
            dimBow: incoming.dimBow ?? existing.dimBow,
            dimStern: incoming.dimStern ?? existing.dimStern,
            dimPort: incoming.dimPort ?? existing.dimPort,
            dimStarboard: incoming.dimStarboard ?? existing.dimStarboard,
            lastSeen: DateTime.now(),
          )
        : incoming;

    state = state.copyWith(
      otherVessels: {...state.otherVessels, mmsi: merged},
    );
  }

  void _removeStaleTargets() {
    final now = DateTime.now();
    final fresh = Map<int, AisVesselData>.from(state.otherVessels);
    fresh.removeWhere(
      (_, t) => now.difference(t.lastSeen).inMinutes >= 10,
    );
    if (fresh.length != state.otherVessels.length) {
      state = state.copyWith(otherVessels: fresh);
    }
  }

  // ── Merge helpers ──
  // Merge incoming partial data into existing state, keeping non-null values.

  NavigationData _mergeNav(NavigationData existing, NavigationData incoming) {
    return existing.copyWith(
      position: incoming.position,
      sog: incoming.sog,
      cog: incoming.cog,
      headingTrue: incoming.headingTrue,
      headingMagnetic: incoming.headingMagnetic,
      rateOfTurn: incoming.rateOfTurn,
      leewayAngle: incoming.leewayAngle,
    );
  }

  EnvironmentData _mergeEnv(
      EnvironmentData existing, EnvironmentData incoming) {
    return existing.copyWith(
      depthBelowKeel: incoming.depthBelowKeel,
      depthBelowTransducer: incoming.depthBelowTransducer,
      depthBelowSurface: incoming.depthBelowSurface,
      windSpeedApparent: incoming.windSpeedApparent,
      windAngleApparent: incoming.windAngleApparent,
      windSpeedTrue: incoming.windSpeedTrue,
      windAngleTrueWater: incoming.windAngleTrueWater,
      windAngleTrueGround: incoming.windAngleTrueGround,
      waterTemp: incoming.waterTemp,
      airTemp: incoming.airTemp,
      pressure: incoming.pressure,
      humidity: incoming.humidity,
    );
  }

  PropulsionData _mergePropulsion(
      PropulsionData existing, PropulsionData incoming) {
    final engines = Map<String, EngineData>.from(existing.engines);
    for (final entry in incoming.engines.entries) {
      final prev = engines[entry.key];
      engines[entry.key] = prev != null
          ? prev.copyWith(
              rpm: entry.value.rpm,
              temperature: entry.value.temperature,
              oilPressure: entry.value.oilPressure,
              coolantTemp: entry.value.coolantTemp,
              exhaustTemp: entry.value.exhaustTemp,
              fuelRate: entry.value.fuelRate,
            )
          : entry.value;
    }
    return PropulsionData(engines: engines);
  }

  TanksData _mergeTanks(TanksData existing, TanksData incoming) {
    final tanks = Map<String, TankData>.from(existing.tanks);
    for (final entry in incoming.tanks.entries) {
      final prev = tanks[entry.key];
      tanks[entry.key] = prev != null
          ? prev.copyWith(
              currentLevel: entry.value.currentLevel,
              capacity: entry.value.capacity,
            )
          : entry.value;
    }
    return TanksData(tanks: tanks);
  }

  ElectricalData _mergeElectrical(
      ElectricalData existing, ElectricalData incoming) {
    final batteries = Map<String, BatteryData>.from(existing.batteries);
    for (final entry in incoming.batteries.entries) {
      final prev = batteries[entry.key];
      batteries[entry.key] = prev != null
          ? prev.copyWith(
              voltage: entry.value.voltage,
              current: entry.value.current,
              stateOfCharge: entry.value.stateOfCharge,
              temperature: entry.value.temperature,
            )
          : entry.value;
    }

    final inverters = Map<String, InverterData>.from(existing.inverters);
    for (final entry in incoming.inverters.entries) {
      final prev = inverters[entry.key];
      inverters[entry.key] = prev != null
          ? prev.copyWith(
              dcVoltage: entry.value.dcVoltage,
              dcCurrent: entry.value.dcCurrent,
              acVoltage: entry.value.acVoltage,
              acCurrent: entry.value.acCurrent,
            )
          : entry.value;
    }

    final chargers = Map<String, ChargerData>.from(existing.chargers);
    for (final entry in incoming.chargers.entries) {
      final prev = chargers[entry.key];
      chargers[entry.key] = prev != null
          ? prev.copyWith(
              voltage: entry.value.voltage,
              current: entry.value.current,
            )
          : entry.value;
    }

    return ElectricalData(
      batteries: batteries,
      inverters: inverters,
      chargers: chargers,
    );
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _livePathsTimer?.cancel();
    _staleDataTimer?.cancel();
    disconnect();
    super.dispose();
  }
}

/// Global Signal K state provider.
final signalKProvider =
    StateNotifierProvider<SignalKNotifier, SignalKState>((ref) {
  final notifier = SignalKNotifier();
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

/// Derived: own vessel Signal K data.
final signalKOwnVesselProvider = Provider<SignalKVesselData>((ref) {
  return ref.watch(signalKProvider).ownVessel;
});

/// Derived: other vessels (AIS) from Signal K.
final signalKOtherVesselsProvider = Provider<Map<int, AisVesselData>>((ref) {
  return ref.watch(signalKProvider).otherVessels;
});

/// Derived: Signal K connection state.
final signalKConnectionStateProvider = Provider<SignalKConnectionState>((ref) {
  return ref.watch(signalKProvider).connectionState;
});

/// Derived: environment data from Signal K.
final signalKEnvironmentProvider = Provider<EnvironmentData>((ref) {
  return ref.watch(signalKProvider).ownVessel.environment;
});

/// Derived: electrical data from Signal K.
final signalKElectricalProvider = Provider<ElectricalData>((ref) {
  return ref.watch(signalKProvider).ownVessel.electrical;
});

/// Derived: propulsion data from Signal K.
final signalKPropulsionProvider = Provider<PropulsionData>((ref) {
  return ref.watch(signalKProvider).ownVessel.propulsion;
});

/// Derived: tanks data from Signal K.
final signalKTanksProvider = Provider<TanksData>((ref) {
  return ref.watch(signalKProvider).ownVessel.tanks;
});

/// Derived: paths updated in the most recent delta (live for ~2s).
final signalKLivePathsProvider = Provider<Set<String>>((ref) {
  return ref.watch(signalKProvider).lastUpdatedPaths;
});
