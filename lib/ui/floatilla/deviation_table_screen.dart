import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers/signalk_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

/// A single deviation observation.
class DeviationEntry {
  final double compassHeading; // degrees magnetic (from compass)
  final double gpsHeading; // degrees true (from GPS COG)
  final DateTime timestamp;
  final String? note;

  const DeviationEntry({
    required this.compassHeading,
    required this.gpsHeading,
    required this.timestamp,
    this.note,
  });

  /// Deviation = GPS heading − compass heading (corrected for wrap-around).
  double get deviation {
    double d = gpsHeading - compassHeading;
    while (d > 180) { d -= 360; }
    while (d < -180) { d += 360; }
    return d;
  }

  Map<String, dynamic> toJson() => {
        'compassHeading': compassHeading,
        'gpsHeading': gpsHeading,
        'timestamp': timestamp.toIso8601String(),
        if (note != null) 'note': note,
      };

  factory DeviationEntry.fromJson(Map<String, dynamic> j) => DeviationEntry(
        compassHeading: (j['compassHeading'] as num).toDouble(),
        gpsHeading: (j['gpsHeading'] as num).toDouble(),
        timestamp: DateTime.parse(j['timestamp'] as String),
        note: j['note'] as String?,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

const _kPrefsKey = 'deviation_entries';

final deviationEntriesProvider =
    StateNotifierProvider<DeviationEntriesNotifier, List<DeviationEntry>>(
        (ref) => DeviationEntriesNotifier());

class DeviationEntriesNotifier extends StateNotifier<List<DeviationEntry>> {
  DeviationEntriesNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(DeviationEntry.fromJson)
          .toList();
      state = list;
    } catch (_) {}
  }

  Future<void> add(DeviationEntry entry) async {
    final next = [...state, entry];
    state = next;
    await _persist(next);
  }

  Future<void> remove(int index) async {
    final next = [...state]..removeAt(index);
    state = next;
    await _persist(next);
  }

  Future<void> clear() async {
    state = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsKey);
  }

  Future<void> _persist(List<DeviationEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kPrefsKey, jsonEncode(entries.map((e) => e.toJson()).toList()));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Deviation card helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Build a 36-point deviation card from entries using a simple average in
