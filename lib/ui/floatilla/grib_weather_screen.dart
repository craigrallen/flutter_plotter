import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../data/providers/weather_grib_provider.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class GribWeatherScreen extends ConsumerStatefulWidget {
  const GribWeatherScreen({super.key});

  @override
  ConsumerState<GribWeatherScreen> createState() => _GribWeatherScreenState();
}

class _GribWeatherScreenState extends ConsumerState<GribWeatherScreen> {
  final MapController _mapController = MapController();
  bool _controlsExpanded = true;

  @override
  void initState() {
    super.initState();
    // Try loading offline data on first open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(weatherGribProvider.notifier).loadOffline();
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  GribBounds _currentBounds() {
    try {
      final bounds = _mapController.camera.visibleBounds;
      return GribBounds(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
      );
    } catch (_) {
      return const GribBounds(
        north: 60.0,
        south: 55.0,
        east: 25.0,
        west: 10.0,
      );
    }
  }

  void _fetchGrid(String model) {
    final bounds = _currentBounds();
    ref.read(weatherGribProvider.notifier).fetchGrid(bounds, model);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weatherGribProvider);
    final isTablet = MediaQuery.of(context).size.width >= 600;

    final mapAndOverlay = _buildMapWithOverlays(state);

    if (isTablet) {
      return Scaffold(
        appBar: AppBar(title: const Text('GRIB Weather')),
        body: Row(
          children: [
            SizedBox(
              width: 280,
              child: _ControlsPanel(onFetch: _fetchGrid),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: mapAndOverlay),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('GRIB Weather'),
        actions: [
          if (state.fetchedAt != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  'Updated ${DateFormat.Hm().format(state.fetchedAt!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          mapAndOverlay,
          // Floating controls toggle
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_controlsExpanded)
                  _BottomControlSheet(onFetch: _fetchGrid),
                GestureDetector(
                  onTap: () =>
                      setState(() => _controlsExpanded = !_controlsExpanded),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4)
                        ],
                      ),
                      child: Icon(
                        _controlsExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapWithOverlays(WeatherGribState state) {
    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: LatLng(57.0, 18.0),
        initialZoom: 6,
      ),
      children: [
        // Base tile layer
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.floatilla.app',
        ),
        // Wave height layer (bottom, color fill)
        if (state.showWaves && state.grid.isNotEmpty)
          _WaveHeightLayer(grid: state.grid, forecastHour: state.forecastHour),
        // Isobar / pressure layer
        if (state.showPressure && state.grid.isNotEmpty)
          _IsobarLayer(grid: state.grid, forecastHour: state.forecastHour),
        // Wind barb layer (top)
        if (state.showWind && state.grid.isNotEmpty)
          _WindBarbLayer(grid: state.grid, forecastHour: state.forecastHour),
        // Loading indicator
        if (state.isLoading)
          const ColorFiltered(
            colorFilter:
                ColorFilter.mode(Colors.black38, BlendMode.darken),
            child: SizedBox.expand(),
          ),
      ],
    );
  }
}

// ── Controls Panel (tablet) ───────────────────────────────────────────────────

class _ControlsPanel extends ConsumerStatefulWidget {
  const _ControlsPanel({required this.onFetch});
  final void Function(String model) onFetch;

  @override
  ConsumerState<_ControlsPanel> createState() => _ControlsPanelState();
}

class _ControlsPanelState extends ConsumerState<_ControlsPanel> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weatherGribProvider);
    final notifier = ref.read(weatherGribProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _ControlsContent(
        state: state,
        notifier: notifier,
        onFetch: widget.onFetch,
      ),
    );
  }
}

// ── Controls Bottom Sheet (phone) ─────────────────────────────────────────────

class _BottomControlSheet extends ConsumerWidget {
  const _BottomControlSheet({required this.onFetch});
  final void Function(String model) onFetch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(weatherGribProvider);
    final notifier = ref.read(weatherGribProvider.notifier);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: _ControlsContent(
        state: state,
        notifier: notifier,
        onFetch: onFetch,
        compact: true,
      ),
    );
  }
}

// ── Shared Controls Content ───────────────────────────────────────────────────

class _ControlsContent extends StatelessWidget {
  const _ControlsContent({
    required this.state,
    required this.notifier,
    required this.onFetch,
    this.compact = false,
  });

