import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/floatilla/floatilla_models.dart';
import '../../data/providers/floatilla_provider.dart';

class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider);

    return friends.when(
      data: (list) => _buildList(context, ref, list),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildList(
      BuildContext context, WidgetRef ref, List<FloatillaUser> friends) {
    return Column(
      children: [
        Expanded(
          child: friends.isEmpty
              ? const Center(child: Text('No friends yet'))
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(friendsProvider.notifier).refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: friends.length,
                    itemBuilder: (ctx, i) =>
                        _FriendTile(friend: friends[i]),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            icon: const Icon(Icons.person_add),
            label: const Text('Add Friend'),
            onPressed: () => _showAddFriendDialog(context, ref),
          ),
        ),
      ],
    );
  }

  void _showAddFriendDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Friend'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Username',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final username = controller.text.trim();
              if (username.isEmpty) return;
              final service = ref.read(floatillaServiceProvider);
              final ok = await service.sendFriendRequest(username);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Friend request sent to $username'
                        : 'Could not send request'),
                  ),
                );
              }
            },
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  final FloatillaUser friend;

  const _FriendTile({required this.friend});

  @override
  Widget build(BuildContext context) {
    final isRecent = friend.lastSeen != null &&
        DateTime.now().difference(friend.lastSeen!).inMinutes < 5;

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            child: Text(
              friend.vesselName.isNotEmpty
                  ? friend.vesselName[0].toUpperCase()
                  : friend.username[0].toUpperCase(),
            ),
          ),
          if (isRecent)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(friend.vesselName.isNotEmpty
          ? friend.vesselName
          : friend.username),
      subtitle: Text(
        friend.vesselName.isNotEmpty
            ? '@${friend.username}'
            : friend.lastSeen != null
                ? 'Last seen ${_timeAgo(friend.lastSeen!)}'
                : 'No position',
      ),
      trailing: friend.position != null
          ? Icon(Icons.place,
              color: Theme.of(context).colorScheme.primary, size: 20)
          : null,
      onTap: () => _showFriendDetail(context, friend),
    );
  }

  void _showFriendDetail(BuildContext context, FloatillaUser friend) {
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
              const SizedBox(height: 8),
              if (friend.position != null)
                Text(
                  '${friend.position!.latitude.toStringAsFixed(4)}, '
                  '${friend.position!.longitude.toStringAsFixed(4)}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              if (friend.lastSeen != null)
                Text(
                  'Last seen ${_timeAgo(friend.lastSeen!)}',
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
                  if (friend.position != null)
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
