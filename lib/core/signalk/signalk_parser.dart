import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'signalk_models.dart';

/// Unit conversion constants.
const double _msToKnots = 1.94384;
const double _radToDeg = 180.0 / pi;
const double _kelvinOffset = 273.15;

/// Result of parsing a single Signal K delta message.
class ParsedDelta {
  final bool isSelf;
  final int? mmsi; // non-null for other vessels

  // Own vessel updates (only populated when isSelf == true)
  final NavigationData? navigation;
  final EnvironmentData? environment;
  final PropulsionData? propulsion;
  final TanksData? tanks;
  final ElectricalData? electrical;
  final NotificationsData? notifications;

  // AIS vessel update (only populated when isSelf == false)
  final AisVesselData? aisVessel;

  const ParsedDelta({
    required this.isSelf,
    this.mmsi,
    this.navigation,
    this.environment,
    this.propulsion,
    this.tanks,
    this.electrical,
    this.notifications,
    this.aisVessel,
  });
}

/// Parses Signal K delta-format JSON into structured [ParsedDelta] objects.
///
/// Handles ALL path prefixes: navigation, environment, propulsion, tanks,
/// electrical, and notifications. Performs unit conversions from SI to
/// display units (m/s→kn, rad→deg, K→°C).
class SignalKParser {
  /// The self context identifier from the server hello message.
  String? selfContext;

  /// Parse a raw JSON string into a [ParsedDelta], or null if not a delta.
  ParsedDelta? parse(String raw) {
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    // Handle hello message to capture self context.
    if (msg.containsKey('self')) {
      selfContext = msg['self'] as String?;
    }

    final updates = msg['updates'] as List<dynamic>?;
    if (updates == null) return null;

    final context = msg['context'] as String?;
    final isSelf = _isSelfContext(context);

    if (isSelf) {
      return _parseOwnVessel(updates);
    } else {
      final mmsi = extractMmsi(context ?? '');
      return _parseOtherVessel(updates, mmsi, context ?? '');
    }
  }

  bool _isSelfContext(String? context) {
    if (context == null || context.isEmpty || context == 'vessels.self') {
      return true;
    }
    if (selfContext != null && context == selfContext) return true;
    return false;
  }

  ParsedDelta _parseOwnVessel(List<dynamic> updates) {
    NavigationData? nav;
    EnvironmentData? env;
    PropulsionData? prop;
    TanksData? tankData;
    ElectricalData? elec;
    List<SignalKNotification>? notifs;

    for (final update in updates) {
      final values =
          (update as Map<String, dynamic>)['values'] as List<dynamic>?;
      if (values == null) continue;

      for (final v in values) {
        final entry = v as Map<String, dynamic>;
        final path = entry['path'] as String?;
        final value = entry['value'];
        if (path == null) continue;

        if (path.startsWith('navigation.')) {
          nav = _mergeNavigation(nav, path, value);
        } else if (path.startsWith('environment.')) {
          env = _mergeEnvironment(env, path, value);
        } else if (path.startsWith('propulsion.')) {
          prop = _mergePropulsion(prop, path, value);
        } else if (path.startsWith('tanks.')) {
          tankData = _mergeTanks(tankData, path, value);
        } else if (path.startsWith('electrical.')) {
          elec = _mergeElectrical(elec, path, value);
        } else if (path.startsWith('notifications.')) {
          notifs ??= [];
          final n = _parseNotification(path, value);
          if (n != null) notifs.add(n);
        }
      }
    }

    return ParsedDelta(
      isSelf: true,
      navigation: nav,
      environment: env,
      propulsion: prop,
      tanks: tankData,
      electrical: elec,
      notifications:
          notifs != null ? NotificationsData(notifications: notifs) : null,
    );
  }

