import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../../core/nav/geo.dart';

/// Represents a tracked AIS target.
class AisTarget {
  final int mmsi;
  final LatLng position;
  final double sogKnots;
  final double cogDegrees;
  final double? headingTrue;
  final String? vesselName;
  final String? callSign;
  final int? shipType;
  final int? navStatus;
  final int? dimBow;
  final int? dimStern;
  final int? dimPort;
  final int? dimStarboard;
  final DateTime lastSeen;
  final bool isAtoN;

  const AisTarget({
    required this.mmsi,
    required this.position,
    required this.sogKnots,
    required this.cogDegrees,
    this.headingTrue,
    this.vesselName,
    this.callSign,
    this.shipType,
    this.navStatus,
    this.dimBow,
    this.dimStern,
    this.dimPort,
    this.dimStarboard,
    required this.lastSeen,
    this.isAtoN = false,
  });

  bool get isStale =>
      DateTime.now().difference(lastSeen).inMinutes >= 10;

  int get lengthMetres => (dimBow ?? 0) + (dimStern ?? 0);
  int get beamMetres => (dimPort ?? 0) + (dimStarboard ?? 0);

  String get displayName {
    if (vesselName != null && vesselName!.isNotEmpty) return vesselName!;
    return mmsi.toString();
  }

  AisTarget copyWith({
    LatLng? position,
    double? sogKnots,
    double? cogDegrees,
    double? headingTrue,
    String? vesselName,
    String? callSign,
    int? shipType,
    int? navStatus,
    int? dimBow,
    int? dimStern,
    int? dimPort,
    int? dimStarboard,
    DateTime? lastSeen,
    bool? isAtoN,
  }) {
    return AisTarget(
      mmsi: mmsi,
      position: position ?? this.position,
      sogKnots: sogKnots ?? this.sogKnots,
      cogDegrees: cogDegrees ?? this.cogDegrees,
      headingTrue: headingTrue ?? this.headingTrue,
      vesselName: vesselName ?? this.vesselName,
      callSign: callSign ?? this.callSign,
      shipType: shipType ?? this.shipType,
      navStatus: navStatus ?? this.navStatus,
      dimBow: dimBow ?? this.dimBow,
      dimStern: dimStern ?? this.dimStern,
      dimPort: dimPort ?? this.dimPort,
      dimStarboard: dimStarboard ?? this.dimStarboard,
      lastSeen: lastSeen ?? this.lastSeen,
      isAtoN: isAtoN ?? this.isAtoN,
    );
  }

  /// Compute CPA (Closest Point of Approach) in nautical miles
  /// and TCPA (Time to CPA) in minutes, relative to own vessel.
  CpaResult computeCpa(LatLng ownPos, double ownSogKnots, double ownCogDeg) {
    // Convert positions to planar coordinates (nm from own vessel)
    final distNm = haversineDistanceNm(ownPos, position);
    final bearing = initialBearing(ownPos, position) * pi / 180;

    // Target relative position in nm (x=east, y=north)
    final dx = distNm * sin(bearing);
    final dy = distNm * cos(bearing);

    // Convert SOG/COG to velocity components (nm/min)
    final ownVx = ownSogKnots / 60 * sin(ownCogDeg * pi / 180);
    final ownVy = ownSogKnots / 60 * cos(ownCogDeg * pi / 180);
    final tgtVx = sogKnots / 60 * sin(cogDegrees * pi / 180);
    final tgtVy = sogKnots / 60 * cos(cogDegrees * pi / 180);

    // Relative velocity and position
    final rvx = tgtVx - ownVx;
    final rvy = tgtVy - ownVy;

    final relSpeedSq = rvx * rvx + rvy * rvy;
    if (relSpeedSq < 1e-10) {
      // No relative motion — CPA is current distance, TCPA undefined
      return CpaResult(cpaNm: distNm, tcpaMinutes: double.infinity);
    }

    // TCPA = -(r·v) / |v|²
    final dot = dx * rvx + dy * rvy;
    final tcpaMin = -dot / relSpeedSq;

    if (tcpaMin < 0) {
      // CPA is in the past — targets diverging
      return CpaResult(cpaNm: distNm, tcpaMinutes: -1);
    }

    // CPA distance
    final cpx = dx + rvx * tcpaMin;
    final cpy = dy + rvy * tcpaMin;
    final cpaNm = sqrt(cpx * cpx + cpy * cpy);

    return CpaResult(cpaNm: cpaNm, tcpaMinutes: tcpaMin);
  }
}

class CpaResult {
  final double cpaNm;
  final double tcpaMinutes; // negative means diverging, infinity means no relative motion

  const CpaResult({required this.cpaNm, required this.tcpaMinutes});

  /// Threat level based on CPA and TCPA.
  ThreatLevel get threatLevel {
    if (tcpaMinutes < 0 || tcpaMinutes == double.infinity) return ThreatLevel.safe;
    if (cpaNm < 0.5 && tcpaMinutes < 10) return ThreatLevel.danger;
    if (cpaNm < 2.0 && tcpaMinutes < 30) return ThreatLevel.caution;
    return ThreatLevel.safe;
  }
}

enum ThreatLevel { safe, caution, danger }
