// Advanced Middleware Models
//
// Professional game audio middleware features:
// - Voice Management System (polyphony, stealing, priorities)
// - Bus Hierarchy with Effects Chain
// - Spatial Audio for Reels (3D positioning)
// - Memory Budget Manager (streaming, resident)
// - Cascade Audio System (slot-specific)
// - HDR Audio (mobile optimization)
// - Streaming Configuration

import 'dart:math' as math;

// =============================================================================
// GROUP 1: VOICE MANAGEMENT SYSTEM
// =============================================================================

/// Voice stealing mode when polyphony limit is reached
enum VoiceStealingMode {
  /// Steal the oldest voice
  oldest,
  /// Steal the quietest voice
  quietest,
  /// Steal the lowest priority voice
  lowestPriority,
  /// Steal the furthest voice (spatial)
  furthest,
  /// Don't steal, reject new voice
  none,
}

/// Voice state
enum VoiceState {
  idle,
  playing,
  paused,
  fadingIn,
  fadingOut,
  stopping,
}

/// Active voice instance
class ActiveVoice {
  final int voiceId;
  final int soundId;
  final int busId;
  final int priority; // 0-100, higher = more important
  final DateTime startTime;
  VoiceState state;
  double volume;
  double pitch;
  double pan;
  double? spatialDistance; // For 3D audio

  ActiveVoice({
    required this.voiceId,
    required this.soundId,
    required this.busId,
    this.priority = 50,
    required this.startTime,
    this.state = VoiceState.playing,
    this.volume = 1.0,
    this.pitch = 1.0,
    this.pan = 0.0,
    this.spatialDistance,
  });

  /// Voice age in milliseconds
  int get ageMs => DateTime.now().difference(startTime).inMilliseconds;

  /// Effective volume considering distance attenuation
  double get effectiveVolume {
    if (spatialDistance == null) return volume;
    // Simple distance attenuation
    final attenuation = 1.0 / (1.0 + spatialDistance! * 0.1);
    return volume * attenuation;
  }
}

/// Voice pool configuration
class VoicePoolConfig {
  /// Maximum simultaneous voices
  final int maxVoices;

  /// Stealing mode when limit reached
  final VoiceStealingMode stealingMode;

  /// Minimum priority required to steal
  final int minPriorityToSteal;

  /// Fade out time when stealing (ms)
  final int stealFadeOutMs;

  /// Enable virtual voices (track inaudible voices)
  final bool enableVirtualVoices;

  /// Virtual voice threshold (volume below which voice becomes virtual)
  final double virtualThreshold;

  const VoicePoolConfig({
    this.maxVoices = 48,
    this.stealingMode = VoiceStealingMode.lowestPriority,
    this.minPriorityToSteal = 10,
    this.stealFadeOutMs = 50,
    this.enableVirtualVoices = true,
    this.virtualThreshold = 0.01,
  });

  VoicePoolConfig copyWith({
    int? maxVoices,
    VoiceStealingMode? stealingMode,
    int? minPriorityToSteal,
    int? stealFadeOutMs,
    bool? enableVirtualVoices,
    double? virtualThreshold,
  }) {
    return VoicePoolConfig(
      maxVoices: maxVoices ?? this.maxVoices,
      stealingMode: stealingMode ?? this.stealingMode,
      minPriorityToSteal: minPriorityToSteal ?? this.minPriorityToSteal,
      stealFadeOutMs: stealFadeOutMs ?? this.stealFadeOutMs,
      enableVirtualVoices: enableVirtualVoices ?? this.enableVirtualVoices,
      virtualThreshold: virtualThreshold ?? this.virtualThreshold,
    );
  }
}

/// Voice pool manager
class VoicePool {
  final VoicePoolConfig config;
  final Map<int, ActiveVoice> _activeVoices = {};
  final List<ActiveVoice> _virtualVoices = [];
  int _nextVoiceId = 1;

  VoicePool({this.config = const VoicePoolConfig()});

  /// Number of active voices
  int get activeCount => _activeVoices.length;

  /// Number of virtual voices
  int get virtualCount => _virtualVoices.length;

  /// Available voice slots
  int get availableSlots => config.maxVoices - activeCount;

  /// Get all active voice IDs
  Iterable<int> get activeVoiceIds => _activeVoices.keys;

  /// Get first active voice ID or null
  int? get firstActiveVoiceId =>
      _activeVoices.isEmpty ? null : _activeVoices.keys.first;

  /// Request a new voice, returns voice ID or null if rejected
  int? requestVoice({
    required int soundId,
    required int busId,
    int priority = 50,
    double volume = 1.0,
    double pitch = 1.0,
    double pan = 0.0,
    double? spatialDistance,
  }) {
    // Check if we have available slots
    if (activeCount < config.maxVoices) {
      return _createVoice(
        soundId: soundId,
        busId: busId,
        priority: priority,
        volume: volume,
        pitch: pitch,
        pan: pan,
        spatialDistance: spatialDistance,
      );
    }

    // Need to steal a voice
    if (config.stealingMode == VoiceStealingMode.none) {
      return null; // Reject
    }

    final victimId = _findVoiceToSteal(priority);
    if (victimId == null) {
      return null; // No suitable victim
    }

    // Steal the voice
    _stealVoice(victimId);

    return _createVoice(
      soundId: soundId,
      busId: busId,
      priority: priority,
      volume: volume,
      pitch: pitch,
      pan: pan,
      spatialDistance: spatialDistance,
    );
  }

  int _createVoice({
    required int soundId,
    required int busId,
    required int priority,
    required double volume,
    required double pitch,
    required double pan,
    double? spatialDistance,
  }) {
    final voiceId = _nextVoiceId++;
    _activeVoices[voiceId] = ActiveVoice(
      voiceId: voiceId,
      soundId: soundId,
      busId: busId,
      priority: priority,
      startTime: DateTime.now(),
      volume: volume,
      pitch: pitch,
      pan: pan,
      spatialDistance: spatialDistance,
    );
    return voiceId;
  }

  int? _findVoiceToSteal(int newPriority) {
    if (_activeVoices.isEmpty) return null;

    final candidates = _activeVoices.values
        .where((v) => v.priority < newPriority ||
                      v.priority <= config.minPriorityToSteal)
        .toList();

    if (candidates.isEmpty) return null;

    switch (config.stealingMode) {
      case VoiceStealingMode.oldest:
        candidates.sort((a, b) => b.ageMs.compareTo(a.ageMs));
        return candidates.first.voiceId;

      case VoiceStealingMode.quietest:
        candidates.sort((a, b) =>
            a.effectiveVolume.compareTo(b.effectiveVolume));
        return candidates.first.voiceId;

      case VoiceStealingMode.lowestPriority:
        candidates.sort((a, b) => a.priority.compareTo(b.priority));
        return candidates.first.voiceId;

      case VoiceStealingMode.furthest:
        candidates.sort((a, b) {
          final distA = a.spatialDistance ?? 0.0;
          final distB = b.spatialDistance ?? 0.0;
          return distB.compareTo(distA);
        });
        return candidates.first.voiceId;

      case VoiceStealingMode.none:
        return null;
    }
  }

  void _stealVoice(int voiceId) {
    final voice = _activeVoices.remove(voiceId);
    if (voice != null && config.enableVirtualVoices) {
      voice.state = VoiceState.stopping;
      _virtualVoices.add(voice);
    }
  }

