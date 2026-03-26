import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'nmea_source.dart';

/// Connects to an NMEA source via TCP (host:port).
/// Splits the byte stream on line boundaries and emits individual sentences.
class TcpSource implements NmeaSource {
  final String host;
  final int port;

  Socket? _socket;
  final _controller = StreamController<String>.broadcast();
  String _buffer = '';

  TcpSource({required this.host, required this.port});

  @override
  Stream<String> get sentences => _controller.stream;

  @override
  bool get isConnected => _socket != null;

  @override
  Future<void> connect() async {
    await disconnect();
    _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    _socket!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen(
      _onData,
      onError: (e) => _controller.addError(e),
      onDone: () {
        _socket = null;
        _controller.addError(const SocketException('Connection closed'));
      },
    );
  }

  void _onData(String chunk) {
    _buffer += chunk;
    while (true) {
      final idx = _buffer.indexOf('\n');
      if (idx == -1) break;
      final line = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + 1);
      if (line.isNotEmpty) _controller.add(line);
    }
  }

  @override
  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
    _buffer = '';
  }
}
