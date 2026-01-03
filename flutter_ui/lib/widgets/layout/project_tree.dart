/// Project Tree Widget
///
/// Wwise-style project hierarchy browser with:
/// - Expandable/collapsible tree nodes
/// - Type-based icons
/// - Search filtering
/// - Selection highlighting

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

// ════════════════════════════════════════════════════════════════════════════
// TYPES
// ════════════════════════════════════════════════════════════════════════════

/// Tree item types
enum TreeItemType {
  folder,
  event,
  sound,
  bus,
  state,
  switch_,
  rtpc,
  music,
}

/// Icon map for tree item types
const Map<TreeItemType, String> treeItemIcons = {
  TreeItemType.folder: '📁',
  TreeItemType.event: '🎯',
  TreeItemType.sound: '🔊',
  TreeItemType.bus: '🔈',
  TreeItemType.state: '🏷️',
  TreeItemType.switch_: '🔀',
  TreeItemType.rtpc: '📊',
  TreeItemType.music: '🎵',
};

/// Tree node for project explorer
class ProjectTreeNode {
  final String id;
  final TreeItemType type;
  final String label;
  final List<ProjectTreeNode> children;
  final int? count;
  final dynamic data;

  const ProjectTreeNode({
    required this.id,
    required this.type,
    required this.label,
    this.children = const [],
    this.count,
    this.data,
  });
}

// ════════════════════════════════════════════════════════════════════════════
// WIDGET
// ════════════════════════════════════════════════════════════════════════════

/// Project tree view widget
class ProjectTree extends StatefulWidget {
  final List<ProjectTreeNode> nodes;
  final String? selectedId;
  final String searchQuery;
  final void Function(String id, TreeItemType type, dynamic data)? onSelect;
  final void Function(String id, TreeItemType type, dynamic data)? onDoubleClick;
  final void Function(TreeItemType type)? onAdd;

  const ProjectTree({
    super.key,
    required this.nodes,
    this.selectedId,
    this.searchQuery = '',
    this.onSelect,
    this.onDoubleClick,
    this.onAdd,
  });

  @override
  State<ProjectTree> createState() => _ProjectTreeState();
}

class _ProjectTreeState extends State<ProjectTree> {
  final Set<String> _expandedIds = {};

  void _toggleExpanded(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tree view
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: widget.nodes.length,
            itemBuilder: (context, index) {
              return _TreeItem(
                node: widget.nodes[index],
                level: 0,
                selectedId: widget.selectedId,
                expandedIds: _expandedIds,
                onToggle: _toggleExpanded,
                onSelect: widget.onSelect,
                onDoubleClick: widget.onDoubleClick,
                searchQuery: widget.searchQuery,
              );
            },
          ),
        ),

        // Add button
        if (widget.onAdd != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: ElevatedButton.icon(
              onPressed: () => widget.onAdd?.call(TreeItemType.event),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Event', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: ReelForgeTheme.bgElevated,
                foregroundColor: ReelForgeTheme.textPrimary,
                minimumSize: const Size(double.infinity, 28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TREE ITEM
// ════════════════════════════════════════════════════════════════════════════

class _TreeItem extends StatelessWidget {
  final ProjectTreeNode node;
  final int level;
  final String? selectedId;
  final Set<String> expandedIds;
  final void Function(String id) onToggle;
  final void Function(String id, TreeItemType type, dynamic data)? onSelect;
  final void Function(String id, TreeItemType type, dynamic data)? onDoubleClick;
  final String searchQuery;

  const _TreeItem({
    required this.node,
    required this.level,
    this.selectedId,
    required this.expandedIds,
    required this.onToggle,
    this.onSelect,
    this.onDoubleClick,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    final hasChildren = node.children.isNotEmpty;
    final isExpanded = expandedIds.contains(node.id);
    final isSelected = selectedId == node.id;
    final matchesSearch = searchQuery.isNotEmpty &&
        node.label.toLowerCase().contains(searchQuery.toLowerCase());

    // Filter children if searching
    final visibleChildren = searchQuery.isEmpty
        ? node.children
        : node.children.where((child) =>
            child.label.toLowerCase().contains(searchQuery.toLowerCase()) ||
            child.children.any((c) =>
                c.label.toLowerCase().contains(searchQuery.toLowerCase()))).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () {
            if (hasChildren) onToggle(node.id);
            onSelect?.call(node.id, node.type, node.data);
          },
          onDoubleTap: () => onDoubleClick?.call(node.id, node.type, node.data),
          child: Container(
            height: 26,
            padding: EdgeInsets.only(left: 12.0 + level * 16),
            decoration: BoxDecoration(
              color: isSelected
                  ? ReelForgeTheme.accentBlue.withValues(alpha: 0.15)
                  : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: isSelected ? ReelForgeTheme.accentBlue : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                // Expand arrow
                SizedBox(
                  width: 16,
                  child: hasChildren
                      ? Icon(
                          isExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: 14,
                          color: ReelForgeTheme.textSecondary,
                        )
                      : null,
                ),

                // Icon
                Text(
                  treeItemIcons[node.type] ?? '📄',
                  style: const TextStyle(fontSize: 12),
                ),

                const SizedBox(width: 6),

                // Label
                Expanded(
                  child: Text(
                    node.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: matchesSearch
                          ? ReelForgeTheme.accentBlue
                          : ReelForgeTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Count badge
                if (node.count != null && node.count! > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: ReelForgeTheme.bgElevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${node.count}',
                      style: TextStyle(
                        fontSize: 10,
                        color: ReelForgeTheme.textSecondary,
                      ),
                    ),
                  ),

                const SizedBox(width: 8),
              ],
            ),
          ),
        ),

        // Children
        if (hasChildren && isExpanded)
          ...visibleChildren.map((child) => _TreeItem(
                node: child,
                level: level + 1,
                selectedId: selectedId,
                expandedIds: expandedIds,
                onToggle: onToggle,
                onSelect: onSelect,
                onDoubleClick: onDoubleClick,
                searchQuery: searchQuery,
              )),
      ],
    );
  }
}
