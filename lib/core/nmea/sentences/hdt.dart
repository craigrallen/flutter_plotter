import '../sentence_parser.dart';

/// HDT — Heading True.
class HdtData {
  final double headingTrue;

  const HdtData({required this.headingTrue});

  static HdtData? fromSentence(NmeaSentence s) {
    if (s.type != 'HDT' || s.fields.isEmpty) return null;
    final h = double.tryParse(s.fields[0]);
    if (h == null) return null;
    return HdtData(headingTrue: h);
  }
}
