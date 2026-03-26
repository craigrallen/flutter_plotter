import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'nmea_source.dart';

/// Listens for NMEA sentences on a UDP port.
/// Each datagram may contain one or more newline-separated sentences.
class UdpSource implements NmeaSource {
  final int port;

  RawDatagramSocket? _socket;
  final _controller = StreamController<String>.broadcast();

  UdpSource({required this.port});

  @override
  Stream<String> get sentences => _controller.stream;

  @override
  bool get isConnected => _socket != null;

  @override
  Future<void> connect() async {
    await disconnect();
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data);
        for (final line in text.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) _controller.add(trimmed);
        }
      }
    });
  }

  @override
  Future<void> disconnect() async {
    _socket?.close();
    _socket = null;
  }
}
