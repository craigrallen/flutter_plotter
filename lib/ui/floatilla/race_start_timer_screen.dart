import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/signalk_provider.dart';
import '../../core/signalk/signalk_source.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State model
// ─────────────────────────────────────────────────────────────────────────────

enum TimerStatus { idle, running, finished }

class RaceTimerState {
  /// Minutes in the countdown (typically 5 or 10).
  final int durationMinutes;

  /// Epoch ms when start gun fires (null if not started).
  final int? startEpochMs;

  /// Whether the timer is running/ticking.
  final TimerStatus status;

  /// Start-line end A bearing (degrees true from centre line mid-point).
  final double? lineABearing;

  /// Start-line end B bearing.
  final double? lineBBearing;

  /// Favoured end: 'A', 'B', or null.
  final String? favouredEnd;

  const RaceTimerState({
    this.durationMinutes = 5,
    this.startEpochMs,
    this.status = TimerStatus.idle,
    this.lineABearing,
    this.lineBBearing,
    this.favouredEnd,
  });

  RaceTimerState copyWith({
    int? durationMinutes,
    int? startEpochMs,
    bool clearStart = false,
    TimerStatus? status,
    double? lineABearing,
    bool clearLineA = false,
    double? lineBBearing,
    bool clearLineB = false,
    String? favouredEnd,
    bool clearFavoured = false,
  }) {
    return RaceTimerState(
      durationMinutes: durationMinutes ?? this.durationMinutes,
      startEpochMs:
          clearStart ? null : (startEpochMs ?? this.startEpochMs),
      status: status ?? this.status,
      lineABearing:
          clearLineA ? null : (lineABearing ?? this.lineABearing),
      lineBBearing:
          clearLineB ? null : (lineBBearing ?? this.lineBBearing),
      favouredEnd:
          clearFavoured ? null : (favouredEnd ?? this.favouredEnd),
    );
  }

