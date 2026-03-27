import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RoutingApiConfig {
  final String orsApiKey;
  final String navionicsApiKey;
  final bool useNavionics;

  const RoutingApiConfig({
    this.orsApiKey = '',
    this.navionicsApiKey = '',
    this.useNavionics = false,
  });

  RoutingApiConfig copyWith({
    String? orsApiKey,
    String? navionicsApiKey,
    bool? useNavionics,
  }) {
    return RoutingApiConfig(
      orsApiKey: orsApiKey ?? this.orsApiKey,
      navionicsApiKey: navionicsApiKey ?? this.navionicsApiKey,
      useNavionics: useNavionics ?? this.useNavionics,
    );
  }
}

class RoutingApiNotifier extends StateNotifier<RoutingApiConfig> {
  RoutingApiNotifier() : super(const RoutingApiConfig()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = RoutingApiConfig(
      orsApiKey: prefs.getString('ors_api_key') ?? '',
      navionicsApiKey: prefs.getString('navionics_api_key') ?? '',
      useNavionics: prefs.getBool('use_navionics') ?? false,
    );
  }

  Future<void> update(RoutingApiConfig config) async {
    state = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ors_api_key', config.orsApiKey);
    await prefs.setString('navionics_api_key', config.navionicsApiKey);
    await prefs.setBool('use_navionics', config.useNavionics);
  }
}

final routingApiProvider =
    StateNotifierProvider<RoutingApiNotifier, RoutingApiConfig>((ref) {
  return RoutingApiNotifier();
});