  ParsedDelta _parseOtherVessel(
      List<dynamic> updates, int? mmsi, String context) {
    if (mmsi == null) {
      return const ParsedDelta(isSelf: false);
    }

    LatLng? position;
    double? sog, cog, heading;
    String? name, callsign;
    int? navStatus, shipType;
    int? dimBow, dimStern, dimPort, dimStarboard;

    for (final update in updates) {
      final values =
          (update as Map<String, dynamic>)['values'] as List<dynamic>?;
      if (values == null) continue;

      for (final v in values) {
        final entry = v as Map<String, dynamic>;
        final path = entry['path'] as String?;
        final value = entry['value'];
        if (path == null) continue;

        switch (path) {
          case 'navigation.position':
            if (value is Map<String, dynamic>) {
              final lat = (value['latitude'] as num?)?.toDouble();
              final lon = (value['longitude'] as num?)?.toDouble();
              if (lat != null && lon != null) position = LatLng(lat, lon);
            }
          case 'navigation.speedOverGround':
            if (value is num) sog = value.toDouble() * _msToKnots;
          case 'navigation.courseOverGroundTrue':
            if (value is num) cog = value.toDouble() * _radToDeg;
          case 'navigation.headingTrue':
            if (value is num) heading = value.toDouble() * _radToDeg;
          case 'name':
            if (value is String) name = value;
          case 'communication.callsignVhf':
            if (value is String) callsign = value;
          case 'navigation.state':
            // Map string nav state to AIS numeric status
            navStatus = _parseNavState(value);
          case 'design.aisShipType':
            if (value is Map<String, dynamic>) {
              shipType = (value['id'] as num?)?.toInt();
            } else if (value is num) {
              shipType = value.toInt();
            }
          case 'design.length':
            if (value is Map<String, dynamic>) {
              final overall = value['overall'] as num?;
              if (overall != null) {
                dimBow = (overall.toDouble() * 0.7).round();
                dimStern = (overall.toDouble() * 0.3).round();
              }
            }
          case 'design.beam':
            if (value is num) {
              dimPort = (value.toDouble() / 2).round();
              dimStarboard = (value.toDouble() / 2).round();
            }
        }
      }
    }

    return ParsedDelta(
      isSelf: false,
      mmsi: mmsi,
      aisVessel: AisVesselData(
        mmsi: mmsi,
        name: name,
        callsign: callsign,
        position: position,
        sog: sog,
        cog: cog,
        heading: heading,
        navStatus: navStatus,
        shipType: shipType,
        dimBow: dimBow,
        dimStern: dimStern,
        dimPort: dimPort,
        dimStarboard: dimStarboard,
        lastSeen: DateTime.now(),
      ),
    );
  }

  // ── Navigation paths ──

  NavigationData? _mergeNavigation(
      NavigationData? prev, String path, dynamic value) {
    final n = prev ?? const NavigationData();
    switch (path) {
      case 'navigation.position':
        if (value is Map<String, dynamic>) {
          final lat = (value['latitude'] as num?)?.toDouble();
          final lon = (value['longitude'] as num?)?.toDouble();
          if (lat != null && lon != null) {
            return n.copyWith(position: LatLng(lat, lon));
          }
        }
      case 'navigation.speedOverGround':
        if (value is num) return n.copyWith(sog: value.toDouble() * _msToKnots);
      case 'navigation.courseOverGroundTrue':
        if (value is num) return n.copyWith(cog: value.toDouble() * _radToDeg);
      case 'navigation.headingTrue':
        if (value is num) {
          return n.copyWith(headingTrue: value.toDouble() * _radToDeg);
        }
      case 'navigation.headingMagnetic':
        if (value is num) {
          return n.copyWith(headingMagnetic: value.toDouble() * _radToDeg);
        }
      case 'navigation.rateOfTurn':
        if (value is num) {
          return n.copyWith(rateOfTurn: value.toDouble() * _radToDeg);
        }
      case 'navigation.leewayAngle':
        if (value is num) {
          return n.copyWith(leewayAngle: value.toDouble() * _radToDeg);
        }
    }
    return prev;
  }

  // ── Environment paths ──

  EnvironmentData? _mergeEnvironment(
      EnvironmentData? prev, String path, dynamic value) {
    if (value is! num) return prev;
    final e = prev ?? const EnvironmentData();
    final v = value.toDouble();

    switch (path) {
      case 'environment.depth.belowKeel':
        return e.copyWith(depthBelowKeel: v);
      case 'environment.depth.belowTransducer':
        return e.copyWith(depthBelowTransducer: v);
      case 'environment.depth.belowSurface':
        return e.copyWith(depthBelowSurface: v);
      case 'environment.wind.speedApparent':
        return e.copyWith(windSpeedApparent: v * _msToKnots);
      case 'environment.wind.angleApparent':
        return e.copyWith(windAngleApparent: v * _radToDeg);
      case 'environment.wind.speedTrue':
        return e.copyWith(windSpeedTrue: v * _msToKnots);
      case 'environment.wind.angleTrueWater':
        return e.copyWith(windAngleTrueWater: v * _radToDeg);
      case 'environment.wind.angleTrueGround':
        return e.copyWith(windAngleTrueGround: v * _radToDeg);
      case 'environment.water.temperature':
        return e.copyWith(waterTemp: v - _kelvinOffset);
      case 'environment.outside.temperature':
        return e.copyWith(airTemp: v - _kelvinOffset);
      case 'environment.outside.pressure':
        return e.copyWith(pressure: v / 100); // Pa → hPa
      case 'environment.outside.humidity':
        return e.copyWith(humidity: v);
    }
    return prev;
  }

  // ── Propulsion paths ──
  // Pattern: propulsion.<engineId>.<property>

