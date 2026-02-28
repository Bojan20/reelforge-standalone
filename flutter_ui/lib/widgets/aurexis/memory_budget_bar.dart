import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/aurexis_provider.dart';
import '../../models/aurexis_models.dart';
import 'aurexis_theme.dart';

/// Always-visible memory budget indicator for the AUREXIS panel.
///
/// Shows current audio memory usage as a segmented bar with
/// per-category breakdowns and platform target indicator.
class MemoryBudgetBar extends StatelessWidget {
  /// Current memory usage in MB.
  final double usedMb;

  /// Total budget in MB.
  final double budgetMb;

  /// Per-category breakdown.
  final Map<String, double> categories;

  const MemoryBudgetBar({
    super.key,
    this.usedMb = 0.0,
    this.budgetMb = 6.0,
    this.categories = const {},
  });

  @override
  Widget build(BuildContext context) {
    final percent = budgetMb > 0 ? (usedMb / budgetMb).clamp(0.0, 1.5) : 0.0;
    final isOverBudget = usedMb > budgetMb;
    final barColor = isOverBudget
        ? AurexisColors.fatigueCritical
        : percent > 0.8
            ? AurexisColors.fatigueHigh
            : percent > 0.6
                ? AurexisColors.fatigueModerate
                : AurexisColors.accent;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AurexisColors.bgSection,
        border: const Border(
          top: BorderSide(color: AurexisColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                'MEMORY BUDGET',
                style: AurexisTextStyles.sectionTitle.copyWith(fontSize: 8),
              ),
              const Spacer(),
              Text(
                '${usedMb.toStringAsFixed(1)} / ${budgetMb.toStringAsFixed(1)} MB',
                style: AurexisTextStyles.paramValue.copyWith(
                  fontSize: 9,
                  color: barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  // Background
                  Container(color: AurexisColors.bgSlider),
                  // Fill
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: percent.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [barColor, barColor.withValues(alpha: 0.7)],
                        ),
                      ),
                    ),
                  ),
                  // Budget limit marker
                  if (isOverBudget)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Align(
                        alignment: Alignment(
                          (1.0 / percent.clamp(1.0, 1.5)) * 2.0 - 1.0,
                          0,
                        ),
                        child: Container(
                          width: 1,
                          color: AurexisColors.fatigueCritical,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Category breakdown (if provided)
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 2,
              children: categories.entries.map((entry) {
                return _CategoryChip(
                  label: entry.key,
                  sizeMb: entry.value,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final double sizeMb;

  const _CategoryChip({required this.label, required this.sizeMb});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: _colorForCategory(label),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          '$label: ${sizeMb.toStringAsFixed(1)}',
          style: AurexisTextStyles.badge.copyWith(
            color: AurexisColors.textLabel,
            fontSize: 7,
          ),
        ),
      ],
    );
  }

  Color _colorForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'sfx':
        return AurexisColors.dynamics;
      case 'music':
        return AurexisColors.music;
      case 'ambience':
        return AurexisColors.spatial;
      case 'voice':
        return AurexisColors.variation;
      default:
        return AurexisColors.textSecondary;
    }
  }
}

/// Standalone memory budget widget that reads from providers.
class AurexisMemoryBudgetWidget extends StatelessWidget {
  const AurexisMemoryBudgetWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // In a real implementation, this would read from audio asset manager
    // For now, show a placeholder budget based on platform
    final engine = GetIt.instance<AurexisProvider>();
    final budget = switch (engine.platform) {
      AurexisPlatform.mobile => 4.0,
      AurexisPlatform.cabinet => 3.0,
      _ => 6.0,
    };

    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        return MemoryBudgetBar(
          usedMb: 0.0, // Will be populated when audio asset manager provides data
          budgetMb: budget,
          categories: const {
            'SFX': 0.0,
            'Music': 0.0,
            'Ambience': 0.0,
          },
        );
      },
    );
  }
}
