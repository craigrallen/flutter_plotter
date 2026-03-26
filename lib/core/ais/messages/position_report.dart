import '../decoder.dart';

/// AIS Message Types 1, 2, 3 — Class A Position Report.
class AisPositionReport {
  final int messageType;
  final int mmsi;
  final int navStatus;
  final double? rateOfTurn;
  final double sogKnots;
  final double longitude;
  final double latitude;
  final double cogDegrees;
  final double? headingTrue;
  final int timestamp;

  const AisPositionReport({
    required this.messageType,
    required this.mmsi,
    required this.navStatus,
    this.rateOfTurn,
    required this.sogKnots,
    required this.longitude,
    required this.latitude,
    required this.cogDegrees,
    this.headingTrue,
    required this.timestamp,
  });

  static AisPositionReport? decode(AisDecoder d) {
    final type = d.messageType;
    if (type < 1 || type > 3) return null;
    if (d.bitLength < 149) return null;

    final mmsi = d.getUnsigned(8, 30);
    final navStatus = d.getUnsigned(38, 4);

    final rotRaw = d.getSigned(42, 8);
    double? rot;
    if (rotRaw != -128) {
      rot = rotRaw.toDouble();
    }

    final sogRaw = d.getUnsigned(50, 10);
    final sog = sogRaw / 10.0; // 1/10 knot

    final lonRaw = d.getSigned(61, 28);
    final lon = lonRaw / 600000.0; // 1/10000 min

    final latRaw = d.getSigned(89, 27);
    final lat = latRaw / 600000.0;

    final cogRaw = d.getUnsigned(116, 12);
    final cog = cogRaw / 10.0;

    final hdgRaw = d.getUnsigned(128, 9);
    double? hdg;
    if (hdgRaw != 511) hdg = hdgRaw.toDouble();

    final ts = d.getUnsigned(137, 6);

    // Validate position — 91° lat or 181° lon means not available
    if (lat.abs() > 90 || lon.abs() > 180) return null;

    return AisPositionReport(
      messageType: type,
      mmsi: mmsi,
      navStatus: navStatus,
      rateOfTurn: rot,
      sogKnots: sog,
      longitude: lon,
      latitude: lat,
      cogDegrees: cog >= 360 ? 0 : cog,
      headingTrue: hdg,
      timestamp: ts,
    );
  }

  static const navStatusNames = [
    'Under way using engine',
    'At anchor',
    'Not under command',
    'Restricted manoeuvrability',
    'Constrained by draught',
    'Moored',
    'Aground',
    'Engaged in fishing',
    'Under way sailing',
    'Reserved (HSC)',
    'Reserved (WIG)',
    'Reserved',
    'Reserved',
    'Reserved',
    'AIS-SART',
    'Not defined',
  ];

  String get navStatusName =>
      navStatus < navStatusNames.length ? navStatusNames[navStatus] : 'Unknown';
}
