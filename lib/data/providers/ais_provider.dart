import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/ais/decoder.dart';
import '../../core/ais/messages/position_report.dart';
import '../../core/ais/messages/class_b_report.dart';
import '../../core/ais/messages/static_voyage.dart';
import '../../core/ais/messages/base_station.dart';
import '../../core/ais/messages/aid_to_nav.dart';
import '../../core/ais/messages/static_data_b.dart';
import '../../core/nmea/sentence_parser.dart';
import '../../core/nmea/sentences/vdm.dart';
import '../models/ais_target.dart';

/// Maintains a map of AIS targets, keyed by MMSI.
/// Processes decoded AIS messages and expires stale targets.
class AisNotifier extends StateNotifier<Map<int, AisTarget>> {
  Timer? _cleanupTimer;
  final VdmAssembler _assembler = VdmAssembler();

  AisNotifier() : super({}) {
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _removeStale(),
    );
  }

  void _removeStale() {
    final now = DateTime.now();
    final fresh = Map<int, AisTarget>.from(state);
    fresh.removeWhere(
      (_, t) => now.difference(t.lastSeen).inMinutes >= 10,
    );
    if (fresh.length != state.length) state = fresh;
  }

  /// Process a raw NMEA sentence. If it's a VDM, decode the AIS payload.
  void processSentence(NmeaSentence sentence) {
    final vdm = VdmData.fromSentence(sentence);
    if (vdm == null) return;

    final payload = _assembler.addFragment(vdm);
    if (payload == null) return;

    final decoder = AisDecoder.fromPayload(payload, vdm.fillBits);
    final type = decoder.messageType;

    switch (type) {
      case 1:
      case 2:
      case 3:
        _handlePositionReport(AisPositionReport.decode(decoder));
      case 4:
        _handleBaseStation(AisBaseStation.decode(decoder));
      case 5:
        _handleStaticVoyage(AisStaticVoyage.decode(decoder));
      case 18:
        _handleClassB(AisClassBReport.decode(decoder));
      case 21:
        _handleAtoN(AisAidToNav.decode(decoder));
      case 24:
        _handleStaticDataB(AisStaticDataB.decode(decoder));
    }
  }

  void _handlePositionReport(AisPositionReport? msg) {
    if (msg == null) return;
    final existing = state[msg.mmsi];
    final target = (existing ?? AisTarget(
      mmsi: msg.mmsi,
      position: LatLng(msg.latitude, msg.longitude),
      sogKnots: msg.sogKnots,
      cogDegrees: msg.cogDegrees,
      lastSeen: DateTime.now(),
    )).copyWith(
      position: LatLng(msg.latitude, msg.longitude),
      sogKnots: msg.sogKnots,
      cogDegrees: msg.cogDegrees,
      headingTrue: msg.headingTrue,
      navStatus: msg.navStatus,
      lastSeen: DateTime.now(),
    );
    state = {...state, msg.mmsi: target};
  }

  void _handleClassB(AisClassBReport? msg) {
    if (msg == null) return;
    final existing = state[msg.mmsi];
    final target = (existing ?? AisTarget(
      mmsi: msg.mmsi,
      position: LatLng(msg.latitude, msg.longitude),
      sogKnots: msg.sogKnots,
      cogDegrees: msg.cogDegrees,
      lastSeen: DateTime.now(),
    )).copyWith(
      position: LatLng(msg.latitude, msg.longitude),
      sogKnots: msg.sogKnots,
      cogDegrees: msg.cogDegrees,
      headingTrue: msg.headingTrue,
      lastSeen: DateTime.now(),
    );
    state = {...state, msg.mmsi: target};
  }

  void _handleStaticVoyage(AisStaticVoyage? msg) {
    if (msg == null) return;
    final existing = state[msg.mmsi];
    if (existing == null) return; // Only update existing targets
    state = {
      ...state,
      msg.mmsi: existing.copyWith(
        vesselName: msg.vesselName,
        callSign: msg.callSign,
        shipType: msg.shipType,
        dimBow: msg.dimBow,
        dimStern: msg.dimStern,
        dimPort: msg.dimPort,
        dimStarboard: msg.dimStarboard,
      ),
    };
  }

  void _handleBaseStation(AisBaseStation? msg) {
    if (msg == null) return;
    // Base stations are informational — store position
    final existing = state[msg.mmsi];
    final target = (existing ?? AisTarget(
      mmsi: msg.mmsi,
      position: LatLng(msg.latitude, msg.longitude),
      sogKnots: 0,
      cogDegrees: 0,
      lastSeen: DateTime.now(),
    )).copyWith(
      position: LatLng(msg.latitude, msg.longitude),
      lastSeen: DateTime.now(),
    );
    state = {...state, msg.mmsi: target};
  }

  void _handleAtoN(AisAidToNav? msg) {
    if (msg == null) return;
    final existing = state[msg.mmsi];
    final target = (existing ?? AisTarget(
      mmsi: msg.mmsi,
      position: LatLng(msg.latitude, msg.longitude),
      sogKnots: 0,
      cogDegrees: 0,
      lastSeen: DateTime.now(),
      isAtoN: true,
    )).copyWith(
      position: LatLng(msg.latitude, msg.longitude),
      vesselName: msg.name,
      lastSeen: DateTime.now(),
      isAtoN: true,
    );
    state = {...state, msg.mmsi: target};
  }

  void _handleStaticDataB(AisStaticDataB? msg) {
    if (msg == null) return;
    final existing = state[msg.mmsi];
    if (existing == null) return;

    if (msg.isPartA && msg.vesselName != null) {
      state = {
        ...state,
        msg.mmsi: existing.copyWith(vesselName: msg.vesselName),
      };
    } else if (msg.isPartB) {
      state = {
        ...state,
        msg.mmsi: existing.copyWith(
          callSign: msg.callSign,
          shipType: msg.shipType,
          dimBow: msg.dimBow,
          dimStern: msg.dimStern,
          dimPort: msg.dimPort,
          dimStarboard: msg.dimStarboard,
        ),
      };
    }
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    super.dispose();
  }
}

final aisProvider =
    StateNotifierProvider<AisNotifier, Map<int, AisTarget>>((ref) {
  return AisNotifier();
});
