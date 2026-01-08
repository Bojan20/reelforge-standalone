// Mixer DSP Provider
//
// Bridge between UI mixer state and real DSP processing:
// - Bus management (master, music, sfx, ambience, voice)
// - Insert chain management
// - Parameter updates
// - Volume/pan/mute control

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

// ============ Types ============

class MixerInsert {
  final String id;
  final String pluginId;
  final String name;
  final bool bypassed;
  final Map<String, double> params;

  const MixerInsert({
    required this.id,
    required this.pluginId,
    required this.name,
    this.bypassed = false,
    this.params = const {},
  });

  MixerInsert copyWith({
    String? id,
    String? pluginId,
    String? name,
    bool? bypassed,
    Map<String, double>? params,
  }) {
    return MixerInsert(
      id: id ?? this.id,
      pluginId: pluginId ?? this.pluginId,
      name: name ?? this.name,
      bypassed: bypassed ?? this.bypassed,
      params: params ?? this.params,
    );
  }
}

class MixerBus {
  final String id;
  final String name;
  final double volume;
  final double pan;
  final bool muted;
  final bool solo;
  final List<MixerInsert> inserts;

  const MixerBus({
    required this.id,
    required this.name,
    this.volume = 0.85,
    this.pan = 0,
    this.muted = false,
    this.solo = false,
    this.inserts = const [],
  });

  MixerBus copyWith({
    String? id,
    String? name,
    double? volume,
    double? pan,
    bool? muted,
    bool? solo,
    List<MixerInsert>? inserts,
  }) {
    return MixerBus(
      id: id ?? this.id,
      name: name ?? this.name,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      muted: muted ?? this.muted,
      solo: solo ?? this.solo,
      inserts: inserts ?? this.inserts,
    );
  }
}

class PluginInfo {
  final String id;
  final String name;
  final String category;
  final String icon;
  final String description;

  const PluginInfo({
    required this.id,
    required this.name,
    required this.category,
    this.icon = '🔌',
    this.description = '',
  });
}

// ============ Default Buses ============

const List<MixerBus> kDefaultBuses = [
  MixerBus(id: 'master', name: 'Master', volume: 0.85),
  MixerBus(id: 'music', name: 'Music', volume: 0.7),
  MixerBus(id: 'sfx', name: 'SFX', volume: 0.9),
  MixerBus(id: 'ambience', name: 'Ambience', volume: 0.5),
  MixerBus(id: 'voice', name: 'Voice', volume: 0.95),
];

// ============ Available Plugins ============

const List<PluginInfo> kAvailablePlugins = [
  PluginInfo(
    id: 'rf-eq',
    name: 'ReelForge EQ',
    category: 'EQ',
    icon: '📊',
    description: '64-band parametric EQ with linear phase',
  ),
  PluginInfo(
    id: 'rf-compressor',
    name: 'ReelForge Compressor',
    category: 'Dynamics',
    icon: '📉',
    description: 'Transparent dynamics processor',
  ),
  PluginInfo(
    id: 'rf-limiter',
    name: 'ReelForge Limiter',
    category: 'Dynamics',
    icon: '🚧',
    description: 'True peak brickwall limiter',
  ),
  PluginInfo(
    id: 'rf-reverb',
    name: 'ReelForge Reverb',
    category: 'Time',
    icon: '🌊',
    description: 'Algorithmic reverb with early reflections',
  ),
  PluginInfo(
    id: 'rf-delay',
    name: 'ReelForge Delay',
    category: 'Time',
    icon: '⏱️',
    description: 'Tempo-synced delay with filtering',
  ),
  PluginInfo(
    id: 'rf-gate',
    name: 'ReelForge Gate',
    category: 'Dynamics',
    icon: '🚪',
    description: 'Noise gate with sidechain',
  ),
  PluginInfo(
    id: 'rf-saturator',
    name: 'ReelForge Saturator',
    category: 'Distortion',
    icon: '🔥',
    description: 'Analog-style tape saturation',
  ),
  PluginInfo(
    id: 'rf-deesser',
    name: 'ReelForge De-Esser',
    category: 'Dynamics',
    icon: '🔇',
    description: 'Sibilance control for vocals',
  ),
];

// ============ Provider ============

class MixerDSPProvider extends ChangeNotifier {
  List<MixerBus> _buses = List.from(kDefaultBuses);
  bool _isConnected = false;
  String? _error;

  int _insertIdCounter = 0;

  List<MixerBus> get buses => _buses;
  bool get isConnected => _isConnected;
  String? get error => _error;
  List<PluginInfo> get availablePlugins => kAvailablePlugins;

