/// Adapter Wizard Panel — Universal Stage Ingest Configuration
///
/// Multi-step wizard for configuring engine adapters:
/// 1. Select JSON source (file or paste)
/// 2. Review auto-detected event mappings
/// 3. Fine-tune stage assignments
/// 4. Select ingest layer
/// 5. Test and export config
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/stage_models.dart';
import '../../providers/stage_provider.dart';

/// Adapter Wizard Panel widget
class AdapterWizardPanel extends StatelessWidget {
  const AdapterWizardPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AdapterWizardProvider(
        context.read<StageProvider>(),
      ),
      child: const _WizardContent(),
    );
  }
}

class _WizardContent extends StatelessWidget {
  const _WizardContent();

  @override
  Widget build(BuildContext context) {
    final wizard = context.watch<AdapterWizardProvider>();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2a2a35)),
      ),
      child: Column(
        children: [
          // Header
          _WizardHeader(currentStep: wizard.currentStep),

          // Content area
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildStepContent(context, wizard),
            ),
          ),

          // Footer with navigation
          _WizardFooter(wizard: wizard),
        ],
      ),
    );
  }

  Widget _buildStepContent(BuildContext context, AdapterWizardProvider wizard) {
    return switch (wizard.currentStep) {
      WizardStep.selectSource => _SelectSourceStep(wizard: wizard),
      WizardStep.reviewDetection => _ReviewDetectionStep(wizard: wizard),
      WizardStep.configureMapping => _ConfigureMappingStep(wizard: wizard),
      WizardStep.selectLayer => _SelectLayerStep(wizard: wizard),
      WizardStep.testParse => _TestParseStep(wizard: wizard),
      WizardStep.complete => _CompleteStep(wizard: wizard),
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════

class _WizardHeader extends StatelessWidget {
  final WizardStep currentStep;

  const _WizardHeader({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2a2a35))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_fix_high, color: Color(0xFF4a9eff), size: 24),
              const SizedBox(width: 12),
              const Text(
                'Adapter Wizard',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Text(
                'Step ${currentStep.index + 1} of ${WizardStep.values.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF808090),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StepIndicator(currentStep: currentStep),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final WizardStep currentStep;

  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: WizardStep.values.map((step) {
        final isActive = step.index <= currentStep.index;
        final isCurrent = step == currentStep;

        return Expanded(
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? const Color(0xFF4a9eff) : const Color(0xFF2a2a35),
                  border: isCurrent
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(
                    '${step.index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isActive ? Colors.white : const Color(0xFF606070),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (step.index < WizardStep.values.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    color: isActive ? const Color(0xFF4a9eff) : const Color(0xFF2a2a35),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 1: SELECT SOURCE
// ═══════════════════════════════════════════════════════════════════════════

class _SelectSourceStep extends StatefulWidget {
  final AdapterWizardProvider wizard;

  const _SelectSourceStep({required this.wizard});

  @override
  State<_SelectSourceStep> createState() => _SelectSourceStepState();
}

class _SelectSourceStepState extends State<_SelectSourceStep> {
  final _jsonController = TextEditingController();
  bool _isValidJson = false;
  String? _parseError;

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  void _validateJson(String text) {
    if (text.trim().isEmpty) {
      setState(() {
        _isValidJson = false;
        _parseError = null;
      });
      return;
    }

    try {
      jsonDecode(text);
      setState(() {
        _isValidJson = true;
        _parseError = null;
      });
      widget.wizard.setJsonContent(text);
    } catch (e) {
      setState(() {
        _isValidJson = false;
        _parseError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste Engine JSON',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Paste a sample JSON from your game engine to auto-detect event mappings.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF808090),
            ),
          ),
          const SizedBox(height: 16),

          // JSON input area
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF121216),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _parseError != null
                      ? const Color(0xFFff4040)
                      : _isValidJson
                          ? const Color(0xFF40ff90)
                          : const Color(0xFF2a2a35),
                ),
              ),
              child: TextField(
                controller: _jsonController,
                onChanged: _validateJson,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white70,
                ),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(12),
                  border: InputBorder.none,
                  hintText: '{\n  "type": "spin_start",\n  "data": {...}\n}',
                  hintStyle: TextStyle(color: Color(0xFF505060)),
                ),
              ),
            ),
          ),

          if (_parseError != null) ...[
            const SizedBox(height: 8),
            Text(
              _parseError!,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFff4040),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Actions row
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    _jsonController.text = data!.text!;
                    _validateJson(data.text!);
                  }
                },
                icon: const Icon(Icons.paste, size: 16),
                label: const Text('Paste from Clipboard'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4a9eff),
                  side: const BorderSide(color: Color(0xFF4a9eff)),
                ),
              ),
              const Spacer(),
              if (_isValidJson)
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF40ff90), size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Valid JSON',
                      style: TextStyle(color: Color(0xFF40ff90), fontSize: 12),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 2: REVIEW DETECTION
