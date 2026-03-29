import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../core/floatilla/floatilla_service.dart';
import '../../core/utils/error_handler.dart';
import '../../data/providers/vessel_provider.dart';

// ── Models ────────────────────────────────────────────────────────────────────

enum _MarinaType { marina, anchorage, fuelDock, hazard }

String _marinaTypeLabel(_MarinaType type) {
  switch (type) {
    case _MarinaType.marina:
      return 'Marina';
    case _MarinaType.anchorage:
      return 'Anchorage';
    case _MarinaType.fuelDock:
      return 'Fuel Dock';
    case _MarinaType.hazard:
      return 'Hazard';
  }
}

String _marinaTypeString(_MarinaType type) {
  switch (type) {
    case _MarinaType.marina:
      return 'marina';
    case _MarinaType.anchorage:
      return 'anchorage';
    case _MarinaType.fuelDock:
      return 'fuel_dock';
    case _MarinaType.hazard:
      return 'hazard';
  }
}

_MarinaType _marinaTypeFromString(String s) {
  switch (s) {
    case 'anchorage':
      return _MarinaType.anchorage;
    case 'fuel_dock':
      return _MarinaType.fuelDock;
    case 'hazard':
      return _MarinaType.hazard;
    default:
      return _MarinaType.marina;
  }
}

enum _Availability { yes, no, unknown }

_Availability _availFromString(String? s) {
  switch (s) {
    case 'yes':
      return _Availability.yes;
    case 'no':
      return _Availability.no;
    default:
      return _Availability.unknown;
  }
}

String _availString(_Availability a) {
  switch (a) {
    case _Availability.yes:
      return 'yes';
    case _Availability.no:
      return 'no';
    case _Availability.unknown:
      return 'unknown';
  }
}

class _Marina {
  final int? id;
  final double lat;
  final double lng;
  final String name;
  final _MarinaType type;
  final _Availability fuel;
  final String? fuelPrice;
  final _Availability water;
  final double? depthM;
  final int? vhfChannel;
  final Map<String, bool> facilities; // shower, laundry, wifi, electricity, pumpout
  final String? createdBy;
  final DateTime? updatedAt;

  const _Marina({
    this.id,
    required this.lat,
    required this.lng,
    required this.name,
    required this.type,
    this.fuel = _Availability.unknown,
    this.fuelPrice,
    this.water = _Availability.unknown,
    this.depthM,
    this.vhfChannel,
    this.facilities = const {},
    this.createdBy,
    this.updatedAt,
  });

  LatLng get position => LatLng(lat, lng);

  factory _Marina.fromJson(Map<String, dynamic> j) => _Marina(
        id: j['id'] as int?,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        name: j['name'] as String? ?? 'Unknown',
        type: _marinaTypeFromString(j['type'] as String? ?? 'marina'),
        fuel: _availFromString(j['fuel'] as String?),
        fuelPrice: j['fuel_price'] as String?,
        water: _availFromString(j['water'] as String?),
        depthM: (j['depth'] as num?)?.toDouble(),
        vhfChannel: j['vhf'] as int?,
        facilities: _parseFacilities(j['facilities']),
        createdBy: j['created_by'] as String?,
        updatedAt: j['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                ((j['updated_at'] as num) * 1000).toInt())
            : null,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'lat': lat,
        'lng': lng,
        'name': name,
        'type': _marinaTypeString(type),
        'fuel': _availString(fuel),
        if (fuelPrice != null) 'fuel_price': fuelPrice,
        'water': _availString(water),
        if (depthM != null) 'depth': depthM,
        if (vhfChannel != null) 'vhf': vhfChannel,
        'facilities': facilities,
      };
}

Map<String, bool> _parseFacilities(dynamic raw) {
  if (raw == null) return {};
  if (raw is Map<String, dynamic>) {
    return raw.map((k, v) => MapEntry(k, v == true));
  }
  try {
    final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, v == true));
  } catch (e) {
    logError('_parseFeatures', e);
    return {};
  }
}

