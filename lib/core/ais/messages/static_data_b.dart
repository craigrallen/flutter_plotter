import '../decoder.dart';

/// AIS Message Type 24 — Class B CS Static Data Report.
/// Part A contains vessel name, Part B contains callsign + ship type + dimensions.
class AisStaticDataB {
  final int mmsi;
  final int partNumber; // 0 = A, 1 = B
  final String? vesselName; // Part A only
  final String? callSign; // Part B only
  final int? shipType; // Part B only
  final int? dimBow;
  final int? dimStern;
  final int? dimPort;
  final int? dimStarboard;

  const AisStaticDataB({
    required this.mmsi,
    required this.partNumber,
    this.vesselName,
    this.callSign,
    this.shipType,
    this.dimBow,
    this.dimStern,
    this.dimPort,
    this.dimStarboard,
  });

  bool get isPartA => partNumber == 0;
  bool get isPartB => partNumber == 1;

  static AisStaticDataB? decode(AisDecoder d) {
    if (d.messageType != 24) return null;
    if (d.bitLength < 160) return null;

    final mmsi = d.getUnsigned(8, 30);
    final partNum = d.getUnsigned(38, 2);

    if (partNum == 0) {
      // Part A — vessel name
      final name = d.getString(40, 20);
      return AisStaticDataB(
        mmsi: mmsi,
        partNumber: 0,
        vesselName: name,
      );
    } else if (partNum == 1 && d.bitLength >= 168) {
      // Part B — callsign, ship type, dimensions
      final callSign = d.getString(40, 7);
      final shipType = d.getUnsigned(82, 8);
      final dimBow = d.getUnsigned(132, 9);
      final dimStern = d.getUnsigned(141, 9);
      final dimPort = d.getUnsigned(150, 6);
      final dimStarboard = d.getUnsigned(156, 6);

      return AisStaticDataB(
        mmsi: mmsi,
        partNumber: 1,
        callSign: callSign,
        shipType: shipType,
        dimBow: dimBow,
        dimStern: dimStern,
        dimPort: dimPort,
        dimStarboard: dimStarboard,
      );
    }
    return null;
  }
}