// ═══════════════════════════════════════════════════════════════════════════

class _ReviewDetectionStep extends StatelessWidget {
  final AdapterWizardProvider wizard;

  const _ReviewDetectionStep({required this.wizard});

  @override
  Widget build(BuildContext context) {
    final result = wizard.result;

    if (wizard.isAnalyzing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF4a9eff)),
            SizedBox(height: 16),
            Text(
              'Analyzing JSON structure...',
              style: TextStyle(color: Color(0xFF808090)),
            ),
          ],
        ),
      );
    }

    if (result == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber, color: Color(0xFFff9040), size: 48),
            const SizedBox(height: 16),
            Text(
              wizard.errorMessage ?? 'Analysis failed',
              style: const TextStyle(color: Color(0xFFff9040)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => wizard.previousStep(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Confidence badge
          _ConfidenceBadge(result: result),

          const SizedBox(height: 24),

          // Detection summary
          _DetectionSummary(result: result),

          const SizedBox(height: 24),

          // Detected events
          const Text(
            'Detected Events',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),

          ...result.detectedEvents.map(
            (event) => _DetectedEventCard(event: event),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  final WizardResult result;

  const _ConfidenceBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    final percentage = (result.confidence * 100).toInt();
    final color = switch (result.confidenceLabel) {
      'Excellent' => const Color(0xFF40ff90),
      'Good' => const Color(0xFF4a9eff),
      'Fair' => const Color(0xFFffff40),
      _ => const Color(0xFFff9040),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.analytics, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detection Confidence: ${result.confidenceLabel}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: result.confidence,
                  backgroundColor: const Color(0xFF2a2a35),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$percentage%',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectionSummary extends StatelessWidget {
  final WizardResult result;

  const _DetectionSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: 'Company',
            value: result.detectedCompany ?? 'Unknown',
          ),
          const Divider(color: Color(0xFF2a2a35)),
          _SummaryRow(
            label: 'Engine',
            value: result.detectedEngine ?? 'Unknown',
          ),
          const Divider(color: Color(0xFF2a2a35)),
          _SummaryRow(
            label: 'Recommended Layer',
            value: result.recommendedLayer.displayName,
          ),
          const Divider(color: Color(0xFF2a2a35)),
          _SummaryRow(
            label: 'Events Detected',
            value: '${result.detectedEvents.length}',
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF808090),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectedEventCard extends StatelessWidget {
  final DetectedEvent event;

  const _DetectedEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final hasMapping = event.suggestedStage != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasMapping
              ? const Color(0xFF40ff90).withValues(alpha: 0.3)
              : const Color(0xFF2a2a35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasMapping ? Icons.check_circle : Icons.help_outline,
            color: hasMapping ? const Color(0xFF40ff90) : const Color(0xFF808090),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.eventName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${event.sampleCount} occurrences',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF606070),
                  ),
                ),
              ],
            ),
          ),
          if (hasMapping)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4a9eff).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '→ ${event.suggestedStage}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF4a9eff),
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            const Text(
              'No mapping',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF606070),
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 3: CONFIGURE MAPPING
// ═══════════════════════════════════════════════════════════════════════════

class _ConfigureMappingStep extends StatelessWidget {
  final AdapterWizardProvider wizard;

  const _ConfigureMappingStep({required this.wizard});

