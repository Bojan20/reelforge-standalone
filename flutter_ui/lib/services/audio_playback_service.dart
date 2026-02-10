/// FluxForge Studio — Unified Audio Playback Service
///
/// DELEGATED MODE: Respects UnifiedPlaybackController for section management.
/// - DAW, SlotLab, Middleware share PLAYBACK_ENGINE (via UnifiedPlaybackController)
/// - Browser uses PREVIEW_ENGINE (isolated, always allowed)
///
/// Voice-level playback management for preview/event audio.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/slot_audio_events.dart';
import '../src/rust/native_ffi.dart';
import 'unified_playback_controller.dart';

// =============================================================================
// PLAYBACK SOURCE ENUM
// =============================================================================

enum PlaybackSource {
  daw,        // DAW timeline playback
  slotlab,    // Slot Lab preview/stage playback
  middleware, // Middleware event trigger
  browser,    // Audio browser hover/click preview
}

// =============================================================================
// VOICE INFO — tracks active voices
// =============================================================================

class VoiceInfo {
  final int voiceId;
  final String audioPath;
  final PlaybackSource source;
  final String? eventId;
  final String? layerId;
  final DateTime startTime;

  VoiceInfo({
    required this.voiceId,
    required this.audioPath,
    required this.source,
    this.eventId,
    this.layerId,
    DateTime? startTime,
  }) : startTime = startTime ?? DateTime.now();
}

// =============================================================================
// AUDIO PLAYBACK SERVICE — Singleton
// =============================================================================

class AudioPlaybackService extends ChangeNotifier {
  // ─── Singleton ─────────────────────────────────────────────────────────────
  static AudioPlaybackService? _instance;
  static AudioPlaybackService get instance => _instance ??= AudioPlaybackService._();

  AudioPlaybackService._();

  // ─── FFI Reference ─────────────────────────────────────────────────────────
  final NativeFFI _ffi = NativeFFI.instance;

  // ─── State ─────────────────────────────────────────────────────────────────
  PlaybackSource? _activeSource;
  final List<VoiceInfo> _activeVoices = [];
  final Map<String, List<int>> _eventVoices = {}; // eventId → [voiceIds]

  bool _isPlaying = false;

  // ─── LUFS Normalization State (P1-02) ────────────────────────────────────
  bool _lufsNormalizationEnabled = false;
  double _targetLufs = -14.0; // Default streaming loudness target
  final Map<String, double> _audioLufsCache = {}; // audioPath → measured LUFS

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Map PlaybackSource to engine source ID (matches Rust PlaybackSource enum)
  int _sourceToEngineId(PlaybackSource source) {
    return switch (source) {
      PlaybackSource.daw => 0,
      PlaybackSource.slotlab => 1,
      PlaybackSource.middleware => 2,
      PlaybackSource.browser => 3,
    };
  }

  // ─── Getters ───────────────────────────────────────────────────────────────
  PlaybackSource? get activeSource => _activeSource;
  bool get isPlaying => _isPlaying;
  bool get isDAWPlaying => _activeSource == PlaybackSource.daw && _isPlaying;
  bool get isSlotLabPlaying => _activeSource == PlaybackSource.slotlab && _isPlaying;
  bool get isMiddlewarePlaying => _activeSource == PlaybackSource.middleware && _isPlaying;
  List<VoiceInfo> get activeVoices => List.unmodifiable(_activeVoices);
  int get activeVoiceCount => _activeVoices.length;

  /// Last error from FFI playback operation (for debugging)
  String get lastPlaybackToBusError => _ffi.lastPlaybackToBusError;

  /// LUFS normalization toggle (P1-02)
  bool get lufsNormalizationEnabled => _lufsNormalizationEnabled;
  double get targetLufs => _targetLufs;

  /// Get cached LUFS value for audio file (or null if not measured)
  double? getLufsForAudio(String audioPath) => _audioLufsCache[audioPath];

  // ===========================================================================
  // DELEGATED MODE — Respects UnifiedPlaybackController
  // ===========================================================================

