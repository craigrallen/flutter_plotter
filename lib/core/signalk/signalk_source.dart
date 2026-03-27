import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connection state for the Signal K WebSocket.
enum SignalKConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// WebSocket client for Signal K server.
///
/// Connects to `ws://host:port/signalk/v1/stream?subscribe=all`
/// and sends an explicit wildcard subscription for ALL contexts and ALL paths.
/// Reconnects with exponential backoff on failure.
class SignalKSource {
  final String host;
  final int port;
  final String? token;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  int _backoffMs = 1000;

  final _messageController = StreamController<String>.broadcast();
  final _stateController =
      StreamController<SignalKConnectionState>.broadcast();
  bool _disposed = false;
  SignalKConnectionState _connectionState = SignalKConnectionState.disconnected;

  SignalKSource({required this.host, required this.port, this.token});

  /// Stream of raw delta JSON strings from the server.
  Stream<String> get messages => _messageController.stream;

  /// Stream of connection state changes.
  Stream<SignalKConnectionState> get connectionState => _stateController.stream;

  /// Current connection state (synchronous).
  SignalKConnectionState get state => _connectionState;

  void _setState(SignalKConnectionState s) {
    _connectionState = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  Future<void> connect() async {
    await disconnect();
    _disposed = false;
    _doConnect();
  }

  void _doConnect() {
    if (_disposed) return;
    _setState(SignalKConnectionState.connecting);

    // Build URI with subscribe=all and optional token as query param.
    final queryParams = <String, String>{'subscribe': 'all'};
    if (token != null && token!.isNotEmpty) {
      queryParams['token'] = token!;
    }
    final uri = Uri(
      scheme: 'ws',
      host: host,
      port: port,
      path: '/signalk/v1/stream',
      queryParameters: queryParams,
    );

    try {
      _channel = WebSocketChannel.connect(uri);
      _backoffMs = 1000;

      _sub = _channel!.stream.listen(
        (data) {
          if (_connectionState != SignalKConnectionState.connected) {
            _setState(SignalKConnectionState.connected);
          }
          if (data is String && !_messageController.isClosed) {
            _messageController.add(data);
          }
        },
        onError: (_) {
          _setState(SignalKConnectionState.error);
          _scheduleReconnect();
        },
        onDone: () {
          _setState(SignalKConnectionState.disconnected);
          _scheduleReconnect();
        },
      );

      // Send explicit wildcard subscription for everything.
      _channel!.sink.add(jsonEncode({
        'context': '*',
        'subscribe': [
          {'path': '*', 'period': 1000, 'policy': 'ideal'},
        ],
      }));
    } catch (_) {
      _setState(SignalKConnectionState.error);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _backoffMs), _doConnect);
    _backoffMs = min(_backoffMs * 2, 30000);
  }

  Future<void> disconnect() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _setState(SignalKConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
  }
}
