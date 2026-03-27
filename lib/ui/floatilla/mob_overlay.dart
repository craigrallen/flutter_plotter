import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/floatilla/floatilla_models.dart';
import '../../data/providers/floatilla_provider.dart';

class MobOverlay extends ConsumerWidget {
  const MobOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = ref.watch(mobAlertProvider);
    if (alert == null) return const SizedBox.shrink();

    return _MobAlertOverlay(
      alert: alert,
      onDismiss: () => ref.read(mobAlertProvider.notifier).state = null,
    );
  }
}

class _MobAlertOverlay extends StatefulWidget {
  final MobAlert alert;
  final VoidCallback onDismiss;

  const _MobAlertOverlay({required this.alert, required this.onDismiss});

  @override
  State<_MobAlertOverlay> createState() => _MobAlertOverlayState();
}

class _MobAlertOverlayState extends State<_MobAlertOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final opacity = 0.7 + 0.3 * _pulseController.value;
        return Container(
          color: Colors.red.withValues(alpha: opacity),
          child: child,
        );
      },
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning, color: Colors.white, size: 72),
                const SizedBox(height: 16),
                const Text(
                  'MAN OVERBOARD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.alert.vesselName.isNotEmpty
                      ? widget.alert.vesselName
                      : widget.alert.username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.alert.position.latitude.toStringAsFixed(5)}, '
                  '${widget.alert.position.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                  icon: const Icon(Icons.map),
                  label: const Text('View on Chart',
                      style: TextStyle(fontSize: 16)),
                  onPressed: widget.onDismiss,
                ),
                const SizedBox(height: 12),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  onPressed: widget.onDismiss,
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