  /// Acquire playback for a source. Delegated to UnifiedPlaybackController.
  /// Browser source is always allowed (uses PREVIEW_ENGINE, isolated).
  /// Other sources must have already acquired via UnifiedPlaybackController.
  void _acquirePlayback(PlaybackSource source) {
    // Browser uses PREVIEW_ENGINE — always allowed, no conflict
    if (source == PlaybackSource.browser) {
      _activeSource = source;
      _isPlaying = true;
      notifyListeners();
      return;
    }

    // For other sources, verify they match UnifiedPlaybackController's active section
    final controller = UnifiedPlaybackController.instance;
    final activeSection = controller.activeSection;

    // Map PlaybackSource to PlaybackSection for comparison
    final expectedSection = switch (source) {
      PlaybackSource.daw => PlaybackSection.daw,
      PlaybackSource.slotlab => PlaybackSection.slotLab,
      PlaybackSource.middleware => PlaybackSection.middleware,
      PlaybackSource.browser => PlaybackSection.browser,
    };

    // If source doesn't match active section, it means the caller didn't acquire first
    // We still allow it but log a warning for debugging
    if (activeSection != expectedSection && activeSection != null) {
    }

    // If switching sources locally, stop previous voices (not transport)
    if (_activeSource != null && _activeSource != source && _activeSource != PlaybackSource.browser) {
      _activeVoices.clear();
      _eventVoices.clear();
    }

    _activeSource = source;
    _isPlaying = true;
    notifyListeners();
  }

  /// Release playback (called when source stops)
  void _releasePlayback(PlaybackSource source) {
    if (_activeSource == source) {
      _activeSource = null;
      _isPlaying = false;
      notifyListeners();
    }
  }

  // ===========================================================================
  // PREVIEW API — Single file playback (Audio Browser, hover preview)
  // ===========================================================================

  /// Play single audio file for preview (uses PreviewEngine - isolated)
  /// Returns voice_id on success, -1 on error
  int previewFile(
    String path, {
    double volume = 1.0,
    PlaybackSource source = PlaybackSource.browser,
  }) {
    if (path.isEmpty) return -1;

    _acquirePlayback(source);

    try {
      // Apply LUFS normalization if enabled (P1-02)
      final normalizedVolume = _calculateNormalizedVolume(path, volume);

      final voiceId = _ffi.previewAudioFile(path, volume: normalizedVolume);
      if (voiceId >= 0) {
        _activeVoices.add(VoiceInfo(
          voiceId: voiceId,
          audioPath: path,
          source: source,
        ));
      }
      return voiceId;
    } catch (e) {
      return -1;
    }
  }

  // ===========================================================================
  // BUS ROUTING API — Play through DAW buses (Middleware/SlotLab)
  // ===========================================================================

  /// Play single audio file through a specific bus (uses PlaybackEngine)
  /// busId: 0=Sfx, 1=Music, 2=Voice, 3=Ambience, 4=Aux, 5=Master
  /// pan: -1.0 = full left, 0.0 = center, +1.0 = full right
  /// Returns voice_id on success, -1 on error
  int playFileToBus(
    String path, {
    double volume = 1.0,
    double pan = 0.0,
    int busId = 0,
    PlaybackSource source = PlaybackSource.middleware,
    String? eventId,
    String? layerId,
    double pitch = 0.0, // P12.0.1: pitch shift in semitones (-24 to +24)
  }) {
    if (path.isEmpty) return -1;

    _acquirePlayback(source);

    try {
      // Map PlaybackSource to engine source ID
      final sourceId = _sourceToEngineId(source);
      final voiceId = _ffi.playbackPlayToBus(path, volume: volume, pan: pan, busId: busId, source: sourceId);
      if (voiceId >= 0) {
        // P12.0.1: Apply pitch shift if non-zero
        if (pitch.abs() > 0.001) {
          _ffi.setVoicePitch(voiceId, pitch);
        }

        _activeVoices.add(VoiceInfo(
          voiceId: voiceId,
          audioPath: path,
          source: source,
          eventId: eventId,
          layerId: layerId,
        ));

        // Track by event if provided
        if (eventId != null) {
          _eventVoices.putIfAbsent(eventId, () => []).add(voiceId);
        }

      }
      return voiceId;
    } catch (e) {
      return -1;
    }
  }

