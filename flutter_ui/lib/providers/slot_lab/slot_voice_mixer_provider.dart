// SlotLab Voice Mixer Provider
//
// Per-layer mixer for SlotLab — every audio layer assigned to a composite
// event becomes a permanent mixer channel. Channels auto-create on audio
// assignment, auto-remove on layer deletion.
//
// Architecture:
// - Source of truth: CompositeEventSystemProvider.compositeEvents
// - Real-time voice control: AudioPlaybackService (setVoiceVolume/Pan/Mute)
// - Parameter persistence: CompositeEventSystemProvider._updateEventLayerInternal
// - Metering: SharedMeterReader (bus-level, approximated per voice)
//
// CRITICAL: This is a SLOTLAB-ONLY mixer. Does NOT touch DAW MixerProvider.
// Shared only: MixerDSPProvider (bus control) + SharedMeterReader (metering).

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../../models/slot_audio_events.dart';
import '../../services/audio_playback_service.dart';
import '../../services/shared_meter_reader.dart';
import '../subsystems/composite_event_system_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SLOT MIXER CHANNEL — one per SlotEventLayer with actionType == 'Play'
// ═══════════════════════════════════════════════════════════════════════════

class SlotMixerChannel {
  /// Layer identity (from SlotEventLayer)
  final String layerId;
  final String eventId;
  final String stageName;

  /// Display
  final String displayName;
  final String audioPath;
  final int busId;
  final bool isLooping;
  final bool isStereo;
  final String actionType;

  /// Controllable params — synced bidirectionally with SlotEventLayer
  double volume;
  double pan;
  double panRight; // stereo dual-pan R channel
  bool muted;

  /// Per-layer DSP chain (from SlotEventLayer.dspChain)
  final List<({String id, String name, bool bypass})> dspInserts;

  /// Solo is LOCAL only — not persisted to SlotEventLayer.
  /// Used for real-time audition during mixing.
  bool soloed;

  /// Real-time state — updated from AudioPlaybackService active voices
  bool isPlaying;
  int? activeVoiceId;

  /// Metering — approximate per-voice from bus peaks
  double peakL;
  double peakR;
  double peakHoldL;
  double peakHoldR;
  int _peakHoldTimeL;
  int _peakHoldTimeR;

