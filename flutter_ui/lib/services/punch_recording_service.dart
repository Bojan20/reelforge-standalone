// punch_recording_service.dart — Punch-In/Punch-Out Recording
// Part of DAW P2 Audio Tools — Professional punch recording workflow

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Punch recording mode
enum PunchMode {
  manual,      // User triggers punch in/out
  auto,        // Auto-punch within loop range
  rehearsal,   // Practice mode (no recording)
}

/// Punch recording state
enum PunchRecordingState {
  idle,
  preRoll,     // Pre-roll countdown
  recording,   // Active recording
  postRoll,    // Post-roll
  stopped,
}

/// Punch recording configuration
class PunchRecordingConfig {
  final PunchMode mode;
  final double preRollSeconds;
  final double postRollSeconds;
  final double punchInTime;
  final double punchOutTime;
  final bool countInEnabled;
  final int countInBars;

  const PunchRecordingConfig({
    this.mode = PunchMode.auto,
    this.preRollSeconds = 2.0,
    this.postRollSeconds = 1.0,
    required this.punchInTime,
    required this.punchOutTime,
    this.countInEnabled = true,
    this.countInBars = 1,
  });
}

/// Punch recording service (singleton)
class PunchRecordingService extends ChangeNotifier {
  static final instance = PunchRecordingService._();
  PunchRecordingService._();

  PunchRecordingState _state = PunchRecordingState.idle;
  PunchRecordingConfig? _config;
  double _currentPosition = 0.0;
  Timer? _timer;

  void Function()? onPunchIn;
  void Function()? onPunchOut;

  PunchRecordingState get state => _state;
  bool get isRecording => _state == PunchRecordingState.recording;

  void startRecording(PunchRecordingConfig config) {
    _config = config;
    _currentPosition = config.punchInTime - config.preRollSeconds;
    _state = PunchRecordingState.preRoll;
    _timer = Timer.periodic(const Duration(milliseconds: 16), _tick);
    notifyListeners();
  }

  void _tick(Timer t) {
    _currentPosition += 0.016;
    if (_state == PunchRecordingState.preRoll && _currentPosition >= _config!.punchInTime) {
      _state = PunchRecordingState.recording;
      onPunchIn?.call();
      notifyListeners();
    }
    if (_state == PunchRecordingState.recording && _currentPosition >= _config!.punchOutTime) {
      _state = PunchRecordingState.postRoll;
      onPunchOut?.call();
      notifyListeners();
    }
    if (_state == PunchRecordingState.postRoll && _currentPosition >= _config!.punchOutTime + _config!.postRollSeconds) {
      stopRecording();
    }
  }

  void stopRecording() {
    _timer?.cancel();
    _state = PunchRecordingState.stopped;
    Future.delayed(const Duration(milliseconds: 500), () {
      _state = PunchRecordingState.idle;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
