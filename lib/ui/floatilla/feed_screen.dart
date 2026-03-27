import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../core/floatilla/floatilla_models.dart';
import '../../core/floatilla/floatilla_service.dart';
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
  bool _sending = false;
  bool _sharingLocation = false; // for one-tap "share my location" post

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);

    final service = ref.read(floatillaServiceProvider);
    final vessel = ref.read(vesselProvider);
    final pos = _sharePosition ? vessel.position : null;

    final ok = await service.sendMessage(text, position: pos);
    if (mounted) {
      setState(() => _sending = false);
      if (ok) {
        _textController.clear();
        setState(() => _sharePosition = false);
        ref.read(messagesProvider.notifier).refresh();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send')),
        );
      }
    }
  }

  Future<void> _shareLocationPost() async {
    final vessel = ref.read(vesselProvider);
    if (vessel.position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No GPS position available')),
      );
      return;
    }
    setState(() => _sharingLocation = true);
    try {
      final service = ref.read(floatillaServiceProvider);
      final pos = vessel.position!;
      final sog = vessel.sog;
      final cog = vessel.cog;
      final sogStr = sog != null ? ' · ${sog.toStringAsFixed(1)} kn' : '';
      final cogStr = cog != null ? ' · ${cog.toStringAsFixed(0)}°' : '';
      final text = '📍 Sharing my position$sogStr$cogStr';
      await service.sendMessage(text, position: pos);
      // Also update server location
      await service.updateLocation(pos, sog ?? 0, cog ?? 0);
      if (mounted) ref.read(messagesProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _sharingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider);
    final vessel = ref.watch(vesselProvider);

    return Column(
      children: [
        // ── Location sharing banner ──
        if (FloatillaService.instance.isLoggedIn())
          _LocationBanner(
            position: vessel.position,
            sog: vessel.sog,
            cog: vessel.cog,
            onShare: _shareLocationPost,
            sharing: _sharingLocation,
          ),

        // ── Feed ──
        Expanded(
          child: messages.when(
            data: (list) => list.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.anchor, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No messages yet',
                            style: TextStyle(color: Colors.grey)),
                        SizedBox(height: 4),
                        Text('Be the first to post',
                            style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () =>
                        ref.read(messagesProvider.notifier).refresh(),
                    child: ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: list.length,
                      itemBuilder: (ctx, i) =>
                          _MessageTile(message: list[i]),
                    ),
                  ),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Error: $e')),
          ),
        ),
        const Divider(height: 1),
        _buildComposer(context),
      ],
    );
  }

  Widget _buildComposer(BuildContext context) {
    final charCount = _textController.text.length;
    final vessel = ref.watch(vesselProvider);
    final hasPos = vessel.position != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Location toggle
                Tooltip(
                  message: _sharePosition
                      ? 'Position will be attached'
                      : 'Tap to attach your position',
                  child: IconButton(
                    icon: Icon(
                      _sharePosition ? Icons.location_on : Icons.location_off,
                      color: _sharePosition
                          ? Theme.of(context).colorScheme.primary
                          : hasPos
                              ? null
                              : Colors.grey,
                    ),
                    onPressed: hasPos
                        ? () =>
                            setState(() => _sharePosition = !_sharePosition)
                        : null,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    maxLength: 280,
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Message your fleet…',
                      border: const OutlineInputBorder(),
                      counterText: '$charCount/280',
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send),
                  onPressed:
                      _textController.text.trim().isEmpty || _sending
                          ? null
                          : _send,
                ),
              ],
            ),
            if (_sharePosition && vessel.position != null)
              Padding(
                padding: const EdgeInsets.only(left: 48, top: 2),
                child: Text(
                  '📍 ${vessel.position!.latitude.toStringAsFixed(4)}, '
                  '${vessel.position!.longitude.toStringAsFixed(4)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Location sharing banner ─────────────────────────────────────────────────

class _LocationBanner extends StatelessWidget {
  final LatLng? position;
  final double? sog;
  final double? cog;
  final VoidCallback onShare;
  final bool sharing;

  const _LocationBanner({
    required this.position,
    required this.sog,
    required this.cog,
    required this.onShare,
    required this.sharing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPos = position != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: hasPos
            ? cs.primaryContainer.withOpacity(0.35)
            : cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasPos ? cs.primary.withOpacity(0.3) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasPos ? Icons.my_location : Icons.location_searching,
            size: 18,
            color: hasPos ? cs.primary : Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: hasPos
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${position!.latitude.toStringAsFixed(4)}, '
                        '${position!.longitude.toStringAsFixed(4)}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      if (sog != null)
                        Text(
                          '${sog!.toStringAsFixed(1)} kn'
                          '${cog != null ? '  ${cog!.toStringAsFixed(0)}°' : ''}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  )
                : const Text(
                    'No GPS fix',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
          ),
          FilledButton.tonal(
            onPressed: hasPos && !sharing ? onShare : null,
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: sharing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Share location'),
          ),
        ],
      ),
    );
  }
}

// ── Message tile ────────────────────────────────────────────────────────────

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
                if (message.position != null) ...[
                  const SizedBox(height: 3),
                  GestureDetector(
                    onTap: () {
                      final pos = message.position!;
                      final url =
                          'https://www.google.com/maps?q=${pos.latitude},${pos.longitude}';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${pos.latitude.toStringAsFixed(4)}, '
                            '${pos.longitude.toStringAsFixed(4)}',
                          ),
                          action: SnackBarAction(
                            label: 'Copy',
                            onPressed: () {
                              // copy to clipboard
                            },
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withOpacity(0.4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.place,
                              size: 12,
                              color:
                                  Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${message.position!.latitude.toStringAsFixed(4)}, '
                            '${message.position!.longitude.toStringAsFixed(4)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
