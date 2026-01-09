/// Recording Provider
///
/// Manages recording state:
/// - Armed tracks
/// - Recording status
/// - Output directory
/// - Recording file paths

import 'package:flutter/foundation.dart';
import '../src/rust/engine_api.dart' as api;

class RecordingProvider extends ChangeNotifier {
  // Recording state
  bool _isRecording = false;
  String _outputDir = '';
  int _armedCount = 0;
  int _recordingCount = 0;
  final Map<int, bool> _armedTracks = {};
  final Map<int, String> _recordingPaths = {};

  // Getters
  bool get isRecording => _isRecording;
  String get outputDir => _outputDir;
  int get armedCount => _armedCount;
  int get recordingCount => _recordingCount;
  bool isTrackArmed(int trackId) => _armedTracks[trackId] ?? false;
  String? getRecordingPath(int trackId) => _recordingPaths[trackId];

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
}
