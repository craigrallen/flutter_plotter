import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/nmea/nmea_stream.dart';
import '../../data/providers/nmea_config_provider.dart';

/// NMEA Multiplexer UI — view, filter, and log all NMEA sentences in real-time.
class NmeaMuxScreen extends ConsumerStatefulWidget {
  const NmeaMuxScreen({super.key});

  @override
  ConsumerState<NmeaMuxScreen> createState() => _NmeaMuxScreenState();
}

class _NmeaMuxState {
  final String sentence;
  final String talker;
  final String type;
  final DateTime timestamp;
  final bool isValid;

  _NmeaMuxState({
    required this.sentence,
    required this.talker,
    required this.type,
    required this.timestamp,
    required this.isValid,
  });
}

class _NmeaMuxScreenState extends ConsumerState<NmeaMuxScreen> {
  final List<_NmeaMuxState> _sentences = [];
  final _maxSentences = 500;
  bool _paused = false;
  bool _autoScroll = true;
  final _scrollController = ScrollController();
  final _filterCtrl = TextEditingController();
  String _filter = '';
  String? _typeFilter; // e.g. 'RMC', 'GLL', 'VTG'
  bool _showValid = true;
  bool _showInvalid = true;
  int _totalReceived = 0;
  final _talkerStats = <String, int>{};

  static const _knownTypes = [
    'ALL', 'RMC', 'GGA', 'GLL', 'VTG', 'HDT', 'HDM', 'MWV', 'DBT', 'VDM',
    'VDO', 'RSA', 'XTE', 'BOD', 'BWC', 'APB', 'RTE'
  ];

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  void _startListening() {
    final stream = ref.read(nmeaStreamProvider);
    stream.sentences.listen((sentence) {
      if (_paused) return;
      _processSentence(sentence);
    });
  }

  void _processSentence(String sentence) {
    if (!mounted) return;
    _totalReceived++;

    final trimmed = sentence.trim();
    if (trimmed.isEmpty) return;

    // Parse talker + type
    String talker = '??';
    String type = '???';
    bool isValid = false;

    if (trimmed.startsWith('\$') || trimmed.startsWith('!')) {
      final body = trimmed.substring(1);
      final parts = body.split(',');
      if (parts.isNotEmpty) {
        final tag = parts[0];
        if (tag.length >= 5) {
          talker = tag.substring(0, 2);
          type = tag.substring(2);
        } else if (tag.length >= 3) {
          talker = '??';
          type = tag;
        }
      }
      // Validate checksum
      final starIdx = trimmed.lastIndexOf('*');
      if (starIdx > 0 && starIdx < trimmed.length - 2) {
        final checkStr = trimmed.substring(starIdx + 1, starIdx + 3);
        final checkVal = int.tryParse(checkStr, radix: 16);
        if (checkVal != null) {
          int xor = 0;
          for (int i = 1; i < starIdx; i++) {
            xor ^= trimmed.codeUnitAt(i);
          }
          isValid = (xor == checkVal);
        }
      }
    }

    // Update talker stats
    _talkerStats[talker] = (_talkerStats[talker] ?? 0) + 1;

    final entry = _NmeaMuxState(
      sentence: trimmed,
      talker: talker,
      type: type,
      timestamp: DateTime.now(),
      isValid: isValid,
    );

    setState(() {
      _sentences.insert(0, entry);
      if (_sentences.length > _maxSentences) {
        _sentences.removeRange(_maxSentences, _sentences.length);
      }
    });
  }