class _MarinaNote {
  final int? id;
  final String note;
  final String? username;
  final DateTime? createdAt;

  const _MarinaNote({this.id, required this.note, this.username, this.createdAt});

  factory _MarinaNote.fromJson(Map<String, dynamic> j) => _MarinaNote(
        id: j['id'] as int?,
        note: j['note'] as String? ?? '',
        username: j['username'] as String?,
        createdAt: j['created_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                ((j['created_at'] as num) * 1000).toInt())
            : null,
      );
}

// ── Filter ────────────────────────────────────────────────────────────────────

enum _Filter { all, fuel, water, shelter }

// ── Providers ─────────────────────────────────────────────────────────────────

final _marinasProvider =
    StateNotifierProvider<_MarinasNotifier, List<_Marina>>(
        (_) => _MarinasNotifier());

class _MarinasNotifier extends StateNotifier<List<_Marina>> {
  _MarinasNotifier() : super([]);

  Future<void> loadNearby(double lat, double lng) async {
    try {
      final uri = Uri.parse(
          '${FloatillaService.instance.baseUrl}/marinas/nearby?lat=$lat&lng=$lng&radiusNm=20');
      final resp = await http.get(uri, headers: {
        if (FloatillaService.instance.token != null)
          'Authorization': 'Bearer ${FloatillaService.instance.token}',
      });
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        state = list
            .map((e) => _Marina.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) { logError('MarinasNotifier.loadNearby', e); }
  }

  Future<bool> submitMarina(_Marina marina) async {
    try {
      final resp = await http.post(
        Uri.parse('${FloatillaService.instance.baseUrl}/marinas'),
        headers: {
          'Content-Type': 'application/json',
          if (FloatillaService.instance.token != null)
            'Authorization': 'Bearer ${FloatillaService.instance.token}',
        },
        body: jsonEncode(marina.toJson()),
      );
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final updated =
            _Marina.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
        state = [...state.where((m) => m.id != updated.id), updated];
        return true;
      }
    } catch (e) { logError('MarinasNotifier.submitMarina', e); }
    return false;
  }

  Future<bool> addNote(int marinaId, String note) async {
    try {
      final resp = await http.post(
        Uri.parse('${FloatillaService.instance.baseUrl}/marinas/$marinaId/notes'),
        headers: {
          'Content-Type': 'application/json',
          if (FloatillaService.instance.token != null)
            'Authorization': 'Bearer ${FloatillaService.instance.token}',
        },
        body: jsonEncode({'note': note}),
      );
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (e) {
      logError('MarinasNotifier.addNote', e);
      return false;
    }
  }
}

final _filterProvider = StateProvider<_Filter>((_) => _Filter.all);

// ── Screen ────────────────────────────────────────────────────────────────────

class MarinaLayerScreen extends ConsumerStatefulWidget {
  const MarinaLayerScreen({super.key});

  @override
  ConsumerState<MarinaLayerScreen> createState() => _MarinaLayerScreenState();
}

class _MarinaLayerScreenState extends ConsumerState<MarinaLayerScreen> {
  final _mapController = MapController();
  LatLng _center = const LatLng(57.7, 11.9); // default: Gothenburg

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final vessel = ref.read(vesselProvider);
    if (vessel.position != null) {
      _center = vessel.position!;
      ref.read(_marinasProvider.notifier).loadNearby(
            vessel.position!.latitude,
            vessel.position!.longitude,
          );
    } else {
      // Try device GPS
      try {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition();
          if (mounted) {
            setState(() => _center = LatLng(pos.latitude, pos.longitude));
            ref.read(_marinasProvider.notifier).loadNearby(
                  pos.latitude,
                  pos.longitude,
                );
          }
        }
      } catch (e) {
        logError('MarinaLayerScreen._initLocation', e);
        ref.read(_marinasProvider.notifier).loadNearby(
              _center.latitude,
              _center.longitude,
            );
      }
    }
  }

