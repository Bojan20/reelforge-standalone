/// AI Mixing Panel — P3-03
///
/// UI widgets for AI-assisted mixing:
/// - AiMixingStatusBadge: Compact status indicator
/// - AiMixingPanel: Full suggestions panel
/// - SuggestionCard: Individual suggestion display
/// - MixScoreIndicator: Overall mix quality score
///
/// Created: 2026-01-31 (P3-03)
library;

import 'package:flutter/material.dart';

import '../../services/ai_mixing_service.dart';
import '../../theme/flux_forge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AI MIXING STATUS BADGE
// ═══════════════════════════════════════════════════════════════════════════

/// Compact AI mixing status badge
class AiMixingStatusBadge extends StatelessWidget {
  final VoidCallback? onTap;

  const AiMixingStatusBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AiMixingService.instance,
      builder: (context, _) {
        final service = AiMixingService.instance;
        final analysis = service.lastAnalysis;

        return Tooltip(
          message: _getTooltip(service, analysis),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getColor(service, analysis).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _getColor(service, analysis).withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (service.isAnalyzing)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.auto_fix_high,
                      size: 14,
                      color: _getColor(service, analysis),
                    ),
                  const SizedBox(width: 4),
                  if (analysis != null)
                    Text(
                      analysis.scoreGrade,
                      style: FluxForgeTheme.dockMono(
                        size: 11,
                        weight: FontWeight.bold,
                        color: _getColor(service, analysis),
                      ),
                    )
                  else
                    Text(
                      'AI',
                      style: FluxForgeTheme.dockSans(
                        size: 11,
                        weight: FontWeight.w500,
                        color: _getColor(service, analysis),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getColor(AiMixingService service, MixAnalysisResult? analysis) {
    if (!service.enabled) return Colors.grey;
    if (service.isAnalyzing) return const Color(0xFF4A9EFF);
    if (analysis == null) return Colors.grey;

    if (analysis.overallScore >= 80) return const Color(0xFF40FF90);
    if (analysis.overallScore >= 60) return const Color(0xFFFFFF40);
    return const Color(0xFFFF4060);
  }

  String _getTooltip(AiMixingService service, MixAnalysisResult? analysis) {
    if (!service.enabled) return 'AI Mixing disabled';
    if (service.isAnalyzing) return 'Analyzing mix...';
    if (analysis == null) return 'Click to analyze mix';

    final critical = analysis.criticalCount;
    final high = analysis.highCount;

    if (critical > 0) {
      return '$critical critical issue(s) found';
    }
    if (high > 0) {
      return '$high high priority suggestion(s)';
    }

    return 'Mix score: ${analysis.overallScore.toStringAsFixed(0)}%';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AI MIXING PANEL
// ═══════════════════════════════════════════════════════════════════════════

/// Full AI mixing suggestions panel
class AiMixingPanel extends StatefulWidget {
  final VoidCallback? onAnalyze;

  const AiMixingPanel({super.key, this.onAnalyze});

  @override
  State<AiMixingPanel> createState() => _AiMixingPanelState();
}

class _AiMixingPanelState extends State<AiMixingPanel> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AiMixingService.instance,
      builder: (context, _) {
        final service = AiMixingService.instance;
        final analysis = service.lastAnalysis;

        return Container(
          color: const Color(0xFF1A1A20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(service),
              const Divider(height: 1, color: Color(0xFF2A2A30)),

              // Score
              if (analysis != null) ...[
                _buildScoreSection(analysis),
                const Divider(height: 1, color: Color(0xFF2A2A30)),
              ],

              // Suggestions
              Expanded(
                child: analysis != null
                    ? _buildSuggestionList(analysis)
                    : _buildEmptyState(service),
              ),

              // Footer
              _buildFooter(service),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(AiMixingService service) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            Icons.auto_fix_high,
            color: service.enabled ? const Color(0xFF4A9EFF) : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'AI Mixing Assistant',
              style: FluxForgeTheme.dockSans(
                color: Colors.white,
                size: 14,
                weight: FontWeight.bold,
              ),
            ),
          ),
          // Genre selector
          PopupMenuButton<GenreProfile>(
            tooltip: 'Select genre profile',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A30),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    service.selectedGenre.displayName,
                    style: FluxForgeTheme.dockSans(
                      color: Colors.white70,
                      size: 11,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 16),
                ],
              ),
            ),
            itemBuilder: (context) => GenreProfile.values.map((genre) {
              return PopupMenuItem(
                value: genre,
                child: Row(
                  children: [
                    if (genre == service.selectedGenre)
                      const Icon(Icons.check, size: 16, color: Color(0xFF4A9EFF))
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(genre.displayName),
                  ],
                ),
              );
            }).toList(),
            onSelected: (genre) => service.setGenre(genre),
          ),
          const SizedBox(width: 8),
          // Enable toggle
          Switch(
            value: service.enabled,
            onChanged: (v) => service.setEnabled(v),
            activeColor: const Color(0xFF4A9EFF),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreSection(MixAnalysisResult analysis) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Score circle
          MixScoreIndicator(score: analysis.overallScore, size: 60),
          const SizedBox(width: 16),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall Mix Score',
                  style: FluxForgeTheme.dockSans(
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${analysis.suggestions.length} suggestions',
                  style: FluxForgeTheme.dockSans(
                    color: Colors.white,
                    size: 13,
                  ),
                ),
                if (analysis.criticalCount > 0)
                  Text(
                    '${analysis.criticalCount} critical',
                    style: FluxForgeTheme.dockSans(
                      color: const Color(0xFFFF4060),
                      size: 11,
                      weight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          // LUFS / DR
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildMetricChip(
                'LUFS',
                analysis.overallLufs.toStringAsFixed(1),
                Colors.cyan,
              ),
              const SizedBox(height: 4),
              _buildMetricChip(
                'DR',
                analysis.overallDynamicRange.toStringAsFixed(1),
                Colors.amber,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: FluxForgeTheme.dockSans(
              color: color.withValues(alpha: 0.8),
              size: 9,
              weight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: FluxForgeTheme.dockMono(
              color: color,
              size: 11,
              weight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionList(MixAnalysisResult analysis) {
    if (analysis.suggestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: const Color(0xFF40FF90).withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No issues found!',
              style: FluxForgeTheme.dockSans(
                color: Colors.white70,
                size: 14,
              ),
            ),
            Text(
              'Your mix is looking great',
              style: FluxForgeTheme.dockSans(
                color: Colors.white.withValues(alpha: 0.5),
                size: 12,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: analysis.suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = analysis.suggestions[index];
        return SuggestionCard(
          suggestion: suggestion,
          onApply: () => _applySuggestion(suggestion),
          onDismiss: () => _dismissSuggestion(suggestion),
        );
      },
    );
  }

  Widget _buildEmptyState(AiMixingService service) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 64,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              service.isAnalyzing ? 'Analyzing your mix...' : 'Ready to analyze',
              style: FluxForgeTheme.dockSans(
                color: Colors.white.withValues(alpha: 0.7),
                size: 14,
              ),
            ),
            const SizedBox(height: 8),
            if (!service.isAnalyzing)
              Text(
                'Click Analyze to get AI mixing suggestions',
                style: FluxForgeTheme.dockSans(
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 12,
                ),
              ),
            if (service.isAnalyzing)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(AiMixingService service) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2A2A30))),
      ),
      child: Row(
        children: [
          // Sensitivity slider
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: service.sensitivity,
                      onChanged: (v) => service.setSensitivity(v),
                      activeColor: const Color(0xFF4A9EFF),
                      inactiveColor: const Color(0xFF2A2A30),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Analyze button
          ElevatedButton.icon(
            onPressed: service.isAnalyzing ? null : widget.onAnalyze,
            icon: service.isAnalyzing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.analytics, size: 16),
            label: const Text('Analyze'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A9EFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applySuggestion(MixingSuggestion suggestion) async {
    final success = await AiMixingService.instance.applySuggestion(suggestion);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Applied: ${suggestion.title}' : 'Failed to apply'),
          backgroundColor: success ? const Color(0xFF40FF90) : const Color(0xFFFF4060),
        ),
      );
    }
  }

  void _dismissSuggestion(MixingSuggestion suggestion) {
    AiMixingService.instance.dismissSuggestion(suggestion.id);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUGGESTION CARD
// ═══════════════════════════════════════════════════════════════════════════

/// Card for displaying a single suggestion
class SuggestionCard extends StatelessWidget {
  final MixingSuggestion suggestion;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.onApply,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF242430),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                // Type icon
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _getPriorityColor().withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      suggestion.type.icon,
                      style: FluxForgeTheme.dockSans(size: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.title,
                        style: FluxForgeTheme.dockSans(
                          color: Colors.white,
                          size: 13,
                          weight: FontWeight.w500,
                        ),
                      ),
                      if (suggestion.trackName != null)
                        Text(
                          suggestion.trackName!,
                          style: FluxForgeTheme.dockSans(
                            color: Colors.white.withValues(alpha: 0.5),
                            size: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                // Priority badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getPriorityColor().withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    suggestion.priority.displayName,
                    style: FluxForgeTheme.dockSans(
                      color: _getPriorityColor(),
                      size: 9,
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Description
            Text(
              suggestion.description,
              style: FluxForgeTheme.dockSans(
                color: Colors.white.withValues(alpha: 0.7),
                size: 12,
              ),
            ),
            // Parameters
            if (suggestion.parameters.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: suggestion.parameters.entries.map((e) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${e.key}: ${e.value.toStringAsFixed(1)}',
                      style: FluxForgeTheme.dockMono(
                        color: Colors.white.withValues(alpha: 0.6),
                        size: 10,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 8),
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Confidence
                Text(
                  '${(suggestion.confidence * 100).toInt()}% confidence',
                  style: FluxForgeTheme.dockSans(
                    color: Colors.white.withValues(alpha: 0.4),
                    size: 10,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onDismiss,
                  child: Text(
                    'Dismiss',
                    style: FluxForgeTheme.dockSans(size: 12),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onApply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getPriorityColor(),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Apply', style: FluxForgeTheme.dockSans(size: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor() {
    switch (suggestion.priority) {
      case SuggestionPriority.critical:
        return const Color(0xFFFF4060);
      case SuggestionPriority.high:
        return const Color(0xFFFF9040);
      case SuggestionPriority.medium:
        return const Color(0xFFFFFF40);
      case SuggestionPriority.low:
        return const Color(0xFF40FF90);
      case SuggestionPriority.info:
        return const Color(0xFF4A9EFF);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MIX SCORE INDICATOR
// ═══════════════════════════════════════════════════════════════════════════

/// Circular score indicator
class MixScoreIndicator extends StatelessWidget {
  final double score;
  final double size;

  const MixScoreIndicator({
    super.key,
    required this.score,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) {
    final grade = _getGrade();
    final color = _getColor();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Background circle
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation(color.withValues(alpha: 0.2)),
            ),
          ),
          // Progress circle
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          // Grade text
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  grade,
                  style: FluxForgeTheme.dockMono(
                    color: color,
                    size: size * 0.35,
                    weight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${score.toInt()}%',
                  style: FluxForgeTheme.dockSans(
                    color: Colors.white.withValues(alpha: 0.7),
                    size: size * 0.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getGrade() {
    if (score >= 90) return 'A';
    if (score >= 80) return 'B';
    if (score >= 70) return 'C';
    if (score >= 60) return 'D';
    return 'F';
  }

  Color _getColor() {
    if (score >= 80) return const Color(0xFF40FF90);
    if (score >= 60) return const Color(0xFFFFFF40);
    return const Color(0xFFFF4060);
  }
}
