import 'dart:convert';

class VesselProfile {
  final String name;
  final double draft;
  final double airDraft;
  final double beam;
  final double length;

  const VesselProfile({
    this.name = 'My Vessel',
    this.draft = 1.5,
    this.airDraft = 10.0,
    this.beam = 3.0,
    this.length = 10.0,
  });

  VesselProfile copyWith({
    String? name,
    double? draft,
    double? airDraft,
    double? beam,
    double? length,
  }) {
    return VesselProfile(
      name: name ?? this.name,
      draft: draft ?? this.draft,
      airDraft: airDraft ?? this.airDraft,
      beam: beam ?? this.beam,
      length: length ?? this.length,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'draft': draft,
      'airDraft': airDraft,
      'beam': beam,
      'length': length,
    };
  }

  factory VesselProfile.fromJson(Map<String, dynamic> json) {
    return VesselProfile(
      name: json['name'] as String? ?? 'My Vessel',
      draft: (json['draft'] as num?)?.toDouble() ?? 1.5,
      airDraft: (json['airDraft'] as num?)?.toDouble() ?? 10.0,
      beam: (json['beam'] as num?)?.toDouble() ?? 3.0,
      length: (json['length'] as num?)?.toDouble() ?? 10.0,
    );
  }

  String encode() => jsonEncode(toJson());

  factory VesselProfile.decode(String source) =>
      VesselProfile.fromJson(jsonDecode(source) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VesselProfile &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          draft == other.draft &&
          airDraft == other.airDraft &&
          beam == other.beam &&
          length == other.length;

  @override
  int get hashCode => Object.hash(name, draft, airDraft, beam, length);
}
