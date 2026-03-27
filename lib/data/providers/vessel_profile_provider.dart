import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vessel_profile.dart';

class VesselProfileNotifier extends StateNotifier<VesselProfile> {
  static const _key = 'vessel_profile';

  VesselProfileNotifier() : super(const VesselProfile()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json != null) {
      state = VesselProfile.decode(json);
    }
  }

  Future<void> update(VesselProfile profile) async {
    state = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, profile.encode());
  }
}

final vesselProfileProvider =
    StateNotifierProvider<VesselProfileNotifier, VesselProfile>((ref) {
  return VesselProfileNotifier();
});