  /// Release a voice
  void releaseVoice(int voiceId) {
    _activeVoices.remove(voiceId);
  }

  /// Get voice by ID
  ActiveVoice? getVoice(int voiceId) => _activeVoices[voiceId];

  /// Update voice parameters
  void updateVoice(int voiceId, {
    double? volume,
    double? pitch,
    double? pan,
    double? spatialDistance,
  }) {
    final voice = _activeVoices[voiceId];
    if (voice == null) return;

    if (volume != null) voice.volume = volume;
    if (pitch != null) voice.pitch = pitch;
    if (pan != null) voice.pan = pan;
    if (spatialDistance != null) voice.spatialDistance = spatialDistance;

    // Check for virtualization
    if (config.enableVirtualVoices &&
        voice.effectiveVolume < config.virtualThreshold) {
      _virtualVoices.add(_activeVoices.remove(voiceId)!);
    }
  }

  /// Stop all voices on a bus
  void stopBus(int busId) {
    final toRemove = _activeVoices.entries
        .where((e) => e.value.busId == busId)
        .map((e) => e.key)
        .toList();
    for (final id in toRemove) {
      _activeVoices.remove(id);
    }
  }

  /// Stop all voices
  void stopAll() {
    _activeVoices.clear();
    _virtualVoices.clear();
  }

  /// Get statistics
  VoicePoolStats getStats() {
    return VoicePoolStats(
      activeVoices: activeCount,
      virtualVoices: virtualCount,
      maxVoices: config.maxVoices,
      peakVoices: activeCount, // Would need tracking
      stealCount: 0, // Would need tracking
    );
  }
}

/// Voice pool statistics
class VoicePoolStats {
  final int activeVoices;
  final int virtualVoices;
  final int maxVoices;
  final int peakVoices;
  final int stealCount;

  const VoicePoolStats({
    required this.activeVoices,
    required this.virtualVoices,
    required this.maxVoices,
    required this.peakVoices,
    required this.stealCount,
  });

  double get utilizationPercent => (activeVoices / maxVoices) * 100;
}

// =============================================================================
// GROUP 2: BUS HIERARCHY & EFFECTS CHAIN
// =============================================================================

/// Effect type
enum EffectType {
  /// Reverb (plate, hall, room)
  reverb,
  /// Delay (sync, ping-pong)
  delay,
  /// Compressor (dynamics)
  compressor,
  /// Limiter (true peak)
  limiter,
  /// EQ (parametric)
  eq,
  /// Low-pass filter
  lpf,
  /// High-pass filter
  hpf,
  /// Chorus
  chorus,
  /// Distortion/Saturation
  distortion,
  /// Stereo widener
  widener,
}

/// Reverb preset
enum ReverbPreset {
  plate,
  hall,
  room,
  chamber,
  cathedral,
  custom,
}

/// Effect slot in a chain
class EffectSlot {
  final int slotIndex;
  final EffectType type;
  final Map<String, double> params;
  bool bypass;
  double wetDry; // 0.0 = dry, 1.0 = wet

  EffectSlot({
    required this.slotIndex,
    required this.type,
    Map<String, double>? params,
    this.bypass = false,
    this.wetDry = 0.5,
  }) : params = params ?? _getDefaultParams(type);

  static Map<String, double> _getDefaultParams(EffectType type) {
    switch (type) {
      case EffectType.reverb:
        return {
          'roomSize': 0.5,
          'damping': 0.5,
          'width': 1.0,
          'predelay': 20.0, // ms
          'decay': 2.0, // seconds
        };
      case EffectType.delay:
        return {
          'time': 250.0, // ms
          'feedback': 0.3,
          'pingPong': 0.0, // 0 or 1
          'syncToBpm': 0.0,
        };
      case EffectType.compressor:
        return {
          'threshold': -12.0, // dB
          'ratio': 4.0,
          'attack': 10.0, // ms
          'release': 100.0, // ms
          'makeupGain': 0.0, // dB
          'knee': 6.0, // dB
        };
      case EffectType.limiter:
        return {
          'ceiling': -0.3, // dB
          'release': 50.0, // ms
          'truePeak': 1.0, // enabled
        };
      case EffectType.eq:
        return {
          'lowGain': 0.0, // dB
          'lowFreq': 100.0, // Hz
          'midGain': 0.0,
          'midFreq': 1000.0,
          'midQ': 1.0,
          'highGain': 0.0,
          'highFreq': 8000.0,
        };
      case EffectType.lpf:
        return {
          'cutoff': 20000.0, // Hz
          'resonance': 0.707,
        };
      case EffectType.hpf:
        return {
          'cutoff': 20.0, // Hz
          'resonance': 0.707,
        };
      case EffectType.chorus:
        return {
          'rate': 1.0, // Hz
          'depth': 0.5,
          'voices': 2.0,
        };
      case EffectType.distortion:
        return {
          'drive': 0.5,
          'tone': 0.5,
          'type': 0.0, // 0=soft, 1=hard, 2=tube
        };
      case EffectType.widener:
        return {
          'width': 1.0, // 0=mono, 1=normal, 2=wide
          'midSide': 0.0, // 0=stereo, 1=mid/side
        };
    }
  }

  EffectSlot copyWith({
    int? slotIndex,
    EffectType? type,
    Map<String, double>? params,
    bool? bypass,
    double? wetDry,
  }) {
    return EffectSlot(
      slotIndex: slotIndex ?? this.slotIndex,
      type: type ?? this.type,
      params: params ?? Map.from(this.params),
      bypass: bypass ?? this.bypass,
      wetDry: wetDry ?? this.wetDry,
    );
  }
}

/// Bus with hierarchy and effects
class AudioBus {
  final int busId;
  final String name;
  final int? parentBusId; // null = master
  final List<int> childBusIds;

  double volume; // 0.0 to 1.0
  double pan; // -1.0 to 1.0
  bool mute;
  bool solo;

  final List<EffectSlot> preInserts; // Before fader
  final List<EffectSlot> postInserts; // After fader

  // Metering
  double peakL;
  double peakR;
  double rmsL;
  double rmsR;
  double lufs;

  AudioBus({
    required this.busId,
    required this.name,
    this.parentBusId,
    List<int>? childBusIds,
    this.volume = 1.0,
    this.pan = 0.0,
    this.mute = false,
    this.solo = false,
    List<EffectSlot>? preInserts,
    List<EffectSlot>? postInserts,
    this.peakL = 0.0,
    this.peakR = 0.0,
    this.rmsL = 0.0,
    this.rmsR = 0.0,
    this.lufs = -70.0,
  }) : childBusIds = childBusIds ?? [],
       preInserts = preInserts ?? [],
       postInserts = postInserts ?? [];

  /// Add effect to pre-insert chain
  void addPreInsert(EffectSlot effect) {
    preInserts.add(effect.copyWith(slotIndex: preInserts.length));
  }

  /// Add effect to post-insert chain
  void addPostInsert(EffectSlot effect) {
    postInserts.add(effect.copyWith(slotIndex: postInserts.length));
  }

  /// Remove effect from pre-insert chain
  void removePreInsert(int slotIndex) {
    preInserts.removeWhere((e) => e.slotIndex == slotIndex);
    // Re-index
    for (int i = 0; i < preInserts.length; i++) {
      preInserts[i] = preInserts[i].copyWith(slotIndex: i);
    }
  }