  MixerBus? getBus(String id) {
    try {
      return _buses.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Connect to audio backend
  Future<void> connect() async {
    try {
      // In real implementation, this would connect to Rust audio engine
      await Future.delayed(const Duration(milliseconds: 100));
      _isConnected = true;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Disconnect from audio backend
  void disconnect() {
    _isConnected = false;
    notifyListeners();
  }

  /// Set bus volume
  void setBusVolume(String busId, double volume) {
    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        return bus.copyWith(volume: volume.clamp(0.0, 1.0));
      }
      return bus;
    }).toList();
    notifyListeners();
  }

  /// Set bus pan
  void setBusPan(String busId, double pan) {
    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        return bus.copyWith(pan: pan.clamp(-1.0, 1.0));
      }
      return bus;
    }).toList();
    notifyListeners();
  }

  /// Toggle bus mute
  void toggleMute(String busId) {
    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        return bus.copyWith(muted: !bus.muted);
      }
      return bus;
    }).toList();
    notifyListeners();
  }

  /// Toggle bus solo
  void toggleSolo(String busId) {
    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        return bus.copyWith(solo: !bus.solo);
      }
      return bus;
    }).toList();
    notifyListeners();
  }

  /// Add insert to bus
  String? addInsert(String busId, String pluginId) {
    final plugin = kAvailablePlugins.where((p) => p.id == pluginId).firstOrNull;
    if (plugin == null) return null;

    final insertId = 'insert_${DateTime.now().millisecondsSinceEpoch}_${_insertIdCounter++}';

    final newInsert = MixerInsert(
      id: insertId,
      pluginId: pluginId,
      name: plugin.name,
      params: _getDefaultParams(pluginId),
    );

    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        return bus.copyWith(inserts: [...bus.inserts, newInsert]);
      }
      return bus;
    }).toList();

    notifyListeners();
    return insertId;
  }

  /// Remove insert from bus
  void removeInsert(String busId, String insertId) {
    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        return bus.copyWith(
          inserts: bus.inserts.where((i) => i.id != insertId).toList(),
        );
      }
      return bus;
    }).toList();
    notifyListeners();
  }

  /// Toggle insert bypass
  void toggleBypass(String busId, String insertId) {
    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        return bus.copyWith(
          inserts: bus.inserts.map((insert) {
            if (insert.id == insertId) {
              return insert.copyWith(bypassed: !insert.bypassed);
            }
            return insert;
          }).toList(),
        );
      }
      return bus;
    }).toList();
    notifyListeners();
  }

  /// Update insert parameters
  void updateInsertParams(String busId, String insertId, Map<String, double> params) {
    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        return bus.copyWith(
          inserts: bus.inserts.map((insert) {
            if (insert.id == insertId) {
              return insert.copyWith(
                params: {...insert.params, ...params},
              );
            }
            return insert;
          }).toList(),
        );
      }
      return bus;
    }).toList();
    notifyListeners();
  }

  /// Reorder inserts within a bus
  void reorderInserts(String busId, int oldIndex, int newIndex) {
    final busIndex = _buses.indexWhere((b) => b.id == busId);
    if (busIndex == -1) return;

    final bus = _buses[busIndex];
    final inserts = List<MixerInsert>.from(bus.inserts);

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final insert = inserts.removeAt(oldIndex);
    inserts.insert(newIndex, insert);

    _buses = List.from(_buses);
    _buses[busIndex] = bus.copyWith(inserts: inserts);
    notifyListeners();
  }

  /// Get default parameters for a plugin
  Map<String, double> _getDefaultParams(String pluginId) {
    switch (pluginId) {
      case 'rf-eq':
        return {
          'lowGain': 0,
          'lowFreq': 80,
          'midGain': 0,
          'midFreq': 1000,
          'midQ': 1,
          'highGain': 0,
          'highFreq': 8000,
        };
      case 'rf-compressor':
        return {
          'threshold': -20,
          'ratio': 4,
          'attack': 10,
          'release': 100,
          'makeupGain': 0,
        };
      case 'rf-limiter':
        return {
          'ceiling': -1,
          'release': 50,
        };
      case 'rf-reverb':
        return {
          'size': 0.5,
          'decay': 2,
          'damping': 0.5,
          'mix': 0.3,
        };
      case 'rf-delay':
        return {
          'time': 500,
          'feedback': 0.3,
          'mix': 0.3,
          'lowCut': 200,
          'highCut': 8000,
        };
      case 'rf-gate':
        return {
          'threshold': -40,
          'attack': 1,
          'hold': 50,
          'release': 100,
        };
      case 'rf-saturator':
        return {
          'drive': 0,
          'mix': 1,
        };
      case 'rf-deesser':
        return {
          'threshold': -20,
          'frequency': 6000,
          'range': 6,
        };
      default:
        return {};
    }
  }

  /// Reset to default buses
  void reset() {
    _buses = List.from(kDefaultBuses);
    notifyListeners();
  }
}

// ============ Utility Functions ============

/// Convert linear amplitude to dB
double linearToDb(double linear) {
  if (linear <= 0) return double.negativeInfinity;
  return 20 * math.log(linear) / math.ln10;
}

/// Convert dB to linear amplitude
double dbToLinear(double db) {
  if (db <= -120) return 0;
  return math.pow(10, db / 20).toDouble();
}
