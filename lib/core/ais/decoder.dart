/// AIS 6-bit ASCII payload decoder.
/// Unpacks the armoured payload from NMEA VDM sentences into a bit vector,
/// then provides helpers to extract unsigned/signed integers and strings.
class AisDecoder {
  final List<int> _bits;
  final int bitLength;

  AisDecoder._(this._bits, this.bitLength);

  /// Decode a 6-bit ASCII payload string into a bit array.
  factory AisDecoder.fromPayload(String payload, [int fillBits = 0]) {
    final bits = <int>[];
    for (int i = 0; i < payload.length; i++) {
      int c = payload.codeUnitAt(i) - 48;
      if (c > 40) c -= 8;
      for (int bit = 5; bit >= 0; bit--) {
        bits.add((c >> bit) & 1);
      }
    }
    final bitLen = bits.length - fillBits;
    return AisDecoder._(bits, bitLen);
  }

  /// Extract an unsigned integer from [start] to [start+length-1].
  int getUnsigned(int start, int length) {
    int val = 0;
    for (int i = start; i < start + length && i < _bits.length; i++) {
      val = (val << 1) | _bits[i];
    }
    return val;
  }

  /// Extract a signed integer (two's complement) from [start].
  int getSigned(int start, int length) {
    int val = getUnsigned(start, length);
    if (val >= (1 << (length - 1))) {
      val -= (1 << length);
    }
    return val;
  }

  /// Extract a 6-bit ASCII string from [start] with [charCount] characters.
  String getString(int start, int charCount) {
    final buf = StringBuffer();
    for (int i = 0; i < charCount; i++) {
      int c = getUnsigned(start + i * 6, 6);
      if (c < 32) c += 64; // Map 0-31 to @A-Z[\]^_
      buf.writeCharCode(c);
    }
    return buf.toString().replaceAll('@', ' ').trim();
  }

  /// The AIS message type (bits 0-5).
  int get messageType => getUnsigned(0, 6);
}
