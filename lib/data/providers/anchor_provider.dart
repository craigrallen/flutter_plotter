import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
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
  final bool notificationsGranted;

  const AnchorState({
    this.isActive = false,
    this.dropPosition,
    this.radiusM = 30,
    this.currentDistanceM,
    this.isDragging = false,
    this.notificationsGranted = false,
  });

  AnchorState copyWith({
    bool? isActive,
    LatLng? dropPosition,
    double? radiusM,
    double? currentDistanceM,
    bool? isDragging,
    bool? notificationsGranted,
  }) {
    return AnchorState(
      isActive: isActive ?? this.isActive,
      dropPosition: dropPosition ?? this.dropPosition,
      radiusM: radiusM ?? this.radiusM,
      currentDistanceM: currentDistanceM ?? this.currentDistanceM,
      isDragging: isDragging ?? this.isDragging,
      notificationsGranted: notificationsGranted ?? this.notificationsGranted,
    );
  }
}

class AnchorNotifier extends StateNotifier<AnchorState> {
  final Ref _ref;
  Timer? _timer;
  final _audioPlayer = AudioPlayer();
  FlutterLocalNotificationsPlugin? _notifications;
  bool _alarmPlaying = false;
  bool _notificationsInitialised = false;

  // Notification IDs
  static const _alarmChannelId = 'anchor_alarm';
  static const _alarmChannelName = 'Anchor Alarm';
  static const _alarmNotificationId = 42;
  static const _watchChannelId = 'anchor_watch';
  static const _watchChannelName = 'Anchor Watch';
  static const _watchNotificationId = 43;

  // Throttle drag notification updates to once every 10s
  DateTime? _lastDragNotificationUpdate;

