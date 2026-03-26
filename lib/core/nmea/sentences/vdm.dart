import '../sentence_parser.dart';

/// VDM/VDO — AIS encapsulated sentence.
/// Multi-sentence messages must be reassembled before AIS decoding.
class VdmData {
  final int fragmentCount;
  final int fragmentNumber;
  final int? sequentialId;
  final String channel; // A or B
  final String payload; // 6-bit encoded AIS payload
  final int fillBits;

  const VdmData({
    required this.fragmentCount,
    required this.fragmentNumber,
    this.sequentialId,
    required this.channel,
    required this.payload,
    required this.fillBits,
  });

  bool get isComplete => fragmentCount == 1;
  bool get isFirstFragment => fragmentNumber == 1;

  static VdmData? fromSentence(NmeaSentence s) {
    if ((s.type != 'VDM' && s.type != 'VDO') || s.fields.length < 5) {
      return null;
    }
    final f = s.fields;
    final fragCount = int.tryParse(f[0]);
    final fragNum = int.tryParse(f[1]);
    final seqId = int.tryParse(f[2]);
    final channel = f[3];
    final payload = f[4];
    final fill = int.tryParse(f[5]) ?? 0;

    if (fragCount == null || fragNum == null || payload.isEmpty) return null;

    return VdmData(
      fragmentCount: fragCount,
      fragmentNumber: fragNum,
      sequentialId: seqId,
      channel: channel,
      payload: payload,
      fillBits: fill,
    );
  }
}

/// Reassembles multi-part VDM messages.
class VdmAssembler {
  final Map<int, List<VdmData>> _pending = {};

  /// Feed a VdmData fragment. Returns the full payload when all fragments
  /// have been received, or null if still waiting for more.
  String? addFragment(VdmData vdm) {
    if (vdm.isComplete) return vdm.payload;

    final key = vdm.sequentialId ?? 0;
    _pending.putIfAbsent(key, () => []);

    if (vdm.isFirstFragment) {
      _pending[key] = [vdm];
    } else {
      _pending[key]!.add(vdm);
    }

    if (_pending[key]!.length == vdm.fragmentCount) {
      _pending[key]!.sort((a, b) => a.fragmentNumber.compareTo(b.fragmentNumber));
      final full = _pending[key]!.map((f) => f.payload).join();
      _pending.remove(key);
      return full;
    }
    return null;
  }
}
