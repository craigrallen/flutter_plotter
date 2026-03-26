/// Validates NMEA checksums and routes sentences to typed parsers.
class NmeaSentence {
  final String talker; // e.g. "GP", "AI"
  final String type; // e.g. "RMC", "VDM"
  final List<String> fields;
  final String raw;

  NmeaSentence({
    required this.talker,
    required this.type,
    required this.fields,
    required this.raw,
  });
}

class SentenceParser {
  /// Parse a raw NMEA sentence string.
  /// Returns null if checksum is invalid or sentence is malformed.
  static NmeaSentence? parse(String raw) {
    final line = raw.trim();
    if (line.length < 6) return null;

    // Must start with $ or !
    final start = line[0];
    if (start != '\$' && start != '!') return null;

    // Split off checksum
    final starIdx = line.indexOf('*');
    String body;
    if (starIdx != -1) {
      final checksumStr = line.substring(starIdx + 1).trim();
      body = line.substring(1, starIdx);
      if (!_validateChecksum(body, checksumStr)) return null;
    } else {
      body = line.substring(1);
    }

    final fields = body.split(',');
    if (fields.isEmpty) return null;

    final tag = fields[0];
    if (tag.length < 3) return null;

    // Talker is first 2 chars, type is the rest (e.g. GPRMC → GP + RMC)
    // For encapsulated sentences (! prefix), tag can be like AIVDM
    final talker = tag.substring(0, tag.length - 3);
    final type = tag.substring(tag.length - 3);

    return NmeaSentence(
      talker: talker,
      type: type,
      fields: fields.sublist(1),
      raw: raw,
    );
  }

  static bool _validateChecksum(String body, String checksumStr) {
    if (checksumStr.length < 2) return false;
    final expected = int.tryParse(checksumStr.substring(0, 2), radix: 16);
    if (expected == null) return false;

    int computed = 0;
    for (int i = 0; i < body.length; i++) {
      computed ^= body.codeUnitAt(i);
    }
    return computed == expected;
  }
}
