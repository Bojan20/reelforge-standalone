/// Aux Send Provider
///
/// Extracted from MiddlewareProvider as part of Provider Decomposition.
/// Manages aux send/return routing (Wwise/FMOD-style effects buses).
///
/// Provides:
/// - Aux bus management (Reverb A/B, Delay, Slapback)
/// - Send routing from source buses to aux buses
/// - Pre/Post fader send positioning
/// - Effect parameters per aux bus

import 'package:flutter/foundation.dart';
import '../../models/advanced_middleware_models.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for managing aux send/return routing
class AuxSendProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  /// Aux bus storage
  final Map<int, AuxBus> _auxBuses = {};

  /// Send routing storage
  final Map<int, AuxSend> _sends = {};

  /// Next available send ID
  int _nextSendId = 0;

  /// Next available aux bus ID (start at 100 to avoid collision with main buses)
  int _nextAuxBusId = 100;

  AuxSendProvider({required NativeFFI ffi}) : _ffi = ffi {
    _createDefaultAuxBuses();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DEFAULT AUX BUSES
  // ═══════════════════════════════════════════════════════════════════════════

  void _createDefaultAuxBuses() {
    // Reverb A (short/room)
    _auxBuses[100] = AuxBus(
      auxBusId: 100,
      name: 'Reverb A',
      effectType: EffectType.reverb,
      effectParams: {
        'roomSize': 0.5,
        'damping': 0.4,
        'width': 1.0,
        'predelay': 20.0,
        'decay': 1.8,
      },
    );

    // Reverb B (large/hall)
    _auxBuses[101] = AuxBus(
      auxBusId: 101,
      name: 'Reverb B',
      effectType: EffectType.reverb,
      effectParams: {
        'roomSize': 0.8,
        'damping': 0.3,
        'width': 1.0,
        'predelay': 40.0,
        'decay': 4.0,
      },
    );

    // Delay (rhythmic)
    _auxBuses[102] = AuxBus(
      auxBusId: 102,
      name: 'Delay',
      effectType: EffectType.delay,
      effectParams: {
        'time': 250.0,
        'feedback': 0.3,
        'pingPong': 1.0,
        'syncToBpm': 0.0,
        'filterHigh': 6000.0,
        'filterLow': 300.0,
      },
    );

    // Slapback (short delay)
    _auxBuses[103] = AuxBus(
      auxBusId: 103,
      name: 'Slapback',
      effectType: EffectType.delay,
      effectParams: {
        'time': 80.0,
        'feedback': 0.1,
        'pingPong': 0.0,
        'syncToBpm': 0.0,
        'filterHigh': 4000.0,
        'filterLow': 500.0,
      },
    );

    _nextAuxBusId = 104;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all aux buses
  List<AuxBus> get allAuxBuses => _auxBuses.values.toList();

  /// Get all sends
  List<AuxSend> get allSends => _sends.values.toList();

  /// Get a specific aux bus
  AuxBus? getAuxBus(int auxBusId) => _auxBuses[auxBusId];

  /// Get a specific send
  AuxSend? getSend(int sendId) => _sends[sendId];

  /// Get all aux bus IDs
  List<int> get allAuxBusIds => _auxBuses.keys.toList();

  /// Get aux bus by name
  AuxBus? getAuxBusByName(String name) {
    return _auxBuses.values.where((b) => b.name == name).firstOrNull;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEND QUERIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all sends from a specific source bus
  List<AuxSend> getSendsFromBus(int sourceBusId) {
    return _sends.values.where((s) => s.sourceBusId == sourceBusId).toList();
  }

  /// Get all sends to a specific aux bus
  List<AuxSend> getSendsToAux(int auxBusId) {
    return _sends.values.where((s) => s.auxBusId == auxBusId).toList();
  }

  /// Check if a send exists between source and aux
  bool sendExists(int sourceBusId, int auxBusId) {
    return _sends.values.any(
      (s) => s.sourceBusId == sourceBusId && s.auxBusId == auxBusId,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEND MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new aux send
  AuxSend createSend({
    required int sourceBusId,
    required int auxBusId,
    double sendLevel = 0.0,
    SendPosition position = SendPosition.postFader,
  }) {
    final auxBus = _auxBuses[auxBusId];
    if (auxBus == null) throw ArgumentError('Aux bus $auxBusId not found');

    final send = AuxSend(
      sendId: _nextSendId++,
      sourceBusId: sourceBusId,
      auxBusId: auxBusId,
      name: auxBus.name,
      sendLevel: sendLevel,
      position: position,
    );

    _sends[send.sendId] = send;
    notifyListeners();
    return send;
  }

  /// Update send level
  void setSendLevel(int sendId, double level) {
    final send = _sends[sendId];
    if (send != null) {
      _sends[sendId] = send.copyWith(sendLevel: level.clamp(0.0, 1.0));
      notifyListeners();
    }
  }

  /// Toggle send enabled
  void toggleSendEnabled(int sendId) {
    final send = _sends[sendId];
    if (send != null) {
      _sends[sendId] = send.copyWith(enabled: !send.enabled);
      notifyListeners();
    }
  }

  /// Set send position (pre/post fader)
  void setSendPosition(int sendId, SendPosition position) {
    final send = _sends[sendId];
    if (send != null) {
      _sends[sendId] = send.copyWith(position: position);
      notifyListeners();
    }
  }

  /// Remove a send
  void removeSend(int sendId) {
    if (_sends.remove(sendId) != null) {
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUX BUS MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a new aux bus
  AuxBus addAuxBus({
    required String name,
    required EffectType effectType,
    Map<String, double>? effectParams,
  }) {
    final auxBus = AuxBus(
      auxBusId: _nextAuxBusId++,
      name: name,
      effectType: effectType,
      effectParams: effectParams ?? {},
    );
    _auxBuses[auxBus.auxBusId] = auxBus;
    notifyListeners();
    return auxBus;
  }

  /// Remove an aux bus (and all sends to it)
  void removeAuxBus(int auxBusId) {
    // Remove all sends to this aux bus
    _sends.removeWhere((_, send) => send.auxBusId == auxBusId);

    if (_auxBuses.remove(auxBusId) != null) {
      notifyListeners();
    }
  }

  /// Update aux bus return level
  void setAuxReturnLevel(int auxBusId, double level) {
    final auxBus = _auxBuses[auxBusId];
    if (auxBus != null) {
      auxBus.returnLevel = level.clamp(0.0, 1.0);
      notifyListeners();
    }
  }

  /// Toggle aux bus mute
  void toggleAuxMute(int auxBusId) {
    final auxBus = _auxBuses[auxBusId];
    if (auxBus != null) {
      auxBus.mute = !auxBus.mute;
      notifyListeners();
    }
  }

  /// Toggle aux bus solo
  void toggleAuxSolo(int auxBusId) {
    final auxBus = _auxBuses[auxBusId];
    if (auxBus != null) {
      auxBus.solo = !auxBus.solo;
      notifyListeners();
    }
  }

  /// Update aux effect parameter
  void setAuxEffectParam(int auxBusId, String param, double value) {
    final auxBus = _auxBuses[auxBusId];
    if (auxBus != null && auxBus.effectParams.containsKey(param)) {
      auxBus.effectParams[param] = value;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CALCULATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calculate total send contribution to an aux bus
  double calculateAuxInput(int auxBusId, Map<int, double> busLevels) {
    double total = 0.0;
    for (final send in getSendsToAux(auxBusId)) {
      if (!send.enabled) continue;

      final sourceLevel = busLevels[send.sourceBusId] ?? 0.0;
      if (send.position == SendPosition.postFader) {
        total += sourceLevel * send.sendLevel;
      } else {
        total += send.sendLevel; // Pre-fader ignores source volume
      }
    }
    return total.clamp(0.0, 1.0);
  }

  /// Calculate all aux output levels given bus levels
  Map<int, double> calculateAllAuxOutputs(Map<int, double> busLevels) {
    final outputs = <int, double>{};
    for (final auxBus in _auxBuses.values) {
      if (auxBus.mute) {
        outputs[auxBus.auxBusId] = 0.0;
      } else {
        final input = calculateAuxInput(auxBus.auxBusId, busLevels);
        outputs[auxBus.auxBusId] = input * auxBus.returnLevel;
      }
    }
    return outputs;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export to JSON
  Map<String, dynamic> toJson() {
    return {
      'auxBuses': _auxBuses.map((k, v) => MapEntry(k.toString(), {
        'auxBusId': v.auxBusId,
        'name': v.name,
        'effectType': v.effectType.index,
        'effectParams': v.effectParams,
        'returnLevel': v.returnLevel,
        'mute': v.mute,
        'solo': v.solo,
      })),
      'sends': _sends.map((k, v) => MapEntry(k.toString(), {
        'sendId': v.sendId,
        'sourceBusId': v.sourceBusId,
        'auxBusId': v.auxBusId,
        'name': v.name,
        'sendLevel': v.sendLevel,
        'position': v.position.index,
        'enabled': v.enabled,
      })),
      'nextSendId': _nextSendId,
      'nextAuxBusId': _nextAuxBusId,
    };
  }

  /// Import from JSON
  void fromJson(Map<String, dynamic> json) {
    _auxBuses.clear();
    _sends.clear();

    final auxBusesJson = json['auxBuses'] as Map<String, dynamic>?;
    if (auxBusesJson != null) {
      for (final entry in auxBusesJson.entries) {
        final data = entry.value as Map<String, dynamic>;
        final auxBus = AuxBus(
          auxBusId: data['auxBusId'] as int,
          name: data['name'] as String,
          effectType: EffectType.values[data['effectType'] as int? ?? 0],
          effectParams: (data['effectParams'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ?? {},
        );
        auxBus.returnLevel = (data['returnLevel'] as num?)?.toDouble() ?? 1.0;
        auxBus.mute = data['mute'] as bool? ?? false;
        auxBus.solo = data['solo'] as bool? ?? false;
        _auxBuses[auxBus.auxBusId] = auxBus;
      }
    }

    final sendsJson = json['sends'] as Map<String, dynamic>?;
    if (sendsJson != null) {
      for (final entry in sendsJson.entries) {
        final data = entry.value as Map<String, dynamic>;
        final send = AuxSend(
          sendId: data['sendId'] as int,
          sourceBusId: data['sourceBusId'] as int,
          auxBusId: data['auxBusId'] as int,
          name: data['name'] as String,
          sendLevel: (data['sendLevel'] as num?)?.toDouble() ?? 0.0,
          position: SendPosition.values[data['position'] as int? ?? 0],
          enabled: data['enabled'] as bool? ?? true,
        );
        _sends[send.sendId] = send;
      }
    }

    _nextSendId = json['nextSendId'] as int? ?? 0;
    _nextAuxBusId = json['nextAuxBusId'] as int? ?? 100;

    // Recreate defaults if empty
    if (_auxBuses.isEmpty) {
      _createDefaultAuxBuses();
    }

    notifyListeners();
  }
}
