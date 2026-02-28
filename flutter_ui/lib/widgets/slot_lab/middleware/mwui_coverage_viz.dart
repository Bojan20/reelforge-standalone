import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../models/behavior_tree_models.dart'
    hide BehaviorCoverageStatus;
import '../../../providers/slot_lab/behavior_tree_provider.dart';
import '../../../providers/slot_lab/behavior_coverage_provider.dart';
import '../../../theme/fluxforge_theme.dart';

/// MWUI-7: Coverage Visualization — Per-Node Binding Status
///
/// Grid of all behavior nodes with color-coded coverage status:
/// - Green: Fully tested/verified
/// - Yellow: Partially tested
/// - Red: Untested
/// Filter by category, hover for missing hooks.
class MwuiCoverageViz extends StatefulWidget {
  const MwuiCoverageViz({super.key});

  @override
  State<MwuiCoverageViz> createState() => _MwuiCoverageVizState();
}

class _MwuiCoverageVizState extends State<MwuiCoverageViz> {
  BehaviorTreeProvider? _treeProvider;
  BehaviorCoverageProvider? _coverageProvider;
  BehaviorCategory? _filterCategory;
  String? _hoveredNodeId;

  @override
  void initState() {
    super.initState();
    try {
      _treeProvider = GetIt.instance<BehaviorTreeProvider>();
      _treeProvider?.addListener(_onUpdate);
    } catch (_) {}
    try {
      _coverageProvider = GetIt.instance<BehaviorCoverageProvider>();
      _coverageProvider?.addListener(_onUpdate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _treeProvider?.removeListener(_onUpdate);
    _coverageProvider?.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildCategoryFilter(),
        _buildOverallBar(),
        Expanded(
          child: Row(
            children: [
              // Grid (left)
              Expanded(child: _buildGrid()),
              // Detail panel (right)
              if (_hoveredNodeId != null)
                SizedBox(
                  width: 220,
                  child: _buildDetailPanel(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final cov = _coverageProvider;
    final pct = cov != null ? (cov.overallCoverage * 100) : 0.0;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.grid_on, size: 14, color: Color(0xFF66BB6A)),
          const SizedBox(width: 6),
          Text('Coverage', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${pct.toStringAsFixed(0)}%', style: TextStyle(
            color: pct >= 80 ? const Color(0xFF66BB6A) : pct >= 50 ? const Color(0xFFFFB74D) : const Color(0xFFEF5350),
            fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip('All', null),
          ...BehaviorCategory.values.map((cat) => _filterChip(cat.displayName, cat)),
        ],
      ),
    );
  }

  Widget _filterChip(String label, BehaviorCategory? category) {
    final isSelected = _filterCategory == category;
    return GestureDetector(
      onTap: () => setState(() => _filterCategory = category),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF66BB6A).withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF66BB6A) : Colors.white.withOpacity(0.4),
            fontSize: 9,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildOverallBar() {
    final cov = _coverageProvider;
    if (cov == null) return const SizedBox.shrink();
    final pct = cov.overallCoverage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SizedBox(
        height: 4,
        child: LinearProgressIndicator(
          value: pct.clamp(0.0, 1.0),
          backgroundColor: Colors.white.withOpacity(0.06),
          valueColor: AlwaysStoppedAnimation(
            pct >= 0.8 ? const Color(0xFF66BB6A) :
            pct >= 0.5 ? const Color(0xFFFFB74D) : const Color(0xFFEF5350),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    final tree = _treeProvider;
    if (tree == null) {
      return Center(
        child: Text('Behavior tree not available', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
      );
    }

    final nodes = tree.allNodes.where((n) {
      if (_filterCategory == null) return true;
      return n.category == _filterCategory;
    }).toList();

    if (nodes.isEmpty) {
      return Center(
        child: Text('No nodes in this category', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 2.0,
      ),
      itemCount: nodes.length,
      itemBuilder: (context, index) {
        final node = nodes[index];
        return _buildNodeTile(node);
      },
    );
  }

  Widget _buildNodeTile(BehaviorNode node) {
    final cov = _coverageProvider;
    final stats = cov?.getNodeStats(node.id);
    final total = stats?.totalStages ?? 0;
    final tested = stats?.testedStages ?? 0;
    final verified = stats?.verifiedStages ?? 0;
    final ratio = total > 0 ? (tested + verified) / total : 0.0;
    final isHovered = _hoveredNodeId == node.id;

    final color = ratio >= 0.8 ? const Color(0xFF66BB6A)
        : ratio >= 0.4 ? const Color(0xFFFFB74D)
        : ratio > 0 ? const Color(0xFFFF7043)
        : const Color(0xFFEF5350);

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredNodeId = node.id),
      onExit: (_) => setState(() => _hoveredNodeId = null),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isHovered ? color.withOpacity(0.15) : color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isHovered ? color.withOpacity(0.6) : color.withOpacity(0.2),
            width: isHovered ? 1.0 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    node.nodeType.displayName,
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              total > 0 ? '${tested + verified}/$total stages' : 'no stages',
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPanel() {
    final nodeId = _hoveredNodeId!;
    final node = _treeProvider?.allNodes.cast<BehaviorNode?>().firstWhere((n) => n?.id == nodeId, orElse: () => null);
    final stats = _coverageProvider?.getNodeStats(nodeId);
    final entries = _coverageProvider?.getEntriesForNode(nodeId) ?? [];

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(left: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node?.nodeType.displayName ?? nodeId,
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (node != null)
                  Text(node.category.displayName, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
              ],
            ),
          ),
          if (stats != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('Total Stages', '${stats.totalStages}'),
                  _detailRow('Tested', '${stats.testedStages}'),
                  _detailRow('Verified', '${stats.verifiedStages}'),
                  _detailRow('Untested', '${stats.totalStages - stats.testedStages - stats.verifiedStages}'),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                Text('STAGE ENTRIES', style: TextStyle(
                  color: const Color(0xFF66BB6A).withOpacity(0.6),
                  fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1)),
                const SizedBox(height: 4),
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        Icon(
                          entry.status == BehaviorCoverageStatus.verified
                              ? Icons.verified
                              : entry.status == BehaviorCoverageStatus.tested
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                          size: 10,
                          color: entry.status == BehaviorCoverageStatus.verified
                              ? const Color(0xFF66BB6A)
                              : entry.status == BehaviorCoverageStatus.tested
                                  ? const Color(0xFFFFB74D)
                                  : const Color(0xFFEF5350),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            entry.stageName,
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9))),
          Text(value, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
