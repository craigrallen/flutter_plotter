import '../decoder.dart';

/// AIS Message Type 21 — Aid to Navigation Report.
class AisAidToNav {
  final int mmsi;
  final int atonType;
  final String name;
  final double longitude;
  final double latitude;
  final int dimBow;
  final int dimStern;
  final int dimPort;
  final int dimStarboard;
  final bool virtual;

  const AisAidToNav({
    required this.mmsi,
    required this.atonType,
    required this.name,
    required this.longitude,
    required this.latitude,
    required this.dimBow,
    required this.dimStern,
    required this.dimPort,
    required this.dimStarboard,
    required this.virtual,
  });

  static AisAidToNav? decode(AisDecoder d) {
    if (d.messageType != 21) return null;
    if (d.bitLength < 272) return null;

    final mmsi = d.getUnsigned(8, 30);
    final atonType = d.getUnsigned(38, 5);
    final name = d.getString(43, 20);

    final lonRaw = d.getSigned(164, 28);
    final lon = lonRaw / 600000.0;
    final latRaw = d.getSigned(192, 27);
    final lat = latRaw / 600000.0;

    final dimBow = d.getUnsigned(219, 9);
    final dimStern = d.getUnsigned(228, 9);
    final dimPort = d.getUnsigned(237, 6);
    final dimStarboard = d.getUnsigned(243, 6);
    final virtual = d.getUnsigned(269, 1) == 1;

    if (lat.abs() > 90 || lon.abs() > 180) return null;

    return AisAidToNav(
      mmsi: mmsi,
      atonType: atonType,
      name: name,
      longitude: lon,
      latitude: lat,
      dimBow: dimBow,
      dimStern: dimStern,
      dimPort: dimPort,
      dimStarboard: dimStarboard,
      virtual: virtual,
    );
  }

  static const atonTypeNames = [
    'Default',
    'Reference point',
    'RACON',
    'Fixed structure',
    'Spare',
    'Light, without sectors',
    'Light, with sectors',
    'Leading light front',
    'Leading light rear',
    'Beacon, cardinal N',
    'Beacon, cardinal E',
    'Beacon, cardinal S',
    'Beacon, cardinal W',
    'Beacon, port hand',
    'Beacon, starboard hand',
    'Beacon, preferred channel port',
    'Beacon, preferred channel starboard',
    'Beacon, isolated danger',
    'Beacon, safe water',
    'Beacon, special mark',
    'Beacon, light vessel / LANBY',
    'Buoy, cardinal N',
    'Buoy, cardinal E',
    'Buoy, cardinal S',
    'Buoy, cardinal W',
    'Buoy, port hand',
    'Buoy, starboard hand',
    'Buoy, preferred channel port',
    'Buoy, preferred channel starboard',
    'Buoy, isolated danger',
    'Buoy, safe water',
    'Buoy, special mark',
  ];

  String get atonTypeName =>
      atonType < atonTypeNames.length ? atonTypeNames[atonType] : 'Unknown';
}
