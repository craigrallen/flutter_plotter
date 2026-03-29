import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/floatilla/floatilla_service.dart';
import '../../data/models/signalk_state.dart';
import '../../core/signalk/signalk_models.dart';
import '../../core/signalk/signalk_source.dart';
import '../../data/providers/signalk_provider.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

String _tankLabel(String key) {
  switch (key) {
    case 'fuel.0':
      return 'Fuel';
    case 'fuel.1':
      return 'Fuel (2)';
    case 'fuel.port':
      return 'Fuel Port';
    case 'fuel.starboard':
      return 'Fuel Starboard';
    case 'freshWater.0':
      return 'Fresh Water';
    case 'freshWater.1':
      return 'Fresh Water (2)';
    case 'blackWater.0':
      return 'Black Water';
    case 'wasteWater.0':
      return 'Waste Water';
    case 'liveWell.0':
      return 'Live Well';
    case 'lubrication.0':
      return 'Lube Oil';
    default:
      final parts = key.split('.');
      final type = parts[0]
          .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[0]}')
          .trim();
      final idx = parts.length > 1 ? ' ${parts[1]}' : '';
      return '${type[0].toUpperCase()}${type.substring(1)}$idx';
  }
}

bool _isFuelTank(String key) => key.startsWith('fuel');

Color _levelColor(double pct) {
  if (pct > 50) return Colors.green;
  if (pct > 20) return Colors.orange;
  return Colors.red;
}

// ── Persisted tank config ─────────────────────────────────────────────────────

class _TankConfig {
  final String key;
  String customName;
  double? capacityLitres; // user-configured capacity
  double? manualLevel; // ratio 0-1
  double? alertThresholdPct; // alert below this %

  _TankConfig({
    required this.key,
    required this.customName,
    this.capacityLitres,
    this.manualLevel,
    this.alertThresholdPct,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'customName': customName,
        if (capacityLitres != null) 'capacityLitres': capacityLitres,
        if (manualLevel != null) 'manualLevel': manualLevel,
        if (alertThresholdPct != null) 'alertThresholdPct': alertThresholdPct,
      };

  factory _TankConfig.fromJson(Map<String, dynamic> j) => _TankConfig(
        key: j['key'] as String,
        customName: j['customName'] as String,
        capacityLitres: (j['capacityLitres'] as num?)?.toDouble(),
        manualLevel: (j['manualLevel'] as num?)?.toDouble(),
        alertThresholdPct: (j['alertThresholdPct'] as num?)?.toDouble(),
      );
}

// ── Provider ──────────────────────────────────────────────────────────────────

final _tankConfigsProvider =
    StateNotifierProvider<_TankConfigNotifier, Map<String, _TankConfig>>(
        (_) => _TankConfigNotifier());

class _TankConfigNotifier extends StateNotifier<Map<String, _TankConfig>> {
  static const _prefsKey = 'floatilla_tank_configs';

  _TankConfigNotifier() : super({}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final map = <String, _TankConfig>{};
      for (final item in list) {
        final cfg = _TankConfig.fromJson(item as Map<String, dynamic>);
        map[cfg.key] = cfg;
      }
      state = map;
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(state.values.map((c) => c.toJson()).toList()));
  }

  void upsert(_TankConfig cfg) {
    state = {...state, cfg.key: cfg};
    _save();
  }

