/// Slot Audio Automation Panel
///
/// UI for the Ultimate Slot Audio Automation System.
/// Provides visual interfaces for all automation features.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/auto_event_builder_models.dart';
import '../../models/middleware_models.dart' show ActionType;
import '../../providers/middleware_provider.dart';
import '../../services/slot_audio_automation_service.dart';
import '../../theme/fluxforge_theme.dart';

// =============================================================================
// MAIN AUTOMATION PANEL
// =============================================================================

/// Main panel for slot audio automation features
class SlotAutomationPanel extends StatefulWidget {
  /// Callback when events are generated
  final void Function(List<AutoEventSpec> events)? onEventsGenerated;

  const SlotAutomationPanel({
    super.key,
    this.onEventsGenerated,
  });

  @override
  State<SlotAutomationPanel> createState() => _SlotAutomationPanelState();
}

class _SlotAutomationPanelState extends State<SlotAutomationPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _service = SlotAudioAutomationService.instance;

  // Reel generator state
  int _reelCount = 5;
  String? _reelAudioPath;

  // Win tier state
  final Map<WinTier, String?> _winTierPaths = {};

  // Cascade state
  int _cascadeStepCount = 8;
  String? _cascadeAudioPath;

  // Batch import state
  final List<String> _batchPaths = [];
  AutomationResult? _batchAnalysis;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        Container(
          color: FluxForgeTheme.surfaceDark,
          child: TabBar(
            controller: _tabController,
            indicatorColor: FluxForgeTheme.accentBlue,
            labelColor: FluxForgeTheme.textPrimary,
            unselectedLabelColor: FluxForgeTheme.textMuted,
            tabs: const [
              Tab(icon: Icon(Icons.view_column, size: 16), text: 'Reel Set'),
              Tab(icon: Icon(Icons.emoji_events, size: 16), text: 'Win Tiers'),
              Tab(icon: Icon(Icons.view_list, size: 16), text: 'Templates'),
              Tab(icon: Icon(Icons.folder_open, size: 16), text: 'Batch'),
            ],
          ),
        ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildReelSetTab(),
              _buildWinTiersTab(),
              _buildTemplatesTab(),
              _buildBatchTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REEL SET GENERATOR TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildReelSetTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.view_column, color: FluxForgeTheme.accentCyan, size: 20),
              const SizedBox(width: 8),
              Text(
                'Reel Set Generator',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Drop one audio file → Generate events for all reels with auto-pan',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 11,
            ),
          ),

          const SizedBox(height: 16),

          // Drop zone
          _buildDropZone(
            label: 'Drop Reel Stop Audio',
            currentPath: _reelAudioPath,
            onPathSelected: (path) => setState(() => _reelAudioPath = path),
          ),

          const SizedBox(height: 16),

          // Reel count slider
          Row(
            children: [
              Text(
                'Reels:',
                style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: _reelCount.toDouble(),
                  min: 3,
                  max: 7,
                  divisions: 4,
                  label: '$_reelCount',
                  activeColor: FluxForgeTheme.accentCyan,
                  onChanged: (v) => setState(() => _reelCount = v.round()),
                ),
              ),
              Text(
                '$_reelCount',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Preview
          if (_reelAudioPath != null) ...[
            _buildPreviewCard(
              title: 'Preview: $_reelCount Reel Events',
              items: List.generate(_reelCount, (i) {
                final pan = (i - (_reelCount - 1) / 2) * (1.6 / (_reelCount - 1));
                return 'REEL_STOP_$i (pan: ${pan.toStringAsFixed(1)})';
              }),
            ),
            const SizedBox(height: 12),
          ],

          // Generate button
          const Spacer(),
          _buildGenerateButton(
            enabled: _reelAudioPath != null,
            label: 'Generate $_reelCount Reel Events',
            onPressed: _generateReelSet,
          ),
        ],
      ),
    );
  }

  void _generateReelSet() {
    if (_reelAudioPath == null) return;

    final result = _service.generateReelSet(
      audioPath: _reelAudioPath!,
      reelCount: _reelCount,
    );

    _showResultDialog(result);
    widget.onEventsGenerated?.call(result.events);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN TIERS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildWinTiersTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.emoji_events, color: FluxForgeTheme.accentOrange, size: 20),
              const SizedBox(width: 8),
              Text(
                'Win Tier Escalation',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Assign audio to each win tier with automatic volume scaling',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 11,
            ),
          ),

          const SizedBox(height: 16),

          // Tier slots
          Expanded(
            child: ListView(
              children: WinTier.values.map((tier) {
                return _buildWinTierSlot(tier);
              }).toList(),
            ),
          ),

          const SizedBox(height: 12),

          // Generate button
          _buildGenerateButton(
            enabled: _winTierPaths.values.any((p) => p != null),
            label: 'Generate ${_winTierPaths.values.where((p) => p != null).length} Win Events',
            onPressed: _generateWinTiers,
          ),
        ],
      ),
    );
  }

  Widget _buildWinTierSlot(WinTier tier) {
    final path = _winTierPaths[tier];
    final volumeScale = {
      WinTier.small: 0.7,
      WinTier.medium: 0.8,
      WinTier.big: 0.9,
      WinTier.mega: 1.0,
      WinTier.epic: 1.0,
      WinTier.ultra: 1.0,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: path != null
              ? FluxForgeTheme.accentOrange.withValues(alpha: 0.5)
              : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          // Tier badge
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _winTierColor(tier).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tier.name.toUpperCase(),
              style: TextStyle(
                color: _winTierColor(tier),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(width: 8),

          // Volume indicator
          Text(
            '${((volumeScale[tier] ?? 1.0) * 100).round()}%',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 10,
            ),
          ),

          const SizedBox(width: 8),

          // File name or drop hint
          Expanded(
            child: path != null
                ? Text(
                    path.split('/').last,
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
                    'Drop ${tier.name} win audio',
                    style: TextStyle(
                      color: FluxForgeTheme.textMuted,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
          ),

          // Clear button
          if (path != null)
            IconButton(
              icon: Icon(Icons.close, size: 14, color: FluxForgeTheme.textMuted),
              onPressed: () => setState(() => _winTierPaths[tier] = null),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
        ],
      ),
    );
  }

  Color _winTierColor(WinTier tier) {
    switch (tier) {
      case WinTier.small:
        return Colors.grey;
      case WinTier.medium:
        return Colors.green;
      case WinTier.big:
        return Colors.blue;
      case WinTier.mega:
        return Colors.purple;
      case WinTier.epic:
        return Colors.orange;
      case WinTier.ultra:
        return Colors.red;
    }
  }

  void _generateWinTiers() {
    final audioByTier = <WinTier, String>{};
    for (final entry in _winTierPaths.entries) {
      if (entry.value != null) {
        audioByTier[entry.key] = entry.value!;
      }
    }

    if (audioByTier.isEmpty) return;

    final result = _service.generateWinTierSet(audioByTier: audioByTier);

    _showResultDialog(result);
    widget.onEventsGenerated?.call(result.events);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW TEMPLATES TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTemplatesTab() {
    final templates = _service.getFlowTemplates();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.view_list, color: FluxForgeTheme.accentGreen, size: 20),
              const SizedBox(width: 8),
              Text(
                'Flow Templates',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'One-click templates for common slot audio flows',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 11,
            ),
          ),

          const SizedBox(height: 16),

          // Template list
          Expanded(
            child: ListView.builder(
              itemCount: templates.length,
              itemBuilder: (context, index) {
                final template = templates[index];
                return _buildTemplateCard(template);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(FlowTemplate template) {
    final categoryColors = {
      FlowCategory.spin: FluxForgeTheme.accentCyan,
      FlowCategory.win: FluxForgeTheme.accentOrange,
      FlowCategory.feature: FluxForgeTheme.accentPurple,
      FlowCategory.music: FluxForgeTheme.accentGreen,
      FlowCategory.cascade: FluxForgeTheme.accentBlue,
      FlowCategory.jackpot: Colors.amber,
    };

    final color = categoryColors[template.category] ?? FluxForgeTheme.accentBlue;
    final requiredCount = template.stages.where((s) => !s.isOptional).length;
    final optionalCount = template.stages.where((s) => s.isOptional).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            template.category.name.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Text(
          template.name,
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '$requiredCount required, $optionalCount optional stages',
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 10,
          ),
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.description,
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 12),

                // Stages list
                ...template.stages.map((stage) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          stage.isOptional ? Icons.radio_button_unchecked : Icons.radio_button_checked,
                          size: 12,
                          color: stage.isOptional ? FluxForgeTheme.textMuted : color,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          stage.stage,
                          style: TextStyle(
                            color: FluxForgeTheme.textPrimary,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const Spacer(),
                        if (stage.hint.isNotEmpty)
                          Tooltip(
                            message: stage.hint,
                            child: Icon(
                              Icons.info_outline,
                              size: 12,
                              color: FluxForgeTheme.textMuted,
                            ),
                          ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 12),

                // Apply button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showTemplateWizard(template),
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Apply Template'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color.withValues(alpha: 0.2),
                      foregroundColor: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showTemplateWizard(FlowTemplate template) {
    showDialog(
      context: context,
      builder: (context) => _TemplateWizardDialog(
        template: template,
        onComplete: (audioByStage) {
          final result = _service.applyFlowTemplate(
            templateId: template.id,
            audioByStage: audioByStage,
          );
          _showResultDialog(result);
          widget.onEventsGenerated?.call(result.events);
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BATCH IMPORT TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBatchTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.folder_open, color: FluxForgeTheme.accentPurple, size: 20),
              const SizedBox(width: 8),
              Text(
                'Batch Import',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Drop multiple audio files → Auto-analyze → Preview → Commit all',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 11,
            ),
          ),

          const SizedBox(height: 16),

          // Drop zone for multiple files
          _buildBatchDropZone(),

          const SizedBox(height: 16),

          // Analysis results
          if (_batchAnalysis != null) ...[
            Text(
              _batchAnalysis!.summary,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),

            // Warnings
            if (_batchAnalysis!.warnings.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _batchAnalysis!.warnings.map((w) {
                    return Row(
                      children: [
                        Icon(Icons.warning, size: 12, color: FluxForgeTheme.accentOrange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            w,
                            style: TextStyle(
                              color: FluxForgeTheme.accentOrange,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 8),

            // Events list
            Expanded(
              child: ListView.builder(
                itemCount: _batchAnalysis!.events.length,
                itemBuilder: (context, index) {
                  final event = _batchAnalysis!.events[index];
                  return _buildBatchEventRow(event, index);
                },
              ),
            ),

            const SizedBox(height: 12),

            // Commit button
            _buildGenerateButton(
              enabled: _batchAnalysis!.events.isNotEmpty,
              label: 'Commit ${_batchAnalysis!.events.length} Events',
              onPressed: _commitBatch,
            ),
          ] else ...[
            // Empty state
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_upload,
                      size: 48,
                      color: FluxForgeTheme.textMuted.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Drop audio files or folder here',
                      style: TextStyle(
                        color: FluxForgeTheme.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Smart parser will auto-detect stages',
                      style: TextStyle(
                        color: FluxForgeTheme.textMuted.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBatchDropZone() {
    return DragTarget<List<String>>(
      onAcceptWithDetails: (details) {
        setState(() {
          _batchPaths.addAll(details.data);
          _batchAnalysis = _service.analyzeBatch(_batchPaths);
        });
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
          height: 60,
          decoration: BoxDecoration(
            color: isHovering
                ? FluxForgeTheme.accentPurple.withValues(alpha: 0.1)
                : FluxForgeTheme.bgMid.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isHovering
                  ? FluxForgeTheme.accentPurple
                  : FluxForgeTheme.borderSubtle,
              width: isHovering ? 2 : 1,
            ),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  color: isHovering ? FluxForgeTheme.accentPurple : FluxForgeTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  _batchPaths.isEmpty
                      ? 'Drop audio files here'
                      : '${_batchPaths.length} files loaded (drop more to add)',
                  style: TextStyle(
                    color: isHovering ? FluxForgeTheme.accentPurple : FluxForgeTheme.textSecondary,
                  ),
                ),
                if (_batchPaths.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => setState(() {
                      _batchPaths.clear();
                      _batchAnalysis = null;
                    }),
                    child: Text(
                      'Clear',
                      style: TextStyle(color: FluxForgeTheme.accentRed, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBatchEventRow(AutoEventSpec event, int index) {
    final confidence = (event.metadata['confidence'] as double? ?? 0.5) * 100;
    final category = event.metadata['category'] as String? ?? 'unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // Index
          SizedBox(
            width: 24,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ),

          // Stage
          Expanded(
            flex: 2,
            child: Text(
              event.stage,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),

          // Category
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              category,
              style: TextStyle(
                color: FluxForgeTheme.accentBlue,
                fontSize: 9,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Confidence
          Text(
            '${confidence.round()}%',
            style: TextStyle(
              color: confidence > 70 ? FluxForgeTheme.accentGreen : FluxForgeTheme.textMuted,
              fontSize: 10,
            ),
          ),

          const SizedBox(width: 8),

          // Action type badge
          if (event.actionType == ActionType.stop)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentRed.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'STOP',
                style: TextStyle(
                  color: FluxForgeTheme.accentRed,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _commitBatch() {
    if (_batchAnalysis == null) return;
    _showResultDialog(_batchAnalysis!);
    widget.onEventsGenerated?.call(_batchAnalysis!.events);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDropZone({
    required String label,
    required String? currentPath,
    required void Function(String path) onPathSelected,
  }) {
    // Accept BOTH AudioAsset and String for drag-drop compatibility
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        return details.data is AudioAsset ||
            details.data is List<AudioAsset> ||
            details.data is String;
      },
      onAcceptWithDetails: (details) {
        String? path;
        if (details.data is AudioAsset) {
          path = (details.data as AudioAsset).path;
        } else if (details.data is List<AudioAsset>) {
          final list = details.data as List<AudioAsset>;
          if (list.isNotEmpty) path = list.first.path;
        } else if (details.data is String) {
          path = details.data as String;
        }
        if (path != null) onPathSelected(path);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
          height: 80,
          decoration: BoxDecoration(
            color: isHovering
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.1)
                : FluxForgeTheme.bgMid.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isHovering
                  ? FluxForgeTheme.accentBlue
                  : currentPath != null
                      ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
                      : FluxForgeTheme.borderSubtle,
              width: isHovering ? 2 : 1,
            ),
          ),
          child: Center(
            child: currentPath != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.audio_file, color: FluxForgeTheme.accentGreen),
                      const SizedBox(height: 4),
                      Text(
                        currentPath.split('/').last,
                        style: TextStyle(
                          color: FluxForgeTheme.textPrimary,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_upload,
                        color: isHovering ? FluxForgeTheme.accentBlue : FluxForgeTheme.textMuted,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          color: isHovering ? FluxForgeTheme.accentBlue : FluxForgeTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildPreviewCard({
    required String title,
    required List<String> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          ...items.map((item) {
            return Text(
              '  • $item',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildGenerateButton({
    required bool enabled,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled
              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.2)
              : FluxForgeTheme.bgMid,
          foregroundColor: enabled ? FluxForgeTheme.accentGreen : FluxForgeTheme.textMuted,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  void _showResultDialog(AutomationResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.surfaceDark,
        title: Row(
          children: [
            Icon(Icons.check_circle, color: FluxForgeTheme.accentGreen),
            const SizedBox(width: 8),
            Text(
              'Events Generated',
              style: TextStyle(color: FluxForgeTheme.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.summary,
              style: TextStyle(color: FluxForgeTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Text(
              '${result.eventCount} events ready to commit',
              style: TextStyle(
                color: FluxForgeTheme.accentGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...result.warnings.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.warning, size: 14, color: FluxForgeTheme.accentOrange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        w,
                        style: TextStyle(
                          color: FluxForgeTheme.accentOrange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: TextStyle(color: FluxForgeTheme.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _commitEvents(result.events);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentGreen,
            ),
            child: const Text('Commit All'),
          ),
        ],
      ),
    );
  }

  void _commitEvents(List<AutoEventSpec> events) {
    // Get middleware provider and commit events
    final middleware = context.read<MiddlewareProvider>();

    for (final spec in events) {
      // Skip stop-only events without audio
      if (spec.audioPath.isEmpty && spec.actionType == ActionType.stop) continue;

      // Create composite event in middleware
      final event = middleware.createCompositeEvent(
        name: spec.eventId,
        category: spec.bus,
      );

      // Add trigger stage
      if (spec.stage.isNotEmpty) {
        middleware.addTriggerStage(event.id, spec.stage);
      }

      // Add layer if we have audio
      if (spec.audioPath.isNotEmpty) {
        final fileName = spec.audioPath.split('/').last;
        middleware.addLayerToEvent(
          event.id,
          audioPath: spec.audioPath,
          name: fileName,
        );

        // Update layer with volume/pan
        final addedLayer = middleware.compositeEvents
            .where((e) => e.id == event.id)
            .firstOrNull
            ?.layers
            .lastOrNull;
        if (addedLayer != null) {
          middleware.updateEventLayer(
            event.id,
            addedLayer.copyWith(
              volume: spec.volume,
              pan: spec.pan,
            ),
          );
        }
      }
    }

    // Show success snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${events.length} events created successfully'),
        backgroundColor: FluxForgeTheme.accentGreen,
      ),
    );
  }
}

// =============================================================================
// TEMPLATE WIZARD DIALOG
// =============================================================================

class _TemplateWizardDialog extends StatefulWidget {
  final FlowTemplate template;
  final void Function(Map<String, String> audioByStage) onComplete;

  const _TemplateWizardDialog({
    required this.template,
    required this.onComplete,
  });

  @override
  State<_TemplateWizardDialog> createState() => _TemplateWizardDialogState();
}

class _TemplateWizardDialogState extends State<_TemplateWizardDialog> {
  final Map<String, String?> _audioByStage = {};

  @override
  Widget build(BuildContext context) {
    final requiredCount = widget.template.stages.where((s) => !s.isOptional).length;
    final filledCount = _audioByStage.values.where((v) => v != null).length;

    return AlertDialog(
      backgroundColor: FluxForgeTheme.surfaceDark,
      title: Text(
        'Apply: ${widget.template.name}',
        style: TextStyle(color: FluxForgeTheme.textPrimary),
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.template.description,
              style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              '$filledCount / $requiredCount required stages filled',
              style: TextStyle(
                color: filledCount >= requiredCount
                    ? FluxForgeTheme.accentGreen
                    : FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: widget.template.stages.length,
                itemBuilder: (context, index) {
                  final stage = widget.template.stages[index];
                  final path = _audioByStage[stage.stage];
                  return _buildStageRow(stage, path);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textMuted)),
        ),
        ElevatedButton(
          onPressed: filledCount >= requiredCount
              ? () {
                  Navigator.of(context).pop();
                  final result = <String, String>{};
                  for (final entry in _audioByStage.entries) {
                    if (entry.value != null) {
                      result[entry.key] = entry.value!;
                    }
                  }
                  widget.onComplete(result);
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.accentGreen,
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _buildStageRow(FlowTemplateStage stage, String? path) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: path != null
              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
              : stage.isOptional
                  ? FluxForgeTheme.borderSubtle
                  : FluxForgeTheme.accentOrange.withValues(alpha: 0.3),
        ),
      ),
      // Accept BOTH AudioAsset and String for drag-drop compatibility
      child: DragTarget<Object>(
        onWillAcceptWithDetails: (details) {
          return details.data is AudioAsset ||
              details.data is List<AudioAsset> ||
              details.data is String;
        },
        onAcceptWithDetails: (details) {
          String? path;
          if (details.data is AudioAsset) {
            path = (details.data as AudioAsset).path;
          } else if (details.data is List<AudioAsset>) {
            final list = details.data as List<AudioAsset>;
            if (list.isNotEmpty) path = list.first.path;
          } else if (details.data is String) {
            path = details.data as String;
          }
          if (path != null) {
            setState(() => _audioByStage[stage.stage] = path);
          }
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return Row(
            children: [
              // Required indicator
              Icon(
                stage.isOptional ? Icons.radio_button_unchecked : Icons.radio_button_checked,
                size: 14,
                color: stage.isOptional ? FluxForgeTheme.textMuted : FluxForgeTheme.accentOrange,
              ),
              const SizedBox(width: 8),

              // Stage name
              SizedBox(
                width: 150,
                child: Text(
                  stage.stage,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Drop area / file name
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isHovering
                        ? FluxForgeTheme.accentBlue.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isHovering ? FluxForgeTheme.accentBlue : Colors.transparent,
                    ),
                  ),
                  child: path != null
                      ? Row(
                          children: [
                            Icon(Icons.audio_file, size: 14, color: FluxForgeTheme.accentGreen),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                path.split('/').last,
                                style: TextStyle(
                                  color: FluxForgeTheme.textSecondary,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, size: 12, color: FluxForgeTheme.textMuted),
                              onPressed: () => setState(() => _audioByStage[stage.stage] = null),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                            ),
                          ],
                        )
                      : Text(
                          stage.hint.isNotEmpty ? stage.hint : 'Drop audio here',
                          style: TextStyle(
                            color: FluxForgeTheme.textMuted,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
