// Mixer DSP Provider
//
// Bridge between UI mixer state and real DSP processing:
// - Bus management (master, music, sfx, ambience, voice)
// - Insert chain management
// - Parameter updates
// - Volume/pan/mute control
//
// CONNECTED TO RUST ENGINE via NativeFFI:
// - setBusVolume → engine_set_bus_volume
// - setBusPan → engine_set_bus_pan
// - toggleMute → engine_set_bus_mute
// - toggleSolo → engine_set_bus_solo

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

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
  // === Modern Digital EQ ===
  PluginInfo(
    id: 'rf-eq',
    name: 'FluxForge Studio EQ',
    category: 'EQ',
    icon: '📊',
    description: '64-band parametric EQ with linear phase',
  ),

  // === Vintage Analog EQs ===
  PluginInfo(
    id: 'rf-pultec',
    name: 'Pultec EQP-1A',
    category: 'EQ',
    icon: '🎚️',
    description: 'Passive tube EQ with boost+cut, 12AX7 saturation',
  ),
  PluginInfo(
    id: 'rf-api550',
    name: 'API 550A',
    category: 'EQ',
    icon: '🔷',
    description: '3-band discrete EQ with proportional Q',
  ),
  PluginInfo(
    id: 'rf-neve1073',
    name: 'Neve 1073',
    category: 'EQ',
    icon: '🔶',
    description: 'Inductor-based EQ with transformer saturation',
  ),

  // === Dynamics ===
  PluginInfo(
    id: 'rf-compressor',
    name: 'FluxForge Studio Compressor',
    category: 'Dynamics',
    icon: '📉',
    description: 'Transparent dynamics processor',
  ),
  PluginInfo(
    id: 'rf-limiter',
    name: 'FluxForge Studio Limiter',
    category: 'Dynamics',
    icon: '🚧',
    description: 'True peak brickwall limiter',
  ),
  PluginInfo(
    id: 'rf-gate',
    name: 'FluxForge Studio Gate',
    category: 'Dynamics',
    icon: '🚪',
    description: 'Noise gate with sidechain',
  ),
  PluginInfo(
    id: 'rf-deesser',
    name: 'FluxForge Studio De-Esser',
    category: 'Dynamics',
    icon: '🔇',
    description: 'Sibilance control for vocals',
  ),

  // === Time-Based ===
  PluginInfo(
    id: 'rf-reverb',
    name: 'FluxForge Studio Reverb',
    category: 'Time',
    icon: '🌊',
    description: 'Algorithmic reverb with early reflections',
  ),
  PluginInfo(
    id: 'rf-delay',
    name: 'FluxForge Studio Delay',
    category: 'Time',
    icon: '⏱️',
    description: 'Tempo-synced delay with filtering',
  ),

  // === Distortion ===
  PluginInfo(
    id: 'rf-saturator',
    name: 'FluxForge Studio Saturator',
    category: 'Distortion',
    icon: '🔥',
    description: 'Analog-style tape saturation',
  ),
];

// ============ Bus ID Mapping ============

/// Map string bus ID to engine bus index
/// Engine buses: 0=Master, 1=Music, 2=Sfx, 3=Voice, 4=Ambience, 5=Aux
/// MUST match Rust playback.rs bus processing loop (lines 3313-3319)
int _busIdToEngineIndex(String busId) {
  return switch (busId) {
    'master' => 0,
    'music' => 1,
    'sfx' => 2,
    'voice' => 3,
    'ambience' => 4,
    'aux' => 5,
    _ => 2, // Default to SFX
  };
}

// ============ Provider ============

class MixerDSPProvider extends ChangeNotifier {
  List<MixerBus> _buses = List.from(kDefaultBuses);
  bool _isConnected = false;
  String? _error;

  int _insertIdCounter = 0;

  // FFI reference
  final NativeFFI _ffi = NativeFFI.instance;

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

  /// Connect to audio backend and sync initial bus state to engine
  Future<void> connect() async {
    try {
      // Sync all bus states to Rust engine
      for (final bus in _buses) {
        final engineIdx = _busIdToEngineIndex(bus.id);
        _ffi.setBusVolume(engineIdx, bus.volume);
        _ffi.setBusPan(engineIdx, bus.pan);
        _ffi.setBusMute(engineIdx, bus.muted);
        _ffi.setBusSolo(engineIdx, bus.solo);
      }
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

  /// Set bus volume — syncs to Rust engine via FFI
  void setBusVolume(String busId, double volume) {
    final clampedVolume = volume.clamp(0.0, 1.0);
    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        return bus.copyWith(volume: clampedVolume);
      }
      return bus;
    }).toList();

    // Sync to Rust engine
    final engineIdx = _busIdToEngineIndex(busId);
    _ffi.setBusVolume(engineIdx, clampedVolume);

