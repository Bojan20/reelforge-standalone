/// Template Auto-Wire Service
///
/// Master orchestrator that connects all template components to the audio system.
/// When a template is applied, this service wires EVERYTHING automatically.
///
/// P3-12: Template Gallery
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../models/template_models.dart';
import '../../providers/subsystems/rtpc_system_provider.dart';
import '../event_registry.dart';
import '../service_locator.dart';
import 'stage_auto_registrar.dart';
import 'event_auto_registrar.dart';
import 'bus_auto_configurator.dart';
import 'ducking_auto_configurator.dart';
import 'ale_auto_configurator.dart';
import 'rtpc_auto_configurator.dart';
import 'template_validation_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WIRE RESULT
// ═══════════════════════════════════════════════════════════════════════════

/// Result of wiring operation
class WireResult {
  final bool success;
  final String? error;
  final WireStats stats;
  final ValidationReport? validationReport;
  final Duration duration;

  const WireResult({
    required this.success,
    this.error,
    required this.stats,
    this.validationReport,
    required this.duration,
  });

  factory WireResult.failure(String error, Duration duration) => WireResult(
        success: false,
        error: error,
        stats: const WireStats(),
        duration: duration,
      );
}

/// Statistics from wiring operation
class WireStats {
  final int stagesRegistered;
  final int eventsCreated;
  final int busesConfigured;
  final int duckingRulesAdded;
  final int aleContextsConfigured;
  final int rtpcParametersConfigured;
  final int unmappedStages;

  const WireStats({
    this.stagesRegistered = 0,
    this.eventsCreated = 0,
    this.busesConfigured = 0,
    this.duckingRulesAdded = 0,
    this.aleContextsConfigured = 0,
    this.rtpcParametersConfigured = 0,
    this.unmappedStages = 0,
  });

  WireStats copyWith({
    int? stagesRegistered,
    int? eventsCreated,
    int? busesConfigured,
    int? duckingRulesAdded,
    int? aleContextsConfigured,
    int? rtpcParametersConfigured,
    int? unmappedStages,
  }) =>
      WireStats(
        stagesRegistered: stagesRegistered ?? this.stagesRegistered,
        eventsCreated: eventsCreated ?? this.eventsCreated,
        busesConfigured: busesConfigured ?? this.busesConfigured,
        duckingRulesAdded: duckingRulesAdded ?? this.duckingRulesAdded,
        aleContextsConfigured: aleContextsConfigured ?? this.aleContextsConfigured,
        rtpcParametersConfigured: rtpcParametersConfigured ?? this.rtpcParametersConfigured,
        unmappedStages: unmappedStages ?? this.unmappedStages,
      );

  @override
  String toString() => '''WireStats:
  - Stages registered: $stagesRegistered
  - Events created: $eventsCreated
  - Buses configured: $busesConfigured
  - Ducking rules: $duckingRulesAdded
  - ALE contexts: $aleContextsConfigured
  - RTPC parameters: $rtpcParametersConfigured
  - Unmapped stages: $unmappedStages''';
}

// ═══════════════════════════════════════════════════════════════════════════
// WIRE PROGRESS CALLBACK
// ═══════════════════════════════════════════════════════════════════════════

/// Progress callback for wiring operation
typedef WireProgressCallback = void Function(WireProgress progress);

/// Progress information during wiring
class WireProgress {
  final WireStep step;
  final double progress; // 0.0 - 1.0
  final String message;

  const WireProgress({
    required this.step,
    required this.progress,
    required this.message,
  });
}

/// Steps in the wiring process
enum WireStep {
  preparing('Preparing', 0.0),
  registeringStages('Registering Stages', 0.1),
  creatingEvents('Creating Events', 0.25),
  configuringBuses('Configuring Buses', 0.4),
  settingUpDucking('Setting Up Ducking', 0.5),
  configuringAle('Configuring ALE', 0.65),
  configuringRtpc('Configuring RTPC', 0.8),
  validating('Validating', 0.9),
  complete('Complete', 1.0);

  const WireStep(this.displayName, this.baseProgress);
  final String displayName;
  final double baseProgress;
}

// ═══════════════════════════════════════════════════════════════════════════
// TEMPLATE AUTO-WIRE SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Master service that orchestrates all auto-wiring
class TemplateAutoWireService {
  TemplateAutoWireService._();
  static final instance = TemplateAutoWireService._();

