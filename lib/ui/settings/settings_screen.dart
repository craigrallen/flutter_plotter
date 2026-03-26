import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/nmea/nmea_stream.dart';
import '../../data/providers/nmea_config_provider.dart';

/// Settings screen with NMEA connection configuration.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(nmeaConfigProvider);
    final connState = ref.watch(nmeaConnectionStateProvider);

    // Initialize text fields from saved config (once)
    if (!_initialized) {
      _hostController.text = config.host;
      _portController.text = config.port.toString();
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
          Text('NMEA Connection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          // Connection status
          _StatusIndicator(state: connectionState),
          const SizedBox(height: 16),

          // Host
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

          // Port
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

          // Protocol toggle
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

          // Connect / Disconnect button
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
        ],
      ),
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

class _StatusIndicator extends StatelessWidget {
  final NmeaConnectionState state;

  const _StatusIndicator({required this.state});

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
