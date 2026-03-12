/// SFX Pipeline Wizard — 6-step wizard for batch SFX processing
///
/// Steps:
/// 1. Import & Scan — select source folder, scan files
/// 2. Trim & Clean — silence removal, DC offset, fades
/// 3. Loudness & Level — LUFS normalization, per-category overrides
/// 4. Format & Channel — output format, sample rate, mono/stereo
/// 5. Naming & Assign — naming convention, stage mapping
/// 6. Export & Finish — output path, execute pipeline
///
/// Opens as a dialog from ASSIGN panel toolbar or Command Palette.
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/sfx_pipeline_config.dart';
import '../../providers/sfx_pipeline_provider.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../services/sfx_pipeline_service.dart';
import '../../services/native_file_picker.dart';
import '../../theme/fluxforge_theme.dart';

/// SFX Pipeline Wizard Dialog
class SfxPipelineWizard extends StatefulWidget {
  const SfxPipelineWizard({super.key});

  /// Show the wizard as a dialog
  static Future<SfxPipelineResult?> show(BuildContext context) {
    return showDialog<SfxPipelineResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ChangeNotifierProvider(
        create: (_) => SfxPipelineProvider(),
        child: const SfxPipelineWizard(),
      ),
    );
  }

  @override
  State<SfxPipelineWizard> createState() => _SfxPipelineWizardState();
}

class _SfxPipelineWizardState extends State<SfxPipelineWizard> {
  // Step-specific controllers
  final _sourcePathController = TextEditingController();
  final _outputPathController = TextEditingController();
  final _prefixController = TextEditingController(text: 'sfx_');
  final _customTemplateController = TextEditingController();
  final _ucsVendorController = TextEditingController();
  final _ucsProjectController = TextEditingController();

  // Step configs
  static const _steps = [
    _StepConfig('IMPORT & SCAN', Icons.folder_open, 'Select source folder and scan files'),
    _StepConfig('TRIM & CLEAN', Icons.content_cut, 'Silence removal, DC offset, fades'),
    _StepConfig('LOUDNESS & LEVEL', Icons.equalizer, 'LUFS normalization and limiting'),
    _StepConfig('FORMAT & CHANNEL', Icons.settings_input_component, 'Output format, sample rate, channels'),
    _StepConfig('NAMING & ASSIGN', Icons.text_fields, 'Naming convention and stage mapping'),
    _StepConfig('EXPORT & FINISH', Icons.rocket_launch, 'Output path and execute pipeline'),
  ];

  @override
  void dispose() {
    _sourcePathController.dispose();
    _outputPathController.dispose();
    _prefixController.dispose();
    _customTemplateController.dispose();
    _ucsVendorController.dispose();
    _ucsProjectController.dispose();
    super.dispose();
  }

