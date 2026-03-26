/// Abstract NMEA data source.
/// Implementations provide a stream of raw NMEA sentences (one per event).
abstract class NmeaSource {
  Stream<String> get sentences;
  Future<void> connect();
  Future<void> disconnect();
  bool get isConnected;
}
