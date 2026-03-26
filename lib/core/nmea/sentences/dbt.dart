import '../sentence_parser.dart';

/// DBT — Depth Below Transducer.
class DbtData {
  final double? depthMetres;

  const DbtData({this.depthMetres});

  static DbtData? fromSentence(NmeaSentence s) {
    if (s.type != 'DBT' || s.fields.length < 5) return null;
    // Field 2 is depth in metres
    return DbtData(depthMetres: double.tryParse(s.fields[2]));
  }
}
