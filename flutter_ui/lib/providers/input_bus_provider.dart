/// Input Bus Provider
///
/// Manages input bus system:
/// - Virtual buses mapping hardware inputs
/// - Bus creation/deletion
/// - Peak metering
/// - Enable/disable state

import 'package:flutter/foundation.dart';
import '../src/rust/engine_api.dart' as api;

class InputBusInfo {
  final int id;
  final String name;
  final int channels;
  final bool enabled;
  final double peakL;
  final double peakR;

  InputBusInfo({
    required this.id,
    required this.name,
    required this.channels,
    required this.enabled,
    this.peakL = 0.0,
    this.peakR = 0.0,
  });
}

class InputBusProvider extends ChangeNotifier {
  final Map<int, InputBusInfo> _buses = {};

  List<InputBusInfo> get buses => _buses.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  int get busCount => _buses.length;

  /// Initialize - load existing buses
  Future<void> initialize() async {
    await refresh();
  }

  /// Create stereo input bus (hardware inputs 0-1)
  Future<int?> createStereoBus(String name) async {
    final busId = api.inputBusCreateStereo(name);
    if (busId > 0) {
      await refresh();
      return busId;
    }
    return null;
  }

  /// Create mono input bus
  Future<int?> createMonoBus(String name, int hwChannel) async {
    final busId = api.inputBusCreateMono(name, hwChannel);
    if (busId > 0) {
      await refresh();
      return busId;
    }
    return null;
  }

  /// Delete bus
  Future<bool> deleteBus(int busId) async {
    if (api.inputBusDelete(busId)) {
      _buses.remove(busId);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Enable/disable bus
  Future<void> setBusEnabled(int busId, bool enabled) async {
    api.inputBusSetEnabled(busId, enabled);
    if (_buses.containsKey(busId)) {
      _buses[busId] = InputBusInfo(
        id: busId,
        name: _buses[busId]!.name,
        channels: _buses[busId]!.channels,
        enabled: enabled,
        peakL: _buses[busId]!.peakL,
        peakR: _buses[busId]!.peakR,
      );
      notifyListeners();
    }
  }

  /// Refresh all buses from Rust
  Future<void> refresh() async {
    final count = api.inputBusCount();
    final Map<int, InputBusInfo> newBuses = {};

    // Note: We don't have a way to enumerate bus IDs from Rust yet
    // For now, assume sequential IDs starting from 1
    for (int id = 1; id <= count; id++) {
      final name = api.inputBusGetName(id);
      if (name != null) {
        final channels = api.inputBusGetChannels(id);
        final enabled = api.inputBusIsEnabled(id);
        final peakL = api.inputBusGetPeak(id, 0);
        final peakR = channels > 1 ? api.inputBusGetPeak(id, 1) : 0.0;

        newBuses[id] = InputBusInfo(
          id: id,
          name: name,
          channels: channels,
          enabled: enabled,
          peakL: peakL,
          peakR: peakR,
        );
      }
    }

    _buses.clear();
    _buses.addAll(newBuses);
    notifyListeners();
  }

  /// Update peak meters only (called frequently)
  Future<void> updateMeters() async {
    bool updated = false;
    for (final entry in _buses.entries) {
      final id = entry.key;
      final bus = entry.value;

      final peakL = api.inputBusGetPeak(id, 0);
      final peakR = bus.channels > 1 ? api.inputBusGetPeak(id, 1) : 0.0;

      if ((peakL - bus.peakL).abs() > 0.001 || (peakR - bus.peakR).abs() > 0.001) {
        _buses[id] = InputBusInfo(
          id: id,
          name: bus.name,
          channels: bus.channels,
          enabled: bus.enabled,
          peakL: peakL,
          peakR: peakR,
        );
        updated = true;
      }
    }

    if (updated) {
      notifyListeners();
    }
  }

  /// Get bus by ID
  InputBusInfo? getBus(int busId) => _buses[busId];
}
