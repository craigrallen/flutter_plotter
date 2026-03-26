import '../decoder.dart';

/// AIS Message Type 18 — Standard Class B CS Position Report.
class AisClassBReport {
  final int mmsi;
  final double sogKnots;
  final double longitude;
  final double latitude;
  final double cogDegrees;
  final double? headingTrue;

  const AisClassBReport({
    required this.mmsi,
    required this.sogKnots,
    required this.longitude,
    required this.latitude,
    required this.cogDegrees,
    this.headingTrue,
  });

  static AisClassBReport? decode(AisDecoder d) {
    if (d.messageType != 18) return null;
    if (d.bitLength < 149) return null;

    final mmsi = d.getUnsigned(8, 30);
    final sogRaw = d.getUnsigned(46, 10);
    final sog = sogRaw / 10.0;

    final lonRaw = d.getSigned(57, 28);
    final lon = lonRaw / 600000.0;

    final latRaw = d.getSigned(85, 27);
    final lat = latRaw / 600000.0;

    final cogRaw = d.getUnsigned(112, 12);
    final cog = cogRaw / 10.0;

    final hdgRaw = d.getUnsigned(124, 9);
    double? hdg;
    if (hdgRaw != 511) hdg = hdgRaw.toDouble();

    if (lat.abs() > 90 || lon.abs() > 180) return null;

    return AisClassBReport(
      mmsi: mmsi,
      sogKnots: sog,
      longitude: lon,
      latitude: lat,
      cogDegrees: cog >= 360 ? 0 : cog,
      headingTrue: hdg,
    );
  }
}
