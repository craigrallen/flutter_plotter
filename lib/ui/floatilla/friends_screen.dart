import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/floatilla/floatilla_models.dart';
import '../../core/floatilla/floatilla_service.dart';
import '../../data/providers/floatilla_provider.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  List<FloatillaFriendRequest> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (!FloatillaService.instance.isLoggedIn()) return;
    try {
      final reqs = await FloatillaService.instance.getFriendRequests();
      if (mounted) setState(() => _requests = reqs);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          ref.read(friendsProvider.notifier).refresh(),
          _loadRequests(),
        ]);
      },
      child: CustomScrollView(
        slivers: [
          // ── Search / add bar ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.search),
                      label: const Text('Find sailors'),
                      onPressed: () => _showSearchSheet(context),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Pending requests ──
          if (_requests.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Requests (${_requests.length})',
                icon: Icons.notifications_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _RequestTile(
                  request: _requests[i],
                  onAccepted: () async {
                    final ok = await FloatillaService.instance
                        .acceptFriendRequest(_requests[i].friendshipId.toString());
                    if (ok && mounted) {
                      await _loadRequests();
                      ref.read(friendsProvider.notifier).refresh();
                    }
                  },
                  onDeclined: () async {
                    // Remove the request (decline = remove)
                    await FloatillaService.instance
                        .removeFriend(int.parse(_requests[i].userId));
                    if (mounted) _loadRequests();
                  },
                ),
                childCount: _requests.length,
              ),
            ),
          ],

          // ── Friends list ──
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Your fleet',
              icon: Icons.sailing,
            ),
          ),
          friends.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: $e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red)),
              ),
            ),
            data: (list) => list.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 32, horizontal: 24),
                      child: Column(
                        children: [
                          const Icon(Icons.anchor, size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text('No friends yet',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: Colors.grey)),
                          const SizedBox(height: 6),
                          const Text(
                            'Tap "Find sailors" to search by username',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _FriendTile(
                        friend: list[i],
                        onRemove: () async {
                          final confirm = await _confirmRemove(
                              context, list[i].username);
                          if (confirm == true) {
                            final ok = await FloatillaService.instance
                                .removeFriend(int.parse(list[i].id));
                            if (ok) {
                              ref.read(friendsProvider.notifier).refresh();
                            }
                          }
                        },
                      ),
                      childCount: list.length,
                    ),
                  ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  void _showSearchSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => const _SearchSheet(),
    );
  }

  Future<bool?> _confirmRemove(BuildContext context, String username) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove friend'),
        content: Text('Remove @$username from your fleet?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? color;

  const _SectionHeader(
      {required this.title, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon,
              size: 16, color: color ?? Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: color ?? Theme.of(context).colorScheme.primary,
              )),
        ],
      ),
    );
  }
}

// ── Request tile ────────────────────────────────────────────────────────────

class _RequestTile extends StatelessWidget {
  final FloatillaFriendRequest request;
  final VoidCallback onAccepted;
  final VoidCallback onDeclined;

  const _RequestTile(
      {required this.request,
      required this.onAccepted,
      required this.onDeclined});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          request.username.isNotEmpty
              ? request.username[0].toUpperCase()
              : '?',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(request.vesselName.isNotEmpty
          ? request.vesselName
          : request.username),
      subtitle: Text('@${request.username}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.green),
            tooltip: 'Accept',
            onPressed: onAccepted,
          ),
          IconButton(
            icon: Icon(Icons.cancel, color: Colors.red.shade300),
            tooltip: 'Decline',
            onPressed: onDeclined,
          ),
        ],
      ),
    );
  }
}

// ── Friend tile ─────────────────────────────────────────────────────────────

class _FriendTile extends StatelessWidget {
  final FloatillaUser friend;
  final VoidCallback onRemove;

  const _FriendTile({required this.friend, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isOnline = friend.lastSeen != null &&
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
          if (isOnline)
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
      title: Text(
          friend.vesselName.isNotEmpty ? friend.vesselName : friend.username),
      subtitle: Text(friend.vesselName.isNotEmpty
          ? '@${friend.username} · ${isOnline ? 'online' : friend.lastSeen != null ? _timeAgo(friend.lastSeen!) : 'offline'}'
          : friend.lastSeen != null
              ? 'Last seen ${_timeAgo(friend.lastSeen!)}'
              : 'Offline'),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (val) {
          if (val == 'remove') onRemove();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'remove',
            child: Row(children: [
              Icon(Icons.person_remove, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Remove friend', style: TextStyle(color: Colors.red)),
            ]),
          ),
        ],
      ),
      onTap: () => _showDetail(context),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
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
                Text('Last seen ${_timeAgo(friend.lastSeen!)}',
                    style: Theme.of(ctx).textTheme.bodySmall),
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

// ── Search sheet ────────────────────────────────────────────────────────────

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet();

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final _ctrl = TextEditingController();
  String _status = '';
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final username = _ctrl.text.trim();
    if (username.isEmpty) return;
    setState(() {
      _loading = true;
      _status = '';
    });
    try {
      final ok =
          await FloatillaService.instance.sendFriendRequest(username);
      if (mounted) {
        setState(() => _status = ok
            ? 'Friend request sent to @$username'
            : 'Could not find @$username');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Find a sailor',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 4),
          const Text(
            'Enter their exact username to send a friend request.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_search),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _status.startsWith('Friend')
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _status.startsWith('Friend')
                      ? Colors.green.shade200
                      : Colors.red.shade200,
                ),
              ),
              child: Text(_status,
                  style: TextStyle(
                    fontSize: 13,
                    color: _status.startsWith('Friend')
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                  )),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.person_add),
            label: const Text('Send request'),
            onPressed: _loading ? null : _send,
          ),
        ],
      ),
    );
  }
}
