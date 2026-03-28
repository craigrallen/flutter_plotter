import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/floatilla/floatilla_service.dart';
import '../../data/providers/signalk_provider.dart';
import '../../data/models/signalk_state.dart';
import '../../core/signalk/signalk_models.dart';
import '../../core/signalk/signalk_source.dart';

class EngineDashboardScreen extends ConsumerStatefulWidget {
  const EngineDashboardScreen({super.key});

  @override
  ConsumerState<EngineDashboardScreen> createState() =>
      _EngineDashboardScreenState();
}

class _EngineDashboardScreenState extends ConsumerState<EngineDashboardScreen> {
  Timer? _cloudLogTimer;
  int _logCount = 0;
  bool _cloudLogging = false;

  @override
  void dispose() {
    _cloudLogTimer?.cancel();
    super.dispose();
  }

  void _toggleCloudLog(PropulsionData propulsion) {
    if (_cloudLogging) {
      _cloudLogTimer?.cancel();
      setState(() => _cloudLogging = false);
      return;
    }
    setState(() => _cloudLogging = true);
    _cloudLogTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _sendEngineLog(propulsion);
    });
  }

  Future<void> _sendEngineLog(PropulsionData propulsion) async {
    if (!FloatillaService.instance.isLoggedIn()) return;
    try {
      final engines = propulsion.engines.map((id, e) => MapEntry(id, {
            if (e.rpm != null) 'rpm': e.rpm,
            if (e.temperature != null) 'tempC': e.temperature! - 273.15,
            if (e.oilPressure != null) 'oilPressureKPa': e.oilPressure! / 1000,
            if (e.fuelRate != null) 'fuelRateLh': e.fuelRate! * 3600,
          }));
      await http.post(
        Uri.parse('${FloatillaService.instance.baseUrl}/logbook/entry'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${FloatillaService.instance.token}',
        },
        body: jsonEncode({
          'lat': 0,
          'lng': 0,
          'entryType': 'engine',
          'note': 'engine:${jsonEncode(engines)}',
        }),
      );
      if (mounted) setState(() => _logCount++);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final skState = ref.watch(signalKProvider);
    final propulsion = skState.ownVessel.propulsion;
    final electrical = skState.ownVessel.electrical;
    final environment = skState.ownVessel.environment;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Engine Dashboard'),
        actions: [
          if (FloatillaService.instance.isLoggedIn())
            IconButton(
              icon: Icon(
                _cloudLogging
                    ? Icons.cloud_upload
                    : Icons.cloud_upload_outlined,
                color: _cloudLogging ? Colors.blue : null,
              ),
              tooltip: _cloudLogging
                  ? 'Stop cloud logging ($_logCount entries)'
                  : 'Start cloud logging',
              onPressed: () => _toggleCloudLog(propulsion),
            ),
        ],
      ),
      body: skState.connectionState != SignalKConnectionState.connected
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.speed, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('No Signal K connection',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 6),
                  const Text(
                    'Connect to a Signal K server in Settings\nto see live engine data',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_cloudLogging)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_upload,
                              size: 16, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            'Logging to cloud — $_logCount entries this session',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),

                  // Engines
                  if (propulsion.engines.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No engine data from Signal K\n'
                          'Check Signal K paths: propulsion.*',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ...propulsion.engines.entries.map((e) =>
                        _EngineCard(id: e.key, data: e.value)),

                  const SizedBox(height: 16),

                  // Batteries
                  if (electrical.batteries.isNotEmpty) ...[
                    const Text('Batteries',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 8),
                    ...electrical.batteries.entries
                        .map((e) => _BatteryCard(id: e.key, data: e.value)),
                    const SizedBox(height: 16),
                  ],

                  // Environment
                  if (environment.waterTemp != null ||
                      environment.depthBelowKeel != null) ...[
                    const Text('Environment',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Wrap(
                          spacing: 20,
                          runSpacing: 12,
                          children: [
                            if (environment.depthBelowKeel != null)
                              _Gauge(
                                label: 'Depth (keel)',
                                value:
                                    '${environment.depthBelowKeel!.toStringAsFixed(1)} m',
                              ),
                            if (environment.waterTemp != null)
                              _Gauge(
                                label: 'Water temp',
                                value:
                                    '${(environment.waterTemp! - 273.15).toStringAsFixed(1)} °C',
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _EngineCard extends StatelessWidget {
  final String id;
  final EngineData data;

  const _EngineCard({required this.id, required this.data});

  @override
  Widget build(BuildContext context) {
    final tempC = data.temperature != null
        ? (data.temperature! - 273.15).toStringAsFixed(0)
        : null;
    final oilBar = data.oilPressure != null
        ? (data.oilPressure! / 100000).toStringAsFixed(2)
        : null;
    final fuelLh = data.fuelRate != null
        ? (data.fuelRate! * 3600).toStringAsFixed(1)
        : null;

    // Simple temp warning
    final tempWarn = data.temperature != null && data.temperature! > 373; // 100°C

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Engine: $id',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                if (tempWarn) ...[
                  const Spacer(),
                  const Icon(Icons.warning, color: Colors.orange, size: 18),
                  const SizedBox(width: 4),
                  const Text('High temp',
                      style: TextStyle(
                          color: Colors.orange, fontSize: 12)),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                if (data.rpm != null)
                  _Gauge(
                      label: 'RPM',
                      value: data.rpm!.toStringAsFixed(0)),
                if (tempC != null)
                  _Gauge(
                    label: 'Coolant',
                    value: '$tempC °C',
                    valueColor: tempWarn ? Colors.orange : null,
                  ),
                if (oilBar != null)
                  _Gauge(label: 'Oil pressure', value: '$oilBar bar'),
                if (fuelLh != null)
                  _Gauge(label: 'Fuel rate', value: '$fuelLh L/h'),
                if (data.exhaustTemp != null)
                  _Gauge(
                    label: 'Exhaust',
                    value:
                        '${(data.exhaustTemp! - 273.15).toStringAsFixed(0)} °C',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  final String id;
  final BatteryData data;

  const _BatteryCard({required this.id, required this.data});

  @override
  Widget build(BuildContext context) {
    final soc = data.stateOfCharge;
    final socPct = soc != null ? (soc * 100).toStringAsFixed(0) : null;
    final socColor = soc == null
        ? null
        : soc > 0.5
            ? Colors.green
            : soc > 0.3
                ? Colors.orange
                : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Battery: $id',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 8),
            if (soc != null) ...[
              LinearProgressIndicator(
                value: soc.clamp(0, 1).toDouble(),
                backgroundColor: Colors.grey.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation(socColor ?? Colors.blue),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                if (data.voltage != null)
                  _Gauge(
                      label: 'Voltage', value: '${data.voltage!.toStringAsFixed(1)} V'),
                if (data.current != null)
                  _Gauge(
                    label: 'Current',
                    value:
                        '${data.current! > 0 ? '+' : ''}${data.current!.toStringAsFixed(1)} A',
                    valueColor: data.current! > 0 ? Colors.green : null,
                  ),
                if (socPct != null)
                  _Gauge(
                    label: 'State of charge',
                    value: '$socPct%',
                    valueColor: socColor,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Gauge extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _Gauge(
      {required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
