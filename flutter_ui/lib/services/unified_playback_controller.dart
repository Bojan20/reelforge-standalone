/// Unified Playback Controller — FluxForge Studio
///
/// SINGLE SOURCE OF TRUTH for all playback state across sections.
///
/// Architecture:
/// - DAW, SlotLab, Middleware all share PLAYBACK_ENGINE
/// - Browser preview uses PREVIEW_ENGINE (isolated)
/// - Only ONE section can control PLAYBACK_ENGINE at a time
/// - Section acquisition is explicit and logged
/// - Section-based MUTING: inactive sections' tracks are muted
///
/// Track ID Ranges:
/// - DAW tracks: 0-999
/// - SlotLab tracks: 100000+
/// - Middleware tracks: 200000+ (reserved)
///
/// Usage:
/// ```dart
/// // Acquire control before playback
/// if (UnifiedPlaybackController.instance.acquireSection(PlaybackSection.daw)) {
///   UnifiedPlaybackController.instance.play();
/// }
///
/// // Release when done
/// UnifiedPlaybackController.instance.releaseSection(PlaybackSection.daw);
/// ```
///
/// See: .claude/architecture/UNIFIED_PLAYBACK_SYSTEM.md

import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// =============================================================================
// PLAYBACK SECTION ENUM
// =============================================================================

/// Sections that can control playback
enum PlaybackSection {
  /// DAW timeline editing and playback
  daw,

  /// Slot Lab stage preview and spin playback
  slotLab,

  /// Middleware event testing
  middleware,

  /// Audio browser hover preview (uses PREVIEW_ENGINE, always isolated)
  browser,
}

// =============================================================================
// SECTION INTERRUPTION INFO
// =============================================================================

/// Information about why a section was interrupted
class SectionInterruption {
  final PlaybackSection interruptedSection;
  final PlaybackSection interruptingSection;
  final DateTime timestamp;
  final double positionAtInterrupt;

  SectionInterruption({
    required this.interruptedSection,
    required this.interruptingSection,
    required this.positionAtInterrupt,
  }) : timestamp = DateTime.now();
}

// =============================================================================
// UNIFIED PLAYBACK CONTROLLER — SINGLETON
// =============================================================================

/// Central controller for all playback across DAW, SlotLab, and Middleware.
///
/// This is the SINGLE SOURCE OF TRUTH for:
/// - Which section currently controls playback
/// - Global transport state (play/pause/stop/seek)
/// - Playhead position
///
/// Rules:
/// 1. Only ONE section can control PLAYBACK_ENGINE at a time
/// 2. Browser preview (PREVIEW_ENGINE) never conflicts with others
/// 3. Acquiring a new section gracefully stops the previous one
/// 4. All UI components should listen to this controller for state
class UnifiedPlaybackController extends ChangeNotifier {
  // ─── Singleton ─────────────────────────────────────────────────────────────
  static UnifiedPlaybackController? _instance;
  static UnifiedPlaybackController get instance =>
      _instance ??= UnifiedPlaybackController._();

  UnifiedPlaybackController._();

  // ─── FFI Reference ─────────────────────────────────────────────────────────
  final NativeFFI _ffi = NativeFFI.instance;

  // ─── State ─────────────────────────────────────────────────────────────────

  /// Currently active section controlling PLAYBACK_ENGINE (null = idle)
  PlaybackSection? _activeSection;

  /// Last interruption info (for UI display like "Paused by SlotLab")
  SectionInterruption? _lastInterruption;

  /// Whether recording is active (blocks section switching except DAW)
  bool _isRecording = false;

  // ─── Getters — State ───────────────────────────────────────────────────────

  /// Currently active section (null = nothing playing via PLAYBACK_ENGINE)
  PlaybackSection? get activeSection => _activeSection;

  /// Last interruption info (for displaying "Paused by X" messages)
  SectionInterruption? get lastInterruption => _lastInterruption;

  /// Whether any section is currently active
  bool get hasActiveSection => _activeSection != null;

  /// Whether recording is in progress
  bool get isRecording => _isRecording;

