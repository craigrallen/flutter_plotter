import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers/boat_health_provider.dart';
import '../shared/responsive.dart';

// ── Entry point ──────────────────────────────────────────────────────────────

class BoatHealthScreen extends ConsumerWidget {
  const BoatHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Responsive.of(context);
    if (layout == LayoutSize.compact) {
      return const _HealthPhoneLayout();
    }
    return const _HealthTabletLayout();
  }
}

// ── Tablet: list left, detail right ─────────────────────────────────────────

class _HealthTabletLayout extends ConsumerStatefulWidget {
  const _HealthTabletLayout();

  @override
  ConsumerState<_HealthTabletLayout> createState() =>
      _HealthTabletLayoutState();
}

class _HealthTabletLayoutState extends ConsumerState<_HealthTabletLayout> {
  String? _selectedPath;

  @override
  Widget build(BuildContext context) {
    final sensors = ref.watch(sensorListProvider);

    return Scaffold(
      appBar: _buildAppBar(context, ref),
      body: Row(
        children: [
          SizedBox(
            width: 340,
            child: _SensorList(
              sensors: sensors,
              selectedPath: _selectedPath,
              onTap: (path) => setState(() => _selectedPath = path),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedPath != null
                ? _SensorDetailPane(path: _selectedPath!)
                : const Center(
                    child: Text('Select a sensor'),
                  ),
          ),
        ],
      ),
      floatingActionButton: _AlertsButton(context: context, ref: ref),
    );
  }
}

// ── Phone: single list with tap-to-expand ───────────────────────────────────

class _HealthPhoneLayout extends ConsumerWidget {
  const _HealthPhoneLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sensors = ref.watch(sensorListProvider);

    return Scaffold(
      appBar: _buildAppBar(context, ref),
      body: _SensorList(
        sensors: sensors,
        selectedPath: null,
        onTap: (path) => _showDetail(context, path),
      ),
      floatingActionButton: _AlertsButton(context: context, ref: ref),
    );
  }