    notifyListeners();
  }

  /// Set bus pan — syncs to Rust engine via FFI
  void setBusPan(String busId, double pan) {
    final clampedPan = pan.clamp(-1.0, 1.0);
    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        return bus.copyWith(pan: clampedPan);
      }
      return bus;
    }).toList();

    // Sync to Rust engine
    final engineIdx = _busIdToEngineIndex(busId);
    _ffi.setBusPan(engineIdx, clampedPan);

    notifyListeners();
  }

  /// Toggle bus mute — syncs to Rust engine via FFI
  void toggleMute(String busId) {
    bool newMuted = false;
    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        newMuted = !bus.muted;
        return bus.copyWith(muted: newMuted);
      }
      return bus;
    }).toList();

    // Sync to Rust engine
    final engineIdx = _busIdToEngineIndex(busId);
    _ffi.setBusMute(engineIdx, newMuted);

    notifyListeners();
  }

  /// Toggle bus solo — syncs to Rust engine via FFI
  void toggleSolo(String busId) {
    bool newSolo = false;
    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        newSolo = !bus.solo;
        return bus.copyWith(solo: newSolo);
      }
      return bus;
    }).toList();

    // Sync to Rust engine
    final engineIdx = _busIdToEngineIndex(busId);
    _ffi.setBusSolo(engineIdx, newSolo);

    notifyListeners();
  }

  /// Add insert to bus — creates processor in Rust engine via FFI
  String? addInsert(String busId, String pluginId) {
    final plugin = kAvailablePlugins.where((p) => p.id == pluginId).firstOrNull;
    if (plugin == null) return null;

    final insertId = 'insert_${DateTime.now().millisecondsSinceEpoch}_${_insertIdCounter++}';

    // Find slot index (next available slot on this bus)
    final bus = getBus(busId);
    final slotIndex = bus?.inserts.length ?? 0;

    final newInsert = MixerInsert(
      id: insertId,
      pluginId: pluginId,
      name: plugin.name,
      params: _getDefaultParams(pluginId),
    );

    _buses = _buses.map((b) {
      if (b.id == busId) {
        return b.copyWith(inserts: [...b.inserts, newInsert]);
      }
      return b;
    }).toList();

    // Create insert chain and load processor in Rust engine
    final trackId = _busIdToEngineIndex(busId);
    _ffi.insertCreateChain(trackId);

    final processorName = _pluginIdToProcessorName(pluginId);
    if (processorName != null) {
      final result = _ffi.insertLoadProcessor(trackId, slotIndex, processorName);
    }

    notifyListeners();
    return insertId;
  }

  /// Remove insert from bus — unloads processor in Rust engine via FFI
  void removeInsert(String busId, String insertId) {
    // Find slot index before removing
    final bus = getBus(busId);
    final slotIndex = bus?.inserts.indexWhere((i) => i.id == insertId) ?? -1;

    _buses = _buses.map((b) {
      if (b.id == busId) {
        return b.copyWith(
          inserts: b.inserts.where((i) => i.id != insertId).toList(),
        );
      }
      return b;
    }).toList();

    // Unload processor from Rust engine
    if (slotIndex >= 0) {
      final trackId = _busIdToEngineIndex(busId);
      _ffi.insertUnloadSlot(trackId, slotIndex);
    }

    notifyListeners();
  }

  /// Toggle insert bypass — syncs to Rust engine via FFI
  void toggleBypass(String busId, String insertId) {
    int slotIndex = -1;
    bool newBypassed = false;

    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        final newInserts = bus.inserts.asMap().entries.map((entry) {
          if (entry.value.id == insertId) {
            slotIndex = entry.key;
            newBypassed = !entry.value.bypassed;
            return entry.value.copyWith(bypassed: newBypassed);
          }
          return entry.value;
        }).toList();
        return bus.copyWith(inserts: newInserts);
      }
      return bus;
    }).toList();

    // Sync bypass state to Rust engine
    if (slotIndex >= 0) {
      final trackId = _busIdToEngineIndex(busId);
      _ffi.insertSetBypass(trackId, slotIndex, newBypassed);
    }

    notifyListeners();
  }

  /// Update insert parameters — syncs to Rust engine via FFI
  void updateInsertParams(String busId, String insertId, Map<String, double> params) {
    int slotIndex = -1;
    String? pluginId;

    _buses = _buses.map((bus) {
      if (bus.id == busId) {
        final newInserts = bus.inserts.asMap().entries.map((entry) {
          if (entry.value.id == insertId) {
            slotIndex = entry.key;
            pluginId = entry.value.pluginId;
            return entry.value.copyWith(
              params: {...entry.value.params, ...params},
            );
          }
          return entry.value;
        }).toList();
        return bus.copyWith(inserts: newInserts);
      }
      return bus;
    }).toList();

    // Sync parameters to Rust engine
    if (slotIndex >= 0 && pluginId != null) {
      final trackId = _busIdToEngineIndex(busId);
      final paramMapping = _getParamIndexMapping(pluginId!);

      for (final entry in params.entries) {
        final paramIndex = paramMapping[entry.key];
        if (paramIndex != null) {
          _ffi.insertSetParam(trackId, slotIndex, paramIndex, entry.value);
        }
      }
    }

    notifyListeners();
  }

  /// Get parameter name to index mapping for a plugin
  /// These mappings correspond to Rust processor parameter indices in dsp_wrappers.rs
  Map<String, int> _getParamIndexMapping(String pluginId) {
    switch (pluginId) {
      // === Modern Digital ===
      case 'rf-eq':
        return {
          'lowGain': 0, 'lowFreq': 1,
          'midGain': 2, 'midFreq': 3, 'midQ': 4,
          'highGain': 5, 'highFreq': 6,
        };
      case 'rf-compressor':
        return {
          'threshold': 0, 'ratio': 1,
          'attack': 2, 'release': 3, 'makeupGain': 4,
        };
      case 'rf-limiter':
        return {'ceiling': 0, 'release': 1};
      case 'rf-reverb':
        return {'size': 0, 'decay': 1, 'damping': 2, 'mix': 3};
      case 'rf-delay':
        return {
          'time': 0, 'feedback': 1, 'mix': 2,
          'lowCut': 3, 'highCut': 4,
        };
      case 'rf-gate':
        return {'threshold': 0, 'attack': 1, 'hold': 2, 'release': 3};
      case 'rf-saturator':
        return {'drive': 0, 'mix': 1};
      case 'rf-deesser':
        return {'threshold': 0, 'frequency': 1, 'range': 2};

      // === Vintage Analog EQs ===
      // Pultec EQP-1A: Passive tube EQ (4 params)
      case 'rf-pultec':
        return {
          'lowBoost': 0,   // Low frequency boost (0-10 dB)
          'lowAtten': 1,   // Low frequency attenuation (0-10 dB)
          'highBoost': 2,  // High frequency boost (0-10 dB)
          'highAtten': 3,  // High frequency attenuation (0-10 dB)
        };

      // API 550A: 3-band discrete EQ (3 params - gain only)
      case 'rf-api550':
        return {
          'lowGain': 0,   // Low band gain (-12 to +12 dB)
          'midGain': 1,   // Mid band gain (-12 to +12 dB)
          'highGain': 2,  // High band gain (-12 to +12 dB)
        };

      // Neve 1073: Inductor-based EQ (3 params)
      case 'rf-neve1073':
        return {
          'hpEnabled': 0,  // High-pass filter enabled (0/1)
          'lowGain': 1,    // Low shelf gain (-16 to +16 dB)
          'highGain': 2,   // High shelf gain (-16 to +16 dB)
        };

      default:
        return {};
    }
  }

  /// Map plugin ID to Rust processor name
  /// These names must match create_processor() in dsp_wrappers.rs
  String? _pluginIdToProcessorName(String pluginId) {
    const mapping = {
      // Modern digital
      'rf-eq': 'pro-eq',
      'rf-compressor': 'compressor',
      'rf-limiter': 'limiter',
      'rf-reverb': 'reverb',
      'rf-delay': 'delay',
      'rf-gate': 'gate',
      'rf-saturator': 'saturator',
      'rf-deesser': 'deesser',
      // Vintage analog EQs
      'rf-pultec': 'pultec',
      'rf-api550': 'api550',
      'rf-neve1073': 'neve1073',
    };
    return mapping[pluginId];
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
  /// Values match Rust DSP defaults from eq_analog.rs and dsp_wrappers.rs
  Map<String, double> _getDefaultParams(String pluginId) {
    switch (pluginId) {
      // === Modern Digital ===
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

      // === Vintage Analog EQs ===
      // Pultec EQP-1A: All at 0 = transparent pass-through
      case 'rf-pultec':
        return {
          'lowBoost': 0,   // No boost (0-10 range)
          'lowAtten': 0,   // No attenuation (0-10 range)
          'highBoost': 0,  // No boost (0-10 range)
          'highAtten': 0,  // No attenuation (0-10 range)
        };

      // API 550A: All gains at 0 = flat response
      case 'rf-api550':
        return {
          'lowGain': 0,   // 0 dB (-12 to +12 range)
          'midGain': 0,   // 0 dB (-12 to +12 range)
          'highGain': 0,  // 0 dB (-12 to +12 range)
        };

      // Neve 1073: HP off, gains at 0 = flat response
      case 'rf-neve1073':
        return {
          'hpEnabled': 0,  // HP filter off
          'lowGain': 0,    // 0 dB (-16 to +16 range)
          'highGain': 0,   // 0 dB (-16 to +16 range)
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