  /// Extended play through specific bus with fadeIn/fadeOut/trim parameters
  /// busId: 0=Sfx, 1=Music, 2=Voice, 3=Ambience, 4=Aux, 5=Master
  /// pan: -1.0 = full left, 0.0 = center, +1.0 = full right
  /// fadeInMs: fade-in duration in milliseconds (0 = instant start)
  /// fadeOutMs: fade-out duration at end in milliseconds (0 = instant stop)
  /// trimStartMs: start playback from this position in milliseconds
  /// trimEndMs: stop playback at this position in milliseconds (0 = play to end)
  /// Returns voice_id on success, -1 on error
  int playFileToBusEx(
    String path, {
    double volume = 1.0,
    double pan = 0.0,
    int busId = 0,
    PlaybackSource source = PlaybackSource.middleware,
    String? eventId,
    String? layerId,
    double fadeInMs = 0.0,
    double fadeOutMs = 0.0,
    double trimStartMs = 0.0,
    double trimEndMs = 0.0,
  }) {
    if (path.isEmpty) return -1;

    _acquirePlayback(source);

    try {
      // Map PlaybackSource to engine source ID
      final sourceId = _sourceToEngineId(source);
      final voiceId = _ffi.playbackPlayToBusEx(
        path,
        volume: volume,
        pan: pan,
        busId: busId,
        source: sourceId,
        fadeInMs: fadeInMs,
        fadeOutMs: fadeOutMs,
        trimStartMs: trimStartMs,
        trimEndMs: trimEndMs,
      );
      if (voiceId >= 0) {
        _activeVoices.add(VoiceInfo(
          voiceId: voiceId,
          audioPath: path,
          source: source,
          eventId: eventId,
          layerId: layerId,
        ));

        // Track by event if provided
        if (eventId != null) {
          _eventVoices.putIfAbsent(eventId, () => []).add(voiceId);
        }

      }
      return voiceId;
    } catch (e) {
      return -1;
    }
  }

  /// P0.2: Play looping audio through a specific bus (REEL_SPIN, ambience loops, etc.)
  /// Loops seamlessly until explicitly stopped with stopOneShotVoice()
  /// busId: 0=Master, 1=Music, 2=Sfx, 3=Voice, 4=Ambience, 5=Aux
  /// pan: -1.0 = full left, 0.0 = center, +1.0 = full right
  /// Returns voice_id on success, -1 on error
  int playLoopingToBus(
    String path, {
    double volume = 1.0,
    double pan = 0.0,
    int busId = 0,
    PlaybackSource source = PlaybackSource.slotlab,
    String? eventId,
    String? layerId,
    double pitch = 0.0, // P12.0.1: pitch shift in semitones (-24 to +24)
  }) {
    if (path.isEmpty) return -1;

    _acquirePlayback(source);

    try {
      // Map PlaybackSource to engine source ID
      final sourceId = _sourceToEngineId(source);
      final voiceId = _ffi.playbackPlayLoopingToBus(path, volume: volume, pan: pan, busId: busId, source: sourceId);
      if (voiceId >= 0) {
        // P12.0.1: Apply pitch shift if non-zero
        if (pitch.abs() > 0.001) {
          _ffi.setVoicePitch(voiceId, pitch);
        }

        _activeVoices.add(VoiceInfo(
          voiceId: voiceId,
          audioPath: path,
          source: source,
          eventId: eventId,
          layerId: layerId,
        ));

        // Track by event if provided
        if (eventId != null) {
          _eventVoices.putIfAbsent(eventId, () => []).add(voiceId);
        }

      }
      return voiceId;
    } catch (e) {
      return -1;
    }
  }

  /// Stop specific one-shot voice (bus routing)
  void stopOneShotVoice(int voiceId) {
    _activeVoices.removeWhere((v) => v.voiceId == voiceId);
    _ffi.playbackStopOneShot(voiceId);
    _checkAndReleasePlayback();
  }

  /// Stop all one-shot voices (bus routing)
  void stopAllOneShots() {
    _activeVoices.removeWhere((v) =>
        v.source == PlaybackSource.middleware || v.source == PlaybackSource.slotlab);
    _eventVoices.clear();
    _ffi.playbackStopAllOneShots();
  }

  // ===========================================================================
  // LAYER API — Play single layer from SlotEventLayer
  // ===========================================================================

