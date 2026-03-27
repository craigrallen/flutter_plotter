import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/nmea/nmea_stream.dart';
import '../../core/signalk/signalk_discovery.dart';
import '../../core/signalk/signalk_source.dart';
import '../../data/providers/data_source_provider.dart';
import '../../data/providers/nmea_config_provider.dart';
import '../../data/providers/settings_provider.dart';
import '../../data/providers/signalk_provider.dart';
import 'nmea_debug_screen.dart';
import 'offline_tiles_screen.dart';

/// Settings screen with NMEA connection, alarms, units, and debug options.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _skHostController = TextEditingController();
  final _skPortController = TextEditingController();
  final _skTokenController = TextEditingController();
  bool _initialized = false;
  bool _scanning = false;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _skHostController.dispose();
    _skPortController.dispose();
    _skTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(nmeaConfigProvider);
    final connState = ref.watch(nmeaConnectionStateProvider);
    final settings = ref.watch(appSettingsProvider);
    final dataSource = ref.watch(dataSourceProvider);
    final skConnState = ref.watch(signalKConnectionStateProvider);

    // Initialize text fields from saved config (once)
    if (!_initialized) {
      _hostController.text = config.host;
      _portController.text = config.port.toString();
      _skHostController.text = dataSource.host;
      _skPortController.text =
          dataSource.isSignalK ? dataSource.port.toString() : '3000';
      _skTokenController.text = dataSource.token ?? '';
      _initialized = true;
    }

    final connectionState = connState.when(
      data: (s) => s,
      loading: () => NmeaConnectionState.disconnected,
      error: (_, _) => NmeaConnectionState.disconnected,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Data Source ──
          Text('Data Source',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          SegmentedButton<DataSourceType>(
            segments: const [
              ButtonSegment(
                value: DataSourceType.gpsOnly,
                label: Text('GPS'),
              ),
              ButtonSegment(
                value: DataSourceType.nmeaTcp,
                label: Text('NMEA'),
              ),
              ButtonSegment(
                value: DataSourceType.signalK,
                label: Text('Signal K'),
              ),
            ],
            selected: {
              dataSource.type == DataSourceType.nmeaUdp
                  ? DataSourceType.nmeaTcp
                  : dataSource.type,
            },
            onSelectionChanged: (selection) {
              ref.read(dataSourceProvider.notifier).update(
                    dataSource.copyWith(type: selection.first),
                  );
            },
          ),

          const Divider(height: 40),

          // ── Signal K section (only when Signal K selected) ──
          if (dataSource.isSignalK) ...[
            Text('Signal K Connection',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),

            _SignalKStatusIndicator(state: skConnState),
            const SizedBox(height: 16),

            TextField(
              controller: _skHostController,
              decoration: const InputDecoration(
                labelText: 'Signal K Host',
                hintText: '192.168.1.1',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _skPortController,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '3000',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _skTokenController,
              decoration: const InputDecoration(
                labelText: 'Token (optional)',
                hintText: 'Bearer token for authentication',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanning ? null : _scanNetwork,
                    icon: _scanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find),
                    label: Text(_scanning ? 'Scanning...' : 'Scan Network'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _toggleSignalK(skConnState),
                    icon: Icon(
                      skConnState == SignalKConnectionState.connected
                          ? Icons.link_off
                          : Icons.link,
                    ),
                    label: Text(
                      skConnState == SignalKConnectionState.connected
                          ? 'Disconnect'
                          : skConnState == SignalKConnectionState.connecting
                              ? 'Connecting...'
                              : 'Connect',
                    ),
                  ),
                ),
              ],
            ),

            const Divider(height: 40),
          ],

          // ── NMEA Connection (only when NMEA selected) ──
          if (dataSource.isNmea) ...[
            Text('NMEA Connection',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),

            _NmeaStatusIndicator(state: connectionState),
            const SizedBox(height: 16),

            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Host / IP Address',
                hintText: '192.168.1.1',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '10110',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),

            SegmentedButton<NmeaProtocol>(
              segments: const [
                ButtonSegment(value: NmeaProtocol.tcp, label: Text('TCP')),
                ButtonSegment(value: NmeaProtocol.udp, label: Text('UDP')),
              ],
              selected: {config.protocol},
              onSelectionChanged: (selection) {
                ref.read(nmeaConfigProvider.notifier).update(
                      config.copyWith(protocol: selection.first),
                    );
              },
            ),
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: () => _toggleConnection(connectionState, config),
              icon: Icon(
                connectionState == NmeaConnectionState.connected
                    ? Icons.link_off
                    : Icons.link,
              ),
              label: Text(
                connectionState == NmeaConnectionState.connected
                    ? 'Disconnect'
                    : connectionState == NmeaConnectionState.connecting ||
                            connectionState == NmeaConnectionState.reconnecting
                        ? 'Connecting...'
                        : 'Connect',
              ),
            ),

            const Divider(height: 40),
          ],

          // ── Units ──
          Text('Units', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          SegmentedButton<UnitSystem>(
            segments: const [
              ButtonSegment(value: UnitSystem.nautical, label: Text('Nautical')),
              ButtonSegment(value: UnitSystem.metric, label: Text('Metric')),
              ButtonSegment(value: UnitSystem.imperial, label: Text('Imperial')),
            ],
            selected: {settings.units},
            onSelectionChanged: (selection) {
              ref.read(appSettingsProvider.notifier).update(
                    settings.copyWith(units: selection.first),
                  );
            },
          ),

          const Divider(height: 40),

          // ── CPA Alarm ──
          Text('CPA Alarm', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          _SliderSetting(
            label: 'CPA Distance Threshold',
            value: settings.cpaAlarmDistanceNm,
            min: 0.1,
            max: 5.0,
            divisions: 49,
            format: (v) => '${v.toStringAsFixed(1)} nm',
            onChanged: (v) {
              ref.read(appSettingsProvider.notifier).update(
                    settings.copyWith(cpaAlarmDistanceNm: v),
                  );
            },
          ),
          const SizedBox(height: 8),

          _SliderSetting(
            label: 'TCPA Time Threshold',
            value: settings.cpaAlarmTimeMinutes,
            min: 1,
            max: 60,
            divisions: 59,
            format: (v) => '${v.toStringAsFixed(0)} min',
            onChanged: (v) {
              ref.read(appSettingsProvider.notifier).update(
                    settings.copyWith(cpaAlarmTimeMinutes: v),
                  );
            },
          ),

          const Divider(height: 40),

          // ── Display ──
          Text('Display', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          SwitchListTile(
            title: const Text('Night Mode'),
            subtitle: const Text('Red-tinted display for dark adaptation'),
            value: settings.nightMode,
            onChanged: (_) {
              ref.read(appSettingsProvider.notifier).toggleNightMode();
            },
          ),

          const Divider(height: 40),

          // ── Debug & Tools ──
          Text('Tools', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Offline Tiles'),
            subtitle: const Text('Download charts for offline use'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const OfflineTilesScreen()),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.terminal),
            title: const Text('NMEA Debug'),
            subtitle: const Text('View raw NMEA sentences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NmeaDebugScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _scanNetwork() async {
    setState(() => _scanning = true);
    try {
      final server = await SignalKDiscovery.discover();
      if (server != null && mounted) {
        _skHostController.text = server.host;
        _skPortController.text = server.port.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Found: ${server.name ?? server.host}:${server.port}')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Signal K server found')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _toggleSignalK(SignalKConnectionState connState) async {
    final skNotifier = ref.read(signalKProvider.notifier);

    if (connState == SignalKConnectionState.connected ||
        connState == SignalKConnectionState.connecting) {
      await skNotifier.disconnect();
      return;
    }

    final host = _skHostController.text.trim();
    final port = int.tryParse(_skPortController.text.trim()) ?? 3000;
    final token = _skTokenController.text.trim();

    // Save config
    await ref.read(dataSourceProvider.notifier).update(
          DataSourceConfig(
            type: DataSourceType.signalK,
            host: host,
            port: port,
            token: token.isEmpty ? null : token,
          ),
        );

    await skNotifier.connect(
      host: host,
      port: port,
      token: token.isEmpty ? null : token,
    );
  }

  Future<void> _toggleConnection(
    NmeaConnectionState connState,
    NmeaConfig config,
  ) async {
    final stream = ref.read(nmeaStreamProvider);

    if (connState == NmeaConnectionState.connected ||
        connState == NmeaConnectionState.connecting ||
        connState == NmeaConnectionState.reconnecting) {
      await stream.disconnect();
      return;
    }

    // Save config
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? config.port;
    final newConfig = config.copyWith(host: host, port: port);
    await ref.read(nmeaConfigProvider.notifier).update(newConfig);

    // Connect
    await stream.connect(
      host: newConfig.host,
      port: newConfig.port,
      protocol: newConfig.protocol,
    );

    // Activate NMEA processor
    ref.read(nmeaProcessorProvider);
  }
}

class _NmeaStatusIndicator extends StatelessWidget {
  final NmeaConnectionState state;

  const _NmeaStatusIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      NmeaConnectionState.disconnected => (Colors.grey, 'Disconnected'),
      NmeaConnectionState.connecting => (Colors.amber, 'Connecting...'),
      NmeaConnectionState.connected => (Colors.green, 'Connected'),
      NmeaConnectionState.reconnecting => (Colors.orange, 'Reconnecting...'),
    };

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

class _SignalKStatusIndicator extends StatelessWidget {
  final SignalKConnectionState state;

  const _SignalKStatusIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      SignalKConnectionState.disconnected => (Colors.grey, 'Disconnected'),
      SignalKConnectionState.connecting => (Colors.amber, 'Connecting...'),
      SignalKConnectionState.connected => (Colors.green, 'Connected'),
      SignalKConnectionState.error => (Colors.red, 'Error'),
    };

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

class _SliderSetting extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const _SliderSetting({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(format(value),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