  // Sub-services
  final _stageRegistrar = StageAutoRegistrar();
  final _eventRegistrar = EventAutoRegistrar();
  final _busConfigurator = BusAutoConfigurator();
  final _duckingConfigurator = DuckingAutoConfigurator();
  final _aleConfigurator = AleAutoConfigurator();
  final _rtpcConfigurator = RtpcAutoConfigurator();
  final _validationService = TemplateValidationService();

  // Current state
  BuiltTemplate? _currentTemplate;
  StreamSubscription<dynamic>? _slotLabSubscription;
  bool _isWired = false;

  /// Currently applied template
  BuiltTemplate? get currentTemplate => _currentTemplate;

  /// Whether a template is currently wired
  bool get isWired => _isWired;

  // ═════════════════════════════════════════════════════════════════════════
  // MAIN WIRING METHOD
  // ═════════════════════════════════════════════════════════════════════════

  /// Wire a built template to all audio systems
  ///
  /// This is the main entry point. It:
  /// 1. Registers all stages with StageConfigurationService
  /// 2. Creates AudioEvents in EventRegistry for each mapped stage
  /// 3. Configures bus hierarchy
  /// 4. Sets up ducking rules
  /// 5. Configures ALE contexts
  /// 6. Sets up RTPC parameters and curves
  /// 7. Validates the complete wiring
  /// 8. Connects SlotLabProvider listener for runtime triggers
  Future<WireResult> wireTemplate(
    BuiltTemplate template, {
    WireProgressCallback? onProgress,
    bool skipValidation = false,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Unwire previous template if any
      if (_isWired) {
        await unwireTemplate();
      }

      _reportProgress(onProgress, WireStep.preparing, 'Preparing to wire template...');

      var stats = const WireStats();

      // ─────────────────────────────────────────────────────────────────────
      // STEP 1: Register Stages
      // ─────────────────────────────────────────────────────────────────────
      _reportProgress(
        onProgress,
        WireStep.registeringStages,
        'Registering ${template.source.allStages.length} stages...',
      );

      final stageCount = _stageRegistrar.registerAll(template);
      stats = stats.copyWith(stagesRegistered: stageCount);


      // ─────────────────────────────────────────────────────────────────────
      // STEP 2: Create Events
      // ─────────────────────────────────────────────────────────────────────
      _reportProgress(
        onProgress,
        WireStep.creatingEvents,
        'Creating events for ${template.audioMappings.length} audio mappings...',
      );

      final eventCount = _eventRegistrar.registerAll(template);
      stats = stats.copyWith(
        eventsCreated: eventCount,
        unmappedStages: template.unmappedStages.length,
      );

      if (template.unmappedStages.isNotEmpty) {
      }

      // ─────────────────────────────────────────────────────────────────────
      // STEP 3: Configure Buses
      // ─────────────────────────────────────────────────────────────────────
      _reportProgress(
        onProgress,
        WireStep.configuringBuses,
        'Configuring audio bus hierarchy...',
      );

      final busCount = _busConfigurator.configureAll(template);
      stats = stats.copyWith(busesConfigured: busCount);


      // ─────────────────────────────────────────────────────────────────────
      // STEP 4: Setup Ducking
      // ─────────────────────────────────────────────────────────────────────
      _reportProgress(
        onProgress,
        WireStep.settingUpDucking,
        'Setting up ducking rules...',
      );

      final duckingCount = _duckingConfigurator.configureAll(template);
      stats = stats.copyWith(duckingRulesAdded: duckingCount);


      // ─────────────────────────────────────────────────────────────────────
      // STEP 5: Configure ALE
      // ─────────────────────────────────────────────────────────────────────
      _reportProgress(
        onProgress,
        WireStep.configuringAle,
        'Configuring ALE music system...',
      );

      final aleCount = _aleConfigurator.configureAll(template);
      stats = stats.copyWith(aleContextsConfigured: aleCount);


      // ─────────────────────────────────────────────────────────────────────
      // STEP 6: Configure RTPC
      // ─────────────────────────────────────────────────────────────────────
      _reportProgress(
        onProgress,
        WireStep.configuringRtpc,
        'Configuring RTPC parameters...',
      );

      final rtpcCount = _rtpcConfigurator.configureAll(template);
      stats = stats.copyWith(rtpcParametersConfigured: rtpcCount);


      // ─────────────────────────────────────────────────────────────────────
      // STEP 7: Validate (optional)
      // ─────────────────────────────────────────────────────────────────────
      ValidationReport? validationReport;
      if (!skipValidation) {
        _reportProgress(
          onProgress,
          WireStep.validating,
          'Validating complete wiring...',
        );

        validationReport = _validationService.validate(template);

        if (!validationReport.allPassed) {
          for (final result in validationReport.results.where((r) => !r.passed)) {
          }
        } else {
        }
      }

      // ─────────────────────────────────────────────────────────────────────
      // STEP 8: Connect Runtime Listener
      // ─────────────────────────────────────────────────────────────────────
      _connectSlotLabListener();

      // Store current template
      _currentTemplate = template;
      _isWired = true;

      stopwatch.stop();

      _reportProgress(
        onProgress,
        WireStep.complete,
        'Template wired successfully!',
      );


      return WireResult(
        success: true,
        stats: stats,
        validationReport: validationReport,
        duration: stopwatch.elapsed,
      );
    } catch (e, stack) {
      stopwatch.stop();

      return WireResult.failure(e.toString(), stopwatch.elapsed);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // UNWIRE
  // ═════════════════════════════════════════════════════════════════════════

  /// Remove all wiring from current template
  Future<void> unwireTemplate() async {
    if (!_isWired) return;


    // Disconnect listener
    await _slotLabSubscription?.cancel();
    _slotLabSubscription = null;

    // Clear event registry
    EventRegistry.instance.clearAllEvents();

    // Note: We don't clear stages, buses, ducking, ALE, RTPC
    // because they might be shared with other systems.
    // The new template will overwrite them.

    _currentTemplate = null;
    _isWired = false;

  }

  // ═════════════════════════════════════════════════════════════════════════
  // RUNTIME CONNECTION
  // ═════════════════════════════════════════════════════════════════════════

  /// Connect to SlotLabProvider to trigger stages at runtime
  void _connectSlotLabListener() {
    // Cancel previous subscription
    _slotLabSubscription?.cancel();

    // Get SlotLabProvider (might be via GetIt or passed in)
    // For now, we'll use a callback-based approach
  }

  /// Called by SlotLabProvider when stages change
  void onSlotLabStagesChanged(List<String> stages) {
    if (!_isWired) return;

    for (final stage in stages) {
      EventRegistry.instance.triggerStage(stage);
    }
  }

  /// Update win multiplier RTPC value
  void updateWinMultiplier(double betAmount, double winAmount) {
    if (!_isWired || betAmount <= 0) return;

    final multiplier = winAmount / betAmount;

    // Update RTPC through provider
    try {
      final rtpcProvider = sl<RtpcSystemProvider>();
      final rtpc = rtpcProvider.getRtpcByName('Win Multiplier');
      if (rtpc != null) {
        rtpcProvider.setRtpc(rtpc.id, _normalizeMultiplier(multiplier));
      }
    } catch (e) { /* ignored */ }
  }

  /// Normalize win multiplier to 0-1 range based on template's max tier
  double _normalizeMultiplier(double multiplier) {
    if (_currentTemplate == null) return (multiplier / 100.0).clamp(0.0, 1.0);

    final winTiers = _currentTemplate!.source.winTiers;
    if (winTiers.isEmpty) return (multiplier / 100.0).clamp(0.0, 1.0);

    // Find max threshold
    final maxThreshold = winTiers.map((t) => t.threshold).reduce((a, b) => a > b ? a : b);
    return (multiplier / maxThreshold).clamp(0.0, 1.0);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  void _reportProgress(
    WireProgressCallback? callback,
    WireStep step,
    String message,
  ) {
    callback?.call(WireProgress(
      step: step,
      progress: step.baseProgress,
      message: message,
    ));
  }

  /// Get stats about current wiring
  WireStats? getCurrentStats() {
    if (!_isWired || _currentTemplate == null) return null;

    return WireStats(
      stagesRegistered: _currentTemplate!.source.allStages.length,
      eventsCreated: _currentTemplate!.audioMappings.length,
      busesConfigured: 8, // Fixed bus count
      duckingRulesAdded: _currentTemplate!.source.duckingRules.length,
      aleContextsConfigured: _currentTemplate!.source.aleContexts.length,
      rtpcParametersConfigured: 1, // winMultiplier
      unmappedStages: _currentTemplate!.unmappedStages.length,
    );
  }
}