  void setManualLevel(String key, double level) {
    final existing = state[key] ??
        _TankConfig(key: key, customName: _tankLabel(key));
    upsert(_TankConfig(
      key: key,
      customName: existing.customName,
      capacityLitres: existing.capacityLitres,
      manualLevel: level,
      alertThresholdPct: existing.alertThresholdPct,
    ));
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class TankMonitorScreen extends ConsumerWidget {
  const TankMonitorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skState = ref.watch(signalKProvider);
    final configs = ref.watch(_tankConfigsProvider);
    final connected =
        skState.connectionState == SignalKConnectionState.connected;

    // Merge Signal K tanks with any manual configs
    final skTanks = skState.ownVessel.tanks.tanks;

    // Build display list: all SK tanks + any manually configured tanks
    final allKeys = <String>{...skTanks.keys, ...configs.keys};

    // Compute effective level for each tank
    double? _effectiveLevel(String key) {
      if (connected && skTanks.containsKey(key)) {
        return skTanks[key]!.currentLevel;
      }
      return configs[key]?.manualLevel;
    }

    // Collect fuel tanks for aggregate stats
    final fuelKeys = allKeys.where(_isFuelTank).toList();
    final fuelLevels = fuelKeys
        .map((k) => _effectiveLevel(k))
        .whereType<double>()
        .toList();
    final fuelCapacities = fuelKeys.map((k) {
      final cfgCap = configs[k]?.capacityLitres;
      final skCap = skTanks[k]?.capacity; // m³
      return cfgCap ?? (skCap != null ? skCap * 1000 : null);
    }).toList();

    double? totalFuelLitres;
    double? totalFuelCapLitres;
    if (fuelLevels.isNotEmpty) {
      double sumL = 0;
      double sumCap = 0;
      bool hasCap = false;
      for (int i = 0; i < fuelKeys.length; i++) {
        final level = _effectiveLevel(fuelKeys[i]);
        if (level == null) continue;
        final cap = fuelCapacities[i];
        if (cap != null) {
          sumL += level * cap;
          sumCap += cap;
          hasCap = true;
        }
      }
      if (hasCap) {
        totalFuelLitres = sumL;
        totalFuelCapLitres = sumCap;
      }
    }

    // Estimate range from FloatillaService fuel burn rate
    double? estimatedRangeNm;
    // Fuel burn rate in L/h (from engine data if available)
    double? fuelBurnRateLh;
    for (final eng in skState.ownVessel.propulsion.engines.values) {
      if (eng.fuelRate != null) {
        fuelBurnRateLh = (fuelBurnRateLh ?? 0) + eng.fuelRate! * 3600;
      }
    }
    final sog = skState.ownVessel.navigation.sog;
    if (totalFuelLitres != null &&
        fuelBurnRateLh != null &&
        fuelBurnRateLh > 0 &&
        sog != null &&
        sog > 0) {
      final hoursRemaining = totalFuelLitres / fuelBurnRateLh;
      estimatedRangeNm = hoursRemaining * sog;
    }

    // Check alerts
    final alertKeys = <String>[];
    for (final key in allKeys) {
      final threshold = configs[key]?.alertThresholdPct;
      if (threshold == null) continue;
      final level = _effectiveLevel(key);
      if (level != null && level * 100 < threshold) {
        alertKeys.add(key);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tank Monitor'),
        actions: [
          if (!connected)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Chip(
                label: const Text('Offline'),
                backgroundColor:
                    Theme.of(context).colorScheme.errorContainer,
                labelStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Aggregate fuel banner
          if (totalFuelLitres != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.local_gas_station,
                        size: 36,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total Fuel',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            totalFuelCapLitres != null
                                ? '${totalFuelLitres.toStringAsFixed(0)} / ${totalFuelCapLitres.toStringAsFixed(0)} L'
                                : '${totalFuelLitres.toStringAsFixed(0)} L',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          if (estimatedRangeNm != null)
                            Text(
                              'Est. range: ${estimatedRangeNm.toStringAsFixed(0)} nm',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.green),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Alerts banner
          if (alertKeys.isNotEmpty)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Low level alert: ${alertKeys.map((k) => configs[k]?.customName ?? _tankLabel(k)).join(', ')}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 8),

          if (allKeys.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                    'No tanks detected. Connect to Signal K or add tanks manually.'),
              ),
            ),

          // Tank cards grid
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.75,
                ),
                itemCount: allKeys.length,
                itemBuilder: (context, i) {
                  final key = allKeys.elementAt(i);
                  final skTank = skTanks[key];
                  final cfg = configs[key];
                  final level = _effectiveLevel(key);
                  final isManual = !connected || !skTanks.containsKey(key);
                  final displayName = cfg?.customName ?? _tankLabel(key);

                  // Capacity: prefer user config, then Signal K (m³ → L)
                  double? capacityL =
                      cfg?.capacityLitres ?? (skTank?.capacity != null
                          ? skTank!.capacity! * 1000
                          : null);

                  return _TankCard(
                    tankKey: key,
                    displayName: displayName,
                    level: level,
                    capacityLitres: capacityL,
                    isManual: isManual,
                    alertThreshold: cfg?.alertThresholdPct,
                    onManualSet: (v) => ref
                        .read(_tankConfigsProvider.notifier)
                        .setManualLevel(key, v),
                    onConfigure: () =>
                        _showConfigDialog(context, ref, key, cfg),
                  );
                },
              );
            },
          ),

          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Manual Tank'),
            onPressed: () => _showAddTankDialog(context, ref),
          ),
        ],
      ),
    );
  }

  void _showAddTankDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Tank'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Tank name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final key = 'manual.${name.toLowerCase().replaceAll(' ', '_')}';
              ref.read(_tankConfigsProvider.notifier).upsert(
                    _TankConfig(key: key, customName: name),
                  );
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showConfigDialog(
      BuildContext context, WidgetRef ref, String key, _TankConfig? existing) {
    final nameCtrl =
        TextEditingController(text: existing?.customName ?? _tankLabel(key));
    final capCtrl = TextEditingController(
        text: existing?.capacityLitres?.toStringAsFixed(0) ?? '');
    final alertCtrl = TextEditingController(
        text: existing?.alertThresholdPct?.toStringAsFixed(0) ?? '');

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Configure ${_tankLabel(key)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            TextField(
              controller: capCtrl,
              decoration: const InputDecoration(
                  labelText: 'Capacity (litres)', hintText: 'e.g. 200'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: alertCtrl,
              decoration: const InputDecoration(
                  labelText: 'Alert below (%)', hintText: 'e.g. 20'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              ref.read(_tankConfigsProvider.notifier).upsert(_TankConfig(
                    key: key,
                    customName:
                        nameCtrl.text.trim().isEmpty ? _tankLabel(key) : nameCtrl.text.trim(),
                    capacityLitres: double.tryParse(capCtrl.text),
                    manualLevel: existing?.manualLevel,
                    alertThresholdPct: double.tryParse(alertCtrl.text),
                  ));
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ── Tank Card ─────────────────────────────────────────────────────────────────

class _TankCard extends StatelessWidget {
  const _TankCard({
    required this.tankKey,
    required this.displayName,
    required this.level,
    required this.capacityLitres,
    required this.isManual,
    required this.alertThreshold,
    required this.onManualSet,
    required this.onConfigure,
  });

  final String tankKey;
  final String displayName;
  final double? level; // 0-1
  final double? capacityLitres;
  final bool isManual;
  final double? alertThreshold;
  final ValueChanged<double> onManualSet;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final pct = level != null ? (level! * 100).clamp(0.0, 100.0) : null;
    final color = pct != null ? _levelColor(pct) : Colors.grey;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                InkWell(
                  onTap: onConfigure,
                  child: const Icon(Icons.settings, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Vertical fill graphic
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 40,
                    child: pct != null
                        ? CustomPaint(
                            painter: _TankPainter(level: pct / 100, color: color),
                          )
                        : const Center(
                            child: Icon(Icons.signal_wifi_off, size: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (pct != null) ...[
                          Text(
                            '${pct.toStringAsFixed(0)}%',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(color: color),
                          ),
                          if (capacityLitres != null)
                            Text(
                              '${(level! * capacityLitres!).toStringAsFixed(0)} / ${capacityLitres!.toStringAsFixed(0)} L',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ] else
                          Text('--',
                              style: Theme.of(context).textTheme.headlineSmall),
                        if (isManual)
                          Text('Manual',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: Colors.orange)),
                        if (alertThreshold != null && pct != null && pct < alertThreshold!)
                          Text('Low!',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isManual && pct != null) ...[
              const SizedBox(height: 8),
              Slider(
                value: level!.clamp(0.0, 1.0),
                onChanged: onManualSet,
                activeColor: color,
              ),
            ] else if (isManual) ...[
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => _showManualDialog(context),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(32)),
                child: const Text('Set Level'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showManualDialog(BuildContext context) {
    double val = level ?? 0.5;
    showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Set $displayName level'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${(val * 100).toStringAsFixed(0)}%'),
              Slider(
                value: val,
                onChanged: (v) => setState(() => val = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                onManualSet(val);
                Navigator.pop(ctx);
              },
              child: const Text('Set'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tank fill painter ─────────────────────────────────────────────────────────

class _TankPainter extends CustomPainter {
  final double level; // 0-1
  final Color color;

  const _TankPainter({required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.grey.shade400;

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.7);

    final borderRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, 4, size.width - 8, size.height - 8),
      const Radius.circular(4),
    );

    final fillHeight = (size.height - 8) * level;
    final fillTop = (size.height - 8) - fillHeight + 4;
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, fillTop, size.width - 8, fillHeight),
      const Radius.circular(4),
    );

    canvas.drawRRect(fillRect, fillPaint);
    canvas.drawRRect(borderRect, borderPaint);

    // Tick marks at 25%, 50%, 75%
    final tickPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;
    for (final frac in [0.25, 0.5, 0.75]) {
      final y = 4 + (size.height - 8) * (1 - frac);
      canvas.drawLine(
        Offset(size.width - 10, y),
        Offset(size.width - 4, y),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_TankPainter old) =>
      old.level != level || old.color != color;
}
