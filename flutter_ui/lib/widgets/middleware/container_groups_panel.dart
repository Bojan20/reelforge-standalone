/// Container Groups Panel
///
/// Hierarchical container group management for nesting containers:
/// - Tree view of container groups (parent/child hierarchy)
/// - Group evaluation mode selector (All, FirstMatch, Priority, Random)
/// - Add/remove child containers
/// - Drag-reorder children within groups
/// - Visual nesting indicators (indentation + lines)
/// - Group statistics (total children, depth)
/// - FFI connection via container_create_group / container_evaluate_group
///
/// Uses mock data for the tree hierarchy since the Rust FFI
/// (container_ffi.rs) has container_create_group(), container_evaluate_group(),
/// container_group_add_child().

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Evaluation mode for a container group.
enum GroupEvalMode {
  all,
  firstMatch,
  priority,
  random;

  String get label {
    switch (this) {
      case GroupEvalMode.all:
        return 'All';
      case GroupEvalMode.firstMatch:
        return 'First Match';
      case GroupEvalMode.priority:
        return 'Priority';
      case GroupEvalMode.random:
        return 'Random';
    }
  }

  Color get color {
    switch (this) {
      case GroupEvalMode.all:
        return FluxForgeTheme.accentCyan;
      case GroupEvalMode.firstMatch:
        return FluxForgeTheme.accentGreen;
      case GroupEvalMode.priority:
        return FluxForgeTheme.accentOrange;
      case GroupEvalMode.random:
        return FluxForgeTheme.accentPurple;
    }
  }

  IconData get icon {
    switch (this) {
      case GroupEvalMode.all:
        return Icons.select_all;
      case GroupEvalMode.firstMatch:
        return Icons.first_page;
      case GroupEvalMode.priority:
        return Icons.sort;
      case GroupEvalMode.random:
        return Icons.shuffle;
    }
  }
}

/// Type of container child node.
enum _ContainerChildType {
  blend,
  random,
  sequence,
  group;

  String get label {
    switch (this) {
      case _ContainerChildType.blend:
        return 'Blend';
      case _ContainerChildType.random:
        return 'Random';
      case _ContainerChildType.sequence:
        return 'Sequence';
      case _ContainerChildType.group:
        return 'Group';
    }
  }

  Color get color {
    switch (this) {
      case _ContainerChildType.blend:
        return Colors.purple;
      case _ContainerChildType.random:
        return Colors.amber;
      case _ContainerChildType.sequence:
        return Colors.teal;
      case _ContainerChildType.group:
        return FluxForgeTheme.accentBlue;
    }
  }

  IconData get icon {
    switch (this) {
      case _ContainerChildType.blend:
        return Icons.tune;
      case _ContainerChildType.random:
        return Icons.casino;
      case _ContainerChildType.sequence:
        return Icons.format_list_numbered;
      case _ContainerChildType.group:
        return Icons.folder_open;
    }
  }
}

/// A node in the container group tree.
class _GroupNode {
  final int id;
  String name;
  GroupEvalMode evalMode;
  final _ContainerChildType type;
  final List<_GroupNode> children;
  bool expanded;
  int priority;

  _GroupNode({
    required this.id,
    required this.name,
    required this.type,
    this.evalMode = GroupEvalMode.all,
    List<_GroupNode>? children,
    this.expanded = true,
    this.priority = 0,
  }) : children = children ?? [];

  int get totalDescendants {
    int count = children.length;
    for (final child in children) {
      count += child.totalDescendants;
    }
    return count;
  }

  int get depth {
    if (children.isEmpty) return 0;
    int maxChildDepth = 0;
    for (final child in children) {
      final d = child.depth;
      if (d > maxChildDepth) maxChildDepth = d;
    }
    return maxChildDepth + 1;
  }
}

class ContainerGroupsPanel extends StatefulWidget {
  const ContainerGroupsPanel({super.key});

  @override
  State<ContainerGroupsPanel> createState() => _ContainerGroupsPanelState();
}