  // ─── Getters — Transport (READ from Rust atomics) ──────────────────────────

  /// Global playback state from PLAYBACK_ENGINE
  bool get isPlaying => _ffi.isPlaying();

  /// Current playhead position in seconds from PLAYBACK_ENGINE
  double get position => _ffi.getPosition();

  /// Playback state: 0=Stopped, 1=Playing, 2=Paused
  int get playbackState => _ffi.getPlaybackState();

  /// Whether currently scrubbing
  bool get isScrubbing => _ffi.playbackIsScrubbing();

  // ─── Convenience Getters ───────────────────────────────────────────────────

  /// Check if a specific section is active
  bool isSectionActive(PlaybackSection section) => _activeSection == section;

  /// Check if DAW is the active section
  bool get isDAWActive => _activeSection == PlaybackSection.daw;

  /// Check if SlotLab is the active section
  bool get isSlotLabActive => _activeSection == PlaybackSection.slotLab;

  /// Check if Middleware is the active section
  bool get isMiddlewareActive => _activeSection == PlaybackSection.middleware;

  /// Check if a section was interrupted (for showing "Paused by X")
  bool wasSectionInterrupted(PlaybackSection section) =>
      _lastInterruption?.interruptedSection == section;

  /// Get the section that caused interruption
  PlaybackSection? getInterruptingSection(PlaybackSection section) =>
      wasSectionInterrupted(section)
          ? _lastInterruption?.interruptingSection
          : null;

  // ===========================================================================
  // SECTION ACQUISITION — Core Logic
  // ===========================================================================

  /// Acquire playback control for a section.
  ///
  /// Returns true if acquired, false if denied.
  ///
  /// Behavior:
  /// - Browser section always succeeds (uses PREVIEW_ENGINE, isolated)
  /// - Other sections stop current section gracefully before acquiring
  /// - Recording blocks acquisition by non-DAW sections
  ///
  /// Example:
  /// ```dart
  /// if (controller.acquireSection(PlaybackSection.slotLab)) {
  ///   // Now SlotLab controls playback
  ///   controller.play();
  /// }
  /// ```
  bool acquireSection(PlaybackSection section) {
    // Browser uses PREVIEW_ENGINE — never conflicts, always allowed
    if (section == PlaybackSection.browser) {
      return true;
    }

    // Recording blocks non-DAW sections
    if (_isRecording && section != PlaybackSection.daw) {
      return false;
    }

    // Same section — already acquired
    if (_activeSection == section) {
      return true;
    }

    // Different section — stop current gracefully
    if (_activeSection != null && _activeSection != PlaybackSection.browser) {
      final previousSection = _activeSection!;
      final positionAtInterrupt = position;


      // Stop current section
      _stopCurrentSection();

      // Record interruption for UI
      _lastInterruption = SectionInterruption(
        interruptedSection: previousSection,
        interruptingSection: section,
        positionAtInterrupt: positionAtInterrupt,
      );
    }

    // Acquire new section
    _activeSection = section;

    // Notify engine of active section for one-shot voice filtering
    _setActiveSection(section);

    notifyListeners();
    return true;
  }

  /// Release playback control for a section.
  ///
  /// Should be called when:
  /// - Playback naturally ends
  /// - User stops playback
  /// - Section is deactivated
  void releaseSection(PlaybackSection section) {
    // Browser doesn't hold PLAYBACK_ENGINE control
    if (section == PlaybackSection.browser) {
      return;
    }

    if (_activeSection == section) {
      _activeSection = null;
      notifyListeners();
    }
  }

  /// Clear the last interruption info (e.g., when user acknowledges)
  void clearInterruption() {
    _lastInterruption = null;
    notifyListeners();
  }

  // ===========================================================================
  // TRANSPORT CONTROLS — Delegated to PLAYBACK_ENGINE
  // ===========================================================================

