import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/nmea_config_provider.dart';

/// Scrolling raw NMEA sentence debug view.
class NmeaDebugScreen extends ConsumerStatefulWidget {
  const NmeaDebugScreen({super.key});

  @override
  ConsumerState<NmeaDebugScreen> createState() => _NmeaDebugScreenState();
}

class _NmeaDebugScreenState extends ConsumerState<NmeaDebugScreen> {
  final _sentences = <String>[];
  final _scrollController = ScrollController();
  StreamSubscription<String>? _sub;
  bool _autoScroll = true;

  static const _maxLines = 500;

  @override
  void initState() {
    super.initState();
    final stream = ref.read(nmeaStreamProvider);
    _sub = stream.sentences.listen((sentence) {
      if (!mounted) return;
      setState(() {
        _sentences.add(sentence);
        if (_sentences.length > _maxLines) {
          _sentences.removeAt(0);
        }
      });
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NMEA Debug'),
        actions: [
          IconButton(
            icon: Icon(_autoScroll ? Icons.lock : Icons.lock_open),
            tooltip: _autoScroll ? 'Auto-scroll on' : 'Auto-scroll off',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: () => setState(() => _sentences.clear()),
          ),
        ],
      ),
      body: _sentences.isEmpty
          ? const Center(child: Text('No NMEA data. Connect to a source.'))
          : ListView.builder(
              controller: _scrollController,
              itemCount: _sentences.length,
              itemBuilder: (_, i) {
                final s = _sentences[i];
                final color = _sentenceColor(s);
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  child: Text(
                    s,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: color,
                    ),
                  ),
                );
              },
            ),
    );
  }

  Color _sentenceColor(String s) {
    if (s.contains('VDM') || s.contains('VDO')) return Colors.orange;
    if (s.contains('RMC') || s.contains('GLL')) return Colors.green;
    if (s.contains('DBT')) return Colors.cyan;
    if (s.contains('MWV')) return Colors.teal;
    return Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;
  }
}
