/// Slot Lab V2 FFI Bindings
///
/// Dart bindings for Engine V2, Scenario System, and GDD Parser.
/// Part of Slot Lab Ultimate implementation.
///
/// Usage: Access via NativeFFI.instance extension methods.

import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SLOT LAB V2 EXTENSION
// ═══════════════════════════════════════════════════════════════════════════════

/// Extension on NativeFFI for Slot Lab V2 functions
extension SlotLabV2FFI on NativeFFI {
  // ═══════════════════════════════════════════════════════════════════════════
  // ENGINE V2 — GameModel-driven engine
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize Engine V2 with default 5x3 game model
  /// Returns true on success
  bool slotLabV2Init() {
    try {
      final fn = lib.lookupFunction<Int32 Function(), int Function()>(
        'slot_lab_v2_init',
      );
      return fn() == 1;
    } catch (e) {
      print('[SlotLabV2] slotLabV2Init error: $e');
      return false;
    }
  }

  /// Initialize Engine V2 with a GameModel from JSON
  /// Returns true on success
  bool slotLabV2InitWithModelJson(String modelJson) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)
      >('slot_lab_v2_init_with_model_json');

      final jsonPtr = modelJson.toNativeUtf8();
      try {
        return fn(jsonPtr) == 1;
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabV2InitWithModelJson error: $e');
      return false;
    }
  }

  /// Initialize Engine V2 from a GDD (Game Design Document) JSON
  /// Returns true on success
  bool slotLabV2InitFromGdd(String gddJson) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)
      >('slot_lab_v2_init_from_gdd');

      final jsonPtr = gddJson.toNativeUtf8();
      try {
        return fn(jsonPtr) == 1;
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabV2InitFromGdd error: $e');
      return false;
    }
  }

  /// Shutdown Engine V2
  void slotLabV2Shutdown() {
    try {
      final fn = lib.lookupFunction<Void Function(), void Function()>(
        'slot_lab_v2_shutdown',
      );
      fn();
    } catch (e) {
      print('[SlotLabV2] slotLabV2Shutdown error: $e');
    }
  }

  /// Check if Engine V2 is initialized
  bool slotLabV2IsInitialized() {
    try {
      final fn = lib.lookupFunction<Int32 Function(), int Function()>(
        'slot_lab_v2_is_initialized',
      );
      return fn() == 1;
    } catch (e) {
      print('[SlotLabV2] slotLabV2IsInitialized error: $e');
      return false;
    }
  }

  /// Execute a spin with Engine V2
  /// Returns spin ID (0 if failed)
  int slotLabV2Spin() {
    try {
      final fn = lib.lookupFunction<Uint64 Function(), int Function()>(
        'slot_lab_v2_spin',
      );
      return fn();
    } catch (e) {
      print('[SlotLabV2] slotLabV2Spin error: $e');
      return 0;
    }
  }

  /// Execute a forced spin with Engine V2
  /// Returns spin ID (0 if failed)
  int slotLabV2SpinForced(int outcome) {
    try {
      final fn = lib.lookupFunction<
        Uint64 Function(Int32),
        int Function(int)
      >('slot_lab_v2_spin_forced');
      return fn(outcome);
    } catch (e) {
      print('[SlotLabV2] slotLabV2SpinForced error: $e');
      return 0;
    }
  }

  /// Get Engine V2 spin result as parsed JSON
  Map<String, dynamic>? slotLabV2GetSpinResult() {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()
      >('slot_lab_v2_get_spin_result_json');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final ptr = fn();
      if (ptr == nullptr) return null;

      try {
        final json = ptr.toDartString();
        if (json.isEmpty || json == '{}') return null;
        return jsonDecode(json) as Map<String, dynamic>;
      } finally {
        freeFn(ptr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabV2GetSpinResult error: $e');
      return null;
    }
  }

  /// Get Engine V2 stages as parsed JSON array
  List<Map<String, dynamic>> slotLabV2GetStages() {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()
      >('slot_lab_v2_get_stages_json');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final ptr = fn();
      if (ptr == nullptr) return [];

      try {
        final json = ptr.toDartString();
        if (json.isEmpty || json == '[]') return [];
        final list = jsonDecode(json) as List;
        return list.cast<Map<String, dynamic>>();
      } finally {
        freeFn(ptr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabV2GetStages error: $e');
      return [];
    }
  }

  /// Get Engine V2 game model as parsed JSON
  Map<String, dynamic>? slotLabV2GetModel() {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()
      >('slot_lab_v2_get_model_json');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final ptr = fn();
      if (ptr == nullptr) return null;

      try {
        final json = ptr.toDartString();
        if (json.isEmpty || json == '{}') return null;
        return jsonDecode(json) as Map<String, dynamic>;
      } finally {
        freeFn(ptr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabV2GetModel error: $e');
      return null;
    }
  }

  /// Get Engine V2 stats as parsed JSON
  Map<String, dynamic>? slotLabV2GetStats() {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()
      >('slot_lab_v2_get_stats_json');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final ptr = fn();
      if (ptr == nullptr) return null;

      try {
        final json = ptr.toDartString();
        if (json.isEmpty || json == '{}') return null;
        return jsonDecode(json) as Map<String, dynamic>;
      } finally {
        freeFn(ptr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabV2GetStats error: $e');
      return null;
    }
  }

  /// Set Engine V2 game mode
  /// mode: 0 = GddOnly, 1 = MathDriven
  void slotLabV2SetMode(int mode) {
    try {
      final fn = lib.lookupFunction<
        Void Function(Int32),
        void Function(int)
      >('slot_lab_v2_set_mode');
      fn(mode);
    } catch (e) {
      print('[SlotLabV2] slotLabV2SetMode error: $e');
    }
  }

  /// Set Engine V2 bet amount
  void slotLabV2SetBet(double bet) {
    try {
      final fn = lib.lookupFunction<
        Void Function(Double),
        void Function(double)
      >('slot_lab_v2_set_bet');
      fn(bet);
    } catch (e) {
      print('[SlotLabV2] slotLabV2SetBet error: $e');
    }
  }

  /// Seed Engine V2 RNG
  void slotLabV2Seed(int seed) {
    try {
      final fn = lib.lookupFunction<
        Void Function(Uint64),
        void Function(int)
      >('slot_lab_v2_seed');
      fn(seed);
    } catch (e) {
      print('[SlotLabV2] slotLabV2Seed error: $e');
    }
  }

  /// Reset Engine V2 stats
  void slotLabV2ResetStats() {
    try {
      final fn = lib.lookupFunction<Void Function(), void Function()>(
        'slot_lab_v2_reset_stats',
      );
      fn();
    } catch (e) {
      print('[SlotLabV2] slotLabV2ResetStats error: $e');
    }
  }

  /// Get win tier name from last V2 spin
  String? slotLabV2LastWinTier() {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()
      >('slot_lab_v2_last_win_tier');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final ptr = fn();
      if (ptr == nullptr) return null;

      try {
        final str = ptr.toDartString();
        return str.isEmpty ? null : str;
      } finally {
        freeFn(ptr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabV2LastWinTier error: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// List all available scenarios
  List<ScenarioInfo> slotLabScenarioList() {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()
      >('slot_lab_scenario_list_json');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final ptr = fn();
      if (ptr == nullptr) return [];

      try {
        final json = ptr.toDartString();
        if (json.isEmpty || json == '[]') return [];
        final list = jsonDecode(json) as List;
        return list.map((e) => ScenarioInfo.fromJson(e as Map<String, dynamic>)).toList();
      } finally {
        freeFn(ptr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabScenarioList error: $e');
      return [];
    }
  }

  /// Load a scenario by ID for playback
  /// Returns true on success
  bool slotLabScenarioLoad(String id) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)
      >('slot_lab_scenario_load');

      final idPtr = id.toNativeUtf8();
      try {
        return fn(idPtr) == 1;
      } finally {
        calloc.free(idPtr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabScenarioLoad error: $e');
      return false;
    }
  }

  /// Check if a scenario is currently loaded
  bool slotLabScenarioIsLoaded() {
    try {
      final fn = lib.lookupFunction<Int32 Function(), int Function()>(
        'slot_lab_scenario_is_loaded',
      );
      return fn() == 1;
    } catch (e) {
      print('[SlotLabV2] slotLabScenarioIsLoaded error: $e');
      return false;
    }
  }

  /// Get the next spin from the loaded scenario
  ScriptedSpin? slotLabScenarioNextSpin() {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()
      >('slot_lab_scenario_next_spin_json');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final ptr = fn();
      if (ptr == nullptr) return null;

      try {
        final json = ptr.toDartString();
        if (json.isEmpty || json == '{}') return null;
        return ScriptedSpin.fromJson(jsonDecode(json) as Map<String, dynamic>);
      } finally {
        freeFn(ptr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabScenarioNextSpin error: $e');
      return null;
    }
  }

  /// Get current playback progress
  /// Returns (current, total) tuple
  (int, int) slotLabScenarioProgress() {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()
      >('slot_lab_scenario_progress');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final ptr = fn();
      if (ptr == nullptr) return (0, 0);

      try {
        final str = ptr.toDartString();
        final parts = str.split(',');
        if (parts.length != 2) return (0, 0);
        return (int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
      } finally {
        freeFn(ptr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabScenarioProgress error: $e');
      return (0, 0);
    }
  }

  /// Check if scenario playback is complete
  bool slotLabScenarioIsComplete() {
    try {
      final fn = lib.lookupFunction<Int32 Function(), int Function()>(
        'slot_lab_scenario_is_complete',
      );
      return fn() == 1;
    } catch (e) {
      print('[SlotLabV2] slotLabScenarioIsComplete error: $e');
      return false;
    }
  }

  /// Reset scenario playback to beginning
  void slotLabScenarioReset() {
    try {
      final fn = lib.lookupFunction<Void Function(), void Function()>(
        'slot_lab_scenario_reset',
      );
      fn();
    } catch (e) {
      print('[SlotLabV2] slotLabScenarioReset error: $e');
    }
  }

  /// Unload the current scenario
  void slotLabScenarioUnload() {
    try {
      final fn = lib.lookupFunction<Void Function(), void Function()>(
        'slot_lab_scenario_unload',
      );
      fn();
    } catch (e) {
      print('[SlotLabV2] slotLabScenarioUnload error: $e');
    }
  }

  /// Register a custom scenario from JSON
  /// Returns true on success
  bool slotLabScenarioRegister(String scenarioJson) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)
      >('slot_lab_scenario_register_json');

      final jsonPtr = scenarioJson.toNativeUtf8();
      try {
        return fn(jsonPtr) == 1;
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabScenarioRegister error: $e');
      return false;
    }
  }

  /// Get a scenario by ID
  DemoScenario? slotLabScenarioGet(String id) {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('slot_lab_scenario_get_json');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final idPtr = id.toNativeUtf8();
      try {
        final ptr = fn(idPtr);
        if (ptr == nullptr) return null;

        try {
          final json = ptr.toDartString();
          if (json.isEmpty || json == '{}') return null;
          return DemoScenario.fromJson(jsonDecode(json) as Map<String, dynamic>);
        } finally {
          freeFn(ptr);
        }
      } finally {
        calloc.free(idPtr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabScenarioGet error: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GDD PARSER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Validate a GDD JSON
  /// Returns validation result with errors list
  GddValidationResult slotLabGddValidate(String gddJson) {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('slot_lab_gdd_validate');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final jsonPtr = gddJson.toNativeUtf8();
      try {
        final ptr = fn(jsonPtr);
        if (ptr == nullptr) {
          return GddValidationResult(valid: false, errors: ['FFI call failed']);
        }

        try {
          final json = ptr.toDartString();
          final map = jsonDecode(json) as Map<String, dynamic>;
          return GddValidationResult.fromJson(map);
        } finally {
          freeFn(ptr);
        }
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabGddValidate error: $e');
      return GddValidationResult(valid: false, errors: ['Exception: $e']);
    }
  }

  /// Convert a GDD JSON to a GameModel
  /// Returns GameModel JSON or error
  GameModelResult slotLabGddToModel(String gddJson) {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('slot_lab_gdd_to_model');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final jsonPtr = gddJson.toNativeUtf8();
      try {
        final ptr = fn(jsonPtr);
        if (ptr == nullptr) {
          return GameModelResult.error('FFI call failed');
        }

        try {
          final json = ptr.toDartString();
          final map = jsonDecode(json) as Map<String, dynamic>;

          if (map.containsKey('error')) {
            return GameModelResult.error(map['error'] as String);
          }

          return GameModelResult.success(map);
        } finally {
          freeFn(ptr);
        }
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      print('[SlotLabV2] slotLabGddToModel error: $e');
      return GameModelResult.error('Exception: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Scenario info for listing
class ScenarioInfo {
  final String id;
  final String name;
  final String description;
  final int spinCount;
  final String loopMode;

  const ScenarioInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.spinCount,
    required this.loopMode,
  });

  factory ScenarioInfo.fromJson(Map<String, dynamic> json) {
    return ScenarioInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      spinCount: json['spin_count'] as int? ?? 0,
      loopMode: json['loop_mode'] as String? ?? 'once',
    );
  }
}

/// Demo scenario
class DemoScenario {
  final String id;
  final String name;
  final String description;
  final List<ScriptedSpin> sequence;
  final String loopMode;

  const DemoScenario({
    required this.id,
    required this.name,
    required this.description,
    required this.sequence,
    required this.loopMode,
  });

  factory DemoScenario.fromJson(Map<String, dynamic> json) {
    final sequenceJson = json['sequence'] as List? ?? [];
    return DemoScenario(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      sequence: sequenceJson.map((e) => ScriptedSpin.fromJson(e as Map<String, dynamic>)).toList(),
      loopMode: json['loop_mode'] as String? ?? 'once',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'sequence': sequence.map((e) => e.toJson()).toList(),
    'loop_mode': loopMode,
  };
}

/// Scripted spin in a scenario
class ScriptedSpin {
  final Map<String, dynamic> outcome;
  final double? delayBeforeMs;
  final String? note;

  const ScriptedSpin({
    required this.outcome,
    this.delayBeforeMs,
    this.note,
  });

  factory ScriptedSpin.fromJson(Map<String, dynamic> json) {
    return ScriptedSpin(
      outcome: json['outcome'] as Map<String, dynamic>? ?? {},
      delayBeforeMs: (json['delay_before_ms'] as num?)?.toDouble(),
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'outcome': outcome,
    if (delayBeforeMs != null) 'delay_before_ms': delayBeforeMs,
    if (note != null) 'note': note,
  };
}

/// GDD validation result
class GddValidationResult {
  final bool valid;
  final List<String> errors;

  const GddValidationResult({
    required this.valid,
    required this.errors,
  });

  factory GddValidationResult.fromJson(Map<String, dynamic> json) {
    final errorsList = json['errors'] as List? ?? [];
    return GddValidationResult(
      valid: json['valid'] as bool? ?? false,
      errors: errorsList.map((e) => e.toString()).toList(),
    );
  }
}

/// GameModel conversion result
class GameModelResult {
  final Map<String, dynamic>? model;
  final String? errorMessage;

  const GameModelResult._({this.model, this.errorMessage});

  factory GameModelResult.success(Map<String, dynamic> model) {
    return GameModelResult._(model: model);
  }

  factory GameModelResult.error(String message) {
    return GameModelResult._(errorMessage: message);
  }

  bool get isSuccess => model != null;
  bool get isError => errorMessage != null;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

/// Game mode for Engine V2
enum SlotLabGameMode {
  /// GDD-only mode (scripted outcomes)
  gddOnly(0),
  /// Math-driven mode (real probability)
  mathDriven(1);

  final int value;
  const SlotLabGameMode(this.value);
}

/// Forced outcome types for Engine V2 testing
enum ForcedOutcomeV2 {
  lose(0),
  smallWin(1),
  mediumWin(2),
  bigWin(3),
  megaWin(4),
  epicWin(5),
  ultraWin(6),
  freeSpins(7),
  jackpotMini(8),
  jackpotMinor(9),
  jackpotMajor(10),
  jackpotGrand(11),
  nearMiss(12),
  cascade(13);

  final int value;
  const ForcedOutcomeV2(this.value);
}