  List<_Marina> _filtered(List<_Marina> marinas, _Filter filter) {
    switch (filter) {
      case _Filter.all:
        return marinas;
      case _Filter.fuel:
        return marinas
            .where((m) => m.fuel == _Availability.yes)
            .toList();
      case _Filter.water:
        return marinas
            .where((m) => m.water == _Availability.yes)
            .toList();
      case _Filter.shelter:
        return marinas
            .where((m) =>
                m.type == _MarinaType.marina ||
                m.type == _MarinaType.anchorage)
            .toList();
    }
  }

  IconData _markerIcon(_MarinaType type) {
    switch (type) {
      case _MarinaType.marina:
        return Icons.anchor;
      case _MarinaType.anchorage:
        return Icons.anchor;
      case _MarinaType.fuelDock:
        return Icons.local_gas_station;
      case _MarinaType.hazard:
        return Icons.warning_amber;
    }
  }

  Color _markerColor(_MarinaType type) {
    switch (type) {
      case _MarinaType.marina:
        return Colors.blue;
      case _MarinaType.anchorage:
        return Colors.green;
      case _MarinaType.fuelDock:
        return Colors.orange;
      case _MarinaType.hazard:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final marinas = ref.watch(_marinasProvider);
    final filter = ref.watch(_filterProvider);
    final visible = _filtered(marinas, filter);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marinas & Amenities'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                for (final f in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(_filterLabel(f)),
                      selected: filter == f,
                      onSelected: (_) =>
                          ref.read(_filterProvider.notifier).state = f,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'refresh',
            onPressed: () => ref
                .read(_marinasProvider.notifier)
                .loadNearby(_center.latitude, _center.longitude),
            child: const Icon(Icons.refresh),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'report',
            icon: const Icon(Icons.add_location_alt),
            label: const Text('Report Location'),
            onPressed: () => _showReportDialog(context, _center),
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _center,
          initialZoom: 10,
          onPositionChanged: (pos, _) {
            if (pos.center != null) _center = pos.center!;
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.craigrallen.flutter_plotter',
          ),
          TileLayer(
            urlTemplate:
                'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.craigrallen.flutter_plotter',
          ),
          MarkerLayer(
            markers: visible
                .map((m) => Marker(
                      point: m.position,
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () => _showMarinaSheet(context, m),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _markerColor(m.type),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                              )
                            ],
                          ),
                          child: Icon(_markerIcon(m.type),
                              color: Colors.white, size: 22),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  String _filterLabel(_Filter f) {
    switch (f) {
      case _Filter.all:
        return 'All';
      case _Filter.fuel:
        return 'Fuel';
      case _Filter.water:
        return 'Water';
      case _Filter.shelter:
        return 'Shelter';
    }
  }

  void _showMarinaSheet(BuildContext context, _Marina marina) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MarinaBottomSheet(marina: marina),
    );
  }

  void _showReportDialog(BuildContext context, LatLng position) {
    if (!FloatillaService.instance.isLoggedIn()) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Log in to Floatilla to report locations')));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => _ReportDialog(position: position),
    );
  }
}

// ── Marina bottom sheet ───────────────────────────────────────────────────────

class _MarinaBottomSheet extends ConsumerStatefulWidget {
  final _Marina marina;
  const _MarinaBottomSheet({required this.marina});

  @override
  ConsumerState<_MarinaBottomSheet> createState() => _MarinaBottomSheetState();
}

class _MarinaBottomSheetState extends ConsumerState<_MarinaBottomSheet> {
  List<_MarinaNote> _notes = [];
  bool _loadingNotes = false;

  @override
  void initState() {
    super.initState();
    if (widget.marina.id != null) _loadNotes();
  }

