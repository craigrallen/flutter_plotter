import 'dart:async';
import 'nmea_source.dart';
import 'tcp_source.dart';
import 'udp_source.dart';

enum NmeaProtocol { tcp, udp }

enum NmeaConnectionState { disconnected, connecting, connected, reconnecting }

/// Unified NMEA stream that manages a single [NmeaSource] and auto-reconnects.
class NmeaStream {
  NmeaSource? _source;
  StreamSubscription<String>? _sub;
  Timer? _reconnectTimer;

  final _sentenceController = StreamController<String>.broadcast();
  final _stateController =
      StreamController<NmeaConnectionState>.broadcast();

  NmeaConnectionState _connectionState = NmeaConnectionState.disconnected;

  String? _host;
  int? _port;
  NmeaProtocol? _protocol;

  Stream<String> get sentences => _sentenceController.stream;
  Stream<NmeaConnectionState> get connectionState => _stateController.stream;
  NmeaConnectionState get currentState => _connectionState;

  Future<void> connect({
    required String host,
    required int port,
    required NmeaProtocol protocol,
  }) async {
    await disconnect();
    _host = host;
    _port = port;
    _protocol = protocol;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    _setState(NmeaConnectionState.connecting);
    try {
      _source = _protocol == NmeaProtocol.tcp
          ? TcpSource(host: _host!, port: _port!)
          : UdpSource(port: _port!);
      await _source!.connect();
      _setState(NmeaConnectionState.connected);
      _sub = _source!.sentences.listen(
        (s) => _sentenceController.add(s),
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_host == null) return;
    _sub?.cancel();
    _setState(NmeaConnectionState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _doConnect);
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub?.cancel();
    _sub = null;
    await _source?.disconnect();
    _source = null;
    _host = null;
    _port = null;
    _protocol = null;
    _setState(NmeaConnectionState.disconnected);
  }

  void _setState(NmeaConnectionState s) {
    _connectionState = s;
    _stateController.add(s);
  }

  void dispose() {
    disconnect();
    _sentenceController.close();
    _stateController.close();
  }
}
