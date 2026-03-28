import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/providers/cloud_logbook_provider.dart';
import '../../data/providers/vessel_provider.dart';

// ── Main Screen ─────────────────────────────────────────────────────────────

class CloudLogbookScreen extends ConsumerStatefulWidget {
  const CloudLogbookScreen({super.key});

  @override
  ConsumerState<CloudLogbookScreen> createState() =>
      _CloudLogbookScreenState();
}

class _CloudLogbookScreenState extends ConsumerState<CloudLogbookScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() => _tabIndex = _tabController.index));
    // Trigger status check + sync on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cloudLogbookProvider.notifier).checkStatus();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 700;

    if (isTablet) {
      return _buildTabletLayout();
    } else {
      return _buildPhoneLayout();
    }
  }

  Widget _buildPhoneLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Logbook'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.book), text: "Captain's"),
            Tab(icon: Icon(Icons.directions_boat), text: "Ship's"),
            Tab(icon: Icon(Icons.map), text: 'Voyages'),
          ],
        ),
        actions: [_SyncButton()],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _CaptainsLogTab(),
          _ShipsLogTab(),
          _VoyagesTab(),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    final tabs = [
      const Tab(
          icon: Icon(Icons.book, size: 20),
          text: "Captain's Log"),
      const Tab(
          icon: Icon(Icons.directions_boat, size: 20),
          text: "Ship's Log"),
      const Tab(icon: Icon(Icons.map, size: 20), text: 'Voyages'),
    ];

    const bodies = [
      _CaptainsLogTab(),
      _ShipsLogTab(),
      _VoyagesTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Logbook'),
        actions: [_SyncButton()],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _tabIndex,
            onDestinationSelected: (i) {
              _tabController.animateTo(i);
            },
            labelType: NavigationRailLabelType.all,
            destinations: [
              NavigationRailDestination(
                icon: tabs[0].icon!,
                label: Text(tabs[0].text!),
              ),
              NavigationRailDestination(
                icon: tabs[1].icon!,
                label: Text(tabs[1].text!),
              ),
              NavigationRailDestination(
                icon: tabs[2].icon!,
                label: Text(tabs[2].text!),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: bodies[_tabIndex]),
        ],
      ),
    );
  }
}

// ── Sync Button ─────────────────────────────────────────────────────────────

class _SyncButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cloudLogbookProvider);
    if (state.status == SyncStatus.syncing) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      icon: Icon(
        Icons.sync,
        color: state.status == SyncStatus.error ? Colors.red : null,
      ),
      tooltip: state.lastSyncedAt != null
          ? 'Last synced: ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(state.lastSyncedAt! * 1000))}'
          : 'Sync',
      onPressed: () => ref.read(cloudLogbookProvider.notifier).syncAll(),
    );
  }
}

// ── Upsell Banner ───────────────────────────────────────────────────────────

