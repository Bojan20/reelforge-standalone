/// Mixer Provider
///
/// Professional DAW mixer state management:
/// - Dynamic tracks (auto-created from timeline)
/// - Buses (UI, SFX, Music, VO, Ambient, Master)
/// - Aux sends/returns
/// - VCA faders
/// - Groups
/// - Full routing matrix
/// - Real-time metering integration

import 'dart:async';
import 'dart:math' show pow, log, ln10;
import 'package:flutter/material.dart';
import '../src/rust/native_ffi.dart';
import '../src/rust/engine_api.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MIXER CHANNEL TYPES
// ═══════════════════════════════════════════════════════════════════════════

enum ChannelType {
  audio,      // Audio track
  instrument, // MIDI/Instrument track
  bus,        // Group/Submix bus
  aux,        // Aux send/return
  vca,        // VCA fader
  master,     // Master output
}

enum BusType {
  ui,       // UI sounds
  sfx,      // Sound effects
  music,    // Music
  vo,       // Voice over
  ambient,  // Ambient/Atmos
  custom,   // User-created
}

// ═══════════════════════════════════════════════════════════════════════════
// MIXER CHANNEL
// ═══════════════════════════════════════════════════════════════════════════

class MixerChannel {
  final String id;
  final String name;
  final ChannelType type;
  final Color color;

  // Levels
  double volume;      // 0.0 - 1.5 (0dB = 1.0)
  double pan;         // -1.0 to 1.0
  bool muted;
  bool soloed;
  bool armed;         // Record arm
  bool monitorInput;  // Input monitoring

  // Routing
  String? outputBus;  // Target bus ID (null = master)
  List<AuxSend> sends;
  String? vcaId;      // Assigned VCA
  String? groupId;    // Assigned group

  // Metering (updated from MeterProvider)
  double peakL;
  double peakR;
  double rmsL;
  double rmsR;
  bool clipping;

  // Track reference (for audio tracks)
  int? trackIndex;    // Engine track index

  MixerChannel({
    required this.id,
    required this.name,
    required this.type,
    this.color = const Color(0xFF4A9EFF),
    this.volume = 1.0,
    this.pan = 0.0,
    this.muted = false,
    this.soloed = false,
    this.armed = false,
    this.monitorInput = false,
    this.outputBus,
    this.sends = const [],
    this.vcaId,
    this.groupId,
    this.peakL = 0.0,
    this.peakR = 0.0,
    this.rmsL = 0.0,
    this.rmsR = 0.0,
    this.clipping = false,
    this.trackIndex,
  });

  MixerChannel copyWith({
    String? id,
    String? name,
    ChannelType? type,
    Color? color,
    double? volume,
    double? pan,
    bool? muted,
    bool? soloed,
    bool? armed,
    bool? monitorInput,
    String? outputBus,
    List<AuxSend>? sends,
    String? vcaId,
    String? groupId,
    double? peakL,
    double? peakR,
    double? rmsL,
    double? rmsR,
    bool? clipping,
    int? trackIndex,
  }) {
    return MixerChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      color: color ?? this.color,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      muted: muted ?? this.muted,
      soloed: soloed ?? this.soloed,
      armed: armed ?? this.armed,
      monitorInput: monitorInput ?? this.monitorInput,
      outputBus: outputBus ?? this.outputBus,
      sends: sends ?? this.sends,
      vcaId: vcaId ?? this.vcaId,
      groupId: groupId ?? this.groupId,
      peakL: peakL ?? this.peakL,
      peakR: peakR ?? this.peakR,
      rmsL: rmsL ?? this.rmsL,
      rmsR: rmsR ?? this.rmsR,
      clipping: clipping ?? this.clipping,
      trackIndex: trackIndex ?? this.trackIndex,
    );
  }

  /// Convert volume (0-1.5) to dB string
  String get volumeDbString {
    if (volume <= 0) return '-∞';
    final db = 20 * _log10(volume);
    if (db <= -60) return '-∞';
    return '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';
  }

  double _log10(double x) => x > 0 ? (log(x) / ln10) : double.negativeInfinity;
}

// ═══════════════════════════════════════════════════════════════════════════
// AUX SEND
// ═══════════════════════════════════════════════════════════════════════════

class AuxSend {
  final String auxId;
  double level;       // 0.0 - 1.0
  bool preFader;      // Pre/post fader
  bool enabled;

