import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/floatilla/voyage_logger_service.dart';
import 'signalk_provider.dart';

// ── Notifier ──────────────────────────────────────────────────────────────────

class VoyageLoggerNotifier extends StateNotifier<VoyageLoggerState> {
  final Ref _ref;

  VoyageLoggerNotifier(this._ref) : super(const VoyageLoggerState()) {
    _init();
  }

  Future<void> _init() async {
    await VoyageLoggerService.instance.init(
      snapshotCallback: _buildSnapshot,
    );

    // Subscribe to voyage events
    VoyageLoggerService.instance.events.listen(_handleEvent);

    // Load past voyages from DB
    await _loadPastVoyages();

    // Start the logger automatically
    VoyageLoggerService.instance.start(settings: state.settings);
    state = state.copyWith(isRunning: true);
  }

  Future<VesselSnapshot> _buildSnapshot() async {
    final vessel = _ref.read(signalKOwnVesselProvider);
    final nav = vessel.navigation;
    final env = vessel.environment;
    final propulsion = vessel.propulsion;
    final electrical = vessel.electrical;

    double? engineRpm;
    if (propulsion.engines.isNotEmpty) {
      engineRpm = propulsion.engines.values.first.rpm;
    }

    double? batteryVoltage;
    if (electrical.batteries.isNotEmpty) {
      batteryVoltage = electrical.batteries.values.first.voltage;
    }

    return VesselSnapshot(
      timestamp: DateTime.now(),
      lat: nav.position?.latitude,
      lng: nav.position?.longitude,
      cog: nav.cog,
      sog: nav.sog,
      tws: env.windSpeedTrue,
      twd: env.windAngleTrueGround ?? env.windAngleTrueWater,
      awa: env.windAngleApparent,
      aws: env.windSpeedApparent,
      depth: env.depth,
      heading: nav.headingTrue,
      engineRpm: engineRpm,
      batteryVoltage: batteryVoltage,
    );
  }

  void _handleEvent(VoyageEvent event) {
    if (event is VoyageStartedEvent) {
      state = state.copyWith(
        isVoyageActive: true,
        currentVoyageId: event.voyageId,
      );
    } else if (event is VoyageEntryEvent) {
      final sog = event.entry.sog;
      state = state.copyWith(currentSog: sog);
    } else if (event is VoyageEndedEvent) {
      state = state.copyWith(
        isVoyageActive: false,
        clearCurrentVoyage: true,
      );
      _loadPastVoyages();
    }
  }

  Future<void> _loadPastVoyages() async {
    final voyages = await VoyageLoggerService.instance.loadPastVoyages();
    state = state.copyWith(pastVoyages: voyages);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> forceStartVoyage() async {
    await VoyageLoggerService.instance.forceStartVoyage();
  }

  Future<void> forceEndVoyage() async {
    await VoyageLoggerService.instance.forceEndVoyage();
  }

  void updateSettings(VoyageLoggerSettings settings) {
    VoyageLoggerService.instance.updateSettings(settings);
    state = state.copyWith(settings: settings);
  }

  Future<List<VoyageLogEntry>> entriesForVoyage(String voyageId) async {
    return VoyageLoggerService.instance.loadEntriesForVoyage(voyageId);
  }

  VoyageStats statsForVoyage(
      VoyageRecord voyage, List<VoyageLogEntry> entries) {
    return VoyageLoggerService.instance.statsFromEntries(voyage, entries);
  }

  Future<void> deleteVoyage(String voyageId) async {
    await VoyageLoggerService.instance.deleteVoyage(voyageId);
    await _loadPastVoyages();
  }

  Future<void> refresh() async {
    await _loadPastVoyages();
  }

  @override
  void dispose() {
    VoyageLoggerService.instance.stop();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final voyageLoggerProvider =
    StateNotifierProvider<VoyageLoggerNotifier, VoyageLoggerState>(
  (ref) => VoyageLoggerNotifier(ref),
);

/// Convenience: whether a voyage is currently active.
final isVoyageActiveProvider = Provider<bool>((ref) {
  return ref.watch(voyageLoggerProvider).isVoyageActive;
});

/// Convenience: current voyage ID.
final currentVoyageIdProvider = Provider<String?>((ref) {
  return ref.watch(voyageLoggerProvider).currentVoyageId;
});

/// Convenience: past voyages list.
final pastVoyagesProvider = Provider<List<VoyageRecord>>((ref) {
  return ref.watch(voyageLoggerProvider).pastVoyages;
});

/// Convenience: current voyage stats.
final currentVoyageStatsProvider = Provider<VoyageStats?>((ref) {
  return ref.watch(voyageLoggerProvider).currentVoyageStats;
});
