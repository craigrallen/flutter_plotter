import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which data source the app is using for vessel/instrument data.
enum DataSourceType {
  gpsOnly,
  nmeaTcp,
  nmeaUdp,
  signalK,
}

/// Persisted configuration for the active data source.
class DataSourceConfig {
  final DataSourceType type;
  final String host;
  final int port;
  final String? token; // Signal K bearer token

  const DataSourceConfig({
    this.type = DataSourceType.gpsOnly,
    this.host = '',
    this.port = 10110,
    this.token,
  });

  DataSourceConfig copyWith({
    DataSourceType? type,
    String? host,
    int? port,
    String? token,
  }) {
    return DataSourceConfig(
      type: type ?? this.type,
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
    );
  }

  bool get isSignalK => type == DataSourceType.signalK;
  bool get isNmea =>
      type == DataSourceType.nmeaTcp || type == DataSourceType.nmeaUdp;
  bool get isGpsOnly => type == DataSourceType.gpsOnly;
}

class DataSourceNotifier extends StateNotifier<DataSourceConfig> {
  DataSourceNotifier() : super(const DataSourceConfig()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final typeIndex = prefs.getInt('data_source_type') ?? 0;
    state = DataSourceConfig(
      type: DataSourceType.values[typeIndex.clamp(0, DataSourceType.values.length - 1)],
      host: prefs.getString('data_source_host') ?? '',
      port: prefs.getInt('data_source_port') ?? 10110,
      token: prefs.getString('data_source_token'),
    );
  }

  Future<void> update(DataSourceConfig config) async {
    state = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('data_source_type', config.type.index);
    await prefs.setString('data_source_host', config.host);
    await prefs.setInt('data_source_port', config.port);
    if (config.token != null) {
      await prefs.setString('data_source_token', config.token!);
    } else {
      await prefs.remove('data_source_token');
    }
  }
}

final dataSourceProvider =
    StateNotifierProvider<DataSourceNotifier, DataSourceConfig>((ref) {
  return DataSourceNotifier();
});
