import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/floatilla/floatilla_service.dart';
import '../../data/providers/floatilla_provider.dart';
import 'feed_screen.dart';
import 'floatilla_auth_screen.dart';
import 'friends_screen.dart';

class FloatillaShell extends ConsumerStatefulWidget {
  const FloatillaShell({super.key});

  @override
  ConsumerState<FloatillaShell> createState() => _FloatillaShellState();
}

class _FloatillaShellState extends ConsumerState<FloatillaShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = ref.watch(isLoggedInProvider);
    final messages = ref.watch(messagesProvider);
    final unreadCount = messages.valueOrNull?.length ?? 0;

    if (!loggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Floatilla')),
        body: const FloatillaAuthScreen(),
      );
    }

    final username = FloatillaService.instance.username;
    final vesselName = FloatillaService.instance.vesselName;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Floatilla'),
            if (username != null)
              Text(
                vesselName != null ? '$vesselName · @$username' : '@$username',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign out'),
                  content: const Text('Sign out of Floatilla?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sign out')),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                await FloatillaService.instance.logout();
                ref.read(isLoggedInProvider.notifier).state = false;
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Feed'),
                  if (unreadCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Friends'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          FeedScreen(),
          FriendsScreen(),
        ],
      ),
    );
  }
}