  /// Play a single layer (used by Slot Lab timeline)
  /// Uses bus routing for slotlab/middleware sources, preview engine for browser
  int playLayer(
    SlotEventLayer layer, {
    double offsetSeconds = 0,
    PlaybackSource source = PlaybackSource.slotlab,
    String? eventId,
    int? busIdOverride,
  }) {
    if (layer.audioPath.isEmpty) return -1;
    if (layer.muted) return -1;

    _acquirePlayback(source);

    try {
      int voiceId;

      // Use bus routing for slotlab/middleware, preview engine for browser
      if (source == PlaybackSource.browser) {
        voiceId = _ffi.previewAudioFile(
          layer.audioPath,
          volume: layer.volume,
        );
      } else {
        // Use layer's busId, override, or default to Sfx (0)
        final busId = busIdOverride ?? layer.busId ?? 0;
        final sourceId = _sourceToEngineId(source);
        voiceId = _ffi.playbackPlayToBus(
          layer.audioPath,
          volume: layer.volume,
          pan: layer.pan,
          busId: busId,
          source: sourceId,
        );
      }

      if (voiceId >= 0) {
        _activeVoices.add(VoiceInfo(
          voiceId: voiceId,
          audioPath: layer.audioPath,
          source: source,
          eventId: eventId,
          layerId: layer.id,
        ));

        // Track by event if provided
        if (eventId != null) {
          _eventVoices.putIfAbsent(eventId, () => []).add(voiceId);
        }

      }
      return voiceId;
    } catch (e) {
      return -1;
    }
  }

  // ===========================================================================
  // EVENT API — Play composite event with all layers
  // ===========================================================================

  /// Play entire composite event with all its layers
  /// Uses bus routing for middleware/slotlab sources
  /// Respects offsetMs, volume, mute, solo, busId for each layer
  Future<List<int>> playEvent(
    SlotCompositeEvent event, {
    PlaybackSource source = PlaybackSource.middleware,
    Map<String, dynamic>? context,
    int? defaultBusId,
  }) async {
    if (event.layers.isEmpty) return [];

    _acquirePlayback(source);

    final voiceIds = <int>[];
    final layers = event.layers.where((l) => !l.muted).toList();

    // Check for solo — if any layer is solo, only play solo layers
    final hasSolo = layers.any((l) => l.solo);
    final layersToPlay = hasSolo ? layers.where((l) => l.solo).toList() : layers;

    for (final layer in layersToPlay) {
      // Calculate delay from offsetMs
      final delayMs = layer.offsetMs.round();
      if (delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }

      // Apply context volume multiplier if provided
      double volume = layer.volume;
      if (context != null && context.containsKey('volumeMultiplier')) {
        volume *= (context['volumeMultiplier'] as num).toDouble();
      }

      try {
        int voiceId;

        // Use bus routing for middleware/slotlab, preview engine for browser
        if (source == PlaybackSource.browser) {
          voiceId = _ffi.previewAudioFile(
            layer.audioPath,
            volume: volume.clamp(0.0, 1.0),
          );
        } else {
          // Use layer's busId, event default, or fallback to Sfx (0)
          final busId = layer.busId ?? defaultBusId ?? 0;
          final sourceId = _sourceToEngineId(source);
          voiceId = _ffi.playbackPlayToBus(
            layer.audioPath,
            volume: volume.clamp(0.0, 1.0),
            pan: layer.pan,
            busId: busId,
            source: sourceId,
          );
        }

        if (voiceId >= 0) {
          voiceIds.add(voiceId);
          _activeVoices.add(VoiceInfo(
            voiceId: voiceId,
            audioPath: layer.audioPath,
            source: source,
            eventId: event.id,
            layerId: layer.id,
          ));
        }
      } catch (e) { /* ignored */ }
    }

    // Track voices by event
    if (voiceIds.isNotEmpty) {
      _eventVoices[event.id] = voiceIds;
    }

    return voiceIds;
  }

  // ===========================================================================
  // DAW TIMELINE API — Delegated to UnifiedPlaybackController
  // ===========================================================================

  /// Start DAW timeline playback
  /// DEPRECATED: Use UnifiedPlaybackController.instance.play() instead
  /// Kept for backward compatibility
  ///
  /// NOTE: This method does NOT call play() - it only prepares the audio stream.
  /// Playback starts only when user explicitly triggers transport (Space bar, Play button).
  bool startDAWPlayback() {
    // Just prepare DAW source, don't acquire section or start playback
    // Actual playback is triggered via UnifiedPlaybackController.play()
    // which is called from TimelinePlaybackProvider.play() when user presses Space/Play
    return true;
  }