  /// Remaining ms (may be negative after start).
  int remainingMs(int nowMs) {
    if (startEpochMs == null) return durationMinutes * 60 * 1000;
    return startEpochMs! - nowMs;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

final raceTimerProvider =
    StateNotifierProvider<RaceTimerNotifier, RaceTimerState>((ref) {
  return RaceTimerNotifier();
});

class RaceTimerNotifier extends StateNotifier<RaceTimerState> {
  RaceTimerNotifier() : super(const RaceTimerState());

  void setDuration(int minutes) {
    if (state.status == TimerStatus.idle) {
      state = state.copyWith(durationMinutes: minutes);
    }
  }

  void start() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    state = state.copyWith(
      startEpochMs: nowMs + state.durationMinutes * 60 * 1000,
      status: TimerStatus.running,
    );
  }

  void sync() {
    // Sync to nearest whole minute.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (state.startEpochMs == null) return;
    final remMs = state.startEpochMs! - nowMs;
    final remMin = (remMs / 60000).ceil();
    final adjusted =
        nowMs + remMin * 60000;
    state = state.copyWith(startEpochMs: adjusted);
  }

  void reset() {
    state = const RaceTimerState();
  }

  void markFinished() {
    state = state.copyWith(status: TimerStatus.finished);
  }

  void setLineBearings(double a, double b) {
    // Determine favoured end: the end that is further to windward
    // (i.e., closer to the wind direction / closer to the start line
    // being square to the wind).
    state = state.copyWith(
      lineABearing: a,
      lineBBearing: b,
    );
    _recalcFavoured();
  }

  void _recalcFavoured() {
    final a = state.lineABearing;
    final b = state.lineBBearing;
    if (a == null || b == null) return;

    // Favoured end is the one more upwind — i.e., the pin-end closest to
    // true wind direction.  Without wind data we fall back to the end whose
    // bearing is further from 180° (i.e., is to leeward side of the line
    // is shorter).  We calculate which end has a smaller port-tack layline
    // angle by checking which bearing is closer to 270° (wind from port).
    // In practice: compare absolute difference between the two bearings to
    // find which end gives the shorter distance to the line.
    // Simple heuristic: end A is favoured if bearing A is closer to 270.
    final diffA = ((a - 270 + 360) % 360);
    final normA = diffA > 180 ? 360 - diffA : diffA;
    final diffB = ((b - 270 + 360) % 360);
    final normB = diffB > 180 ? 360 - diffB : diffB;

    state = state.copyWith(favouredEnd: normA < normB ? 'A' : 'B');
  }

  void clearLine() {
    state = state.copyWith(clearLineA: true, clearLineB: true, clearFavoured: true);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class RaceStartTimerScreen extends ConsumerStatefulWidget {
  const RaceStartTimerScreen({super.key});

  @override
  ConsumerState<RaceStartTimerScreen> createState() =>
      _RaceStartTimerScreenState();
}

class _RaceStartTimerScreenState extends ConsumerState<RaceStartTimerScreen>
    with SingleTickerProviderStateMixin {
  late final Timer _ticker;
  late final TabController _tabs;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;

  // TOD / distance inputs
  final _distController = TextEditingController(text: '1.0');
  final _speedController = TextEditingController(text: '5.0');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {
        _nowMs = DateTime.now().millisecondsSinceEpoch;
      });
      // Auto-mark finished just after gun
      final timerState = ref.read(raceTimerProvider);
      if (timerState.status == TimerStatus.running) {
        final rem = timerState.remainingMs(_nowMs);
        if (rem < -500) {
          ref.read(raceTimerProvider.notifier).markFinished();
        }
      }
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    _tabs.dispose();
    _distController.dispose();
    _speedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timerState = ref.watch(raceTimerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Race Start Timer'),
        actions: [
          if (timerState.status != TimerStatus.idle)
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Reset'),
              onPressed: () => ref.read(raceTimerProvider.notifier).reset(),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Timer'),
            Tab(text: 'Line & TOD'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _TimerTab(timerState: timerState, nowMs: _nowMs),
          _LineTab(
            timerState: timerState,
            nowMs: _nowMs,
            distController: _distController,
            speedController: _speedController,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timer tab
// ─────────────────────────────────────────────────────────────────────────────

class _TimerTab extends ConsumerWidget {
  final RaceTimerState timerState;
  final int nowMs;

  const _TimerTab({required this.timerState, required this.nowMs});

  String _formatTime(int ms) {
    final abs = ms.abs();
    final totalSec = (abs / 1000).ceil();
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    final sign = ms < 0 ? '+' : '';
    return '$sign${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remMs = timerState.remainingMs(nowMs);
    final isRunning = timerState.status == TimerStatus.running;
    final isIdle = timerState.status == TimerStatus.idle;
    final isFinished = timerState.status == TimerStatus.finished;
    final isPastGun = remMs < 0;

    // Colour logic
    Color timerColour;
    if (isFinished || (isRunning && isPastGun)) {
      timerColour = Colors.green;
    } else if (isRunning && remMs < 60000) {
      timerColour = Colors.red;
    } else if (isRunning && remMs < 180000) {
      timerColour = Colors.orange;
    } else if (isRunning) {
      timerColour = Colors.blue;
    } else {
      timerColour = Theme.of(context).colorScheme.onSurface;
    }

    return Column(
      children: [
        // ── Duration selector (only when idle) ──
        if (isIdle)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                const Text('Countdown:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                ...[1, 3, 5, 10].map((m) {
                  final sel = timerState.durationMinutes == m;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${m}min'),
                      selected: sel,
                      onSelected: (_) =>
                          ref.read(raceTimerProvider.notifier).setDuration(m),
                    ),
                  );
                }),
              ],
            ),
          ),

        // ── Big clock ──
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status label
                Text(
                  isIdle
                      ? 'Ready'
                      : isFinished
                          ? 'RACING'
                          : isPastGun
                              ? 'GUN!'
                              : 'Countdown',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: timerColour,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),

                // Main timer digits
                Text(
                  isIdle
                      ? '${timerState.durationMinutes.toString().padLeft(2, '0')}:00'
                      : _formatTime(remMs),
                  style: TextStyle(
                    fontSize: 88,
                    fontWeight: FontWeight.w900,
                    color: timerColour,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),

                const SizedBox(height: 24),

                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isIdle) ...[
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 16),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                        onPressed: () =>
                            ref.read(raceTimerProvider.notifier).start(),
                      ),
                    ] else if (isRunning) ...[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.sync),
                        label: const Text('Sync'),
                        onPressed: () =>
                            ref.read(raceTimerProvider.notifier).sync(),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () =>
                            ref.read(raceTimerProvider.notifier).reset(),
                      ),
                    ] else if (isFinished) ...[
                      FilledButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('New Race'),
                        onPressed: () =>
                            ref.read(raceTimerProvider.notifier).reset(),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 32),

