import '../sentence_parser.dart';
import 'rmc.dart' show parseLatLon;

/// GLL — Geographic Position – Latitude/Longitude.
class GllData {
  final double? latitude;
  final double? longitude;
  final bool isValid;

  const GllData({this.latitude, this.longitude, this.isValid = false});

  static GllData? fromSentence(NmeaSentence s) {
    if (s.type != 'GLL' || s.fields.length < 5) return null;
    final f = s.fields;
    return GllData(
      latitude: parseLatLon(f[0], f[1]),
      longitude: parseLatLon(f[2], f[3]),
      isValid: f.length > 5 ? f[5] == 'A' : f[4].isNotEmpty,
    );
  }
}
