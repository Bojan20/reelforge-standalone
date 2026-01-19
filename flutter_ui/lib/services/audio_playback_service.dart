/// FluxForge Studio — Unified Audio Playback Service
///
/// EXCLUSIVE MODE: Only ONE source plays at a time.
/// When DAW plays → Middleware & Slot Lab stop
/// When Slot Lab plays → DAW & Middleware stop
/// When Middleware plays → DAW & Slot Lab stop
///
/// Single source of truth for ALL audio playback in FluxForge.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/slot_audio_events.dart';
import '../src/rust/native_ffi.dart';

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

  // ─── Getters ───────────────────────────────────────────────────────────────
  PlaybackSource? get activeSource => _activeSource;
  bool get isPlaying => _isPlaying;
  bool get isDAWPlaying => _activeSource == PlaybackSource.daw && _isPlaying;
  bool get isSlotLabPlaying => _activeSource == PlaybackSource.slotlab && _isPlaying;
  bool get isMiddlewarePlaying => _activeSource == PlaybackSource.middleware && _isPlaying;
  List<VoiceInfo> get activeVoices => List.unmodifiable(_activeVoices);
  int get activeVoiceCount => _activeVoices.length;

  // ===========================================================================
  // EXCLUSIVE MODE — Stop other sources before playing
  // ===========================================================================

  /// Acquire playback for a source. Stops all other sources.
  void _acquirePlayback(PlaybackSource source) {
    if (_activeSource != null && _activeSource != source) {
      debugPrint('[AudioPlayback] Switching from $_activeSource to $source — stopping previous');
      _stopAllInternal();
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

  /// Play single audio file for preview
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
  // LAYER API — Play single layer from SlotEventLayer
  // ===========================================================================

  /// Play a single layer (used by Slot Lab timeline)
  int playLayer(
    SlotEventLayer layer, {
    double offsetSeconds = 0,
    PlaybackSource source = PlaybackSource.slotlab,
    String? eventId,
  }) {
    if (layer.audioPath.isEmpty) return -1;
    if (layer.muted) return -1;

    _acquirePlayback(source);

    try {
      final voiceId = _ffi.previewAudioFile(
        layer.audioPath,
        volume: layer.volume,
      );

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

        debugPrint('[AudioPlayback] Layer started: ${layer.name} (voice $voiceId)');
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
  /// Respects offsetMs, volume, mute, solo for each layer
  Future<List<int>> playEvent(
    SlotCompositeEvent event, {
    PlaybackSource source = PlaybackSource.middleware,
    Map<String, dynamic>? context,
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
        final voiceId = _ffi.previewAudioFile(
          layer.audioPath,
          volume: volume.clamp(0.0, 1.0),
        );

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
        debugPrint('[AudioPlayback] Event layer: ${layer.name} (voice $voiceId)');
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
  // DAW TIMELINE API
  // ===========================================================================

  /// Start DAW timeline playback
  /// Stops all other sources first
  bool startDAWPlayback() {
    _acquirePlayback(PlaybackSource.daw);

    try {
      final success = _ffi.startPlayback();
      if (success) {
        debugPrint('[AudioPlayback] DAW playback started');
      }
      return success;
    } catch (e) {
      debugPrint('[AudioPlayback] DAW start error: $e');
      return false;
    }
  }

  /// Stop DAW timeline playback
  void stopDAWPlayback() {
    if (_activeSource != PlaybackSource.daw) return;

    try {
      _ffi.stopPlayback();
      _releasePlayback(PlaybackSource.daw);
      debugPrint('[AudioPlayback] DAW playback stopped');
    } catch (e) {
      debugPrint('[AudioPlayback] DAW stop error: $e');
    }
  }

  // ===========================================================================
  // STOP API
  // ===========================================================================

  /// Stop specific voice by ID
  void stopVoice(int voiceId) {
    _activeVoices.removeWhere((v) => v.voiceId == voiceId);
    // Note: PreviewEngine doesn't support stopping individual voices yet
    // This just removes from tracking
    _checkAndReleasePlayback();
  }

  /// Stop all voices for a specific event
  void stopEvent(String eventId) {
    final voices = _eventVoices.remove(eventId);
    if (voices != null) {
      _activeVoices.removeWhere((v) => v.eventId == eventId);
      debugPrint('[AudioPlayback] Stopped event: $eventId (${voices.length} voices)');
    }
    _checkAndReleasePlayback();
  }

  /// Stop all voices from a specific source
  void stopSource(PlaybackSource source) {
    if (source == PlaybackSource.daw) {
      stopDAWPlayback();
      return;
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

    debugPrint('[AudioPlayback] Stopped source: $source');
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
