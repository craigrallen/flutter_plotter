import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/floatilla/floatilla_service.dart';
import '../../core/utils/error_handler.dart';

class PassageBriefingScreen extends StatefulWidget {
  const PassageBriefingScreen({super.key});

  @override
  State<PassageBriefingScreen> createState() => _PassageBriefingScreenState();
}

class _PassageBriefingScreenState extends State<PassageBriefingScreen> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _speedCtrl = TextEditingController(text: '6');

  DateTime _departureTime = DateTime.now().add(const Duration(hours: 2));
  bool _loading = false;
  String _briefingText = '';
  String? _error;

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _speedCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDeparture() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _departureTime,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departureTime),
    );
    if (time == null || !mounted) return;
    setState(() {
      _departureTime = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _getBriefing() async {
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();
    if (from.isEmpty || to.isEmpty) {
      setState(() => _error = 'Enter departure and destination');
      return;
    }
    final speed = double.tryParse(_speedCtrl.text.trim()) ?? 6.0;

    setState(() {
      _loading = true;
      _briefingText = '';
      _error = null;
    });

    final service = FloatillaService.instance;
    final token = service.token;

    try {
      final uri = Uri.parse('${service.baseUrl}/passage/briefing');
      final request = http.Request('POST', uri);
      request.headers['Content-Type'] = 'application/json';
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.body = jsonEncode(<String, dynamic>{
        'from': {'name': from, 'lat': 0.0, 'lng': 0.0},
        'to': {'name': to, 'lat': 0.0, 'lng': 0.0},
        'departureTime': _departureTime.toIso8601String(),
        'vesselSpeedKn': speed,
      });

      final streamed = await request.send();

      if (streamed.statusCode == 200) {
        final contentType = streamed.headers['content-type'] ?? '';

        if (contentType.contains('event-stream')) {
          // SSE streaming
          final buffer = StringBuffer();
          await for (final chunk
              in streamed.stream.transform(utf8.decoder)) {
            for (final line in chunk.split('\n')) {
              if (line.startsWith('data: ')) {
                final data = line.substring(6).trim();
                if (data == '[DONE]') break;
                try {
                  final json =
                      jsonDecode(data) as Map<String, dynamic>;
                  final text = json['text'] as String? ?? '';
                  buffer.write(text);
                  if (mounted) {
                    setState(() => _briefingText = buffer.toString());
                  }
                } catch (e) { logError('PassageBriefingScreen.streamParse', e); }
              }
            }
          }
        } else {
          // JSON fallback
          final body = await streamed.stream.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          final text = json['briefing'] as String? ?? body;
          setState(() => _briefingText = text);
        }

        // Save to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final key = 'briefing_${from}_$to'.replaceAll(' ', '_');
        await prefs.setString(key, _briefingText);
      } else {
        final body =
            await streamed.stream.transform(utf8.decoder).join();
        setState(() => _error = 'Server error ${streamed.statusCode}: $body');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _briefingText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Briefing copied to clipboard')),
    );
  }

  void _share() {
    Share.share(_briefingText, subject: 'Passage Briefing');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Passage Briefing')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 600;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 320,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildInputForm(context),
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildBriefingPanel(context),
                  ),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInputForm(context),
                const SizedBox(height: 16),
                _buildBriefingPanel(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputForm(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Passage Details',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _fromCtrl,
              decoration: const InputDecoration(
                labelText: 'From (place or lat,lng)',
                prefixIcon: Icon(Icons.my_location),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _toCtrl,
              decoration: const InputDecoration(
                labelText: 'To (place or lat,lng)',
                prefixIcon: Icon(Icons.flag),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text(
                'Departure: ${_departureTime.day}/${_departureTime.month}/${_departureTime.year} '
                '${_departureTime.hour.toString().padLeft(2, '0')}:'
                '${_departureTime.minute.toString().padLeft(2, '0')}',
              ),
              onPressed: _pickDeparture,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _speedCtrl,
              decoration: const InputDecoration(
                labelText: 'Vessel Speed (kn)',
                prefixIcon: Icon(Icons.speed),
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
            FilledButton.icon(
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_loading ? 'Getting briefing...' : 'Get Briefing'),
              onPressed: _loading ? null : _getBriefing,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBriefingPanel(BuildContext context) {
    if (_briefingText.isEmpty && !_loading) {
      return Card(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.4),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.auto_awesome, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'Enter your passage details and tap Get Briefing.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (_briefingText.isEmpty && _loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Passage Briefing',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy',
              onPressed: _briefingText.isNotEmpty ? _copy : null,
            ),
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share',
              onPressed: _briefingText.isNotEmpty ? _share : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _BriefingCard(
          icon: Icons.cloud,
          title: 'Weather Window',
          text: _extractSection(_briefingText, 'weather'),
          loading: _loading && _briefingText.isEmpty,
        ),
        const SizedBox(height: 8),
        _BriefingCard(
          icon: Icons.water,
          title: 'Tidal Constraints',
          text: _extractSection(_briefingText, 'tidal'),
          loading: _loading && _briefingText.isEmpty,
        ),
        const SizedBox(height: 8),
        _BriefingCard(
          icon: Icons.warning_amber,
          title: 'Route Hazards',
          text: _extractSection(_briefingText, 'hazard'),
          loading: _loading && _briefingText.isEmpty,
        ),
        const SizedBox(height: 8),
        _BriefingCard(
          icon: Icons.anchor,
          title: 'Recommended Anchorages',
          text: _extractSection(_briefingText, 'anchorage'),
          loading: _loading && _briefingText.isEmpty,
        ),
        const SizedBox(height: 8),
        _BriefingCard(
          icon: Icons.location_on,
          title: 'Key Waypoints',
          text: _extractSection(_briefingText, 'waypoint'),
          loading: _loading && _briefingText.isEmpty,
        ),
        const SizedBox(height: 8),
        _BriefingCard(
          icon: Icons.summarize,
          title: 'Summary',
          text: _extractSection(_briefingText, 'summary'),
          loading: _loading && _briefingText.isEmpty,
        ),
        const SizedBox(height: 8),
        // Full raw text card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.article, size: 18),
                    const SizedBox(width: 6),
                    Text('Full Briefing',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _briefingText,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Extracts a section from the briefing text by keyword.
  String _extractSection(String text, String keyword) {
    if (text.isEmpty) return '';
    final kw = keyword.toLowerCase();

    // Find the relevant paragraph/section
    final lines = text.split('\n');
    final result = StringBuffer();
    bool inSection = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineLower = line.toLowerCase();

      if (lineLower.contains(kw)) {
        inSection = true;
        result.writeln(line);
        continue;
      }

      if (inSection) {
        // Stop at next numbered heading or empty section boundary
        final isNewSection = RegExp(r'^\d+\.|^#{1,3} ').hasMatch(line.trim());
        if (isNewSection && !lineLower.contains(kw)) {
          inSection = false;
          continue;
        }
        if (line.trim().isNotEmpty || result.isNotEmpty) {
          result.writeln(line);
        }
        // Stop after a few lines of context
        if (result.toString().split('\n').length > 8) break;
      }
    }

    return result.toString().trim();
  }
}

class _BriefingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final bool loading;

  const _BriefingCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              )
            else if (text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(text,
                  style: const TextStyle(fontSize: 13, height: 1.4)),
            ] else ...[
              const SizedBox(height: 6),
              const Text('—',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}