  SlotMixerChannel({
    required this.layerId,
    required this.eventId,
    required this.stageName,
    required this.displayName,
    required this.audioPath,
    required this.busId,
    required this.isLooping,
    required this.isStereo,
    required this.actionType,
    required this.volume,
    required this.pan,
    required this.panRight,
    required this.muted,
    this.dspInserts = const [],
    this.soloed = false,
    this.isPlaying = false,
    this.activeVoiceId,
    this.peakL = 0.0,
    this.peakR = 0.0,
    this.peakHoldL = 0.0,
    this.peakHoldR = 0.0,
  })  : _peakHoldTimeL = 0,
        _peakHoldTimeR = 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// BUS INFO — cached for display
// ═══════════════════════════════════════════════════════════════════════════

/// Map busId to human-readable name
String busIdToName(int busId) {
  return switch (busId) {
    SlotBusIds.master => 'Master',
    SlotBusIds.music => 'Music',
    SlotBusIds.sfx => 'SFX',
    SlotBusIds.voice => 'Voice',
    SlotBusIds.ui => 'UI',
    SlotBusIds.reels => 'Reels',
    SlotBusIds.wins => 'Wins',
    SlotBusIds.anticipation => 'Anticip',
    _ => 'SFX',
  };
}

/// Map SlotBusIds → SharedMeterReader channel index
/// SharedMeterReader channels: 0=SFX, 1=Music, 2=Voice, 3=Ambience, 4=Aux, 5=Master
/// SlotBusIds: master=0, music=1, sfx=2, voice=3, ui=4, reels=5, wins=6, anticipation=7
int _busIdToMeterChannel(int busId) {
  return switch (busId) {
    SlotBusIds.master => 5,
    SlotBusIds.music => 1,
    SlotBusIds.sfx => 0,
    SlotBusIds.voice => 2,
    SlotBusIds.ui => 4, // UI → Aux meter channel
    SlotBusIds.reels => 0, // sub-bus of SFX
    SlotBusIds.wins => 0, // sub-bus of SFX
    SlotBusIds.anticipation => 0, // sub-bus of SFX
    _ => 0,
  };
}

/// Parse display name from audio path
/// "/path/to/sfx_reel_stop_01.wav" → "Reel Stop 01"
String _parseDisplayName(String audioPath, String layerName) {
  // Prefer layer name if meaningful (not auto-generated)
  if (layerName.isNotEmpty &&
      !layerName.startsWith('layer_') &&
      !layerName.startsWith('ffnc_layer_')) {
    return layerName;
  }

  // Parse from filename
  final filename = audioPath.split('/').last;
  final noExt = filename.contains('.') ? filename.substring(0, filename.lastIndexOf('.')) : filename;

  // Remove common prefixes (sfx_, mus_, amb_, trn_, ui_, vo_)
  String cleaned = noExt;
  for (final prefix in ['sfx_', 'mus_', 'amb_', 'trn_', 'ui_', 'vo_']) {
    if (cleaned.toLowerCase().startsWith(prefix)) {
      cleaned = cleaned.substring(prefix.length);
      break;
    }
  }

  // Convert underscores to spaces, capitalize words, filter empty segments
  return cleaned
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// Parse stage name from composite event ID
/// "audio_REEL_STOP_0" → "REEL_STOP_0"
String _parseStage(String eventId) {
  if (eventId.startsWith('audio_')) return eventId.substring(6);
  return eventId;
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

class SlotVoiceMixerProvider extends ChangeNotifier {
  final CompositeEventSystemProvider _compositeProvider;

  /// Channels sorted by busId, then by eventId, then by layerId
  List<SlotMixerChannel> _channels = [];

  /// Cached bus grouping — rebuilt only when channels change, not on every getter call
  Map<int, List<SlotMixerChannel>> _channelsByBusCache = {};

  /// Ticker for metering and voice mapping (30fps)
  Ticker? _ticker;

  /// Metering state
  bool _meterInitialized = false;

  /// Peak hold constants
  static const int _peakHoldMs = 1500;
  static const double _peakDecayRate = 0.02;

  /// Solo state cache — true if any channel is soloed
  bool _hasSoloActive = false;

  // ─── Constructor ─────────────────────────────────────────────────────────

  SlotVoiceMixerProvider({
    required CompositeEventSystemProvider compositeProvider,
  }) : _compositeProvider = compositeProvider {
    // Listen to composite event changes → rebuild channels
    _compositeProvider.addListener(_onCompositeChanged);

    // Initial build
    _rebuildChannels();

    // Init metering
    _initMetering();
  }

  @override
  void dispose() {
    _compositeProvider.removeListener(_onCompositeChanged);
    _ticker?.dispose();
    super.dispose();
  }

  // ─── Getters ─────────────────────────────────────────────────────────────

  List<SlotMixerChannel> get channels => _channels;
  bool get hasSoloActive => _hasSoloActive;
  int get channelCount => _channels.length;
  int get playingCount => _channels.where((c) => c.isPlaying).length;

  /// Get channels grouped by busId (cached — rebuilt on channel change only)
  Map<int, List<SlotMixerChannel>> get channelsByBus => _channelsByBusCache;

  /// Bus display order — matches SlotLab convention
  static const List<int> busDisplayOrder = [
    SlotBusIds.sfx,
    SlotBusIds.reels,
    SlotBusIds.wins,
    SlotBusIds.anticipation,
    SlotBusIds.music,
    SlotBusIds.voice,
    SlotBusIds.ui,
  ];

  // ─── Metering Init ───────────────────────────────────────────────────────

  Future<void> _initMetering() async {
    final success = await SharedMeterReader.instance.initialize();
    _meterInitialized = success;
  }

  /// Start metering ticker — call from widget's initState with TickerProvider
  void startMetering(TickerProvider vsync) {
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onMeterTick)..start();
  }

  /// Stop metering ticker — call from widget's dispose
  void stopMetering() {
    _ticker?.dispose();
    _ticker = null;
  }

  // ─── Channel Rebuild (from composite events) ────────────────────────────

  void _onCompositeChanged() {
    _rebuildChannels();
  }

  void _rebuildChannels() {
    final compositeEvents = _compositeProvider.compositeEvents;
    final newChannelMap = <String, SlotMixerChannel>{};

    for (final event in compositeEvents) {
      for (final layer in event.layers) {
        // Only "Play" action layers get a mixer strip.
        // "Stop", "FadeOut", "SetVolume" etc. are control actions, not sounds.
        if (layer.actionType != 'Play') continue;

        // Skip layers without audio path (shouldn't happen but defensive)
        if (layer.audioPath.isEmpty) continue;

        final key = layer.id;

        // Preserve existing channel state (solo, metering) if layer already exists
        SlotMixerChannel? existing;
        for (final c in _channels) {
          if (c.layerId == key) { existing = c; break; }
        }

        newChannelMap[key] = SlotMixerChannel(
          layerId: layer.id,
          eventId: event.id,
          stageName: _parseStage(event.id),
          displayName: _parseDisplayName(layer.audioPath, layer.name),
          audioPath: layer.audioPath,
          busId: layer.busId ?? SlotBusIds.sfx,
          isLooping: layer.loop,
          isStereo: _isStereoBus(layer.busId ?? SlotBusIds.sfx),
          actionType: layer.actionType,
          // Params from layer (source of truth)
          volume: layer.volume,
          pan: layer.pan,
          panRight: layer.panRight,
          muted: layer.muted,
          // DSP chain from layer
          dspInserts: layer.dspChain
              .map((n) => (id: n.id, name: n.type.shortName, bypass: n.bypass))
              .toList(),
          // Preserve local-only state
          soloed: existing?.soloed ?? false,
          // Preserve real-time state (will be re-evaluated in next tick)
          isPlaying: existing?.isPlaying ?? false,
          activeVoiceId: existing?.activeVoiceId,
          peakL: existing?.peakL ?? 0.0,
          peakR: existing?.peakR ?? 0.0,
          peakHoldL: existing?.peakHoldL ?? 0.0,
          peakHoldR: existing?.peakHoldR ?? 0.0,
        );
      }
    }

    // Sort: by bus display order, then by stage name, then by layer id
    final sorted = newChannelMap.values.toList()
      ..sort((a, b) {
        final busOrderA = busDisplayOrder.indexOf(a.busId);
        final busOrderB = busDisplayOrder.indexOf(b.busId);
        final busA = busOrderA >= 0 ? busOrderA : 999;
        final busB = busOrderB >= 0 ? busOrderB : 999;
        if (busA != busB) return busA.compareTo(busB);
        final stageComp = a.stageName.compareTo(b.stageName);
        if (stageComp != 0) return stageComp;
        return a.layerId.compareTo(b.layerId);
      });

    _channels = sorted;
    _hasSoloActive = _channels.any((c) => c.soloed);

    // Rebuild bus grouping cache
    _channelsByBusCache = {};
    for (final ch in _channels) {
      _channelsByBusCache.putIfAbsent(ch.busId, () => []).add(ch);
    }

    notifyListeners();
  }

  /// Music bus is stereo by default (dual-pan L=-1, R=+1)
  bool _isStereoBus(int busId) {
    return busId == SlotBusIds.music;
  }

  // ─── Metering Tick (30fps) ──────────────────────────────────────────────

  void _onMeterTick(Duration elapsed) {
    if (_channels.isEmpty) return;

    bool changed = false;

    // 1. Map active voices → channels
    final activeVoices = AudioPlaybackService.instance.activeVoices;

    for (final ch in _channels) {
      final wasPlaying = ch.isPlaying;
      VoiceInfo? matchedVoice;
      for (final v in activeVoices) {
        if (v.layerId == ch.layerId) { matchedVoice = v; break; }
      }

      ch.isPlaying = matchedVoice != null;
      ch.activeVoiceId = matchedVoice?.voiceId;

      if (wasPlaying != ch.isPlaying) changed = true;
    }

    // 2. Approximate per-voice metering from bus peaks
    if (_meterInitialized && SharedMeterReader.instance.hasChanged) {
      final snapshot = SharedMeterReader.instance.readMeters();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Calculate total playing volume per bus (for proportional split)
      final busPlayingVolume = <int, double>{};
      for (final ch in _channels) {
        if (ch.isPlaying) {
          busPlayingVolume[ch.busId] =
              (busPlayingVolume[ch.busId] ?? 0.0) + ch.volume;
        }
      }

      for (final ch in _channels) {
        if (ch.isPlaying) {
          final meterCh = _busIdToMeterChannel(ch.busId);
          final leftIdx = meterCh * 2;
          final rightIdx = leftIdx + 1;

          if (leftIdx < snapshot.channelPeaks.length) {
            final busPeakL = snapshot.channelPeaks[leftIdx].clamp(0.0, 1.0);
            final busPeakR = rightIdx < snapshot.channelPeaks.length
                ? snapshot.channelPeaks[rightIdx].clamp(0.0, 1.0)
                : busPeakL;

            // Proportional split: voice peak ≈ bus peak × (voice volume / total bus volume)
            final totalVol = busPlayingVolume[ch.busId] ?? 1.0;
            final ratio = totalVol > 0.001 ? (ch.volume / totalVol).clamp(0.0, 1.0) : 0.0;

            ch.peakL = busPeakL * ratio;
            ch.peakR = busPeakR * ratio;

            // Peak hold L
            if (ch.peakL >= ch.peakHoldL) {
              ch.peakHoldL = ch.peakL;
              ch._peakHoldTimeL = now;
            }
            // Peak hold R
            if (ch.peakR >= ch.peakHoldR) {
              ch.peakHoldR = ch.peakR;
              ch._peakHoldTimeR = now;
            }

            changed = true;
          }
        } else {
          // Not playing — gradual meter decay (smooth visual transition)
          if (ch.peakL > 0.001) {
            ch.peakL *= 0.85; // ~100ms decay to zero at 30fps
            if (ch.peakL < 0.001) ch.peakL = 0.0;
            changed = true;
          }
          if (ch.peakR > 0.001) {
            ch.peakR *= 0.85;
            if (ch.peakR < 0.001) ch.peakR = 0.0;
            changed = true;
          }
        }
      }

      // Peak hold decay
      if (_decayPeakHold(now)) changed = true;
    } else {
      // No new meter data — still decay peak hold
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_decayPeakHold(now)) changed = true;
    }

    if (changed) notifyListeners();
  }

  bool _decayPeakHold(int now) {
    bool changed = false;
    for (final ch in _channels) {
      // L
      if (now - ch._peakHoldTimeL > _peakHoldMs && ch.peakHoldL > 0) {
        ch.peakHoldL = (ch.peakHoldL - _peakDecayRate).clamp(0.0, 1.0);
        if (ch.peakHoldL <= 0) ch._peakHoldTimeL = 0;
        changed = true;
      }
      // R
      if (now - ch._peakHoldTimeR > _peakHoldMs && ch.peakHoldR > 0) {
        ch.peakHoldR = (ch.peakHoldR - _peakDecayRate).clamp(0.0, 1.0);
        if (ch.peakHoldR <= 0) ch._peakHoldTimeR = 0;
        changed = true;
      }
    }
    return changed;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANNEL CONTROL — bidirectional sync with CompositeEventSystemProvider
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set channel volume (continuous — no undo, for fader drag)
  /// Updates: local state + composite event layer + active voice real-time FFI
  /// Note: SlotEventLayer.volume range is 0.0-1.0 (enforced by setLayerVolumeContinuous)
  void setChannelVolume(String layerId, double volume) {
    final ch = _findChannel(layerId);
    if (ch == null) return;

    final clamped = volume.clamp(0.0, 1.0);
    if ((ch.volume - clamped).abs() < 0.001) return;

    ch.volume = clamped;

    // Sync to composite event (triggers _updateEventLayerInternal →
    // EventRegistry.updateActiveLayerVolume for real-time FFI)
    _compositeProvider.setLayerVolumeContinuous(ch.eventId, layerId, clamped);

    // Don't notifyListeners here — _onCompositeChanged will fire from provider
  }

  /// Set channel volume (final — with undo, for fader drag end)
  void setChannelVolumeFinal(String layerId, double volume) {
    final ch = _findChannel(layerId);
    if (ch == null) return;

    _compositeProvider.setLayerVolume(ch.eventId, layerId, volume.clamp(0.0, 1.0));
  }

  /// Set channel pan (continuous — no undo)
  void setChannelPan(String layerId, double pan) {
    final ch = _findChannel(layerId);
    if (ch == null) return;

    final clamped = pan.clamp(-1.0, 1.0);
    ch.pan = clamped;

    _compositeProvider.setLayerPanContinuous(ch.eventId, layerId, clamped);
  }

  /// Set channel pan (final — with undo)
  void setChannelPanFinal(String layerId, double pan) {
    final ch = _findChannel(layerId);
    if (ch == null) return;

    _compositeProvider.setLayerPan(ch.eventId, layerId, pan.clamp(-1.0, 1.0));
  }

  /// Set channel pan right for stereo dual-pan (continuous — no undo)
  void setChannelPanRight(String layerId, double panRight) {
    final ch = _findChannel(layerId);
    if (ch == null) return;

    final clamped = panRight.clamp(-1.0, 1.0);
    ch.panRight = clamped;

    _compositeProvider.setLayerPanRightContinuous(ch.eventId, layerId, clamped);
  }

  /// Set channel pan right (final — with undo)
  void setChannelPanRightFinal(String layerId, double panRight) {
    final ch = _findChannel(layerId);
    if (ch == null) return;

    _compositeProvider.setLayerPanRight(ch.eventId, layerId, panRight.clamp(-1.0, 1.0));
  }

  /// Toggle channel mute — syncs to composite event + active voice FFI
  void toggleMute(String layerId) {
    final ch = _findChannel(layerId);
    if (ch == null) return;

    _compositeProvider.toggleLayerMute(ch.eventId, layerId);
    // _onCompositeChanged will update ch.muted from layer
  }

  /// Toggle channel solo (LOCAL only — not persisted to layer)
  /// When any channel is soloed, all non-soloed playing voices get muted via FFI
  void toggleSolo(String layerId) {
    final ch = _findChannel(layerId);
    if (ch == null) return;

    ch.soloed = !ch.soloed;
    _hasSoloActive = _channels.any((c) => c.soloed);

    // Apply solo-in-place to active voices
    _applySoloState();

    notifyListeners();
  }

  /// Change channel bus routing — updates composite event layer busId,
  /// triggers rebuild which moves channel to correct bus group
  void setChannelBus(String layerId, int newBusId) {
    final ch = _findChannel(layerId);
    if (ch == null) return;
    if (ch.busId == newBusId) return;

    // Get current layer from composite event
    SlotCompositeEvent? event;
    for (final e in _compositeProvider.compositeEvents) {
      if (e.id == ch.eventId) { event = e; break; }
    }
    if (event == null) return;

    SlotEventLayer? layer;
    for (final l in event.layers) {
      if (l.id == layerId) { layer = l; break; }
    }
    if (layer == null) return;

    // Update with undo
    _compositeProvider.updateEventLayer(
      ch.eventId,
      layer.copyWith(busId: newBusId),
    );
    // _onCompositeChanged → _rebuildChannels → channel moves to new bus group
  }

  /// Preview/audition a channel — play the sound once regardless of slot state
  void auditionChannel(String layerId) {
    final ch = _findChannel(layerId);
    if (ch == null) return;

    AudioPlaybackService.instance.playFileToBus(
      ch.audioPath,
      volume: ch.volume,
      pan: ch.pan,
      busId: ch.busId,
      source: PlaybackSource.slotlab,
      layerId: ch.layerId,
    );
  }

  // ─── Solo Implementation ────────────────────────────────────────────────

  /// Apply solo-in-place: mute all non-soloed active voices via FFI
  void _applySoloState() {
    final playback = AudioPlaybackService.instance;

    for (final ch in _channels) {
      if (ch.activeVoiceId == null) continue;

      if (_hasSoloActive) {
        // Solo active: mute non-soloed, unmute soloed
        final shouldMute = !ch.soloed || ch.muted;
        playback.updateLayerMute(ch.layerId, shouldMute);
      } else {
        // No solo: restore original mute state from layer
        playback.updateLayerMute(ch.layerId, ch.muted);
      }
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  SlotMixerChannel? _findChannel(String layerId) {
    for (final c in _channels) {
      if (c.layerId == layerId) return c;
    }
    return null;
  }
}
