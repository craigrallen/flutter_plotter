import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../core/floatilla/floatilla_service.dart';
import '../../core/floatilla/logbook_service.dart';
import '../../data/providers/floatilla_provider.dart';
import '../../data/providers/vessel_provider.dart';

class LogbookScreen extends ConsumerStatefulWidget {
  const LogbookScreen({super.key});

  @override
  ConsumerState<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends ConsumerState<LogbookScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  bool _autoLogging = false;
  int _selectedDays = 7;

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _autoLogging = LogbookService.instance.isLogging;
  }

  Future<void> _loadEntries() async {
    if (!FloatillaService.instance.isLoggedIn()) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final since = DateTime.now()
              .subtract(Duration(days: _selectedDays))
              .millisecondsSinceEpoch ~/
          1000;
      final resp = await http.get(
        Uri.parse(
            '${FloatillaService.instance.baseUrl}/logbook?since=$since&limit=500'),
        headers: {
          'Authorization': 'Bearer ${FloatillaService.instance.token}'
        },
      );
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        setState(() {
          _entries =
              list.map((e) => e as Map<String, dynamic>).toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addManualEntry() async {
    final vessel = ref.read(vesselProvider);
    if (vessel.position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No GPS position')),
      );
      return;
    }
    final noteCtrl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add logbook entry'),
        content: TextField(
          controller: noteCtrl,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, noteCtrl.text.trim()),
              child: const Text('Log entry')),
        ],
      ),
    );
    if (note == null) return;
    await LogbookService.instance.addManualEntry(
      pos: vessel.position!,
      note: note.isEmpty ? null : note,
      sog: vessel.sog,
      cog: vessel.cog,
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Entry logged')));
      _loadEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!FloatillaService.instance.isLoggedIn()) {
      return Scaffold(
        appBar: AppBar(title: const Text('Voyage Logbook')),
        body: const Center(
          child: Text('Log in to Floatilla to use the logbook'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voyage Logbook'),
        actions: [
          // Auto-log toggle
          IconButton(
            icon: Icon(
              _autoLogging ? Icons.fiber_manual_record : Icons.radio_button_unchecked,
              color: _autoLogging ? Colors.red : null,
            ),
            tooltip: _autoLogging ? 'Stop auto-logging' : 'Start auto-logging',
            onPressed: () {
              setState(() => _autoLogging = !_autoLogging);
              if (!_autoLogging) {
                LogbookService.instance.stopAutoLog();
              }
              // Start is handled by the provider wiring
            },
          ),
          // GPX export
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export GPX',
            onPressed: () => _showExportSheet(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withOpacity(0.3),
            child: Row(
              children: [
                _Stat(label: 'Entries', value: _entries.length.toString()),
                const SizedBox(width: 24),
                _Stat(
                    label: 'Distance',
                    value: '${_calcDistanceNm().toStringAsFixed(1)} nm'),
                const SizedBox(width: 24),
                _Stat(
                    label: 'Session',
                    value:
                        '${LogbookService.instance.entriesThisSession} pts'),
                const Spacer(),
                // Days filter
                DropdownButton<int>(
                  value: _selectedDays,
                  underline: const SizedBox(),
                  style: const TextStyle(fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('24h')),
                    DropdownMenuItem(value: 7, child: Text('7d')),
                    DropdownMenuItem(value: 30, child: Text('30d')),
                    DropdownMenuItem(value: 90, child: Text('90d')),
                  ],
                  onChanged: (v) {
                    setState(() => _selectedDays = v!);
                    _loadEntries();
                  },
                ),
              ],
            ),
          ),
          // Auto-log status
          if (_autoLogging)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.red.withOpacity(0.1),
              child: const Row(
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
                  SizedBox(width: 8),
                  Text(
                    'Auto-logging — recording track every minute',
                    style: TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ),
            ),
          // Entries list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.book_outlined,
                                size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            const Text('No logbook entries',
                                style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 6),
                            const Text(
                              'Enable auto-log or tap + to add an entry',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Add entry'),
                              onPressed: _addManualEntry,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadEntries,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _entries.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 56),
                          itemBuilder: (ctx, i) {
                            final e = _entries[i];
                            return _EntryTile(entry: e);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addManualEntry,
        child: const Icon(Icons.add),
      ),
    );
  }

  double _calcDistanceNm() {
    if (_entries.length < 2) return 0;
    double total = 0;
    for (int i = 1; i < _entries.length; i++) {
      final a = _entries[i];
      final b = _entries[i - 1];
      final dlat = ((b['lat'] as num) - (a['lat'] as num)).abs();
      final dlng = ((b['lng'] as num) - (a['lng'] as num)).abs();
      // rough distance in degrees → nm
      total += (dlat * dlat + dlng * dlng) * 3600;
    }
    return (total / 3600).clamp(0, 9999);
  }

  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Export Logbook',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Download GPX (7 days)'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('GPX URL copied'),
                      action: SnackBarAction(
                        label: 'Open',
                        onPressed: () {},
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Download GPX (30 days)'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700)),
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.grey)),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  final Map<String, dynamic> entry;

  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final ts = entry['created_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(
            (entry['created_at'] as num).toInt() * 1000)
        : DateTime.now();
    final timeStr = DateFormat('HH:mm').format(ts);
    final dateStr = DateFormat('MMM d').format(ts);
    final lat = (entry['lat'] as num?)?.toStringAsFixed(4) ?? '?';
    final lng = (entry['lng'] as num?)?.toStringAsFixed(4) ?? '?';
    final sog = entry['sog'] != null
        ? '${(entry['sog'] as num).toStringAsFixed(1)} kn'
        : null;
    final isManual = entry['entry_type'] == 'manual';

    return ListTile(
      leading: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(timeStr,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          Text(dateStr,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
      title: Text('$lat, $lng'),
      subtitle: Row(
        children: [
          if (sog != null) ...[
            Text(sog,
                style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
          ],
          if (isManual) ...[
            const Icon(Icons.edit, size: 12, color: Colors.blue),
            const SizedBox(width: 4),
          ],
          if (entry['note'] != null && entry['note'].toString().isNotEmpty)
            Expanded(
              child: Text(
                entry['note'].toString(),
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      trailing: entry['depth'] != null
          ? Text(
              '${(entry['depth'] as num).toStringAsFixed(1)}m',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            )
          : null,
    );
  }
}