  /// Stop DAW timeline playback
  /// DEPRECATED: Use UnifiedPlaybackController.instance.stop() instead
  void stopDAWPlayback() {
    if (_activeSource != PlaybackSource.daw) return;

    final controller = UnifiedPlaybackController.instance;
    controller.stop(releaseAfterStop: true);
    _releasePlayback(PlaybackSource.daw);
  }

  // ===========================================================================
  // STOP API
  // ===========================================================================

  /// Stop specific voice by ID
  void stopVoice(int voiceId) {
    // Stop in engine first
    _ffi.playbackStopOneShot(voiceId);
    _activeVoices.removeWhere((v) => v.voiceId == voiceId);
    _checkAndReleasePlayback();
  }

  /// P0: Fade out specific voice with configurable duration
  /// voiceId: voice to fade out
  /// fadeMs: fade duration in milliseconds (50ms typical for reel stop)
  void fadeOutVoice(int voiceId, {int fadeMs = 50}) {
    _ffi.playbackFadeOutOneShot(voiceId, fadeMs: fadeMs);
    // Remove from tracking after fade starts (voice will deactivate itself)
    _activeVoices.removeWhere((v) => v.voiceId == voiceId);
    _checkAndReleasePlayback();
  }

  /// Stop all voices for a specific event
  void stopEvent(String eventId) {
    final voices = _eventVoices.remove(eventId);
    if (voices != null) {
      // Stop each voice in engine
      for (final voiceId in voices) {
        _ffi.playbackStopOneShot(voiceId);
      }
      _activeVoices.removeWhere((v) => v.eventId == eventId);
    }
    _checkAndReleasePlayback();
  }

  /// Stop all voices for a specific layer
  void stopLayer(String layerId) {
    final voicesToStop = _activeVoices.where((v) => v.layerId == layerId).toList();
    for (final voice in voicesToStop) {
      _ffi.playbackStopOneShot(voice.voiceId);
      // Remove from event tracking
      _eventVoices.forEach((eventId, voices) {
        voices.remove(voice.voiceId);
      });
    }
    _activeVoices.removeWhere((v) => v.layerId == layerId);
    _checkAndReleasePlayback();
    if (voicesToStop.isNotEmpty) {
    }
  }

  /// Stop all voices from a specific source
  void stopSource(PlaybackSource source) {
    if (source == PlaybackSource.daw) {
      stopDAWPlayback();
      return;
    }

    // Stop all one-shot voices for this source in engine
    final voicesToStop = _activeVoices.where((v) => v.source == source).toList();
    for (final voice in voicesToStop) {
      _ffi.playbackStopOneShot(voice.voiceId);
    }

    _activeVoices.removeWhere((v) => v.source == source);

    // Remove event tracking for this source
    _eventVoices.removeWhere((eventId, voices) {
      return _activeVoices.every((v) => v.eventId != eventId);
    });

    // If this was the active source, stop preview engine
    if (_activeSource == source) {
      _ffi.previewStop();
      _releasePlayback(source);
    }

  }

  // ===========================================================================
  // P1.11: PRE-TRIGGER BUFFER — Schedule audio playback in advance
  // ===========================================================================

  /// Default pre-trigger offset in milliseconds (compensates for audio latency)
  static const int _defaultPreTriggerMs = 20;

  /// Pre-trigger offsets for specific stage categories (ms)
  static const Map<String, int> _preTriggerOffsets = {
    'ANTICIPATION': 50,    // Critical timing for anticipation
    'REEL_STOP': 30,       // Precise sync with visual reel stop
    'WIN_PRESENT': 20,     // Win reveal needs tight sync
    'CASCADE_STEP': 15,    // Cascade steps are rapid-fire
    'JACKPOT': 40,         // Jackpot reveal is dramatic
  };

  /// Pending pre-triggered events (scheduled but not yet played)
  final Map<String, Timer> _preTriggerTimers = {};

  /// Get pre-trigger offset for a stage type
  int getPreTriggerOffset(String stageType) {
    // Check exact match first
    if (_preTriggerOffsets.containsKey(stageType)) {
      return _preTriggerOffsets[stageType]!;
    }
    // Check prefix match
    for (final entry in _preTriggerOffsets.entries) {
      if (stageType.startsWith(entry.key)) {
        return entry.value;
      }
    }
    return _defaultPreTriggerMs;
  }

