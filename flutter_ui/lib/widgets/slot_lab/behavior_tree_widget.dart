/// Behavior Tree Widget — SlotLab Middleware §5 UI
///
/// Visual tree display of all behavior nodes organized by category.
/// Supports selection, coverage indicators, runtime state visualization,
/// and drag-drop sound assignment.
///
/// Used in Build Mode (§16) as the primary authoring view.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../models/behavior_tree_models.dart';
import '../../providers/slot_lab/behavior_tree_provider.dart';

class BehaviorTreeWidget extends StatefulWidget {
  /// Optional callback when a node is selected
  final ValueChanged<String?>? onNodeSelected;

  /// Whether to show coverage indicators
  final bool showCoverage;

  /// Whether to show runtime state (active/idle indicators)
  final bool showRuntimeState;

  /// Current parameter tier for display filtering
  final ParameterTier parameterTier;

  const BehaviorTreeWidget({
    super.key,
    this.onNodeSelected,
    this.showCoverage = true,
    this.showRuntimeState = true,
    this.parameterTier = ParameterTier.basic,
  });

  @override
  State<BehaviorTreeWidget> createState() => _BehaviorTreeWidgetState();
}

/// Parameter tier for progressive disclosure
enum ParameterTier {
  basic,
  advanced,
  expert,
}

class _BehaviorTreeWidgetState extends State<BehaviorTreeWidget> {
  final _provider = GetIt.instance<BehaviorTreeProvider>();
  final _scrollController = ScrollController();

  /// Collapsed categories
  final Set<BehaviorCategory> _collapsedCategories = {};

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final nodesByCategory = _provider.nodesByCategory;

    return Column(
      children: [
        // Coverage summary bar
        if (widget.showCoverage) _buildCoverageSummary(),

        // Tree content
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: BehaviorCategory.values.length,
            itemBuilder: (context, index) {
              final category = BehaviorCategory.values[index];
              final nodes = nodesByCategory[category] ?? [];
              if (nodes.isEmpty) return const SizedBox.shrink();
              return _buildCategorySection(category, nodes);
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COVERAGE SUMMARY BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCoverageSummary() {
    final total = _provider.totalNodeCount;
    final bound = _provider.boundNodeCount;
    final percent = _provider.coveragePercent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          // Coverage bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Coverage: $bound/$total',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(percent * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: _getCoverageColor(percent),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(_getCoverageColor(percent)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getCoverageColor(double percent) {
    if (percent >= 0.9) return const Color(0xFF44BB44);
    if (percent >= 0.7) return const Color(0xFFFFAA22);
    if (percent >= 0.5) return const Color(0xFFFF8844);
    return const Color(0xFFFF4444);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CATEGORY SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCategorySection(BehaviorCategory category, List<BehaviorNode> nodes) {
    final isCollapsed = _collapsedCategories.contains(category);
    final coverageStats = _provider.coverageByCategory[category];
    final boundCount = coverageStats?.bound ?? 0;
    final totalCount = coverageStats?.total ?? nodes.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header
        InkWell(
          onTap: () {
            setState(() {
              if (isCollapsed) {
                _collapsedCategories.remove(category);
              } else {
                _collapsedCategories.add(category);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF252535),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isCollapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 16,
                  color: Colors.white54,
                ),
                const SizedBox(width: 4),
                Text(
                  category.icon,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(width: 6),
                Text(
                  category.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                if (widget.showCoverage)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: boundCount == totalCount
                          ? const Color(0xFF44BB44).withValues(alpha: 0.2)
                          : const Color(0xFFFF4444).withValues(alpha: 0.2),
                    ),
                    child: Text(
                      '$boundCount/$totalCount',
                      style: TextStyle(
                        color: boundCount == totalCount
                            ? const Color(0xFF44BB44)
                            : const Color(0xFFFF8844),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Nodes (if not collapsed)
        if (!isCollapsed)
          ...nodes.map((node) => _buildNodeRow(node)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NODE ROW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNodeRow(BehaviorNode node) {
    final isSelected = _provider.selectedNodeId == node.id;
    final isActive = node.runtimeState == BehaviorNodeState.active;
    final hasError = node.runtimeState == BehaviorNodeState.error;

    return InkWell(
      onTap: () {
        _provider.selectNode(node.id);
        widget.onNodeSelected?.call(node.id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        margin: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2A4A6A)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isActive
                  ? const Color(0xFF44BB44)
                  : hasError
                      ? const Color(0xFFFF4444)
                      : Colors.white.withValues(alpha: 0.1),
              width: isActive || hasError ? 2 : 1,
            ),
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.03)),
          ),
        ),
        child: Row(
          children: [
            // Runtime state indicator
            if (widget.showRuntimeState)
              _buildStateIndicator(node.runtimeState),

            const SizedBox(width: 6),

            // Node name
            Expanded(
              child: Text(
                node.nodeType.displayName,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),

            // Variant count badge
            if (node.variantCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                child: Text(
                  '${node.variantCount}v',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            // Playback mode badge
            Text(
              _getPlaybackModeShort(node.playbackMode),
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 9,
              ),
            ),

            const SizedBox(width: 6),

            // Coverage status dot
            if (widget.showCoverage)
              _buildCoverageDot(node.coverageStatus),
          ],
        ),
      ),
    );
  }

  Widget _buildStateIndicator(BehaviorNodeState state) {
    Color color;
    IconData icon;
    switch (state) {
      case BehaviorNodeState.idle:
        color = Colors.white24;
        icon = Icons.circle;
      case BehaviorNodeState.active:
        color = const Color(0xFF44BB44);
        icon = Icons.play_circle_filled;
      case BehaviorNodeState.cooldown:
        color = const Color(0xFF4488FF);
        icon = Icons.timer;
      case BehaviorNodeState.disabled:
        color = Colors.white12;
        icon = Icons.block;
      case BehaviorNodeState.error:
        color = const Color(0xFFFF4444);
        icon = Icons.error;
    }
    return Icon(icon, size: 10, color: color);
  }

  Widget _buildCoverageDot(BehaviorCoverageStatus status) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color(status.colorValue),
      ),
    );
  }

  String _getPlaybackModeShort(PlaybackMode mode) {
    switch (mode) {
      case PlaybackMode.oneShot: return '1S';
      case PlaybackMode.loop: return 'LP';
      case PlaybackMode.loopUntilStop: return 'LS';
      case PlaybackMode.retrigger: return 'RT';
      case PlaybackMode.sequence: return 'SQ';
      case PlaybackMode.sustain: return 'SU';
    }
  }
}