  void _syncControllersFromPreset(SfxPipelinePreset preset) {
    _prefixController.text = preset.prefix;
    _customTemplateController.text = preset.customTemplate;
    _ucsVendorController.text = preset.ucsVendor;
    _ucsProjectController.text = preset.ucsProject;
    if (preset.lastSourcePath != null) {
      _sourcePathController.text = preset.lastSourcePath!;
    }
    if (preset.outputPath != null) {
      _outputPathController.text = preset.outputPath!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.85).clamp(900.0, 1400.0);
    final dialogHeight = (screenSize.height * 0.85).clamp(700.0, 1000.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 40,
              spreadRadius: 10,
            ),
          ],
        ),
        child: Consumer<SfxPipelineProvider>(
          builder: (context, provider, _) {
            return Column(
              children: [
                _buildTitleBar(provider),
                _buildStepIndicator(provider),
                Expanded(child: _buildStepContent(provider)),
                _buildFooter(provider),
              ],
            );
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TITLE BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTitleBar(SfxPipelineProvider provider) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.bgElevated)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_fix_high, color: FluxForgeTheme.accentCyan, size: 18),
          const SizedBox(width: 8),
          const Text(
            'SFX PIPELINE WIZARD',
            style: TextStyle(
              color: FluxForgeTheme.accentCyan,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 12),
          // Preset selector
          _buildPresetSelector(provider),
          const Spacer(),
          // Processing status
          if (provider.isProcessing)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: FluxForgeTheme.accentCyan),
                ),
                const SizedBox(width: 6),
                Text(
                  '${provider.progress.currentFilename ?? "Processing..."}',
                  style: const TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
          const SizedBox(width: 8),
          // Close button
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: FluxForgeTheme.textTertiary),
            onPressed: () => _handleClose(provider),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetSelector(SfxPipelineProvider provider) {
    return PopupMenuButton<SfxPipelinePreset>(
      tooltip: 'Load Preset',
      offset: const Offset(0, 32),
      color: FluxForgeTheme.bgSurface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.bgElevated),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune, size: 12, color: FluxForgeTheme.textTertiary),
            const SizedBox(width: 4),
            Text(
              provider.preset.name,
              style: const TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 14, color: FluxForgeTheme.textTertiary),
          ],
        ),
      ),
      itemBuilder: (_) => [
        ...SfxBuiltInPresets.all.map((preset) => PopupMenuItem(
              value: preset,
              child: Text(preset.name, style: const TextStyle(fontSize: 12, color: Colors.white)),
            )),
      ],
      onSelected: (preset) {
        provider.loadPreset(preset);
        _syncControllersFromPreset(preset);
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP INDICATOR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStepIndicator(SfxPipelineProvider provider) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.bgElevated)),
      ),
      child: Row(
        children: List.generate(_steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line
            final stepIdx = i ~/ 2;
            final isComplete = stepIdx < provider.currentStep.index;
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: isComplete
                    ? FluxForgeTheme.accentCyan.withValues(alpha: 0.6)
                    : FluxForgeTheme.bgElevated,
              ),
            );
          }
          final stepIdx = i ~/ 2;
          final step = _steps[stepIdx];
          final wizStep = SfxWizardStep.values[stepIdx];
          final isCurrent = provider.currentStep == wizStep;
          final isComplete = provider.currentStep.index > stepIdx;
          final color = isCurrent
              ? FluxForgeTheme.accentCyan
              : isComplete
                  ? FluxForgeTheme.accentGreen
                  : FluxForgeTheme.textTertiary;

          return GestureDetector(
            onTap: provider.isProcessing ? null : () => provider.goToStep(wizStep),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCurrent ? color.withValues(alpha: 0.2) : Colors.transparent,
                    border: Border.all(color: color, width: isCurrent ? 2 : 1),
                  ),
                  child: Center(
                    child: isComplete
                        ? Icon(Icons.check, size: 12, color: color)
                        : Text(
                            '${stepIdx + 1}',
                            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  step.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStepContent(SfxPipelineProvider provider) {
    switch (provider.currentStep) {
      case SfxWizardStep.importScan:
        return _buildImportStep(provider);
      case SfxWizardStep.trimClean:
        return _buildTrimStep(provider);
      case SfxWizardStep.loudnessLevel:
        return _buildLoudnessStep(provider);
      case SfxWizardStep.formatChannel:
        return _buildFormatStep(provider);
      case SfxWizardStep.namingAssign:
        return _buildNamingStep(provider);
      case SfxWizardStep.exportFinish:
        return _buildExportStep(provider);
    }
  }

  // ─── Step 1: Import & Scan ────────────────────────────────────────────────

  Widget _buildImportStep(SfxPipelineProvider provider) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Source config
        Expanded(
          flex: 4,
          child: _stepPanel(
            'SOURCE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source path
                _paramRow('Folder', child: Row(
                  children: [
                    Expanded(
                      child: _textField(_sourcePathController, hint: '/path/to/sfx/folder'),
                    ),
                    const SizedBox(width: 4),
                    _actionBtn('Browse', Icons.folder_open, () async {
                      final path = await NativeFilePicker.pickDirectory(
                        title: 'Select SFX Source Folder',
                      );
                      if (path != null) {
                        _sourcePathController.text = path;
                        provider.updatePreset((p) => p.copyWith(lastSourcePath: path));
                      }
                    }),
                  ],
                )),
                _paramRow('Recursive', child: _toggle(
                  provider.preset.recursive,
                  (v) => provider.updatePreset((p) => p.copyWith(recursive: v)),
                )),
                _paramRow('Filter', child: Text(
                  provider.preset.fileFilter,
                  style: const TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11, fontFamily: 'monospace'),
                )),
                const SizedBox(height: 12),
                // Scan button
                Center(
                  child: _primaryBtn(
                    provider.state == SfxPipelineState.scanning ? 'SCANNING...' : 'SCAN FILES',
                    Icons.search,
                    provider.state == SfxPipelineState.scanning ? null : () => _handleScan(provider),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Right: Scan results
        Expanded(
          flex: 6,
          child: _stepPanel(
            'SCAN RESULTS  (${provider.selectedCount}/${provider.totalScanned} selected)',
            child: provider.scanResults.isEmpty
                ? const Center(child: Text('No files scanned yet', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12)))
                : Column(
                    children: [
                      // Stats bar
                      _buildScanStats(provider),
                      const SizedBox(height: 4),
                      // Selection controls
                      Row(
                        children: [
                          _miniBtn('All', () => provider.selectAllFiles()),
                          _miniBtn('None', () => provider.deselectAllFiles()),
                          _miniBtn('Invert', () => provider.invertSelection()),
                          const Spacer(),
                          if (provider.stereoCount > 0)
                            _statBadge('ST: ${provider.stereoCount}', FluxForgeTheme.accentBlue),
                          if (provider.monoCount > 0)
                            _statBadge('MO: ${provider.monoCount}', FluxForgeTheme.accentGreen),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // File list
                      Expanded(child: _buildScanFileList(provider)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildScanStats(SfxPipelineProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          _statItem('LUFS', '${provider.avgLufs.toStringAsFixed(1)} avg'),
          _statItem('Range', '${provider.quietestLufs.toStringAsFixed(0)}..${provider.loudestLufs.toStringAsFixed(0)}'),
          if (provider.filesWithSilence > 0)
            _statItem('Silence', '${provider.filesWithSilence}', color: FluxForgeTheme.accentOrange),
          if (provider.filesWithDcOffset > 0)
            _statItem('DC', '${provider.filesWithDcOffset}', color: FluxForgeTheme.accentRed),
        ],
      ),
    );
  }

  Widget _buildScanFileList(SfxPipelineProvider provider) {
    return ListView.builder(
      itemCount: provider.scanResults.length,
      itemExtent: 28,
      itemBuilder: (context, index) {
        final file = provider.scanResults[index];
        return GestureDetector(
          onTap: () => provider.toggleFileSelection(index),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            color: index.isEven ? Colors.transparent : FluxForgeTheme.bgMid.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(
                  file.selected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 14,
                  color: file.selected ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    file.filename,
                    style: TextStyle(
                      color: file.selected ? Colors.white : FluxForgeTheme.textTertiary,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Category badge
                _categoryBadge(file.detectedCategory),
                const SizedBox(width: 4),
                // Format info
                Text(
                  '${file.channelLabel} ${file.formatLabel}',
                  style: const TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9, fontFamily: 'monospace'),
                ),
                const SizedBox(width: 4),
                // LUFS
                Text(
                  '${file.integratedLufs.toStringAsFixed(1)}',
                  style: TextStyle(
                    color: file.isQuiet ? FluxForgeTheme.accentOrange : FluxForgeTheme.textSecondary,
                    fontSize: 9, fontFamily: 'monospace',
                  ),
                ),
                // Warning indicators
                if (file.hasSilence)
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(Icons.content_cut, size: 10, color: FluxForgeTheme.accentOrange),
                  ),
                if (file.hasDcOffset)
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(Icons.warning_amber, size: 10, color: FluxForgeTheme.accentRed),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Step 2: Trim & Clean ─────────────────────────────────────────────────

  Widget _buildTrimStep(SfxPipelineProvider provider) {
    final preset = provider.preset;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Trim settings
        Expanded(
          child: _stepPanel('SILENCE TRIMMING', child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _paramRow('Trim Start', child: _toggle(preset.trimStart, (v) =>
                  provider.updatePreset((p) => p.copyWith(trimStart: v)))),
              _paramRow('Trim End', child: _toggle(preset.trimEnd, (v) =>
                  provider.updatePreset((p) => p.copyWith(trimEnd: v)))),
              _paramRow('Threshold', child: _slider(
                preset.thresholdDb, -80, -20, 'dB',
                (v) => provider.updatePreset((p) => p.copyWith(thresholdDb: v)),
              )),
              _paramRow('Min Silence', child: _slider(
                preset.minSilenceMs, 10, 500, 'ms',
                (v) => provider.updatePreset((p) => p.copyWith(minSilenceMs: v)),
              )),
              _paramRow('Pad Before', child: _slider(
                preset.paddingBeforeMs, 0, 50, 'ms',
                (v) => provider.updatePreset((p) => p.copyWith(paddingBeforeMs: v)),
              )),
              _paramRow('Pad After', child: _slider(
                preset.paddingAfterMs, 0, 100, 'ms',
                (v) => provider.updatePreset((p) => p.copyWith(paddingAfterMs: v)),
              )),
              const Divider(color: FluxForgeTheme.bgElevated, height: 12),
              const Text('SKIP TRIM FOR:', style: TextStyle(
                color: FluxForgeTheme.textTertiary, fontSize: 9,
                fontWeight: FontWeight.w600, letterSpacing: 1,
              )),
              const SizedBox(height: 4),
              ...SfxCategory.values.where((c) => c != SfxCategory.unknown).map((cat) =>
                _paramRow(cat.displayName, child: _toggle(
                  preset.noTrimCategories.contains(cat),
                  (v) {
                    final updated = Set<SfxCategory>.from(preset.noTrimCategories);
                    if (v) {
                      updated.add(cat);
                    } else {
                      updated.remove(cat);
                    }
                    provider.updatePreset((p) => p.copyWith(noTrimCategories: updated));
                  },
                )),
              ),
            ],
          )),
        ),
        const SizedBox(width: 8),
        // Right: DC offset & Fades
        Expanded(
          child: Column(
            children: [
              _stepPanel('DC OFFSET & NORMALIZE', child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _paramRow('Remove DC Offset', child: _toggle(preset.removeDcOffset, (v) =>
                      provider.updatePreset((p) => p.copyWith(removeDcOffset: v)))),
                  _paramRow('Pre-Normalize Peak', child: _toggle(preset.preNormalizePeak, (v) =>
                      provider.updatePreset((p) => p.copyWith(preNormalizePeak: v)))),
                ],
              )),
              const SizedBox(height: 8),
              _stepPanel('FILTERS', child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _paramRow('High-Pass', child: Row(
                    children: [
                      _toggle(preset.highPassEnabled, (v) =>
                          provider.updatePreset((p) => p.copyWith(highPassEnabled: v))),
                      if (preset.highPassEnabled) ...[
                        const SizedBox(width: 8),
                        Expanded(child: _slider(
                          preset.highPassFreq, 20, 200, 'Hz',
                          (v) => provider.updatePreset((p) => p.copyWith(highPassFreq: v)),
                        )),
                      ],
                    ],
                  )),
                  _paramRow('Low-Pass', child: Row(
                    children: [
                      _toggle(preset.lowPassEnabled, (v) =>
                          provider.updatePreset((p) => p.copyWith(lowPassEnabled: v))),
                      if (preset.lowPassEnabled) ...[
                        const SizedBox(width: 8),
                        Expanded(child: _slider(
                          preset.lowPassFreq, 8000, 20000, 'Hz',
                          (v) => provider.updatePreset((p) => p.copyWith(lowPassFreq: v)),
                        )),
                      ],
                    ],
                  )),
                ],
              )),
              const SizedBox(height: 8),
              Expanded(child: _stepPanel('FADES', child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _paramRow('Fade In', child: Row(
                    children: [
                      _toggle(preset.fadeIn, (v) =>
                          provider.updatePreset((p) => p.copyWith(fadeIn: v))),
                      if (preset.fadeIn) ...[
                        const SizedBox(width: 8),
                        Expanded(child: _slider(
                          preset.fadeInMs, 0.5, 50, 'ms',
                          (v) => provider.updatePreset((p) => p.copyWith(fadeInMs: v)),
                        )),
                      ],
                    ],
                  )),
                  _paramRow('Fade Out', child: Row(
                    children: [
                      _toggle(preset.fadeOut, (v) =>
                          provider.updatePreset((p) => p.copyWith(fadeOut: v))),
                      if (preset.fadeOut) ...[
                        const SizedBox(width: 8),
                        Expanded(child: _slider(
                          preset.fadeOutMs, 1, 100, 'ms',
                          (v) => provider.updatePreset((p) => p.copyWith(fadeOutMs: v)),
                        )),
                      ],
                    ],
                  )),
                  _paramRow('Curve', child: _enumDropdown<SfxFadeCurve>(
                    SfxFadeCurve.values, preset.fadeCurve,
                    (v) => provider.updatePreset((p) => p.copyWith(fadeCurve: v)),
                    labelOf: (v) => v.displayName,
                  )),
                ],
              ))),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Step 3: Loudness & Level ─────────────────────────────────────────────

  Widget _buildLoudnessStep(SfxPipelineProvider provider) {
    final preset = provider.preset;
    final hasFiles = provider.scanResults.any((f) => f.selected);
    return Column(
      children: [
        // ── Top row: Normalization settings + Per-category overrides ──
        Expanded(
          flex: hasFiles ? 3 : 1,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _stepPanel('NORMALIZATION', child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _paramRow('Mode', child: _enumDropdown<SfxNormMode>(
                    SfxNormMode.values, preset.normMode,
                    (v) => provider.updatePreset((p) => p.copyWith(normMode: v)),
                    labelOf: (v) => v.displayName,
                  )),
                  if (preset.normMode == SfxNormMode.lufs) ...[
                    _paramRow('Target LUFS', child: _slider(
                      preset.targetLufs, -30, -6, 'LUFS',
                      (v) => provider.updatePreset((p) => p.copyWith(targetLufs: v)),
                    )),
                    _paramRow('True Peak Ceiling', child: _slider(
                      preset.truePeakCeiling, -3, 0, 'dBTP',
                      (v) => provider.updatePreset((p) => p.copyWith(truePeakCeiling: v)),
                    )),
                  ],
                  _paramRow('Apply Limiter', child: _toggle(preset.applyLimiter, (v) =>
                      provider.updatePreset((p) => p.copyWith(applyLimiter: v)))),
                  _paramRow('Allow Clipping', child: _toggle(preset.allowClipping, (v) =>
                      provider.updatePreset((p) => p.copyWith(allowClipping: v)))),
                ],
              )),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _stepPanel('PER-CATEGORY OVERRIDES', child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _paramRow('Auto-Detect Category', child: _toggle(preset.categoryDetection, (v) =>
                      provider.updatePreset((p) => p.copyWith(categoryDetection: v)))),
                  const SizedBox(height: 8),
                  if (preset.categoryDetection)
                    ...SfxCategory.values.where((c) => c != SfxCategory.unknown).map((cat) {
                      final catOverride = preset.perCategoryOverrides[cat];
                      return _paramRow(
                        cat.displayName,
                        child: Row(
                          children: [
                            _toggle(catOverride != null, (enabled) {
                              final overrides = Map<SfxCategory, double?>.from(preset.perCategoryOverrides);
                              overrides[cat] = enabled
                                  ? (SfxBuiltInPresets.slotCategoryLufs[cat] ?? preset.targetLufs)
                                  : null;
                              provider.updatePreset((p) => p.copyWith(perCategoryOverrides: overrides));
                            }),
                            if (catOverride != null) ...[
                              const SizedBox(width: 8),
                              Expanded(child: _slider(
                                catOverride, -30, -6, 'LUFS',
                                (v) {
                                  final overrides = Map<SfxCategory, double?>.from(preset.perCategoryOverrides);
                                  overrides[cat] = v;
                                  provider.updatePreset((p) => p.copyWith(perCategoryOverrides: overrides));
                                },
                              )),
                            ],
                          ],
                        ),
                      );
                    }),
                ],
              )),
            ),
            ],
          ),
        ),
        // ── Bottom: Live preview table — shows resolved target for each file ──
        if (hasFiles)
          Expanded(
            flex: 2,
            child: _buildLoudnessPreviewTable(provider),
          ),
      ],
    );
  }

  /// Live preview table: for each scanned file, shows detected category,
  /// current LUFS, resolved target LUFS (from slider/override), and gain delta.
  /// Updates in real-time as user moves sliders.
  Widget _buildLoudnessPreviewTable(SfxPipelineProvider provider) {
    final preset = provider.preset;
    final files = provider.scanResults.where((f) => f.selected).toList();
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Text('No files selected — scan files in Step 1',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
        ),
      );
    }

    // Aggregate per-category file counts for header chips
    final catCounts = <SfxCategory, int>{};
    for (final f in files) {
      catCounts[f.detectedCategory] = (catCounts[f.detectedCategory] ?? 0) + 1;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.bgElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: FluxForgeTheme.bgElevated)),
            ),
            child: Row(
              children: [
                const Text('LIVE PREVIEW', style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                )),
                const SizedBox(width: 8),
                Text('${files.length} files', style: const TextStyle(
                  color: FluxForgeTheme.textTertiary, fontSize: 9,
                )),
                const Spacer(),
                // Per-category summary chips
                ...catCounts.entries.where((e) => e.key != SfxCategory.unknown).map((e) =>
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _categoryBadge(e.key),
                  ),
                ),
                if (catCounts.containsKey(SfxCategory.unknown))
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text('${catCounts[SfxCategory.unknown]} ?',
                      style: const TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 8)),
                  ),
              ],
            ),
          ),
          // ── Column headers ──
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
            ),
            child: const Row(
              children: [
                SizedBox(width: 180, child: Text('FILENAME', style: _previewHeaderStyle)),
                SizedBox(width: 80, child: Text('CATEGORY', style: _previewHeaderStyle)),
                SizedBox(width: 60, child: Text('NOW', style: _previewHeaderStyle)),
                SizedBox(width: 16, child: Text('→', style: _previewHeaderStyle)),
                SizedBox(width: 60, child: Text('TARGET', style: _previewHeaderStyle)),
                SizedBox(width: 60, child: Text('GAIN', style: _previewHeaderStyle)),
                Expanded(child: Text('', style: _previewHeaderStyle)),
              ],
            ),
          ),
          // ── File rows ──
          Expanded(
            child: ListView.builder(
              itemCount: files.length,
              itemExtent: 22,
              itemBuilder: (context, index) {
                final file = files[index];
                final cat = file.detectedCategory;

                // Resolve target — exact same logic as executePipeline
                // LUFS mode: per-category override → global targetLufs
                // Peak/TruePeak: truePeakCeiling (no per-category override)
                final bool isLufs = preset.normMode == SfxNormMode.lufs;
                final bool hasOverride = isLufs && preset.categoryDetection &&
                    preset.perCategoryOverrides[cat] != null;
                double targetDisplay;
                String targetUnit;
                double gainDelta;

                if (preset.normMode == SfxNormMode.none) {
                  targetDisplay = 0;
                  targetUnit = '';
                  gainDelta = 0;
                } else if (isLufs) {
                  targetDisplay = preset.targetLufs;
                  if (hasOverride) {
                    targetDisplay = preset.perCategoryOverrides[cat]!;
                  }
                  targetUnit = 'LUFS';
                  gainDelta = targetDisplay - file.integratedLufs;
                } else {
                  // Peak / TruePeak — target is dBTP ceiling, gain relative to peak
                  targetDisplay = preset.truePeakCeiling;
                  targetUnit = 'dBTP';
                  gainDelta = targetDisplay - file.peakDbfs;
                }

                // Color coding for gain
                final gainColor = gainDelta.abs() < 1.0
                    ? FluxForgeTheme.textTertiary
                    : gainDelta > 0
                        ? FluxForgeTheme.accentOrange  // Boosting
                        : FluxForgeTheme.accentCyan;   // Cutting

                // Warning: boost > 12 dB is aggressive
                final bool isAggressiveBoost = gainDelta > 12.0;
                // Warning: unknown category uses global target
                final bool isUnknownCat = cat == SfxCategory.unknown;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  color: index.isEven ? Colors.transparent : FluxForgeTheme.bgDeep.withValues(alpha: 0.3),
                  child: Row(
                    children: [
                      // Filename
                      SizedBox(
                        width: 180,
                        child: Text(
                          file.filename,
                          style: TextStyle(
                            color: isUnknownCat
                                ? FluxForgeTheme.textTertiary
                                : Colors.white,
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Category badge
                      SizedBox(
                        width: 80,
                        child: cat == SfxCategory.unknown
                            ? Text('—', style: TextStyle(
                                color: FluxForgeTheme.textTertiary, fontSize: 9,
                                fontStyle: FontStyle.italic))
                            : _categoryBadge(cat),
                      ),
                      // Current level (LUFS for LUFS mode, peak dBFS for Peak/TruePeak)
                      SizedBox(
                        width: 60,
                        child: Text(
                          isLufs || preset.normMode == SfxNormMode.none
                              ? '${file.integratedLufs.toStringAsFixed(1)}'
                              : '${file.peakDbfs.toStringAsFixed(1)}',
                          style: const TextStyle(
                            color: FluxForgeTheme.textSecondary,
                            fontSize: 10, fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      // Arrow
                      SizedBox(
                        width: 16,
                        child: Text('→', style: TextStyle(
                          color: preset.normMode == SfxNormMode.none
                              ? FluxForgeTheme.textTertiary
                              : FluxForgeTheme.textSecondary,
                          fontSize: 9,
                        )),
                      ),
                      // Target level
                      SizedBox(
                        width: 60,
                        child: preset.normMode == SfxNormMode.none
                            ? const Text('—', style: TextStyle(
                                color: FluxForgeTheme.textTertiary, fontSize: 10))
                            : Text(
                                '${targetDisplay.toStringAsFixed(1)}',
                                style: TextStyle(
                                  color: hasOverride
                                      ? FluxForgeTheme.accentCyan
                                      : FluxForgeTheme.textSecondary,
                                  fontSize: 10, fontFamily: 'monospace',
                                  fontWeight: hasOverride ? FontWeight.w700 : FontWeight.normal,
                                ),
                              ),
                      ),
                      // Gain delta
                      SizedBox(
                        width: 60,
                        child: preset.normMode == SfxNormMode.none
                            ? const SizedBox.shrink()
                            : Text(
                                '${gainDelta >= 0 ? "+" : ""}${gainDelta.toStringAsFixed(1)} dB',
                                style: TextStyle(
                                  color: gainColor,
                                  fontSize: 10, fontFamily: 'monospace',
                                ),
                              ),
                      ),
                      // Warnings
                      Expanded(
                        child: Row(
                          children: [
                            if (isAggressiveBoost)
                              Tooltip(
                                message: 'Aggressive boost (${gainDelta.toStringAsFixed(1)} dB) — may cause artifacts',
                                child: const Icon(Icons.warning_amber, size: 12, color: FluxForgeTheme.accentOrange),
                              ),
                            if (isUnknownCat && preset.categoryDetection)
                              Tooltip(
                                message: 'Category not detected — using global target (${preset.targetLufs.toStringAsFixed(1)} LUFS)',
                                child: const Icon(Icons.help_outline, size: 12, color: FluxForgeTheme.textTertiary),
                              ),
                            if (hasOverride)
                              Tooltip(
                                message: '${cat.displayName} override active',
                                child: Icon(Icons.tune, size: 11, color: FluxForgeTheme.accentCyan.withValues(alpha: 0.6)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static const _previewHeaderStyle = TextStyle(
    color: FluxForgeTheme.textTertiary,
    fontSize: 8,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );

  // ─── Step 4: Format & Channel ─────────────────────────────────────────────

  Widget _buildFormatStep(SfxPipelineProvider provider) {
    final preset = provider.preset;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _stepPanel('OUTPUT FORMAT', child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _paramRow('Format', child: _enumDropdown<SfxOutputFormat>(
                SfxOutputFormat.values, preset.outputFormat,
                (v) => provider.updatePreset((p) => p.copyWith(outputFormat: v)),
                labelOf: (v) => v.displayName,
              )),
              _paramRow('Sample Rate', child: _enumDropdown<int>(
                const [22050, 44100, 48000, 96000], preset.sampleRate,
                (v) => provider.updatePreset((p) => p.copyWith(sampleRate: v)),
                labelOf: (v) => '${v ~/ 1000}kHz',
              )),
              const SizedBox(height: 8),
              _paramRow('Multi-Format Export', child: _toggle(preset.multiFormat, (v) =>
                  provider.updatePreset((p) => p.copyWith(multiFormat: v)))),
              if (preset.multiFormat)
                _paramRow('Subfolder/Format', child: _toggle(preset.subfolderPerFormat, (v) =>
                    provider.updatePreset((p) => p.copyWith(subfolderPerFormat: v)))),
            ],
          )),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _stepPanel('CHANNEL MODE PER CATEGORY', child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Per-category channel mode table
              ..._buildPerCategoryChannelRows(provider, preset),
              const Divider(color: FluxForgeTheme.bgElevated, height: 12),
              _paramRow('Mono Downmix', child: _enumDropdown<MonoDownmixMethod>(
                MonoDownmixMethod.values, preset.monoMethod,
                (v) => provider.updatePreset((p) => p.copyWith(monoMethod: v)),
                labelOf: (v) => v.displayName,
              )),
            ],
          )),
        ),
      ],
    );
  }

  List<Widget> _buildPerCategoryChannelRows(SfxPipelineProvider provider, SfxPipelinePreset preset) {
    // Show all categories except unknown
    final categories = SfxCategory.values.where((c) => c != SfxCategory.unknown).toList();
    return categories.map((cat) {
      final resolved = preset.resolveChannelMode(cat);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(
                cat.displayName,
                style: const TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  for (final mode in OutputChannelMode.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _channelModeChip(mode, resolved == mode, () {
                        final updated = Map<SfxCategory, OutputChannelMode>.from(preset.perCategoryChannels);
                        if (mode == cat.defaultChannelMode) {
                          updated.remove(cat); // revert to default
                        } else {
                          updated[cat] = mode;
                        }
                        provider.updatePreset((p) => p.copyWith(perCategoryChannels: updated));
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _channelModeChip(OutputChannelMode mode, bool selected, VoidCallback onTap) {
    final label = switch (mode) {
      OutputChannelMode.mono => 'M',
      OutputChannelMode.stereo => 'ST',
      OutputChannelMode.keepOriginal => 'ORIG',
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? FluxForgeTheme.accentCyan.withValues(alpha: 0.2) : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: selected ? FluxForgeTheme.accentCyan : FluxForgeTheme.bgElevated,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  // ─── Step 5: Naming & Assign ──────────────────────────────────────────────

  Widget _buildNamingStep(SfxPipelineProvider provider) {
    final preset = provider.preset;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Naming settings
        Expanded(
          flex: 4,
          child: _stepPanel('NAMING', child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _paramRow('Mode', child: _enumDropdown<SfxNamingMode>(
                SfxNamingMode.values, preset.namingMode,
                (v) => provider.updatePreset((p) => p.copyWith(namingMode: v)),
                labelOf: (v) => v.displayName,
              )),
              if (preset.namingMode == SfxNamingMode.slotLabStageId) ...[
                _paramRow('Prefix', child: _textField(_prefixController, hint: 'sfx_')),
                _paramRow('Lowercase', child: _toggle(preset.lowercase, (v) =>
                    provider.updatePreset((p) => p.copyWith(lowercase: v)))),
              ],
              if (preset.namingMode == SfxNamingMode.ucs) ...[
                _paramRow('Vendor', child: _textField(_ucsVendorController, hint: 'VEN')),
                _paramRow('Project', child: _textField(_ucsProjectController, hint: 'ProjectName')),
              ],
              if (preset.namingMode == SfxNamingMode.custom)
                _paramRow('Template', child: _textField(_customTemplateController, hint: '{prefix}_{stage}_{index}')),
              _paramRow('Number Duplicates', child: _toggle(preset.numberDuplicates, (v) =>
                  provider.updatePreset((p) => p.copyWith(numberDuplicates: v)))),
              const Divider(color: FluxForgeTheme.bgElevated, height: 16),
              _paramRow('Auto-Assign to Stages', child: _toggle(preset.autoAssign, (v) =>
                  provider.updatePreset((p) => p.copyWith(autoAssign: v)))),
              if (preset.autoAssign)
                _paramRow('On Conflict', child: _enumDropdown<SfxConflictResolution>(
                  SfxConflictResolution.values, preset.conflictResolution,
                  (v) => provider.updatePreset((p) => p.copyWith(conflictResolution: v)),
                  labelOf: (v) => v.displayName,
                )),
            ],
          )),
        ),
        const SizedBox(width: 8),
        // Right: Stage mappings
        Expanded(
          flex: 6,
          child: _stepPanel(
            'STAGE MAPPINGS  (${provider.matchedCount}/${provider.stageMappings.length})',
            actions: [
              _miniBtn('Auto-Match', () => _handleAutoMatch(provider)),
            ],
            child: provider.stageMappings.isEmpty
                ? const Center(child: Text(
                    'Run Auto-Match to map files to stages',
                    style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12),
                  ))
                : _buildStageMappingList(provider),
          ),
        ),
      ],
    );
  }

  Widget _buildStageMappingList(SfxPipelineProvider provider) {
    return ListView.builder(
      itemCount: provider.stageMappings.length,
      itemExtent: 30,
      itemBuilder: (context, index) {
        final mapping = provider.stageMappings[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          color: index.isEven ? Colors.transparent : FluxForgeTheme.bgMid.withValues(alpha: 0.3),
          child: Row(
            children: [
              // Confidence indicator
              Container(
                width: 6, height: 6,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mapping.isMatched
                      ? (mapping.isHighConfidence ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange)
                      : FluxForgeTheme.accentRed,
                ),
              ),
              // Source filename
              Expanded(
                flex: 5,
                child: Text(
                  mapping.sourceFilename,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Arrow
              const Icon(Icons.arrow_forward, size: 12, color: FluxForgeTheme.textTertiary),
              const SizedBox(width: 4),
              // Stage ID
              Expanded(
                flex: 4,
                child: Text(
                  mapping.stageId ?? '—',
                  style: TextStyle(
                    color: mapping.isMatched ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              // Confidence
              Text(
                mapping.isManualOverride
                    ? '✋'
                    : '${(mapping.confidence * 100).toInt()}%',
                style: const TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Step 6: Export & Finish ───────────────────────────────────────────────

  Widget _buildExportStep(SfxPipelineProvider provider) {
    final preset = provider.preset;
    final isProcessing = provider.isProcessing;
    final isCompleted = provider.isCompleted;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Export settings + Execute
        Expanded(
          child: _stepPanel('EXPORT SETTINGS', child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _paramRow('Output Folder', child: Row(
                children: [
                  Expanded(child: _textField(_outputPathController, hint: '/path/to/output')),
                  const SizedBox(width: 4),
                  _actionBtn('Browse', Icons.folder_open, () async {
                    final path = await NativeFilePicker.pickDirectory(
                      title: 'Select Output Folder',
                    );
                    if (path != null) {
                      _outputPathController.text = path;
                      provider.updatePreset((p) => p.copyWith(outputPath: path));
                    }
                  }),
                ],
              )),
              _paramRow('Date Subfolder', child: _toggle(preset.createDateSubfolder, (v) =>
                  provider.updatePreset((p) => p.copyWith(createDateSubfolder: v)))),
              _paramRow('Overwrite Existing', child: _toggle(preset.overwriteExisting, (v) =>
                  provider.updatePreset((p) => p.copyWith(overwriteExisting: v)))),
              _paramRow('Generate Manifest', child: _toggle(preset.generateManifest, (v) =>
                  provider.updatePreset((p) => p.copyWith(generateManifest: v)))),
              _paramRow('Generate LUFS Report', child: _toggle(preset.generateLufsReport, (v) =>
                  provider.updatePreset((p) => p.copyWith(generateLufsReport: v)))),
              const SizedBox(height: 16),
              // Execute button
              Center(
                child: isCompleted
                    ? _successBanner(provider)
                    : _primaryBtn(
                        isProcessing ? 'PROCESSING...' : 'EXECUTE PIPELINE',
                        isProcessing ? Icons.hourglass_top : Icons.rocket_launch,
                        isProcessing ? null : () => _handleExecute(provider),
                        large: true,
                      ),
              ),
            ],
          )),
        ),
        const SizedBox(width: 8),
        // Right: Progress / Results
        Expanded(
          child: _stepPanel('PROGRESS', child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isProcessing || isCompleted) ...[
                _buildProgressBar(provider),
                const SizedBox(height: 8),
                _buildProgressLog(provider),
              ] else
                const Center(child: Text(
                  'Configure settings and click Execute',
                  style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12),
                )),
              if (provider.errorMessage != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxForgeTheme.accentRed.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    provider.errorMessage!,
                    style: const TextStyle(color: FluxForgeTheme.accentRed, fontSize: 11),
                  ),
                ),
              ],
            ],
          )),
        ),
      ],
    );
  }

  Widget _buildProgressBar(SfxPipelineProvider provider) {
    final progress = provider.progress;
    final pct = progress.totalFiles > 0
        ? progress.currentFileIndex / progress.totalFiles
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              progress.currentStep.displayName,
              style: const TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
            ),
            Text(
              '${progress.currentFileIndex}/${progress.totalFiles}',
              style: const TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10, fontFamily: 'monospace'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: pct,
          backgroundColor: FluxForgeTheme.bgMid,
          color: FluxForgeTheme.accentCyan,
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
        ),
        if (progress.currentFilename != null) ...[
          const SizedBox(height: 2),
          Text(
            progress.currentFilename!,
            style: const TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildProgressLog(SfxPipelineProvider provider) {
    final result = provider.result;
    if (result == null) return const SizedBox.shrink();

    return Expanded(
      child: ListView(
        children: [
          _logLine('Processed: ${result.successCount} files', FluxForgeTheme.accentGreen),
          _logLine('Skipped: ${result.totalFiles - result.successCount}', FluxForgeTheme.accentOrange),
          _logLine('Errors: ${result.failedCount}', result.failedCount > 0 ? FluxForgeTheme.accentRed : FluxForgeTheme.textTertiary),
          if (result.preset.generateManifest)
            _logLine('Manifest: ${result.outputDirectory}/manifest.json', FluxForgeTheme.accentBlue),
          if (result.preset.generateLufsReport)
            _logLine('LUFS Report: ${result.outputDirectory}/lufs_report.txt', FluxForgeTheme.accentBlue),
        ],
      ),
    );
  }

  Widget _successBanner(SfxPipelineProvider provider) {
    final result = provider.result;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.accentGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: FluxForgeTheme.accentGreen, size: 32),
          const SizedBox(height: 4),
          Text(
            'Pipeline Complete — ${result?.successCount ?? 0} files processed',
            style: const TextStyle(color: FluxForgeTheme.accentGreen, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _actionBtn('Open Folder', Icons.folder_open, () {
                if (result?.outputDirectory != null) {
                  Process.run('open', [result!.outputDirectory]);
                }
              }),
              const SizedBox(width: 8),
              _actionBtn('Close', Icons.close, () => Navigator.of(context).pop(result)),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FOOTER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFooter(SfxPipelineProvider provider) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(top: BorderSide(color: FluxForgeTheme.bgElevated)),
      ),
      child: Row(
        children: [
          // Step description
          Text(
            _steps[provider.currentStep.index].description,
            style: const TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
          ),
          const Spacer(),
          // Navigation buttons
          if (provider.canGoBack && !provider.isProcessing)
            _navBtn('← BACK', false, () => provider.previousStep()),
          const SizedBox(width: 8),
          if (provider.canGoNext && !provider.isProcessing)
            _navBtn('NEXT →', true, () => provider.nextStep()),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _handleScan(SfxPipelineProvider provider) async {
    final path = _sourcePathController.text.trim();
    if (path.isEmpty) return;

    provider.setScanning();
    try {
      final results = await SfxPipelineService.instance.scanDirectory(
        path: path,
        recursive: provider.preset.recursive,
        fileFilter: provider.preset.fileFilter,
      );
      provider.setScanResults(results);
      provider.resetToConfiguring();
    } catch (e) {
      provider.setFailed('Scan failed: $e');
    }
  }

  void _handleAutoMatch(SfxPipelineProvider provider) {
    final selectedFiles = provider.selectedFiles;
    if (selectedFiles.isEmpty) return;

    final mappings = SfxPipelineService.instance.matchFilesToStages(selectedFiles);
    provider.setStageMappings(mappings);
  }

  Future<void> _handleExecute(SfxPipelineProvider provider) async {
    final outputPath = _outputPathController.text.trim();
    if (outputPath.isEmpty) return;

    final updatedPreset = provider.preset.copyWith(
      outputPath: outputPath,
      prefix: _prefixController.text,
      customTemplate: _customTemplateController.text,
      ucsVendor: _ucsVendorController.text,
      ucsProject: _ucsProjectController.text,
    );
    provider.loadPreset(updatedPreset);

    provider.setProcessing();
    try {
      final result = await SfxPipelineService.instance.executePipeline(
        files: provider.selectedFiles,
        stageMappings: provider.stageMappings,
        preset: updatedPreset,
        onProgress: (progress) => provider.updateProgress(progress),
        batchAssign: (stageToPath) {
          // Access SlotLabProjectProvider through context for atomic batch assign
          // This creates ONE undo entry for all assignments (§16 of spec)
          // EventRegistry sync happens through SlotLabScreen listener
          try {
            final projectProvider = context.read<SlotLabProjectProvider>();
            projectProvider.batchSetAudioAssignments(stageToPath);
          } catch (_) {
            // Provider not available outside SlotLab context
          }
        },
      );
      provider.setCompleted(result);
    } catch (e) {
      provider.setFailed('Pipeline failed: $e');
    }
  }

  void _handleClose(SfxPipelineProvider provider) {
    if (provider.isProcessing) {
      // Confirm cancel
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: FluxForgeTheme.bgSurface,
          title: const Text('Cancel Pipeline?', style: TextStyle(color: Colors.white, fontSize: 14)),
          content: const Text('Processing is in progress. Cancel?', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Continue', style: TextStyle(color: FluxForgeTheme.accentBlue)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                provider.setCancelled();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel', style: TextStyle(color: FluxForgeTheme.accentRed)),
            ),
          ],
        ),
      );
    } else {
      Navigator.of(context).pop(provider.result);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REUSABLE WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _stepPanel(String title, {required Widget child, List<Widget>? actions}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FluxForgeTheme.bgElevated),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: FluxForgeTheme.bgElevated)),
              ),
              child: Row(
                children: [
                  Text(title, style: const TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  )),
                  const Spacer(),
                  if (actions != null) ...actions,
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paramRow(String label, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
            )),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _toggle(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 32, height: 16,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: value ? FluxForgeTheme.accentCyan.withValues(alpha: 0.3) : FluxForgeTheme.bgSurface,
          border: Border.all(color: value ? FluxForgeTheme.accentCyan : FluxForgeTheme.bgElevated),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 12, height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _slider(double value, double min, double max, String unit, ValueChanged<double> onChanged) {
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: FluxForgeTheme.accentCyan,
              inactiveTrackColor: FluxForgeTheme.bgElevated,
              thumbColor: FluxForgeTheme.accentCyan,
              overlayColor: FluxForgeTheme.accentCyan.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            '${value.toStringAsFixed(1)} $unit',
            style: const TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10, fontFamily: 'monospace'),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _enumDropdown<T>(List<T> values, T current, ValueChanged<T> onChanged, {required String Function(T) labelOf}) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.bgElevated),
      ),
      child: DropdownButton<T>(
        value: current,
        isDense: true,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: FluxForgeTheme.bgSurface,
        style: const TextStyle(color: Colors.white, fontSize: 11),
        items: values.map((v) => DropdownMenuItem(value: v, child: Text(labelOf(v)))).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }

  Widget _textField(TextEditingController controller, {String? hint}) {
    return SizedBox(
      height: 24,
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 11),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          hintText: hint,
          hintStyle: const TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
          filled: true,
          fillColor: FluxForgeTheme.bgSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: FluxForgeTheme.bgElevated),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: FluxForgeTheme.bgElevated),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: FluxForgeTheme.accentCyan),
          ),
        ),
      ),
    );
  }

  Widget _primaryBtn(String label, IconData icon, VoidCallback? onTap, {bool large = false}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: large ? 24 : 12, vertical: large ? 10 : 6),
        decoration: BoxDecoration(
          color: enabled ? FluxForgeTheme.accentCyan.withValues(alpha: 0.2) : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: enabled ? FluxForgeTheme.accentCyan : FluxForgeTheme.bgElevated),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: large ? 16 : 14, color: enabled ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              color: enabled ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
              fontSize: large ? 13 : 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            )),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.bgElevated),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: FluxForgeTheme.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _navBtn(String label, bool primary, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: primary ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2) : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: primary ? FluxForgeTheme.accentBlue : FluxForgeTheme.bgElevated),
        ),
        child: Text(label, style: TextStyle(
          color: primary ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        )),
      ),
    );
  }

  Widget _miniBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label, style: const TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9)),
      ),
    );
  }

  Widget _statBadge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }

  Widget _statItem(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9)),
          Text(value, style: TextStyle(color: color ?? FluxForgeTheme.textSecondary, fontSize: 9, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _categoryBadge(SfxCategory cat) {
    if (cat == SfxCategory.unknown) return const SizedBox(width: 0);
    const catColors = {
      SfxCategory.uiClicks: FluxForgeTheme.accentPurple,
      SfxCategory.reelMechanics: FluxForgeTheme.accentBlue,
      SfxCategory.winCelebrations: FluxForgeTheme.accentGreen,
      SfxCategory.ambientLoops: FluxForgeTheme.accentCyan,
      SfxCategory.featureTriggers: FluxForgeTheme.accentOrange,
      SfxCategory.anticipation: FluxForgeTheme.accentRed,
      SfxCategory.musicBigWin: Color(0xFFFF6090),
      SfxCategory.musicFeature: Color(0xFF40C8FF),
      SfxCategory.musicBase: Color(0xFF8090A0),
      SfxCategory.music: Color(0xFF9080C0),
      SfxCategory.voiceOver: Color(0xFFFFD740),
    };
    final color = catColors[cat] ?? FluxForgeTheme.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        cat.displayName.split(' ').first,
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _logLine(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 11))),
        ],
      ),
    );
  }
}

/// Step configuration
class _StepConfig {
  final String label;
  final IconData icon;
  final String description;

  const _StepConfig(this.label, this.icon, this.description);
}
