import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/vessel_profile_provider.dart';

class VesselProfileEditor extends ConsumerStatefulWidget {
  const VesselProfileEditor({super.key});

  @override
  ConsumerState<VesselProfileEditor> createState() =>
      _VesselProfileEditorState();
}

class _VesselProfileEditorState extends ConsumerState<VesselProfileEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _draftController;
  late final TextEditingController _airDraftController;
  late final TextEditingController _beamController;
  late final TextEditingController _lengthController;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(vesselProfileProvider);
    _nameController = TextEditingController(text: profile.name);
    _draftController = TextEditingController(text: profile.draft.toString());
    _airDraftController =
        TextEditingController(text: profile.airDraft.toString());
    _beamController = TextEditingController(text: profile.beam.toString());
    _lengthController = TextEditingController(text: profile.length.toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _draftController.dispose();
    _airDraftController.dispose();
    _beamController.dispose();
    _lengthController.dispose();
    super.dispose();
  }

  String? _validatePositive(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final n = double.tryParse(value.trim());
    if (n == null || n <= 0) return 'Must be > 0';
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    ref.read(vesselProfileProvider.notifier).update(
          ref.read(vesselProfileProvider).copyWith(
                name: _nameController.text.trim(),
                draft: double.parse(_draftController.text.trim()),
                airDraft: double.parse(_airDraftController.text.trim()),
                beam: double.parse(_beamController.text.trim()),
                length: double.parse(_lengthController.text.trim()),
              ),
        );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vessel Profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Vessel Name',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _draftController,
              decoration: const InputDecoration(
                labelText: 'Draft (m)',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _validatePositive,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _airDraftController,
              decoration: const InputDecoration(
                labelText: 'Air Draft (m)',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _validatePositive,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _beamController,
              decoration: const InputDecoration(
                labelText: 'Beam (m)',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _validatePositive,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _lengthController,
              decoration: const InputDecoration(
                labelText: 'Length (m)',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _validatePositive,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
