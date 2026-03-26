import '../sentence_parser.dart';

/// RMC — Recommended Minimum Navigation Information.
/// Position, SOG, COG, date/time.
class RmcData {
  final DateTime? utc;
  final bool isValid;
  final double? latitude;
  final double? longitude;
  final double? sogKnots;
  final double? cogTrue;

  const RmcData({
    this.utc,
    this.isValid = false,
    this.latitude,
    this.longitude,
    this.sogKnots,
    this.cogTrue,
  });

  static RmcData? fromSentence(NmeaSentence s) {
    if (s.type != 'RMC' || s.fields.length < 11) return null;
    final f = s.fields;

    final valid = f[1] == 'A';
    final lat = parseLatLon(f[2], f[3]);
    final lon = parseLatLon(f[4], f[5]);
    final sog = double.tryParse(f[6]);
    final cog = double.tryParse(f[7]);
    final utc = _parseDateTime(f[0], f[8]);

    return RmcData(
      utc: utc,
      isValid: valid,
      latitude: lat,
      longitude: lon,
      sogKnots: sog,
      cogTrue: cog,
    );
  }
}

/// Parse NMEA lat/lon (DDDMM.MMMMM, N/S/E/W) to decimal degrees.
double? parseLatLon(String value, String dir) {
  if (value.isEmpty || dir.isEmpty) return null;
  final d = double.tryParse(value);
  if (d == null) return null;
  final degrees = (d / 100).truncateToDouble();
  final minutes = d - degrees * 100;
  var result = degrees + minutes / 60;
  if (dir == 'S' || dir == 'W') result = -result;
  return result;
}

DateTime? _parseDateTime(String time, String date) {
  if (time.length < 6 || date.length < 6) return null;
  final h = int.tryParse(time.substring(0, 2));
  final m = int.tryParse(time.substring(2, 4));
  final sec = double.tryParse(time.substring(4));
  final day = int.tryParse(date.substring(0, 2));
  final mon = int.tryParse(date.substring(2, 4));
  final yr = int.tryParse(date.substring(4, 6));
  if (h == null || m == null || sec == null || day == null || mon == null || yr == null) {
    return null;
  }
  return DateTime.utc(2000 + yr, mon, day, h, m, sec.truncate(), ((sec % 1) * 1000).truncate());
}
