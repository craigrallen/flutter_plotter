import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/floatilla/floatilla_models.dart';
import '../../data/providers/floatilla_provider.dart';
import '../../data/providers/vessel_provider.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _textController = TextEditingController();
  bool _sharePosition = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final service = ref.read(floatillaServiceProvider);
    final vessel = ref.read(vesselProvider);
    final pos = _sharePosition ? vessel.position : null;

    final ok = await service.sendMessage(text, position: pos);
    if (ok && mounted) {
      _textController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider);

    return Column(
      children: [
        Expanded(
          child: messages.when(
            data: (list) => list.isEmpty
                ? const Center(child: Text('No messages yet'))
                : RefreshIndicator(
                    onRefresh: () =>
                        ref.read(messagesProvider.notifier).refresh(),
                    child: ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: list.length,
                      itemBuilder: (ctx, i) => _MessageTile(message: list[i]),
                    ),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
        const Divider(height: 1),
        _buildComposer(context),
      ],
    );
  }

  Widget _buildComposer(BuildContext context) {
    final charCount = _textController.text.length;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(
                _sharePosition ? Icons.location_on : Icons.location_off,
                color: _sharePosition
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: 'Share position',
              onPressed: () => setState(() => _sharePosition = !_sharePosition),
            ),
            Expanded(
              child: TextField(
                controller: _textController,
                maxLength: 280,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Message your fleet...',
                  border: const OutlineInputBorder(),
                  counterText: '$charCount/280',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: _textController.text.trim().isEmpty ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  final FloatillaMessage message;

  const _MessageTile({required this.message});

  @override
  Widget build(BuildContext context) {
    final timeAgo = _formatTimeAgo(message.createdAt);
    final initial = message.authorUsername.isNotEmpty
        ? message.authorUsername[0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            child: Text(initial),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      message.authorUsername,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeAgo,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (message.position != null) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.place,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(message.text),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat.MMMd().format(dt);
  }
}