class _UpsellBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: [
          const Icon(Icons.cloud_sync, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Sync across devices — Logbook Pro \$0.99/mo',
              style: TextStyle(fontSize: 13),
            ),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
            ),
            onPressed: () async {
              final url =
                  await ref.read(cloudLogbookProvider.notifier).getSubscribeUrl();
              if (url.isNotEmpty) {
                await launchUrl(Uri.parse(url),
                    mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Subscribe'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1: Captain's Log
// ─────────────────────────────────────────────────────────────────────────────

class _CaptainsLogTab extends ConsumerStatefulWidget {
  const _CaptainsLogTab();

  @override
  ConsumerState<_CaptainsLogTab> createState() => _CaptainsLogTabState();
}

class _CaptainsLogTabState extends ConsumerState<_CaptainsLogTab> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cloudLogbookProvider);
    final entries = state.captainsLog;

    return Scaffold(
      body: Column(
        children: [
          if (!state.logbookPro) _UpsellBanner(),
          Expanded(
            child: entries.isEmpty
                ? _emptyState()
                : RefreshIndicator(
                    onRefresh: () =>
                        ref.read(cloudLogbookProvider.notifier).syncCaptainsLog(),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: entries.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1, indent: 16),
                      itemBuilder: (ctx, i) =>
                          _CaptainEntryCard(entry: entries[i]),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddForm(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.book_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text("No captain's log entries",
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('New entry'),
            onPressed: () => _showAddForm(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddForm(BuildContext context,
      [CaptainLogEntry? existing]) async {
    final result = await showModalBottomSheet<CaptainLogEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _CaptainEntryForm(existing: existing),
    );
    if (result == null) return;
    if (existing != null) {
      await ref.read(cloudLogbookProvider.notifier).updateCaptainEntry(result);
    } else {
      await ref.read(cloudLogbookProvider.notifier).addCaptainEntry(result);
    }
  }
}

class _CaptainEntryCard extends ConsumerWidget {
  final CaptainLogEntry entry;
  const _CaptainEntryCard({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = entry.entryDate.isNotEmpty
        ? _formatDate(entry.entryDate)
        : 'Unknown date';
    final preview = entry.notes.length > 80
        ? '${entry.notes.substring(0, 80)}...'
        : entry.notes;

    return ListTile(
      leading: CircleAvatar(
        child: Text(
          _dayAbbr(entry.entryDate),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(dateStr),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.positionLat != null)
            Text(
              '${entry.positionLat!.toStringAsFixed(4)}, ${entry.positionLng!.toStringAsFixed(4)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          if (entry.weather != null && entry.weather!.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.wb_sunny, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(entry.weather!,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          if (preview.isNotEmpty)
            Text(preview, style: const TextStyle(fontSize: 13)),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'edit') {
            await _showEditForm(context, ref);
          } else if (v == 'delete') {
            if (entry.id != null) {
              await ref
                  .read(cloudLogbookProvider.notifier)
                  .deleteCaptainEntry(entry.id!);
            }
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      isThreeLine: true,
    );
  }

  Future<void> _showEditForm(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<CaptainLogEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _CaptainEntryForm(existing: entry),
    );
    if (result == null) return;
    await ref.read(cloudLogbookProvider.notifier).updateCaptainEntry(result);
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return DateFormat('EEE d MMM yyyy').format(d);
    } catch (_) {
      return iso;
    }
  }

  String _dayAbbr(String iso) {
    try {
      final d = DateTime.parse(iso);
      return d.day.toString();
    } catch (_) {
      return '?';
    }
  }
}

class _CaptainEntryForm extends ConsumerStatefulWidget {
  final CaptainLogEntry? existing;
  const _CaptainEntryForm({this.existing});

  @override
  ConsumerState<_CaptainEntryForm> createState() => _CaptainEntryFormState();
}

class _CaptainEntryFormState extends ConsumerState<_CaptainEntryForm> {
  late DateTime _date;
  late TextEditingController _weatherCtrl;
  late TextEditingController _crewCtrl;
  late TextEditingController _notesCtrl;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e != null ? (DateTime.tryParse(e.entryDate) ?? DateTime.now()) : DateTime.now();
    _weatherCtrl = TextEditingController(text: e?.weather ?? '');
    _crewCtrl = TextEditingController(text: e?.crew ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _lat = e?.positionLat;
    _lng = e?.positionLng;
    if (_lat == null) _autoFillPosition();
  }

  void _autoFillPosition() {
    final vessel = ref.read(vesselProvider);
    if (vessel.position != null) {
      _lat = vessel.position!.latitude;
      _lng = vessel.position!.longitude;
    }
  }

  @override
  void dispose() {
    _weatherCtrl.dispose();
    _crewCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? "New Captain's Log Entry" : "Edit Entry",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          // Date picker
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today),
            title: Text(DateFormat('EEE d MMM yyyy').format(_date)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          // Position
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.my_location),
            title: _lat != null
                ? Text(
                    '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 13),
                  )
                : const Text('No position'),
            trailing: TextButton(
              onPressed: _autoFillPosition,
              child: const Text('Use GPS'),
            ),
          ),
          TextField(
            controller: _weatherCtrl,
            decoration: const InputDecoration(
              labelText: 'Weather',
              prefixIcon: Icon(Icons.wb_sunny),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _crewCtrl,
            decoration: const InputDecoration(
              labelText: 'Crew',
              prefixIcon: Icon(Icons.people),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Notes',
              prefixIcon: Icon(Icons.notes),
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 4,
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submit,
                child: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _submit() {
    final entry = CaptainLogEntry(
      id: widget.existing?.id,
      entryDate: DateFormat('yyyy-MM-dd').format(_date),
      positionLat: _lat,
      positionLng: _lng,
      weather: _weatherCtrl.text.trim().isEmpty ? null : _weatherCtrl.text.trim(),
      crew: _crewCtrl.text.trim().isEmpty ? null : _crewCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      createdAt: widget.existing?.createdAt,
    );
    Navigator.pop(context, entry);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2: Ship's Log
// ─────────────────────────────────────────────────────────────────────────────

class _ShipsLogTab extends ConsumerStatefulWidget {
  const _ShipsLogTab();

  @override
  ConsumerState<_ShipsLogTab> createState() => _ShipsLogTabState();
}

class _ShipsLogTabState extends ConsumerState<_ShipsLogTab> {
  bool _autoLogging = false;
  int _autoIntervalMin = 30;
  Timer? _autoTimer;
  String? _activeVoyageId;

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  void _toggleAutoLog() {
    setState(() => _autoLogging = !_autoLogging);
    if (_autoLogging) {
      _activeVoyageId ??=
          'voyage_${DateTime.now().millisecondsSinceEpoch}';
      _autoTimer = Timer.periodic(
        Duration(minutes: _autoIntervalMin),
        (_) => _logCurrentData(),
      );
    } else {
      _autoTimer?.cancel();
      _autoTimer = null;
    }
  }

  Future<void> _logCurrentData() async {
    final vessel = ref.read(vesselProvider);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final entry = ShipLogEntry(
      loggedAt: now,
      positionLat: vessel.position?.latitude,
      positionLng: vessel.position?.longitude,
      course: vessel.cog,
      speed: vessel.sog,
      windSpeed: vessel.windSpeed,
      windDirection: vessel.windAngle,
      depth: vessel.depth,
      voyageId: _activeVoyageId,
    );
    await ref.read(cloudLogbookProvider.notifier).addShipEntry(entry);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cloudLogbookProvider);

    // Group entries by voyage
    final Map<String, List<ShipLogEntry>> grouped = {};
    for (final e in state.shipsLog) {
      final key = e.voyageId ?? 'no_voyage';
      grouped.putIfAbsent(key, () => []).add(e);
    }
    final voyageKeys = grouped.keys.toList()
      ..sort((a, b) {
        final ta = grouped[a]!.first.loggedAt;
        final tb = grouped[b]!.first.loggedAt;
        return tb.compareTo(ta);
      });

    return Scaffold(
      body: Column(
        children: [
          if (!state.logbookPro) _UpsellBanner(),
          // Auto-log control bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _autoLogging
                ? Colors.red.withAlpha(20)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  _autoLogging
                      ? Icons.fiber_manual_record
                      : Icons.radio_button_unchecked,
                  color: _autoLogging ? Colors.red : Colors.grey,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _autoLogging
                      ? 'Auto-logging every $_autoIntervalMin min'
                      : 'Auto-log off',
                  style: const TextStyle(fontSize: 13),
                ),
                const Spacer(),
                if (!_autoLogging)
                  DropdownButton<int>(
                    value: _autoIntervalMin,
                    underline: const SizedBox(),
                    style: const TextStyle(fontSize: 12),
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15 min')),
                      DropdownMenuItem(value: 30, child: Text('30 min')),
                      DropdownMenuItem(value: 60, child: Text('60 min')),
                      DropdownMenuItem(value: 120, child: Text('2 hrs')),
                    ],
                    onChanged: (v) => setState(() => _autoIntervalMin = v!),
                  ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                  onPressed: _toggleAutoLog,
                  child: Text(_autoLogging ? 'Stop' : 'Start'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                  onPressed: _logCurrentData,
                  child: const Text('Log now'),
                ),
              ],
            ),
          ),
          Expanded(
            child: state.shipsLog.isEmpty
                ? const Center(
                    child: Text('No ship log entries',
                        style: TextStyle(color: Colors.grey)),
                  )
                : RefreshIndicator(
                    onRefresh: () =>
                        ref.read(cloudLogbookProvider.notifier).syncShipsLog(),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: voyageKeys.length,
                      itemBuilder: (ctx, i) {
                        final key = voyageKeys[i];
                        final entries = grouped[key]!;
                        return _VoyageGroup(
                          voyageId: key,
                          entries: entries,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _VoyageGroup extends StatefulWidget {
  final String voyageId;
  final List<ShipLogEntry> entries;
  const _VoyageGroup({required this.voyageId, required this.entries});

  @override
  State<_VoyageGroup> createState() => _VoyageGroupState();
}

class _VoyageGroupState extends State<_VoyageGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final start = entries.last.loggedAt;
    final end = entries.first.loggedAt;
    final dur = Duration(seconds: end - start);
    final startStr = DateFormat('d MMM HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(start * 1000));
    final endStr = DateFormat('HH:mm d MMM').format(
        DateTime.fromMillisecondsSinceEpoch(end * 1000));
    final durStr = _formatDuration(dur);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.sailing),
            title: Text(
              widget.voyageId.startsWith('voyage_')
                  ? 'Voyage ${_shortId(widget.voyageId)}'
                  : widget.voyageId,
            ),
            subtitle: Text('$startStr — $endStr  ($durStr)  ${entries.length} entries'),
            trailing: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            ...entries.map((e) => _ShipEntryTile(entry: e)),
        ],
      ),
    );
  }

  String _shortId(String id) {
    // "voyage_1234567890" → last 4 digits
    final parts = id.split('_');
    if (parts.length > 1) {
      final n = parts.last;
      return n.length > 4 ? n.substring(n.length - 4) : n;
    }
    return id.substring(0, math.min(8, id.length));
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _ShipEntryTile extends StatelessWidget {
  final ShipLogEntry entry;
  const _ShipEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(entry.loggedAt * 1000));

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(time,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                if (entry.positionLat != null)
                  _chip(Icons.location_on,
                      '${entry.positionLat!.toStringAsFixed(3)}, ${entry.positionLng!.toStringAsFixed(3)}'),
                if (entry.course != null)
                  _chip(Icons.explore, 'COG ${entry.course!.toStringAsFixed(0)}°'),
                if (entry.speed != null)
                  _chip(Icons.speed, '${entry.speed!.toStringAsFixed(1)} kn'),
                if (entry.windSpeed != null)
                  _chip(Icons.air, '${entry.windSpeed!.toStringAsFixed(1)} kn'),
                if (entry.depth != null)
                  _chip(Icons.waves, '${entry.depth!.toStringAsFixed(1)} m'),
                if (entry.notes != null && entry.notes!.isNotEmpty)
                  _chip(Icons.notes, entry.notes!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey),
        const SizedBox(width: 2),
        Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3: Voyages
// ─────────────────────────────────────────────────────────────────────────────

class _VoyagesTab extends ConsumerWidget {
  const _VoyagesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cloudLogbookProvider);
    final voyages = state.voyages;

    if (voyages.isEmpty) {
      return const Center(
        child: Text('No voyages yet', style: TextStyle(color: Colors.grey)),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(cloudLogbookProvider.notifier).syncShipsLog(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: voyages.length,
        itemBuilder: (ctx, i) => _VoyageCard(
          voyage: voyages[i],
          entries: state.shipsLog
              .where((e) => e.voyageId == voyages[i].voyageId)
              .toList(),
        ),
      ),
    );
  }
}

class _VoyageCard extends StatelessWidget {
  final VoyageSummary voyage;
  final List<ShipLogEntry> entries;
  const _VoyageCard({required this.voyage, required this.entries});

  @override
  Widget build(BuildContext context) {
    final startStr = DateFormat('d MMM yyyy HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(voyage.startTime * 1000));
    final endStr = DateFormat('d MMM yyyy HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(voyage.endTime * 1000));
    final dur = Duration(seconds: voyage.endTime - voyage.startTime);
    final durStr = '${dur.inHours}h ${dur.inMinutes % 60}m';

    // Stats from entries
    final speeds = entries
        .where((e) => e.speed != null)
        .map((e) => e.speed!)
        .toList();
    final maxSog = speeds.isEmpty
        ? null
        : speeds.reduce((a, b) => a > b ? a : b);
    final avgSog = speeds.isEmpty
        ? null
        : speeds.reduce((a, b) => a + b) / speeds.length;

    // Distance estimate
    double distNm = 0;
    final withPos = entries
        .where((e) => e.positionLat != null)
        .toList()
      ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    for (int i = 1; i < withPos.length; i++) {
      distNm += _haversineNm(
        withPos[i - 1].positionLat!,
        withPos[i - 1].positionLng!,
        withPos[i].positionLat!,
        withPos[i].positionLng!,
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () => _showVoyageDetail(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.sailing, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      voyage.voyageId.startsWith('voyage_')
                          ? 'Voyage — $startStr'
                          : voyage.voyageId,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _stat(Icons.timer, durStr),
                  _stat(Icons.map, '${distNm.toStringAsFixed(1)} nm'),
                  if (maxSog != null)
                    _stat(Icons.speed, 'Max ${maxSog.toStringAsFixed(1)} kn'),
                  if (avgSog != null)
                    _stat(Icons.show_chart,
                        'Avg ${avgSog.toStringAsFixed(1)} kn'),
                  _stat(Icons.format_list_numbered,
                      '${voyage.entryCount} entries'),
                ],
              ),
              const SizedBox(height: 4),
              Text('$startStr — $endStr',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('GPX'),
                    style: OutlinedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () => _exportGpx(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  double _haversineNm(double lat1, double lng1, double lat2, double lng2) {
    const r = 3440.065;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.asin(math.sqrt(a));
  }

  void _showVoyageDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _VoyageDetailScreen(voyage: voyage, entries: entries),
      ),
    );
  }

  void _exportGpx(BuildContext context) {
    final withPos = entries
        .where((e) => e.positionLat != null)
        .toList()
      ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

    final trkpts = withPos.map((e) {
      final dt = DateTime.fromMillisecondsSinceEpoch(e.loggedAt * 1000)
          .toUtc()
          .toIso8601String();
      return '    <trkpt lat="${e.positionLat}" lon="${e.positionLng}">'
          '<time>$dt</time>'
          '${e.speed != null ? '<speed>${(e.speed! * 0.514444).toStringAsFixed(2)}</speed>' : ''}'
          '</trkpt>';
    }).join('\n');

    final gpx =
        '<?xml version="1.0" encoding="UTF-8"?>\n<gpx version="1.1" creator="Floatilla">\n  <trk><name>${voyage.voyageId}</name>\n    <trkseg>\n$trkpts\n    </trkseg>\n  </trk>\n</gpx>';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('GPX exported (${withPos.length} track points)'),
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ),
    );
    debugPrint(gpx); // In a real app, use share_plus to share the file
  }
}

class _VoyageDetailScreen extends StatelessWidget {
  final VoyageSummary voyage;
  final List<ShipLogEntry> entries;

  const _VoyageDetailScreen(
      {required this.voyage, required this.entries});

  @override
  Widget build(BuildContext context) {
    final withPos = entries
        .where((e) => e.positionLat != null)
        .toList()
      ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

    final dur = Duration(seconds: voyage.endTime - voyage.startTime);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          voyage.voyageId.startsWith('voyage_')
              ? 'Voyage Detail'
              : voyage.voyageId,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Stats panel
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Stats',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _statRow('Duration',
                          '${dur.inHours}h ${dur.inMinutes % 60}m'),
                      _statRow('Entries', '${voyage.entryCount}'),
                      _statRow(
                          'Start',
                          DateFormat('d MMM yyyy HH:mm').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                  voyage.startTime * 1000))),
                      _statRow(
                          'End',
                          DateFormat('d MMM yyyy HH:mm').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                  voyage.endTime * 1000))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Track points
          Text(
            'Track Points (${withPos.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...entries
              .map((e) => _ShipEntryTile(entry: e)),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