  Future<void> _loadNotes() async {
    if (widget.marina.id == null) return;
    setState(() => _loadingNotes = true);
    try {
      final uri = Uri.parse(
          '${FloatillaService.instance.baseUrl}/marinas/${widget.marina.id}/notes?limit=5');
      final resp = await http.get(uri, headers: {
        if (FloatillaService.instance.token != null)
          'Authorization': 'Bearer ${FloatillaService.instance.token}',
      });
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        if (mounted) {
          setState(() => _notes =
              list.map((e) => _MarinaNote.fromJson(e as Map<String, dynamic>)).toList());
        }
      }
    } catch (e) { logError('_MarinaBottomSheetState._loadNotes', e); }
    if (mounted) setState(() => _loadingNotes = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.marina;
    final fmt = DateFormat('dd MMM yyyy');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name, style: Theme.of(context).textTheme.titleLarge),
                    Text(_marinaTypeLabel(m.type),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey)),
                    Text(
                      '${m.lat.toStringAsFixed(4)}N  ${m.lng.toStringAsFixed(4)}E',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('Update'),
                onPressed: () {
                  Navigator.pop(context);
                  _showUpdateDialog(context, m);
                },
              ),
            ],
          ),
          const Divider(height: 24),

          // Availability row
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _AvailChip(
                  label: 'Fuel',
                  avail: m.fuel,
                  icon: Icons.local_gas_station,
                  detail: m.fuelPrice != null ? '${m.fuelPrice}/L' : null),
              _AvailChip(
                  label: 'Water',
                  avail: m.water,
                  icon: Icons.water_drop),
              if (m.depthM != null)
                Chip(
                  avatar: const Icon(Icons.water, size: 16),
                  label: Text('Depth: ${m.depthM!.toStringAsFixed(1)} m'),
                ),
              if (m.vhfChannel != null)
                Chip(
                  avatar: const Icon(Icons.radio, size: 16),
                  label: Text('VHF Ch ${m.vhfChannel}'),
                ),
            ],
          ),

          // Facilities
          if (m.facilities.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Facilities', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (m.facilities['shower'] == true)
                  _FacilityIcon(icon: Icons.shower, label: 'Shower'),
                if (m.facilities['laundry'] == true)
                  _FacilityIcon(icon: Icons.local_laundry_service, label: 'Laundry'),
                if (m.facilities['wifi'] == true)
                  _FacilityIcon(icon: Icons.wifi, label: 'WiFi'),
                if (m.facilities['electricity'] == true)
                  _FacilityIcon(icon: Icons.electrical_services, label: 'Shore Power'),
                if (m.facilities['pumpout'] == true)
                  _FacilityIcon(icon: Icons.water_damage, label: 'Pump-out'),
              ],
            ),
          ],

          // Last updated
          if (m.updatedAt != null || m.createdBy != null) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (m.updatedAt != null) 'Updated ${fmt.format(m.updatedAt!)}',
                if (m.createdBy != null) 'by ${m.createdBy}',
              ].join(' '),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey),
            ),
          ],

          // Community notes
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Community Notes',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (FloatillaService.instance.isLoggedIn())
                TextButton.icon(
                  icon: const Icon(Icons.add_comment, size: 16),
                  label: const Text('Add'),
                  onPressed: () => _showAddNoteDialog(context, m),
                ),
            ],
          ),
          if (_loadingNotes)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            )
          else if (_notes.isEmpty)
            const Text('No notes yet.',
                style: TextStyle(color: Colors.grey))
          else
            for (final n in _notes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.note),
                    if (n.username != null || n.createdAt != null)
                      Text(
                        [
                          if (n.username != null) n.username!,
                          if (n.createdAt != null) fmt.format(n.createdAt!),
                        ].join(' · '),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: Colors.grey),
                      ),
                    const Divider(height: 8),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  void _showUpdateDialog(BuildContext context, _Marina marina) {
    showDialog<void>(
      context: context,
      builder: (_) => _UpdateMarinaDialog(marina: marina),
    );
  }

  void _showAddNoteDialog(BuildContext context, _Marina marina) {
    if (marina.id == null) return;
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Note'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Your note...'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context);
              await ref
                  .read(_marinasProvider.notifier)
                  .addNote(marina.id!, text);
              await _loadNotes();
            },
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }
}