  /// Schedule audio playback with pre-trigger compensation
  /// Returns a handle ID that can be used to cancel the scheduled playback
  String schedulePreTrigger({
    required String path,
    required int preTriggerMs,
    double volume = 1.0,
    double pan = 0.0,
    int busId = 0,
    PlaybackSource source = PlaybackSource.slotlab,
    String? stageType,
  }) {
    final handleId = 'pretrig_${DateTime.now().microsecondsSinceEpoch}_${path.hashCode}';
    final offsetMs = stageType != null ? getPreTriggerOffset(stageType) : preTriggerMs;

    // Schedule the playback
    final timer = Timer(Duration(milliseconds: offsetMs.clamp(0, 200)), () {
      _preTriggerTimers.remove(handleId);
      final voiceId = playFileToBus(
        path,
        volume: volume,
        pan: pan,
        busId: busId,
        source: source,
      );
    });

    _preTriggerTimers[handleId] = timer;
    return handleId;
  }

  /// Cancel a scheduled pre-trigger
  void cancelPreTrigger(String handleId) {
    final timer = _preTriggerTimers.remove(handleId);
    if (timer != null) {
      timer.cancel();
    }
  }

  /// Cancel all pending pre-triggers
  void cancelAllPreTriggers() {
    for (final timer in _preTriggerTimers.values) {
      timer.cancel();
    }
    final count = _preTriggerTimers.length;
    _preTriggerTimers.clear();
    if (count > 0) {
    }
  }

  // ===========================================================================
  // P1.12: TAIL HANDLING — Soft stop with configurable fade-out
  // ===========================================================================

  /// Default tail fade duration in milliseconds
  static const int _defaultTailFadeMs = 50;

  /// Tail fade durations for specific stage categories (ms)
  static const Map<String, int> _tailFadeDurations = {
    'MUSIC': 500,          // Music needs long tail
    'AMBIENT': 400,        // Ambience also needs smooth fade
    'REEL_SPIN': 80,       // Spin loop needs quick but not instant stop
    'WIN': 100,            // Win sounds moderate fade
    'BIGWIN': 200,         // Big win celebration longer fade
    'VOICE': 30,           // Voice can be shorter
  };

  /// Get tail fade duration for a stage type
  int getTailFadeDuration(String? stageType) {
    if (stageType == null) return _defaultTailFadeMs;
    // Check exact match first
    if (_tailFadeDurations.containsKey(stageType)) {
      return _tailFadeDurations[stageType]!;
    }
    // Check prefix match
    for (final entry in _tailFadeDurations.entries) {
      if (stageType.startsWith(entry.key)) {
        return entry.value;
      }
    }
    return _defaultTailFadeMs;
  }

  /// Stop voice with tail fade-out (soft stop)
  /// Uses stage-aware fade duration for natural audio endings
  void stopVoiceWithTail(int voiceId, {String? stageType, int? fadeMs}) {
    final fadeDuration = fadeMs ?? getTailFadeDuration(stageType);
    fadeOutVoice(voiceId, fadeMs: fadeDuration);
  }

  /// Stop event with tail fade-out (soft stop all voices)
  void stopEventWithTail(String eventId, {String? stageType, int? fadeMs}) {
    final voices = _eventVoices.remove(eventId);
    if (voices != null && voices.isNotEmpty) {
      final fadeDuration = fadeMs ?? getTailFadeDuration(stageType);
      for (final voiceId in voices) {
        fadeOutVoice(voiceId, fadeMs: fadeDuration);
      }
      _activeVoices.removeWhere((v) => v.eventId == eventId);
    }
    _checkAndReleasePlayback();
  }

  /// Stop all voices from source with tail fade-out
  void stopSourceWithTail(PlaybackSource source, {int fadeMs = 100}) {
    if (source == PlaybackSource.daw) {
      stopDAWPlayback();
      return;
    }

    final voicesToStop = _activeVoices.where((v) => v.source == source).toList();
    for (final voice in voicesToStop) {
      fadeOutVoice(voice.voiceId, fadeMs: fadeMs);
    }

    _activeVoices.removeWhere((v) => v.source == source);
    _eventVoices.removeWhere((eventId, voices) {
      return _activeVoices.every((v) => v.eventId != eventId);
    });

    if (_activeSource == source) {
      _releasePlayback(source);
    }

  }

  /// Stop ALL playback (all sources)
  void stopAll() {
    _stopAllInternal();
    notifyListeners();
  }

