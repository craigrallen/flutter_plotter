import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/floatilla/floatilla_models.dart';
import '../../../data/providers/floatilla_provider.dart';

class FriendsLayer extends ConsumerWidget {
  const FriendsLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider);

    final visible = friends.valueOrNull?.where((f) {
          if (f.position == null) return false;
          if (f.lastSeen == null) return false;
          return DateTime.now().difference(f.lastSeen!).inMinutes < 30;
        }).toList() ??
        [];

    if (visible.isEmpty) return const SizedBox.shrink();

    return MarkerLayer(
      markers: visible.map((f) => _friendMarker(context, ref, f)).toList(),
    );
  }

  Marker _friendMarker(
      BuildContext context, WidgetRef ref, FloatillaUser friend) {
    return Marker(
      point: friend.position!,
      width: 36,
      height: 36,
      child: GestureDetector(
        onTap: () => _showFriendSheet(context, friend),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Center(
            child: Text(
              friend.vesselName.isNotEmpty
                  ? friend.vesselName[0].toUpperCase()
                  : friend.username[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showFriendSheet(BuildContext context, FloatillaUser friend) {
    final timeAgo = friend.lastSeen != null
        ? _timeAgo(friend.lastSeen!)
        : 'unknown';

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                friend.vesselName.isNotEmpty
                    ? friend.vesselName
                    : friend.username,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              if (friend.vesselName.isNotEmpty)
                Text('@${friend.username}',
                    style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text('Last update: $timeAgo',
                  style: Theme.of(ctx).textTheme.bodySmall),
              if (friend.position != null)
                Text(
                  '${friend.position!.latitude.toStringAsFixed(4)}, '
                  '${friend.position!.longitude.toStringAsFixed(4)}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.message),
                      label: const Text('Message'),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.route),
                      label: const Text('Route Here'),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
