// Mixer Provider
//
// Professional DAW mixer state management:
// - Dynamic tracks (auto-created from timeline)
// - Buses (UI, SFX, Music, VO, Ambient, Master)
// - Aux sends/returns
// - VCA faders
// - Groups
// - Full routing matrix
// - Real-time metering integration

import 'dart:async';
import 'dart:math' show pow, log, ln10;
import 'package:flutter/material.dart';
import '../src/rust/native_ffi.dart';
import '../src/rust/engine_api.dart';
import '../models/layout_models.dart' show InsertSlot;
import '../models/mixer_undo_actions.dart';
import 'dsp_chain_provider.dart';
import 'undo_manager.dart';
import '../utils/input_validator.dart'; // ✅ Input validation

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
  double pan;         // -1.0 to 1.0 (left channel for stereo)
  double panRight;    // -1.0 to 1.0 (right channel for stereo, Pro Tools dual-pan)
  bool isStereo;      // true = dual pan (stereo), false = single pan (mono)
  bool muted;
  bool soloed;
  bool armed;         // Record arm
  bool monitorInput;  // Input monitoring
  bool phaseInverted; // Phase/polarity invert (Ø)
  double inputGain;   // Input gain/trim in dB (-20 to +20)

  // Routing
  String? outputBus;  // Target bus ID (null = master)
  String? inputSource; // Input source (None, Input 1, etc.)
  List<AuxSend> sends;
  String? vcaId;      // Assigned VCA
  String? groupId;    // Assigned group

  // Inserts (8 slots: 0-3 pre-fader, 4-7 post-fader)
  List<InsertSlot> inserts;

  // Metering (updated from MeterProvider)
  double peakL;
  double peakR;
  double rmsL;
  double rmsR;
  bool clipping;

  // Track reference (for audio tracks)
  int? trackIndex;    // Engine track index

  // Phase 4: Solo Safe, Comments, Folder
  bool soloSafe;      // Excluded from SIP muting (§4.2)
  String comments;    // Per-strip text notes
  bool isFolder;      // Routing Folder track
  bool folderExpanded; // Folder expand/collapse state
  int folderChildCount; // Number of child tracks in folder

  MixerChannel({
    required this.id,
    required this.name,
    required this.type,
    this.color = const Color(0xFF4A9EFF),
    this.volume = 1.0,
    this.pan = 0.0,
    this.panRight = 0.0,
    this.isStereo = true,
    this.muted = false,
    this.soloed = false,
    this.armed = false,
    this.monitorInput = false,
    this.phaseInverted = false,
    this.inputGain = 0.0,
    this.outputBus,
    this.inputSource,
    this.sends = const [],
    this.vcaId,
    this.groupId,
    List<InsertSlot>? inserts,
    this.peakL = 0.0,
    this.peakR = 0.0,
    this.rmsL = 0.0,
    this.rmsR = 0.0,
    this.clipping = false,
    this.trackIndex,
    this.soloSafe = false,
    this.comments = '',
    this.isFolder = false,
    this.folderExpanded = true,
    this.folderChildCount = 0,
  }) : inserts = inserts ?? _defaultInserts();

  /// Default empty insert slots (8 total: 4 pre-fader, 4 post-fader)
  static List<InsertSlot> _defaultInserts() => [
    InsertSlot.empty(0, isPreFader: true),
    InsertSlot.empty(1, isPreFader: true),
    InsertSlot.empty(2, isPreFader: true),
    InsertSlot.empty(3, isPreFader: true),
    InsertSlot.empty(4, isPreFader: false),
    InsertSlot.empty(5, isPreFader: false),
    InsertSlot.empty(6, isPreFader: false),
    InsertSlot.empty(7, isPreFader: false),
  ];

  MixerChannel copyWith({
    String? id,
    String? name,
    ChannelType? type,
    Color? color,
    double? volume,
    double? pan,
    double? panRight,
    bool? isStereo,
    bool? muted,
    bool? soloed,
    bool? armed,
    bool? monitorInput,
    bool? phaseInverted,
    double? inputGain,
    String? outputBus,
    String? inputSource,
    List<AuxSend>? sends,
    String? vcaId,
    String? groupId,
    List<InsertSlot>? inserts,
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
      panRight: panRight ?? this.panRight,
      isStereo: isStereo ?? this.isStereo,
      muted: muted ?? this.muted,
      soloed: soloed ?? this.soloed,
      armed: armed ?? this.armed,
      monitorInput: monitorInput ?? this.monitorInput,
      phaseInverted: phaseInverted ?? this.phaseInverted,
      inputGain: inputGain ?? this.inputGain,
      outputBus: outputBus ?? this.outputBus,
      inputSource: inputSource ?? this.inputSource,
      sends: sends ?? this.sends,
      vcaId: vcaId ?? this.vcaId,
      groupId: groupId ?? this.groupId,
      inserts: inserts ?? this.inserts,
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

/// Parameters that can be linked in a group
enum GroupLinkParameter {
  volume,  // 0
  pan,     // 1
  mute,    // 2
  solo,    // 3
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

  // Channel order (list of channel IDs in display order)
  // Supports bidirectional sync with timeline track order
  final List<String> _channelOrder = [];

  // Callback for notifying timeline when channel order changes
  void Function(List<String> channelIds)? onChannelOrderChanged;

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

  // Drag anchor tracking: captures pre-drag value for undo on drag-end
  final Map<String, double> _panDragAnchors = {};

  MixerProvider() {
    _initializeDefaultBuses();
    _subscribeToMetering();
    _subscribeToTransport();
    _subscribeToDspChainProvider();
  }

  /// P1.1: Subscribe to DspChainProvider for unified DSP state
  void _subscribeToDspChainProvider() {
    DspChainProvider.instance.addListener(_syncFromDspChainProvider);
  }

  /// P1.1: Sync insert slots from DspChainProvider when it changes
  void _syncFromDspChainProvider() {
    final dspProvider = DspChainProvider.instance;

    // For each channel, sync its insert slots from DspChainProvider
    for (final channel in _channels.values) {
      final trackId = int.tryParse(channel.id.replaceAll('track_', ''));
      if (trackId == null) continue;

      if (!dspProvider.hasChain(trackId)) continue;

      final chain = dspProvider.getChain(trackId);
      final newInserts = _dspChainToInserts(chain);

      // Only update if different
      if (!_insertsEqual(channel.inserts, newInserts)) {
        _channels[channel.id] = channel.copyWith(inserts: newInserts);
      }
    }

    notifyListeners();
  }

  /// P1.1: Convert DspChain to InsertSlot list
  List<InsertSlot> _dspChainToInserts(DspChain chain) {
    final inserts = <InsertSlot>[];
    final sortedNodes = chain.sortedNodes;

    // DspChain has up to 8 nodes
    for (int i = 0; i < 8; i++) {
      if (i < sortedNodes.length) {
        final node = sortedNodes[i];
        inserts.add(InsertSlot(
          id: node.id,
          name: node.type.fullName,
          type: node.type.name, // eq, compressor, limiter, etc.
          isPreFader: i < 4, // First 4 are pre-fader
          bypassed: node.bypass,
          wetDry: node.wetDry,
        ));
      } else {
        inserts.add(InsertSlot.empty(i, isPreFader: i < 4));
      }
    }

    return inserts;
  }

  /// P1.1: Compare two insert lists for equality
  bool _insertsEqual(List<InsertSlot> a, List<InsertSlot> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].bypassed != b[i].bypassed ||
          a[i].wetDry != b[i].wetDry) {
        return false;
      }
    }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns channels in display order (respects drag-drop reordering)
  List<MixerChannel> get channels {
    // Return channels in order, filtering out any stale IDs
    final ordered = <MixerChannel>[];
    for (final id in _channelOrder) {
      final channel = _channels[id];
      if (channel != null) {
        ordered.add(channel);
      }
    }
    // Add any channels not in order list (shouldn't happen, but defensive)
    for (final channel in _channels.values) {
      if (!_channelOrder.contains(channel.id)) {
        ordered.add(channel);
      }
    }
    return ordered;
  }

  /// Returns channel order as list of IDs
  List<String> get channelOrder => List.unmodifiable(_channelOrder);

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

  /// Channel count
  int get channelCount => _channels.length;

  /// Bus count
  int get busCount => _buses.length;

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANNEL REORDERING (Bidirectional sync with Timeline)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Reorder a channel from oldIndex to newIndex
  /// Called when user drags a fader in the mixer
  void reorderChannel(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _channelOrder.length) return;
    if (newIndex < 0 || newIndex >= _channelOrder.length) return;
    if (oldIndex == newIndex) return;

    final channelId = _channelOrder.removeAt(oldIndex);
    _channelOrder.insert(newIndex, channelId);

    // Notify timeline to sync track order
    onChannelOrderChanged?.call(List.unmodifiable(_channelOrder));

    notifyListeners();
  }

  /// Set channel order from external source (e.g., timeline track reorder)
  /// Called when user drags a track header in the timeline
  void setChannelOrder(List<String> newOrder, {bool notifyTimeline = false}) {
    // Validate all IDs exist
    final validOrder = newOrder.where((id) => _channels.containsKey(id)).toList();

    // Add any missing channels at the end
    for (final channel in _channels.values) {
      if (!validOrder.contains(channel.id)) {
        validOrder.add(channel.id);
      }
    }

    _channelOrder.clear();
    _channelOrder.addAll(validOrder);

    // Optionally notify timeline (used when order set programmatically)
    if (notifyTimeline) {
      onChannelOrderChanged?.call(List.unmodifiable(_channelOrder));
    }

    notifyListeners();
  }

  /// Get channel index in display order
  int getChannelIndex(String channelId) {
    return _channelOrder.indexOf(channelId);
  }

  /// Clear all solo states
  void clearAllSolo() {
    for (final id in List.from(_soloedChannels)) {
      setSoloed(id, false);
    }
  }

  /// Set pan for a channel (shorthand for setChannelPan)
  void setPan(String id, double pan) => setChannelPan(id, pan);

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
    // Skip meter updates when transport is stopped — let decay timer drain them
    // Rust engine still produces audio (one-shot voices, insert tails) after stop,
    // which would keep meters alive indefinitely if we kept reading them.
    if (!_isPlaying) return;

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

    // Update bus meters (buses use engine ID from _getBusEngineId)
    for (final bus in _buses.values) {
      final engineId = _getBusEngineId(bus.id);
      if (engineId < metering.buses.length) {
        final busMeter = metering.buses[engineId];
        _buses[bus.id] = bus.copyWith(
          peakL: _dbToLinear(busMeter.peakL),
          peakR: _dbToLinear(busMeter.peakR),
          rmsL: _dbToLinear(busMeter.rmsL),
          rmsR: _dbToLinear(busMeter.rmsR),
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
    // ✅ P0.3: Input validation
    final validationError = InputSanitizer.validateName(name);
    if (validationError != null) {
      throw ArgumentError('Invalid channel name: $validationError');
    }

    final sanitizedName = InputSanitizer.sanitizeName(name);
    final id = 'ch_${DateTime.now().millisecondsSinceEpoch}';
    final trackIndex = _nextTrackIndex++;

    // Create in engine
    final engineTrackId = NativeFFI.instance.createTrack(
      sanitizedName, // ✅ Use sanitized name
      (color ?? const Color(0xFF4A9EFF)).value,
      _getBusEngineId(outputBus ?? 'bus_sfx'),
    );

    final channel = MixerChannel(
      id: id,
      name: sanitizedName, // ✅ Use sanitized name
      type: ChannelType.audio,
      color: color ?? _getNextTrackColor(),
      outputBus: outputBus ?? 'bus_sfx',
      trackIndex: engineTrackId > 0 ? engineTrackId : trackIndex,
    );

    _channels[id] = channel;
    _channelOrder.add(id); // Maintain order list
    notifyListeners();
    return channel;
  }

  /// Create channel from timeline track creation
  /// trackId is the engine track ID (as string, but may be numeric for native tracks)
  /// channels: 1 = mono, 2 = stereo (affects default pan values)
  /// Cubase-style: track = mixer channel, direct to master
  MixerChannel createChannelFromTrack(
    String trackId,
    String trackName,
    Color trackColor, {
    int channels = 2,
  }) {
    // ✅ P0.3: Input validation
    final validationError = InputSanitizer.validateName(trackName);
    if (validationError != null) {
      throw ArgumentError('Invalid track name: $validationError');
    }

    final sanitizedName = InputSanitizer.sanitizeName(trackName);

    // Check if channel already exists for this track
    final existing = _channels.values.where((c) => c.id == 'ch_$trackId').firstOrNull;
    if (existing != null) return existing;

    final id = 'ch_$trackId';

    // Try to parse trackId as native engine ID (for FFI calls)
    // Native engine returns numeric IDs, mock returns 'track-123...' strings
    final nativeTrackId = int.tryParse(trackId);

    // Pro Tools dual-pan defaults: stereo = L hard left, R hard right
    // Mono = center
    final bool isStereo = channels >= 2;
    final defaultPan = isStereo ? -1.0 : 0.0;
    final defaultPanRight = isStereo ? 1.0 : 0.0;

    // Cubase-style: channels route directly to master (no intermediate buses)
    final channel = MixerChannel(
      id: id,
      name: sanitizedName, // ✅ Use sanitized name
      type: ChannelType.audio,
      color: trackColor,
      pan: defaultPan,
      panRight: defaultPanRight,
      isStereo: isStereo,
      outputBus: 'master', // Direct to master, not to bus
      trackIndex: nativeTrackId, // Store native engine track ID for FFI
    );

    _channels[id] = channel;
    _channelOrder.add(id); // Maintain order list
    notifyListeners();
    return channel;
  }

  /// Create channel from timeline at specific index (for ordered track creation)
  MixerChannel createChannelFromTrackAtIndex(
    String trackId,
    String trackName,
    Color trackColor,
    int index, {
    int channels = 2,
  }) {
    final channel = createChannelFromTrack(trackId, trackName, trackColor, channels: channels);

    // Move to correct position if not at end
    final currentIndex = _channelOrder.indexOf(channel.id);
    if (currentIndex != -1 && currentIndex != index && index < _channelOrder.length) {
      _channelOrder.removeAt(currentIndex);
      _channelOrder.insert(index.clamp(0, _channelOrder.length), channel.id);
      notifyListeners();
    }

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
    _channelOrder.remove(id); // Maintain order list
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

  /// Toggle channel phase invert (polarity flip)
  void togglePhaseInvert(String id) {
    final channel = _channels[id] ?? _buses[id];
    if (channel == null) return;

    channel.phaseInverted = !channel.phaseInverted;

    // Send to engine if track channel
    if (channel.trackIndex != null) {
      NativeFFI.instance.trackSetPhaseInvert(channel.trackIndex!, channel.phaseInverted);
    }

    notifyListeners();
  }

  /// Get channel phase invert state
  bool getPhaseInvert(String id) {
    final channel = _channels[id] ?? _buses[id];
    return channel?.phaseInverted ?? false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOLO SAFE (Phase 4 §4.2)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Toggle solo safe — channel excluded from SIP muting
  void toggleSoloSafe(String id) {
    final channel = _channels[id] ?? _buses[id];
    if (channel == null) return;
    channel.soloSafe = !channel.soloSafe;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMMENTS (Phase 4 §15.1)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set per-channel comments text
  void setChannelComments(String id, String comments) {
    final channel = _channels[id] ?? _buses[id];
    if (channel == null) return;
    channel.comments = comments;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FOLDER TRACKS (Phase 4 §18)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Toggle folder track expand/collapse
  void toggleFolderExpanded(String id) {
    final channel = _channels[id];
    if (channel == null || !channel.isFolder) return;
    channel.folderExpanded = !channel.folderExpanded;
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
    // ✅ P0.3: Input validation
    final validationError = InputSanitizer.validateName(name);
    if (validationError != null) {
      throw ArgumentError('Invalid bus name: $validationError');
    }

    // Sanitize name to be extra safe
    final sanitizedName = InputSanitizer.sanitizeName(name);

    final id = 'bus_${DateTime.now().millisecondsSinceEpoch}';

    final bus = MixerChannel(
      id: id,
      name: sanitizedName, // ✅ Use sanitized name
      type: ChannelType.bus,
      color: color ?? const Color(0xFF9B59B6),
      outputBus: outputBus ?? 'master',
      pan: -1.0,        // Stereo bus: L channel hard left
      panRight: 1.0,    // Stereo bus: R channel hard right
      isStereo: true,
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
    // No default buses in DAW mixer — all buses are user-created and deletable
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUX MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create an aux send/return
  MixerChannel createAux({
    required String name,
    Color? color,
  }) {
    // ✅ P0.3: Input validation
    final validationError = InputSanitizer.validateName(name);
    if (validationError != null) {
      throw ArgumentError('Invalid aux name: $validationError');
    }

    final sanitizedName = InputSanitizer.sanitizeName(name);
    final id = 'aux_${DateTime.now().millisecondsSinceEpoch}';

    final aux = MixerChannel(
      id: id,
      name: sanitizedName, // ✅ Use sanitized name
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

  /// Map group UI ID to engine ID
  final Map<String, int> _groupEngineIds = {};

  /// Create a group
  MixerGroup createGroup({required String name, Color? color}) {
    final id = 'grp_${DateTime.now().millisecondsSinceEpoch}';

    // Create in engine and store mapping
    final engineId = NativeFFI.instance.groupCreate(name);
    _groupEngineIds[id] = engineId;

    final group = MixerGroup(
      id: id,
      name: name,
      color: color ?? const Color(0xFF40FF90),
    );

    _groups[id] = group;

    // Set initial link states in engine
    _syncGroupToEngine(group, engineId);

    notifyListeners();
    return group;
  }

  /// Delete a group
  void deleteGroup(String id) {
    final group = _groups[id];
    if (group == null) return;

    // Delete from engine
    final engineId = _groupEngineIds[id];
    if (engineId != null) {
      NativeFFI.instance.groupDelete(engineId);
      _groupEngineIds.remove(id);
    }

    // Remove group assignment from channels
    for (final channel in _channels.values) {
      if (channel.groupId == id) {
        _channels[channel.id] = channel.copyWith(groupId: null);
      }
    }

    _groups.remove(id);
    notifyListeners();
  }

  /// Add a channel to a group
  void addChannelToGroup(String channelId, String groupId) {
    final group = _groups[groupId];
    final channel = _channels[channelId];
    if (group == null || channel == null) return;

    // Update channel
    _channels[channelId] = channel.copyWith(groupId: groupId);

    // Update group member list
    if (!group.memberIds.contains(channelId)) {
      group.memberIds = [...group.memberIds, channelId];
    }

    // Sync to engine
    final engineGroupId = _groupEngineIds[groupId];
    if (engineGroupId != null && channel.trackIndex != null) {
      NativeFFI.instance.groupAddTrack(engineGroupId, channel.trackIndex!);
    }

    notifyListeners();
  }

  /// Remove a channel from a group
  void removeChannelFromGroup(String channelId, String groupId) {
    final group = _groups[groupId];
    final channel = _channels[channelId];
    if (group == null || channel == null) return;

    // Update channel
    _channels[channelId] = channel.copyWith(groupId: null);

    // Update group member list
    group.memberIds = group.memberIds.where((id) => id != channelId).toList();

    // Sync to engine
    final engineGroupId = _groupEngineIds[groupId];
    if (engineGroupId != null && channel.trackIndex != null) {
      NativeFFI.instance.groupRemoveTrack(engineGroupId, channel.trackIndex!);
    }

    notifyListeners();
  }

  /// Set group link mode (relative/absolute)
  void setGroupLinkMode(String groupId, GroupLinkMode mode) {
    final group = _groups[groupId];
    if (group == null) return;

    group.linkMode = mode;

    // Sync to engine (0 = relative, 1 = absolute)
    final engineId = _groupEngineIds[groupId];
    if (engineId != null) {
      NativeFFI.instance.groupSetLinkMode(engineId, mode == GroupLinkMode.absolute ? 1 : 0);
    }

    notifyListeners();
  }

  /// Toggle link for a specific parameter
  void toggleGroupLink(String groupId, GroupLinkParameter param) {
    final group = _groups[groupId];
    if (group == null) return;

    switch (param) {
      case GroupLinkParameter.volume:
        group.linkVolume = !group.linkVolume;
        break;
      case GroupLinkParameter.pan:
        group.linkPan = !group.linkPan;
        break;
      case GroupLinkParameter.mute:
        group.linkMute = !group.linkMute;
        break;
      case GroupLinkParameter.solo:
        group.linkSolo = !group.linkSolo;
        break;
    }

    // Sync to engine
    final engineId = _groupEngineIds[groupId];
    if (engineId != null) {
      NativeFFI.instance.groupToggleLink(engineId, param.index);
    }

    notifyListeners();
  }

  /// Set group color
  void setGroupColor(String groupId, Color color) {
    final group = _groups[groupId];
    if (group == null) return;

    // Create new group with updated color
    _groups[groupId] = MixerGroup(
      id: group.id,
      name: group.name,
      color: color,
      linkMode: group.linkMode,
      linkVolume: group.linkVolume,
      linkPan: group.linkPan,
      linkMute: group.linkMute,
      linkSolo: group.linkSolo,
      memberIds: group.memberIds,
    );

    // Sync to engine (convert color to u32)
    final engineId = _groupEngineIds[groupId];
    if (engineId != null) {
      NativeFFI.instance.groupSetColor(engineId, color.value);
    }

    notifyListeners();
  }

  /// Get channels belonging to a group
  List<MixerChannel> getGroupMembers(String groupId) {
    final group = _groups[groupId];
    if (group == null) return [];

    return group.memberIds
        .map((id) => _channels[id])
        .whereType<MixerChannel>()
        .toList();
  }

  /// Propagate parameter change to all group members (called from setChannelXxx methods)
  void _propagateGroupParameter(String channelId, GroupLinkParameter param, double value) {
    final channel = _channels[channelId];
    if (channel == null || channel.groupId == null) return;

    final group = _groups[channel.groupId];
    if (group == null) return;

    // Check if parameter is linked
    bool isLinked = false;
    switch (param) {
      case GroupLinkParameter.volume:
        isLinked = group.linkVolume;
        break;
      case GroupLinkParameter.pan:
        isLinked = group.linkPan;
        break;
      case GroupLinkParameter.mute:
      case GroupLinkParameter.solo:
        isLinked = false; // Mute/solo handled separately
        break;
    }

    if (!isLinked) return;

    // Get original value for relative mode
    final originalValue = switch (param) {
      GroupLinkParameter.volume => channel.volume,
      GroupLinkParameter.pan => channel.pan,
      _ => 0.0,
    };

    final delta = value - originalValue;

    // Apply to all group members
    for (final memberId in group.memberIds) {
      if (memberId == channelId) continue; // Skip source channel

      final member = _channels[memberId];
      if (member == null) continue;

      double newValue;
      if (group.linkMode == GroupLinkMode.absolute) {
        newValue = value;
      } else {
        // Relative mode - add delta
        newValue = switch (param) {
          GroupLinkParameter.volume => (member.volume + delta).clamp(0.0, 1.5),
          GroupLinkParameter.pan => (member.pan + delta).clamp(-1.0, 1.0),
          _ => value,
        };
      }

      // Update member without recursion (direct update)
      switch (param) {
        case GroupLinkParameter.volume:
          _channels[memberId] = member.copyWith(volume: newValue);
          if (member.trackIndex != null) {
            engine.setTrackVolume(member.trackIndex!, newValue);
          }
          break;
        case GroupLinkParameter.pan:
          _channels[memberId] = member.copyWith(pan: newValue);
          if (member.trackIndex != null) {
            engine.setTrackPan(member.trackIndex!, newValue);
          }
          break;
        default:
          break;
      }
    }
  }

  /// Sync group state to engine
  void _syncGroupToEngine(MixerGroup group, int engineId) {
    // Set link mode
    NativeFFI.instance.groupSetLinkMode(
      engineId,
      group.linkMode == GroupLinkMode.absolute ? 1 : 0,
    );

    // Set linked parameters (engine tracks which params are linked)
    // Note: engine starts with all unlinked, toggle to enable
    if (group.linkVolume) {
      NativeFFI.instance.groupToggleLink(engineId, GroupLinkParameter.volume.index);
    }
    if (group.linkPan) {
      NativeFFI.instance.groupToggleLink(engineId, GroupLinkParameter.pan.index);
    }
    if (group.linkMute) {
      NativeFFI.instance.groupToggleLink(engineId, GroupLinkParameter.mute.index);
    }
    if (group.linkSolo) {
      NativeFFI.instance.groupToggleLink(engineId, GroupLinkParameter.solo.index);
    }

    // Set color
    NativeFFI.instance.groupSetColor(engineId, group.color.value);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UNDO MANAGER INTEGRATION (P10.0.4)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Undo manager singleton for mixer operations
  UiUndoManager get _undoManager => UiUndoManager.instance;

  /// Set channel volume WITH undo recording
  /// Use this for user-initiated volume changes (fader drag)
  void setChannelVolumeWithUndo(String id, double volume, {bool propagateGroup = true}) {
    final channel = _channels[id] ?? _buses[id] ?? _auxes[id];
    if (channel == null) return;

    final oldVolume = channel.volume;
    if ((oldVolume - volume).abs() < 0.001) return; // Skip trivial changes

    _undoManager.record(VolumeChangeAction(
      channelId: id,
      channelName: channel.name,
      oldVolume: oldVolume,
      newVolume: volume,
      applyVolume: (cId, vol) => setChannelVolume(cId, vol, propagateGroup: false),
    ));

    setChannelVolume(id, volume, propagateGroup: propagateGroup);
  }

  /// Set channel pan WITH undo recording
  /// Called on drag END — uses saved anchor as oldPan for correct undo
  void setChannelPanWithUndo(String id, double pan, {bool propagateGroup = true}) {
    final channel = _channels[id] ?? _buses[id] ?? _auxes[id];
    if (channel == null) return;

    // Use drag anchor (pre-drag value) if available, otherwise current
    final oldPan = _panDragAnchors.remove(id) ?? channel.pan;
    if ((oldPan - pan).abs() < 0.001) return;

    _undoManager.record(PanChangeAction(
      channelId: id,
      channelName: channel.name,
      oldPan: oldPan,
      newPan: pan,
      applyPan: (cId, p) => setChannelPan(cId, p, propagateGroup: false),
    ));

    // Pan is already applied during drag via setChannelPan(), no need to re-apply
  }

  /// Set channel pan right (stereo) WITH undo recording
  void setChannelPanRightWithUndo(String id, double panRight) {
    final channel = _channels[id] ?? _buses[id] ?? _auxes[id];
    if (channel == null) return;

    final oldPanRight = channel.panRight;
    if ((oldPanRight - panRight).abs() < 0.001) return;

    _undoManager.record(PanChangeAction(
      channelId: id,
      channelName: channel.name,
      oldPan: oldPanRight,
      newPan: panRight,
      applyPan: setChannelPanRight,
      isRightChannel: true,
    ));

    setChannelPanRight(id, panRight);
  }

  /// Toggle channel mute WITH undo recording
  void toggleChannelMuteWithUndo(String id) {
    final channel = _channels[id] ?? _buses[id] ?? _auxes[id];
    if (channel == null) return;

    _undoManager.record(MuteToggleAction(
      channelId: id,
      channelName: channel.name,
      wasMuted: channel.muted,
      applyMute: (cId, muted) {
        if (_channels.containsKey(cId)) {
          _channels[cId] = _channels[cId]!.copyWith(muted: muted);
          if (_channels[cId]!.trackIndex != null) {
            NativeFFI.instance.setTrackMute(_channels[cId]!.trackIndex!, muted);
          }
        } else if (_buses.containsKey(cId)) {
          _buses[cId] = _buses[cId]!.copyWith(muted: muted);
          NativeFFI.instance.mixerSetBusMute(_getBusEngineId(cId), muted);
        } else if (_auxes.containsKey(cId)) {
          _auxes[cId] = _auxes[cId]!.copyWith(muted: muted);
        }
        notifyListeners();
      },
    ));

    toggleChannelMute(id);
  }

  /// Toggle channel solo WITH undo recording
  void toggleChannelSoloWithUndo(String id) {
    final channel = _channels[id] ?? _buses[id] ?? _auxes[id];
    if (channel == null) return;

    _undoManager.record(SoloToggleAction(
      channelId: id,
      channelName: channel.name,
      wasSoloed: channel.soloed,
      applySolo: (cId, soloed) {
        if (soloed) {
          _soloedChannels.add(cId);
        } else {
          _soloedChannels.remove(cId);
        }
        if (_channels.containsKey(cId)) {
          _channels[cId] = _channels[cId]!.copyWith(soloed: soloed);
          if (_channels[cId]!.trackIndex != null) {
            NativeFFI.instance.setTrackSolo(_channels[cId]!.trackIndex!, soloed);
          }
        } else if (_buses.containsKey(cId)) {
          _buses[cId] = _buses[cId]!.copyWith(soloed: soloed);
          NativeFFI.instance.mixerSetBusSolo(_getBusEngineId(cId), soloed);
        } else if (_auxes.containsKey(cId)) {
          _auxes[cId] = _auxes[cId]!.copyWith(soloed: soloed);
        }
        notifyListeners();
      },
    ));

    toggleChannelSolo(id);
  }

  /// Set aux send level WITH undo recording
  void setAuxSendLevelWithUndo(String channelId, String auxId, double level) {
    final channel = _channels[channelId];
    if (channel == null) return;

    final existingSend = channel.sends.where((s) => s.auxId == auxId).firstOrNull;
    final oldLevel = existingSend?.level ?? 0.0;
    if ((oldLevel - level).abs() < 0.001) return;

    // Find send index for description
    final sendIndex = channel.sends.indexWhere((s) => s.auxId == auxId);

    _undoManager.record(SendLevelChangeAction(
      channelId: channelId,
      channelName: channel.name,
      sendId: auxId,
      sendIndex: sendIndex >= 0 ? sendIndex : channel.sends.length,
      oldLevel: oldLevel,
      newLevel: level,
      applyLevel: setAuxSendLevel,
    ));

    setAuxSendLevel(channelId, auxId, level);
  }

  /// Set channel output routing WITH undo recording
  void setChannelOutputWithUndo(String channelId, String busId) {
    final channel = _channels[channelId];
    if (channel == null) return;

    final oldBusId = channel.outputBus;
    if (oldBusId == busId) return;

    // Get bus names for description
    final oldBusName = _buses[oldBusId]?.name ?? oldBusId;
    final newBusName = _buses[busId]?.name ?? busId;

    _undoManager.record(RouteChangeAction(
      channelId: channelId,
      channelName: channel.name,
      oldBusId: oldBusId,
      newBusId: busId,
      oldBusName: oldBusName,
      newBusName: newBusName,
      applyRoute: (cId, bId) => setChannelOutput(cId, bId ?? 'master'),
    ));

    setChannelOutput(channelId, busId);
  }

  /// Load insert WITH undo recording
  void loadInsertWithUndo(String channelId, int slotIndex, String pluginId, String pluginName, String pluginType) {
    final channel = _channels[channelId];
    if (channel == null) return;

    _undoManager.record(InsertLoadAction(
      channelId: channelId,
      channelName: channel.name,
      slotIndex: slotIndex,
      processorName: pluginName,
      processorId: pluginId,
      processorType: pluginType,
      applyLoad: loadInsert,
      applyUnload: removeInsert,
    ));

    loadInsert(channelId, slotIndex, pluginId, pluginName, pluginType);
  }

  /// Remove insert WITH undo recording
  void removeInsertWithUndo(String channelId, int slotIndex) {
    final channel = _channels[channelId];
    if (channel == null) return;
    if (slotIndex < 0 || slotIndex >= channel.inserts.length) return;

    final insert = channel.inserts[slotIndex];
    if (insert.isEmpty) return; // Nothing to remove

    _undoManager.record(InsertUnloadAction(
      channelId: channelId,
      channelName: channel.name,
      slotIndex: slotIndex,
      processorName: insert.name,
      processorId: insert.id,
      processorType: insert.type,
      applyUnload: removeInsert,
      applyLoad: loadInsert,
    ));

    removeInsert(channelId, slotIndex);
  }

  /// Update insert bypass WITH undo recording
  void updateInsertBypassWithUndo(String channelId, int slotIndex, bool bypassed) {
    final channel = _channels[channelId];
    if (channel == null) return;
    if (slotIndex < 0 || slotIndex >= channel.inserts.length) return;

    final insert = channel.inserts[slotIndex];
    if (insert.isEmpty) return;
    if (insert.bypassed == bypassed) return;

    _undoManager.record(InsertBypassAction(
      channelId: channelId,
      channelName: channel.name,
      slotIndex: slotIndex,
      processorName: insert.name,
      wasBypassed: insert.bypassed,
      applyBypass: updateInsertBypass,
    ));

    updateInsertBypass(channelId, slotIndex, bypassed);
  }

  /// Set input gain WITH undo recording
  void setInputGainWithUndo(String channelId, double gain) {
    final channel = _channels[channelId];
    if (channel == null) return;

    final oldGain = channel.inputGain;
    if ((oldGain - gain).abs() < 0.01) return;

    _undoManager.record(InputGainChangeAction(
      channelId: channelId,
      channelName: channel.name,
      oldGain: oldGain,
      newGain: gain,
      applyGain: setInputGain,
    ));

    setInputGain(channelId, gain);
  }

  /// Set master volume WITH undo recording
  void setMasterVolumeWithUndo(double volume) {
    final oldVolume = _master.volume;
    if ((oldVolume - volume).abs() < 0.001) return;

    _undoManager.record(VolumeChangeAction(
      channelId: _master.id,
      channelName: 'Master',
      oldVolume: oldVolume,
      newVolume: volume,
      applyVolume: (_, vol) => setMasterVolume(vol),
    ));

    setMasterVolume(volume);
  }

  /// Set VCA level WITH undo recording
  void setVcaLevelWithUndo(String id, double level) {
    final vca = _vcas[id];
    if (vca == null) return;

    final oldLevel = vca.level;
    if ((oldLevel - level).abs() < 0.001) return;

    _undoManager.record(VolumeChangeAction(
      channelId: id,
      channelName: vca.name,
      oldVolume: oldLevel,
      newVolume: level,
      applyVolume: (cId, vol) => setVcaLevel(cId, vol),
    ));

    setVcaLevel(id, level);
  }

  /// Toggle solo safe WITH undo recording (Phase 4 §4.2)
  void toggleSoloSafeWithUndo(String id) {
    final channel = _channels[id] ?? _buses[id];
    if (channel == null) return;

    _undoManager.record(SoloSafeToggleAction(
      channelId: id,
      channelName: channel.name,
      wasSoloSafe: channel.soloSafe,
      applySoloSafe: (cId, val) {
        final ch = _channels[cId] ?? _buses[cId];
        if (ch != null) {
          ch.soloSafe = val;
          notifyListeners();
        }
      },
    ));

    toggleSoloSafe(id);
  }

  /// Set channel comments WITH undo recording (Phase 4 §15.1)
  void setChannelCommentsWithUndo(String id, String comments) {
    final channel = _channels[id] ?? _buses[id];
    if (channel == null) return;

    final oldComments = channel.comments;
    if (oldComments == comments) return;

    _undoManager.record(CommentsChangeAction(
      channelId: id,
      channelName: channel.name,
      oldComments: oldComments,
      newComments: comments,
      applyComments: (cId, val) => setChannelComments(cId, val),
    ));

    setChannelComments(id, comments);
  }

  /// Toggle folder expand/collapse WITH undo recording (Phase 4 §18)
  void toggleFolderExpandedWithUndo(String id) {
    final channel = _channels[id];
    if (channel == null || !channel.isFolder) return;

    _undoManager.record(FolderToggleAction(
      channelId: id,
      channelName: channel.name,
      wasExpanded: channel.folderExpanded,
      applyFolder: (cId, val) {
        final ch = _channels[cId];
        if (ch != null) {
          ch.folderExpanded = val;
          notifyListeners();
        }
      },
    ));

    toggleFolderExpanded(id);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANNEL CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  void setChannelVolume(String id, double volume, {bool propagateGroup = true}) {
    final channel = _channels[id] ?? _buses[id] ?? _auxes[id];
    if (channel == null) return;

    // ✅ P0.3: FFI bounds checking (NaN/Infinite protection)
    if (!FFIBoundsChecker.validateVolume(volume)) {
      return; // Abort instead of crashing
    }

    final clampedVolume = FFIBoundsChecker.clampVolume(volume);

    // Propagate to group members first (before updating this channel)
    if (propagateGroup && _channels.containsKey(id)) {
      _propagateGroupParameter(id, GroupLinkParameter.volume, clampedVolume);
    }

    if (_channels.containsKey(id)) {
      _channels[id] = channel.copyWith(volume: clampedVolume);
      if (channel.trackIndex != null) {
        // ✅ Validate track ID before FFI call
        if (FFIBoundsChecker.validateTrackId(channel.trackIndex!)) {
          engine.setTrackVolume(channel.trackIndex!, clampedVolume);
        } else {
        }
      }
    } else if (_buses.containsKey(id)) {
      _buses[id] = channel.copyWith(volume: clampedVolume);
      final busId = _getBusEngineId(id);
      if (FFIBoundsChecker.validateBusId(busId)) {
        engine.setBusVolume(busId, clampedVolume);
      }
    } else if (_auxes.containsKey(id)) {
      _auxes[id] = channel.copyWith(volume: clampedVolume);
    }

    notifyListeners();
  }

  void setChannelPan(String id, double pan, {bool propagateGroup = true}) {
    final channel = _channels[id] ?? _buses[id] ?? _auxes[id];
    if (channel == null) return;

    // Save pre-drag anchor for undo (first call in a drag gesture)
    if (!_panDragAnchors.containsKey(id)) {
      _panDragAnchors[id] = channel.pan;
    }

    // ✅ P0.3: FFI bounds checking (NaN/Infinite protection)
    if (!FFIBoundsChecker.validatePan(pan)) {
      return;
    }

    final clampedPan = FFIBoundsChecker.clampPan(pan);

    // Propagate to group members first (before updating this channel)
    if (propagateGroup && _channels.containsKey(id)) {
      _propagateGroupParameter(id, GroupLinkParameter.pan, clampedPan);
    }

    if (_channels.containsKey(id)) {
      _channels[id] = channel.copyWith(pan: clampedPan);
      if (channel.trackIndex != null) {
        // ✅ Validate track ID before FFI call
        if (FFIBoundsChecker.validateTrackId(channel.trackIndex!)) {
          engine.setTrackPan(channel.trackIndex!, clampedPan);
        } else {
        }
      }
    } else if (_buses.containsKey(id)) {
      _buses[id] = channel.copyWith(pan: clampedPan);
      final busId = _getBusEngineId(id);
      if (FFIBoundsChecker.validateBusId(busId)) {
        engine.setBusPan(busId, clampedPan);
      }
    } else if (_auxes.containsKey(id)) {
      _auxes[id] = channel.copyWith(pan: clampedPan);
    }

    notifyListeners();
  }

  void setChannelPanRight(String id, double panRight) {
    final channel = _channels[id] ?? _buses[id] ?? _auxes[id];
    if (channel == null) return;

    final clampedPan = panRight.clamp(-1.0, 1.0);

    if (_channels.containsKey(id)) {
      _channels[id] = channel.copyWith(panRight: clampedPan);
      // Send to engine for stereo dual-pan processing
      if (channel.trackIndex != null) {
        engine.setTrackPanRight(channel.trackIndex!, clampedPan);
      }
    } else if (_buses.containsKey(id)) {
      _buses[id] = channel.copyWith(panRight: clampedPan);
    } else if (_auxes.containsKey(id)) {
      _auxes[id] = channel.copyWith(panRight: clampedPan);
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

    final newArmed = !channel.armed;
    _channels[id] = channel.copyWith(armed: newArmed);

    // Sync with recording system via FFI
    final trackId = int.tryParse(id) ?? 0;
    if (newArmed) {
      recordingArmTrack(trackId);
    } else {
      recordingDisarmTrack(trackId);
    }

    notifyListeners();
  }

  void setChannelOutput(String channelId, String busId) {
    final channel = _channels[channelId];
    if (channel == null) return;

    _channels[channelId] = channel.copyWith(outputBus: busId);
    notifyListeners();
  }

  void setChannelInput(String channelId, String input) {
    final channel = _channels[channelId];
    if (channel == null) return;

    _channels[channelId] = channel.copyWith(inputSource: input);
    notifyListeners();
  }

  /// Update channel color (syncs with track header color)
  void updateChannelColor(String trackId, Color color) {
    final channelId = 'ch_$trackId';
    final channel = _channels[channelId];
    if (channel == null) return;

    _channels[channelId] = channel.copyWith(color: color);
    notifyListeners();
  }

  /// Alias for toggleChannelArm
  void toggleArm(String id) => toggleChannelArm(id);

  void toggleInputMonitor(String id) {
    final channel = _channels[id];
    if (channel == null) return;

    final newMonitorState = !channel.monitorInput;
    _channels[id] = channel.copyWith(monitorInput: newMonitorState);

    // Send to engine if track channel
    if (channel.trackIndex != null) {
      NativeFFI.instance.trackSetInputMonitor(channel.trackIndex!, newMonitorState);
    }

    notifyListeners();
  }

  /// Set channel muted state directly (for sync with track header)
  void setMuted(String id, bool muted) {
    final channel = _channels[id] ?? _buses[id];
    if (channel == null) return;

    channel.muted = muted;

    // Send to engine if track channel
    if (channel.trackIndex != null) {
      NativeFFI.instance.setTrackMute(channel.trackIndex!, muted);
    }

    notifyListeners();
  }

  /// Set channel soloed state directly (for sync with track header)
  void setSoloed(String id, bool soloed) {
    final channel = _channels[id] ?? _buses[id];
    if (channel == null) return;

    channel.soloed = soloed;

    if (soloed) {
      _soloedChannels.add(id);
    } else {
      _soloedChannels.remove(id);
    }

    // Send to engine if track channel
    if (channel.trackIndex != null) {
      NativeFFI.instance.setTrackSolo(channel.trackIndex!, soloed);
    }

    notifyListeners();
  }

  /// Set channel armed state directly (for sync with track header)
  void setArmed(String id, bool armed) {
    final channel = _channels[id];
    if (channel == null) return;

    _channels[id] = channel.copyWith(armed: armed);
    notifyListeners();
  }

  /// Set channel input monitor state directly (for sync with track header)
  void setInputMonitor(String id, bool monitor) {
    final channel = _channels[id];
    if (channel == null) return;

    _channels[id] = channel.copyWith(monitorInput: monitor);
    notifyListeners();

    // Send to engine FFI
    if (channel.trackIndex != null) {
      NativeFFI.instance.trackSetInputMonitor(channel.trackIndex!, monitor);
    }
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

  void toggleVcaSolo(String id) {
    final vca = _vcas[id];
    if (vca == null) return;

    final newSoloed = !vca.soloed;
    _vcas[id] = vca.copyWith(soloed: newSoloed);

    final engineId = int.tryParse(id.replaceAll('vca_', '')) ?? 0;
    NativeFFI.instance.vcaSetSolo(engineId, newSoloed);

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

  /// Toggle aux send enabled state
  void toggleAuxSendEnabled(String channelId, String auxId) {
    final channel = _channels[channelId];
    if (channel == null) return;

    final sends = List<AuxSend>.from(channel.sends);
    final existingIndex = sends.indexWhere((s) => s.auxId == auxId);

    if (existingIndex >= 0) {
      final current = sends[existingIndex];
      sends[existingIndex] = current.copyWith(enabled: !current.enabled);
      _channels[channelId] = channel.copyWith(sends: sends);
      notifyListeners();
    }
  }

  /// Toggle aux send pre/post fader
  void toggleAuxSendPreFader(String channelId, String auxId) {
    final channel = _channels[channelId];
    if (channel == null) return;

    final sends = List<AuxSend>.from(channel.sends);
    final existingIndex = sends.indexWhere((s) => s.auxId == auxId);

    if (existingIndex >= 0) {
      final current = sends[existingIndex];
      sends[existingIndex] = current.copyWith(preFader: !current.preFader);
      _channels[channelId] = channel.copyWith(sends: sends);
      notifyListeners();
    }
  }

  /// Set aux send destination (change which aux bus it routes to)
  void setAuxSendDestination(String channelId, int sendIndex, String newAuxId) {
    final channel = _channels[channelId];
    if (channel == null) return;
    if (sendIndex < 0 || sendIndex >= channel.sends.length) return;

    final sends = List<AuxSend>.from(channel.sends);
    final current = sends[sendIndex];
    sends[sendIndex] = AuxSend(
      auxId: newAuxId,
      level: current.level,
      preFader: current.preFader,
      enabled: current.enabled,
    );
    _channels[channelId] = channel.copyWith(sends: sends);
    notifyListeners();
  }

  /// Set input gain (trim) for a channel
  void setInputGain(String channelId, double gain) {
    final channel = _channels[channelId];
    if (channel == null) return;

    // Clamp gain to reasonable range (-20dB to +20dB)
    final clampedGain = gain.clamp(-20.0, 20.0);

    _channels[channelId] = channel.copyWith(inputGain: clampedGain);
    notifyListeners();

    // Send to engine FFI (expects dB value)
    if (channel.trackIndex != null) {
      NativeFFI.instance.channelStripSetInputGain(channel.trackIndex!, clampedGain);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INSERT MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update insert bypass state
  void updateInsertBypass(String channelId, int slotIndex, bool bypassed) {
    final channel = _channels[channelId];
    if (channel == null) return;
    if (slotIndex < 0 || slotIndex >= channel.inserts.length) return;

    // Get track ID for FFI
    final trackId = int.tryParse(channelId.replaceAll('ch_', '')) ?? 0;

    // Send bypass state to Rust engine
    NativeFFI.instance.insertSetBypass(trackId, slotIndex, bypassed);

    // Update UI state
    final inserts = List<InsertSlot>.from(channel.inserts);
    inserts[slotIndex] = inserts[slotIndex].copyWith(bypassed: bypassed);
    _channels[channelId] = channel.copyWith(inserts: inserts);
    notifyListeners();
  }

  /// Update insert wet/dry mix
  void updateInsertWetDry(String channelId, int slotIndex, double wetDry) {
    final channel = _channels[channelId];
    if (channel == null) return;
    if (slotIndex < 0 || slotIndex >= channel.inserts.length) return;

    // Get track ID for FFI
    final trackId = int.tryParse(channelId.replaceAll('ch_', '')) ?? 0;

    // Send wet/dry mix to Rust engine
    final clampedMix = wetDry.clamp(0.0, 1.0);
    NativeFFI.instance.insertSetMix(trackId, slotIndex, clampedMix);

    // Update UI state
    final inserts = List<InsertSlot>.from(channel.inserts);
    inserts[slotIndex] = inserts[slotIndex].copyWith(wetDry: clampedMix);
    _channels[channelId] = channel.copyWith(inserts: inserts);
    notifyListeners();
  }

  /// Remove insert (replace with empty slot)
  void removeInsert(String channelId, int slotIndex) {
    final channel = _channels[channelId];
    if (channel == null) return;
    if (slotIndex < 0 || slotIndex >= channel.inserts.length) return;

    // Get track ID for FFI
    final trackId = int.tryParse(channelId.replaceAll('ch_', '')) ?? 0;

    // Unload processor from Rust engine
    NativeFFI.instance.insertUnloadSlot(trackId, slotIndex);

    // Update UI state
    final inserts = List<InsertSlot>.from(channel.inserts);
    final isPreFader = slotIndex < 4;
    inserts[slotIndex] = InsertSlot.empty(slotIndex, isPreFader: isPreFader);
    _channels[channelId] = channel.copyWith(inserts: inserts);
    notifyListeners();
  }

  /// Load plugin into insert slot
  /// This connects to the Rust engine via FFI to actually process audio
  void loadInsert(String channelId, int slotIndex, String pluginId, String pluginName, String pluginType) {
    final channel = _channels[channelId];
    if (channel == null) return;
    if (slotIndex < 0 || slotIndex >= channel.inserts.length) return;

    // Get track ID for FFI (strip 'ch_' prefix if present)
    final trackId = int.tryParse(channelId.replaceAll('ch_', '')) ?? 0;

    // Map plugin ID to Rust processor name
    final processorName = _pluginIdToProcessorName(pluginId);
    if (processorName == null) {
      return;
    }

    // Create insert chain if needed (idempotent in Rust)
    NativeFFI.instance.insertCreateChain(trackId);

    // Load processor into the slot
    final result = NativeFFI.instance.insertLoadProcessor(trackId, slotIndex, processorName);
    if (result < 0) {
      return;
    }


    // Update UI state
    final inserts = List<InsertSlot>.from(channel.inserts);
    final isPreFader = slotIndex < 4;
    inserts[slotIndex] = InsertSlot(
      id: pluginId,
      name: pluginName,
      type: pluginType,
      isPreFader: isPreFader,
      bypassed: false,
      wetDry: 1.0,
    );
    _channels[channelId] = channel.copyWith(inserts: inserts);
    notifyListeners();
  }

  /// Map plugin ID to Rust processor name
  /// Must match create_processor() in dsp_wrappers.rs
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

  /// Reorder inserts within same section (pre or post fader)
  void reorderInserts(String channelId, int oldIndex, int newIndex) {
    final channel = _channels[channelId];
    if (channel == null) return;

    // Ensure both indices are in same section (0-3 pre, 4-7 post)
    final oldSection = oldIndex < 4 ? 0 : 1;
    final newSection = newIndex < 4 ? 0 : 1;
    if (oldSection != newSection) return;

    final inserts = List<InsertSlot>.from(channel.inserts);
    final item = inserts.removeAt(oldIndex);
    inserts.insert(newIndex, item);
    _channels[channelId] = channel.copyWith(inserts: inserts);
    notifyListeners();
  }

  /// Get inserts for a channel
  List<InsertSlot> getInserts(String channelId) {
    final channel = _channels[channelId];
    return channel?.inserts ?? [];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Map bus ID to engine bus index
  /// Engine buses: 0=Master, 1=Music, 2=Sfx, 3=Voice, 4=Ambience, 5=Aux
  /// MUST match Rust playback.rs bus processing loop (lines 3313-3319)
  int _getBusEngineId(String busId) {
    switch (busId) {
      case 'master': return 0;
      case 'bus_music': return 1;
      case 'bus_sfx': return 2;
      case 'bus_vo': return 3;
      case 'bus_ambient': return 4;
      case 'bus_aux': return 5;
      case 'bus_ui': return 2; // UI sounds route to SFX bus
      default: return 2; // Default to SFX
    }
  }

  /// Convert linear gain to dB
  double linearToDb(double linear) {
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
    DspChainProvider.instance.removeListener(_syncFromDspChainProvider);
    super.dispose();
  }
}