  /// Remove effect from post-insert chain
  void removePostInsert(int slotIndex) {
    postInserts.removeWhere((e) => e.slotIndex == slotIndex);
    for (int i = 0; i < postInserts.length; i++) {
      postInserts[i] = postInserts[i].copyWith(slotIndex: i);
    }
  }
}

// =============================================================================
// AUX SEND ROUTING SYSTEM
// =============================================================================

/// Send position (pre or post fader)
enum SendPosition {
  preFader,  // Before fader - not affected by track volume
  postFader, // After fader - follows track volume
}

/// Aux send from a source to an aux bus
class AuxSend {
  final int sendId;
  final int sourceBusId;   // Source track/bus
  final int auxBusId;       // Target aux bus (reverb, delay, etc.)
  final String name;

  double sendLevel;         // 0.0 to 1.0
  SendPosition position;
  bool enabled;

  AuxSend({
    required this.sendId,
    required this.sourceBusId,
    required this.auxBusId,
    required this.name,
    this.sendLevel = 0.0,
    this.position = SendPosition.postFader,
    this.enabled = true,
  });

  /// Create a copy with modified values
  AuxSend copyWith({
    int? sendId,
    int? sourceBusId,
    int? auxBusId,
    String? name,
    double? sendLevel,
    SendPosition? position,
    bool? enabled,
  }) {
    return AuxSend(
      sendId: sendId ?? this.sendId,
      sourceBusId: sourceBusId ?? this.sourceBusId,
      auxBusId: auxBusId ?? this.auxBusId,
      name: name ?? this.name,
      sendLevel: sendLevel ?? this.sendLevel,
      position: position ?? this.position,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// Aux bus (effect return)
class AuxBus {
  final int auxBusId;
  final String name;
  final EffectType effectType;

  double returnLevel;   // 0.0 to 1.0
  bool mute;
  bool solo;

  // Effect parameters
  final Map<String, double> effectParams;

  // Metering
  double peakL;
  double peakR;

  AuxBus({
    required this.auxBusId,
    required this.name,
    required this.effectType,
    this.returnLevel = 1.0,
    this.mute = false,
    this.solo = false,
    Map<String, double>? effectParams,
    this.peakL = 0.0,
    this.peakR = 0.0,
  }) : effectParams = effectParams ?? _getDefaultAuxParams(effectType);

  static Map<String, double> _getDefaultAuxParams(EffectType type) {
    switch (type) {
      case EffectType.reverb:
        return {
          'roomSize': 0.6,
          'damping': 0.5,
          'width': 1.0,
          'predelay': 25.0,
          'decay': 2.5,
        };
      case EffectType.delay:
        return {
          'time': 375.0, // ms (1/8 note at 80bpm)
          'feedback': 0.35,
          'pingPong': 1.0,
          'syncToBpm': 1.0,
          'filterHigh': 8000.0,
          'filterLow': 200.0,
        };
      default:
        return {};
    }
  }
}

/// Aux send routing manager
class AuxSendManager {
  final Map<int, AuxBus> _auxBuses = {};
  final Map<int, AuxSend> _sends = {};
  int _nextSendId = 0;
  int _nextAuxBusId = 100; // Start at 100 to avoid collision with main buses

  AuxSendManager() {
    _createDefaultAuxBuses();
  }

  void _createDefaultAuxBuses() {
    // Default Aux buses
    _auxBuses[100] = AuxBus(
      auxBusId: 100,
      name: 'Reverb A',
      effectType: EffectType.reverb,
      effectParams: {
        'roomSize': 0.5,
        'damping': 0.4,
        'width': 1.0,
        'predelay': 20.0,
        'decay': 1.8,
      },
    );

    _auxBuses[101] = AuxBus(
      auxBusId: 101,
      name: 'Reverb B',
      effectType: EffectType.reverb,
      effectParams: {
        'roomSize': 0.8,
        'damping': 0.3,
        'width': 1.0,
        'predelay': 40.0,
        'decay': 4.0,
      },
    );

    _auxBuses[102] = AuxBus(
      auxBusId: 102,
      name: 'Delay',
      effectType: EffectType.delay,
      effectParams: {
        'time': 250.0,
        'feedback': 0.3,
        'pingPong': 1.0,
        'syncToBpm': 0.0,
        'filterHigh': 6000.0,
        'filterLow': 300.0,
      },
    );

    _auxBuses[103] = AuxBus(
      auxBusId: 103,
      name: 'Slapback',
      effectType: EffectType.delay,
      effectParams: {
        'time': 80.0,
        'feedback': 0.1,
        'pingPong': 0.0,
        'syncToBpm': 0.0,
        'filterHigh': 4000.0,
        'filterLow': 500.0,
      },
    );
  }

  // Getters
  List<AuxBus> get allAuxBuses => _auxBuses.values.toList();
  List<AuxSend> get allSends => _sends.values.toList();
  AuxBus? getAuxBus(int auxBusId) => _auxBuses[auxBusId];

  /// Get all sends from a specific source bus
  List<AuxSend> getSendsFromBus(int sourceBusId) {
    return _sends.values.where((s) => s.sourceBusId == sourceBusId).toList();
  }

  /// Get all sends to a specific aux bus
  List<AuxSend> getSendsToAux(int auxBusId) {
    return _sends.values.where((s) => s.auxBusId == auxBusId).toList();
  }

  /// Create a new aux send
  AuxSend createSend({
    required int sourceBusId,
    required int auxBusId,
    double sendLevel = 0.0,
    SendPosition position = SendPosition.postFader,
  }) {
    final auxBus = _auxBuses[auxBusId];
    if (auxBus == null) throw ArgumentError('Aux bus $auxBusId not found');

    final send = AuxSend(
      sendId: _nextSendId++,
      sourceBusId: sourceBusId,
      auxBusId: auxBusId,
      name: auxBus.name,
      sendLevel: sendLevel,
      position: position,
    );

    _sends[send.sendId] = send;
    return send;
  }

  /// Update send level
  void setSendLevel(int sendId, double level) {
    final send = _sends[sendId];
    if (send != null) {
      _sends[sendId] = send.copyWith(sendLevel: level.clamp(0.0, 1.0));
    }
  }

  /// Toggle send enabled
  void toggleSendEnabled(int sendId) {
    final send = _sends[sendId];
    if (send != null) {
      _sends[sendId] = send.copyWith(enabled: !send.enabled);
    }
  }

  /// Set send position (pre/post fader)
  void setSendPosition(int sendId, SendPosition position) {
    final send = _sends[sendId];
    if (send != null) {
      _sends[sendId] = send.copyWith(position: position);
    }
  }

  /// Remove a send
  void removeSend(int sendId) {
    _sends.remove(sendId);
  }

  /// Add a new aux bus
  AuxBus addAuxBus({
    required String name,
    required EffectType effectType,
  }) {
    final auxBus = AuxBus(
      auxBusId: _nextAuxBusId++,
      name: name,
      effectType: effectType,
    );
    _auxBuses[auxBus.auxBusId] = auxBus;
    return auxBus;
  }

  /// Update aux bus return level
  void setAuxReturnLevel(int auxBusId, double level) {
    final auxBus = _auxBuses[auxBusId];
    if (auxBus != null) {
      auxBus.returnLevel = level.clamp(0.0, 1.0);
    }
  }

  /// Toggle aux bus mute
  void toggleAuxMute(int auxBusId) {
    final auxBus = _auxBuses[auxBusId];
    if (auxBus != null) {
      auxBus.mute = !auxBus.mute;
    }
  }

  /// Toggle aux bus solo
  void toggleAuxSolo(int auxBusId) {
    final auxBus = _auxBuses[auxBusId];
    if (auxBus != null) {
      auxBus.solo = !auxBus.solo;
    }
  }

  /// Update aux effect parameter
  void setAuxEffectParam(int auxBusId, String param, double value) {
    final auxBus = _auxBuses[auxBusId];
    if (auxBus != null && auxBus.effectParams.containsKey(param)) {
      auxBus.effectParams[param] = value;
    }
  }

  /// Calculate total send contribution to an aux bus
  double calculateAuxInput(int auxBusId, Map<int, double> busLevels) {
    double total = 0.0;
    for (final send in getSendsToAux(auxBusId)) {
      if (!send.enabled) continue;

      final sourceLevel = busLevels[send.sourceBusId] ?? 0.0;
      if (send.position == SendPosition.postFader) {
        total += sourceLevel * send.sendLevel;
      } else {
        total += send.sendLevel; // Pre-fader ignores source volume
      }
    }
    return total.clamp(0.0, 1.0);
  }
}

/// Bus hierarchy manager
class BusHierarchy {
  final Map<int, AudioBus> _buses = {};

  BusHierarchy() {
    // Create default hierarchy
    _createDefaultHierarchy();
  }

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

  AudioBus? getBus(int busId) => _buses[busId];

  List<AudioBus> get allBuses => _buses.values.toList();

  AudioBus get master => _buses[0]!;

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

  /// Add a new bus
  void addBus(AudioBus bus) {
    _buses[bus.busId] = bus;
    if (bus.parentBusId != null) {
      _buses[bus.parentBusId]?.childBusIds.add(bus.busId);
    }
  }

  /// Remove a bus and reparent children to parent
  void removeBus(int busId) {
    final bus = _buses[busId];
    if (bus == null || busId == 0) return; // Can't remove master

    // Reparent children
    for (final childId in bus.childBusIds) {
      _buses[childId]?.parentBusId == bus.parentBusId;
      _buses[bus.parentBusId]?.childBusIds.add(childId);
    }

    // Remove from parent
    _buses[bus.parentBusId]?.childBusIds.remove(busId);

    _buses.remove(busId);
  }
}

// =============================================================================
// GROUP 3: SPATIAL AUDIO FOR REELS
// =============================================================================

/// Spatial audio mode
enum SpatialMode {
  /// No spatial processing
  none,
  /// 2D panning only
  stereo2d,
  /// 3D positioning
  spatial3d,
  /// Ambisonics (future)
  ambisonics,
}

/// Attenuation model for distance
enum AttenuationModel {
  /// No attenuation
  none,
  /// Linear falloff
  linear,
  /// Inverse distance
  inverse,
  /// Logarithmic
  logarithmic,
  /// Custom curve
  custom,
}

/// 3D position
class AudioPosition {
  final double x; // Left-Right (-1 to 1)
  final double y; // Up-Down (-1 to 1)
  final double z; // Front-Back (0 to 1, 0 = front)

  const AudioPosition({
    this.x = 0.0,
    this.y = 0.0,
    this.z = 0.0,
  });

  /// Distance from listener (assumed at origin)
  double get distance => math.sqrt(x * x + y * y + z * z);

  /// 2D pan value
  double get pan => x.clamp(-1.0, 1.0);

  AudioPosition copyWith({double? x, double? y, double? z}) {
    return AudioPosition(
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
    );
  }
}

/// Spatial audio configuration for reels
class ReelSpatialConfig {
  /// Number of reels
  final int reelCount;

  /// Pan spread across reels (-1 to 1)
  final double panSpread;

  /// Depth spread for rows (0 to 1)
  final double depthSpread;

  /// Attenuation model
  final AttenuationModel attenuationModel;

  /// Reference distance for attenuation
  final double referenceDistance;

  /// Max distance for attenuation
  final double maxDistance;

  /// Rolloff factor
  final double rolloff;

  const ReelSpatialConfig({
    this.reelCount = 5,
    this.panSpread = 0.8, // 80% of stereo field
    this.depthSpread = 0.3,
    this.attenuationModel = AttenuationModel.logarithmic,
    this.referenceDistance = 1.0,
    this.maxDistance = 10.0,
    this.rolloff = 1.0,
  });

  /// Get position for a reel
  AudioPosition getReelPosition(int reelIndex, {int rowIndex = 1}) {
    // Spread reels across stereo field
    final normalizedReel = reelCount > 1
        ? (reelIndex / (reelCount - 1)) * 2 - 1 // -1 to 1
        : 0.0;

    final x = normalizedReel * panSpread;
    final y = 0.0; // Reels are at ear level
    final z = rowIndex * depthSpread * 0.1; // Slight depth per row

    return AudioPosition(x: x, y: y, z: z);
  }

  /// Calculate attenuation for distance
  double calculateAttenuation(double distance) {
    if (distance <= referenceDistance) return 1.0;
    if (distance >= maxDistance) return 0.0;

    switch (attenuationModel) {
      case AttenuationModel.none:
        return 1.0;

      case AttenuationModel.linear:
        return 1.0 - (distance - referenceDistance) /
                     (maxDistance - referenceDistance);

      case AttenuationModel.inverse:
        return referenceDistance /
               (referenceDistance + rolloff * (distance - referenceDistance));

      case AttenuationModel.logarithmic:
        return referenceDistance /
               (referenceDistance + rolloff *
                math.log(distance / referenceDistance + 1));

      case AttenuationModel.custom:
        return 1.0; // Would use curve
    }
  }

  ReelSpatialConfig copyWith({
    int? reelCount,
    double? panSpread,
    double? depthSpread,
    AttenuationModel? attenuationModel,
    double? referenceDistance,
    double? maxDistance,
    double? rolloff,
  }) {
    return ReelSpatialConfig(
      reelCount: reelCount ?? this.reelCount,
      panSpread: panSpread ?? this.panSpread,
      depthSpread: depthSpread ?? this.depthSpread,
      attenuationModel: attenuationModel ?? this.attenuationModel,
      referenceDistance: referenceDistance ?? this.referenceDistance,
      maxDistance: maxDistance ?? this.maxDistance,
      rolloff: rolloff ?? this.rolloff,
    );
  }
}

/// Spatial emitter (sound source in 3D space)
class SpatialEmitter {
  final int emitterId;
  final String name;
  AudioPosition position;
  double spreadAngle; // For non-point sources (degrees)
  bool followListener; // For UI sounds

  SpatialEmitter({
    required this.emitterId,
    required this.name,
    this.position = const AudioPosition(),
    this.spreadAngle = 0.0,
    this.followListener = false,
  });
}

// =============================================================================
// GROUP 4: MEMORY BUDGET MANAGER
// =============================================================================

/// Load priority for soundbanks
enum LoadPriority {
  /// Load immediately, keep resident
  critical,
  /// Load on demand, keep resident
  high,
  /// Load on demand, can unload
  normal,
  /// Stream from disk
  streaming,
}

/// Sound bank definition
class SoundBank {
  final String bankId;
  final String name;
  final int estimatedSizeBytes;
  final LoadPriority priority;
  final List<String> soundIds;
  bool isLoaded;
  int actualSizeBytes;
  DateTime? lastUsed;

  SoundBank({
    required this.bankId,
    required this.name,
    required this.estimatedSizeBytes,
    this.priority = LoadPriority.normal,
    this.soundIds = const [],
    this.isLoaded = false,
    this.actualSizeBytes = 0,
    this.lastUsed,
  });

  /// Size in MB
  double get sizeMb => actualSizeBytes / (1024 * 1024);

  /// Estimated size in MB
  double get estimatedSizeMb => estimatedSizeBytes / (1024 * 1024);
}

/// Memory budget configuration
class MemoryBudgetConfig {
  /// Maximum resident memory (bytes)
  final int maxResidentBytes;

  /// Maximum streaming buffer (bytes)
  final int maxStreamingBytes;

  /// Warning threshold (percentage)
  final double warningThreshold;

  /// Critical threshold (percentage) - start unloading
  final double criticalThreshold;

  /// Minimum time before unloading (ms)
  final int minResidentTimeMs;

  const MemoryBudgetConfig({
    this.maxResidentBytes = 64 * 1024 * 1024, // 64MB
    this.maxStreamingBytes = 32 * 1024 * 1024, // 32MB
    this.warningThreshold = 0.75,
    this.criticalThreshold = 0.90,
    this.minResidentTimeMs = 5000,
  });

  int get maxResidentMb => maxResidentBytes ~/ (1024 * 1024);
  int get maxStreamingMb => maxStreamingBytes ~/ (1024 * 1024);
}

/// Memory budget manager
class MemoryBudgetManager {
  final MemoryBudgetConfig config;
  final Map<String, SoundBank> _banks = {};
  int _currentResidentBytes = 0;
  int _currentStreamingBytes = 0;

  MemoryBudgetManager({this.config = const MemoryBudgetConfig()});

  /// Current resident memory usage
  int get residentBytes => _currentResidentBytes;
  double get residentMb => _currentResidentBytes / (1024 * 1024);
  double get residentPercent => _currentResidentBytes / config.maxResidentBytes;

  /// Current streaming buffer usage
  int get streamingBytes => _currentStreamingBytes;
  double get streamingMb => _currentStreamingBytes / (1024 * 1024);
  double get streamingPercent => _currentStreamingBytes / config.maxStreamingBytes;

  /// Memory state
  MemoryState get state {
    if (residentPercent >= config.criticalThreshold) return MemoryState.critical;
    if (residentPercent >= config.warningThreshold) return MemoryState.warning;
    return MemoryState.normal;
  }

  /// Register a soundbank
  void registerBank(SoundBank bank) {
    _banks[bank.bankId] = bank;
  }

  /// Load a soundbank
  bool loadBank(String bankId) {
    final bank = _banks[bankId];
    if (bank == null || bank.isLoaded) return false;

    // Check if we have space
    final neededBytes = bank.estimatedSizeBytes;
    if (_currentResidentBytes + neededBytes > config.maxResidentBytes) {
      // Try to free space
      final freed = _freeSpace(neededBytes);
      if (!freed) return false;
    }

    // Load the bank
    bank.isLoaded = true;
    bank.actualSizeBytes = neededBytes; // Would be actual size after load
    bank.lastUsed = DateTime.now();
    _currentResidentBytes += bank.actualSizeBytes;

    return true;
  }

  /// Unload a soundbank
  bool unloadBank(String bankId) {
    final bank = _banks[bankId];
    if (bank == null || !bank.isLoaded) return false;

    // Can't unload critical banks
    if (bank.priority == LoadPriority.critical) return false;

    bank.isLoaded = false;
    _currentResidentBytes -= bank.actualSizeBytes;
    bank.actualSizeBytes = 0;

    return true;
  }

  /// Try to free space by unloading least recently used banks
  bool _freeSpace(int neededBytes) {
    final now = DateTime.now();

    // Get unloadable banks sorted by last used
    final candidates = _banks.values
        .where((b) => b.isLoaded &&
                      b.priority != LoadPriority.critical &&
                      (b.lastUsed == null ||
                       now.difference(b.lastUsed!).inMilliseconds >=
                       config.minResidentTimeMs))
        .toList()
      ..sort((a, b) => (a.lastUsed ?? DateTime(1970))
          .compareTo(b.lastUsed ?? DateTime(1970)));

    int freed = 0;
    for (final bank in candidates) {
      if (freed >= neededBytes) break;

      if (unloadBank(bank.bankId)) {
        freed += bank.estimatedSizeBytes;
      }
    }

    return freed >= neededBytes;
  }

  /// Mark bank as used
  void touchBank(String bankId) {
    _banks[bankId]?.lastUsed = DateTime.now();
  }

  /// Get loaded banks
  List<SoundBank> get loadedBanks =>
      _banks.values.where((b) => b.isLoaded).toList();

  /// Get all registered banks
  List<SoundBank> get allBanks => _banks.values.toList();

  /// Check if bank is loaded
  bool isBankLoaded(String bankId) => _banks[bankId]?.isLoaded ?? false;

  /// Get memory statistics
  MemoryStats getStats() {
    return MemoryStats(
      residentBytes: _currentResidentBytes,
      residentMaxBytes: config.maxResidentBytes,
      streamingBytes: _currentStreamingBytes,
      streamingMaxBytes: config.maxStreamingBytes,
      loadedBankCount: loadedBanks.length,
      totalBankCount: _banks.length,
      state: state,
    );
  }
}

enum MemoryState { normal, warning, critical }

class MemoryStats {
  final int residentBytes;
  final int residentMaxBytes;
  final int streamingBytes;
  final int streamingMaxBytes;
  final int loadedBankCount;
  final int totalBankCount;
  final MemoryState state;

  const MemoryStats({
    required this.residentBytes,
    required this.residentMaxBytes,
    required this.streamingBytes,
    required this.streamingMaxBytes,
    required this.loadedBankCount,
    required this.totalBankCount,
    required this.state,
  });

  double get residentPercent => residentBytes / residentMaxBytes;
  double get streamingPercent => streamingBytes / streamingMaxBytes;
  double get residentMb => residentBytes / (1024 * 1024);
  double get streamingMb => streamingBytes / (1024 * 1024);
}

// =============================================================================
// GROUP 5: CASCADE AUDIO SYSTEM (SLOT-SPECIFIC)
// =============================================================================

/// Cascade audio escalation mode
enum CascadeEscalationMode {
  /// Pitch increases per step
  pitch,
  /// Volume increases per step
  volume,
  /// Add layers per step
  layering,
  /// Combination
  combined,
}

/// Cascade layer definition
class CascadeLayer {
  final int layerIndex;
  final String soundId;
  final int triggerAtStep; // Activate at this cascade step
  final double baseVolume;
  final double basePitch;

  const CascadeLayer({
    required this.layerIndex,
    required this.soundId,
    required this.triggerAtStep,
    this.baseVolume = 1.0,
    this.basePitch = 1.0,
  });
}

/// Cascade audio configuration
class CascadeAudioConfig {
  /// Escalation mode
  final CascadeEscalationMode mode;

  /// Pitch increment per cascade step (semitones)
  final double pitchIncrementSemitones;

  /// Maximum pitch shift (semitones)
  final double maxPitchSemitones;

  /// Volume increment per step (linear)
  final double volumeIncrement;

  /// Maximum volume
  final double maxVolume;

  /// Sound layers that activate at different cascade depths
  final List<CascadeLayer> layers;

  /// RTPC curve for cascade depth → tension parameter
  final List<CascadeTensionPoint> tensionCurve;

  /// Enable stereo widening as cascade progresses
  final bool progressiveWidth;

  /// Maximum stereo width (0-2)
  final double maxWidth;

  /// Enable reverb increase as cascade progresses
  final bool progressiveReverb;

  /// Maximum reverb wet amount
  final double maxReverbWet;

  const CascadeAudioConfig({
    this.mode = CascadeEscalationMode.combined,
    this.pitchIncrementSemitones = 0.5,
    this.maxPitchSemitones = 6.0,
    this.volumeIncrement = 0.05,
    this.maxVolume = 1.2,
    this.layers = const [],
    this.tensionCurve = const [],
    this.progressiveWidth = true,
    this.maxWidth = 1.5,
    this.progressiveReverb = true,
    this.maxReverbWet = 0.4,
  });

  /// Calculate pitch multiplier for cascade step
  double getPitchMultiplier(int cascadeStep) {
    final semitones = (cascadeStep * pitchIncrementSemitones)
        .clamp(0.0, maxPitchSemitones);
    return math.pow(2, semitones / 12).toDouble();
  }

  /// Calculate volume for cascade step
  double getVolume(int cascadeStep) {
    return (1.0 + cascadeStep * volumeIncrement).clamp(0.0, maxVolume);
  }

  /// Get active layers for cascade step
  List<CascadeLayer> getActiveLayers(int cascadeStep) {
    return layers.where((l) => l.triggerAtStep <= cascadeStep).toList();
  }

  /// Calculate tension RTPC value for cascade step
  double getTensionValue(int cascadeStep) {
    if (tensionCurve.isEmpty) {
      return (cascadeStep / 10.0).clamp(0.0, 1.0);
    }

    // Interpolate curve
    for (int i = 0; i < tensionCurve.length - 1; i++) {
      if (cascadeStep >= tensionCurve[i].step &&
          cascadeStep < tensionCurve[i + 1].step) {
        final t = (cascadeStep - tensionCurve[i].step) /
                  (tensionCurve[i + 1].step - tensionCurve[i].step);
        return tensionCurve[i].tension +
               t * (tensionCurve[i + 1].tension - tensionCurve[i].tension);
      }
    }

    return tensionCurve.last.tension;
  }

  /// Calculate stereo width for cascade step
  double getWidth(int cascadeStep) {
    if (!progressiveWidth) return 1.0;
    return (1.0 + cascadeStep * 0.05).clamp(1.0, maxWidth);
  }

  /// Calculate reverb wet for cascade step
  double getReverbWet(int cascadeStep) {
    if (!progressiveReverb) return 0.0;
    return (cascadeStep * 0.03).clamp(0.0, maxReverbWet);
  }
}

/// Tension curve point
class CascadeTensionPoint {
  final int step;
  final double tension; // 0.0 to 1.0

  const CascadeTensionPoint({
    required this.step,
    required this.tension,
  });
}

/// Default cascade config for slots
const defaultCascadeConfig = CascadeAudioConfig(
  mode: CascadeEscalationMode.combined,
  pitchIncrementSemitones: 0.5,
  maxPitchSemitones: 6.0,
  volumeIncrement: 0.03,
  maxVolume: 1.15,
  layers: [
    CascadeLayer(layerIndex: 0, soundId: 'cascade_base', triggerAtStep: 0),
    CascadeLayer(layerIndex: 1, soundId: 'cascade_mid', triggerAtStep: 3),
    CascadeLayer(layerIndex: 2, soundId: 'cascade_high', triggerAtStep: 6),
    CascadeLayer(layerIndex: 3, soundId: 'cascade_intense', triggerAtStep: 10),
  ],
  tensionCurve: [
    CascadeTensionPoint(step: 0, tension: 0.0),
    CascadeTensionPoint(step: 3, tension: 0.3),
    CascadeTensionPoint(step: 6, tension: 0.6),
    CascadeTensionPoint(step: 10, tension: 0.85),
    CascadeTensionPoint(step: 15, tension: 1.0),
  ],
  progressiveWidth: true,
  maxWidth: 1.5,
  progressiveReverb: true,
  maxReverbWet: 0.35,
);

// =============================================================================
// GROUP 6: HDR AUDIO & STREAMING
// =============================================================================

/// HDR audio profile
enum HdrProfile {
  /// Full dynamic range (studio monitors)
  reference,
  /// Compressed for desktop speakers
  desktop,
  /// Heavily compressed for mobile
  mobile,
  /// Night mode (very compressed)
  night,
  /// Custom
  custom,
}

/// HDR audio configuration
class HdrAudioConfig {
  final HdrProfile profile;

  /// Target loudness (LUFS)
  final double targetLoudnessLufs;

  /// Dynamic range (dB)
  final double dynamicRangeDb;

  /// Enable limiter
  final bool enableLimiter;

  /// Limiter ceiling (dB)
  final double limiterCeilingDb;

  /// Enable automatic gain
  final bool enableAutoGain;

  /// Compression ratio
  final double compressionRatio;

  /// Compression threshold (dB)
  final double compressionThresholdDb;

  const HdrAudioConfig({
    this.profile = HdrProfile.desktop,
    this.targetLoudnessLufs = -14.0,
    this.dynamicRangeDb = 18.0,
    this.enableLimiter = true,
    this.limiterCeilingDb = -0.3,
    this.enableAutoGain = true,
    this.compressionRatio = 3.0,
    this.compressionThresholdDb = -18.0,
  });

  /// Get preset config
  factory HdrAudioConfig.fromProfile(HdrProfile profile) {
    switch (profile) {
      case HdrProfile.reference:
        return const HdrAudioConfig(
          profile: HdrProfile.reference,
          targetLoudnessLufs: -23.0,
          dynamicRangeDb: 30.0,
          enableLimiter: true,
          limiterCeilingDb: -0.1,
          enableAutoGain: false,
          compressionRatio: 1.5,
          compressionThresholdDb: -12.0,
        );
      case HdrProfile.desktop:
        return const HdrAudioConfig(
          profile: HdrProfile.desktop,
          targetLoudnessLufs: -14.0,
          dynamicRangeDb: 18.0,
          enableLimiter: true,
          limiterCeilingDb: -0.3,
          enableAutoGain: true,
          compressionRatio: 3.0,
          compressionThresholdDb: -18.0,
        );
      case HdrProfile.mobile:
        return const HdrAudioConfig(
          profile: HdrProfile.mobile,
          targetLoudnessLufs: -16.0,
          dynamicRangeDb: 12.0,
          enableLimiter: true,
          limiterCeilingDb: -0.5,
          enableAutoGain: true,
          compressionRatio: 5.0,
          compressionThresholdDb: -24.0,
        );
      case HdrProfile.night:
        return const HdrAudioConfig(
          profile: HdrProfile.night,
          targetLoudnessLufs: -20.0,
          dynamicRangeDb: 8.0,
          enableLimiter: true,
          limiterCeilingDb: -1.0,
          enableAutoGain: true,
          compressionRatio: 8.0,
          compressionThresholdDb: -30.0,
        );
      case HdrProfile.custom:
        return const HdrAudioConfig();
    }
  }
}

/// Streaming configuration
class StreamingConfig {
  /// Buffer size in milliseconds
  final int bufferSizeMs;

  /// Prefetch buffer in milliseconds
  final int prefetchMs;

  /// Enable seamless looping
  final bool seamlessLoop;

  /// Maximum concurrent streams
  final int maxConcurrentStreams;

  /// Decode buffer size
  final int decodeBufferSizeKb;

  /// Enable disk caching
  final bool enableCache;

  /// Cache size in MB
  final int cacheSizeMb;

  const StreamingConfig({
    this.bufferSizeMs = 200,
    this.prefetchMs = 500,
    this.seamlessLoop = true,
    this.maxConcurrentStreams = 8,
    this.decodeBufferSizeKb = 256,
    this.enableCache = true,
    this.cacheSizeMb = 50,
  });

  StreamingConfig copyWith({
    int? bufferSizeMs,
    int? prefetchMs,
    bool? seamlessLoop,
    int? maxConcurrentStreams,
    int? decodeBufferSizeKb,
    bool? enableCache,
    int? cacheSizeMb,
  }) {
    return StreamingConfig(
      bufferSizeMs: bufferSizeMs ?? this.bufferSizeMs,
      prefetchMs: prefetchMs ?? this.prefetchMs,
      seamlessLoop: seamlessLoop ?? this.seamlessLoop,
      maxConcurrentStreams: maxConcurrentStreams ?? this.maxConcurrentStreams,
      decodeBufferSizeKb: decodeBufferSizeKb ?? this.decodeBufferSizeKb,
      enableCache: enableCache ?? this.enableCache,
      cacheSizeMb: cacheSizeMb ?? this.cacheSizeMb,
    );
  }
}

// =============================================================================
// GROUP 7: EVENT PROFILER
// =============================================================================

/// Profiler event type
enum ProfilerEventType {
  eventPost,
  eventTrigger,
  voiceStart,
  voiceStop,
  voiceSteal,
  bankLoad,
  bankUnload,
  rtpcChange,
  stateChange,
  error,
}

/// Profiler event record
class ProfilerEvent {
  final int eventId;
  final DateTime timestamp;
  final ProfilerEventType type;
  final String description;
  final int? soundId;
  final int? busId;
  final int? voiceId;
  final double? value;
  final int latencyUs; // Microseconds

  ProfilerEvent({
    required this.eventId,
    required this.timestamp,
    required this.type,
    required this.description,
    this.soundId,
    this.busId,
    this.voiceId,
    this.value,
    this.latencyUs = 0,
  });
}

/// Profiler statistics
class ProfilerStats {
  final int totalEvents;
  final int eventsPerSecond;
  final int peakEventsPerSecond;
  final double avgLatencyUs;
  final double maxLatencyUs;
  final int voiceStarts;
  final int voiceStops;
  final int voiceSteals;
  final int errors;

  const ProfilerStats({
    required this.totalEvents,
    required this.eventsPerSecond,
    required this.peakEventsPerSecond,
    required this.avgLatencyUs,
    required this.maxLatencyUs,
    required this.voiceStarts,
    required this.voiceStops,
    required this.voiceSteals,
    required this.errors,
  });

  double get avgLatencyMs => avgLatencyUs / 1000;
  double get maxLatencyMs => maxLatencyUs / 1000;
}

/// Event profiler
class EventProfiler {
  final int maxEvents;
  final List<ProfilerEvent> _events = [];
  int _nextEventId = 1;

  // Per-second tracking
  final List<int> _eventsPerSecond = [];
  int _currentSecondEvents = 0;
  DateTime _currentSecond = DateTime.now();

  // Latency tracking
  double _totalLatencyUs = 0;
  double _maxLatencyUs = 0;

  // Counters
  int _voiceStarts = 0;
  int _voiceStops = 0;
  int _voiceSteals = 0;
  int _errors = 0;

  EventProfiler({this.maxEvents = 10000});

  /// Record an event
  void record({
    required ProfilerEventType type,
    required String description,
    int? soundId,
    int? busId,
    int? voiceId,
    double? value,
    int latencyUs = 0,
  }) {
    final now = DateTime.now();

    // Update per-second tracking
    if (now.second != _currentSecond.second) {
      _eventsPerSecond.add(_currentSecondEvents);
      if (_eventsPerSecond.length > 60) {
        _eventsPerSecond.removeAt(0);
      }
      _currentSecondEvents = 0;
      _currentSecond = now;
    }
    _currentSecondEvents++;

    // Update latency tracking
    _totalLatencyUs += latencyUs;
    if (latencyUs > _maxLatencyUs) _maxLatencyUs = latencyUs.toDouble();

    // Update counters
    switch (type) {
      case ProfilerEventType.voiceStart:
        _voiceStarts++;
        break;
      case ProfilerEventType.voiceStop:
        _voiceStops++;
        break;
      case ProfilerEventType.voiceSteal:
        _voiceSteals++;
        break;
      case ProfilerEventType.error:
        _errors++;
        break;
      default:
        break;
    }

    // Add event
    final event = ProfilerEvent(
      eventId: _nextEventId++,
      timestamp: now,
      type: type,
      description: description,
      soundId: soundId,
      busId: busId,
      voiceId: voiceId,
      value: value,
      latencyUs: latencyUs,
    );

    _events.add(event);

    // Trim old events
    while (_events.length > maxEvents) {
      _events.removeAt(0);
    }
  }

  /// Get recent events
  List<ProfilerEvent> getRecentEvents({int count = 100}) {
    final start = _events.length > count ? _events.length - count : 0;
    return _events.sublist(start);
  }

  /// Get events by type
  List<ProfilerEvent> getEventsByType(ProfilerEventType type) {
    return _events.where((e) => e.type == type).toList();
  }

  /// Get statistics
  ProfilerStats getStats() {
    final totalEvents = _events.length;
    final avgLatency = totalEvents > 0 ? _totalLatencyUs / totalEvents : 0.0;
    final peakEps = _eventsPerSecond.isEmpty
        ? 0
        : _eventsPerSecond.reduce((a, b) => a > b ? a : b);

    return ProfilerStats(
      totalEvents: totalEvents,
      eventsPerSecond: _currentSecondEvents,
      peakEventsPerSecond: peakEps,
      avgLatencyUs: avgLatency,
      maxLatencyUs: _maxLatencyUs,
      voiceStarts: _voiceStarts,
      voiceStops: _voiceStops,
      voiceSteals: _voiceSteals,
      errors: _errors,
    );
  }

  /// Clear all events
  void clear() {
    _events.clear();
    _eventsPerSecond.clear();
    _totalLatencyUs = 0;
    _maxLatencyUs = 0;
    _voiceStarts = 0;
    _voiceStops = 0;
    _voiceSteals = 0;
    _errors = 0;
    _currentSecondEvents = 0;
  }
}

// =============================================================================
// P3.12: DSP PROFILER
// =============================================================================

/// DSP processing stage for profiling
enum DspStage {
  input,
  mixing,
  effects,
  metering,
  output,
  total,
}

extension DspStageExtension on DspStage {
  String get displayName {
    switch (this) {
      case DspStage.input: return 'Input';
      case DspStage.mixing: return 'Mixing';
      case DspStage.effects: return 'Effects';
      case DspStage.metering: return 'Metering';
      case DspStage.output: return 'Output';
      case DspStage.total: return 'Total';
    }
  }

  String get shortName {
    switch (this) {
      case DspStage.input: return 'IN';
      case DspStage.mixing: return 'MIX';
      case DspStage.effects: return 'FX';
      case DspStage.metering: return 'MTR';
      case DspStage.output: return 'OUT';
      case DspStage.total: return 'TOT';
    }
  }
}

/// Single DSP timing sample
class DspTimingSample {
  final DateTime timestamp;
  final Map<DspStage, double> stageTimingsUs;
  final int blockSize;
  final double sampleRate;
  final int activeVoices;

  const DspTimingSample({
    required this.timestamp,
    required this.stageTimingsUs,
    required this.blockSize,
    required this.sampleRate,
    required this.activeVoices,
  });

  /// Total DSP time in microseconds
  double get totalUs => stageTimingsUs[DspStage.total] ?? 0.0;

  /// Available time for this block (microseconds)
  double get availableUs => (blockSize / sampleRate) * 1000000.0;

  /// DSP load as percentage (0-100)
  double get loadPercent {
    final available = availableUs;
    if (available <= 0) return 0;
    return (totalUs / available * 100).clamp(0.0, 100.0);
  }

  /// Is this sample showing overload?
  bool get isOverloaded => loadPercent > 90;

  /// Is this sample in warning zone?
  bool get isWarning => loadPercent > 70 && loadPercent <= 90;
}

/// DSP profiler statistics
class DspProfilerStats {
  final double avgLoadPercent;
  final double peakLoadPercent;
  final double minLoadPercent;
  final Map<DspStage, double> avgStageTimingsUs;
  final Map<DspStage, double> peakStageTimingsUs;
  final int totalSamples;
  final int overloadCount;
  final int warningCount;
  final double avgBlockTimeUs;
  final double peakBlockTimeUs;

  const DspProfilerStats({
    required this.avgLoadPercent,
    required this.peakLoadPercent,
    required this.minLoadPercent,
    required this.avgStageTimingsUs,
    required this.peakStageTimingsUs,
    required this.totalSamples,
    required this.overloadCount,
    required this.warningCount,
    required this.avgBlockTimeUs,
    required this.peakBlockTimeUs,
  });

  /// Empty stats
  factory DspProfilerStats.empty() => const DspProfilerStats(
    avgLoadPercent: 0,
    peakLoadPercent: 0,
    minLoadPercent: 0,
    avgStageTimingsUs: {},
    peakStageTimingsUs: {},
    totalSamples: 0,
    overloadCount: 0,
    warningCount: 0,
    avgBlockTimeUs: 0,
    peakBlockTimeUs: 0,
  );
}

/// DSP Profiler - tracks real-time audio processing performance
class DspProfiler {
  final int maxSamples;
  final List<DspTimingSample> _samples = [];

  // Running stats
  double _totalLoad = 0;
  double _peakLoad = 0;
  double _minLoad = double.infinity;
  int _overloadCount = 0;
  int _warningCount = 0;

  // Stage-specific accumulators
  final Map<DspStage, double> _stageTotals = {};
  final Map<DspStage, double> _stagePeaks = {};

  DspProfiler({this.maxSamples = 1000});

  /// Record a new timing sample
  void record({
    required Map<DspStage, double> stageTimingsUs,
    required int blockSize,
    required double sampleRate,
    required int activeVoices,
  }) {
    final sample = DspTimingSample(
      timestamp: DateTime.now(),
      stageTimingsUs: Map.from(stageTimingsUs),
      blockSize: blockSize,
      sampleRate: sampleRate,
      activeVoices: activeVoices,
    );

    // Update running stats
    _totalLoad += sample.loadPercent;
    if (sample.loadPercent > _peakLoad) _peakLoad = sample.loadPercent;
    if (sample.loadPercent < _minLoad) _minLoad = sample.loadPercent;
    if (sample.isOverloaded) _overloadCount++;
    if (sample.isWarning) _warningCount++;

    // Update stage stats
    for (final entry in stageTimingsUs.entries) {
      _stageTotals[entry.key] = (_stageTotals[entry.key] ?? 0) + entry.value;
      final current = _stagePeaks[entry.key] ?? 0;
      if (entry.value > current) _stagePeaks[entry.key] = entry.value;
    }

    _samples.add(sample);

    // Trim old samples
    while (_samples.length > maxSamples) {
      _samples.removeAt(0);
    }
  }

  /// Get recent samples
  List<DspTimingSample> getRecentSamples({int count = 100}) {
    final start = _samples.length > count ? _samples.length - count : 0;
    return _samples.sublist(start);
  }

  /// Get current load (from most recent sample)
  double get currentLoad => _samples.isNotEmpty ? _samples.last.loadPercent : 0;

  /// Get current block time
  double get currentBlockTimeUs => _samples.isNotEmpty ? _samples.last.totalUs : 0;

  /// Get statistics
  DspProfilerStats getStats() {
    if (_samples.isEmpty) return DspProfilerStats.empty();

    final avgLoad = _totalLoad / _samples.length;
    final avgStageTimings = <DspStage, double>{};
    for (final stage in _stageTotals.keys) {
      avgStageTimings[stage] = _stageTotals[stage]! / _samples.length;
    }

    // Calculate average block time
    double totalBlockTime = 0;
    double peakBlockTime = 0;
    for (final sample in _samples) {
      totalBlockTime += sample.totalUs;
      if (sample.totalUs > peakBlockTime) peakBlockTime = sample.totalUs;
    }

    return DspProfilerStats(
      avgLoadPercent: avgLoad,
      peakLoadPercent: _peakLoad,
      minLoadPercent: _minLoad == double.infinity ? 0 : _minLoad,
      avgStageTimingsUs: avgStageTimings,
      peakStageTimingsUs: Map.from(_stagePeaks),
      totalSamples: _samples.length,
      overloadCount: _overloadCount,
      warningCount: _warningCount,
      avgBlockTimeUs: totalBlockTime / _samples.length,
      peakBlockTimeUs: peakBlockTime,
    );
  }

  /// Get load history for graphing (last N samples)
  List<double> getLoadHistory({int count = 100}) {
    final samples = getRecentSamples(count: count);
    return samples.map((s) => s.loadPercent).toList();
  }

  /// Get stage breakdown for current sample
  Map<DspStage, double> getCurrentStageBreakdown() {
    if (_samples.isEmpty) return {};
    return Map.from(_samples.last.stageTimingsUs);
  }

  /// Clear all data
  void clear() {
    _samples.clear();
    _totalLoad = 0;
    _peakLoad = 0;
    _minLoad = double.infinity;
    _overloadCount = 0;
    _warningCount = 0;
    _stageTotals.clear();
    _stagePeaks.clear();
  }

  /// Simulate sample for testing
  void simulateSample({
    double baseLoad = 15.0,
    double variance = 10.0,
    int blockSize = 256,
    double sampleRate = 44100,
    int activeVoices = 8,
  }) {
    final random = math.Random();
    final load = baseLoad + (random.nextDouble() * variance * 2 - variance);
    final availableUs = (blockSize / sampleRate) * 1000000.0;
    final totalUs = availableUs * load / 100.0;

    // Distribute time across stages
    final stageTimings = <DspStage, double>{
      DspStage.input: totalUs * 0.05,
      DspStage.mixing: totalUs * 0.25,
      DspStage.effects: totalUs * 0.50,
      DspStage.metering: totalUs * 0.10,
      DspStage.output: totalUs * 0.10,
      DspStage.total: totalUs,
    };

    record(
      stageTimingsUs: stageTimings,
      blockSize: blockSize,
      sampleRate: sampleRate,
      activeVoices: activeVoices,
    );
  }
}
