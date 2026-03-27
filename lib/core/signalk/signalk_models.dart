import 'package:latlong2/latlong.dart';

/// Top-level Signal K delta envelope.
class SignalKDelta {
  final String? context;
  final List<SignalKUpdate> updates;

  const SignalKDelta({this.context, this.updates = const []});
}

/// A single update block within a delta (source + timestamp + values).
class SignalKUpdate {
  final String? source;
  final DateTime? timestamp;
  final List<SignalKValue> values;

  const SignalKUpdate({this.source, this.timestamp, this.values = const []});
}

/// A single path/value pair within an update.
class SignalKValue {
  final String path;
  final dynamic value;

  const SignalKValue({required this.path, required this.value});
}

// ── Navigation ──

class NavigationData {
  final LatLng? position;
  final double? sog; // knots
  final double? cog; // degrees true
  final double? headingTrue; // degrees
  final double? headingMagnetic; // degrees
  final double? rateOfTurn; // degrees/min
  final double? leewayAngle; // degrees

  const NavigationData({
    this.position,
    this.sog,
    this.cog,
    this.headingTrue,
    this.headingMagnetic,
    this.rateOfTurn,
    this.leewayAngle,
  });

  NavigationData copyWith({
    LatLng? position,
    double? sog,
    double? cog,
    double? headingTrue,
    double? headingMagnetic,
    double? rateOfTurn,
    double? leewayAngle,
  }) {
    return NavigationData(
      position: position ?? this.position,
      sog: sog ?? this.sog,
      cog: cog ?? this.cog,
      headingTrue: headingTrue ?? this.headingTrue,
      headingMagnetic: headingMagnetic ?? this.headingMagnetic,
      rateOfTurn: rateOfTurn ?? this.rateOfTurn,
      leewayAngle: leewayAngle ?? this.leewayAngle,
    );
  }
}

// ── Environment ──

class EnvironmentData {
  final double? depthBelowKeel; // metres
  final double? depthBelowTransducer; // metres
  final double? depthBelowSurface; // metres
  final double? windSpeedApparent; // knots
  final double? windAngleApparent; // degrees
  final double? windSpeedTrue; // knots
  final double? windAngleTrueWater; // degrees
  final double? windAngleTrueGround; // degrees
  final double? waterTemp; // °C
  final double? airTemp; // °C
  final double? pressure; // hPa
  final double? humidity; // ratio 0-1

  const EnvironmentData({
    this.depthBelowKeel,
    this.depthBelowTransducer,
    this.depthBelowSurface,
    this.windSpeedApparent,
    this.windAngleApparent,
    this.windSpeedTrue,
    this.windAngleTrueWater,
    this.windAngleTrueGround,
    this.waterTemp,
    this.airTemp,
    this.pressure,
    this.humidity,
  });

  /// Best available depth reading.
  double? get depth =>
      depthBelowKeel ?? depthBelowTransducer ?? depthBelowSurface;

  EnvironmentData copyWith({
    double? depthBelowKeel,
    double? depthBelowTransducer,
    double? depthBelowSurface,
    double? windSpeedApparent,
    double? windAngleApparent,
    double? windSpeedTrue,
    double? windAngleTrueWater,
    double? windAngleTrueGround,
    double? waterTemp,
    double? airTemp,
    double? pressure,
    double? humidity,
  }) {
    return EnvironmentData(
      depthBelowKeel: depthBelowKeel ?? this.depthBelowKeel,
      depthBelowTransducer: depthBelowTransducer ?? this.depthBelowTransducer,
      depthBelowSurface: depthBelowSurface ?? this.depthBelowSurface,
      windSpeedApparent: windSpeedApparent ?? this.windSpeedApparent,
      windAngleApparent: windAngleApparent ?? this.windAngleApparent,
      windSpeedTrue: windSpeedTrue ?? this.windSpeedTrue,
      windAngleTrueWater: windAngleTrueWater ?? this.windAngleTrueWater,
      windAngleTrueGround: windAngleTrueGround ?? this.windAngleTrueGround,
      waterTemp: waterTemp ?? this.waterTemp,
      airTemp: airTemp ?? this.airTemp,
      pressure: pressure ?? this.pressure,
      humidity: humidity ?? this.humidity,
    );
  }
}

