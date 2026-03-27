import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/signalk/signalk_models.dart';
import '../../core/signalk/signalk_source.dart';
import '../../data/providers/settings_provider.dart';
import '../../data/providers/signalk_provider.dart';
import '../instruments/instrument_tile.dart';

/// Dashboard screen showing live Signal K data in categorised tiles.
class SignalKDashboard extends ConsumerStatefulWidget {
  const SignalKDashboard({super.key});

  @override
  ConsumerState<SignalKDashboard> createState() => _SignalKDashboardState();
}

class _SignalKDashboardState extends ConsumerState<SignalKDashboard> {
  bool _showRawDeltas = false;
  final List<String> _rawDeltas = [];
  static const _maxRawDeltas = 200;

  String _formatTime(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final skState = ref.watch(signalKProvider);
    final settings = ref.watch(appSettingsProvider);
    final connState = skState.connectionState;

    // Track raw deltas by watching lastUpdateAt changes
    if (_showRawDeltas) {
      ref.listen(
        signalKProvider.select((s) => s.lastUpdateAt),
        (prev, next) {
          if (next != null && next != prev) {
            setState(() {
              _rawDeltas.insert(0, 'Delta at ${_formatTime(next)}');
              if (_rawDeltas.length > _maxRawDeltas) {
                _rawDeltas.removeRange(_maxRawDeltas, _rawDeltas.length);
              }
            });
          }
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Signal K'),
        actions: [
          IconButton(
            icon: Icon(_showRawDeltas ? Icons.list : Icons.code),
            tooltip: _showRawDeltas ? 'Show tiles' : 'Show raw deltas',
            onPressed: () => setState(() {
              _showRawDeltas = !_showRawDeltas;
              if (!_showRawDeltas) _rawDeltas.clear();
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          _ConnectionBar(state: connState, lastUpdate: skState.lastUpdateAt),
          Expanded(
            child: _showRawDeltas
                ? _RawDeltaView(deltas: _rawDeltas)
                : _TileView(
                    vessel: skState.ownVessel,
                    notifications: skState.notifications,
                    settings: settings,
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Connection status bar ──

class _ConnectionBar extends StatelessWidget {
  final SignalKConnectionState state;
  final DateTime? lastUpdate;

  const _ConnectionBar({required this.state, this.lastUpdate});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      SignalKConnectionState.disconnected => (Colors.grey, 'Disconnected'),
      SignalKConnectionState.connecting => (Colors.amber, 'Connecting...'),
      SignalKConnectionState.connected => (Colors.green, 'Connected'),
      SignalKConnectionState.error => (Colors.red, 'Error'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withValues(alpha: 0.15),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          if (lastUpdate != null)
            Text(
              'Last: ${_formatTime(lastUpdate!)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }
}

// ── Tile view ──

class _TileView extends StatelessWidget {
  final SignalKVesselData vessel;
  final List<SignalKNotification> notifications;
  final AppSettings settings;

  const _TileView({
    required this.vessel,
    required this.notifications,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildNavigationSection(),
        _buildEnvironmentSection(),
        if (vessel.propulsion.engines.isNotEmpty) _buildPropulsionSection(),
        if (vessel.tanks.tanks.isNotEmpty) _buildTanksSection(),
        if (vessel.electrical.batteries.isNotEmpty) _buildElectricalSection(),
        if (notifications.isNotEmpty) _buildNotificationsSection(context),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _tileRow(List<Widget> tiles) {
    return Wrap(spacing: 8, runSpacing: 8, children: tiles);
  }

  Widget _tile(String label, String value, String unit) {
    return SizedBox(
      width: 100,
      child: InstrumentTile(label: label, value: value, unit: unit),
    );
  }

  // ── Navigation ──

  Widget _buildNavigationSection() {
    final nav = vessel.navigation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('NAVIGATION'),
        _tileRow([
          _tile('SOG', _fmtSpeed(nav.sog), _speedUnit()),
          _tile('COG', _fmtDeg(nav.cog), 'true'),
          _tile('HDG', _fmtDeg(nav.headingTrue), 'true'),
          if (nav.headingMagnetic != null)
            _tile('HDG M', _fmtDeg(nav.headingMagnetic), 'mag'),
          _tile(
            'POS',
            nav.position != null
                ? nav.position!.latitude.toStringAsFixed(4)
                : '--',
            nav.position != null
                ? nav.position!.longitude.toStringAsFixed(4)
                : '',
          ),
          if (nav.rateOfTurn != null)
            _tile('ROT', nav.rateOfTurn!.toStringAsFixed(1), 'deg/min'),
        ]),
      ],
    );
  }

  // ── Environment ──

  Widget _buildEnvironmentSection() {
    final env = vessel.environment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('ENVIRONMENT'),
        _tileRow([
          _tile('DEPTH', _fmtDepth(env.depth), _depthUnit()),
          _tile('AWS', _fmtSpeed(env.windSpeedApparent), _speedUnit()),
          _tile('AWA', _fmtDeg(env.windAngleApparent), 'apparent'),
          _tile('TWS', _fmtSpeed(env.windSpeedTrue), _speedUnit()),
          _tile('TWA', _fmtDeg(env.windAngleTrueWater), 'true'),
          if (env.waterTemp != null)
            _tile('WATER', env.waterTemp!.toStringAsFixed(1), 'C'),
          if (env.airTemp != null)
            _tile('AIR', env.airTemp!.toStringAsFixed(1), 'C'),
          if (env.pressure != null)
            _tile('BARO', env.pressure!.toStringAsFixed(0), 'hPa'),
          if (env.humidity != null)
            _tile(
              'HUMID',
              (env.humidity! * 100).toStringAsFixed(0),
              '%',
            ),
        ]),
      ],
    );
  }

  // ── Propulsion ──

  Widget _buildPropulsionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('PROPULSION'),
        _tileRow([
          for (final entry in vessel.propulsion.engines.entries) ...[
            _tile(
              'RPM ${entry.key}',
              entry.value.rpm?.toStringAsFixed(0) ?? '--',
              'RPM',
            ),
            if (entry.value.temperature != null)
              _tile(
                'TEMP ${entry.key}',
                entry.value.temperature!.toStringAsFixed(0),
                'C',
              ),
            if (entry.value.oilPressure != null)
              _tile(
                'OIL ${entry.key}',
                (entry.value.oilPressure! / 1000).toStringAsFixed(0),
                'kPa',
              ),
            if (entry.value.coolantTemp != null)
              _tile(
                'COOL ${entry.key}',
                entry.value.coolantTemp!.toStringAsFixed(0),
                'C',
              ),
          ],
        ]),
      ],
    );
  }

  // ── Tanks ──

  Widget _buildTanksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('TANKS'),
        _tileRow([
          for (final entry in vessel.tanks.tanks.entries)
            _tile(
              entry.value.type.toUpperCase(),
              entry.value.levelPercent?.toStringAsFixed(0) ?? '--',
              '%',
            ),
        ]),
      ],
    );
  }

  // ── Electrical ──

  Widget _buildElectricalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('ELECTRICAL'),
        _tileRow([
          for (final entry in vessel.electrical.batteries.entries) ...[
            _tile(
              'BAT ${entry.key}',
              entry.value.voltage?.toStringAsFixed(1) ?? '--',
              'V',
            ),
            if (entry.value.current != null)
              _tile(
                'AMP ${entry.key}',
                entry.value.current!.toStringAsFixed(1),
                'A',
              ),
            if (entry.value.socPercent != null)
              _tile(
                'SOC ${entry.key}',
                entry.value.socPercent!.toStringAsFixed(0),
                '%',
              ),
          ],
        ]),
      ],
    );
  }

  // ── Notifications ──

  Widget _buildNotificationsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('NOTIFICATIONS'),
        ...notifications.map((n) => Card(
              color: _notifColor(n.state),
              child: ListTile(
                dense: true,
                leading: Icon(_notifIcon(n.state)),
                title: Text(n.message ?? n.path),
                subtitle: Text(n.state),
              ),
            )),
      ],
    );
  }

  Color _notifColor(String state) {
    switch (state) {
      case 'alarm':
      case 'emergency':
        return Colors.red.shade100;
      case 'warn':
        return Colors.orange.shade100;
      case 'alert':
        return Colors.amber.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  IconData _notifIcon(String state) {
    switch (state) {
      case 'alarm':
      case 'emergency':
        return Icons.error;
      case 'warn':
        return Icons.warning;
      case 'alert':
        return Icons.info;
      default:
        return Icons.notifications_none;
    }
  }

  // ── Formatting helpers ──

  String _fmtSpeed(double? knots) {
    if (knots == null) return '--';
    switch (settings.units) {
      case UnitSystem.nautical:
        return knots.toStringAsFixed(1);
      case UnitSystem.metric:
        return (knots * 1.852).toStringAsFixed(1);
      case UnitSystem.imperial:
        return (knots * 1.15078).toStringAsFixed(1);
    }
  }

  String _speedUnit() {
    switch (settings.units) {
      case UnitSystem.nautical:
        return 'kn';
      case UnitSystem.metric:
        return 'km/h';
      case UnitSystem.imperial:
        return 'mph';
    }
  }

  String _fmtDeg(double? deg) {
    if (deg == null) return '--';
    return '${deg.toStringAsFixed(0)}°';
  }

  String _fmtDepth(double? m) {
    if (m == null) return '--';
    switch (settings.units) {
      case UnitSystem.nautical:
      case UnitSystem.metric:
        return m.toStringAsFixed(1);
      case UnitSystem.imperial:
        return (m * 3.28084).toStringAsFixed(1);
    }
  }

  String _depthUnit() {
    switch (settings.units) {
      case UnitSystem.nautical:
      case UnitSystem.metric:
        return 'm';
      case UnitSystem.imperial:
        return 'ft';
    }
  }
}

// ── Raw delta view ──

class _RawDeltaView extends StatelessWidget {
  final List<String> deltas;

  const _RawDeltaView({required this.deltas});

  @override
  Widget build(BuildContext context) {
    if (deltas.isEmpty) {
      return const Center(
        child: Text('Waiting for deltas...', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: deltas.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          deltas[i],
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