  /// Internal stop without notification (used during source switch)
  void _stopAllInternal() {
    // Stop DAW if running
    if (_activeSource == PlaybackSource.daw) {
      try {
        _ffi.stopPlayback();
      } catch (e) { /* ignored */ }
    }

    // Stop preview engine (covers all preview sources)
    try {
      _ffi.previewStop();
    } catch (e) { /* ignored */ }

    // Clear tracking
    _activeVoices.clear();
    _eventVoices.clear();
    _activeSource = null;
    _isPlaying = false;

  }

  /// Check if we should release playback (no active voices)
  void _checkAndReleasePlayback() {
    if (_activeVoices.isEmpty && _activeSource != PlaybackSource.daw) {
      _releasePlayback(_activeSource!);
    }
  }

  // ===========================================================================
  // UTILITY
  // ===========================================================================

  /// Check if preview engine is currently playing
  bool isPreviewPlaying() {
    try {
      return _ffi.previewIsPlaying();
    } catch (e) {
      return false;
    }
  }

  /// Get voices for a specific event
  List<int> getEventVoices(String eventId) {
    return _eventVoices[eventId] ?? [];
  }

  /// Preview composite event with respect to layer offsets (P0 WF-05)
  ///
  /// Plays all non-muted layers with correct timing (offsetMs)
  void previewCompositeEvent(SlotCompositeEvent event) {
    if (event.layers.isEmpty) return;


    for (final layer in event.layers) {
      if (layer.muted || layer.audioPath.isEmpty) continue;

      if (layer.offsetMs > 0) {
        // Schedule delayed playback
        Future.delayed(Duration(milliseconds: layer.offsetMs.round()), () {
          final voiceId = previewFile(layer.audioPath);
        });
      } else {
        // Play immediately
        final voiceId = previewFile(layer.audioPath);
      }
    }
  }

  // ===========================================================================
  // LUFS NORMALIZATION (P1-02)
  // ===========================================================================

  /// Enable/disable LUFS normalization for preview playback
  void setLufsNormalization(bool enabled, {double? targetLufs}) {
    _lufsNormalizationEnabled = enabled;
    if (targetLufs != null) {
      _targetLufs = targetLufs.clamp(-40.0, 0.0);
    }
    notifyListeners();
  }

  /// Set target LUFS level
  void setTargetLufs(double lufs) {
    _targetLufs = lufs.clamp(-40.0, 0.0);
    notifyListeners();
  }

  /// Measure LUFS for audio file via rf-offline FFI
  /// Returns measured LUFS value or null on error
  Future<double?> measureLufs(String audioPath) async {
    // Check cache first
    if (_audioLufsCache.containsKey(audioPath)) {
      return _audioLufsCache[audioPath];
    }

    try {
      // TODO: Call rf-offline FFI function for EBU R128 LUFS metering
      // This requires implementing:
      // - offlineMeasureLufs(audioPath) → double (integrated LUFS)
      //
      // For now, return a placeholder value
      // Real implementation would call:
      // final lufs = _ffi.offlineMeasureLufs(audioPath);

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Calculate normalized volume based on measured LUFS
  /// Returns volume multiplier (linear gain)
  double _calculateNormalizedVolume(String audioPath, double baseVolume) {
    if (!_lufsNormalizationEnabled) return baseVolume;

    final measuredLufs = _audioLufsCache[audioPath];
    if (measuredLufs == null) {
      // Not measured yet — play at base volume
      // Optionally trigger async measurement for next time
      measureLufs(audioPath).then((lufs) {
        if (lufs != null) {
          _audioLufsCache[audioPath] = lufs;
        }
      });
      return baseVolume;
    }

    // Calculate gain adjustment in dB
    final gainDb = _targetLufs - measuredLufs;

    // Convert dB to linear gain
    // Clamp to reasonable range (-12dB to +12dB)
    final clampedGainDb = gainDb.clamp(-12.0, 12.0);
    final linearGain = _dbToLinear(clampedGainDb);

    final normalizedVolume = baseVolume * linearGain;


    return normalizedVolume;
  }

  /// Convert dB to linear gain
  double _dbToLinear(double db) {
    return math.pow(10, db / 20).toDouble();
  }

  /// Clear LUFS cache (for testing/reset)
  void clearLufsCache() {
    _audioLufsCache.clear();
    notifyListeners();
  }

  /// Dispose service
  @override
  void dispose() {
    stopAll();
    super.dispose();
  }
}
