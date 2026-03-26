import '../sentence_parser.dart';

/// VTG — Track Made Good and Ground Speed.
class VtgData {
  final double? cogTrue;
  final double? sogKnots;

  const VtgData({this.cogTrue, this.sogKnots});

  static VtgData? fromSentence(NmeaSentence s) {
    if (s.type != 'VTG' || s.fields.length < 7) return null;
    final f = s.fields;
    return VtgData(
      cogTrue: double.tryParse(f[0]),
      sogKnots: double.tryParse(f[4]),
    );
  }
}
