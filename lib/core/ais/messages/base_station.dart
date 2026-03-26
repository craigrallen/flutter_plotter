import '../decoder.dart';

/// AIS Message Type 4 — Base Station Report.
class AisBaseStation {
  final int mmsi;
  final double longitude;
  final double latitude;

  const AisBaseStation({
    required this.mmsi,
    required this.longitude,
    required this.latitude,
  });

  static AisBaseStation? decode(AisDecoder d) {
    if (d.messageType != 4) return null;
    if (d.bitLength < 168) return null;

    final mmsi = d.getUnsigned(8, 30);
    final lonRaw = d.getSigned(79, 28);
    final lon = lonRaw / 600000.0;
    final latRaw = d.getSigned(107, 27);
    final lat = latRaw / 600000.0;

    if (lat.abs() > 90 || lon.abs() > 180) return null;

    return AisBaseStation(mmsi: mmsi, longitude: lon, latitude: lat);
  }
}
