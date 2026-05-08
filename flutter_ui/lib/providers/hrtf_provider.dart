/// HRTF Provider — owns the live anthropometric profile + generated HRTF DB
///
/// Thin reactive layer over the Rust `hrtf_*` FFI surface.  Holds the
/// currently-edited profile in Dart, streams clamps through Rust to keep
/// the bound checks in one place, and exposes an explicit `generate`
/// trigger that materialises the database into Rust's global slot so
/// other providers (BinauralProvider, AutoSpatial) can immediately use it.
///
/// Persistence is via the `.ffhrtf` directory bundle format — manifest +
/// raw left/right HRIRs + positions JSON.  The same format is used by
/// the Rust `tools/convert_sofa.py` helper.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/hrtf_models.dart';
import '../services/audio_playback_service.dart';
import '../src/rust/hrtf_ffi.dart';
import '../src/rust/native_ffi.dart';

/// Status of the most recent HRTF database operation.
enum HrtfStatus {
  /// No database has been generated yet.
  none,

  /// `hrtf_generate` / `hrtf_load_ffhrtf` succeeded; metadata is current.
  ready,

  /// Last operation failed (parse error, I/O error).  See [errorMessage].
  error,
}

/// Test signals understood by the live audition pipeline.
/// Order must match `SIGNAL_*` constants in `hrtf_ffi.rs`.
enum HrtfAuditionSignal {
  pinkNoise,    // 0
  whiteNoise,   // 1
  sine440,      // 2
  sine1k,       // 3
  chirp,        // 4
}

extension HrtfAuditionSignalLabel on HrtfAuditionSignal {
  String get label {
    switch (this) {
      case HrtfAuditionSignal.pinkNoise: return 'PINK';
      case HrtfAuditionSignal.whiteNoise: return 'WHITE';
      case HrtfAuditionSignal.sine440: return '440Hz';
      case HrtfAuditionSignal.sine1k: return '1kHz';
      case HrtfAuditionSignal.chirp: return 'CHIRP';
    }
  }

  String get tooltip {
    switch (this) {
      case HrtfAuditionSignal.pinkNoise:
        return 'Pink noise — equal energy per octave; best general HRTF audition signal';
      case HrtfAuditionSignal.whiteNoise:
        return 'White noise — flat spectrum; emphasises high-frequency pinna cues';
      case HrtfAuditionSignal.sine440:
        return '440 Hz sine — A4 tone, low-frequency localisation reference';
      case HrtfAuditionSignal.sine1k:
        return '1 kHz sine — calibration tone, mid-band ITD/ILD reference';
      case HrtfAuditionSignal.chirp:
        return '200 Hz → 8 kHz log chirp — sweeps through the full pinna-cue band';
    }
  }
}

class HrtfProvider extends ChangeNotifier {
  HrtfProvider({
    AnthropometricProfile? initialProfile,
    int sampleRate = 48000,
  })  : _profile = initialProfile ?? AnthropometricProfile.cipicAverage,
        _sampleRate = sampleRate;

  // ─── State ───────────────────────────────────────────────────────────────

  AnthropometricProfile _profile;
  int _sampleRate;
  HrtfStatus _status = HrtfStatus.none;
  String? _errorMessage;
  HrtfDatabaseMetadata? _metadata;
  String? _lastSavedPath;
  String? _subjectId;

  // ─── Audition state (P1.2) ─────────────────────────────────────────────
  /// Azimuth in degrees: 0 = front, +90 = right.
  double _auditionAzimuthDeg = 30.0;

  /// Elevation in degrees: 0 = ear-level, +90 = above.
  double _auditionElevationDeg = 0.0;

  /// Test signal currently selected in the UI.
  HrtfAuditionSignal _auditionSignal = HrtfAuditionSignal.pinkNoise;

  /// Audition tone duration in milliseconds.
  int _auditionDurationMs = 600;

  /// True while the rendered WAV is being played back.
  bool _auditionPlaying = false;

  // ─── AutoSpatial integration (P1.4) ────────────────────────────────────
  /// Whether AutoSpatial should consult the HRTF database for spatial output.
  /// Mirrors `auto_spatial_get_hrtf_enabled` so the toggle is reflected
  /// across UI mounts.
  bool _autoSpatialHrtfEnabled = false;

  /// When true, an internal poll timer slaves the audition position to
  /// the most-recently-active AutoSpatial event so the user can hear
  /// what the live game is producing.
  bool _followAutoSpatialEvent = false;
  Timer? _followTimer;

  // ─── Getters ─────────────────────────────────────────────────────────────

  AnthropometricProfile get profile => _profile;
  int get sampleRate => _sampleRate;
  HrtfStatus get status => _status;
  String? get errorMessage => _errorMessage;
  HrtfDatabaseMetadata? get metadata => _metadata;
  String? get lastSavedPath => _lastSavedPath;
  String? get subjectId => _subjectId;
  bool get hasGenerated => _status == HrtfStatus.ready;

