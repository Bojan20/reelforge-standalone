/// Control Room Provider
///
/// Manages professional studio monitoring:
/// - Monitor source selection (Master, Cue 1-4, External 1-2)
/// - Monitor level, dim, mono controls
/// - Speaker selection (4 sets with calibration)
/// - Solo system (Off, SIP, AFL, PFL)
/// - Cue mixes (4 independent headphone mixes)
/// - Talkback system

import 'package:flutter/foundation.dart';
import '../src/rust/engine_api.dart' as api;

enum MonitorSource {
  master(0),
  cue1(1),
  cue2(2),
  cue3(3),
  cue4(4),
  external1(5),
  external2(6);

  final int value;
  const MonitorSource(this.value);

  static MonitorSource fromValue(int value) {
    return MonitorSource.values.firstWhere(
      (s) => s.value == value,
      orElse: () => MonitorSource.master,
    );
  }
}

enum SoloMode {
  off(0),      // No solo
  sip(1),      // Solo In Place (mutes others in main mix)
  afl(2),      // After Fade Listen (post-fader to monitor)
  pfl(3);      // Pre-Fade Listen (pre-fader to monitor)

  final int value;
  const SoloMode(this.value);

  static SoloMode fromValue(int value) {
    return SoloMode.values.firstWhere(
      (s) => s.value == value,
      orElse: () => SoloMode.off,
    );
  }
}

class CueSendInfo {
  final int channelId;
  final double level;
  final double pan;

  CueSendInfo({
    required this.channelId,
    required this.level,
    required this.pan,
  });
}

class ControlRoomProvider extends ChangeNotifier {
  // Monitor state
  MonitorSource _monitorSource = MonitorSource.master;
  double _monitorLevelDb = 0.0;
  bool _dimEnabled = false;
  bool _monoEnabled = false;

  // Speaker state
  int _activeSpeakerSet = 0;
  List<double> _speakerLevelsDb = [0.0, 0.0, 0.0, 0.0];

  // Solo state
  SoloMode _soloMode = SoloMode.off;
  Set<int> _soloedChannels = {};

  // Cue mix state (4 mixes)
  List<bool> _cueEnabled = [false, false, false, false];
  List<double> _cueLevelsDb = [0.0, 0.0, 0.0, 0.0];
  List<double> _cuePan = [0.0, 0.0, 0.0, 0.0];

  // Talkback state
  bool _talkbackEnabled = false;
  double _talkbackLevelDb = 0.0;
  int _talkbackDestinations = 0; // Bitmask: cue1=1, cue2=2, cue3=4, cue4=8

  // Metering
  double _monitorPeakL = 0.0;
  double _monitorPeakR = 0.0;

  // Getters
  MonitorSource get monitorSource => _monitorSource;
  double get monitorLevelDb => _monitorLevelDb;
  bool get dimEnabled => _dimEnabled;
  bool get monoEnabled => _monoEnabled;

  int get activeSpeakerSet => _activeSpeakerSet;
  double getSpeakerLevelDb(int index) => _speakerLevelsDb[index];

  SoloMode get soloMode => _soloMode;
  bool isChannelSoloed(int channelId) => _soloedChannels.contains(channelId);
  int get soloedCount => _soloedChannels.length;

  bool getCueEnabled(int index) => _cueEnabled[index];
  double getCueLevelDb(int index) => _cueLevelsDb[index];
  double getCuePan(int index) => _cuePan[index];

  bool get talkbackEnabled => _talkbackEnabled;
  double get talkbackLevelDb => _talkbackLevelDb;
  bool isTalkbackDestination(int cueIndex) =>
      (_talkbackDestinations & (1 << cueIndex)) != 0;

  double get monitorPeakL => _monitorPeakL;
  double get monitorPeakR => _monitorPeakR;

