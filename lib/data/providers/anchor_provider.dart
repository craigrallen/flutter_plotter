import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/anchor/anchor_watch.dart';
import 'vessel_provider.dart';

class AnchorState {
  final bool isActive;
  final LatLng? dropPosition;
  final double radiusM;
  final double? currentDistanceM;
  final bool isDragging;

  const AnchorState({
    this.isActive = false,
    this.dropPosition,
    this.radiusM = 30,
    this.currentDistanceM,
    this.isDragging = false,
  });

  AnchorState copyWith({
    bool? isActive,
    LatLng? dropPosition,
    double? radiusM,
    double? currentDistanceM,
    bool? isDragging,
  }) {
    return AnchorState(
      isActive: isActive ?? this.isActive,
      dropPosition: dropPosition ?? this.dropPosition,
      radiusM: radiusM ?? this.radiusM,
      currentDistanceM: currentDistanceM ?? this.currentDistanceM,
      isDragging: isDragging ?? this.isDragging,
    );
  }
}

class AnchorNotifier extends StateNotifier<AnchorState> {
  final Ref _ref;
  Timer? _timer;
  final _audioPlayer = AudioPlayer();
  FlutterLocalNotificationsPlugin? _notifications;
  bool _alarmPlaying = false;

  AnchorNotifier(this._ref) : super(const AnchorState()) {
    _loadPersisted();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    _notifications = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );
    await _notifications!.initialize(initSettings);
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getBool('anchor_active') ?? false;
    final lat = prefs.getDouble('anchor_lat');
    final lon = prefs.getDouble('anchor_lon');
    final radius = prefs.getDouble('anchor_radius') ?? 30;

    if (active && lat != null && lon != null) {
      state = AnchorState(
        isActive: true,
        dropPosition: LatLng(lat, lon),
        radiusM: radius,
      );
      _startMonitoring();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('anchor_active', state.isActive);
    if (state.dropPosition != null) {
      await prefs.setDouble('anchor_lat', state.dropPosition!.latitude);
      await prefs.setDouble('anchor_lon', state.dropPosition!.longitude);
    }
    await prefs.setDouble('anchor_radius', state.radiusM);
  }

  /// Drop anchor at current vessel position or specified position.
  void dropAnchor({LatLng? position}) {
    final pos = position ?? _ref.read(vesselProvider).position;
    if (pos == null) return;

    state = state.copyWith(
      isActive: true,
      dropPosition: pos,
      isDragging: false,
      currentDistanceM: 0,
    );
    _persist();
    _startMonitoring();
  }

  /// Release anchor watch.
  void releaseAnchor() {
    _timer?.cancel();
    _timer = null;
    _stopAlarm();
    state = const AnchorState();
    _persist();
  }

  /// Update watch radius.
  void setRadius(double radiusM) {
    state = state.copyWith(radiusM: radiusM);
    _persist();
  }

  void _startMonitoring() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkPosition();
    });
  }

  void _checkPosition() {
    if (!state.isActive || state.dropPosition == null) return;

    final vessel = _ref.read(vesselProvider);
    if (vessel.position == null) return;

    final watch = AnchorWatch(
      dropPosition: state.dropPosition!,
      radiusM: state.radiusM,
    );

    final dist = watch.distanceM(vessel.position!);
    final dragging = watch.isDragging(vessel.position!);

    state = state.copyWith(
      currentDistanceM: dist,
      isDragging: dragging,
    );

    if (dragging && !_alarmPlaying) {
      _triggerAlarm();
    } else if (!dragging && _alarmPlaying) {
      _stopAlarm();
    }
  }

  Future<void> _triggerAlarm() async {
    _alarmPlaying = true;

    // Play beep sound (system alert).
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(
        AssetSource('sounds/anchor_alarm.mp3'),
        volume: 1.0,
      );
    } catch (_) {
      // Sound file may not exist; alarm still fires via notification.
    }

    // Show notification.
    try {
      const androidDetails = AndroidNotificationDetails(
        'anchor_alarm',
        'Anchor Alarm',
        channelDescription: 'Anchor drag alarm',
        importance: Importance.max,
        priority: Priority.high,
        ongoing: true,
      );
      const details = NotificationDetails(android: androidDetails);
      await _notifications?.show(
        42,
        'Anchor Dragging!',
        'Vessel has moved ${state.currentDistanceM?.toStringAsFixed(0)}m '
            'from anchor (limit: ${state.radiusM.toStringAsFixed(0)}m)',
        details,
      );
    } catch (_) {}
  }

  Future<void> _stopAlarm() async {
    _alarmPlaying = false;
    try {
      await _audioPlayer.stop();
      await _notifications?.cancel(42);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}

final anchorProvider =
    StateNotifierProvider<AnchorNotifier, AnchorState>((ref) {
  return AnchorNotifier(ref);
});
