import '../decoder.dart';

/// AIS Message Type 5 — Static and Voyage Related Data.
class AisStaticVoyage {
  final int mmsi;
  final String vesselName;
  final String callSign;
  final int shipType;
  final int dimBow;
  final int dimStern;
  final int dimPort;
  final int dimStarboard;
  final double draught;
  final String destination;

  const AisStaticVoyage({
    required this.mmsi,
    required this.vesselName,
    required this.callSign,
    required this.shipType,
    required this.dimBow,
    required this.dimStern,
    required this.dimPort,
    required this.dimStarboard,
    required this.draught,
    required this.destination,
  });

  int get lengthMetres => dimBow + dimStern;
  int get beamMetres => dimPort + dimStarboard;

  static AisStaticVoyage? decode(AisDecoder d) {
    if (d.messageType != 5) return null;
    if (d.bitLength < 420) return null;

    final mmsi = d.getUnsigned(8, 30);
    final callSign = d.getString(70, 7);
    final vesselName = d.getString(112, 20);
    final shipType = d.getUnsigned(232, 8);
    final dimBow = d.getUnsigned(240, 9);
    final dimStern = d.getUnsigned(249, 9);
    final dimPort = d.getUnsigned(258, 6);
    final dimStarboard = d.getUnsigned(264, 6);
    final draughtRaw = d.getUnsigned(294, 8);
    final draught = draughtRaw / 10.0;
    final destination = d.getString(302, 20);

    return AisStaticVoyage(
      mmsi: mmsi,
      vesselName: vesselName,
      callSign: callSign,
      shipType: shipType,
      dimBow: dimBow,
      dimStern: dimStern,
      dimPort: dimPort,
      dimStarboard: dimStarboard,
      draught: draught,
      destination: destination,
    );
  }

  static String shipTypeName(int type) {
    if (type >= 20 && type <= 29) return 'Wing in ground';
    if (type == 30) return 'Fishing';
    if (type == 31 || type == 32) return 'Towing';
    if (type == 33) return 'Dredging';
    if (type == 34) return 'Diving';
    if (type == 35) return 'Military';
    if (type == 36) return 'Sailing';
    if (type == 37) return 'Pleasure craft';
    if (type >= 40 && type <= 49) return 'High speed craft';
    if (type == 50) return 'Pilot vessel';
    if (type == 51) return 'Search & rescue';
    if (type == 52) return 'Tug';
    if (type == 53) return 'Port tender';
    if (type == 55) return 'Law enforcement';
    if (type >= 60 && type <= 69) return 'Passenger';
    if (type >= 70 && type <= 79) return 'Cargo';
    if (type >= 80 && type <= 89) return 'Tanker';
    return 'Other';
  }
}
