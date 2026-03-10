// ═══════════════════════════════════════════════════════════════════════════════
// SFX PIPELINE PROVIDER — State management for SFX Pipeline Wizard
// ═══════════════════════════════════════════════════════════════════════════════
//
// Manages wizard state across 6 steps:
// 1. Import & Scan
// 2. Trim & Clean
// 3. Loudness & Level
// 4. Format & Channel
// 5. Naming & Assign
// 6. Export & Finish
//
// All processing is OFFLINE (rf-offline crate).
// Audio thread (rf-engine) is NEVER touched during processing.
// EventRegistry sync happens indirektno through SlotLabScreen listener.

import 'package:flutter/foundation.dart';

import '../models/sfx_pipeline_config.dart';

/// Wizard step enum
enum SfxWizardStep {
  importScan,
  trimClean,
  loudnessLevel,
  formatChannel,
  namingAssign,
  exportFinish,
}

extension SfxWizardStepExt on SfxWizardStep {
  String get title {
    switch (this) {
      case SfxWizardStep.importScan:
        return 'IMPORT & SCAN';
      case SfxWizardStep.trimClean:
        return 'TRIM & CLEAN';
      case SfxWizardStep.loudnessLevel:
        return 'LOUDNESS & LEVEL';
      case SfxWizardStep.formatChannel:
        return 'FORMAT & CHANNEL';
      case SfxWizardStep.namingAssign:
        return 'NAMING & ASSIGN';
      case SfxWizardStep.exportFinish:
        return 'EXPORT & FINISH';
    }
  }

  int get stepNumber => index + 1;
}

/// State of the pipeline execution
enum SfxPipelineState {
  /// Wizard is open, user is configuring
  configuring,

  /// Scanning source files
  scanning,

  /// Processing files (trim/normalize/convert/export)
  processing,

  /// Pipeline completed successfully
  completed,

  /// Pipeline was cancelled
  cancelled,

  /// Pipeline encountered a fatal error
  failed,
}

/// Main provider for the SFX Pipeline Wizard
class SfxPipelineProvider extends ChangeNotifier {
  // ─── Wizard Navigation ─────────────────────────────────────────────────

  SfxWizardStep _currentStep = SfxWizardStep.importScan;
  SfxWizardStep get currentStep => _currentStep;

  void goToStep(SfxWizardStep step) {
    _currentStep = step;
    notifyListeners();
  }

  void nextStep() {
    final idx = _currentStep.index;
    if (idx < SfxWizardStep.values.length - 1) {
      _currentStep = SfxWizardStep.values[idx + 1];
      notifyListeners();
    }
  }

  void previousStep() {
    final idx = _currentStep.index;
    if (idx > 0) {
      _currentStep = SfxWizardStep.values[idx - 1];
      notifyListeners();
    }
  }

  bool get canGoNext => _currentStep.index < SfxWizardStep.values.length - 1;
  bool get canGoBack => _currentStep.index > 0;
  bool get isLastStep => _currentStep == SfxWizardStep.exportFinish;

  // ─── Pipeline State ────────────────────────────────────────────────────

  SfxPipelineState _state = SfxPipelineState.configuring;
  SfxPipelineState get state => _state;
  bool get isProcessing => _state == SfxPipelineState.processing || _state == SfxPipelineState.scanning;
  bool get isCompleted => _state == SfxPipelineState.completed;
  bool get isCancelled => _state == SfxPipelineState.cancelled;

  // ─── Preset / Configuration ────────────────────────────────────────────

  SfxPipelinePreset _preset = SfxBuiltInPresets.slotGameStandard;
  SfxPipelinePreset get preset => _preset;

  void loadPreset(SfxPipelinePreset preset) {
    _preset = preset;
    notifyListeners();
  }

  void updatePreset(SfxPipelinePreset Function(SfxPipelinePreset) updater) {
    _preset = updater(_preset);
    notifyListeners();
  }

  // ─── Step 1: Scan Results ──────────────────────────────────────────────

  List<SfxScanResult> _scanResults = [];
  List<SfxScanResult> get scanResults => _scanResults;
  List<SfxScanResult> get selectedFiles => _scanResults.where((f) => f.selected).toList();
  int get selectedCount => _scanResults.where((f) => f.selected).length;
  int get totalScanned => _scanResults.length;

  void setScanResults(List<SfxScanResult> results) {
    _scanResults = results;
    notifyListeners();
  }