  PropulsionData? _mergePropulsion(
      PropulsionData? prev, String path, dynamic value) {
    final parts = path.split('.');
    if (parts.length < 3) return prev;
    // parts[0] = 'propulsion', parts[1] = engineId, parts[2+] = property
    final engineId = parts[1];
    final prop = parts.sublist(2).join('.');

    final p = prev ?? const PropulsionData();
    final engine = p.engines[engineId] ?? const EngineData();

    EngineData? updated;
    if (value is num) {
      final v = value.toDouble();
      switch (prop) {
        case 'revolutions':
          updated = engine.copyWith(rpm: v * 60); // rev/s → RPM
        case 'temperature':
          updated = engine.copyWith(temperature: v - _kelvinOffset);
        case 'oilPressure':
          updated = engine.copyWith(oilPressure: v);
        case 'coolantTemperature':
          updated = engine.copyWith(coolantTemp: v - _kelvinOffset);
        case 'exhaustTemperature':
          updated = engine.copyWith(exhaustTemp: v - _kelvinOffset);
        case 'fuel.rate':
          updated = engine.copyWith(fuelRate: v * 3600); // m³/s → l/h approx
      }
    }

    if (updated != null) return p.withEngine(engineId, updated);
    return prev;
  }

  // ── Tanks paths ──
  // Pattern: tanks.<type>.<tankId>.<property>

  TanksData? _mergeTanks(TanksData? prev, String path, dynamic value) {
    final parts = path.split('.');
    if (parts.length < 4) return prev;
    // parts[0] = 'tanks', parts[1] = type, parts[2] = tankId, parts[3+] = property
    final type = parts[1];
    final tankId = parts[2];
    final prop = parts.sublist(3).join('.');
    final key = '$type.$tankId';

    final t = prev ?? const TanksData();
    final tank = t.tanks[key] ?? TankData(type: type);

    TankData? updated;
    if (value is num) {
      switch (prop) {
        case 'currentLevel':
          updated = tank.copyWith(currentLevel: value.toDouble());
        case 'capacity':
          updated = tank.copyWith(capacity: value.toDouble());
      }
    }

    if (updated != null) return t.withTank(key, updated);
    return prev;
  }

  // ── Electrical paths ──
  // Pattern: electrical.batteries.<id>.<property>
  //          electrical.inverters.<id>.<property>
  //          electrical.chargers.<id>.<property>

  ElectricalData? _mergeElectrical(
      ElectricalData? prev, String path, dynamic value) {
    final parts = path.split('.');
    if (parts.length < 4) return prev;
    // parts[0] = 'electrical', parts[1] = category, parts[2] = id, parts[3+] = property
    final category = parts[1];
    final id = parts[2];
    final prop = parts.sublist(3).join('.');

    final el = prev ?? const ElectricalData();

    if (value is! num) return prev;
    final v = value.toDouble();

    switch (category) {
      case 'batteries':
        final bat = el.batteries[id] ?? const BatteryData();
        BatteryData? updated;
        switch (prop) {
          case 'voltage':
            updated = bat.copyWith(voltage: v);
          case 'current':
            updated = bat.copyWith(current: v);
          case 'capacity.stateOfCharge':
            updated = bat.copyWith(stateOfCharge: v);
          case 'temperature':
            updated = bat.copyWith(temperature: v - _kelvinOffset);
        }
        if (updated != null) return el.withBattery(id, updated);

      case 'inverters':
        final inv = el.inverters[id] ?? const InverterData();
        InverterData? updated;
        switch (prop) {
          case 'dc.voltage':
            updated = inv.copyWith(dcVoltage: v);
          case 'dc.current':
            updated = inv.copyWith(dcCurrent: v);
          case 'ac.voltage':
            updated = inv.copyWith(acVoltage: v);
          case 'ac.current':
            updated = inv.copyWith(acCurrent: v);
        }
        if (updated != null) return el.withInverter(id, updated);

      case 'chargers':
        final ch = el.chargers[id] ?? const ChargerData();
        ChargerData? updated;
        switch (prop) {
          case 'voltage':
            updated = ch.copyWith(voltage: v);
          case 'current':
            updated = ch.copyWith(current: v);
        }
        if (updated != null) return el.withCharger(id, updated);
    }

    return prev;
  }

  // ── Notifications ──

  SignalKNotification? _parseNotification(String path, dynamic value) {
    if (value is Map<String, dynamic>) {
      return SignalKNotification(
        path: path.replaceFirst('notifications.', ''),
        message: value['message'] as String?,
        state: (value['state'] as String?) ?? 'normal',
        timestamp: value['timestamp'] != null
            ? DateTime.tryParse(value['timestamp'] as String)
            : null,
      );
    }
    return null;
  }

  // ── Helpers ──

  int? _parseNavState(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) {
      switch (value) {
        case 'motoring':
          return 0;
        case 'anchored':
          return 1;
        case 'not under command':
          return 2;
        case 'restricted maneuverability':
          return 3;
        case 'sailing':
          return 8;
        default:
          return 15; // undefined
      }
    }
    return null;
  }

  /// Extract MMSI from a Signal K vessel context like
  /// "vessels.urn:mrn:imo:mmsi:123456789".
  static int? extractMmsi(String context) {
    final match = RegExp(r'mmsi:(\d+)').firstMatch(context);
    if (match != null) return int.tryParse(match.group(1)!);
    // Fallback: try the last segment after the last dot/colon
    final parts = context.split(RegExp(r'[.:]'));
    for (final part in parts.reversed) {
      final n = int.tryParse(part);
      if (n != null && part.length >= 9) return n;
    }
    return null;
  }
}