// ── Propulsion ──

class PropulsionData {
  /// Keyed by engine id (e.g. "0", "1", "port", "starboard").
  final Map<String, EngineData> engines;

  const PropulsionData({this.engines = const {}});

  PropulsionData withEngine(String key, EngineData engine) {
    return PropulsionData(engines: {...engines, key: engine});
  }
}

class EngineData {
  final double? rpm;
  final double? temperature; // °C
  final double? oilPressure; // Pa
  final double? coolantTemp; // °C
  final double? exhaustTemp; // °C
  final double? fuelRate; // l/h

  const EngineData({
    this.rpm,
    this.temperature,
    this.oilPressure,
    this.coolantTemp,
    this.exhaustTemp,
    this.fuelRate,
  });

  EngineData copyWith({
    double? rpm,
    double? temperature,
    double? oilPressure,
    double? coolantTemp,
    double? exhaustTemp,
    double? fuelRate,
  }) {
    return EngineData(
      rpm: rpm ?? this.rpm,
      temperature: temperature ?? this.temperature,
      oilPressure: oilPressure ?? this.oilPressure,
      coolantTemp: coolantTemp ?? this.coolantTemp,
      exhaustTemp: exhaustTemp ?? this.exhaustTemp,
      fuelRate: fuelRate ?? this.fuelRate,
    );
  }
}

// ── Tanks ──

class TanksData {
  /// Keyed by tank id (e.g. "fuel.0", "freshWater.0", "wasteWater.0").
  final Map<String, TankData> tanks;

  const TanksData({this.tanks = const {}});

  TanksData withTank(String key, TankData tank) {
    return TanksData(tanks: {...tanks, key: tank});
  }
}

class TankData {
  final String type; // fuel, freshWater, wasteWater, etc.
  final double? currentLevel; // ratio 0-1
  final double? capacity; // m³

  const TankData({required this.type, this.currentLevel, this.capacity});

  TankData copyWith({double? currentLevel, double? capacity}) {
    return TankData(
      type: type,
      currentLevel: currentLevel ?? this.currentLevel,
      capacity: capacity ?? this.capacity,
    );
  }

  /// Level as a percentage 0-100.
  double? get levelPercent =>
      currentLevel != null ? (currentLevel! * 100) : null;
}

// ── Electrical ──

class ElectricalData {
  /// Keyed by battery id (e.g. "0", "1", "house", "starter").
  final Map<String, BatteryData> batteries;
  final Map<String, InverterData> inverters;
  final Map<String, ChargerData> chargers;

  const ElectricalData({
    this.batteries = const {},
    this.inverters = const {},
    this.chargers = const {},
  });

  ElectricalData withBattery(String key, BatteryData battery) {
    return ElectricalData(
      batteries: {...batteries, key: battery},
      inverters: inverters,
      chargers: chargers,
    );
  }

  ElectricalData withInverter(String key, InverterData inverter) {
    return ElectricalData(
      batteries: batteries,
      inverters: {...inverters, key: inverter},
      chargers: chargers,
    );
  }

  ElectricalData withCharger(String key, ChargerData charger) {
    return ElectricalData(
      batteries: batteries,
      inverters: inverters,
      chargers: {...chargers, key: charger},
    );
  }
}

class BatteryData {
  final double? voltage; // V
  final double? current; // A
  final double? stateOfCharge; // ratio 0-1
  final double? temperature; // °C

  const BatteryData({
    this.voltage,
    this.current,
    this.stateOfCharge,
    this.temperature,
  });

  BatteryData copyWith({
    double? voltage,
    double? current,
    double? stateOfCharge,
    double? temperature,
  }) {
    return BatteryData(
      voltage: voltage ?? this.voltage,
      current: current ?? this.current,
      stateOfCharge: stateOfCharge ?? this.stateOfCharge,
      temperature: temperature ?? this.temperature,
    );
  }

  /// SOC as percentage 0-100.
  double? get socPercent =>
      stateOfCharge != null ? (stateOfCharge! * 100) : null;
}

class InverterData {
  final double? dcVoltage;
  final double? dcCurrent;
  final double? acVoltage;
  final double? acCurrent;

