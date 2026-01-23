/// GDD Import Wizard
///
/// Multi-step wizard for importing Game Design Documents:
/// 1. Input (paste JSON or load file)
/// 2. Preview (show parsed GDD summary)
/// 3. Stages (show generated stages)
/// 4. Confirm (apply to SlotLab)
///
/// Part of P3.4: GDD import wizard
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/gdd_import_service.dart';
import '../../services/stage_configuration_service.dart';

/// GDD Import Wizard Dialog
class GddImportWizard extends StatefulWidget {
  const GddImportWizard({super.key});

  /// Show the wizard as a dialog
  static Future<GddImportResult?> show(BuildContext context) {
    return showDialog<GddImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const GddImportWizard(),
    );
  }

  @override
  State<GddImportWizard> createState() => _GddImportWizardState();
}

class _GddImportWizardState extends State<GddImportWizard> {
  int _currentStep = 0;
  final _jsonController = TextEditingController();
  GddImportResult? _importResult;
  bool _isLoading = false;
  String? _error;

  // Step names
  static const _steps = ['Input', 'Preview', 'Stages', 'Confirm'];

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      backgroundColor: const Color(0xFF1a1a20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 700,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.upload_file, color: Color(0xFF4A9EFF), size: 28),
                const SizedBox(width: 12),
                Text(
                  'Import Game Design Document',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Step indicator
            _buildStepIndicator(colorScheme),
            const SizedBox(height: 24),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildStepContent(),
            ),