// ── Availability chip ─────────────────────────────────────────────────────────

class _AvailChip extends StatelessWidget {
  final String label;
  final _Availability avail;
  final IconData icon;
  final String? detail;

  const _AvailChip({
    required this.label,
    required this.avail,
    required this.icon,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (avail) {
      case _Availability.yes:
        color = Colors.green;
        break;
      case _Availability.no:
        color = Colors.red;
        break;
      case _Availability.unknown:
        color = Colors.grey;
        break;
    }
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        detail != null ? '$label ($detail)' : label,
        style: TextStyle(color: color),
      ),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
    );
  }
}

class _FacilityIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FacilityIcon({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

// ── Report/Update dialog ──────────────────────────────────────────────────────

class _ReportDialog extends ConsumerStatefulWidget {
  final LatLng position;
  const _ReportDialog({required this.position});

  @override
  ConsumerState<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends ConsumerState<_ReportDialog> {
  final _nameCtrl = TextEditingController();
  final _depthCtrl = TextEditingController();
  final _vhfCtrl = TextEditingController();
  final _fuelPriceCtrl = TextEditingController();
  _MarinaType _type = _MarinaType.marina;
  _Availability _fuel = _Availability.unknown;
  _Availability _water = _Availability.unknown;
  final Map<String, bool> _facilities = {
    'shower': false,
    'laundry': false,
    'wifi': false,
    'electricity': false,
    'pumpout': false,
  };
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _depthCtrl.dispose();
    _vhfCtrl.dispose();
    _fuelPriceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report Location'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<_MarinaType>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: _MarinaType.values
                  .map((t) => DropdownMenuItem(
                      value: t, child: Text(_marinaTypeLabel(t))))
                  .toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 8),
            _AvailDropdown(
              label: 'Fuel',
              value: _fuel,
              onChanged: (v) => setState(() => _fuel = v),
            ),
            if (_fuel == _Availability.yes)
              TextField(
                controller: _fuelPriceCtrl,
                decoration: const InputDecoration(labelText: 'Fuel price (optional)'),
              ),
            const SizedBox(height: 8),
            _AvailDropdown(
              label: 'Water',
              value: _water,
              onChanged: (v) => setState(() => _water = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _depthCtrl,
              decoration: const InputDecoration(labelText: 'Depth (m)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _vhfCtrl,
              decoration: const InputDecoration(labelText: 'VHF channel'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            Text('Facilities', style: Theme.of(context).textTheme.labelMedium),
            for (final key in _facilities.keys)
              CheckboxListTile(
                title: Text(_facilityLabel(key)),
                value: _facilities[key],
                onChanged: (v) => setState(() => _facilities[key] = v!),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Submit'),
        ),
      ],
    );
  }

  String _facilityLabel(String key) {
    switch (key) {
      case 'shower':
        return 'Shower';
      case 'laundry':
        return 'Laundry';
      case 'wifi':
        return 'WiFi';
      case 'electricity':
        return 'Shore Power';
      case 'pumpout':
        return 'Pump-out';
      default:
        return key;
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _submitting = true);
    final marina = _Marina(
      lat: widget.position.latitude,
      lng: widget.position.longitude,
      name: name,
      type: _type,
      fuel: _fuel,
      fuelPrice:
          _fuelPriceCtrl.text.trim().isEmpty ? null : _fuelPriceCtrl.text.trim(),
      water: _water,
      depthM: double.tryParse(_depthCtrl.text),
      vhfChannel: int.tryParse(_vhfCtrl.text),
      facilities: Map.from(_facilities),
    );
    final ok =
        await ref.read(_marinasProvider.notifier).submitMarina(marina);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Location reported!' : 'Failed to submit'),
      ));
    }
  }
}

