/// FluxForge Studio — Unified Audio Playback Service
///
/// DELEGATED MODE: Respects UnifiedPlaybackController for section management.
/// - DAW, SlotLab, Middleware share PLAYBACK_ENGINE (via UnifiedPlaybackController)
/// - Browser uses PREVIEW_ENGINE (isolated, always allowed)
///
/// Voice-level playback management for preview/event audio.

import 'dart:async';
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
      debugPrint('[AudioPlayback] WARNING: Source $source but active section is $activeSection');
    }

    // If switching sources locally, stop previous voices (not transport)
    if (_activeSource != null && _activeSource != source && _activeSource != PlaybackSource.browser) {
      debugPrint('[AudioPlayback] Switching from $_activeSource to $source — clearing voices');
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
      final voiceId = _ffi.previewAudioFile(path, volume: volume);
      if (voiceId >= 0) {
        _activeVoices.add(VoiceInfo(
          voiceId: voiceId,
          audioPath: path,
          source: source,
        ));
        debugPrint('[AudioPlayback] Preview started: $path (voice $voiceId, source: $source)');
      }
      return voiceId;
    } catch (e) {
      debugPrint('[AudioPlayback] Preview error: $e');
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
  }) {
    if (path.isEmpty) return -1;

    _acquirePlayback(source);

    try {
      // Map PlaybackSource to engine source ID
      final sourceId = _sourceToEngineId(source);
      final voiceId = _ffi.playbackPlayToBus(path, volume: volume, pan: pan, busId: busId, source: sourceId);
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

        debugPrint('[AudioPlayback] PlayToBus: $path -> bus $busId (voice $voiceId, source: $source)');
      }
      return voiceId;
    } catch (e) {
      debugPrint('[AudioPlayback] PlayToBus error: $e');
      return -1;
    }
  }

  /// P0.2: Play looping audio through a specific bus (REEL_SPIN, ambience loops, etc.)
  /// Loops seamlessly until explicitly stopped with stopOneShotVoice()
  /// busId: 0=Sfx, 1=Music, 2=Voice, 3=Ambience, 4=Aux, 5=Master
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
  }) {
    if (path.isEmpty) return -1;

    _acquirePlayback(source);

    try {
      // Map PlaybackSource to engine source ID
      final sourceId = _sourceToEngineId(source);
      final voiceId = _ffi.playbackPlayLoopingToBus(path, volume: volume, pan: pan, busId: busId, source: sourceId);
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

        debugPrint('[AudioPlayback] PlayLoopingToBus: $path -> bus $busId (voice $voiceId, source: $source)');
      }
      return voiceId;
    } catch (e) {
      debugPrint('[AudioPlayback] PlayLoopingToBus error: $e');
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
    debugPrint('[AudioPlayback] All one-shots stopped');
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

        debugPrint('[AudioPlayback] Layer started: ${layer.name} (voice $voiceId, bus: ${layer.busId ?? 0})');
      }
      return voiceId;
    } catch (e) {
      debugPrint('[AudioPlayback] Layer play error: $e');
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
        debugPrint('[AudioPlayback] Event layer: ${layer.name} (voice $voiceId, bus: ${layer.busId ?? defaultBusId ?? 0})');
      } catch (e) {
        debugPrint('[AudioPlayback] Event layer error: $e');
      }
    }

    // Track voices by event
    if (voiceIds.isNotEmpty) {
      _eventVoices[event.id] = voiceIds;
    }

    debugPrint('[AudioPlayback] Event "${event.name}" started with ${voiceIds.length} voices');
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
    debugPrint('[AudioPlayback] DAW audio stream ready (no auto-play)');
    return true;
  }

  /// Stop DAW timeline playback
  /// DEPRECATED: Use UnifiedPlaybackController.instance.stop() instead
  void stopDAWPlayback() {
    if (_activeSource != PlaybackSource.daw) return;

    final controller = UnifiedPlaybackController.instance;
    controller.stop(releaseAfterStop: true);
    _releasePlayback(PlaybackSource.daw);
    debugPrint('[AudioPlayback] DAW playback stopped via UnifiedPlaybackController');
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
    debugPrint('[AudioPlayback] Stopped voice: $voiceId');
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
      debugPrint('[AudioPlayback] Stopped event: $eventId (${voices.length} voices)');
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
      debugPrint('[AudioPlayback] Stopped layer: $layerId (${voicesToStop.length} voices)');
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

    debugPrint('[AudioPlayback] Stopped source: $source (${voicesToStop.length} voices)');
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
      } catch (e) {
        debugPrint('[AudioPlayback] DAW stop error: $e');
      }
    }

    // Stop preview engine (covers all preview sources)
    try {
      _ffi.previewStop();
    } catch (e) {
      debugPrint('[AudioPlayback] Preview stop error: $e');
    }

    // Clear tracking
    _activeVoices.clear();
    _eventVoices.clear();
    _activeSource = null;
    _isPlaying = false;

    debugPrint('[AudioPlayback] All playback stopped');
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

  /// Dispose service
  @override
  void dispose() {
    stopAll();
    super.dispose();
  }
}