  // Audition getters
  double get auditionAzimuthDeg => _auditionAzimuthDeg;
  double get auditionElevationDeg => _auditionElevationDeg;
  HrtfAuditionSignal get auditionSignal => _auditionSignal;
  int get auditionDurationMs => _auditionDurationMs;
  bool get auditionPlaying => _auditionPlaying;

  // AutoSpatial integration getters (P1.4)
  bool get autoSpatialHrtfEnabled => _autoSpatialHrtfEnabled;
  bool get followAutoSpatialEvent => _followAutoSpatialEvent;

  // ─── Profile Mutation ────────────────────────────────────────────────────

  /// Replace the entire profile (used by preset buttons).
  /// Does NOT auto-generate the database — call [generate] explicitly.
  void setProfile(AnthropometricProfile profile) {
    if (_profile == profile) return;
    _profile = profile;
    notifyListeners();
  }

  /// Update a single anthropometric field with the supplied [value], then
  /// run the value through the Rust clamp so out-of-range edits are made
  /// visible to the UI immediately.
  void updateField({
    double? headWidthMm,
    double? headDepthMm,
    double? pinnaHeightMm,
    double? pinnaWidthMm,
    double? cavumConchaDepthMm,
    double? headCircumferenceMm,
    double? interTragalDistanceMm,
    double? noseBridgeProminenceMm,
  }) {
    final next = _profile.copyWith(
      headWidthMm: headWidthMm,
      headDepthMm: headDepthMm,
      pinnaHeightMm: pinnaHeightMm,
      pinnaWidthMm: pinnaWidthMm,
      cavumConchaDepthMm: cavumConchaDepthMm,
      headCircumferenceMm: headCircumferenceMm,
      interTragalDistanceMm: interTragalDistanceMm,
      noseBridgeProminenceMm: noseBridgeProminenceMm,
    );
    if (next == _profile) return;
    _profile = next;
    notifyListeners();
  }

  /// Push the current profile through Rust's `hrtf_clamp_profile_json`
  /// and adopt the clamped result.  Useful after a paste from clipboard
  /// or a load from a foreign config file.
  void clampToValidRange() {
    if (!_ffiAvailable()) return;
    final clamped =
        NativeFFI.instance.hrtfClampProfileJson(_profile.toJsonString());
    if (clamped == null) return;
    final next = AnthropometricProfile.fromJsonString(clamped);
    if (next == _profile) return;
    _profile = next;
    notifyListeners();
  }

  /// Change the target sample rate.  Existing database is invalidated.
  void setSampleRate(int hz) {
    if (_sampleRate == hz) return;
    _sampleRate = hz;
    _status = HrtfStatus.none;
    _metadata = null;
    notifyListeners();
  }

  // ─── Pipeline Actions ────────────────────────────────────────────────────

  /// Generate the personalized HRTF database from the current profile.
  /// On success the Rust global state is populated and downstream
  /// renderers (BinauralRenderer) can use it on the next render call.
  Future<bool> generate() async {
    if (!_ffiAvailable()) {
      return _fail('FFI not available');
    }
    final rc = NativeFFI.instance
        .hrtfGenerate(_profile.toJsonString(), _sampleRate);
    if (rc != 0) {
      return _fail('hrtf_generate returned $rc');
    }
    return _refreshMetadata();
  }

  /// Generate using the Rust default profile (CIPIC average).  Faster
  /// than [generate] when the user has not customised the profile yet.
  Future<bool> generateDefault() async {
    if (!_ffiAvailable()) {
      return _fail('FFI not available');
    }
    final rc = NativeFFI.instance.hrtfGenerateDefault(_sampleRate);
    if (rc != 0) {
      return _fail('hrtf_generate_default returned $rc');
    }
    return _refreshMetadata();
  }

  /// Save the current database to a `.ffhrtf` directory bundle.
  /// Returns `true` on success.  Sets [errorMessage] on failure.
  Future<bool> saveFfhrtf(String path, {String subjectId = 'custom'}) async {
    if (!_ffiAvailable()) return _fail('FFI not available');
    final rc = NativeFFI.instance.hrtfSaveFfhrtf(path, subjectId);
    switch (rc) {
      case 0:
        _lastSavedPath = path;
        _subjectId = subjectId;
        _errorMessage = null;
        notifyListeners();
        return true;
      case -1:
        return _fail('No HRTF database to save (call generate() first)');
      case -2:
        return _fail('I/O error while writing $path');
      default:
        return _fail('hrtf_save_ffhrtf returned $rc');
    }
  }