  void toggleFileSelection(int index) {
    if (index < 0 || index >= _scanResults.length) return;
    _scanResults[index] = _scanResults[index].copyWith(
      selected: !_scanResults[index].selected,
    );
    notifyListeners();
  }

  void selectAllFiles() {
    _scanResults = _scanResults.map((f) => f.copyWith(selected: true)).toList();
    notifyListeners();
  }

  void deselectAllFiles() {
    _scanResults = _scanResults.map((f) => f.copyWith(selected: false)).toList();
    notifyListeners();
  }

  void invertSelection() {
    _scanResults = _scanResults.map((f) => f.copyWith(selected: !f.selected)).toList();
    notifyListeners();
  }

  // Scan statistics
  int get stereoCount => _scanResults.where((f) => f.selected && f.isStereo).length;
  int get monoCount => _scanResults.where((f) => f.selected && f.isMono).length;
  int get filesWithSilence => _scanResults.where((f) => f.selected && f.hasSilence).length;
  int get filesWithDcOffset => _scanResults.where((f) => f.selected && f.hasDcOffset).length;
  int get quietFiles => _scanResults.where((f) => f.selected && f.isQuiet).length;

  double get loudestLufs => _scanResults.isEmpty
      ? 0.0
      : _scanResults
          .where((f) => f.selected)
          .fold(-100.0, (max, f) => f.integratedLufs > max ? f.integratedLufs : max);

  double get quietestLufs => _scanResults.isEmpty
      ? 0.0
      : _scanResults
          .where((f) => f.selected)
          .fold(0.0, (min, f) => f.integratedLufs < min ? f.integratedLufs : min);

  double get avgLufs {
    final selected = _scanResults.where((f) => f.selected).toList();
    if (selected.isEmpty) return 0.0;
    return selected.fold(0.0, (sum, f) => sum + f.integratedLufs) / selected.length;
  }

  // ─── Step 5: Stage Mappings ────────────────────────────────────────────

  List<SfxStageMapping> _stageMappings = [];
  List<SfxStageMapping> get stageMappings => _stageMappings;
  List<SfxStageMapping> get matchedMappings => _stageMappings.where((m) => m.isMatched).toList();
  List<SfxStageMapping> get unmatchedMappings => _stageMappings.where((m) => !m.isMatched).toList();
  int get matchedCount => _stageMappings.where((m) => m.isMatched).length;

  void setStageMappings(List<SfxStageMapping> mappings) {
    _stageMappings = mappings;
    notifyListeners();
  }

  void updateStageMapping(int index, {String? stageId}) {
    if (index < 0 || index >= _stageMappings.length) return;
    _stageMappings[index] = _stageMappings[index].copyWith(
      stageId: stageId,
      confidence: 1.0,
      isManualOverride: true,
    );
    notifyListeners();
  }

  // ─── Step 6: Processing Progress ──────────────────────────────────────

  SfxPipelineProgress _progress = const SfxPipelineProgress();
  SfxPipelineProgress get progress => _progress;

  SfxPipelineResult? _result;
  SfxPipelineResult? get result => _result;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  void updateProgress(SfxPipelineProgress progress) {
    _progress = progress;
    notifyListeners();
  }

  void setProcessing() {
    _state = SfxPipelineState.processing;
    _result = null;
    _errorMessage = null;
    notifyListeners();
  }

  void setScanning() {
    _state = SfxPipelineState.scanning;
    notifyListeners();
  }

  void setCompleted(SfxPipelineResult result) {
    _state = SfxPipelineState.completed;
    _result = result;
    notifyListeners();
  }

  void setCancelled() {
    _state = SfxPipelineState.cancelled;
    notifyListeners();
  }

  void setFailed(String message) {
    _state = SfxPipelineState.failed;
    _errorMessage = message;
    notifyListeners();
  }

  void resetToConfiguring() {
    _state = SfxPipelineState.configuring;
    _progress = const SfxPipelineProgress();
    _result = null;
    _errorMessage = null;
    notifyListeners();
  }

  // ─── Reset ─────────────────────────────────────────────────────────────

  void reset() {
    _currentStep = SfxWizardStep.importScan;
    _state = SfxPipelineState.configuring;
    _preset = SfxBuiltInPresets.slotGameStandard;
    _scanResults = [];
    _stageMappings = [];
    _progress = const SfxPipelineProgress();
    _result = null;
    _errorMessage = null;
    notifyListeners();
  }
}