  /// Start playback.
  ///
  /// Only works if a section has been acquired.
  /// Browser section cannot start PLAYBACK_ENGINE transport.
  void play() {
    if (_activeSection == null) {
      return;
    }
    if (_activeSection == PlaybackSection.browser) {
      return;
    }

    // Ensure audio stream is running before transport play
    final streamStarted = _ffi.startPlayback();
    if (!streamStarted) {
    }

    _ffi.play();
    notifyListeners();
  }

  /// Start audio stream WITHOUT starting transport.
  ///
  /// Use this for SlotLab/Middleware which use one-shot voices (playFileToBus)
  /// instead of timeline clips. This prevents DAW clips from playing when
  /// SlotLab triggers events.
  ///
  /// Returns true if stream started successfully.
  bool ensureStreamRunning() {
    if (_activeSection == null) {
      return false;
    }

    final streamStarted = _ffi.startPlayback();
    return streamStarted;
  }

  /// Pause playback.
  void pause() {
    if (_activeSection == null || _activeSection == PlaybackSection.browser) {
      return;
    }

    _ffi.pause();
    notifyListeners();
  }

  /// Stop playback and optionally release section.
  ///
  /// [releaseAfterStop] - If true, releases the active section after stopping.
  void stop({bool releaseAfterStop = false}) {
    if (_activeSection == null || _activeSection == PlaybackSection.browser) {
      return;
    }

    final section = _activeSection!;
    _ffi.stop();

    if (releaseAfterStop) {
      releaseSection(section);
    } else {
      notifyListeners();
    }
  }

  /// Seek to position in seconds.
  void seek(double seconds) {
    if (_activeSection == null || _activeSection == PlaybackSection.browser) {
      return;
    }

    _ffi.seek(seconds);
    // Don't notify — position will be read from atomic in next frame
  }

  /// Toggle play/pause state.
  void togglePlayPause() {
    if (isPlaying) {
      pause();
    } else {
      play();
    }
  }

  // ===========================================================================
  // SCRUBBING — Pro Tools / Cubase style
  // ===========================================================================

  /// Start scrubbing at position.
  void startScrub(double seconds) {
    if (_activeSection == null || _activeSection == PlaybackSection.browser) {
      return;
    }
    _ffi.playbackStartScrub(seconds);
  }

  /// Update scrub position with velocity.
  void updateScrub(double seconds, double velocity) {
    if (_activeSection == null || _activeSection == PlaybackSection.browser) {
      return;
    }
    _ffi.playbackUpdateScrub(seconds, velocity);
  }

  /// Stop scrubbing.
  void stopScrub() {
    if (_activeSection == null || _activeSection == PlaybackSection.browser) {
      return;
    }
    _ffi.playbackStopScrub();
  }

  // ===========================================================================
  // RECORDING STATE
  // ===========================================================================

  /// Set recording state (called by DAW recording system)
  void setRecording(bool recording) {
    if (_isRecording == recording) return;

    _isRecording = recording;
    notifyListeners();
  }

  // ===========================================================================
  // SECTION-BASED PLAYBACK FILTERING (ENGINE-LEVEL)
  // ===========================================================================

  /// Notify engine of active section for one-shot voice filtering.
  /// This is handled in Rust engine - one-shot voices from inactive sections
  /// are silenced automatically. DAW timeline tracks are not affected.
  void _setActiveSection(PlaybackSection section) {
    // Map PlaybackSection to engine source ID
    final sourceId = switch (section) {
      PlaybackSection.daw => 0,
      PlaybackSection.slotLab => 1,
      PlaybackSection.middleware => 2,
      PlaybackSection.browser => 3,
    };
    _ffi.setActiveSection(sourceId);
  }

  // ===========================================================================
  // INTERNAL HELPERS
  // ===========================================================================

  /// Stop current section gracefully
  void _stopCurrentSection() {
    if (_activeSection == null) return;

    // Stop PLAYBACK_ENGINE
    _ffi.stop();

  }

  // ===========================================================================
  // DISPOSAL
  // ===========================================================================

  @override
  void dispose() {
    // Ensure playback is stopped
    if (_activeSection != null && _activeSection != PlaybackSection.browser) {
      _ffi.stop();
    }
    super.dispose();
  }
}
