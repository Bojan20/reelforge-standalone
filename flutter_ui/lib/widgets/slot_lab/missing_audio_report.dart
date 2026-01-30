/// Missing Audio Report Dialog
///
/// Shows which stages don't have audio assigned.
/// Helps audio designers track completion progress.
///
/// Features:
/// - Section breakdown (which sections incomplete)
/// - Stage list (unassigned stages)
/// - Priority sorting (Primary > Secondary > Feature)
/// - Quick assign button per stage
///
/// Task: SL-LP-P1.5
library;

import 'package:flutter/material.dart';
import '../../services/stage_configuration_service.dart';
import '../../theme/fluxforge_theme.dart';

class MissingAudioReport extends StatelessWidget {
  final Map<String, String> audioAssignments;
  final Function(String stage)? onQuickAssign;

  const MissingAudioReport({
    super.key,
    required this.audioAssignments,
    this.onQuickAssign,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, String> audioAssignments,
    Function(String stage)? onQuickAssign,
  }) {
    return showDialog(
      context: context,
      builder: (_) => MissingAudioReport(
        audioAssignments: audioAssignments,
        onQuickAssign: onQuickAssign,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allStages = StageConfigurationService.instance.allStageNames;
    final assignedStages = audioAssignments.keys.toSet();
    final missingStages = allStages.where((s) => !assignedStages.contains(s)).toList();

    // Sort by priority
    missingStages.sort((a, b) {
      final priorityA = StageConfigurationService.instance.getPriority(a);
      final priorityB = StageConfigurationService.instance.getPriority(b);
      return priorityB.compareTo(priorityA); // Descending (high priority first)
    });

    final totalStages = allStages.length;
    final assignedCount = assignedStages.length;
    final completionPercent = (assignedCount / totalStages * 100).toInt();

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A22),
      title: Row(
        children: [
          Icon(Icons.assignment, color: FluxForgeTheme.accentOrange, size: 20),
          const SizedBox(width: 8),
          const Text('Missing Audio Report', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: completionPercent == 100
                    ? FluxForgeTheme.accentGreen.withOpacity(0.1)
                    : FluxForgeTheme.accentOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Total', totalStages.toString(), Colors.white),
                  _buildStat('Assigned', assignedCount.toString(), FluxForgeTheme.accentGreen),
                  _buildStat('Missing', missingStages.length.toString(), FluxForgeTheme.accentOrange),
                  _buildStat('Complete', '$completionPercent%',
                      completionPercent == 100 ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Missing stages list
            Text(
              'UNASSIGNED STAGES (${missingStages.length})',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white54,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: missingStages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.celebration, size: 64, color: FluxForgeTheme.accentGreen.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          Text(
                            'All stages have audio!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: FluxForgeTheme.accentGreen,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '100% completion',
                            style: TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: missingStages.length,
                      itemBuilder: (context, index) {
                        final stage = missingStages[index];
                        final priority = StageConfigurationService.instance.getPriority(stage);
                        final stageDef = StageConfigurationService.instance.getStage(stage);
                        final category = stageDef?.category ?? StageCategory.custom;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF16161C),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _getPriorityColor(priority).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Priority indicator
                              Container(
                                width: 32,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: _getPriorityColor(priority).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '$priority',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: _getPriorityColor(priority),
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Stage name
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      stage,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    Text(
                                      category.name.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 8,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Quick assign button
                              if (onQuickAssign != null)
                                TextButton.icon(
                                  icon: Icon(Icons.add, size: 14, color: FluxForgeTheme.accentBlue),
                                  label: const Text('Assign', style: TextStyle(fontSize: 10)),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    onQuickAssign!(stage);
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: FluxForgeTheme.accentBlue,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
      ),
      actions: [
        TextButton(
          child: const Text('Close'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: Colors.white54),
        ),
      ],
    );
  }

  Color _getPriorityColor(int priority) {
    if (priority >= 80) return FluxForgeTheme.accentRed; // Highest
    if (priority >= 60) return FluxForgeTheme.accentOrange; // High
    if (priority >= 40) return FluxForgeTheme.accentBlue; // Medium
    return Colors.white38; // Low
  }
}
