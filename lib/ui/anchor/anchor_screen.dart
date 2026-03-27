import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/anchor_provider.dart';
import '../../data/providers/vessel_provider.dart';

class AnchorScreen extends ConsumerWidget {
  const AnchorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchor = ref.watch(anchorProvider);
    final vessel = ref.watch(vesselProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Anchor Watch')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card.
            Card(
              color: anchor.isDragging
                  ? Colors.red.shade50
                  : anchor.isActive
                      ? Colors.green.shade50
                      : null,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.anchor,
                      size: 64,
                      color: anchor.isDragging
                          ? Colors.red
                          : anchor.isActive
                              ? Colors.green
                              : Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      anchor.isDragging
                          ? 'DRAGGING!'
                          : anchor.isActive
                              ? 'Anchor Set'
                              : 'No Anchor',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: anchor.isDragging
                                ? Colors.red
                                : anchor.isActive
                                    ? Colors.green
                                    : null,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (anchor.isActive && anchor.currentDistanceM != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Distance: ${anchor.currentDistanceM!.toStringAsFixed(1)} m',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Radius: ${anchor.radiusM.toStringAsFixed(0)} m',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Radius slider.
            if (anchor.isActive) ...[
              Text('Watch Radius: ${anchor.radiusM.toStringAsFixed(0)} m',
                  style: Theme.of(context).textTheme.titleMedium),
              Slider(
                value: anchor.radiusM,
                min: 10,
                max: 200,
                divisions: 19,
                label: '${anchor.radiusM.toStringAsFixed(0)} m',
                onChanged: (v) {
                  ref.read(anchorProvider.notifier).setRadius(v);
                },
              ),
            ],

            const Spacer(),

            // Set / Release button.
            if (!anchor.isActive)
              FilledButton.icon(
                onPressed: vessel.position != null
                    ? () {
                        ref.read(anchorProvider.notifier).dropAnchor();
                        Navigator.pop(context);
                      }
                    : null,
                icon: const Icon(Icons.anchor),
                label: const Text('Drop Anchor Here'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(anchorProvider.notifier).releaseAnchor();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.clear),
                label: const Text('Release Anchor'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  foregroundColor: Colors.red,
                ),
              ),

            if (anchor.dropPosition != null) ...[
              const SizedBox(height: 12),
              Text(
                'Anchor at: ${anchor.dropPosition!.latitude.toStringAsFixed(5)}, '
                '${anchor.dropPosition!.longitude.toStringAsFixed(5)}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