  @override
  Widget build(BuildContext context) {
    final result = wizard.result;
    if (result == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fine-tune Event Mappings',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Adjust the stage assignments for detected events.',
            style: TextStyle(fontSize: 12, color: Color(0xFF808090)),
          ),
          const SizedBox(height: 16),

          ...result.detectedEvents.map(
            (event) => _EventMappingEditor(
              event: event,
              onChanged: (stage) => wizard.setEventMapping(event.eventName, stage),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventMappingEditor extends StatelessWidget {
  final DetectedEvent event;
  final ValueChanged<String> onChanged;

  const _EventMappingEditor({
    required this.event,
    required this.onChanged,
  });

  static const _stageOptions = [
    'SpinStart',
    'ReelSpinning',
    'ReelStop',
    'EvaluateWins',
    'SpinEnd',
    'AnticipationOn',
    'AnticipationOff',
    'WinPresent',
    'WinLineShow',
    'RollupStart',
    'RollupEnd',
    'BigWinTier',
    'FeatureEnter',
    'FeatureStep',
    'FeatureExit',
    'CascadeStart',
    'CascadeStep',
    'CascadeEnd',
    'BonusEnter',
    'BonusChoice',
    'BonusReveal',
    'BonusExit',
    'GambleStart',
    'GambleResult',
    'GambleEnd',
    'JackpotTrigger',
    'JackpotPresent',
    'JackpotEnd',
    'IdleStart',
    'IdleLoop',
    '(None)',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.eventName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${event.sampleCount} samples',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF606070),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward, color: Color(0xFF606070), size: 16),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: event.suggestedStage ?? '(None)',
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              dropdownColor: const Color(0xFF1a1a20),
              style: const TextStyle(fontSize: 12, color: Colors.white),
              items: _stageOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (value) {
                if (value != null) onChanged(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 4: SELECT LAYER
// ═══════════════════════════════════════════════════════════════════════════

class _SelectLayerStep extends StatelessWidget {
  final AdapterWizardProvider wizard;

  const _SelectLayerStep({required this.wizard});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Ingest Layer',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose how FluxForge should interpret engine data.',
            style: TextStyle(fontSize: 12, color: Color(0xFF808090)),
          ),
          const SizedBox(height: 24),

          _LayerOption(
            layer: IngestLayer.directEvent,
            isSelected: wizard.selectedLayer == IngestLayer.directEvent,
            isRecommended:
                wizard.result?.recommendedLayer == IngestLayer.directEvent,
            onTap: () => wizard.setSelectedLayer(IngestLayer.directEvent),
          ),

          _LayerOption(
            layer: IngestLayer.snapshotDiff,
            isSelected: wizard.selectedLayer == IngestLayer.snapshotDiff,
            isRecommended:
                wizard.result?.recommendedLayer == IngestLayer.snapshotDiff,
            onTap: () => wizard.setSelectedLayer(IngestLayer.snapshotDiff),
          ),

          _LayerOption(
            layer: IngestLayer.ruleBased,
            isSelected: wizard.selectedLayer == IngestLayer.ruleBased,
            isRecommended:
                wizard.result?.recommendedLayer == IngestLayer.ruleBased,
            onTap: () => wizard.setSelectedLayer(IngestLayer.ruleBased),
          ),
        ],
      ),
    );
  }
}

class _LayerOption extends StatelessWidget {
  final IngestLayer layer;
  final bool isSelected;
  final bool isRecommended;
  final VoidCallback onTap;

  const _LayerOption({
    required this.layer,
    required this.isSelected,
    required this.isRecommended,
    required this.onTap,
  });

  String get _description => switch (layer) {
        IngestLayer.directEvent =>
          'Maps engine event names directly to stages. Best for engines with clear event semantics.',
        IngestLayer.snapshotDiff =>
          'Compares consecutive state snapshots to derive stages. Best for state-based engines.',
        IngestLayer.ruleBased =>
          'Uses heuristic rules to reconstruct stages from raw data. Fallback for complex engines.',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4a9eff).withValues(alpha: 0.1)
              : const Color(0xFF121216),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4a9eff)
                : const Color(0xFF2a2a35),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: isSelected,
              onChanged: (_) => onTap(),
              activeColor: const Color(0xFF4a9eff),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        layer.displayName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF40ff90),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Recommended',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF808090),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 5: TEST PARSE
// ═══════════════════════════════════════════════════════════════════════════

class _TestParseStep extends StatefulWidget {
  final AdapterWizardProvider wizard;

  const _TestParseStep({required this.wizard});

  @override
  State<_TestParseStep> createState() => _TestParseStepState();
}

class _TestParseStepState extends State<_TestParseStep> {
  bool _isTesting = false;
  List<_ParsedStage>? _results;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Test Configuration',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Parse the sample JSON with your configuration to verify correctness.',
            style: TextStyle(fontSize: 12, color: Color(0xFF808090)),
          ),
          const SizedBox(height: 24),

          Center(
            child: ElevatedButton.icon(
              onPressed: _isTesting ? null : _runTest,
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isTesting ? 'Testing...' : 'Run Test'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4a9eff),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Test results
          Expanded(
            child: _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFff4040), size: 48),
            const SizedBox(height: 12),
            Text(
              'Parse Error',
              style: const TextStyle(color: Color(0xFFff4040), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFF808090), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_results == null) {
      return const Center(
        child: Text(
          'Click "Run Test" to parse sample data',
          style: TextStyle(color: Color(0xFF606070)),
        ),
      );
    }

    if (_results!.isEmpty) {
      return const Center(
        child: Text(
          'No stages detected. Check your configuration.',
          style: TextStyle(color: Color(0xFFffff40)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF40ff90), size: 18),
            const SizedBox(width: 8),
            Text(
              'Detected ${_results!.length} stages',
              style: const TextStyle(color: Color(0xFF40ff90), fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF121216),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2a2a35)),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _results!.length,
              itemBuilder: (context, index) {
                final stage = _results![index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2a2a35),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF808090),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: stage.categoryColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stage.stageName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            if (stage.sourceEvent != null)
                              Text(
                                'from: ${stage.sourceEvent}',
                                style: const TextStyle(
                                  color: Color(0xFF606070),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        stage.category,
                        style: TextStyle(
                          color: stage.categoryColor.withValues(alpha: 0.8),
                          fontSize: 10,
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

  Future<void> _runTest() async {
    final jsonContent = widget.wizard.jsonContent;
    if (jsonContent == null || jsonContent.isEmpty) {
      setState(() {
        _error = 'No JSON content to parse';
        _results = null;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _error = null;
      _results = null;
    });

    try {
      // Simulate parsing based on detected events
      await Future.delayed(const Duration(milliseconds: 500));

      final result = widget.wizard.result;
      if (result == null) {
        setState(() {
          _error = 'No wizard result available';
          _isTesting = false;
        });
        return;
      }

      // Generate parsed stages from detected events
      final stages = result.detectedEvents
          .where((e) => e.suggestedStage != null)
          .map((e) => _ParsedStage(
                stageName: e.suggestedStage!,
                sourceEvent: e.eventName,
                category: _getCategoryFromStage(e.suggestedStage!),
                categoryColor: _getCategoryColor(e.suggestedStage!),
              ))
          .toList();

      setState(() {
        _results = stages;
        _isTesting = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isTesting = false;
      });
    }
  }

  String _getCategoryFromStage(String stageName) {
    if (stageName.contains('spin') || stageName.contains('reel')) {
      return 'spin';
    } else if (stageName.contains('win') || stageName.contains('rollup')) {
      return 'win';
    } else if (stageName.contains('feature') || stageName.contains('free')) {
      return 'feature';
    } else if (stageName.contains('anticipation')) {
      return 'anticipation';
    } else if (stageName.contains('jackpot')) {
      return 'jackpot';
    } else if (stageName.contains('bonus')) {
      return 'bonus';
    }
    return 'other';
  }

  Color _getCategoryColor(String stageName) {
    final category = _getCategoryFromStage(stageName);
    return switch (category) {
      'spin' => const Color(0xFF4a9eff),
      'win' => const Color(0xFF40ff90),
      'feature' => const Color(0xFFff40ff),
      'anticipation' => const Color(0xFFff9040),
      'jackpot' => const Color(0xFFffd700),
      'bonus' => const Color(0xFFffff40),
      _ => const Color(0xFF808090),
    };
  }
}

class _ParsedStage {
  final String stageName;
  final String? sourceEvent;
  final String category;
  final Color categoryColor;

  _ParsedStage({
    required this.stageName,
    this.sourceEvent,
    required this.category,
    required this.categoryColor,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 6: COMPLETE
// ═══════════════════════════════════════════════════════════════════════════

class _CompleteStep extends StatelessWidget {
  final AdapterWizardProvider wizard;

  const _CompleteStep({required this.wizard});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle,
            color: Color(0xFF40ff90),
            size: 64,
          ),
          const SizedBox(height: 24),
          const Text(
            'Adapter Configuration Complete!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your adapter is ready to use.',
            style: TextStyle(fontSize: 14, color: Color(0xFF808090)),
          ),
          const SizedBox(height: 32),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _exportConfig(context, wizard),
                icon: const Icon(Icons.download),
                label: const Text('Export Config'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4a9eff),
                  side: const BorderSide(color: Color(0xFF4a9eff)),
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => _copyConfigToClipboard(context, wizard),
                icon: const Icon(Icons.content_copy),
                label: const Text('Copy YAML'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF808090),
                  side: const BorderSide(color: Color(0xFF2a2a35)),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: wizard.reset,
                icon: const Icon(Icons.refresh),
                label: const Text('Start Over'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4a9eff),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _exportConfig(BuildContext context, AdapterWizardProvider wizard) {
    final config = _generateYamlConfig(wizard);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Export Adapter Config',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'YAML Configuration:',
                style: TextStyle(color: Color(0xFF808090), fontSize: 12),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121216),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2a2a35)),
                  ),
                  child: SelectableText(
                    config,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFF40c8ff),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Color(0xFF808090))),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: config));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Config copied to clipboard'),
                  backgroundColor: Color(0xFF40ff90),
                ),
              );
            },
            icon: const Icon(Icons.content_copy, size: 16),
            label: const Text('Copy'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4a9eff),
            ),
          ),
        ],
      ),
    );
  }

  void _copyConfigToClipboard(BuildContext context, AdapterWizardProvider wizard) {
    final config = _generateYamlConfig(wizard);
    Clipboard.setData(ClipboardData(text: config));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('YAML config copied to clipboard'),
        backgroundColor: Color(0xFF40ff90),
      ),
    );
  }

  String _generateYamlConfig(AdapterWizardProvider wizard) {
    final result = wizard.result;
    if (result == null) return '# No configuration available';

    final buffer = StringBuffer();
    buffer.writeln('# FluxForge Stage Adapter Configuration');
    buffer.writeln('# Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln();
    buffer.writeln('adapter:');
    buffer.writeln('  id: "${result.detectedCompany ?? "custom"}-adapter"');
    buffer.writeln('  name: "${result.detectedEngine ?? "Custom"} Adapter"');
    buffer.writeln('  version: "1.0.0"');
    buffer.writeln();
    buffer.writeln('ingest:');
    buffer.writeln('  layer: ${wizard.selectedLayer.toJson()}');
    buffer.writeln('  confidence: ${(result.confidence * 100).toStringAsFixed(1)}%');
    buffer.writeln();
    buffer.writeln('event_mapping:');

    for (final event in result.detectedEvents) {
      if (event.suggestedStage != null) {
        buffer.writeln('  - event: "${event.eventName}"');
        buffer.writeln('    stage: ${event.suggestedStage}');
        if (event.samplePayload != null) {
          buffer.writeln('    # Sample: ${event.samplePayload}');
        }
      }
    }

    buffer.writeln();
    buffer.writeln('# To use this adapter:');
    buffer.writeln('# 1. Save as adapters/custom-adapter.yaml');
    buffer.writeln('# 2. Load via StageProvider.loadAdapterConfig()');
    buffer.writeln('# 3. Connect to engine with adapterId: "custom-adapter"');

    return buffer.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FOOTER
// ═══════════════════════════════════════════════════════════════════════════

class _WizardFooter extends StatelessWidget {
  final AdapterWizardProvider wizard;

  const _WizardFooter({required this.wizard});

  @override
  Widget build(BuildContext context) {
    final isFirst = wizard.currentStep == WizardStep.selectSource;
    final isLast = wizard.currentStep == WizardStep.complete;
    final canProceed = _canProceed();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2a2a35))),
      ),
      child: Row(
        children: [
          if (!isFirst && !isLast)
            OutlinedButton(
              onPressed: wizard.previousStep,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF808090),
                side: const BorderSide(color: Color(0xFF2a2a35)),
              ),
              child: const Text('Back'),
            ),
          const Spacer(),
          if (!isLast)
            ElevatedButton(
              onPressed: canProceed ? _onNext : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4a9eff),
                disabledBackgroundColor: const Color(0xFF2a2a35),
              ),
              child: Text(
                wizard.currentStep == WizardStep.selectSource
                    ? 'Analyze'
                    : wizard.currentStep == WizardStep.testParse
                        ? 'Finish'
                        : 'Next',
              ),
            ),
        ],
      ),
    );
  }

  bool _canProceed() {
    return switch (wizard.currentStep) {
      WizardStep.selectSource => wizard.jsonContent?.isNotEmpty == true,
      WizardStep.reviewDetection => wizard.result != null,
      _ => true,
    };
  }

  void _onNext() {
    if (wizard.currentStep == WizardStep.selectSource) {
      wizard.analyze();
    } else if (wizard.currentStep == WizardStep.testParse) {
      wizard.finish();
    } else {
      wizard.nextStep();
    }
  }
}