  /// Initialize control room (called by PlaybackEngine)
  /// control_room_ptr: Pointer to ControlRoom (from Rust)
  Future<bool> initialize(int controlRoomPtr) async {
    final result = api.controlRoomInit(controlRoomPtr);
    if (result == 1) {
      _refreshState();
      notifyListeners();
      return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MONITOR CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> setMonitorSource(MonitorSource source) async {
    final result = api.controlRoomSetMonitorSource(source.value);
    if (result == 1) {
      _monitorSource = source;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> setMonitorLevelDb(double levelDb) async {
    final result = api.controlRoomSetMonitorLevel(levelDb);
    if (result == 1) {
      _monitorLevelDb = levelDb;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> setDim(bool enabled) async {
    final result = api.controlRoomSetDim(enabled ? 1 : 0);
    if (result == 1) {
      _dimEnabled = enabled;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> setMono(bool enabled) async {
    final result = api.controlRoomSetMono(enabled ? 1 : 0);
    if (result == 1) {
      _monoEnabled = enabled;
      notifyListeners();
      return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPEAKER SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> setSpeakerSet(int index) async {
    if (index < 0 || index > 3) return false;

    final result = api.controlRoomSetSpeakerSet(index);
    if (result == 1) {
      _activeSpeakerSet = index;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> setSpeakerLevelDb(int index, double levelDb) async {
    if (index < 0 || index > 3) return false;

    final result = api.controlRoomSetSpeakerLevel(index, levelDb);
    if (result == 1) {
      _speakerLevelsDb[index] = levelDb;
      notifyListeners();
      return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOLO SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> setSoloMode(SoloMode mode) async {
    final result = api.controlRoomSetSoloMode(mode.value);
    if (result == 1) {
      _soloMode = mode;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> soloChannel(int channelId) async {
    final result = api.controlRoomSoloChannel(channelId);
    if (result == 1) {
      _soloedChannels.add(channelId);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> unsoloChannel(int channelId) async {
    final result = api.controlRoomUnsoloChannel(channelId);
    if (result == 1) {
      _soloedChannels.remove(channelId);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> toggleSolo(int channelId) async {
    if (_soloedChannels.contains(channelId)) {
      return unsoloChannel(channelId);
    } else {
      return soloChannel(channelId);
    }
  }

  Future<bool> clearSolo() async {
    final result = api.controlRoomClearSolo();
    if (result == 1) {
      _soloedChannels.clear();
      notifyListeners();
      return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CUE MIXES (4 INDEPENDENT HEADPHONE MIXES)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> setCueEnabled(int cueIndex, bool enabled) async {
    if (cueIndex < 0 || cueIndex > 3) return false;

    final result = api.controlRoomSetCueEnabled(cueIndex, enabled ? 1 : 0);
    if (result == 1) {
      _cueEnabled[cueIndex] = enabled;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> setCueLevelDb(int cueIndex, double levelDb) async {
    if (cueIndex < 0 || cueIndex > 3) return false;

    final result = api.controlRoomSetCueLevel(cueIndex, levelDb);
    if (result == 1) {
      _cueLevelsDb[cueIndex] = levelDb;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> setCuePan(int cueIndex, double pan) async {
    if (cueIndex < 0 || cueIndex > 3) return false;

    final result = api.controlRoomSetCuePan(cueIndex, pan.clamp(-1.0, 1.0));
    if (result == 1) {
      _cuePan[cueIndex] = pan;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> addCueSend({
    required int cueIndex,
    required int channelId,
    required double level,
    required double pan,
  }) async {
    if (cueIndex < 0 || cueIndex > 3) return false;

    final result = api.controlRoomAddCueSend(
      cueIndex,
      channelId,
      level.clamp(0.0, 1.0),
      pan.clamp(-1.0, 1.0),
    );
    if (result == 1) {
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> removeCueSend(int cueIndex, int channelId) async {
    if (cueIndex < 0 || cueIndex > 3) return false;

    final result = api.controlRoomRemoveCueSend(cueIndex, channelId);
    if (result == 1) {
      notifyListeners();
      return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TALKBACK
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> setTalkback(bool enabled) async {
    final result = api.controlRoomSetTalkback(enabled ? 1 : 0);
    if (result == 1) {
      _talkbackEnabled = enabled;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> setTalkbackLevelDb(double levelDb) async {
    final result = api.controlRoomSetTalkbackLevel(levelDb);
    if (result == 1) {
      _talkbackLevelDb = levelDb;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Set talkback destinations (bitmask: cue1=1, cue2=2, cue3=4, cue4=8)
  Future<bool> setTalkbackDestinations(int destinations) async {
    final result = api.controlRoomSetTalkbackDestinations(destinations);
    if (result == 1) {
      _talkbackDestinations = destinations;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> toggleTalkbackDestination(int cueIndex) async {
    if (cueIndex < 0 || cueIndex > 3) return false;

    final mask = 1 << cueIndex;
    final newDestinations = _talkbackDestinations ^ mask;
    return setTalkbackDestinations(newDestinations);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // METERING
  // ═══════════════════════════════════════════════════════════════════════════

  void updateMetering() {
    _monitorPeakL = api.controlRoomGetMonitorPeakL();
    _monitorPeakR = api.controlRoomGetMonitorPeakR();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  void _refreshState() {
    // Query current state from Rust
    _monitorSource = MonitorSource.fromValue(api.controlRoomGetMonitorSource());
    _monitorLevelDb = api.controlRoomGetMonitorLevel();
    _dimEnabled = api.controlRoomGetDim() != 0;
    _monoEnabled = api.controlRoomGetMono() != 0;
    _activeSpeakerSet = api.controlRoomGetSpeakerSet();
    _soloMode = SoloMode.fromValue(api.controlRoomGetSoloMode());
  }

  Future<void> refresh() async {
    _refreshState();
    updateMetering();
  }
}
