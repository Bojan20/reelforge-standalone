/// Bus Hierarchy Provider
///
/// Extracted from MiddlewareProvider as part of Provider Decomposition.
/// Manages the audio bus hierarchy (Wwise/FMOD-style bus routing).
///
/// Provides hierarchical bus structure with:
/// - Master bus with child groups (Music, SFX, Voice, UI)
/// - Sub-buses for granular control
/// - Effect insert slots per bus
/// - Volume propagation through parent chain

import 'package:flutter/foundation.dart';
import '../../models/advanced_middleware_models.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for managing audio bus hierarchy
class BusHierarchyProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  /// Internal bus storage
  final Map<int, AudioBus> _buses = {};

  /// Next available bus ID
  int _nextBusId = 50; // Start after reserved IDs

  BusHierarchyProvider({required NativeFFI ffi}) : _ffi = ffi {
    _createDefaultHierarchy();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DEFAULT HIERARCHY
  // ═══════════════════════════════════════════════════════════════════════════

  void _createDefaultHierarchy() {
    // Master bus (ID: 0)
    _buses[0] = AudioBus(busId: 0, name: 'Master', childBusIds: [1, 2, 3, 4]);

    // Main groups
    _buses[1] = AudioBus(busId: 1, name: 'Music', parentBusId: 0, childBusIds: [10, 11]);
    _buses[2] = AudioBus(busId: 2, name: 'SFX', parentBusId: 0, childBusIds: [20, 21, 22]);
    _buses[3] = AudioBus(busId: 3, name: 'Voice', parentBusId: 0, childBusIds: [30, 31]);
    _buses[4] = AudioBus(busId: 4, name: 'UI', parentBusId: 0);

    // Music sub-buses
    _buses[10] = AudioBus(busId: 10, name: 'Music_Base', parentBusId: 1);
    _buses[11] = AudioBus(busId: 11, name: 'Music_Wins', parentBusId: 1);

    // SFX sub-buses
    _buses[20] = AudioBus(busId: 20, name: 'SFX_Reels', parentBusId: 2);
    _buses[21] = AudioBus(busId: 21, name: 'SFX_Wins', parentBusId: 2);
    _buses[22] = AudioBus(busId: 22, name: 'SFX_Anticipation', parentBusId: 2);

    // Voice sub-buses
    _buses[30] = AudioBus(busId: 30, name: 'VO_Announcer', parentBusId: 3);
    _buses[31] = AudioBus(busId: 31, name: 'VO_Celebration', parentBusId: 3);

    // Add default effects to master
    _buses[0]!.addPostInsert(EffectSlot(
      slotIndex: 0,
      type: EffectType.limiter,
      params: {'ceiling': -0.3, 'release': 50.0, 'truePeak': 1.0},
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get a specific bus
  AudioBus? getBus(int busId) => _buses[busId];

  /// Get all buses
  List<AudioBus> get allBuses => _buses.values.toList();

  /// Get master bus
  AudioBus get master => _buses[0]!;

  /// Get all bus IDs
  List<int> get allBusIds => _buses.keys.toList();

  /// Get bus by name
  AudioBus? getBusByName(String name) {
    return _buses.values.where((b) => b.name == name).firstOrNull;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HIERARCHY TRAVERSAL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all children recursively
  List<AudioBus> getDescendants(int busId) {
    final bus = _buses[busId];
    if (bus == null) return [];

    final descendants = <AudioBus>[];
    for (final childId in bus.childBusIds) {
      final child = _buses[childId];
      if (child != null) {
        descendants.add(child);
        descendants.addAll(getDescendants(childId));
      }
    }
    return descendants;
  }

  /// Get parent chain (from bus to master)
  List<AudioBus> getParentChain(int busId) {
    final chain = <AudioBus>[];
    int? currentId = busId;

    while (currentId != null) {
      final bus = _buses[currentId];
      if (bus == null) break;
      chain.add(bus);
      currentId = bus.parentBusId;
    }

    return chain;
  }

  /// Calculate effective volume (considering parent chain)
  double getEffectiveVolume(int busId) {
    final bus = _buses[busId];
    if (bus == null) return 0.0;
    if (bus.mute) return 0.0;

    double vol = bus.volume;
    int? parentId = bus.parentBusId;

    while (parentId != null) {
      final parent = _buses[parentId];
      if (parent == null) break;
      if (parent.mute) return 0.0;
      vol *= parent.volume;
      parentId = parent.parentBusId;
    }

    return vol;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUS MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a new bus
  void addBus(AudioBus bus) {
    _buses[bus.busId] = bus;
    if (bus.parentBusId != null) {
      _buses[bus.parentBusId]?.childBusIds.add(bus.busId);
    }
    notifyListeners();
  }

  /// Create and add a new bus
  AudioBus createBus({
    required String name,
    int? parentBusId,
  }) {
    final busId = _nextBusId++;
    final bus = AudioBus(
      busId: busId,
      name: name,
      parentBusId: parentBusId ?? 0,
    );
    addBus(bus);
    return bus;
  }

  /// Remove a bus (children become orphaned and should be handled separately)
  /// Note: parentBusId is final in AudioBus, so true reparenting would require
  /// creating new AudioBus instances. For now, we just remove from parent's childBusIds.
  void removeBus(int busId) {
    final bus = _buses[busId];
    if (bus == null || busId == 0) return; // Can't remove master

    // Add children to parent's childBusIds (they keep their old parentBusId)
    if (bus.parentBusId != null) {
      final parent = _buses[bus.parentBusId];
      if (parent != null) {
        parent.childBusIds.addAll(bus.childBusIds);
        parent.childBusIds.remove(busId);
      }
    }

    _buses.remove(busId);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUS PARAMETERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set bus volume
  void setBusVolume(int busId, double volume) {
    final bus = _buses[busId];
    if (bus != null) {
      bus.volume = volume.clamp(0.0, 1.0);

      // Sync to Rust engine
      _ffi.setBusVolume(busId, volume);

      notifyListeners();
    }
  }

  /// Toggle bus mute
  void toggleBusMute(int busId) {
    final bus = _buses[busId];
    if (bus != null) {
      bus.mute = !bus.mute;

      // Sync to Rust engine
      _ffi.setBusMute(busId, bus.mute);

      notifyListeners();
    }
  }

  /// Toggle bus solo
  void toggleBusSolo(int busId) {
    final bus = _buses[busId];
    if (bus != null) {
      bus.solo = !bus.solo;

      // Sync to Rust engine
      _ffi.setBusSolo(busId, bus.solo);

      notifyListeners();
    }
  }

  /// Set bus pan
  void setBusPan(int busId, double pan) {
    final bus = _buses[busId];
    if (bus != null) {
      bus.pan = pan.clamp(-1.0, 1.0);

      // Sync to Rust engine
      _ffi.setBusPan(busId, pan);

      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EFFECT SLOTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add pre-insert effect to bus
  void addBusPreInsert(int busId, EffectSlot effect) {
    final bus = _buses[busId];
    if (bus != null) {
      bus.addPreInsert(effect);
      notifyListeners();
    }
  }

  /// Add post-insert effect to bus
  void addBusPostInsert(int busId, EffectSlot effect) {
    final bus = _buses[busId];
    if (bus != null) {
      bus.addPostInsert(effect);
      notifyListeners();
    }
  }

  /// Remove effect from bus
  void removeBusEffect(int busId, int slotIndex, bool isPreInsert) {
    final bus = _buses[busId];
    if (bus != null) {
      if (isPreInsert) {
        bus.preInserts.removeWhere((e) => e.slotIndex == slotIndex);
      } else {
        bus.postInserts.removeWhere((e) => e.slotIndex == slotIndex);
      }
      notifyListeners();
    }
  }

  /// Toggle effect bypass
  void toggleBusEffectBypass(int busId, int slotIndex, bool isPreInsert) {
    final bus = _buses[busId];
    if (bus != null) {
      final effects = isPreInsert ? bus.preInserts : bus.postInserts;
      final effect = effects.where((e) => e.slotIndex == slotIndex).firstOrNull;
      if (effect != null) {
        effect.bypass = !effect.bypass;
        notifyListeners();
      }
    }
  }

  /// Update effect parameter
  void setBusEffectParam(int busId, int slotIndex, bool isPreInsert, String param, double value) {
    final bus = _buses[busId];
    if (bus != null) {
      final effects = isPreInsert ? bus.preInserts : bus.postInserts;
      final effect = effects.where((e) => e.slotIndex == slotIndex).firstOrNull;
      if (effect != null && effect.params.containsKey(param)) {
        effect.params[param] = value;
        notifyListeners();
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export hierarchy to JSON
  Map<String, dynamic> toJson() {
    return {
      'buses': _buses.map((k, v) => MapEntry(k.toString(), {
        'busId': v.busId,
        'name': v.name,
        'parentBusId': v.parentBusId,
        'childBusIds': v.childBusIds,
        'volume': v.volume,
        'pan': v.pan,
        'mute': v.mute,
        'solo': v.solo,
      })),
      'nextBusId': _nextBusId,
    };
  }

  /// Import hierarchy from JSON
  void fromJson(Map<String, dynamic> json) {
    _buses.clear();

    final busesJson = json['buses'] as Map<String, dynamic>?;
    if (busesJson != null) {
      for (final entry in busesJson.entries) {
        final busData = entry.value as Map<String, dynamic>;
        final bus = AudioBus(
          busId: busData['busId'] as int,
          name: busData['name'] as String,
          parentBusId: busData['parentBusId'] as int?,
          childBusIds: (busData['childBusIds'] as List<dynamic>?)?.cast<int>() ?? [],
        );
        bus.volume = (busData['volume'] as num?)?.toDouble() ?? 1.0;
        bus.pan = (busData['pan'] as num?)?.toDouble() ?? 0.0;
        bus.mute = busData['mute'] as bool? ?? false;
        bus.solo = busData['solo'] as bool? ?? false;
        _buses[bus.busId] = bus;
      }
    }

    _nextBusId = json['nextBusId'] as int? ?? 50;

    // Recreate default if empty
    if (_buses.isEmpty) {
      _createDefaultHierarchy();
    }

    notifyListeners();
  }
}
