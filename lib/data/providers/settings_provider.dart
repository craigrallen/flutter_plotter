import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Distance/speed unit system.
enum UnitSystem { metric, imperial, nautical }

/// App-wide settings persisted to SharedPreferences.
class AppSettings {
  final bool nightMode;
  final UnitSystem units;
  final double cpaAlarmDistanceNm;
  final double cpaAlarmTimeMinutes;
  final bool nmeaDebugEnabled;

  const AppSettings({
    this.nightMode = false,
    this.units = UnitSystem.nautical,
    this.cpaAlarmDistanceNm = 0.5,
    this.cpaAlarmTimeMinutes = 10,
    this.nmeaDebugEnabled = false,
  });

  AppSettings copyWith({
    bool? nightMode,
    UnitSystem? units,
    double? cpaAlarmDistanceNm,
    double? cpaAlarmTimeMinutes,
    bool? nmeaDebugEnabled,
  }) {
    return AppSettings(
      nightMode: nightMode ?? this.nightMode,
      units: units ?? this.units,
      cpaAlarmDistanceNm: cpaAlarmDistanceNm ?? this.cpaAlarmDistanceNm,
      cpaAlarmTimeMinutes: cpaAlarmTimeMinutes ?? this.cpaAlarmTimeMinutes,
      nmeaDebugEnabled: nmeaDebugEnabled ?? this.nmeaDebugEnabled,
    );
  }

  /// Format a distance value according to the current unit system.
  String formatDistance(double nm) {
    switch (units) {
      case UnitSystem.nautical:
        return '${nm.toStringAsFixed(2)} nm';
      case UnitSystem.metric:
        final km = nm * 1.852;
        return km >= 1
            ? '${km.toStringAsFixed(2)} km'
            : '${(km * 1000).toStringAsFixed(0)} m';
      case UnitSystem.imperial:
        final mi = nm * 1.15078;
        return '${mi.toStringAsFixed(2)} mi';
    }
  }

  /// Format a speed value (input in knots) according to the current unit system.
  String formatSpeed(double knots) {
    switch (units) {
      case UnitSystem.nautical:
        return '${knots.toStringAsFixed(1)} kn';
      case UnitSystem.metric:
        return '${(knots * 1.852).toStringAsFixed(1)} km/h';
      case UnitSystem.imperial:
        return '${(knots * 1.15078).toStringAsFixed(1)} mph';
    }
  }

  /// Format depth (input in metres) according to the current unit system.
  String formatDepth(double metres) {
    switch (units) {
      case UnitSystem.nautical:
      case UnitSystem.metric:
        return '${metres.toStringAsFixed(1)} m';
      case UnitSystem.imperial:
        return '${(metres * 3.28084).toStringAsFixed(1)} ft';
    }
  }
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      nightMode: prefs.getBool('night_mode') ?? false,
      units: UnitSystem.values[prefs.getInt('units') ?? 2],
      cpaAlarmDistanceNm: prefs.getDouble('cpa_alarm_dist') ?? 0.5,
      cpaAlarmTimeMinutes: prefs.getDouble('cpa_alarm_time') ?? 10,
      nmeaDebugEnabled: prefs.getBool('nmea_debug') ?? false,
    );
  }

  Future<void> update(AppSettings settings) async {
    state = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('night_mode', settings.nightMode);
    await prefs.setInt('units', settings.units.index);
    await prefs.setDouble('cpa_alarm_dist', settings.cpaAlarmDistanceNm);
    await prefs.setDouble('cpa_alarm_time', settings.cpaAlarmTimeMinutes);
    await prefs.setBool('nmea_debug', settings.nmeaDebugEnabled);
  }

  void toggleNightMode() {
    update(state.copyWith(nightMode: !state.nightMode));
  }

  void toggleNmeaDebug() {
    update(state.copyWith(nmeaDebugEnabled: !state.nmeaDebugEnabled));
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  return AppSettingsNotifier();
});