  /// Load a `.ffhrtf` directory and replace the live database.
  Future<bool> loadFfhrtf(String path) async {
    if (!_ffiAvailable()) return _fail('FFI not available');
    final rc = NativeFFI.instance.hrtfLoadFfhrtf(path);
    if (rc != 0) {
      return _fail('hrtf_load_ffhrtf returned $rc');
    }
    _lastSavedPath = path;
    return _refreshMetadata();
  }

  // ─── Bundled presets (P1.3) ──────────────────────────────────────────────

  /// Resolve the on-disk root that holds the three default presets.
  /// We use the same Application Support directory used by other persistent
  /// state, so users can browse to it from the SAVE dialog if they want.
  String get _defaultPresetsRoot {
    final home = Platform.environment['HOME'] ?? '/tmp';
    return '$home/Library/Application Support/FluxForge Studio/hrtf/presets';
  }

  /// True if all three default presets already exist on disk.
  bool get hasDefaultPresets {
    final root = Directory(_defaultPresetsRoot);
    if (!root.existsSync()) return false;
    for (final n in const ['small', 'average', 'large']) {
      if (!Directory('${root.path}/$n').existsSync()) return false;
      if (!File('${root.path}/$n/manifest.json').existsSync()) return false;
    }
    return true;
  }

  /// Generate the three canonical presets if they aren't already installed.
  /// Idempotent — if all three exist on disk this returns `true` without
  /// touching the filesystem.
  Future<bool> installDefaultPresets({bool force = false}) async {
    if (!_ffiAvailable()) return _fail('FFI not available');
    if (!force && hasDefaultPresets) return true;

    final root = Directory(_defaultPresetsRoot);
    try {
      await root.create(recursive: true);
    } catch (e) {
      return _fail('Could not create presets dir: $e');
    }

    final rc = NativeFFI.instance
        .hrtfSaveDefaultPresets(_defaultPresetsRoot, _sampleRate);
    if (rc != 0) {
      return _fail('hrtf_save_default_presets returned $rc');
    }
    notifyListeners();
    return true;
  }

  /// Load one of the bundled presets by name (`small`, `average`, `large`).
  /// Auto-installs the bundle on first call so a fresh app always has
  /// these three available.
  Future<bool> loadBundledPreset(String name) async {
    if (!const ['small', 'average', 'large'].contains(name)) {
      return _fail('Unknown bundled preset: $name');
    }
    if (!hasDefaultPresets) {
      final installed = await installDefaultPresets();
      if (!installed) return false;
    }
    // Sync the editor profile to match what we are loading so the UI
    // sliders reflect the bundled measurements.
    final mirrored = switch (name) {
      'small' => AnthropometricProfile.small,
      'large' => AnthropometricProfile.large,
      _ => AnthropometricProfile.cipicAverage,
    };
    setProfile(mirrored);
    return loadFfhrtf('$_defaultPresetsRoot/$name');
  }

  // ─── Audition (P1.2) ─────────────────────────────────────────────────────

  /// Update the audition source position.  Each axis is clamped to the
  /// HRTF database's supported range.
  void setAuditionPosition({double? azimuthDeg, double? elevationDeg}) {
    final az = (azimuthDeg ?? _auditionAzimuthDeg).clamp(-180.0, 180.0);
    final el = (elevationDeg ?? _auditionElevationDeg).clamp(-40.0, 90.0);
    if (az == _auditionAzimuthDeg && el == _auditionElevationDeg) return;
    _auditionAzimuthDeg = az;
    _auditionElevationDeg = el;
    notifyListeners();
  }

  /// Pick which test signal will be rendered on the next [playAudition].
  void setAuditionSignal(HrtfAuditionSignal signal) {
    if (_auditionSignal == signal) return;
    _auditionSignal = signal;
    notifyListeners();
  }

  /// Set the audition duration in milliseconds (clamped to [50, 5000]).
  void setAuditionDurationMs(int ms) {
    final clamped = ms.clamp(50, 5000);
    if (_auditionDurationMs == clamped) return;
    _auditionDurationMs = clamped;
    notifyListeners();
  }

