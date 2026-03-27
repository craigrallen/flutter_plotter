import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/floatilla/floatilla_models.dart';
import '../../core/floatilla/floatilla_service.dart';
import 'vessel_provider.dart';

// ── Service singleton ───────────────────────────────────────

final floatillaServiceProvider = Provider<FloatillaService>((ref) {
  return FloatillaService.instance;
});

// ── Auth state ──────────────────────────────────────────────

final isLoggedInProvider = StateProvider<bool>((ref) {
  return ref.watch(floatillaServiceProvider).isLoggedIn();
});

// ── Friends ─────────────────────────────────────────────────

class FriendsNotifier extends StateNotifier<AsyncValue<List<FloatillaUser>>> {
  final FloatillaService _service;

  FriendsNotifier(this._service) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    if (!_service.isLoggedIn()) {
      state = const AsyncValue.data([]);
      return;
    }
    try {
      final friends = await _service.getFriends();
      state = AsyncValue.data(friends);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

  void updateFromWs(FloatillaUser updated) {
    final current = state.valueOrNull ?? [];
    final idx = current.indexWhere((f) => f.id == updated.id);
    if (idx >= 0) {
      final list = [...current];
      list[idx] = updated;
      state = AsyncValue.data(list);
    } else {
      state = AsyncValue.data([...current, updated]);
    }
  }
}

final friendsProvider =
    StateNotifierProvider<FriendsNotifier, AsyncValue<List<FloatillaUser>>>(
        (ref) {
  return FriendsNotifier(ref.watch(floatillaServiceProvider));
});

// ── Messages ────────────────────────────────────────────────

class MessagesNotifier
    extends StateNotifier<AsyncValue<List<FloatillaMessage>>> {
  final FloatillaService _service;

  MessagesNotifier(this._service) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    if (!_service.isLoggedIn()) {
      state = const AsyncValue.data([]);
      return;
    }
    try {
      final msgs = await _service.getMessages();
      state = AsyncValue.data(msgs);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

  void prepend(FloatillaMessage msg) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([msg, ...current]);
  }
}

final messagesProvider = StateNotifierProvider<MessagesNotifier,
    AsyncValue<List<FloatillaMessage>>>((ref) {
  return MessagesNotifier(ref.watch(floatillaServiceProvider));
});

// ── MoB Alert ───────────────────────────────────────────────

final mobAlertProvider = StateProvider<MobAlert?>((ref) => null);

// ── Pending Waypoints ───────────────────────────────────────

final pendingWaypointsProvider =
    StateProvider<List<FloatillaWaypoint>>((ref) => []);

// ── Floatilla settings ──────────────────────────────────────

final floatillaAutoShareProvider = StateProvider<bool>((ref) => false);
final floatillaServerUrlProvider =
    StateProvider<String>((ref) => 'https://fleet.floatilla.app');

// ── Background location sharing ─────────────────────────────

final floatillaLocationSharingProvider = Provider<void>((ref) {
  final autoShare = ref.watch(floatillaAutoShareProvider);
  final service = ref.watch(floatillaServiceProvider);
  if (!autoShare || !service.isLoggedIn()) return;

  Timer? timer;
  timer = Timer.periodic(const Duration(seconds: 60), (_) {
    final vessel = ref.read(vesselProvider);
    if (vessel.position != null &&
        vessel.sog != null &&
        vessel.sog! > 0.5) {
      service.updateLocation(
        vessel.position!,
        vessel.sog!,
        vessel.cog ?? 0,
      );
    }
  });

  ref.onDispose(() => timer?.cancel());
});

// ── WebSocket event wiring ──────────────────────────────────

final floatillaWsWiringProvider = Provider<void>((ref) {
  final service = ref.watch(floatillaServiceProvider);
  if (!service.isLoggedIn()) return;

  service.onMessage = (json) {
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      final msg = FloatillaMessage.fromJson(data);
      ref.read(messagesProvider.notifier).prepend(msg);
    } catch (_) {}
  };

  service.onFriendUpdate = (json) {
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      final user = FloatillaUser.fromJson(data);
      ref.read(friendsProvider.notifier).updateFromWs(user);
    } catch (_) {}
  };

  service.onWaypointShared = (json) {
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      final wp = FloatillaWaypoint.fromJson(data);
      final current = ref.read(pendingWaypointsProvider);
      ref.read(pendingWaypointsProvider.notifier).state = [...current, wp];
    } catch (_) {}
  };

  service.onMobAlert = (json) {
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      final alert = MobAlert.fromJson(data);
      ref.read(mobAlertProvider.notifier).state = alert;
    } catch (_) {}
  };

  ref.onDispose(() {
    service.onMessage = null;
    service.onFriendUpdate = null;
    service.onWaypointShared = null;
    service.onMobAlert = null;
  });
});
