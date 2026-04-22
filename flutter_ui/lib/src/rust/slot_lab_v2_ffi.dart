/// Slot Lab V2 FFI Bindings
///
/// Dart bindings for Engine V2, Scenario System, and GDD Parser.
/// Part of Slot Lab Ultimate implementation.
///
/// Usage: Access via NativeFFI.instance extension methods.

import 'dart:convert';
import 'dart:developer' as dev;
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
      dev.log('FFI: $e', name: 'SlotLabV2FFI');
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
      dev.log('FFI: $e', name: 'SlotLabV2FFI');
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
      dev.log('FFI: $e', name: 'SlotLabV2FFI');
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
      dev.log('FFI: $e', name: 'SlotLabV2FFI');
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
      dev.log('FFI: $e', name: 'SlotLabV2FFI');
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
      dev.log('FFI: $e', name: 'SlotLabV2FFI');
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
      dev.log('FFI: $e', name: 'SlotLabV2FFI');
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
      return GameModelResult.error('Exception: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO ASSET RESOLUTION — Stage→canonical asset IDs
  // ═══════════════════════════════════════════════════════════════════════════

  /// Resolve audio assets for all stages from the last spin.
  ///
  /// Returns list of stage audio bindings:
  /// ```dart
  /// [
  ///   {
  ///     "stage_index": 0,
  ///     "stage_type": "reel_stop",
  ///     "timestamp_ms": 150,
  ///     "assets": [
  ///       { "asset_id": "sfx_reel_stop_0", "category": "sfx", "looping": false, "exclusive": false }
  ///     ]
  ///   }
  /// ]
  /// ```
  List<Map<String, dynamic>> resolveAudioAssets() {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()
      >('slot_lab_resolve_audio_assets');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final ptr = fn();
      if (ptr == nullptr) return [];

      try {
        final json = ptr.toDartString();
        final list = jsonDecode(json) as List;
        return list.cast<Map<String, dynamic>>();
      } finally {
        freeFn(ptr);
      }
    } catch (e) {
      dev.log('[SlotLabFFI] resolveAudioAssets error: $e');
      return [];
    }
  }

  /// Resolve audio assets for a single stage (by JSON).
  ///
  /// Input: stage JSON, e.g. `{"type":"reel_stop","reel_index":2,"symbols":[]}`
  /// Returns list of audio asset bindings.
  List<Map<String, dynamic>> resolveStageAudio(String stageJson) {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('slot_lab_resolve_stage_audio');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final jsonPtr = stageJson.toNativeUtf8();
      try {
        final ptr = fn(jsonPtr);
        if (ptr == nullptr) return [];

        try {
          final json = ptr.toDartString();
          final list = jsonDecode(json) as List;
          return list.cast<Map<String, dynamic>>();
        } finally {
          freeFn(ptr);
        }
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      dev.log('[SlotLabFFI] resolveStageAudio error: $e');
      return [];
    }
  }

  /// Get all canonical audio asset IDs.
  ///
  /// Returns complete list of asset IDs that a game should provide.
  /// Used for completeness checking in SlotLab UI.
  List<String> getCanonicalAssetIds() {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()
      >('slot_lab_get_canonical_asset_ids');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final ptr = fn();
      if (ptr == nullptr) return [];

      try {
        final json = ptr.toDartString();
        final list = jsonDecode(json) as List;
        return list.cast<String>();
      } finally {
        freeFn(ptr);
      }
    } catch (e) {
      dev.log('[SlotLabFFI] getCanonicalAssetIds error: $e');
      return [];
    }
  }

  /// Get audio asset coverage percentage.
  ///
  /// Pass a list of asset IDs that the game provides,
  /// returns percentage of canonical assets covered (0.0 - 100.0).
  double getAudioCoverage(List<String> providedAssetIds) {
    try {
      final fn = lib.lookupFunction<
        Double Function(Pointer<Utf8>),
        double Function(Pointer<Utf8>)
      >('slot_lab_audio_coverage');

      final json = jsonEncode(providedAssetIds);
      final jsonPtr = json.toNativeUtf8();
      try {
        return fn(jsonPtr);
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      dev.log('[SlotLabFFI] getAudioCoverage error: $e');
      return 0.0;
    }
  }

  /// Get missing audio assets for provided asset list.
  ///
  /// Returns list of canonical asset IDs that are NOT in [providedAssetIds].
  /// Useful for showing which sounds a game still needs.
  List<String> getMissingAssets(List<String> providedAssetIds) {
    try {
      final fn = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('slot_lab_missing_assets');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('slot_lab_free_string');

      final json = jsonEncode(providedAssetIds);
      final jsonPtr = json.toNativeUtf8();
      try {
        final ptr = fn(jsonPtr);
        if (ptr == nullptr) return [];

        try {
          final resultJson = ptr.toDartString();
          final list = jsonDecode(resultJson) as List;
          return list.cast<String>();
        } finally {
          freeFn(ptr);
        }
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      dev.log('[SlotLabFFI] getMissingAssets error: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SONIC DNA CLASSIFIER — Zero-Click Sound Placement
  // ═══════════════════════════════════════════════════════════════════════════

  /// Klasifikuje sve audio fajlove u folderu.
  ///
  /// Vraća [SonicDnaResult] sa klasifikacijom svakog fajla, FFNC imenima,
  /// confidence score-om, i gap analizom (koji tipovi fale).
  ///
  /// Može potrajati (audio I/O + FFT). Pozovi u isolate ili sa compute().
  SonicDnaResult? classifyFolder(String folderPath) {
    try {
      final classifyFn = lib.lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('sonic_dna_classify_folder');
      final freeFn = lib.lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('sonic_dna_free_result');

      final pathPtr = folderPath.toNativeUtf8();
      Pointer<Utf8> resultPtr = nullptr;
      try {
        resultPtr = classifyFn(pathPtr);
        if (resultPtr == nullptr) return null;
        final jsonStr = resultPtr.toDartString();
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        return SonicDnaResult.fromJson(decoded);
      } finally {
        malloc.free(pathPtr);
        if (resultPtr != nullptr) {
          freeFn(resultPtr);
        }
      }
    } catch (e) {
      dev.log('[SonicDNA] classifyFolder error: $e');
      return null;
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

// ═══════════════════════════════════════════════════════════════════════════════
// SONIC DNA DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Rezultat Sonic DNA klasifikacije celog foldera
class SonicDnaResult {
  final List<SoundClassification> classifications;
  final List<String> missingTypes;
  final Map<String, int> typeCounts;
  final double avgConfidence;

  const SonicDnaResult({
    required this.classifications,
    required this.missingTypes,
    required this.typeCounts,
    required this.avgConfidence,
  });

  factory SonicDnaResult.fromJson(Map<String, dynamic> json) => SonicDnaResult(
        classifications: (json['classifications'] as List<dynamic>? ?? [])
            .map((e) => SoundClassification.fromJson(e as Map<String, dynamic>))
            .toList(),
        missingTypes: (json['missing_types'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        typeCounts: (json['type_counts'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toInt())),
        avgConfidence: (json['avg_confidence'] as num? ?? 0.0).toDouble(),
      );

  /// Broj klasifikovanih zvukova
  int get totalSounds => classifications.length;

  /// Procenat stage-ova koji imaju zvuk
  double get coveragePercent {
    const total = 15; // SlotSoundType.all().len()
    final assigned = totalSounds.clamp(0, total);
    return assigned / total;
  }

  @override
  String toString() =>
      'SonicDnaResult(${classifications.length} sounds, ${missingTypes.length} missing, '
      'confidence=${(avgConfidence * 100).toStringAsFixed(0)}%)';
}

/// Klasifikacija jednog zvuka
class SoundClassification {
  final String originalPath;
  final String soundType;
  final String ffncName;
  final double confidence;
  final int variantIndex;

  const SoundClassification({
    required this.originalPath,
    required this.soundType,
    required this.ffncName,
    required this.confidence,
    required this.variantIndex,
  });

  factory SoundClassification.fromJson(Map<String, dynamic> json) =>
      SoundClassification(
        originalPath: json['original_path'] as String? ?? '',
        soundType: json['sound_type'] as String? ?? '',
        ffncName: json['ffnc_name'] as String? ?? '',
        confidence: (json['confidence'] as num? ?? 0.0).toDouble(),
        variantIndex: (json['variant_index'] as num? ?? 0).toInt(),
      );

  /// Originalni filename bez puta
  String get originalFilename {
    final parts = originalPath.replaceAll('\\', '/').split('/');
    return parts.last;
  }

  /// Confidence kao procenat string
  String get confidencePercent =>
      '${(confidence * 100).toStringAsFixed(0)}%';

  @override
  String toString() =>
      'SoundClassification($originalFilename → $ffncName, $confidencePercent)';
}