/// 10-degree bins.  Returns a list of 36 (compassHeading, deviation) pairs.
List<(double, double)> buildDeviationCard(List<DeviationEntry> entries) {
  if (entries.isEmpty) return [];

  // Group into 10° bins (0–9, 10–19, … 350–359)
  final bins = <int, List<double>>{};
  for (final e in entries) {
    final bin = (e.compassHeading / 10).floor() * 10;
    bins.putIfAbsent(bin, () => []).add(e.deviation);
  }

  final result = <(double, double)>[];
  for (int deg = 0; deg < 360; deg += 10) {
    final deviations = bins[deg];
    if (deviations == null) continue;
    final avg = deviations.reduce((a, b) => a + b) / deviations.length;
    result.add((deg.toDouble(), avg));
  }
  result.sort((a, b) => a.$1.compareTo(b.$1));
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────────────────────

class DeviationTableScreen extends ConsumerStatefulWidget {
  const DeviationTableScreen({super.key});

  @override
  ConsumerState<DeviationTableScreen> createState() =>
      _DeviationTableScreenState();
}

class _DeviationTableScreenState extends ConsumerState<DeviationTableScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deviation Table'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Log'),
            Tab(text: 'Deviation Card'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _LogTab(),
          _CardTab(),
        ],
      ),
      floatingActionButton: _LogFAB(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Log tab
// ─────────────────────────────────────────────────────────────────────────────

class _LogTab extends ConsumerWidget {
  const _LogTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(deviationEntriesProvider);

    if (entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No observations yet',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
            SizedBox(height: 8),
            Text('Tap + to log a compass vs GPS heading pair.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 0),
      itemBuilder: (context, i) {
        final e = entries[i];
        final dev = e.deviation;
        final devStr =
            '${dev >= 0 ? '+' : ''}${dev.toStringAsFixed(1)}°';
        final color = dev.abs() > 5
            ? Colors.orange
            : dev.abs() > 10
                ? Colors.red
                : Colors.green;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child:
                Text('${e.compassHeading.round()}°', style: const TextStyle(fontSize: 11)),
          ),
          title: Text(
            'Compass ${e.compassHeading.toStringAsFixed(1)}°  →  GPS ${e.gpsHeading.toStringAsFixed(1)}°',
          ),
          subtitle: Text(
            '${e.timestamp.toLocal().toString().substring(0, 16)}'
            '${e.note != null ? '  ·  ${e.note}' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Chip(
                label: Text(devStr,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                backgroundColor: color.withValues(alpha: 0.1),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _confirmDelete(context, ref, i),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext ctx, WidgetRef ref, int i) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Delete observation?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) ref.read(deviationEntriesProvider.notifier).remove(i);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Deviation Card tab
// ─────────────────────────────────────────────────────────────────────────────

class _CardTab extends ConsumerWidget {
  const _CardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(deviationEntriesProvider);
    final card = buildDeviationCard(entries);

    if (card.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Log at least a few observations across different headings\n'
            'to generate your deviation card.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _DeviationChart(card: card),
          ),
        ),
        const Divider(height: 0),
        Expanded(
          flex: 2,
          child: _DeviationCardTable(card: card),
        ),
        if (entries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Clear all observations'),
              style:
                  TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => _confirmClear(context, ref),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext ctx, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Clear all observations?'),
        content:
            const Text('This will delete all logged compass observations.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) ref.read(deviationEntriesProvider.notifier).clear();
  }
}

class _DeviationCardTable extends StatelessWidget {
  const _DeviationCardTable({required this.card});
  final List<(double, double)> card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Expanded(
                  child: Text('Compass',
                      style: theme.textTheme.labelMedium,
                      textAlign: TextAlign.center)),
              Expanded(
                  child: Text('Deviation',
                      style: theme.textTheme.labelMedium,
                      textAlign: TextAlign.center)),
              Expanded(
                  child: Text('Magnetic',
                      style: theme.textTheme.labelMedium,
                      textAlign: TextAlign.center)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: card.length,
            itemBuilder: (_, i) {
              final (cHdg, dev) = card[i];
              final magnetic = (cHdg + dev + 360) % 360;
              final devStr =
                  '${dev >= 0 ? '+' : ''}${dev.toStringAsFixed(1)}°';
              final color = dev.abs() > 10
                  ? Colors.red
                  : dev.abs() > 5
                      ? Colors.orange
                      : theme.colorScheme.onSurface;
              return Container(
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: theme.dividerColor, width: 0.5)),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                        child: Text('${cHdg.toStringAsFixed(0)}°',
                            textAlign: TextAlign.center)),
                    Expanded(
                        child: Text(devStr,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        child: Text('${magnetic.toStringAsFixed(0)}°',
                            textAlign: TextAlign.center)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Simple deviation curve painter
// ─────────────────────────────────────────────────────────────────────────────

class _DeviationChart extends StatelessWidget {
  const _DeviationChart({required this.card});
  final List<(double, double)> card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _DeviationPainter(cardData: card, theme: theme),
      child: const SizedBox.expand(),
    );
  }
}

class _DeviationPainter extends CustomPainter {
  _DeviationPainter({required this.cardData, required this.theme});
  final List<(double, double)> cardData;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final maxDev = cardData.map((e) => e.$2.abs()).reduce(math.max);
    final yRange = math.max(maxDev + 2, 10.0);
    final midY = size.height / 2;
    const padX = 48.0;
    final chartW = size.width - padX * 2;

    // Axes
    final axisPaint = Paint()
      ..color = theme.dividerColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(padX, 0), Offset(padX, size.height), axisPaint);
    canvas.drawLine(
        Offset(padX, midY), Offset(size.width - padX, midY), axisPaint);

    // Y-axis labels
    final labelStyle = TextStyle(
        fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.6));

    void drawLabel(String text, Offset offset) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, offset);
    }

    drawLabel('+${yRange.toStringAsFixed(0)}°',
        Offset(0, 0));
    drawLabel('0°', Offset(4, midY - 7));
    drawLabel('-${yRange.toStringAsFixed(0)}°',
        Offset(0, size.height - 14));

    // Zero line label
    drawLabel('N', Offset(padX, size.height - 14));
    drawLabel('E',
        Offset(padX + chartW * 0.25 - 4, size.height - 14));
    drawLabel('S',
        Offset(padX + chartW * 0.5 - 4, size.height - 14));
    drawLabel('W',
        Offset(padX + chartW * 0.75 - 4, size.height - 14));

    // Curve
    final curvePaint = Paint()
      ..color = theme.colorScheme.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool first = true;
    for (final (cHdg, dev) in cardData) {
      final x = padX + (cHdg / 360) * chartW;
      final y = midY - (dev / yRange) * midY;
      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, curvePaint);

    // Dots
    final dotPaint = Paint()
      ..color = theme.colorScheme.secondary
      ..style = PaintingStyle.fill;
    for (final (cHdg, dev) in cardData) {
      final x = padX + (cHdg / 360) * chartW;
      final y = midY - (dev / yRange) * midY;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_DeviationPainter old) => old.cardData != cardData;
}

// ─────────────────────────────────────────────────────────────────────────────
// FAB — log new observation
// ─────────────────────────────────────────────────────────────────────────────

class _LogFAB extends ConsumerWidget {
  const _LogFAB();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton.extended(
      icon: const Icon(Icons.add),
      label: const Text('Log observation'),
      onPressed: () => _showLogDialog(context, ref),
    );
  }

  Future<void> _showLogDialog(BuildContext context, WidgetRef ref) async {
    // Try to pre-fill from live SignalK data.
    final vessel = ref.read(signalKOwnVesselProvider);
    final liveCog = vessel.navigation.cog != null
        ? vessel.navigation.cog!.toStringAsFixed(1)
        : '';
    final liveHdm = vessel.navigation.headingMagnetic != null
        ? vessel.navigation.headingMagnetic!.toStringAsFixed(1)
        : '';

    final compassCtrl =
        TextEditingController(text: liveHdm);
    final gpsCtrl =
        TextEditingController(text: liveCog);
    final noteCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log compass observation'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (liveHdm.isNotEmpty || liveCog.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.sensors, size: 16,
                          color: Colors.green),
                      const SizedBox(width: 6),
                      const Text('Pre-filled from Signal K',
                          style: TextStyle(
                              fontSize: 12, color: Colors.green)),
                    ],
                  ),
                ),
              TextFormField(
                controller: compassCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Compass heading (°M)',
                  helperText: 'Read from your binnacle compass',
                ),
                validator: (v) {
                  final d = double.tryParse(v ?? '');
                  if (d == null) return 'Enter a number';
                  if (d < 0 || d > 360) return '0–360';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: gpsCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: const InputDecoration(
                  labelText: 'GPS/COG heading (°T)',
                  helperText: 'From GPS COG (add variation for true→magnetic)',
                ),
                validator: (v) {
                  final d = double.tryParse(v ?? '');
                  if (d == null) return 'Enter a number';
                  if (d < 0 || d > 360) return '0–360';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  helperText: 'e.g. calm seas, motoring',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final entry = DeviationEntry(
                compassHeading:
                    double.parse(compassCtrl.text),
                gpsHeading: double.parse(gpsCtrl.text),
                timestamp: DateTime.now(),
                note:
                    noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              );
              ref
                  .read(deviationEntriesProvider.notifier)
                  .add(entry);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
