import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';
import '../../data/providers/chart_tile_provider.dart';

/// Offline tile cache management and area download screen.
class OfflineTilesScreen extends StatefulWidget {
  const OfflineTilesScreen({super.key});

  @override
  State<OfflineTilesScreen> createState() => _OfflineTilesScreenState();
}

class _OfflineTilesScreenState extends State<OfflineTilesScreen> {
  double? _cacheSizeKiB;
  int? _cacheCount;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final store = FMTCStore('mapTiles');
      if (!await store.manage.ready) {
        if (mounted) {
          setState(() {
            _cacheSizeKiB = 0;
            _cacheCount = 0;
            _loading = false;
          });
        }
        return;
      }
      final stats = await store.stats.all;
      if (mounted) {
        setState(() {
          _cacheSizeKiB = stats.size;
          _cacheCount = stats.length;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Tile Cache'),
        content: const Text('Delete all downloaded offline tiles?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final store = FMTCStore('mapTiles');
      await store.manage.delete();
      await _loadStats();
    }
  }

  void _openDownloadScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _AreaDownloadScreen()),
    ).then((_) => _loadStats());
  }

  String _formatKiB(double kib) {
    if (kib < 1024) return '${kib.toStringAsFixed(0)} KiB';
    final mib = kib / 1024;
    if (mib < 1024) return '${mib.toStringAsFixed(1)} MiB';
    return '${(mib / 1024).toStringAsFixed(2)} GiB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Tiles')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cache Statistics',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        _statRow('Tiles cached',
                            '${_cacheCount ?? 0}'),
                        _statRow('Storage used',
                            _formatKiB(_cacheSizeKiB ?? 0)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _openDownloadScreen,
                                icon: const Icon(Icons.download),
                                label: const Text('Download Area'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: (_cacheCount ?? 0) > 0
                                  ? _clearCache
                                  : null,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Clear'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Screen to select an area on the map and download tiles for offline use.
class _AreaDownloadScreen extends StatefulWidget {
  const _AreaDownloadScreen();

  @override
  State<_AreaDownloadScreen> createState() => _AreaDownloadScreenState();
}

class _AreaDownloadScreenState extends State<_AreaDownloadScreen> {
  final _mapController = MapController();
  LatLng? _corner1;
  LatLng? _corner2;
  int _minZoom = 8;
  int _maxZoom = 15;
  bool _downloading = false;
  double _progress = 0;
  StreamSubscription<DownloadProgress>? _downloadSub;

  @override
  void dispose() {
    _downloadSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onTap(TapPosition tapPos, LatLng point) {
    setState(() {
      if (_corner1 == null || _corner2 != null) {
        _corner1 = point;
        _corner2 = null;
      } else {
        _corner2 = point;
      }
    });
  }

  LatLngBounds? get _selectedBounds {
    if (_corner1 == null || _corner2 == null) return null;
    return LatLngBounds(_corner1!, _corner2!);
  }

  Future<void> _startDownload() async {
    final bounds = _selectedBounds;
    if (bounds == null) return;

    setState(() {
      _downloading = true;
      _progress = 0;
    });

    try {
      final store = FMTCStore('mapTiles');
      await store.manage.create();

      final region = RectangleRegion(bounds);
      final downloadable = region.toDownloadable(
        minZoom: _minZoom,
        maxZoom: _maxZoom,
        options: TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.craigrallen.flutter_plotter',
        ),
      );

      _downloadSub = store.download.startForeground(
        region: downloadable,
      ).listen(
        (progress) {
          if (mounted) {
            setState(() {
              _progress = progress.percentageProgress / 100;
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() => _downloading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Download complete')),
            );
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() => _downloading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Download error: $e')),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseLayer = OsmBaseProvider();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Download Area'),
        actions: [
          if (_corner1 != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear selection',
              onPressed: () => setState(() {
                _corner1 = null;
                _corner2 = null;
              }),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(57.7089, 11.9746),
                initialZoom: 10,
                onTap: _onTap,
              ),
              children: [
                baseLayer.tileLayer,
                if (_selectedBounds != null)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: [
                          _selectedBounds!.northWest,
                          _selectedBounds!.northEast,
                          _selectedBounds!.southEast,
                          _selectedBounds!.southWest,
                        ],
                        color: Colors.blue.withValues(alpha: 0.2),
                        borderColor: Colors.blue,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                if (_corner1 != null && _corner2 == null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _corner1!,
                        width: 20,
                        height: 20,
                        child: const Icon(Icons.circle, color: Colors.blue,
                            size: 12),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // Controls
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_corner1 == null)
                  const Text('Tap two corners to select download area')
                else if (_corner2 == null)
                  const Text('Tap second corner to complete selection')
                else ...[
                  // Zoom range picker
                  Row(
                    children: [
                      const Text('Zoom: '),
                      Expanded(
                        child: RangeSlider(
                          values: RangeValues(
                              _minZoom.toDouble(), _maxZoom.toDouble()),
                          min: 1,
                          max: 18,
                          divisions: 17,
                          labels: RangeLabels('$_minZoom', '$_maxZoom'),
                          onChanged: _downloading
                              ? null
                              : (v) => setState(() {
                                    _minZoom = v.start.round();
                                    _maxZoom = v.end.round();
                                  }),
                        ),
                      ),
                      Text('$_minZoom-$_maxZoom'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_downloading)
                    Column(
                      children: [
                        LinearProgressIndicator(value: _progress),
                        const SizedBox(height: 8),
                        Text('${(_progress * 100).toStringAsFixed(1)}%'),
                      ],
                    )
                  else
                    FilledButton.icon(
                      onPressed: _startDownload,
                      icon: const Icon(Icons.download),
                      label: const Text('Download Tiles'),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
