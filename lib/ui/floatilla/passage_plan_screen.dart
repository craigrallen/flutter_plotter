import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/providers/vessel_provider.dart';

/// Passage planning screen — combine waypoints + fuel + tides + weather
/// into a go/no-go passage summary.
class PassagePlanScreen extends ConsumerStatefulWidget {
  const PassagePlanScreen({super.key});

  @override
  ConsumerState<PassagePlanScreen> createState() => _PassagePlanScreenState();
}

class _PassagePlanScreenState extends ConsumerState<PassagePlanScreen> {
  final _destCtrl = TextEditingController();
  final _distCtrl = TextEditingController();
  final _fuelCtrl = TextEditingController();
  final _speedCtrl = TextEditingController();
  DateTime _departureTime = DateTime.now().add(const Duration(hours: 1));
  bool _calculated = false;
  _PassageSummary? _summary;

  @override
  void dispose() {
    _destCtrl.dispose();
    _distCtrl.dispose();
    _fuelCtrl.dispose();
    _speedCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final dist = double.tryParse(_distCtrl.text.trim());
    final speed = double.tryParse(_speedCtrl.text.trim());
    final fuel = double.tryParse(_fuelCtrl.text.trim());
    if (dist == null || speed == null || speed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter distance and speed')),
      );
      return;
    }

    final hours = dist / speed;
    final arrivalTime = _departureTime.add(Duration(
      hours: hours.floor(),
      minutes: ((hours - hours.floor()) * 60).round(),
    ));

    final vessel = ref.read(vesselProvider);

    // Rough fuel estimate: assume 5L/hr at hull speed, scale by speed²
    const hullSpeed = 6.0; // default hull speed knots
    final fuelRate = 5.0 * (speed / hullSpeed) * (speed / hullSpeed);
    final fuelNeeded = fuelRate * hours;
    final fuelRemaining = fuel ?? 0;
    final fuelOk = fuel == null || fuelRemaining >= fuelNeeded * 1.2;

    setState(() {
      _calculated = true;
      _summary = _PassageSummary(
        destination: _destCtrl.text.trim(),
        distanceNm: dist,
        speedKn: speed,
        durationHours: hours,
        departureTime: _departureTime,
        arrivalTime: arrivalTime,
        fuelNeededL: fuelNeeded,
        fuelOk: fuelOk,
        startPos: vessel.position,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Passage Plan')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Input card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Plan your passage',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _destCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Destination',
                        prefixIcon: Icon(Icons.flag),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _distCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Distance (nm)',
                              prefixIcon: Icon(Icons.straighten),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _speedCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Speed (kn)',
                              prefixIcon: Icon(Icons.speed),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fuelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Fuel onboard (L)',
                        prefixIcon: Icon(Icons.local_gas_station),
                        border: OutlineInputBorder(),
                        helperText: 'Optional',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    // Departure time
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _departureTime,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 365)),
                        );
                        if (date == null || !mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(_departureTime),
                        );
                        if (time == null) return;
                        setState(() {
                          _departureTime = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Departure',
                          prefixIcon: Icon(Icons.schedule),
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          DateFormat('EEE dd MMM HH:mm')
                              .format(_departureTime),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.calculate),
                      label: const Text('Calculate passage'),
                      onPressed: _calculate,
                    ),
                  ],
                ),
              ),
            ),

            // Summary card
            if (_calculated && _summary != null) ...[
              const SizedBox(height: 16),
              _PassageSummaryCard(summary: _summary!),
            ],

            const SizedBox(height: 16),
            // Info card
            Card(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withOpacity(0.5),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 16),
                        SizedBox(width: 6),
                        Text('Coming soon',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Live weather forecast, tidal current overlays, '
                      'and fuel consumption curves are planned for '
                      'Floatilla Pro.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassageSummary {
  final String destination;
  final double distanceNm;
  final double speedKn;
  final double durationHours;
  final DateTime departureTime;
  final DateTime arrivalTime;
  final double fuelNeededL;
  final bool fuelOk;
  final dynamic startPos;

  const _PassageSummary({
    required this.destination,
    required this.distanceNm,
    required this.speedKn,
    required this.durationHours,
    required this.departureTime,
    required this.arrivalTime,
    required this.fuelNeededL,
    required this.fuelOk,
    this.startPos,
  });
}

class _PassageSummaryCard extends StatelessWidget {
  final _PassageSummary summary;

  const _PassageSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final h = summary.durationHours.floor();
    final m = ((summary.durationHours - h) * 60).round();
    final durationStr = '${h}h ${m}m';

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  summary.destination.isNotEmpty
                      ? 'Passage to ${summary.destination}'
                      : 'Passage summary',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _SummaryItem(
                    icon: Icons.straighten,
                    label: 'Distance',
                    value: '${summary.distanceNm.toStringAsFixed(1)} nm'),
                _SummaryItem(
                    icon: Icons.speed,
                    label: 'Speed',
                    value: '${summary.speedKn.toStringAsFixed(1)} kn'),
                _SummaryItem(
                    icon: Icons.timer,
                    label: 'Duration',
                    value: durationStr),
                _SummaryItem(
                    icon: Icons.departure_board,
                    label: 'Depart',
                    value: DateFormat('HH:mm EEE').format(summary.departureTime)),
                _SummaryItem(
                    icon: Icons.flag,
                    label: 'Arrive',
                    value: DateFormat('HH:mm EEE dd MMM')
                        .format(summary.arrivalTime)),
                _SummaryItem(
                  icon: Icons.local_gas_station,
                  label: 'Fuel est.',
                  value: '${summary.fuelNeededL.toStringAsFixed(0)} L',
                  valueColor: summary.fuelOk ? null : Colors.red,
                ),
              ],
            ),
            if (!summary.fuelOk) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Estimated fuel may be insufficient. '
                        'Add 20% reserve margin.',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(label,
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