                // Sync hint
                if (isRunning && !isPastGun)
                  const Text(
                    'Tap Sync to align to the next whole minute',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),

        // ── Quick-access layline panel ──
        if (!isIdle)
          _LaylinePanel(timerState: timerState, nowMs: nowMs),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Layline panel (compact, shown during countdown)
// ─────────────────────────────────────────────────────────────────────────────

class _LaylinePanel extends ConsumerWidget {
  final RaceTimerState timerState;
  final int nowMs;

  const _LaylinePanel({required this.timerState, required this.nowMs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skState = ref.watch(signalKProvider);
    final nav = skState.ownVessel.navigation;
    final env = skState.ownVessel.environment;
    final cog = nav.cog;
    final sog = nav.sog;
    final twa = env.windAngleTrueWater;
    final tws = env.windSpeedTrue;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(0.5),
        border: Border(
          top: BorderSide(
            color:
                Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _PanelCell(
            label: 'COG',
            value:
                cog != null ? '${cog.toStringAsFixed(0)}°' : '—',
          ),
          _PanelCell(
            label: 'SOG',
            value:
                sog != null ? '${sog.toStringAsFixed(1)}kn' : '—',
          ),
          _PanelCell(
            label: 'TWA',
            value: twa != null
                ? '${twa.toStringAsFixed(0)}°'
                : '—',
          ),
          _PanelCell(
            label: 'TWS',
            value: tws != null
                ? '${tws.toStringAsFixed(1)}kn'
                : '—',
          ),
          if (timerState.favouredEnd != null)
            _PanelCell(
              label: 'Favoured',
              value: 'End ${timerState.favouredEnd}',
              color: Colors.amber,
            ),
        ],
      ),
    );
  }
}

class _PanelCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _PanelCell({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Line & TOD tab
// ─────────────────────────────────────────────────────────────────────────────

class _LineTab extends ConsumerStatefulWidget {
  final RaceTimerState timerState;
  final int nowMs;
  final TextEditingController distController;
  final TextEditingController speedController;

  const _LineTab({
    required this.timerState,
    required this.nowMs,
    required this.distController,
    required this.speedController,
  });

  @override
  ConsumerState<_LineTab> createState() => _LineTabState();
}

class _LineTabState extends ConsumerState<_LineTab> {
  final _bearingAController = TextEditingController();
  final _bearingBController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final timerState = widget.timerState;
    if (timerState.lineABearing != null) {
      _bearingAController.text =
          timerState.lineABearing!.toStringAsFixed(0);
    }
    if (timerState.lineBBearing != null) {
      _bearingBController.text =
          timerState.lineBBearing!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _bearingAController.dispose();
    _bearingBController.dispose();
    super.dispose();
  }

  void _applyLine() {
    final a = double.tryParse(_bearingAController.text.trim());
    final b = double.tryParse(_bearingBController.text.trim());
    if (a == null || b == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid bearings for both ends.')),
      );
      return;
    }
    ref.read(raceTimerProvider.notifier).setLineBearings(a, b);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Line set.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timerState = ref.watch(raceTimerProvider);
    final remMs = timerState.remainingMs(widget.nowMs);
    final remSec = (remMs / 1000).clamp(0, double.infinity);

    // TOD calculation
    final distNm =
        double.tryParse(widget.distController.text.trim()) ?? 1.0;
    final speedKn =
        double.tryParse(widget.speedController.text.trim()) ?? 5.0;
    double? todSec;
    if (distNm > 0 && speedKn > 0) {
      todSec = (distNm / speedKn) * 3600;
    }

    // Time-to-start minus TOD
    final burnMs = todSec != null ? remSec - todSec : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Time on Distance ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Time on Distance (TOD)',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'How long to reach the line at your current speed.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widget.distController,
                          decoration: const InputDecoration(
                            labelText: 'Distance to line (nm)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]')),
                          ],
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: widget.speedController,
                          decoration: const InputDecoration(
                            labelText: 'Speed (kn)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]')),
                          ],
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (todSec != null) ...[
                    _TodRow(
                      label: 'TOD',
                      value: _formatMinSec(todSec.round()),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    if (timerState.status == TimerStatus.running) ...[
                      const SizedBox(height: 8),
                      _TodRow(
                        label: 'Time to start',
                        value: _formatMinSec(remSec.round()),
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 8),
                      _TodBurnCard(burnSec: burnMs!),
                    ],
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Start line favoured end ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Start Line — Favoured End',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Enter the bearing FROM each end TOWARD the committee boat / pin.\n'
                    'The favoured end is the one that gains the most distance to windward.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _bearingAController,
                          decoration: const InputDecoration(
                            labelText: 'End A bearing (°T)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _bearingBController,
                          decoration: const InputDecoration(
                            labelText: 'End B bearing (°T)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: _applyLine,
                        child: const Text('Calculate'),
                      ),
                      if (timerState.lineABearing != null) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            ref
                                .read(raceTimerProvider.notifier)
                                .clearLine();
                            _bearingAController.clear();
                            _bearingBController.clear();
                          },
                          child: const Text('Clear'),
                        ),
                      ],
                    ],
                  ),

                  if (timerState.favouredEnd != null) ...[
                    const SizedBox(height: 16),
                    _FavouredEndCard(
                      favouredEnd: timerState.favouredEnd!,
                      lineABearing: timerState.lineABearing!,
                      lineBBearing: timerState.lineBBearing!,
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Laylines card ──
          _LaylinesCard(),
        ],
      ),
    );
  }

  String _formatMinSec(int totalSec) {
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '${min}m ${sec.toString().padLeft(2, '0')}s';
  }
}