  /// Render the test signal through the HRTF database to a temp WAV file
  /// and play it through the existing AudioPlaybackService.
  ///
  /// Requires [hasGenerated] — call [generate] / [generateDefault] first.
  /// Returns `true` when playback was initiated successfully.
  Future<bool> playAudition() async {
    if (!_ffiAvailable()) return _fail('FFI not available');
    if (!hasGenerated) {
      return _fail('Generate the HRTF database before auditioning');
    }

    // Render to a per-process temp WAV — overwriting it each call so the
    // disk footprint stays at one file.
    final tmpDir = Directory.systemTemp.path;
    final wavPath = '$tmpDir/fluxforge_hrtf_audition.wav';
    final rc = NativeFFI.instance.hrtfAuditionRenderToWav(
      azimuthDeg: _auditionAzimuthDeg,
      elevationDeg: _auditionElevationDeg,
      signalType: _auditionSignal.index,
      durationMs: _auditionDurationMs,
      outPath: wavPath,
    );
    switch (rc) {
      case 0:
        break;
      case -1:
        return _fail('No HRTF database loaded');
      case -2:
        return _fail('Invalid audition arguments');
      case -3:
        return _fail('Audition render failed');
      case -4:
        return _fail('Audition WAV write failed');
      default:
        return _fail('Audition returned $rc');
    }

    // Hand off to the existing playback service.  We use bus 0 (master)
    // and a very-short PlaybackSource so it doesn't fight the DAW
    // transport.
    final voice = AudioPlaybackService.instance.playFileToBus(
      wavPath,
      volume: 0.85,
      pan: 0.0,
      busId: 0,
      source: PlaybackSource.browser,
      eventId: 'hrtf_audition',
    );
    if (voice < 0) {
      return _fail('Playback service rejected the WAV (voice=$voice)');
    }
    _auditionPlaying = true;
    _errorMessage = null;
    notifyListeners();

    // Auto-clear the playing flag after the audition has run its course.
    // We don't actually stop the voice — playback service marks it
    // inactive when the file ends.
    Future.delayed(Duration(milliseconds: _auditionDurationMs + 50), () {
      if (_auditionPlaying) {
        _auditionPlaying = false;
        notifyListeners();
      }
    });

    return true;
  }

  // ─── AutoSpatial integration (P1.4) ──────────────────────────────────────

  /// Toggle whether the AutoSpatial engine consults the HRTF database
  /// for its `hrtf_azimuth` / `hrtf_elevation` outputs.  Reads back the
  /// effective state via `auto_spatial_get_hrtf_enabled` so the UI mirror
  /// agrees with the engine even if FFI fails silently.
  void setAutoSpatialHrtfEnabled(bool enabled) {
    if (!_ffiAvailable()) return;
    NativeFFI.instance.autoSpatialSetHrtfEnabled(enabled);
    _autoSpatialHrtfEnabled =
        NativeFFI.instance.autoSpatialGetHrtfEnabled();
    notifyListeners();
  }

  /// Sync the local mirror of the AutoSpatial HRTF flag from the engine.
  /// Useful at panel mount — engine state may already be `true` from a
  /// prior session.
  void syncAutoSpatialHrtfMirror() {
    if (!_ffiAvailable()) return;
    final fresh = NativeFFI.instance.autoSpatialGetHrtfEnabled();
    if (fresh == _autoSpatialHrtfEnabled) return;
    _autoSpatialHrtfEnabled = fresh;
    notifyListeners();
  }

  /// Toggle FOLLOW EVENT mode — when enabled, a 250 ms timer reads the
  /// most-recently-active AutoSpatial event and copies its HRTF angles
  /// into the audition position so the user hears whatever the live
  /// game is producing.
  void setFollowAutoSpatialEvent(bool enabled) {
    if (_followAutoSpatialEvent == enabled) return;
    _followAutoSpatialEvent = enabled;
    _followTimer?.cancel();
    _followTimer = null;
    if (enabled) {
      _followTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _followTick(),
      );
    }
    notifyListeners();
  }

  void _followTick() {
    if (!_ffiAvailable()) return;
    final ffi = NativeFFI.instance;
    final eventId = ffi.autoSpatialLatestActiveEvent();
    if (eventId == 0) return;
    final out = ffi.autoSpatialGetOutput(eventId);
    if (out == null) return;
    setAuditionPosition(
      azimuthDeg: out.hrtfAzimuth,
      elevationDeg: out.hrtfElevation,
    );
  }

  @override
  void dispose() {
    _followTimer?.cancel();
    _followTimer = null;
    super.dispose();
  }

  /// Force-stop any in-flight audition voice.  Safe to call when nothing
  /// is playing — it's a no-op.
  void stopAudition() {
    if (!_auditionPlaying) return;
    try {
      AudioPlaybackService.instance.stopEvent('hrtf_audition');
    } catch (_) {
      // Service may not be ready in test mode — ignore.
    }
    _auditionPlaying = false;
    notifyListeners();
  }

  // ─── Internal ────────────────────────────────────────────────────────────

  bool _refreshMetadata() {
    final json = NativeFFI.instance.hrtfMetadataJson();
    if (json == null) {
      return _fail('Database metadata unavailable after generate()');
    }
    _metadata = HrtfDatabaseMetadata.fromJsonString(json);
    _status = HrtfStatus.ready;
    _errorMessage = null;
    notifyListeners();
    return true;
  }

  bool _fail(String msg) {
    _status = HrtfStatus.error;
    _errorMessage = msg;
    notifyListeners();
    return false;
  }

  bool _ffiAvailable() {
    try {
      return NativeFFI.instance.isLoaded;
    } catch (_) {
      return false;
    }
  }
}