  AnchorNotifier(this._ref) : super(const AnchorState()) {
    _loadPersisted();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    if (_notificationsInitialised) return;
    try {
      _notifications = FlutterLocalNotificationsPlugin();

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
      );
      await _notifications!.initialize(initSettings);

      if (Platform.isAndroid) {
        final androidPlugin = _notifications!
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        // High-priority alarm channel for drag alerts.
        await androidPlugin?.createNotificationChannel(
          AndroidNotificationChannel(
            _alarmChannelId,
            _alarmChannelName,
            description: 'Alerts when your vessel drags anchor',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            vibrationPattern:
                Int64List.fromList([0, 500, 250, 500, 250, 500]),
            enableLights: true,
            ledColor: const Color(0xFFFF0000),
          ),
        );

        // Low-priority persistent channel for "watch active" status.
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            _watchChannelId,
            _watchChannelName,
            description: 'Persistent status while anchor watch is running',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
          ),
        );
      }

      _notificationsInitialised = true;
    } catch (e) {
      debugPrint('AnchorNotifier: notification init failed: $e');
    }
  }

  /// Request notification permission (Android 13+ / iOS).
  /// Returns true if granted or not required.
  Future<bool> requestNotificationPermission() async {
    await _initNotifications();
    try {
      bool granted = false;
      if (Platform.isAndroid) {
        final androidPlugin = _notifications!
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        granted =
            await androidPlugin?.requestNotificationsPermission() ?? false;
      } else if (Platform.isIOS || Platform.isMacOS) {
        final darwinPlugin = _notifications!
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        granted = await darwinPlugin?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      } else {
        granted = true; // Not required on other platforms.
      }
      state = state.copyWith(notificationsGranted: granted);
      return granted;
    } catch (e) {
      debugPrint('AnchorNotifier: permission request failed: $e');
      return false;
    }
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
    _showWatchActiveNotification();
  }

  /// Release anchor watch.
  void releaseAnchor() {
    _timer?.cancel();
    _timer = null;
    _stopAlarm();
    _cancelWatchActiveNotification();
    state = const AnchorState();
    _persist();
  }

  /// Update watch radius.
  void setRadius(double radiusM) {
    state = state.copyWith(radiusM: radiusM);
    _persist();
    if (state.isActive) _updateWatchActiveNotification();
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
      // Cancel the "watch active" status notification when alarm fires.
      _cancelWatchActiveNotification();
    } else if (!dragging && _alarmPlaying) {
      _stopAlarm();
      _showWatchActiveNotification();
    } else if (dragging && _alarmPlaying) {
      // Throttle drag notification updates to once every 10 seconds.
      final now = DateTime.now();
      if (_lastDragNotificationUpdate == null ||
          now.difference(_lastDragNotificationUpdate!).inSeconds >= 10) {
        _lastDragNotificationUpdate = now;
        _updateAlarmNotification();
      }
    } else if (!dragging) {
      // Update watch status notification with current distance (throttled).
      final now = DateTime.now();
      if (_lastDragNotificationUpdate == null ||
          now.difference(_lastDragNotificationUpdate!).inSeconds >= 30) {
        _lastDragNotificationUpdate = now;
        _updateWatchActiveNotification();
      }
    }
  }

  Future<void> _triggerAlarm() async {
    _alarmPlaying = true;
    _lastDragNotificationUpdate = null;

    // Play looping alarm sound.
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(
        AssetSource('sounds/anchor_alarm.mp3'),
        volume: 1.0,
      );
    } catch (_) {
      // Sound file may not exist; alarm still fires via notification.
    }

    await _showAlarmNotification();
  }

  Future<void> _showAlarmNotification() async {
    try {
      final distStr =
          state.currentDistanceM?.toStringAsFixed(0) ?? '?';
      final radiusStr = state.radiusM.toStringAsFixed(0);

      final androidDetails = AndroidNotificationDetails(
        _alarmChannelId,
        _alarmChannelName,
        channelDescription: 'Alerts when your vessel drags anchor',
        importance: Importance.max,
        priority: Priority.high,
        ongoing: true,
        autoCancel: false,
        // Full-screen intent for locked-screen alert (alarm-style).
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        vibrationPattern:
            Int64List.fromList([0, 500, 250, 500, 250, 500]),
        enableVibration: true,
        color: const Color(0xFFFF0000),
        colorized: true,
        styleInformation: BigTextStyleInformation(
          'Vessel is ${distStr}m from anchor (limit: ${radiusStr}m). '
          'Check your position immediately!',
          summaryText: 'Anchor Drag Alert',
        ),
      );

      const iosDetails = DarwinNotificationDetails(
        sound: 'default',
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.critical,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        macOS: const DarwinNotificationDetails(
          sound: 'default',
          presentAlert: true,
          presentSound: true,
        ),
      );

      await _notifications?.show(
        _alarmNotificationId,
        '⚓ Anchor Dragging!',
        'Vessel is ${distStr}m from anchor (limit: ${radiusStr}m)',
        details,
      );
    } catch (e) {
      debugPrint('AnchorNotifier: alarm notification failed: $e');
    }
  }

  Future<void> _updateAlarmNotification() async {
    try {
      await _showAlarmNotification();
    } catch (_) {}
  }

  /// Shows a persistent low-priority notification while anchor watch is active.
  /// On Android, uses the foreground service API so the OS cannot kill the
  /// monitoring timer while the screen is off.
  Future<void> _showWatchActiveNotification() async {
    try {
      final radiusStr = state.radiusM.toStringAsFixed(0);
      final distStr = state.currentDistanceM != null
          ? '${state.currentDistanceM!.toStringAsFixed(0)}m'
          : 'measuring...';

      final androidDetails = AndroidNotificationDetails(
        _watchChannelId,
        _watchChannelName,
        channelDescription: 'Persistent status while anchor watch is running',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        showWhen: false,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(
          'Watch radius: ${radiusStr}m · Current distance: $distStr\n'
          'Floatilla will alert you if your vessel drags.',
          summaryText: 'Anchor Watch Active',
        ),
      );

      if (Platform.isAndroid) {
        // Use startForegroundService so Android binds a real ForegroundService.
        // This prevents the OS from killing the monitoring timer when the
        // screen turns off (critical for overnight anchor watches).
        final androidPlugin = _notifications!
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.startForegroundService(
          _watchNotificationId,
          '⚓ Anchor Watch Active',
          'Monitoring · radius ${radiusStr}m · $distStr from anchor',
          notificationDetails: androidDetails,
          foregroundServiceTypes: {
            AndroidServiceForegroundType.foregroundServiceTypeLocation,
          },
        );
      } else {
        // iOS/macOS: regular silent notification (background location handles
        // the monitoring continuity via UIBackgroundModes=location).
        final details = NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: false,
          ),
          macOS: const DarwinNotificationDetails(
            presentAlert: false,
            presentSound: false,
          ),
        );
        await _notifications?.show(
          _watchNotificationId,
          '⚓ Anchor Watch Active',
          'Monitoring · radius ${radiusStr}m · $distStr from anchor',
          details,
        );
      }
    } catch (e) {
      debugPrint('AnchorNotifier: watch notification failed: $e');
    }
  }

  Future<void> _updateWatchActiveNotification() async {
    if (!state.isActive || state.isDragging) return;
    try {
      await _showWatchActiveNotification();
    } catch (_) {}
  }

  Future<void> _cancelWatchActiveNotification() async {
    try {
      if (Platform.isAndroid) {
        final androidPlugin = _notifications!
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.stopForegroundService();
      } else {
        await _notifications?.cancel(_watchNotificationId);
      }
    } catch (_) {}
  }

  Future<void> _stopAlarm() async {
    _alarmPlaying = false;
    _lastDragNotificationUpdate = null;
    try {
      await _audioPlayer.stop();
      await _notifications?.cancel(_alarmNotificationId);
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
