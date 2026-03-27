class TidePrediction {
  final TideType type;
  final DateTime time;
  final double heightM; // metres above MLLW

  const TidePrediction({
    required this.type,
    required this.time,
    required this.heightM,
  });

  factory TidePrediction.fromJson(Map<String, dynamic> json) {
    return TidePrediction(
      type: (json['type'] as String) == 'H' ? TideType.high : TideType.low,
      time: DateTime.parse(json['t'] as String),
      heightM: double.parse(json['v'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type == TideType.high ? 'H' : 'L',
        't': time.toIso8601String(),
        'v': heightM.toString(),
      };
}

enum TideType { high, low }
