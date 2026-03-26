import '../sentence_parser.dart';

/// MWV — Wind Speed and Angle.
class MwvData {
  final double? windAngle;
  final bool isRelative; // true = relative, false = true
  final double? windSpeedKnots;
  final bool isValid;

  const MwvData({
    this.windAngle,
    this.isRelative = true,
    this.windSpeedKnots,
    this.isValid = false,
  });

  static MwvData? fromSentence(NmeaSentence s) {
    if (s.type != 'MWV' || s.fields.length < 4) return null;
    final f = s.fields;
    final angle = double.tryParse(f[0]);
    final isRel = f[1] == 'R';
    var speed = double.tryParse(f[2]);
    final unit = f[3];
    final valid = f.length > 4 && f[4] == 'A';

    // Convert to knots if needed.
    if (speed != null) {
      switch (unit) {
        case 'M':
          speed = speed * 1.94384; // m/s to knots
        case 'K':
          speed = speed * 0.539957; // km/h to knots
      }
    }

    return MwvData(
      windAngle: angle,
      isRelative: isRel,
      windSpeedKnots: speed,
      isValid: valid,
    );
  }
}