  AuxSend({
    required this.auxId,
    this.level = 0.0,
    this.preFader = false,
    this.enabled = true,
  });

  AuxSend copyWith({
    String? auxId,
    double? level,
    bool? preFader,
    bool? enabled,
  }) {
    return AuxSend(
      auxId: auxId ?? this.auxId,
      level: level ?? this.level,
      preFader: preFader ?? this.preFader,
      enabled: enabled ?? this.enabled,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// VCA FADER
// ═══════════════════════════════════════════════════════════════════════════

class VcaFader {
  final String id;
  final String name;
  final Color color;
  double level;       // Multiplier 0.0 - 1.5
  bool muted;
  bool soloed;
  List<String> memberIds;  // Channel IDs assigned to this VCA

  VcaFader({
    required this.id,
    required this.name,
    this.color = const Color(0xFFFF9040),
    this.level = 1.0,
    this.muted = false,
    this.soloed = false,
    this.memberIds = const [],
  });

  VcaFader copyWith({
    String? id,
    String? name,
    Color? color,
    double? level,
    bool? muted,
    bool? soloed,
    List<String>? memberIds,
  }) {
    return VcaFader(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      level: level ?? this.level,
      muted: muted ?? this.muted,
      soloed: soloed ?? this.soloed,
      memberIds: memberIds ?? this.memberIds,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GROUP
// ═══════════════════════════════════════════════════════════════════════════

enum GroupLinkMode {
  relative,   // Maintain relative levels
  absolute,   // All move to same position
}

class MixerGroup {
  final String id;
  final String name;
  final Color color;
  GroupLinkMode linkMode;
  bool linkVolume;
  bool linkPan;
  bool linkMute;
  bool linkSolo;
  List<String> memberIds;

  MixerGroup({
    required this.id,
    required this.name,
    this.color = const Color(0xFF40FF90),
    this.linkMode = GroupLinkMode.relative,
    this.linkVolume = true,
    this.linkPan = false,
    this.linkMute = true,
    this.linkSolo = true,
    this.memberIds = const [],
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// MIXER PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

class MixerProvider extends ChangeNotifier {
  // Channels by type
  final Map<String, MixerChannel> _channels = {};
  final Map<String, MixerChannel> _buses = {};
  final Map<String, MixerChannel> _auxes = {};
  final Map<String, VcaFader> _vcas = {};
  final Map<String, MixerGroup> _groups = {};

  // Master channel
  late MixerChannel _master;

  // Track index counter
  int _nextTrackIndex = 1;

  // Metering subscription
  StreamSubscription<MeteringState>? _meteringSub;
  StreamSubscription<TransportState>? _transportSub;
  Timer? _decayTimer;
  bool _isPlaying = false;

  // Solo state tracking
  final Set<String> _soloedChannels = {};

  MixerProvider() {
    _initializeDefaultBuses();
    _subscribeToMetering();
    _subscribeToTransport();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<MixerChannel> get channels => _channels.values.toList();
  List<MixerChannel> get buses => _buses.values.toList();
  List<MixerChannel> get auxes => _auxes.values.toList();
  List<VcaFader> get vcas => _vcas.values.toList();
  List<MixerGroup> get groups => _groups.values.toList();
  MixerChannel get master => _master;

  MixerChannel? getChannel(String id) => _channels[id];
  MixerChannel? getBus(String id) => _buses[id];
  MixerChannel? getAux(String id) => _auxes[id];
  VcaFader? getVca(String id) => _vcas[id];
  MixerGroup? getGroup(String id) => _groups[id];

  bool get hasSoloedChannels => _soloedChannels.isNotEmpty;

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  void _initializeDefaultBuses() {
    // Master bus only - Cubase style stereo output
    // Buses are created dynamically when tracks are added
    _master = MixerChannel(
      id: 'master',
      name: 'Stereo Out',
      type: ChannelType.master,
      color: const Color(0xFFFF9040),
    );
    // No default buses - they are created when tracks are added
  }

  void _subscribeToMetering() {
    _meteringSub = engine.meteringStream.listen(_updateMeters);
  }

  void _subscribeToTransport() {
    _transportSub = engine.transportStream.listen((transport) {
      final wasPlaying = _isPlaying;
      _isPlaying = transport.isPlaying;

      // When playback stops, immediately start decay (Cubase-style)
      if (wasPlaying && !_isPlaying) {
        _startMeterDecay();
      } else if (_isPlaying) {
        _stopMeterDecay();
      }
    });
  }

  void _startMeterDecay() {
    _decayTimer?.cancel();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      bool hasActivity = false;

      // Decay master meters
      if (_master.peakL > 0.001 || _master.peakR > 0.001) {
        hasActivity = true;
        _master = _master.copyWith(
          peakL: _master.peakL * 0.85,
          peakR: _master.peakR * 0.85,
          rmsL: _master.rmsL * 0.85,
          rmsR: _master.rmsR * 0.85,
          clipping: false,
        );
      }

      // Decay channel meters
      for (final channel in _channels.values) {
        if (channel.peakL > 0.001 || channel.peakR > 0.001) {
          hasActivity = true;
          _channels[channel.id] = channel.copyWith(
            peakL: channel.peakL * 0.85,
            peakR: channel.peakR * 0.85,
            rmsL: channel.rmsL * 0.85,
            rmsR: channel.rmsR * 0.85,
            clipping: false,
          );
        }
      }

      notifyListeners();

      if (!hasActivity) {
        _stopMeterDecay();
      }
    });
  }

  void _stopMeterDecay() {
    _decayTimer?.cancel();
    _decayTimer = null;
  }

  void _updateMeters(MeteringState metering) {
    // Update master meters (from master peak/rms)
    _master = _master.copyWith(
      peakL: _dbToLinear(metering.masterPeakL),
      peakR: _dbToLinear(metering.masterPeakR),
      rmsL: _dbToLinear(metering.masterRmsL),
      rmsR: _dbToLinear(metering.masterRmsR),
      clipping: metering.masterPeakL > -0.1 || metering.masterPeakR > -0.1,
    );

    // Update channel meters (direct from track metering)
    // In Cubase-style: each track has its own meter before master
    for (final channel in _channels.values) {
      if (channel.trackIndex != null && channel.trackIndex! < metering.buses.length) {
        final trackMeter = metering.buses[channel.trackIndex!];
        _channels[channel.id] = channel.copyWith(
          peakL: _dbToLinear(trackMeter.peakL),
          peakR: _dbToLinear(trackMeter.peakR),
          rmsL: _dbToLinear(trackMeter.rmsL),
          rmsR: _dbToLinear(trackMeter.rmsR),
        );
      }
    }

    notifyListeners();
  }

  double _dbToLinear(double db) {
    if (db <= -60) return 0.0;
    return pow(10, db / 20).toDouble().clamp(0.0, 1.5);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANNEL MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new audio channel (called when track is created in timeline)
  MixerChannel createChannel({
    required String name,
    Color? color,
    String? outputBus,
  }) {
    final id = 'ch_${DateTime.now().millisecondsSinceEpoch}';
    final trackIndex = _nextTrackIndex++;

    // Create in engine
    final engineTrackId = NativeFFI.instance.createTrack(
      name,
      (color ?? const Color(0xFF4A9EFF)).value,
      _getBusEngineId(outputBus ?? 'bus_sfx'),
    );

    final channel = MixerChannel(
      id: id,
      name: name,
      type: ChannelType.audio,
      color: color ?? _getNextTrackColor(),
      outputBus: outputBus ?? 'bus_sfx',
      trackIndex: engineTrackId > 0 ? engineTrackId : trackIndex,
    );

    _channels[id] = channel;
    notifyListeners();
    return channel;
  }

  /// Create channel from timeline track creation
  /// trackId is the engine track ID (as string, but may be numeric for native tracks)
  /// Cubase-style: track = mixer channel, direct to master
  MixerChannel createChannelFromTrack(String trackId, String trackName, Color trackColor) {
    // Check if channel already exists for this track
    final existing = _channels.values.where((c) => c.id == 'ch_$trackId').firstOrNull;
    if (existing != null) return existing;

    final id = 'ch_$trackId';

    // Try to parse trackId as native engine ID (for FFI calls)
    // Native engine returns numeric IDs, mock returns 'track-123...' strings
    final nativeTrackId = int.tryParse(trackId);

    // Cubase-style: channels route directly to master (no intermediate buses)
    final channel = MixerChannel(
      id: id,
      name: trackName,
      type: ChannelType.audio,
      color: trackColor,
      outputBus: 'master', // Direct to master, not to bus
      trackIndex: nativeTrackId, // Store native engine track ID for FFI
    );

    _channels[id] = channel;
    notifyListeners();
    return channel;
  }

  /// Delete a channel
  void deleteChannel(String id) {
    final channel = _channels[id];
    if (channel == null) return;

    // Delete from engine
    if (channel.trackIndex != null) {
      NativeFFI.instance.deleteTrack(channel.trackIndex!);
    }

    // Remove from VCAs and groups
    for (final vca in _vcas.values) {
      vca.memberIds.remove(id);
    }
    for (final group in _groups.values) {
      group.memberIds.remove(id);
    }

    _channels.remove(id);
    _soloedChannels.remove(id);
    notifyListeners();
  }

  /// Set channel volume (0.0 - 1.5, where 1.0 = 0dB)
  void setVolume(String id, double volume) {
    final channel = _channels[id] ?? _buses[id];
    if (channel == null) return;

    channel.volume = volume.clamp(0.0, 1.5);

    // Send to engine if track channel
    // Rust engine_set_track_volume expects LINEAR value (0.0-1.5), NOT dB!
    if (channel.trackIndex != null) {
      NativeFFI.instance.setTrackVolume(channel.trackIndex!, channel.volume);
    }

    notifyListeners();
  }

  /// Toggle channel mute
  void toggleMute(String id) {
    final channel = _channels[id] ?? _buses[id];
    if (channel == null) return;

    channel.muted = !channel.muted;

    // Send to engine if track channel
    if (channel.trackIndex != null) {
      NativeFFI.instance.setTrackMute(channel.trackIndex!, channel.muted);
    }

    notifyListeners();
  }

  /// Toggle channel solo
  void toggleSolo(String id) {
    final channel = _channels[id] ?? _buses[id];
    if (channel == null) return;

    channel.soloed = !channel.soloed;

    if (channel.soloed) {
      _soloedChannels.add(id);
    } else {
      _soloedChannels.remove(id);
    }

    // Send to engine if track channel
    if (channel.trackIndex != null) {
      NativeFFI.instance.setTrackSolo(channel.trackIndex!, channel.soloed);
    }

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUS MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a custom bus
  MixerChannel createBus({
    required String name,
    Color? color,
    String? outputBus,
  }) {
    final id = 'bus_${DateTime.now().millisecondsSinceEpoch}';

    final bus = MixerChannel(
      id: id,
      name: name,
      type: ChannelType.bus,
      color: color ?? const Color(0xFF9B59B6),
      outputBus: outputBus ?? 'master',
    );

    _buses[id] = bus;
    notifyListeners();
    return bus;
  }

  /// Delete a custom bus (cannot delete default buses)
  void deleteBus(String id) {
    if (_isDefaultBus(id)) return;

    // Reroute channels to master
    for (final channel in _channels.values) {
      if (channel.outputBus == id) {
        _channels[channel.id] = channel.copyWith(outputBus: 'master');
      }
    }

    _buses.remove(id);
    notifyListeners();
  }

  bool _isDefaultBus(String id) {
    return ['bus_ui', 'bus_sfx', 'bus_music', 'bus_vo', 'bus_ambient'].contains(id);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUX MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create an aux send/return
  MixerChannel createAux({
    required String name,
    Color? color,
  }) {
    final id = 'aux_${DateTime.now().millisecondsSinceEpoch}';

    final aux = MixerChannel(
      id: id,
      name: name,
      type: ChannelType.aux,
      color: color ?? const Color(0xFFE74C3C),
      outputBus: 'master',
    );

    _auxes[id] = aux;
    notifyListeners();
    return aux;
  }

  /// Delete an aux
  void deleteAux(String id) {
    // Remove sends from all channels
    for (final channel in _channels.values) {
      final newSends = channel.sends.where((s) => s.auxId != id).toList();
      if (newSends.length != channel.sends.length) {
        _channels[channel.id] = channel.copyWith(sends: newSends);
      }
    }

    _auxes.remove(id);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VCA MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a VCA fader
  VcaFader createVca({required String name, Color? color}) {
    final id = 'vca_${DateTime.now().millisecondsSinceEpoch}';

    // Create in engine
    NativeFFI.instance.vcaCreate(name);

    final vca = VcaFader(
      id: id,
      name: name,
      color: color ?? const Color(0xFFFF9040),
    );

    _vcas[id] = vca;
    notifyListeners();
    return vca;
  }

  /// Delete a VCA
  void deleteVca(String id) {
    final vca = _vcas[id];
    if (vca == null) return;

    // Remove VCA assignment from channels
    for (final channel in _channels.values) {
      if (channel.vcaId == id) {
        _channels[channel.id] = channel.copyWith(vcaId: null);
      }
    }

    _vcas.remove(id);
    notifyListeners();
  }

  /// Assign channel to VCA
  void assignChannelToVca(String channelId, String vcaId) {
    final channel = _channels[channelId];
    final vca = _vcas[vcaId];
    if (channel == null || vca == null) return;

    // Update channel
    _channels[channelId] = channel.copyWith(vcaId: vcaId);

    // Update VCA members
    if (!vca.memberIds.contains(channelId)) {
      _vcas[vcaId] = vca.copyWith(
        memberIds: [...vca.memberIds, channelId],
      );
    }

    // Update engine
    if (channel.trackIndex != null) {
      NativeFFI.instance.vcaAssignTrack(
        int.parse(vcaId.replaceAll('vca_', '')),
        channel.trackIndex!,
      );
    }

    notifyListeners();
  }

  /// Remove channel from VCA
  void removeChannelFromVca(String channelId, String vcaId) {
    final channel = _channels[channelId];
    final vca = _vcas[vcaId];
    if (channel == null || vca == null) return;

    _channels[channelId] = channel.copyWith(vcaId: null);
    _vcas[vcaId] = vca.copyWith(
      memberIds: vca.memberIds.where((id) => id != channelId).toList(),
    );

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a group
  MixerGroup createGroup({required String name, Color? color}) {
    final id = 'grp_${DateTime.now().millisecondsSinceEpoch}';

    NativeFFI.instance.groupCreate(name);

    final group = MixerGroup(
      id: id,
      name: name,
      color: color ?? const Color(0xFF40FF90),
    );

    _groups[id] = group;
    notifyListeners();
    return group;
  }

  /// Delete a group
  void deleteGroup(String id) {
    final group = _groups[id];
    if (group == null) return;

    // Remove group assignment from channels
    for (final channel in _channels.values) {
      if (channel.groupId == id) {
        _channels[channel.id] = channel.copyWith(groupId: null);
      }
    }

    _groups.remove(id);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANNEL CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  void setChannelVolume(String id, double volume) {
    final channel = _channels[id] ?? _buses[id] ?? _auxes[id];
    if (channel == null) return;

    final clampedVolume = volume.clamp(0.0, 1.5);

    if (_channels.containsKey(id)) {
      _channels[id] = channel.copyWith(volume: clampedVolume);
      if (channel.trackIndex != null) {
        engine.setTrackVolume(channel.trackIndex!, clampedVolume);
      }
    } else if (_buses.containsKey(id)) {
      _buses[id] = channel.copyWith(volume: clampedVolume);
      engine.setBusVolume(_getBusEngineId(id), clampedVolume);
    } else if (_auxes.containsKey(id)) {
      _auxes[id] = channel.copyWith(volume: clampedVolume);
    }

    notifyListeners();
  }

  void setChannelPan(String id, double pan) {
    final channel = _channels[id] ?? _buses[id] ?? _auxes[id];
    if (channel == null) return;

    final clampedPan = pan.clamp(-1.0, 1.0);

    if (_channels.containsKey(id)) {
      _channels[id] = channel.copyWith(pan: clampedPan);
      if (channel.trackIndex != null) {
        engine.setTrackPan(channel.trackIndex!, clampedPan);
      }
    } else if (_buses.containsKey(id)) {
      _buses[id] = channel.copyWith(pan: clampedPan);
      engine.setBusPan(_getBusEngineId(id), clampedPan);
    } else if (_auxes.containsKey(id)) {
      _auxes[id] = channel.copyWith(pan: clampedPan);
    }

    notifyListeners();
  }

  void toggleChannelMute(String id) {
    final channel = _channels[id] ?? _buses[id] ?? _auxes[id];
    if (channel == null) return;

    final newMuted = !channel.muted;

    if (_channels.containsKey(id)) {
      _channels[id] = channel.copyWith(muted: newMuted);
      if (channel.trackIndex != null) {
        NativeFFI.instance.setTrackMute(channel.trackIndex!, newMuted);
      }
    } else if (_buses.containsKey(id)) {
      _buses[id] = channel.copyWith(muted: newMuted);
      NativeFFI.instance.mixerSetBusMute(_getBusEngineId(id), newMuted);
    } else if (_auxes.containsKey(id)) {
      _auxes[id] = channel.copyWith(muted: newMuted);
    }

    notifyListeners();
  }

  void toggleChannelSolo(String id) {
    final channel = _channels[id] ?? _buses[id] ?? _auxes[id];
    if (channel == null) return;

    final newSoloed = !channel.soloed;

    if (newSoloed) {
      _soloedChannels.add(id);
    } else {
      _soloedChannels.remove(id);
    }

    if (_channels.containsKey(id)) {
      _channels[id] = channel.copyWith(soloed: newSoloed);
      if (channel.trackIndex != null) {
        NativeFFI.instance.setTrackSolo(channel.trackIndex!, newSoloed);
      }
    } else if (_buses.containsKey(id)) {
      _buses[id] = channel.copyWith(soloed: newSoloed);
      NativeFFI.instance.mixerSetBusSolo(_getBusEngineId(id), newSoloed);
    } else if (_auxes.containsKey(id)) {
      _auxes[id] = channel.copyWith(soloed: newSoloed);
    }

    notifyListeners();
  }

  void toggleChannelArm(String id) {
    final channel = _channels[id];
    if (channel == null) return;

    _channels[id] = channel.copyWith(armed: !channel.armed);
    notifyListeners();
  }

  void setChannelOutput(String channelId, String busId) {
    final channel = _channels[channelId];
    if (channel == null) return;

    _channels[channelId] = channel.copyWith(outputBus: busId);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VCA CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  void setVcaLevel(String id, double level) {
    final vca = _vcas[id];
    if (vca == null) return;

    final clampedLevel = level.clamp(0.0, 1.5);
    _vcas[id] = vca.copyWith(level: clampedLevel);

    // Update engine
    final engineId = int.tryParse(id.replaceAll('vca_', '')) ?? 0;
    NativeFFI.instance.vcaSetLevel(engineId, clampedLevel);

    notifyListeners();
  }

  void toggleVcaMute(String id) {
    final vca = _vcas[id];
    if (vca == null) return;

    final newMuted = !vca.muted;
    _vcas[id] = vca.copyWith(muted: newMuted);

    final engineId = int.tryParse(id.replaceAll('vca_', '')) ?? 0;
    NativeFFI.instance.vcaSetMute(engineId, newMuted);

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MASTER CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  void setMasterVolume(double volume) {
    final clampedVolume = volume.clamp(0.0, 1.5);
    _master = _master.copyWith(volume: clampedVolume);
    // Use EngineApi which handles both FFI and mock mode
    engine.setMasterVolume(clampedVolume);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUX SEND CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  void setAuxSendLevel(String channelId, String auxId, double level) {
    final channel = _channels[channelId];
    if (channel == null) return;

    final sends = List<AuxSend>.from(channel.sends);
    final existingIndex = sends.indexWhere((s) => s.auxId == auxId);

    if (existingIndex >= 0) {
      sends[existingIndex] = sends[existingIndex].copyWith(level: level);
    } else {
      sends.add(AuxSend(auxId: auxId, level: level));
    }

    _channels[channelId] = channel.copyWith(sends: sends);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITIES
  // ═══════════════════════════════════════════════════════════════════════════

  int _getBusEngineId(String busId) {
    switch (busId) {
      case 'bus_ui': return 0;
      case 'bus_sfx': return 1;
      case 'bus_music': return 2;
      case 'bus_vo': return 3;
      case 'bus_ambient': return 4;
      case 'master': return 5;
      default: return 1; // Default to SFX
    }
  }

  double _linearToDb(double linear) {
    if (linear <= 0) return -96.0;
    return 20 * _log10(linear);
  }

  double _log10(double x) => x > 0 ? (log(x) / ln10) : -96.0;

  Color _getNextTrackColor() {
    const colors = [
      Color(0xFF4A9EFF), // Blue
      Color(0xFF40C8FF), // Cyan
      Color(0xFF40FF90), // Green
      Color(0xFFFFD93D), // Yellow
      Color(0xFFFF9040), // Orange
      Color(0xFFFF6B6B), // Red
      Color(0xFF9B59B6), // Purple
      Color(0xFFE91E63), // Pink
    ];
    return colors[_channels.length % colors.length];
  }

  @override
  void dispose() {
    _meteringSub?.cancel();
    _transportSub?.cancel();
    _decayTimer?.cancel();
    super.dispose();
  }
}