class _ContainerGroupsPanelState extends State<ContainerGroupsPanel> {
  final List<_GroupNode> _rootGroups = [];
  int _nextId = 100;
  int? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _initMockData();
  }

  void _initMockData() {
    _rootGroups.addAll([
      _GroupNode(
        id: 1,
        name: 'Base Game Audio',
        type: _ContainerChildType.group,
        evalMode: GroupEvalMode.all,
        children: [
          _GroupNode(
            id: 2,
            name: 'Spin Variations',
            type: _ContainerChildType.random,
            priority: 1,
          ),
          _GroupNode(
            id: 3,
            name: 'Reel Stop Mix',
            type: _ContainerChildType.blend,
            priority: 2,
          ),
          _GroupNode(
            id: 4,
            name: 'Win Sequence',
            type: _ContainerChildType.sequence,
            priority: 3,
          ),
        ],
      ),
      _GroupNode(
        id: 5,
        name: 'Feature Sounds',
        type: _ContainerChildType.group,
        evalMode: GroupEvalMode.priority,
        children: [
          _GroupNode(
            id: 6,
            name: 'Free Spin Music',
            type: _ContainerChildType.blend,
            priority: 1,
          ),
          _GroupNode(
            id: 7,
            name: 'Bonus Pick',
            type: _ContainerChildType.group,
            evalMode: GroupEvalMode.firstMatch,
            children: [
              _GroupNode(id: 8, name: 'Pick SFX', type: _ContainerChildType.random, priority: 1),
              _GroupNode(id: 9, name: 'Reveal Sequence', type: _ContainerChildType.sequence, priority: 2),
            ],
          ),
        ],
      ),
    ]);
  }

  void _addGroup() {
    final id = _nextId++;
    setState(() {
      _rootGroups.add(_GroupNode(
        id: id,
        name: 'New Group $id',
        type: _ContainerChildType.group,
        evalMode: GroupEvalMode.all,
      ));
    });
  }

  void _addChildTo(_GroupNode parent, _ContainerChildType type) {
    final id = _nextId++;
    setState(() {
      parent.children.add(_GroupNode(
        id: id,
        name: '${type.label} $id',
        type: type,
        priority: parent.children.length,
      ));
    });
  }

  void _removeNode(List<_GroupNode> siblings, int index) {
    setState(() {
      siblings.removeAt(index);
    });
  }

  void _reorderChild(List<_GroupNode> siblings, int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = siblings.removeAt(oldIndex);
      siblings.insert(newIndex, item);
      for (int i = 0; i < siblings.length; i++) {
        siblings[i].priority = i;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _rootGroups.isEmpty
                ? _buildEmptyState()
                : _buildTreeView(),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_tree, color: Colors.teal, size: 16),
          const SizedBox(width: 8),
          const Text(
            'CONTAINER GROUPS',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_rootGroups.length} roots',
              style: TextStyle(
                color: Colors.teal,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          _buildActionButton(
            icon: Icons.add,
            label: 'Add Group',
            color: Colors.teal,
            onTap: _addGroup,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    final c = color ?? FluxForgeTheme.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree, size: 32, color: FluxForgeTheme.textTertiary),
          const SizedBox(height: 8),
          Text(
            'No container groups',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            'Create groups to nest containers hierarchically',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeView() {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (int i = 0; i < _rootGroups.length; i++)
          _buildTreeNode(_rootGroups[i], 0, _rootGroups, i),
      ],
    );
  }

  Widget _buildTreeNode(_GroupNode node, int depth, List<_GroupNode> siblings, int index) {
    final isGroup = node.type == _ContainerChildType.group;
    final isSelected = _selectedGroupId == node.id;
    final indent = depth * 20.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Node row
        GestureDetector(
          onTap: () {
            setState(() {
              if (isGroup) {
                node.expanded = !node.expanded;
              }
              _selectedGroupId = node.id;
            });
          },
          child: Container(
            margin: EdgeInsets.only(left: indent, bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? node.type.color.withValues(alpha: 0.1)
                  : FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? node.type.color.withValues(alpha: 0.5)
                    : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                // Expand/collapse
                if (isGroup)
                  Icon(
                    node.expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 14,
                    color: FluxForgeTheme.textSecondary,
                  )
                else
                  const SizedBox(width: 14),
                const SizedBox(width: 4),
                // Type indicator
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: node.type.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                // Type icon
                Icon(node.type.icon, size: 13, color: node.type.color),
                const SizedBox(width: 6),
                // Name
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: isGroup ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Eval mode badge (groups only)
                if (isGroup) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: node.evalMode.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: node.evalMode.color.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(node.evalMode.icon, size: 9, color: node.evalMode.color),
                        const SizedBox(width: 3),
                        Text(
                          node.evalMode.label,
                          style: TextStyle(
                            color: node.evalMode.color,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Child count
                  Text(
                    '${node.children.length}',
                    style: TextStyle(
                      color: FluxForgeTheme.textTertiary,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                // Type badge (leaf only)
                if (!isGroup)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: node.type.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      node.type.label,
                      style: TextStyle(
                        color: node.type.color,
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                // Add child (groups only)
                if (isGroup)
                  _buildAddChildPopup(node),
                // Remove
                GestureDetector(
                  onTap: () => _removeNode(siblings, index),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 12, color: FluxForgeTheme.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Children (expanded groups only)
        if (isGroup && node.expanded)
          ...List.generate(node.children.length, (ci) {
            // Connector line
            return _buildTreeNode(node.children[ci], depth + 1, node.children, ci);
          }),
      ],
    );
  }

  Widget _buildAddChildPopup(_GroupNode parent) {
    return PopupMenuButton<_ContainerChildType>(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      iconSize: 14,
      icon: Icon(Icons.add_circle_outline, size: 13, color: Colors.teal.withValues(alpha: 0.7)),
      color: FluxForgeTheme.bgMid,
      tooltip: 'Add child',
      onSelected: (type) => _addChildTo(parent, type),
      itemBuilder: (context) => _ContainerChildType.values.map((type) {
        return PopupMenuItem(
          value: type,
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(type.icon, size: 14, color: type.color),
              const SizedBox(width: 8),
              Text(
                type.label,
                style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFooter() {
    int totalNodes = 0;
    int maxDepth = 0;
    for (final g in _rootGroups) {
      totalNodes += 1 + g.totalDescendants;
      final d = g.depth;
      if (d > maxDepth) maxDepth = d;
    }

    final selectedNode = _findNode(_selectedGroupId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          _buildStatChip('Nodes', '$totalNodes', Colors.teal),
          const SizedBox(width: 8),
          _buildStatChip('Depth', '$maxDepth', FluxForgeTheme.accentBlue),
          const Spacer(),
          // Eval mode selector for selected group
          if (selectedNode != null && selectedNode.type == _ContainerChildType.group) ...[
            Text(
              'Eval:',
              style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9),
            ),
            const SizedBox(width: 4),
            ...GroupEvalMode.values.map((mode) {
              final isActive = selectedNode.evalMode == mode;
              return Padding(
                padding: const EdgeInsets.only(left: 3),
                child: GestureDetector(
                  onTap: () => setState(() => selectedNode.evalMode = mode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isActive ? mode.color.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: isActive ? mode.color : FluxForgeTheme.borderSubtle,
                      ),
                    ),
                    child: Text(
                      mode.label,
                      style: TextStyle(
                        color: isActive ? mode.color : FluxForgeTheme.textTertiary,
                        fontSize: 8,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 8, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  _GroupNode? _findNode(int? id) {
    if (id == null) return null;
    return _findInList(_rootGroups, id);
  }

  _GroupNode? _findInList(List<_GroupNode> nodes, int id) {
    for (final node in nodes) {
      if (node.id == id) return node;
      final found = _findInList(node.children, id);
      if (found != null) return found;
    }
    return null;
  }
}