  const InverterData({
    this.dcVoltage,
    this.dcCurrent,
    this.acVoltage,
    this.acCurrent,
  });

  InverterData copyWith({
    double? dcVoltage,
    double? dcCurrent,
    double? acVoltage,
    double? acCurrent,
  }) {
    return InverterData(
      dcVoltage: dcVoltage ?? this.dcVoltage,
      dcCurrent: dcCurrent ?? this.dcCurrent,
      acVoltage: acVoltage ?? this.acVoltage,
      acCurrent: acCurrent ?? this.acCurrent,
    );
  }
}

class ChargerData {
  final double? voltage;
  final double? current;
  final String? mode;

  const ChargerData({this.voltage, this.current, this.mode});

  ChargerData copyWith({double? voltage, double? current, String? mode}) {
    return ChargerData(
      voltage: voltage ?? this.voltage,
      current: current ?? this.current,
      mode: mode ?? this.mode,
    );
  }
}

// ── Notifications ──

class NotificationsData {
  final List<SignalKNotification> notifications;

  const NotificationsData({this.notifications = const []});
}

class SignalKNotification {
  final String path;
  final String? message;
  final String state; // normal, alert, warn, alarm, emergency
  final DateTime? timestamp;

  const SignalKNotification({
    required this.path,
    this.message,
    this.state = 'normal',
    this.timestamp,
  });
}

// ── AIS Vessel ──

class AisVesselData {
  final int mmsi;
  final String? name;
  final String? callsign;
  final LatLng? position;
  final double? sog; // knots
  final double? cog; // degrees
  final double? heading; // degrees
  final int? navStatus;
  final int? shipType;
  final int? dimBow;
  final int? dimStern;
  final int? dimPort;
  final int? dimStarboard;
  final DateTime lastSeen;

  const AisVesselData({
    required this.mmsi,
    this.name,
    this.callsign,
    this.position,
    this.sog,
    this.cog,
    this.heading,
    this.navStatus,
    this.shipType,
    this.dimBow,
    this.dimStern,
    this.dimPort,
    this.dimStarboard,
    required this.lastSeen,
  });

  AisVesselData copyWith({
    String? name,
    String? callsign,
    LatLng? position,
    double? sog,
    double? cog,
    double? heading,
    int? navStatus,
    int? shipType,
    int? dimBow,
    int? dimStern,
    int? dimPort,
    int? dimStarboard,
    DateTime? lastSeen,
  }) {
    return AisVesselData(
      mmsi: mmsi,
      name: name ?? this.name,
      callsign: callsign ?? this.callsign,
      position: position ?? this.position,
      sog: sog ?? this.sog,
      cog: cog ?? this.cog,
      heading: heading ?? this.heading,
      navStatus: navStatus ?? this.navStatus,
      shipType: shipType ?? this.shipType,
      dimBow: dimBow ?? this.dimBow,
      dimStern: dimStern ?? this.dimStern,
      dimPort: dimPort ?? this.dimPort,
      dimStarboard: dimStarboard ?? this.dimStarboard,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

// ── Aggregated vessel state ──

class SignalKVesselData {
  final NavigationData navigation;
  final EnvironmentData environment;
  final PropulsionData propulsion;
  final TanksData tanks;
  final ElectricalData electrical;
  final NotificationsData notifications;

  const SignalKVesselData({
    this.navigation = const NavigationData(),
    this.environment = const EnvironmentData(),
    this.propulsion = const PropulsionData(),
    this.tanks = const TanksData(),
    this.electrical = const ElectricalData(),
    this.notifications = const NotificationsData(),
  });

  SignalKVesselData copyWith({
    NavigationData? navigation,
    EnvironmentData? environment,
    PropulsionData? propulsion,
    TanksData? tanks,
    ElectricalData? electrical,
    NotificationsData? notifications,
  }) {
    return SignalKVesselData(
      navigation: navigation ?? this.navigation,
      environment: environment ?? this.environment,
      propulsion: propulsion ?? this.propulsion,
      tanks: tanks ?? this.tanks,
      electrical: electrical ?? this.electrical,
      notifications: notifications ?? this.notifications,
    );
  }
}
