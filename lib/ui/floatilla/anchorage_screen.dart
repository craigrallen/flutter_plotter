import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/floatilla/anchorage_service.dart';
import '../../data/providers/chart_tile_provider.dart';
import '../../data/providers/vessel_provider.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _anchoragesProvider =
    StateProvider<List<AnchorageInfo>>((ref) => []);
final _hazardsProvider =
    StateProvider<List<HazardReport>>((ref) => []);
final _loadingProvider = StateProvider<bool>((ref) => false);

// ── Helpers ──────────────────────────────────────────────────────────────────

IconData _hazardIcon(String type) {
  switch (type) {
    case 'floating_debris':
      return Icons.delete_outline;
    case 'shallow_water':
      return Icons.water;
    case 'fishing_net':
      return Icons.grid_on;
    case 'unlit_vessel':
      return Icons.directions_boat;
    case 'submerged_object':
      return Icons.hardware;
    default:
      return Icons.warning_amber;
  }
}

String _hazardLabel(String type) {
  switch (type) {
    case 'floating_debris':
      return 'Floating Debris';
    case 'shallow_water':
      return 'Shallow Water';
    case 'fishing_net':
      return 'Fishing Net';
    case 'unlit_vessel':
      return 'Unlit Vessel';
    case 'submerged_object':
      return 'Submerged Object';
    default:
      return 'Hazard';
  }
}

// Open-Meteo: fetch current wind at a point
Future<Map<String, dynamic>?> _fetchWindData(double lat, double lng) async {
  try {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lng'
      '&current_weather=true'
      '&wind_speed_unit=kn',
    );
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return null;
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return body['current_weather'] as Map<String, dynamic>?;
  } catch (_) {
    return null;
  }
}

String _compassDir(double deg) {
  const dirs = [
    'N', 'NNE', 'NE', 'ENE',
    'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW',
    'W', 'WNW', 'NW', 'NNW',
  ];
  return dirs[((deg / 22.5) + 0.5).floor() % 16];
}

// ── Main Screen ───────────────────────────────────────────────────────────────

class AnchorageScreen extends ConsumerStatefulWidget {
  const AnchorageScreen({super.key});

  @override
  ConsumerState<AnchorageScreen> createState() => _AnchorageScreenState();
}

