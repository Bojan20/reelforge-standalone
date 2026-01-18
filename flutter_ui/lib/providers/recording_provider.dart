/// Recording Provider
///
/// Manages recording state:
/// - Armed tracks
/// - Recording status
/// - Output directory
/// - Recording file paths
/// - Punch in/out
/// - Pre-roll
/// - Auto-arm

import 'package:flutter/foundation.dart';
import '../src/rust/engine_api.dart' as api;
import '../src/rust/native_ffi.dart';

/// Punch recording mode
enum PunchMode { off, punchIn, punchOut, punchInOut }

class RecordingProvider extends ChangeNotifier {
  final NativeFFI _ffi = NativeFFI.instance;

  // Recording state
  bool _isRecording = false;
  String _outputDir = '';
  int _armedCount = 0;
  int _recordingCount = 0;
  final Map<int, bool> _armedTracks = {};
  final Map<int, String> _recordingPaths = {};

  // Punch state
  PunchMode _punchMode = PunchMode.off;
  double _punchInTime = 0.0;
  double _punchOutTime = 10.0;

  // Pre-roll state
  bool _preRollEnabled = false;
  double _preRollSeconds = 2.0;
  int _preRollBars = 1;

  // Auto-arm state
  bool _autoArmEnabled = false;
  double _autoArmThresholdDb = -40.0;

  // Auto-disarm after punch-out
  bool _autoDisarmAfterPunchOut = true;

  // Getters
  bool get isRecording => _isRecording;
  String get outputDir => _outputDir;
  int get armedCount => _armedCount;
  int get recordingCount => _recordingCount;
  bool isTrackArmed(int trackId) => _armedTracks[trackId] ?? false;
  String? getRecordingPath(int trackId) => _recordingPaths[trackId];

  // Punch getters
  PunchMode get punchMode => _punchMode;
  double get punchInTime => _punchInTime;
  double get punchOutTime => _punchOutTime;
  bool get isPunchedIn => _ffi.isLoaded ? _ffi.recordingIsPunchedIn() : false;

  // Pre-roll getters
  bool get preRollEnabled => _preRollEnabled;
  double get preRollSeconds => _preRollSeconds;
  int get preRollBars => _preRollBars;

  // Auto-arm getters
  bool get autoArmEnabled => _autoArmEnabled;
  double get autoArmThresholdDb => _autoArmThresholdDb;
  bool get autoDisarmAfterPunchOut => _autoDisarmAfterPunchOut;

  /// Initialize recording system
  Future<void> initialize() async {
    // Get default output directory
    _outputDir = api.recordingGetOutputDir();
    if (_outputDir.isEmpty) {
      // Set default
      _outputDir = './recordings';
      api.recordingSetOutputDir(_outputDir);
    }
    _updateCounts();
    notifyListeners();
  }