  final WeatherGribState state;
  final WeatherGribNotifier notifier;
  final void Function(String model) onFetch;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Model selector
        Text('Model', style: theme.textTheme.labelSmall),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'gfs', label: Text('GFS')),
            ButtonSegment(value: 'ecmwf', label: Text('ECMWF')),
            ButtonSegment(value: 'icon', label: Text('ICON')),
          ],
          selected: {state.model},
          onSelectionChanged: (s) => onFetch(s.first),
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
          ),
        ),

        const SizedBox(height: 12),

        // Forecast time slider
        Row(
          children: [
            Text('Forecast: ${state.forecastHour}h',
                style: theme.textTheme.labelSmall),
            const Spacer(),
            // Play/stop
            IconButton(
              icon: Icon(
                state.isAnimating ? Icons.stop : Icons.play_arrow,
                size: 20,
              ),
              onPressed: () {
                if (state.isAnimating) {
                  notifier.stopAnimation();
                } else {
                  notifier.startAnimation();
                }
              },
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        Slider(
          value: state.forecastHour.toDouble(),
          min: 0,
          max: 72,
          divisions: 24, // steps of 3
          label: '${state.forecastHour}h',
          onChanged: (v) => notifier.setForecastHour(v.round()),
        ),

        const SizedBox(height: 8),

        // Layer toggles
        Text('Layers', style: theme.textTheme.labelSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            FilterChip(
              label: const Text('Wind'),
              avatar: const Icon(Icons.air, size: 16),
              selected: state.showWind,
              onSelected: (_) => notifier.toggleWind(),
              visualDensity: VisualDensity.compact,
            ),
            FilterChip(
              label: const Text('Pressure'),
              avatar: const Icon(Icons.compress, size: 16),
              selected: state.showPressure,
              onSelected: (_) => notifier.togglePressure(),
              visualDensity: VisualDensity.compact,
            ),
            FilterChip(
              label: const Text('Waves'),
              avatar: const Icon(Icons.waves, size: 16),
              selected: state.showWaves,
              onSelected: (_) => notifier.toggleWaves(),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Fetch + offline buttons
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: state.isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download, size: 18),
                label:
                    Text(state.isLoading ? 'Fetching...' : 'Fetch'),
                onPressed:
                    state.isLoading ? null : () => onFetch(state.model),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              icon: const Icon(Icons.save_alt, size: 18),
              tooltip: 'Save offline',
              onPressed:
                  state.grid.isEmpty ? null : () => notifier.saveOffline(),
            ),
          ],
        ),

        if (state.error != null) ...[
          const SizedBox(height: 8),
          Text(
            state.error!,
            style: TextStyle(
                color: theme.colorScheme.error, fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        if (state.fetchedAt != null && !compact) ...[
          const SizedBox(height: 8),
          Text(
            'Updated: ${DateFormat('dd MMM HH:mm').format(state.fetchedAt!)}',
            style: theme.textTheme.bodySmall,
          ),
        ],

        if (state.isOfflineCapable && state.grid.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.offline_bolt,
                  size: 12,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text('Offline data available',
                  style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.primary)),
            ],
          ),
        ],
      ],
    );
  }
}

// ── Wind Barb Layer ───────────────────────────────────────────────────────────

class _WindBarbLayer extends StatelessWidget {
  const _WindBarbLayer({
    required this.grid,
    required this.forecastHour,
  });

  final List<WeatherGribEntry> grid;
  final int forecastHour;