class _AnchorageScreenState extends ConsumerState<AnchorageScreen> {
  final _mapController = MapController();
  LatLng _center = const LatLng(57.7, 11.97); // fallback Gothenburg area
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    // Use vessel position if available.
    final vessel = ref.read(vesselProvider);
    LatLng center;
    if (vessel.position != null) {
      center = vessel.position!;
    } else {
      try {
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
          );
          center = LatLng(pos.latitude, pos.longitude);
        } else {
          center = _center;
        }
      } catch (_) {
        center = _center;
      }
    }

    setState(() {
      _center = center;
      _initialised = true;
    });
    _mapController.move(center, 11);
    await _load(center);
  }

  Future<void> _load(LatLng center) async {
    ref.read(_loadingProvider.notifier).state = true;
    try {
      final results = await Future.wait([
        AnchorageService.instance.nearbyAnchorages(center, radiusNm: 10),
        AnchorageService.instance.nearbyHazards(center, radiusNm: 25),
      ]);
      ref.read(_anchoragesProvider.notifier).state =
          results[0] as List<AnchorageInfo>;
      ref.read(_hazardsProvider.notifier).state =
          results[1] as List<HazardReport>;
    } finally {
      ref.read(_loadingProvider.notifier).state = false;
    }
  }

  // ── Bottom sheet: anchorage details ──────────────────────────────────────

  void _showAnchorageSheet(AnchorageInfo info) {
    final layout = MediaQuery.sizeOf(context);
    final isTablet = layout.width > 720;

    if (isTablet) {
      _showAnchorageSidePanel(info);
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => _AnchorageSheet(
          info: info,
          onRefresh: () => _load(_center),
        ),
      );
    }
  }

  void _showAnchorageSidePanel(AnchorageInfo info) {
    showDialog(
      context: context,
      builder: (_) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          elevation: 8,
          child: SizedBox(
            width: 360,
            height: double.infinity,
            child: _AnchorageSheet(
              info: info,
              onRefresh: () => _load(_center),
            ),
          ),
        ),
      ),
    );
  }

  // ── Bottom sheet: hazard details ─────────────────────────────────────────

  void _showHazardSheet(HazardReport hazard) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_hazardIcon(hazard.type),
                      color: Colors.orange, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _hazardLabel(hazard.type),
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (hazard.description != null &&
                  hazard.description!.isNotEmpty)
                Text(hazard.description!),
              const SizedBox(height: 8),
              Text(
                'Reported by ${hazard.reporterUsername ?? "unknown"} — ${hazard.ageLabel}',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              if (hazard.confirmedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${hazard.confirmedCount} confirmation${hazard.confirmedCount == 1 ? "" : "s"}',
                    style: TextStyle(
                        color: Theme.of(ctx).colorScheme.primary,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.thumb_up_outlined),
                    label: const Text('Confirm hazard'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final ok = await AnchorageService.instance
                          .confirmHazard(hazard.id);
                      if (!ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Could not confirm — try again')),
                        );
                      } else if (mounted) {
                        await _load(_center);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Report hazard dialog ─────────────────────────────────────────────────

  void _showReportHazardDialog() {
    final vessel = ref.read(vesselProvider);
    final LatLng pos = vessel.position ?? _center;
    showDialog(
      context: context,
      builder: (ctx) => _ReportHazardDialog(
        initialPos: pos,
        onSubmit: (type, desc, submitPos) async {
          Navigator.pop(ctx);
          final ok = await AnchorageService.instance.reportHazard(
            pos: submitPos,
            type: type,
            description: desc,
          );
          if (!ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to submit hazard report')),
            );
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Hazard reported')),
            );
            await _load(_center);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final anchorages = ref.watch(_anchoragesProvider);
    final hazards = ref.watch(_hazardsProvider);
    final loading = ref.watch(_loadingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anchorages'),
        actions: [
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _load(_center),
          ),
        ],
      ),
      body: _initialised
          ? FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 11,
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture && position.center != null) {
                    _center = position.center!;
                  }
                },
                onMapEvent: (event) {
                  if (event is MapEventMoveEnd) {
                    _load(event.camera.center);
                  }
                },
              ),
              children: [
                // Base chart
                OsmBaseProvider().tileLayer,
                // Nautical overlay
                OpenSeaMapProvider().tileLayer,
                // Hazard markers
                MarkerLayer(
                  markers: hazards
                      .map(
                        (h) => Marker(
                          width: 36,
                          height: 36,
                          point: h.position,
                          child: GestureDetector(
                            onTap: () => _showHazardSheet(h),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.orange.withAlpha(220),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.deepOrange, width: 2),
                              ),
                              child: Icon(
                                _hazardIcon(h.type),
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                // Anchorage markers
                MarkerLayer(
                  markers: anchorages
                      .map(
                        (a) => Marker(
                          width: 64,
                          height: 64,
                          point: a.position,
                          child: GestureDetector(
                            onTap: () => _showAnchorageSheet(a),
                            child: _AnchorageMarker(info: a),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showReportHazardDialog,
        icon: const Icon(Icons.add_alert),
        label: const Text('Report hazard'),
      ),
    );
  }
}

// ── Anchorage marker widget ───────────────────────────────────────────────────

class _AnchorageMarker extends StatelessWidget {
  final AnchorageInfo info;
  const _AnchorageMarker({required this.info});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(80),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.place, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Text(
                '${info.boatCount} boat${info.boatCount == 1 ? "" : "s"}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Anchorage bottom sheet ────────────────────────────────────────────────────

class _AnchorageSheet extends ConsumerStatefulWidget {
  final AnchorageInfo info;
  final VoidCallback onRefresh;

  const _AnchorageSheet({required this.info, required this.onRefresh});

  @override
  ConsumerState<_AnchorageSheet> createState() => _AnchorageSheetState();
}

class _AnchorageSheetState extends ConsumerState<_AnchorageSheet> {
  String? _windSummary;
  bool _windLoading = false;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchWind();
  }

  Future<void> _fetchWind() async {
    setState(() => _windLoading = true);
    final wind = await _fetchWind0(widget.info.lat, widget.info.lng);
    if (!mounted) return;
    if (wind != null) {
      final speed = (wind['windspeed'] as num?)?.toDouble() ?? 0;
      final dir = (wind['winddirection'] as num?)?.toDouble() ?? 0;
      final dirLabel = _compassDir(dir);
      setState(() {
        _windSummary = '$dirLabel ${speed.round()} kn';
      });
    }
    setState(() => _windLoading = false);
  }

  Future<Map<String, dynamic>?> _fetchWind0(double lat, double lng) =>
      _fetchWindData(lat, lng);

  Future<void> _checkin() async {
    setState(() => _actionLoading = true);
    final ok = await AnchorageService.instance
        .checkin(LatLng(widget.info.lat, widget.info.lng));
    if (!mounted) return;
    setState(() => _actionLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(ok
              ? 'Checked in at ${widget.info.name}'
              : 'Check-in failed')),
    );
    if (ok) {
      Navigator.pop(context);
      widget.onRefresh();
    }
  }

  Future<void> _checkout() async {
    setState(() => _actionLoading = true);
    final ok = await AnchorageService.instance.checkout();
    if (!mounted) return;
    setState(() => _actionLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(ok ? 'Departure recorded' : 'Checkout failed')),
    );
    if (ok) {
      Navigator.pop(context);
      widget.onRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                const Icon(Icons.place, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    info.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${info.boatCount} boat${info.boatCount == 1 ? "" : "s"} currently anchored',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
            ),

            // Wind
            const SizedBox(height: 12),
            if (_windLoading)
              const Text('Loading wind...',
                  style: TextStyle(color: Colors.grey))
            else if (_windSummary != null)
              _WindBanner(
                summary: _windSummary!,
                anchorageName: info.name,
              ),

            // Boats list
            if (info.boats.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Currently anchored',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              ...info.boats.map((b) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_boat,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(b.vesselName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(width: 4),
                        Text('(@${b.username})',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  )),
            ],

            // Last review
            if (info.lastReview != null) ...[
              const SizedBox(height: 16),
              Text('Last review',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Row(
                children: [
                  ...List.generate(
                    5,
                    (i) => Icon(
                      i < info.lastReview!.rating.round()
                          ? Icons.star
                          : Icons.star_border,
                      size: 16,
                      color: Colors.amber,
                    ),
                  ),
                ],
              ),
              if (info.lastReview!.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(info.lastReview!.text),
                ),
            ],

            // Action buttons
            const SizedBox(height: 20),
            if (_actionLoading)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.place),
                      label: const Text("I'm anchoring here"),
                      onPressed: _checkin,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.logout),
                      label: const Text("I'm leaving"),
                      onPressed: _checkout,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ── Wind exposure banner ──────────────────────────────────────────────────────

class _WindBanner extends StatelessWidget {
  final String summary;
  final String anchorageName;

  const _WindBanner({required this.summary, required this.anchorageName});

  @override
  Widget build(BuildContext context) {
    // Simple heuristic: flag if wind > 15 kn
    final parts = summary.split(' ');
    final speed = parts.length >= 2 ? int.tryParse(parts[1]) ?? 0 : 0;
    final dirLabel = parts.isNotEmpty ? parts[0] : '';
    final exposed = speed > 15;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: exposed
            ? Colors.orange.withAlpha(40)
            : Colors.blue.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: exposed ? Colors.orange : Colors.blue.withAlpha(80),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.air,
            color: exposed ? Colors.orange : Colors.blue,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              exposed
                  ? '$summary — this anchorage may be exposed to $dirLabel winds'
                  : 'Wind: $summary',
              style: TextStyle(
                color: exposed ? Colors.orange.shade800 : null,
                fontWeight:
                    exposed ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Report hazard dialog ──────────────────────────────────────────────────────

class _ReportHazardDialog extends StatefulWidget {
  final LatLng initialPos;
  final void Function(String type, String? description, LatLng pos)
      onSubmit;

  const _ReportHazardDialog({
    required this.initialPos,
    required this.onSubmit,
  });

  @override
  State<_ReportHazardDialog> createState() => _ReportHazardDialogState();
}

class _ReportHazardDialogState extends State<_ReportHazardDialog> {
  static const _types = [
    ('floating_debris', 'Floating Debris'),
    ('shallow_water', 'Shallow Water'),
    ('fishing_net', 'Fishing Net'),
    ('unlit_vessel', 'Unlit Vessel'),
    ('submerged_object', 'Submerged Object'),
    ('other', 'Other'),
  ];

  String _selectedType = 'floating_debris';
  final _descController = TextEditingController();

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report Hazard'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hazard type'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedType,
              items: _types
                  .map((t) => DropdownMenuItem<String>(
                        value: t.$1,
                        child: Text(t.$2),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedType = v!),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.my_location, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Using your current GPS position',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.send),
          label: const Text('Submit'),
          onPressed: () {
            widget.onSubmit(
              _selectedType,
              _descController.text.trim().isEmpty
                  ? null
                  : _descController.text.trim(),
              widget.initialPos,
            );
          },
        ),
      ],
    );
  }
}
