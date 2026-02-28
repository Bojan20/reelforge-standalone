import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';
import '../models/aurexis_models.dart';

/// Provider for the AUREXIS™ Deterministic Slot Audio Intelligence Engine.
///
/// Manages the lifecycle of the Rust AUREXIS engine via FFI,
/// provides a tick-based update loop, and exposes the
/// [AurexisParameterMap] to UI consumers.
///
/// Register as GetIt singleton (Layer 6).
class AurexisProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  bool _initialized = false;
  AurexisParameterMap _parameters = const AurexisParameterMap();
  Timer? _tickTimer;
  int _tickIntervalMs = 50; // 20Hz default
  AurexisPlatform _platform = AurexisPlatform.desktop;
  bool _enabled = true;

  // ═══ INPUT STATE (cached for UI display) ═══
  double _volatility = 0.5;
  double _rtp = 96.0;
  double _winMultiplier = 0.0;
  double _jackpotProximity = 0.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get initialized => _initialized;
  bool get enabled => _enabled;
  AurexisParameterMap get parameters => _parameters;
  AurexisPlatform get platform => _platform;
  double get volatility => _volatility;
  double get rtp => _rtp;
  double get winMultiplier => _winMultiplier;
  double get jackpotProximity => _jackpotProximity;
  FatigueLevel get fatigueLevel => FatigueLevel.fromIndex(_parameters.fatigueIndex);
  int get tickIntervalMs => _tickIntervalMs;
  bool get isTicking => _tickTimer != null;

  // ═══════════════════════════════════════════════════════════════════════════
  // CONSTRUCTOR
  // ═══════════════════════════════════════════════════════════════════════════

  AurexisProvider({NativeFFI? ffi}) : _ffi = ffi ?? NativeFFI.instance;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize the AUREXIS engine.
  bool initialize() {
    if (_initialized) return true;

    final success = _ffi.aurexisInit();
    if (success) {
      _initialized = true;
      _ffi.aurexisSetPlatform(_platform.id);
      notifyListeners();
    }
    return success;
  }

  /// Shutdown the engine and release resources.
  void shutdown() {
    if (!_initialized) return;
    stopTickLoop();
    _ffi.aurexisDestroy();
    _initialized = false;
    _parameters = const AurexisParameterMap();
    notifyListeners();
  }

  /// Reset session state without destroying the engine.
  void resetSession() {
    if (!_initialized) return;
    _ffi.aurexisResetSession();
    _parameters = const AurexisParameterMap();
    _winMultiplier = 0.0;
    _jackpotProximity = 0.0;
    notifyListeners();
  }

  /// Enable/disable AUREXIS processing.
  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      stopTickLoop();
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TICK LOOP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start the periodic compute tick.
  void startTickLoop({int intervalMs = 50}) {
    if (!_initialized || !_enabled) return;
    _tickIntervalMs = intervalMs;
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _tick();
    });
  }

  /// Stop the tick loop.
  void stopTickLoop() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// Single tick: compute and refresh output.
  void _tick() {
    if (!_initialized || !_enabled) return;

    final json = _ffi.aurexisComputeAndGetJson(_tickIntervalMs);
    if (json != null) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _parameters = AurexisParameterMap.fromJson(map);
        notifyListeners();
      } catch (e) {
        // Silent — don't spam on parse errors
      }
    }
  }

  /// Manual single compute (for non-periodic usage).
  void compute({int elapsedMs = 50}) {
    if (!_initialized || !_enabled) return;
    _ffi.aurexisCompute(elapsedMs);
    _refreshOutput();
  }

  void _refreshOutput() {
    final json = _ffi.aurexisGetOutputJson();
    if (json != null) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _parameters = AurexisParameterMap.fromJson(map);
        notifyListeners();
      } catch (_) {}
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INPUT SETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set the volatility index (0.0 = low, 1.0 = extreme).
  void setVolatility(double index) {
    _volatility = index.clamp(0.0, 1.0);
    if (_initialized) _ffi.aurexisSetVolatility(_volatility);
  }

  /// Set the RTP percentage (85.0 - 99.5).
  void setRtp(double rtp) {
    _rtp = rtp.clamp(85.0, 99.5);
    if (_initialized) _ffi.aurexisSetRtp(_rtp);
  }

  /// Set win data.
  void setWin({
    required double amount,
    required double bet,
    double jackpotProximity = 0.0,
  }) {
    _winMultiplier = bet > 0 ? amount / bet : 0.0;
    _jackpotProximity = jackpotProximity.clamp(0.0, 1.0);
    if (_initialized) _ffi.aurexisSetWin(amount, bet, _jackpotProximity);
  }

  /// Clear win state (after win animation completes).
  void clearWin() {
    _winMultiplier = 0.0;
    _jackpotProximity = 0.0;
    if (_initialized) _ffi.aurexisSetWin(0, 1, 0);
  }

  /// Update audio metering (called from audio thread proxy).
  void setMetering(double rmsDb, double hfDb) {
    if (_initialized) _ffi.aurexisSetMetering(rmsDb, hfDb);
  }

  /// Set deterministic seed.
  void setSeed({
    required int spriteId,
    required int eventTime,
    required int gameState,
    int sessionIndex = 0,
  }) {
    if (_initialized) {
      _ffi.aurexisSetSeed(spriteId, eventTime, gameState, sessionIndex);
    }
  }

  /// Set platform type.
  void setPlatform(AurexisPlatform platform) {
    _platform = platform;
    if (_initialized) _ffi.aurexisSetPlatform(platform.id);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VOICE COLLISION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a voice for spatial collision tracking.
  bool registerVoice(int voiceId, double pan, double zDepth, int priority) {
    if (!_initialized) return false;
    return _ffi.aurexisRegisterVoice(voiceId, pan, zDepth, priority);
  }

  /// Unregister a voice.
  bool unregisterVoice(int voiceId) {
    if (!_initialized) return false;
    return _ffi.aurexisUnregisterVoice(voiceId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN EVENTS (ATTENTION VECTOR)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a screen event for attention vector calculation.
  bool registerScreenEvent(int eventId, double x, double y, {double weight = 1.0, int priority = 1}) {
    if (!_initialized) return false;
    return _ffi.aurexisRegisterScreenEvent(eventId, x, y, weight, priority);
  }

  /// Clear all screen events.
  void clearScreenEvents() {
    if (_initialized) _ffi.aurexisClearScreenEvents();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIG
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load configuration from JSON string.
  bool loadConfig(String json) {
    if (!_initialized) return false;
    return _ffi.aurexisLoadConfig(json);
  }

  /// Export current configuration as JSON.
  String? exportConfig() {
    return _ffi.aurexisExportConfig();
  }

  /// Set a single coefficient by section and key.
  bool setCoefficient(String section, String key, double value) {
    if (!_initialized) return false;
    return _ffi.aurexisSetCoefficient(section, key, value);
  }

  /// Bulk update state via JSON map.
  bool updateState(Map<String, dynamic> updates) {
    if (!_initialized) return false;
    final json = jsonEncode(updates);
    return _ffi.aurexisUpdateStateJson(json);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    stopTickLoop();
    if (_initialized) {
      _ffi.aurexisDestroy();
      _initialized = false;
    }
    super.dispose();
  }
}