            // Navigation buttons
            const SizedBox(height: 16),
            _buildNavigationButtons(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(ColorScheme colorScheme) {
    return Row(
      children: List.generate(_steps.length * 2 - 1, (index) {
        if (index.isOdd) {
          // Connector line
          final stepIndex = index ~/ 2;
          return Expanded(
            child: Container(
              height: 2,
              color: _currentStep > stepIndex
                  ? const Color(0xFF4A9EFF)
                  : Colors.white24,
            ),
          );
        } else {
          // Step circle
          final stepIndex = index ~/ 2;
          final isActive = stepIndex == _currentStep;
          final isComplete = stepIndex < _currentStep;

          return Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isComplete
                  ? const Color(0xFF4A9EFF)
                  : isActive
                      ? const Color(0xFF4A9EFF).withValues(alpha: 0.3)
                      : Colors.white12,
              border: isActive
                  ? Border.all(color: const Color(0xFF4A9EFF), width: 2)
                  : null,
            ),
            child: Center(
              child: isComplete
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        color: isActive ? const Color(0xFF4A9EFF) : Colors.white54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          );
        }
      }),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildInputStep();
      case 1:
        return _buildPreviewStep();
      case 2:
        return _buildStagesStep();
      case 3:
        return _buildConfirmStep();
      default:
        return const SizedBox();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1: INPUT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInputStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Paste GDD JSON or load from file:',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 12),

        // Action buttons
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _loadFromFile,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Load File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2a2a30),
                foregroundColor: Colors.white70,
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _pasteFromClipboard,
              icon: const Icon(Icons.paste, size: 18),
              label: const Text('Paste'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2a2a30),
                foregroundColor: Colors.white70,
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _loadSampleGdd,
              icon: const Icon(Icons.science, size: 18),
              label: const Text('Load Sample'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2a2a30),
                foregroundColor: Colors.white70,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // JSON input
        Expanded(
          child: TextField(
            controller: _jsonController,
            maxLines: null,
            expands: true,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText: '{\n  "name": "My Slot",\n  "grid": { ... },\n  ...\n}',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              filled: true,
              fillColor: const Color(0xFF121216),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // Error display
        if (_error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _loadFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.single.path != null) {
      try {
        final bytes = result.files.single.bytes;
        if (bytes != null) {
          _jsonController.text = utf8.decode(bytes);
          setState(() => _error = null);
        }
      } catch (e) {
        setState(() => _error = 'Failed to read file: $e');
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _jsonController.text = data!.text!;
      setState(() => _error = null);
    }
  }

  void _loadSampleGdd() {
    _jsonController.text = GddImportService.instance.createSampleGddJson();
    setState(() => _error = null);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2: PREVIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPreviewStep() {
    final gdd = _importResult?.gdd;
    if (gdd == null) {
      return const Center(
        child: Text('No GDD loaded', style: TextStyle(color: Colors.white54)),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Game Info
          _buildSection('Game Information', [
            _buildRow('Name', gdd.name),
            _buildRow('Version', gdd.version),
            if (gdd.description != null) _buildRow('Description', gdd.description!),
          ]),

          const SizedBox(height: 16),

          // Grid Config
          _buildSection('Grid Configuration', [
            _buildRow('Size', '${gdd.grid.columns} x ${gdd.grid.rows}'),
            _buildRow('Mechanic', gdd.grid.mechanic),
            if (gdd.grid.paylines != null)
              _buildRow('Paylines', '${gdd.grid.paylines}'),
            if (gdd.grid.ways != null)
              _buildRow('Ways', '${gdd.grid.ways}'),
          ]),

          const SizedBox(height: 16),

          // Math Model
          _buildSection('Math Model', [
            _buildRow('RTP', '${(gdd.math.rtp * 100).toStringAsFixed(2)}%'),
            _buildRow('Volatility', gdd.math.volatility),
            _buildRow('Hit Frequency', '${(gdd.math.hitFrequency * 100).toStringAsFixed(1)}%'),
            _buildRow('Win Tiers', '${gdd.math.winTiers.length}'),
          ]),

          const SizedBox(height: 16),

          // Symbols
          _buildSection('Symbols (${gdd.symbols.length})', [
            for (final tier in SymbolTier.values)
              if (gdd.symbolsByTier(tier).isNotEmpty)
                _buildRow(
                  tier.label,
                  gdd.symbolsByTier(tier).map((s) => s.name).join(', '),
                ),
          ]),

          const SizedBox(height: 16),

          // Features
          _buildSection('Features (${gdd.features.length})', [
            for (final feature in gdd.features)
              _buildRow(feature.name, feature.type.label),
          ]),

          // Warnings
          if (_importResult?.hasWarnings ?? false) ...[
            const SizedBox(height: 16),
            _buildSection('Warnings', [
              for (final warning in _importResult!.warnings)
                _buildWarningRow(warning),
            ], icon: Icons.warning_amber, color: Colors.orange),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children,
      {IconData icon = Icons.info_outline, Color color = const Color(0xFF4A9EFF)}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF121216),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningRow(String warning) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              warning,
              style: const TextStyle(color: Colors.orange, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 3: STAGES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStagesStep() {
    final stages = _importResult?.generatedStages ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.layers, size: 16, color: Color(0xFF40FF90)),
            const SizedBox(width: 8),
            Text(
              '${stages.length} stages will be registered',
              style: const TextStyle(
                color: Color(0xFF40FF90),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Stages list
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF121216),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              itemCount: stages.length,
              itemBuilder: (context, index) {
                final stage = stages[index];
                final category = _getCategoryForStage(stage);
                final color = _getColorForCategory(category);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        stage,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        category,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  String _getCategoryForStage(String stage) {
    if (stage.startsWith('SPIN_') || stage.startsWith('REEL_')) return 'Spin';
    if (stage.startsWith('WIN_') || stage.startsWith('ROLLUP_')) return 'Win';
    if (stage.startsWith('FS_')) return 'Free Spins';
    if (stage.startsWith('BONUS_')) return 'Bonus';
    if (stage.startsWith('HOLD_')) return 'Hold & Spin';
    if (stage.startsWith('CASCADE_')) return 'Cascade';
    if (stage.startsWith('JACKPOT_')) return 'Jackpot';
    if (stage.startsWith('GAMBLE_')) return 'Gamble';
    if (stage.startsWith('WILD_')) return 'Wild';
    if (stage.startsWith('SCATTER_') || stage.startsWith('ANTICIPATION_')) return 'Scatter';
    if (stage.startsWith('SYMBOL_')) return 'Symbol';
    if (stage.startsWith('MULT_')) return 'Multiplier';
    return 'Custom';
  }

  Color _getColorForCategory(String category) {
    return switch (category) {
      'Spin' => const Color(0xFF4A9EFF),
      'Win' => const Color(0xFFFFD700),
      'Free Spins' || 'Bonus' => const Color(0xFF40FF90),
      'Hold & Spin' => const Color(0xFFFF9040),
      'Cascade' => const Color(0xFF40C8FF),
      'Jackpot' => const Color(0xFFFF4040),
      'Gamble' => const Color(0xFFE040FB),
      'Wild' || 'Scatter' => const Color(0xFFFFB6C1),
      'Symbol' => const Color(0xFF888888),
      'Multiplier' => const Color(0xFFFF9040),
      _ => Colors.white54,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 4: CONFIRM
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildConfirmStep() {
    final gdd = _importResult?.gdd;
    final stages = _importResult?.generatedStages ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, size: 48, color: Color(0xFF40FF90)),
        const SizedBox(height: 16),

        Text(
          'Ready to Import',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),

        const Text(
          'The following will be configured:',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 16),

        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121216),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummaryRow('Game', gdd?.name ?? 'Unknown'),
              _buildSummaryRow('Grid', '${gdd?.grid.columns ?? 5} x ${gdd?.grid.rows ?? 3}'),
              _buildSummaryRow('Symbols', '${gdd?.symbols.length ?? 0}'),
              _buildSummaryRow('Features', '${gdd?.features.length ?? 0}'),
              _buildSummaryRow('Stages', '$stages'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF4A9EFF).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF4A9EFF).withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xFF4A9EFF), size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Custom stages will be registered with StageConfigurationService. '
                  'You can then create audio events for each stage in the Event Editor.',
                  style: TextStyle(color: Color(0xFF4A9EFF), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.check, size: 16, color: Color(0xFF40FF90)),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NAVIGATION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNavigationButtons(ColorScheme colorScheme) {
    return Row(
      children: [
        if (_currentStep > 0)
          TextButton(
            onPressed: () => setState(() => _currentStep--),
            child: const Text('Back'),
          ),
        const Spacer(),
        if (_currentStep < _steps.length - 1)
          ElevatedButton(
            onPressed: _canProceed ? _nextStep : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A9EFF),
              foregroundColor: Colors.white,
            ),
            child: const Text('Next'),
          )
        else
          ElevatedButton(
            onPressed: _finishImport,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF40FF90),
              foregroundColor: Colors.black,
            ),
            child: const Text('Import'),
          ),
      ],
    );
  }

  bool get _canProceed {
    switch (_currentStep) {
      case 0:
        return _jsonController.text.trim().isNotEmpty;
      case 1:
      case 2:
        return _importResult != null && !_importResult!.hasErrors;
      default:
        return true;
    }
  }

  void _nextStep() {
    if (_currentStep == 0) {
      // Parse JSON
      final result = GddImportService.instance.importFromJson(_jsonController.text);
      if (result == null || result.hasErrors) {
        setState(() {
          _error = result?.errors.join('\n') ?? 'Failed to parse GDD';
        });
        return;
      }
      setState(() {
        _importResult = result;
        _error = null;
      });
    }

    setState(() => _currentStep++);
  }

  void _finishImport() {
    if (_importResult == null) return;

    // Register custom stages with StageConfigurationService
    final service = StageConfigurationService.instance;
    for (final stageName in _importResult!.generatedStages) {
      // Skip if already registered
      if (service.getStage(stageName) != null) continue;

      // Create custom stage definition
      final category = _inferCategory(stageName);
      final priority = service.getPriority(stageName);
      final bus = service.getBus(stageName);

      service.registerCustomStage(StageDefinition(
        name: stageName,
        category: category,
        priority: priority,
        bus: bus,
        spatialIntent: service.getSpatialIntent(stageName),
      ));
    }

    Navigator.of(context).pop(_importResult);
  }

  StageCategory _inferCategory(String stage) {
    if (stage.startsWith('SPIN_') || stage.startsWith('REEL_')) return StageCategory.spin;
    if (stage.startsWith('WIN_') || stage.startsWith('ROLLUP_')) return StageCategory.win;
    if (stage.startsWith('FS_')) return StageCategory.feature;
    if (stage.startsWith('BONUS_')) return StageCategory.feature;
    if (stage.startsWith('HOLD_')) return StageCategory.hold;
    if (stage.startsWith('CASCADE_') || stage.startsWith('TUMBLE_')) return StageCategory.cascade;
    if (stage.startsWith('JACKPOT_')) return StageCategory.jackpot;
    if (stage.startsWith('GAMBLE_')) return StageCategory.gamble;
    if (stage.startsWith('WILD_') || stage.startsWith('SCATTER_') || stage.startsWith('SYMBOL_')) return StageCategory.symbol;
    if (stage.startsWith('MUSIC_') || stage.startsWith('AMBIENT_')) return StageCategory.music;
    if (stage.startsWith('UI_')) return StageCategory.ui;
    return StageCategory.custom;
  }
}