  @override
  Widget build(BuildContext context) {
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _WindBarbPainter(
          grid: grid,
          forecastHour: forecastHour,
          camera: MapCamera.of(context),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WindBarbPainter extends CustomPainter {
  _WindBarbPainter({
    required this.grid,
    required this.forecastHour,
    required this.camera,
  });

  final List<WeatherGribEntry> grid;
  final int forecastHour;
  final MapCamera camera;

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in grid) {
      final hourEntry = entry.atHour(forecastHour);
      final pt = camera.latLngToScreenPoint(entry.position);
      // Skip points outside viewport with margin
      if (pt.x < -40 ||
          pt.x > size.width + 40 ||
          pt.y < -40 ||
          pt.y > size.height + 40) {
        continue;
      }

      _drawWindBarb(
        canvas,
        Offset(pt.x, pt.y),
        hourEntry.windSpeed,
        hourEntry.windDir,
      );
    }
  }

  void _drawWindBarb(
      Canvas canvas, Offset center, double speedKn, double dirDeg) {
    final color = _windColor(speedKn);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (speedKn < 0.5) {
      // Calm — small circle
      canvas.drawCircle(center, 5, paint);
      return;
    }

    // Rotate canvas so barb points in wind direction
    final radians = dirDeg * math.pi / 180;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(radians);

    // Staff line
    const staffLen = 20.0;
    canvas.drawLine(const Offset(0, 0), const Offset(0, staffLen), paint);

    // Add barbs from tail
    double remaining = speedKn;
    double barbY = staffLen;
    const barbSpacing = 4.0;
    const barbLen = 10.0;
    const halfBarbLen = 5.0;
    const pennantH = 8.0;

    // Pennants (50 kn each) — filled triangles
    while (remaining >= 47.5) {
      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final pennantPath = ui.Path()
        ..moveTo(0, barbY)
        ..lineTo(barbLen, barbY - pennantH / 2)
        ..lineTo(0, barbY - pennantH)
        ..close();
      canvas.drawPath(pennantPath, fillPaint);
      barbY -= pennantH + barbSpacing / 2;
      remaining -= 50;
    }

    // Full barbs (5 kn each)
    while (remaining >= 7.5) {
      canvas.drawLine(
        Offset(0, barbY),
        Offset(barbLen, barbY - 4),
        paint,
      );
      barbY -= barbSpacing;
      remaining -= 5;
    }

    // Half barb (2.5 kn)
    if (remaining >= 2.5) {
      canvas.drawLine(
        Offset(0, barbY),
        Offset(halfBarbLen, barbY - 2),
        paint,
      );
    }

    canvas.restore();
  }

  Color _windColor(double kn) {
    if (kn < 1) return Colors.grey;
    if (kn < 11) return Colors.green;
    if (kn < 21) return Colors.yellow.shade700;
    if (kn < 34) return Colors.orange;
    return Colors.red;
  }

  @override
  bool shouldRepaint(_WindBarbPainter old) =>
      old.forecastHour != forecastHour || old.grid != grid;
}

// ── Isobar Layer ─────────────────────────────────────────────────────────────

class _IsobarLayer extends StatelessWidget {
  const _IsobarLayer({
    required this.grid,
    required this.forecastHour,
  });

  final List<WeatherGribEntry> grid;
  final int forecastHour;