class _TodRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _TodRow(
      {required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 14)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _TodBurnCard extends StatelessWidget {
  final double burnSec;

  const _TodBurnCard({required this.burnSec});

  @override
  Widget build(BuildContext context) {
    // burnSec > 0 → arrive too late; < 0 → arrive too early
    final lateEarly = burnSec > 0 ? 'late' : 'early';
    final abs = burnSec.abs();
    final min = abs ~/ 60;
    final sec = (abs % 60).round();
    final timeStr = min > 0 ? '${min}m ${sec}s' : '${sec}s';

    final color = burnSec > 30
        ? Colors.red
        : burnSec < -30
            ? Colors.orange
            : Colors.green;
    final message = burnSec > 30
        ? 'Speed up or reduce distance!'
        : burnSec < -30
            ? 'You\'ll arrive early — slow down or extend.'
            : 'On time — good approach!';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(
            burnSec.abs() <= 30
                ? Icons.check_circle
                : Icons.warning_amber_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$timeStr $lateEarly',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: color),
                ),
                Text(
                  message,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FavouredEndCard extends StatelessWidget {
  final String favouredEnd;
  final double lineABearing;
  final double lineBBearing;

  const _FavouredEndCard({
    required this.favouredEnd,
    required this.lineABearing,
    required this.lineBBearing,
  });

  double _lineBias() {
    // Angle of the start line from the average bearing
    final avg = (lineABearing + lineBBearing) / 2;
    final bias = ((lineABearing - avg + 360) % 360);
    return bias > 180 ? 360 - bias : bias;
  }

  @override
  Widget build(BuildContext context) {
    final bias = _lineBias();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag, color: Colors.amber, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'End $favouredEnd is favoured',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Colors.amber,
                  ),
                ),
                Text(
                  'Line bias: ${bias.toStringAsFixed(1)}°  ·  '
                  'A: ${lineABearing.toStringAsFixed(0)}°T  '
                  'B: ${lineBBearing.toStringAsFixed(0)}°T',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Laylines visualiser
// ─────────────────────────────────────────────────────────────────────────────

class _LaylinesCard extends ConsumerWidget {
  const _LaylinesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skState = ref.watch(signalKProvider);
    final env = skState.ownVessel.environment;
    final nav = skState.ownVessel.navigation;
    final twa = env.windAngleTrueWater;
    final tws = env.windSpeedTrue;
    final cog = nav.cog;
    final connected =
        skState.connectionState == SignalKConnectionState.connected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Laylines',
              style:
                  TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              'Upwind tack angles based on live TWA.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (!connected)
              const _NoSkBanner()
            else if (twa == null)
              const _NoDataBanner(
                  message: 'Waiting for true wind angle…')
            else ...[
              SizedBox(
                height: 200,
                child: CustomPaint(
                  painter: _LaylinePainter(
                    twa: twa,
                    cog: cog,
                    color: Theme.of(context).colorScheme.primary,
                    gridColor: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.15),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 20,
                children: [
                  _PanelCell(
                    label: 'Port layline',
                    value: cog != null
                        ? '${_normBearing(cog - twa.abs()).toStringAsFixed(0)}°T'
                        : '—',
                    color: Colors.red,
                  ),
                  _PanelCell(
                    label: 'Stbd layline',
                    value: cog != null
                        ? '${_normBearing(cog + twa.abs()).toStringAsFixed(0)}°T'
                        : '—',
                    color: Colors.green,
                  ),
                  _PanelCell(
                    label: 'Tack angle',
                    value: '${(twa.abs() * 2).toStringAsFixed(0)}°',
                  ),
                  if (tws != null)
                    _PanelCell(
                      label: 'TWS',
                      value: '${tws.toStringAsFixed(1)} kn',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _normBearing(double deg) => ((deg % 360) + 360) % 360;
}

class _LaylinePainter extends CustomPainter {
  final double twa;
  final double? cog;
  final Color color;
  final Color gridColor;

  const _LaylinePainter({
    required this.twa,
    required this.cog,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.75;
    final len = math.min(cx, cy) * 1.1;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // Horizon line
    canvas.drawLine(
        Offset(0, cy), Offset(size.width, cy), gridPaint);

    final heading = cog ?? 0;

    void drawLine(double bearingDeg, Color c) {
      final rad = (bearingDeg - 90) * math.pi / 180;
      final x2 = cx + len * math.cos(rad);
      final y2 = cy + len * math.sin(rad);
      canvas.drawLine(
        Offset(cx, cy),
        Offset(x2, y2),
        Paint()
          ..color = c
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }

    final absAngle = twa.abs();

    // Port tack layline (wind from starboard — red)
    drawLine(((heading - absAngle) % 360 + 360) % 360, Colors.red);
    // Starboard tack layline (green)
    drawLine(((heading + absAngle) % 360 + 360) % 360, Colors.green);
    // COG / heading (white/primary)
    drawLine(heading, color);

    // Boat symbol
    canvas.drawCircle(
      Offset(cx, cy),
      5,
      Paint()..color = color,
    );

    // Wind direction indicator (upwind is up)
    final windY = cy - len * 0.92;
    canvas.drawLine(
      Offset(cx, windY),
      Offset(cx, windY - 18),
      Paint()
        ..color = Colors.amber
        ..strokeWidth = 2,
    );
    final arrowPath = Path()
      ..moveTo(cx, windY - 18)
      ..lineTo(cx - 6, windY - 8)
      ..lineTo(cx + 6, windY - 8)
      ..close();
    canvas.drawPath(
      arrowPath,
      Paint()..color = Colors.amber,
    );
  }

  @override
  bool shouldRepaint(_LaylinePainter old) =>
      old.twa != twa || old.cog != cog;
}

class _NoSkBanner extends StatelessWidget {
  const _NoSkBanner();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.link_off, color: Colors.grey),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Connect to Signal K in Settings for live laylines.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _NoDataBanner extends StatelessWidget {
  final String message;

  const _NoDataBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.hourglass_empty, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style:
                  const TextStyle(color: Colors.grey, fontSize: 13)),
        ),
      ],
    );
  }
}