  List<_NmeaMuxState> get _filtered {
    return _sentences.where((s) {
      if (!_showValid && s.isValid) return false;
      if (!_showInvalid && !s.isValid) return false;
      if (_typeFilter != null && _typeFilter != 'ALL') {
        if (s.type != _typeFilter) return false;
      }
      if (_filter.isNotEmpty) {
        return s.sentence.toLowerCase().contains(_filter.toLowerCase());
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(nmeaConnectionStateProvider);
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NMEA Multiplexer'),
        actions: [
          // Pause/resume
          IconButton(
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
            tooltip: _paused ? 'Resume' : 'Pause',
            onPressed: () => setState(() => _paused = !_paused),
          ),
          // Clear
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear',
            onPressed: () => setState(() {
              _sentences.clear();
              _talkerStats.clear();
              _totalReceived = 0;
            }),
          ),
          // Copy all
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all',
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: filtered.map((s) => s.sentence).join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection status + stats
          _buildHeader(connState),

          // Filter bar
          _buildFilterBar(),

          // Sentences list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cable,
                            size: 48,
                            color: Colors.grey.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        Text(
                          _sentences.isEmpty
                              ? 'No NMEA sentences received\nConnect to a source in Settings'
                              : 'No sentences match current filter',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) =>
                        _SentenceTile(entry: filtered[i]),
                  ),
          ),

          // Talker stats bar
          if (_talkerStats.isNotEmpty) _buildTalkerStats(),
        ],
      ),
    );
  }

  Widget _buildHeader(AsyncValue<NmeaConnectionState> connState) {
    final connected = connState.value == NmeaConnectionState.connected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: connected
          ? Colors.green.withOpacity(0.1)
          : Colors.grey.withOpacity(0.05),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            connected ? 'Connected' : 'Disconnected',
            style: TextStyle(
                fontSize: 13,
                color: connected ? Colors.green : Colors.grey),
          ),
          const Spacer(),
          Text(
            'Total: $_totalReceived  Showing: ${_filtered.length}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (_paused) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('PAUSED',
                  style: TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(
        children: [
          // Type filter
          SizedBox(
            width: 90,
            child: DropdownButtonFormField<String>(
              value: _typeFilter ?? 'ALL',
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
              items: _knownTypes
                  .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t,
                          style: const TextStyle(fontSize: 12))))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _typeFilter = v == 'ALL' ? null : v),
            ),
          ),
          const SizedBox(width: 8),
          // Text search
          Expanded(
            child: TextField(
              controller: _filterCtrl,
              decoration: InputDecoration(
                hintText: 'Search sentences...',
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _filterCtrl.clear();
                          setState(() => _filter = '');
                        })
                    : null,
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          const SizedBox(width: 6),
          // Valid/invalid toggles
          _FilterChip(
              label: '✓',
              active: _showValid,
              color: Colors.green,
              onTap: () => setState(() => _showValid = !_showValid)),
          const SizedBox(width: 4),
          _FilterChip(
              label: '✗',
              active: _showInvalid,
              color: Colors.red,
              onTap: () => setState(() => _showInvalid = !_showInvalid)),
        ],
      ),
    );
  }

  Widget _buildTalkerStats() {
    final sorted = _talkerStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      height: 32,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: sorted
            .map((e) => Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${e.key}: ${e.value}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.2) : Colors.transparent,
          border: Border.all(
              color: active ? color : Colors.grey.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? color : Colors.grey, fontSize: 13)),
      ),
    );
  }
}

class _SentenceTile extends StatelessWidget {
  final _NmeaMuxState entry;

  const _SentenceTile({required this.entry});

  static final _timeFmt = DateFormat('HH:mm:ss.SSS');

  @override
  Widget build(BuildContext context) {
    final typeColor = _typeColor(entry.type);
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: entry.sentence));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Copied'),
              duration: Duration(seconds: 1)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time
            SizedBox(
              width: 90,
              child: Text(
                _timeFmt.format(entry.timestamp),
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontFamily: 'monospace'),
              ),
            ),
            // Type badge
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                entry.type,
                style: TextStyle(
                    fontSize: 10,
                    color: typeColor,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Sentence
            Expanded(
              child: Text(
                entry.sentence,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: entry.isValid ? null : Colors.red.shade300,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Valid indicator
            Icon(
              entry.isValid ? Icons.check_circle : Icons.error_outline,
              size: 12,
              color: entry.isValid
                  ? Colors.green.withOpacity(0.6)
                  : Colors.red.withOpacity(0.6),
            ),
          ],
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'RMC':
      case 'GGA':
      case 'GLL':
        return Colors.blue;
      case 'VTG':
      case 'HDT':
      case 'HDM':
        return Colors.green;
      case 'MWV':
        return Colors.cyan;
      case 'DBT':
      case 'DPT':
        return Colors.teal;
      case 'VDM':
      case 'VDO':
        return Colors.orange;
      case 'XTE':
      case 'BOD':
      case 'BWC':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