  /// Set output directory
  Future<bool> setOutputDir(String path) async {
    if (api.recordingSetOutputDir(path)) {
      _outputDir = path;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Arm track for recording
  Future<bool> armTrack(int trackId, {int numChannels = 2}) async {
    if (api.recordingArmTrack(trackId, numChannels: numChannels)) {
      _armedTracks[trackId] = true;
      _updateCounts();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Disarm track
  Future<bool> disarmTrack(int trackId) async {
    if (api.recordingDisarmTrack(trackId)) {
      _armedTracks.remove(trackId);
      _updateCounts();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Toggle track arm state
  Future<bool> toggleArmTrack(int trackId, {int numChannels = 2}) async {
    if (isTrackArmed(trackId)) {
      return disarmTrack(trackId);
    } else {
      return armTrack(trackId, numChannels: numChannels);
    }
  }

  /// Start recording on all armed tracks
  Future<bool> startRecording() async {
    if (_armedCount == 0) return false;

    final count = api.recordingStartAll();
    if (count > 0) {
      _isRecording = true;
      _updateCounts();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Stop recording on all tracks
  Future<bool> stopRecording() async {
    final count = api.recordingStopAll();
    _isRecording = false;
    _updateCounts();
    notifyListeners();
    return count > 0;
  }

  /// Start recording on specific track
  Future<String?> startTrack(int trackId) async {
    final path = api.recordingStartTrack(trackId);
    if (path != null) {
      _recordingPaths[trackId] = path;
      _updateCounts();
      notifyListeners();
    }
    return path;
  }

  /// Stop recording on specific track
  Future<String?> stopTrack(int trackId) async {
    final path = api.recordingStopTrack(trackId);
    if (path != null) {
      _recordingPaths[trackId] = path;
      _updateCounts();
      notifyListeners();
    }
    return path;
  }

  /// Clear all recorders
  Future<void> clearAll() async {
    api.recordingClearAll();
    _armedTracks.clear();
    _recordingPaths.clear();
    _isRecording = false;
    _updateCounts();
    notifyListeners();
  }

  /// Update counts from Rust
  void _updateCounts() {
    _armedCount = api.recordingArmedCount();
    _recordingCount = api.recordingRecordingCount();
  }

  /// Refresh recording state (poll from Rust)
  Future<void> refresh() async {
    _updateCounts();
    // Check if still recording
    if (_recordingCount == 0 && _isRecording) {
      _isRecording = false;
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUNCH IN/OUT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set punch mode
  void setPunchMode(PunchMode mode) {
    _punchMode = mode;
    if (_ffi.isLoaded) {
      _ffi.recordingSetPunchMode(mode.index);
    }
    notifyListeners();
  }

  /// Set punch in time (seconds)
  void setPunchInTime(double seconds) {
    _punchInTime = seconds;
    if (_ffi.isLoaded) {
      final samples = (seconds * 48000).round(); // TODO: use actual sample rate
      _ffi.recordingSetPunchIn(samples);
    }
    notifyListeners();
  }

  /// Set punch out time (seconds)
  void setPunchOutTime(double seconds) {
    _punchOutTime = seconds;
    if (_ffi.isLoaded) {
      final samples = (seconds * 48000).round();
      _ffi.recordingSetPunchOut(samples);
    }
    notifyListeners();
  }

  /// Set both punch times
  void setPunchTimes(double punchIn, double punchOut) {
    _punchInTime = punchIn;
    _punchOutTime = punchOut;
    if (_ffi.isLoaded) {
      _ffi.recordingSetPunchTimes(punchIn, punchOut);
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRE-ROLL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable/disable pre-roll
  void setPreRollEnabled(bool enabled) {
    _preRollEnabled = enabled;
    if (_ffi.isLoaded) {
      _ffi.recordingSetPreRollEnabled(enabled);
    }
    notifyListeners();
  }

  /// Set pre-roll duration in seconds
  void setPreRollSeconds(double seconds) {
    _preRollSeconds = seconds;
    if (_ffi.isLoaded) {
      _ffi.recordingSetPreRollSeconds(seconds);
    }
    notifyListeners();
  }

  /// Set pre-roll in bars
  void setPreRollBars(int bars) {
    _preRollBars = bars;
    if (_ffi.isLoaded) {
      _ffi.recordingSetPreRollBars(bars);
    }
    notifyListeners();
  }

  /// Calculate pre-roll start position
  int getPreRollStart(int recordStart, double tempo) {
    if (!_ffi.isLoaded) return recordStart;
    return _ffi.recordingPreRollStart(recordStart, tempo);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO-ARM
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable/disable auto-arm
  void setAutoArmEnabled(bool enabled) {
    _autoArmEnabled = enabled;
    if (_ffi.isLoaded) {
      _ffi.recordingSetAutoArmEnabled(enabled);
    }
    notifyListeners();
  }

  /// Set auto-arm threshold in dB
  void setAutoArmThresholdDb(double db) {
    _autoArmThresholdDb = db;
    if (_ffi.isLoaded) {
      _ffi.recordingSetAutoArmThresholdDb(db);
    }
    notifyListeners();
  }

  /// Add track to pending auto-arm list
  void addPendingAutoArm(int trackId) {
    if (_ffi.isLoaded) {
      _ffi.recordingAddPendingAutoArm(trackId);
    }
  }

  /// Remove track from pending auto-arm list
  void removePendingAutoArm(int trackId) {
    if (_ffi.isLoaded) {
      _ffi.recordingRemovePendingAutoArm(trackId);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO-DISARM AFTER PUNCH-OUT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable/disable auto-disarm after punch-out
  void setAutoDisarmAfterPunchOut(bool enabled) {
    _autoDisarmAfterPunchOut = enabled;
    notifyListeners();
  }

  /// Called when punch-out occurs - disarms all tracks if auto-disarm is enabled
  Future<void> onPunchOut() async {
    if (_autoDisarmAfterPunchOut) {
      // Stop recording and disarm all tracks
      await stopRecording();

      // Disarm all armed tracks
      final tracksToDisarm = List<int>.from(_armedTracks.keys);
      for (final trackId in tracksToDisarm) {
        await disarmTrack(trackId);
      }
    }
  }
}