  @override
  Widget build(BuildContext context) {
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _IsobarPainter(
          grid: grid,
          forecastHour: forecastHour,
          camera: MapCamera.of(context),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _IsobarPainter extends CustomPainter {
  _IsobarPainter({
    required this.grid,
    required this.forecastHour,
    required this.camera,
  });

  final List<WeatherGribEntry> grid;
  final int forecastHour;
  final MapCamera camera;

  @override
  void paint(Canvas canvas, Size size) {
    if (grid.isEmpty) return;

    // Collect all unique lat/lng values
    final lats = grid.map((e) => e.lat).toSet().toList()..sort();
    final lngs = grid.map((e) => e.lng).toSet().toList()..sort();
    if (lats.length < 2 || lngs.length < 2) return;

    // Build 2D pressure grid
    final pressureGrid = List.generate(
      lats.length,
      (i) => List<double?>.filled(lngs.length, null),
    );

    for (final entry in grid) {
      final li = lats.indexOf(entry.lat);
      final lj = lngs.indexOf(entry.lng);
      if (li >= 0 && lj >= 0) {
        final hourEntry = entry.atHour(forecastHour);
        pressureGrid[li][lj] = hourEntry.pressure;
      }
    }

    // Determine pressure range
    double minP = 1040, maxP = 960;
    for (final row in pressureGrid) {
      for (final v in row) {
        if (v != null) {
          if (v < minP) minP = v;
          if (v > maxP) maxP = v;
        }
      }
    }

    // Round to nearest 2hPa interval
    final startP = (minP / 2).ceil() * 2;
    final endP = (maxP / 2).floor() * 2;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.85),
      fontSize: 9,
      fontWeight: FontWeight.w500,
    );

    for (var level = startP; level <= endP; level += 2) {
      _drawContour(
          canvas, size, lats, lngs, pressureGrid, level.toDouble(),
          paint, labelStyle);
    }
  }

  void _drawContour(
    Canvas canvas,
    Size size,
    List<double> lats,
    List<double> lngs,
    List<List<double?>> grid,
    double level,
    Paint paint,
    TextStyle labelStyle,
  ) {
    // Simple marching squares — iterate over each cell
    for (var i = 0; i < lats.length - 1; i++) {
      for (var j = 0; j < lngs.length - 1; j++) {
        final v00 = grid[i][j];
        final v10 = grid[i + 1][j];
        final v01 = grid[i][j + 1];
        final v11 = grid[i + 1][j + 1];

        if (v00 == null || v10 == null || v01 == null || v11 == null) {
          continue;
        }

        // Corner indices above level
        final c00 = v00 >= level ? 1 : 0;
        final c10 = v10 >= level ? 1 : 0;
        final c01 = v01 >= level ? 1 : 0;
        final c11 = v11 >= level ? 1 : 0;
        final code = c00 | (c01 << 1) | (c10 << 2) | (c11 << 3);

        if (code == 0 || code == 15) continue; // all same side

        final cellLat0 = lats[i];
        final cellLat1 = lats[i + 1];
        final cellLng0 = lngs[j];
        final cellLng1 = lngs[j + 1];

        Offset edgePoint(double vFrom, double vTo,
            double lat0, double lng0, double lat1, double lng1) {
          if ((vFrom - level).abs() < 0.001) return _toScreen(lat0, lng0);
          if ((vTo - level).abs() < 0.001) return _toScreen(lat1, lng1);
          final t = (level - vFrom) / (vTo - vFrom);
          final lat = lat0 + t * (lat1 - lat0);
          final lng = lng0 + t * (lng1 - lng0);
          return _toScreen(lat, lng);
        }

        // Interpolate edge midpoints
        final bottom = edgePoint(
            v00, v01, cellLat0, cellLng0, cellLat0, cellLng1);
        final top = edgePoint(
            v10, v11, cellLat1, cellLng0, cellLat1, cellLng1);
        final left = edgePoint(
            v00, v10, cellLat0, cellLng0, cellLat1, cellLng0);
        final right = edgePoint(
            v01, v11, cellLat0, cellLng1, cellLat1, cellLng1);

        // Draw appropriate line segment based on marching squares case
        void drawLine(Offset a, Offset b) {
          canvas.drawLine(a, b, paint);
        }

        switch (code) {
          case 1:
          case 14:
            drawLine(bottom, left);
          case 2:
          case 13:
            drawLine(bottom, right);
          case 3:
          case 12:
            drawLine(left, right);
          case 4:
          case 11:
            drawLine(top, left);
          case 5:
          case 10:
            drawLine(bottom, top);
          case 6:
          case 9:
            drawLine(top, right);
          case 7:
          case 8:
            drawLine(top, left);
            drawLine(bottom, right);
        }
      }
    }
  }

  Offset _toScreen(double lat, double lng) {
    final pt = camera.latLngToScreenPoint(LatLng(lat, lng));
    return Offset(pt.x, pt.y);
  }

  @override
  bool shouldRepaint(_IsobarPainter old) =>
      old.forecastHour != forecastHour || old.grid != grid;
}

// ── Wave Height Layer ─────────────────────────────────────────────────────────

class _WaveHeightLayer extends StatelessWidget {
  const _WaveHeightLayer({
    required this.grid,
    required this.forecastHour,
  });

  final List<WeatherGribEntry> grid;
  final int forecastHour;

  @override
  Widget build(BuildContext context) {
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _WaveHeightPainter(
          grid: grid,
          forecastHour: forecastHour,
          camera: MapCamera.of(context),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WaveHeightPainter extends CustomPainter {
  _WaveHeightPainter({
    required this.grid,
    required this.forecastHour,
    required this.camera,
  });

  final List<WeatherGribEntry> grid;
  final int forecastHour;
  final MapCamera camera;

  Color _waveColor(double? h) {
    if (h == null) return Colors.transparent;
    if (h < 0.5) return Colors.blue.withValues(alpha: 0.4);
    if (h < 1.0) return Colors.cyan.withValues(alpha: 0.4);
    if (h < 1.5) return Colors.green.withValues(alpha: 0.4);
    if (h < 2.0) return Colors.yellow.withValues(alpha: 0.4);
    return Colors.red.withValues(alpha: 0.4);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in grid) {
      final hourEntry = entry.atHour(forecastHour);
      final wh = hourEntry.waveHeight;
      final color = _waveColor(wh);
      if (color == Colors.transparent) continue;

      final paint = Paint()..color = color;
      // Draw a filled rectangle covering roughly the grid cell (0.5°×0.5°)
      final nePt = camera.latLngToScreenPoint(
          LatLng(entry.lat + 0.25, entry.lng + 0.25));
      final swPt = camera.latLngToScreenPoint(
          LatLng(entry.lat - 0.25, entry.lng - 0.25));

      canvas.drawRect(
        Rect.fromLTRB(
          math.min(nePt.x, swPt.x),
          math.min(nePt.y, swPt.y),
          math.max(nePt.x, swPt.x),
          math.max(nePt.y, swPt.y),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveHeightPainter old) =>
      old.forecastHour != forecastHour || old.grid != grid;
}