class _UpdateMarinaDialog extends ConsumerStatefulWidget {
  final _Marina marina;
  const _UpdateMarinaDialog({required this.marina});

  @override
  ConsumerState<_UpdateMarinaDialog> createState() =>
      _UpdateMarinaDialogState();
}

class _UpdateMarinaDialogState extends ConsumerState<_UpdateMarinaDialog> {
  late final TextEditingController _depthCtrl;
  late final TextEditingController _vhfCtrl;
  late final TextEditingController _fuelPriceCtrl;
  late _Availability _fuel;
  late _Availability _water;
  late Map<String, bool> _facilities;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final m = widget.marina;
    _depthCtrl = TextEditingController(text: m.depthM?.toStringAsFixed(1) ?? '');
    _vhfCtrl = TextEditingController(text: m.vhfChannel?.toString() ?? '');
    _fuelPriceCtrl = TextEditingController(text: m.fuelPrice ?? '');
    _fuel = m.fuel;
    _water = m.water;
    _facilities = {
      'shower': m.facilities['shower'] ?? false,
      'laundry': m.facilities['laundry'] ?? false,
      'wifi': m.facilities['wifi'] ?? false,
      'electricity': m.facilities['electricity'] ?? false,
      'pumpout': m.facilities['pumpout'] ?? false,
    };
  }

  @override
  void dispose() {
    _depthCtrl.dispose();
    _vhfCtrl.dispose();
    _fuelPriceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Update ${widget.marina.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AvailDropdown(
              label: 'Fuel',
              value: _fuel,
              onChanged: (v) => setState(() => _fuel = v),
            ),
            if (_fuel == _Availability.yes)
              TextField(
                controller: _fuelPriceCtrl,
                decoration:
                    const InputDecoration(labelText: 'Fuel price (optional)'),
              ),
            const SizedBox(height: 8),
            _AvailDropdown(
              label: 'Water',
              value: _water,
              onChanged: (v) => setState(() => _water = v),
            ),
            TextField(
              controller: _depthCtrl,
              decoration: const InputDecoration(labelText: 'Depth (m)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _vhfCtrl,
              decoration: const InputDecoration(labelText: 'VHF channel'),
              keyboardType: TextInputType.number,
            ),
            for (final key in _facilities.keys)
              CheckboxListTile(
                title: Text(_facilityLabel(key)),
                value: _facilities[key],
                onChanged: (v) => setState(() => _facilities[key] = v!),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  String _facilityLabel(String key) {
    switch (key) {
      case 'shower':
        return 'Shower';
      case 'laundry':
        return 'Laundry';
      case 'wifi':
        return 'WiFi';
      case 'electricity':
        return 'Shore Power';
      case 'pumpout':
        return 'Pump-out';
      default:
        return key;
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final m = widget.marina;
    final updated = _Marina(
      id: m.id,
      lat: m.lat,
      lng: m.lng,
      name: m.name,
      type: m.type,
      fuel: _fuel,
      fuelPrice: _fuelPriceCtrl.text.trim().isEmpty
          ? null
          : _fuelPriceCtrl.text.trim(),
      water: _water,
      depthM: double.tryParse(_depthCtrl.text),
      vhfChannel: int.tryParse(_vhfCtrl.text),
      facilities: Map.from(_facilities),
    );
    final ok = await ref.read(_marinasProvider.notifier).submitMarina(updated);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Updated!' : 'Failed to update'),
      ));
    }
  }
}

class _AvailDropdown extends StatelessWidget {
  final String label;
  final _Availability value;
  final ValueChanged<_Availability> onChanged;

  const _AvailDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<_Availability>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: const [
        DropdownMenuItem(value: _Availability.yes, child: Text('Yes')),
        DropdownMenuItem(value: _Availability.no, child: Text('No')),
        DropdownMenuItem(value: _Availability.unknown, child: Text('Unknown')),
      ],
      onChanged: (v) => onChanged(v!),
    );
  }
}
