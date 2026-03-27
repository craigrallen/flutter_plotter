import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/routing/route_engine.dart';
import '../../core/routing/engines/opensea_engine.dart';
import '../../core/routing/engines/enc_engine.dart';
import '../../core/routing/engines/api_engine.dart';
import 'routing_api_provider.dart';

const _key = 'selected_route_engine';

final allRouteEnginesProvider = Provider<List<RouteEngine>>((ref) {
  final apiConfig = ref.watch(routingApiProvider);
  return [
    OpenSeaEngine(),
    EncEngine(),
    ApiEngine(apiConfig),
  ];
});

class SelectedEngineNotifier extends StateNotifier<String> {
  SelectedEngineNotifier() : super('opensea') {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_key) ?? 'opensea';
  }

  Future<void> select(String engineId) async {
    state = engineId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, engineId);
  }
}

final selectedEngineIdProvider =
    StateNotifierProvider<SelectedEngineNotifier, String>((ref) {
  return SelectedEngineNotifier();
});

final currentRouteEngineProvider = Provider<RouteEngine>((ref) {
  final engines = ref.watch(allRouteEnginesProvider);
  final selectedId = ref.watch(selectedEngineIdProvider);
  return engines.firstWhere(
    (e) => e.id == selectedId,
    orElse: () => engines.first,
  );
});
