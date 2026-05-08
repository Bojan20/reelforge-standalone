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

import 'package:flutter/foundation.dart';

import '../models/hrtf_models.dart';
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

  // ─── Getters ─────────────────────────────────────────────────────────────

  AnthropometricProfile get profile => _profile;
  int get sampleRate => _sampleRate;
  HrtfStatus get status => _status;
  String? get errorMessage => _errorMessage;
  HrtfDatabaseMetadata? get metadata => _metadata;
  String? get lastSavedPath => _lastSavedPath;
  String? get subjectId => _subjectId;
  bool get hasGenerated => _status == HrtfStatus.ready;

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