  void _showDetail(BuildContext context, String path) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => _SensorDetailPane(
          path: path,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

// ── App bar ──────────────────────────────────────────────────────────────────

PreferredSizeWidget _buildAppBar(BuildContext context, WidgetRef ref) {
  final health = ref.watch(boatHealthProvider);
  final online = health.onlineCount;
  final warnings = health.warningCount;
  final offline = health.offlineCount;

  return AppBar(
    title: const Text('Boat Health'),
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(36),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            _StatusChip(
              icon: Icons.check_circle,
              color: Colors.green,
              label: '$online online',
            ),
            const SizedBox(width: 8),
            _StatusChip(
              icon: Icons.warning,
              color: Colors.amber,
              label: '$warnings warnings',
            ),
            const SizedBox(width: 8),
            _StatusChip(
              icon: Icons.error,
              color: Colors.red,
              label: '$offline offline',
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _StatusChip({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ── Sensor list ──────────────────────────────────────────────────────────────

class _SensorList extends ConsumerWidget {
  final List<SensorData> sensors;
  final String? selectedPath;
  final ValueChanged<String> onTap;

  const _SensorList({
    required this.sensors,
    required this.selectedPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sensors.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sensors_off, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No sensor data yet.\nConnect to Signal K to begin.',
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final alertHistory = ref.watch(boatHealthProvider).alertHistory;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: sensors.length,
            itemBuilder: (context, index) {
              final sensor = sensors[index];
              return _SensorCard(
                sensor: sensor,
                isSelected: sensor.path == selectedPath,
                onTap: () => onTap(sensor.path),
              );
            },
          ),
        ),
        if (alertHistory.isNotEmpty) _AlertHistoryStrip(alerts: alertHistory),
      ],
    );
  }
}

// ── Sensor card ──────────────────────────────────────────────────────────────

class _SensorCard extends StatelessWidget {
  final SensorData sensor;
  final bool isSelected;
  final VoidCallback onTap;

  const _SensorCard({
    required this.sensor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(sensor.status);
    final statusIcon = _statusIcon(sensor.status);

    final groupPath = sensor.path.length > 30
        ? '${sensor.path.substring(0, 27)}...'
        : sensor.path;

    final lastSeenStr = sensor.lastSeen != null
        ? _formatAge(DateTime.now().difference(sensor.lastSeen!))
        : 'never';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      groupPath,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    lastSeenStr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sensor.currentValue != null
                          ? '${_formatValue(sensor.currentValue!)} ${sensor.unit}'
                          : '--',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                  if (sensor.history.length >= 3)
                    SizedBox(
                      width: 80,
                      height: 28,
                      child: _Sparkline(readings: sensor.history),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sensor detail pane ───────────────────────────────────────────────────────

class _SensorDetailPane extends ConsumerWidget {
  final String path;
  final ScrollController? scrollController;

  const _SensorDetailPane({required this.path, this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(boatHealthProvider);
    final sensor = health.sensors[path];
    final theme = Theme.of(context);

    if (sensor == null) {
      return const Center(child: Text('Sensor not found'));
    }

    final now = DateTime.now();
    final twoHoursAgo = now.subtract(const Duration(hours: 2));
    final recentHistory = sensor.history
        .where((r) => r.timestamp.isAfter(twoHoursAgo))
        .toList();

    final values = recentHistory.map((r) => r.value).toList();
    final minVal = values.isEmpty ? 0.0 : values.reduce(math.min);
    final maxVal = values.isEmpty ? 0.0 : values.reduce(math.max);
    final avgVal = values.isEmpty
        ? 0.0
        : values.fold(0.0, (a, b) => a + b) / values.length;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Text(path, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(_statusIcon(sensor.status),
                color: _statusColor(sensor.status), size: 20),
            const SizedBox(width: 6),
            Text(
              _statusLabel(sensor.status),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _statusColor(sensor.status),
              ),
            ),
            const Spacer(),
            if (sensor.lastSeen != null)
              Text(
                'Last: ${DateFormat('HH:mm:ss').format(sensor.lastSeen!)}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Current value big display
        Center(
          child: Text(
            sensor.currentValue != null
                ? '${_formatValue(sensor.currentValue!)} ${sensor.unit}'
                : '--',
            style: theme.textTheme.displaySmall?.copyWith(
              color: _statusColor(sensor.status),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Stats row
        if (values.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatBox(label: 'Min', value: _formatValue(minVal), unit: sensor.unit),
              _StatBox(label: 'Avg', value: _formatValue(avgVal), unit: sensor.unit),
              _StatBox(label: 'Max', value: _formatValue(maxVal), unit: sensor.unit),
              _StatBox(
                  label: 'Readings',
                  value: '${recentHistory.length}',
                  unit: '/2h'),
            ],
          ),
          const SizedBox(height: 16),
          // Full history chart
          SizedBox(
            height: 140,
            child: _HistoryChart(
                readings: recentHistory, unit: sensor.unit),
          ),
          const SizedBox(height: 16),
        ],
        // Alert threshold config
        const Divider(),
        Text('Alert Rules for this sensor',
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _SensorRulesList(path: path),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_alert),
          label: const Text('Add Alert Rule'),
          onPressed: () => _showAddRuleDialog(context, ref, path),
        ),
      ],
    );
  }

  void _showAddRuleDialog(BuildContext context, WidgetRef ref, String path) {
    showDialog(
      context: context,
      builder: (ctx) => _AddRuleDialog(path: path),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _StatBox({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value $unit',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

// ── Rules list for a sensor ──────────────────────────────────────────────────

class _SensorRulesList extends ConsumerWidget {
  final String path;

  const _SensorRulesList({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref
        .watch(boatHealthProvider)
        .rules
        .where((r) => r.path == path)
        .toList();

    if (rules.isEmpty) {
      return const Text('No rules configured for this sensor.');
    }

    return Column(
      children: rules.map((rule) => _RuleTile(rule: rule)).toList(),
    );
  }
}

class _RuleTile extends ConsumerWidget {
  final AlertRule rule;

  const _RuleTile({required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opStr = switch (rule.op) {
      ComparisonOp.greaterThan => '>',
      ComparisonOp.lessThan => '<',
      ComparisonOp.equalTo => '=',
    };

    return ListTile(
      dense: true,
      leading: Switch(
        value: rule.enabled,
        onChanged: (v) => ref
            .read(boatHealthProvider.notifier)
            .updateRule(rule.copyWith(enabled: v)),
      ),
      title: Text(rule.message),
      subtitle: Text('${rule.path} $opStr ${rule.threshold}'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: () =>
            ref.read(boatHealthProvider.notifier).removeRule(rule.id),
      ),
    );
  }
}

// ── Add rule dialog ──────────────────────────────────────────────────────────

class _AddRuleDialog extends ConsumerStatefulWidget {
  final String path;
  const _AddRuleDialog({required this.path});

  @override
  ConsumerState<_AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends ConsumerState<_AddRuleDialog> {
  late final TextEditingController _thresholdCtrl;
  late final TextEditingController _messageCtrl;
  ComparisonOp _op = ComparisonOp.greaterThan;

  @override
  void initState() {
    super.initState();
    _thresholdCtrl = TextEditingController();
    _messageCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _thresholdCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Alert Rule'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Path: ${widget.path}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          DropdownButtonFormField<ComparisonOp>(
            initialValue: _op,
            decoration: const InputDecoration(labelText: 'Condition'),
            items: const [
              DropdownMenuItem(
                  value: ComparisonOp.greaterThan,
                  child: Text('Greater than (>)')),
              DropdownMenuItem(
                  value: ComparisonOp.lessThan,
                  child: Text('Less than (<)')),
              DropdownMenuItem(
                  value: ComparisonOp.equalTo, child: Text('Equal to (=)')),
            ],
            onChanged: (v) => setState(() => _op = v!),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _thresholdCtrl,
            decoration: const InputDecoration(labelText: 'Threshold value'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _messageCtrl,
            decoration: const InputDecoration(labelText: 'Alert message'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }

  void _submit() {
    final threshold = double.tryParse(_thresholdCtrl.text);
    if (threshold == null || _messageCtrl.text.isEmpty) return;
    final rule = AlertRule(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      path: widget.path,
      threshold: threshold,
      op: _op,
      message: _messageCtrl.text,
    );
    ref.read(boatHealthProvider.notifier).addRule(rule);
    Navigator.pop(context);
  }
}

// ── Alert rules panel (bottom sheet) ────────────────────────────────────────

class _AlertRulesPanel extends ConsumerWidget {
  const _AlertRulesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(boatHealthProvider).rules;
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Alert Rules', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          ...rules.map((rule) => _RuleTile(rule: rule)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_alert),
            label: const Text('Add Custom Rule'),
            onPressed: () {
              Navigator.pop(ctx);
              _showCustomRuleDialog(context, ref);
            },
          ),
        ],
      ),
    );
  }

  void _showCustomRuleDialog(BuildContext context, WidgetRef ref) {
    // Ask for path first, then use add rule dialog
    showDialog(
      context: context,
      builder: (ctx) => const _CustomRulePathDialog(),
    );
  }
}

class _CustomRulePathDialog extends ConsumerStatefulWidget {
  const _CustomRulePathDialog();

  @override
  ConsumerState<_CustomRulePathDialog> createState() =>
      _CustomRulePathDialogState();
}

class _CustomRulePathDialogState
    extends ConsumerState<_CustomRulePathDialog> {
  late final TextEditingController _pathCtrl;

  @override
  void initState() {
    super.initState();
    _pathCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sensors = ref.watch(sensorListProvider);
    final paths = sensors.map((s) => s.path).toList();

    return AlertDialog(
      title: const Text('Custom Alert Rule'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Autocomplete<String>(
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) return paths;
              return paths.where((p) => p
                  .toLowerCase()
                  .contains(textEditingValue.text.toLowerCase()));
            },
            onSelected: (val) => _pathCtrl.text = val,
            fieldViewBuilder:
                (ctx, ctrl, focusNode, onSubmitted) =>
                    TextFormField(
              controller: ctrl,
              focusNode: focusNode,
              decoration:
                  const InputDecoration(labelText: 'Signal K path'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final path = _pathCtrl.text.trim();
            if (path.isEmpty) return;
            Navigator.pop(context);
            showDialog(
              context: context,
              builder: (_) => _AddRuleDialog(path: path),
            );
          },
          child: const Text('Next'),
        ),
      ],
    );
  }
}

// ── Alert history strip ──────────────────────────────────────────────────────

class _AlertHistoryStrip extends StatelessWidget {
  final List<TriggeredAlert> alerts;

  const _AlertHistoryStrip({required this.alerts});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = alerts.reversed.take(5).toList();

    return Container(
      color: theme.colorScheme.errorContainer.withAlpha(40),
      child: ExpansionTile(
        title: Text('Alert History (${alerts.length})',
            style: theme.textTheme.titleSmall),
        leading: const Icon(Icons.notifications_active, size: 18),
        children: recent
            .map(
              (a) => ListTile(
                dense: true,
                leading: const Icon(Icons.warning, size: 16),
                title: Text(a.message,
                    style: theme.textTheme.bodySmall),
                subtitle: Text(
                  '${a.path} — ${_formatValue(a.value)}  '
                  '${DateFormat('HH:mm:ss').format(a.triggeredAt)}',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── FAB for alerts panel ─────────────────────────────────────────────────────

class _AlertsButton extends StatelessWidget {
  final BuildContext context;
  final WidgetRef ref;

  const _AlertsButton({required this.context, required this.ref});

  @override
  Widget build(BuildContext context) {
    final alertCount = ref.watch(boatHealthProvider).alertHistory.length;

    return FloatingActionButton.extended(
      icon: Badge(
        isLabelVisible: alertCount > 0,
        label: Text('$alertCount'),
        child: const Icon(Icons.rule),
      ),
      label: const Text('Alert Rules'),
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => const _AlertRulesPanel(),
        );
      },
    );
  }
}

// ── Sparkline widget ─────────────────────────────────────────────────────────

class _Sparkline extends StatelessWidget {
  final List<SensorReading> readings;

  const _Sparkline({required this.readings});

  @override
  Widget build(BuildContext context) {
    final last20 =
        readings.length > 20 ? readings.sublist(readings.length - 20) : readings;
    return CustomPaint(
      painter: _SparklinePainter(
        readings: last20,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<SensorReading> readings;
  final Color color;

  const _SparklinePainter({required this.readings, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (readings.length < 2) return;

    final values = readings.map((r) => r.value).toList();
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = maxV - minV;
    if (range == 0) {
      // Flat line in the middle
      final y = size.height / 2;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = color
          ..strokeWidth = 1.5,
      );
      return;
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < readings.length; i++) {
      final x = i / (readings.length - 1) * size.width;
      final y = size.height - (values[i] - minV) / range * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.readings != readings || old.color != color;
}

// ── History chart ────────────────────────────────────────────────────────────

class _HistoryChart extends StatelessWidget {
  final List<SensorReading> readings;
  final String unit;

  const _HistoryChart({required this.readings, required this.unit});

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return const Center(child: Text('No history data'));
    }

    return CustomPaint(
      painter: _HistoryChartPainter(
        readings: readings,
        unit: unit,
        lineColor: Theme.of(context).colorScheme.primary,
        textStyle: Theme.of(context).textTheme.labelSmall!,
        gridColor: Theme.of(context)
            .colorScheme
            .onSurface
            .withAlpha(30),
      ),
    );
  }
}

class _HistoryChartPainter extends CustomPainter {
  final List<SensorReading> readings;
  final String unit;
  final Color lineColor;
  final Color gridColor;
  final TextStyle textStyle;

  const _HistoryChartPainter({
    required this.readings,
    required this.unit,
    required this.lineColor,
    required this.gridColor,
    required this.textStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 48.0;
    const bottomPad = 24.0;
    final chartW = size.width - leftPad;
    final chartH = size.height - bottomPad;

    final values = readings.map((r) => r.value).toList();
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = maxV == minV ? 1.0 : maxV - minV;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    // Grid lines (4 horizontal)
    for (int i = 0; i <= 4; i++) {
      final y = chartH * (1 - i / 4);
      canvas.drawLine(
          Offset(leftPad, y), Offset(size.width, y), gridPaint);
      final labelVal = minV + range * i / 4;
      _drawText(
          canvas,
          labelVal.toStringAsFixed(1),
          Offset(0, y - 6),
          size: 9);
    }

    // Line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < readings.length; i++) {
      final x = leftPad + i / (readings.length - 1) * chartW;
      final y = chartH * (1 - (values[i] - minV) / range);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    // X-axis time labels
    if (readings.length >= 2) {
      final first = readings.first.timestamp;
      final last = readings.last.timestamp;
      _drawText(
          canvas,
          DateFormat('HH:mm').format(first),
          Offset(leftPad, chartH + 6),
          size: 9);
      _drawText(
          canvas,
          DateFormat('HH:mm').format(last),
          Offset(size.width - 28, chartH + 6),
          size: 9);
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, {double size = 10}) {
    final span = TextSpan(
      text: text,
      style: textStyle.copyWith(fontSize: size),
    );
    final tp = TextPainter(text: span, textDirection: ui.TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_HistoryChartPainter old) =>
      old.readings != readings;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Color _statusColor(SensorStatus status) {
  switch (status) {
    case SensorStatus.online:
      return Colors.green;
    case SensorStatus.stale:
      return Colors.amber;
    case SensorStatus.offline:
      return Colors.grey;
    case SensorStatus.warning:
      return Colors.orange;
    case SensorStatus.critical:
      return Colors.red;
  }
}

IconData _statusIcon(SensorStatus status) {
  switch (status) {
    case SensorStatus.online:
      return Icons.check_circle;
    case SensorStatus.stale:
      return Icons.warning;
    case SensorStatus.offline:
      return Icons.sensors_off;
    case SensorStatus.warning:
      return Icons.warning;
    case SensorStatus.critical:
      return Icons.error;
  }
}

String _statusLabel(SensorStatus status) {
  switch (status) {
    case SensorStatus.online:
      return 'Online';
    case SensorStatus.stale:
      return 'Stale';
    case SensorStatus.offline:
      return 'Offline';
    case SensorStatus.warning:
      return 'Warning';
    case SensorStatus.critical:
      return 'Critical';
  }
}

String _formatValue(double v) {
  if (v.abs() >= 1000) return v.toStringAsFixed(0);
  if (v.abs() >= 10) return v.toStringAsFixed(1);
  return v.toStringAsFixed(2);
}

String _formatAge(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  return '${d.inHours}h ago';
}
