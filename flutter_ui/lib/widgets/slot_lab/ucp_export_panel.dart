import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../providers/slot_lab/feature_composer_provider.dart';

/// UCP Export™ Panel — Universal Compliance Package Overview.
///
/// Reads REAL project data:
/// - Audio assignments per stage from SlotLabProjectProvider
/// - Composed stages + enabled mechanics from FeatureComposerProvider
/// - Win tier configuration and coverage
/// - Export readiness assessment
class UcpExportPanel extends StatefulWidget {
  const UcpExportPanel({super.key});

  @override
  State<UcpExportPanel> createState() => _UcpExportPanelState();
}

class _UcpExportPanelState extends State<UcpExportPanel> {
  late final SlotLabProjectProvider _project;
  late final FeatureComposerProvider _composer;

  @override
  void initState() {
    super.initState();
    _project = GetIt.instance<SlotLabProjectProvider>();
    _composer = GetIt.instance<FeatureComposerProvider>();
    _project.addListener(_onUpdate);
    _composer.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _project.removeListener(_onUpdate);
    _composer.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          _buildCoverageBar(),
          const SizedBox(height: 8),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final assignments = _project.audioAssignments;
    final stages = _composer.composedStages;
    final coverage = stages.isEmpty ? 0.0 : assignments.length / stages.length;
    final readyColor = coverage >= 1.0
        ? const Color(0xFF4CAF50)
        : coverage >= 0.5
            ? const Color(0xFFFFBB33)
            : const Color(0xFFFF5252);

    return Row(
      children: [
        const Icon(Icons.file_download, size: 14, color: Color(0xFF40C8FF)),
        const SizedBox(width: 4),
        Text(
          'UCP Export',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: readyColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: readyColor.withValues(alpha: 0.4)),
          ),
          child: Text(
            coverage >= 1.0 ? 'READY' : '${(coverage * 100).toStringAsFixed(0)}% COVERAGE',
            style: TextStyle(
              color: readyColor,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Spacer(),
        Text(
          '${assignments.length}/${stages.length} stages',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 9),
        ),
      ],
    );
  }

  Widget _buildCoverageBar() {
    final assignments = _project.audioAssignments;
    final stages = _composer.composedStages;
    final coverage = stages.isEmpty ? 0.0 : assignments.length / stages.length;
    final covColor = coverage >= 1.0
        ? const Color(0xFF4CAF50)
        : coverage >= 0.5
            ? const Color(0xFFFFBB33)
            : const Color(0xFFFF5252);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Audio Coverage', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9)),
            const Spacer(),
            Text('${(coverage * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 9, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: coverage.clamp(0.0, 1.0),
          backgroundColor: const Color(0xFF2A2A4A),
          valueColor: AlwaysStoppedAnimation<Color>(covColor),
          minHeight: 5,
          borderRadius: BorderRadius.circular(2.5),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final assignments = _project.audioAssignments;
    final stages = _composer.composedStages;
    final mechanics = _composer.enabledMechanics;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Enabled mechanics
          _buildSectionTitle('Active Mechanics (${mechanics.length})'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: mechanics.map((m) => _buildMechanicChip(m)).toList(),
          ),

          const SizedBox(height: 10),

          // Stage coverage list
          _buildSectionTitle('Stage Coverage (${stages.length} stages)'),
          const SizedBox(height: 4),
          ...stages.map((stage) {
            final hasAudio = assignments.containsKey(stage.id);
            return _buildStageRow(stage.id, stage.layer.name, hasAudio);
          }),

          const SizedBox(height: 10),

          // Win tier stages
          _buildSectionTitle('Win Tier Stages'),
          const SizedBox(height: 4),
          ..._project.allWinTierStages.map((stage) {
            final hasAudio = assignments.containsKey(stage);
            return _buildStageRow(stage, 'win-tier', hasAudio);
          }),

          const SizedBox(height: 10),

          // Export package summary
          _buildSectionTitle('Package Summary'),
          const SizedBox(height: 4),
          _buildKeyValue('Total Stages', '${stages.length}'),
          _buildKeyValue('Assigned Audio', '${assignments.length}'),
          _buildKeyValue('Missing Audio', '${stages.length - assignments.length}'),
          _buildKeyValue('Unique Assets', '${assignments.values.toSet().length}'),
          _buildKeyValue('Win Tier Stages', '${_project.allWinTierStages.length}'),
          _buildKeyValue('Active Mechanics', '${mechanics.length}'),
        ],
      ),
    );
  }

  Widget _buildMechanicChip(SlotMechanic mechanic) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF40C8FF).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF40C8FF).withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        mechanic.displayName,
        style: const TextStyle(
          color: Color(0xFF40C8FF),
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildStageRow(String stageName, String source, bool hasAudio) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E36),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Icon(
            hasAudio ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 10,
            color: hasAudio ? const Color(0xFF4CAF50) : const Color(0xFF3A3A5C),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              stageName,
              style: TextStyle(
                color: Colors.white.withValues(alpha: hasAudio ? 0.8 : 0.4),
                fontSize: 9,
                fontWeight: hasAudio ? FontWeight.w500 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A4A),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              source,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.8),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildKeyValue(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(key,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 9)),
          ),
        ],
      ),
    );
  }
}
