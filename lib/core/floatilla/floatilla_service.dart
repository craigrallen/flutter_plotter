import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'floatilla_models.dart';

typedef WsMessageCallback = void Function(Map<String, dynamic> data);

class FloatillaService {
  FloatillaService._();
  static final instance = FloatillaService._();

  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'floatilla_jwt';

  String baseUrl = 'https://floatilla-fleet-social-production.up.railway.app';
  String? _token;
  String? _username;
  String? _vesselName;

  WebSocketChannel? _ws;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _intentionalClose = false;

  // Callbacks for WebSocket events
  WsMessageCallback? onMessage;
  WsMessageCallback? onFriendUpdate;
  WsMessageCallback? onWaypointShared;
  WsMessageCallback? onMobAlert;

  String? get username => _username;
  String? get vesselName => _vesselName;

  // ── Auth ──────────────────────────────────────────────────

  Future<void> init() async {
    _token = await _storage.read(key: _tokenKey);
    _username = await _storage.read(key: 'floatilla_username');
    _vesselName = await _storage.read(key: 'floatilla_vessel');
    if (_token != null) {
      _connectWebSocket();
    }
  }

  bool isLoggedIn() => _token != null;

  Future<bool> login(String username, String password) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (resp.statusCode != 200) return false;

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    _token = body['token'] as String;
    _username = body['username'] as String? ?? username;
    _vesselName = body['vesselName'] as String?;
    await _storage.write(key: _tokenKey, value: _token);
    await _storage.write(key: 'floatilla_username', value: _username);
    if (_vesselName != null) {
      await _storage.write(key: 'floatilla_vessel', value: _vesselName);
    }
    _connectWebSocket();
    return true;
  }

  Future<bool> register(
      String username, String vesselName, String password) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'vesselName': vesselName,
        'password': password,
      }),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) return false;

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    _token = body['token'] as String;
    _username = username;
    _vesselName = vesselName;
    await _storage.write(key: _tokenKey, value: _token);
    await _storage.write(key: 'floatilla_username', value: _username);
    await _storage.write(key: 'floatilla_vessel', value: _vesselName);
    _connectWebSocket();
    return true;
  }

  Future<void> requestPasswordReset(String usernameOrEmail) async {
    await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'identifier': usernameOrEmail}),
    );
    // Fire-and-forget: always succeed from UX perspective (don't leak user existence)
  }

  Future<void> logout() async {
    _intentionalClose = true;
    _ws?.sink.close();
    _ws = null;
    _reconnectTimer?.cancel();
    _token = null;
    _username = null;
    _vesselName = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: 'floatilla_username');
    await _storage.delete(key: 'floatilla_vessel');
  }

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  // ── Messages ──────────────────────────────────────────────

  Future<List<FloatillaMessage>> getMessages({int page = 1}) async {
    final resp = await http.get(
      Uri.parse('$baseUrl/messages?page=$page'),
      headers: _authHeaders,
    );
    if (resp.statusCode != 200) return [];
    final list = jsonDecode(resp.body) as List;
    return list
        .map((e) => FloatillaMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<bool> sendMessage(String text, {LatLng? position}) async {
    final body = <String, dynamic>{'text': text};
    if (position != null) {
      body['lat'] = position.latitude;
      body['lng'] = position.longitude;
    }
    final resp = await http.post(
      Uri.parse('$baseUrl/messages'),
      headers: _authHeaders,
      body: jsonEncode(body),
    );
    return resp.statusCode == 200 || resp.statusCode == 201;
  }

  // ── Friends ───────────────────────────────────────────────

  Future<List<FloatillaUser>> getFriends() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/friends'),
      headers: _authHeaders,
    );
    if (resp.statusCode != 200) return [];
    final list = jsonDecode(resp.body) as List;
    return list
        .map((e) => FloatillaUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<bool> sendFriendRequest(String username) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/friends/add'),
      headers: _authHeaders,
      body: jsonEncode({'username': username}),
    );
    return resp.statusCode == 200 || resp.statusCode == 201;
  }

  Future<bool> acceptFriendRequest(String friendshipId) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/friends/accept'),
      headers: _authHeaders,
      body: jsonEncode({'friendshipId': friendshipId}),
    );
    return resp.statusCode == 200;
  }

  Future<bool> removeFriend(int friendId) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/friends/remove'),
      headers: _authHeaders,
      body: jsonEncode({'friendId': friendId}),
    );
    return resp.statusCode == 200;
  }

  Future<List<FloatillaFriendRequest>> getFriendRequests() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/friends/requests'),
      headers: _authHeaders,
    );
    if (resp.statusCode != 200) return [];
    final list = jsonDecode(resp.body) as List;
    return list
        .map((e) => FloatillaFriendRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Location ──────────────────────────────────────────────

  Future<void> updateLocation(LatLng pos, double sog, double cog) async {
    await http.post(
      Uri.parse('$baseUrl/users/location'),
      headers: _authHeaders,
      body: jsonEncode({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'sog': sog,
        'cog': cog,
      }),
    );
  }

  // ── Waypoints ─────────────────────────────────────────────

  Future<bool> shareWaypoint(LatLng pos, String name) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/waypoints'),
      headers: _authHeaders,
      body: jsonEncode({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'name': name,
      }),
    );
    return resp.statusCode == 200 || resp.statusCode == 201;
  }

  // ── MoB ───────────────────────────────────────────────────

  Future<bool> triggerMoB(LatLng position) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/mob'),
      headers: _authHeaders,
      body: jsonEncode({
        'lat': position.latitude,
        'lng': position.longitude,
      }),
    );
    return resp.statusCode == 200 || resp.statusCode == 201;
  }

  // ── WebSocket ─────────────────────────────────────────────

  void _connectWebSocket() {
    if (_token == null) return;
    _intentionalClose = false;

    final wsScheme = baseUrl.startsWith('https') ? 'wss' : 'ws';
    final host = baseUrl.replaceFirst(RegExp(r'^https?://'), '');
    final uri = Uri.parse('$wsScheme://$host/ws?token=$_token');

    _ws?.sink.close();
    _ws = WebSocketChannel.connect(uri);
    _reconnectAttempts = 0;

    _ws!.stream.listen(
      (data) {
        final json = jsonDecode(data as String) as Map<String, dynamic>;
        final type = json['type'] as String?;
        switch (type) {
          case 'message':
            onMessage?.call(json);
          case 'friend_update':
            onFriendUpdate?.call(json);
          case 'waypoint_shared':
            onWaypointShared?.call(json);
          case 'mob':
            onMobAlert?.call(json);
        }
      },
      onDone: () {
        if (!_intentionalClose) _scheduleReconnect();
      },
      onError: (_) {
        if (!_intentionalClose) _scheduleReconnect();
      },
    );
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = Duration(
      seconds: min(30, pow(2, _reconnectAttempts).toInt()),
    );
    _reconnectAttempts++;
    _reconnectTimer = Timer(delay, _connectWebSocket);
  }

  void dispose() {
    _intentionalClose = true;
    _reconnectTimer?.cancel();
    _ws?.sink.close();
  }
}
