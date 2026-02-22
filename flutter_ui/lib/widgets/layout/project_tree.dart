/// Project Tree Widget
///
/// Ultimate DAW-style project hierarchy browser with:
/// - Professional Material icons with type-based accent colors
/// - Hover effects with smooth animation
/// - Indentation guide lines (Cubase-style depth visualization)
/// - Premium selection with glow accent
/// - Folder depth shading for visual hierarchy
/// - Smooth expand/collapse transitions

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

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

/// Icon + color config for each tree item type
class _TreeItemStyle {
  final IconData icon;
  final Color color;
  const _TreeItemStyle(this.icon, this.color);
}

/// Professional icon map — replaces emoji with Material icons + accent colors
const Map<TreeItemType, _TreeItemStyle> _treeItemStyles = {
  TreeItemType.folder:  _TreeItemStyle(Icons.folder_rounded, Color(0xFFD4A84B)),
  TreeItemType.event:   _TreeItemStyle(Icons.bolt_rounded, Color(0xFFFF9850)),
  TreeItemType.sound:   _TreeItemStyle(Icons.graphic_eq_rounded, Color(0xFF5AA8FF)),
  TreeItemType.bus:     _TreeItemStyle(Icons.call_split_rounded, Color(0xFFA855F7)),
  TreeItemType.state:   _TreeItemStyle(Icons.label_rounded, Color(0xFF50FF98)),
  TreeItemType.switch_: _TreeItemStyle(Icons.swap_horiz_rounded, Color(0xFF50D8FF)),
  TreeItemType.rtpc:    _TreeItemStyle(Icons.show_chart_rounded, Color(0xFFFF80B0)),
  TreeItemType.music:   _TreeItemStyle(Icons.music_note_rounded, Color(0xFFFFE050)),
};

/// Legacy icon map (emoji) for external consumers
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
  /// Duration string for audio files (e.g. "02:35")
  final String? duration;
  /// Whether this node is selected
  final bool isSelected;
  /// Whether this node is draggable (for pool items)
  final bool isDraggable;

  const ProjectTreeNode({
    required this.id,
    required this.type,
    required this.label,
    this.children = const [],
    this.count,
    this.data,
    this.duration,
    this.isSelected = false,
    this.isDraggable = false,
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

  /// External expanded IDs (from AudioAssetManager)
  /// If provided, these will be used instead of local state
  final Set<String>? externalExpandedIds;

  /// Callback when folder is toggled (for external state management)
  final void Function(String id)? onToggleExpanded;

  const ProjectTree({
    super.key,
    required this.nodes,
    this.selectedId,
    this.searchQuery = '',
    this.onSelect,
    this.onDoubleClick,
    this.onAdd,
    this.externalExpandedIds,
    this.onToggleExpanded,
  });

  @override
  State<ProjectTree> createState() => _ProjectTreeState();
}

class _ProjectTreeState extends State<ProjectTree> {
  final Set<String> _localExpandedIds = {};
  bool _initialized = false;

  /// Get the active expanded IDs (external or local)
  Set<String> get _expandedIds => widget.externalExpandedIds ?? _localExpandedIds;

  @override
  void didUpdateWidget(ProjectTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-expand all folders when nodes change (first load) - only for local state
    if (widget.externalExpandedIds == null && !_initialized && widget.nodes.isNotEmpty) {
      _expandAllFolders(widget.nodes);
      _initialized = true;
    }
  }

  /// Recursively collect all folder IDs to expand by default
  void _expandAllFolders(List<ProjectTreeNode> nodes) {
    for (final node in nodes) {
      if (node.children.isNotEmpty) {
        _localExpandedIds.add(node.id);
        _expandAllFolders(node.children);
      }
    }
  }

  void _toggleExpanded(String id) {
    // If external callback is provided, use it
    if (widget.onToggleExpanded != null) {
      widget.onToggleExpanded!(id);
      return;
    }

    // Otherwise manage locally
    setState(() {
      if (_localExpandedIds.contains(id)) {
        _localExpandedIds.remove(id);
      } else {
        _localExpandedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Auto-expand all folders on first build with nodes (only for local state)
    if (widget.externalExpandedIds == null && !_initialized && widget.nodes.isNotEmpty) {
      _expandAllFolders(widget.nodes);
      _initialized = true;
    }

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
                backgroundColor: FluxForgeTheme.bgElevated,
                foregroundColor: FluxForgeTheme.textPrimary,
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
// TREE ITEM — Ultimate DAW-style
// ════════════════════════════════════════════════════════════════════════════

class _TreeItem extends StatefulWidget {
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
  State<_TreeItem> createState() => _TreeItemState();
}

class _TreeItemState extends State<_TreeItem> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    final isExpanded = widget.expandedIds.contains(widget.node.id);
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
      value: isExpanded ? 1.0 : 0.0,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(_TreeItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isExpanded = widget.expandedIds.contains(widget.node.id);
    if (isExpanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasChildren = widget.node.children.isNotEmpty;
    final isExpanded = widget.expandedIds.contains(widget.node.id);
    final isSelected = widget.selectedId == widget.node.id;
    final isFolder = widget.node.type == TreeItemType.folder;
    final matchesSearch = widget.searchQuery.isNotEmpty &&
        widget.node.label.toLowerCase().contains(widget.searchQuery.toLowerCase());

    // Filter children if searching
    final visibleChildren = widget.searchQuery.isEmpty
        ? widget.node.children
        : widget.node.children.where((child) =>
            child.label.toLowerCase().contains(widget.searchQuery.toLowerCase()) ||
            child.children.any((c) =>
                c.label.toLowerCase().contains(widget.searchQuery.toLowerCase()))).toList();

    final style = _treeItemStyles[widget.node.type] ??
        const _TreeItemStyle(Icons.description_rounded, FluxForgeTheme.textSecondary);

    final typeColor = style.color;

    // Depth-based background dimming (folders slightly brighter)
    final depthAlpha = isFolder ? 0.03 : 0.0;
    final bgTint = widget.level > 0
        ? typeColor.withValues(alpha: depthAlpha)
        : Colors.transparent;

    // Build the item widget
    Widget itemWidget = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: 30,
        decoration: BoxDecoration(
          color: isSelected
              ? typeColor.withValues(alpha: 0.12)
              : _isHovered
                  ? FluxForgeTheme.bgHover.withValues(alpha: 0.5)
                  : bgTint,
          border: Border(
            left: BorderSide(
              color: isSelected ? typeColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            // Indentation guide lines
            ..._buildIndentGuides(widget.level),

            // Expand/collapse arrow
            SizedBox(
              width: 20,
              child: hasChildren
                  ? AnimatedBuilder(
                      animation: _expandAnimation,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _expandAnimation.value * 1.5708, // 0 → π/2
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: isSelected
                                ? typeColor
                                : _isHovered
                                    ? FluxForgeTheme.textPrimary
                                    : FluxForgeTheme.textTertiary,
                          ),
                        );
                      },
                    )
                  : const SizedBox(width: 16),
            ),

            const SizedBox(width: 2),

            // Type icon with accent color
            _TypeIcon(
              icon: isFolder
                  ? (isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded)
                  : style.icon,
              color: isSelected
                  ? typeColor
                  : _isHovered
                      ? typeColor
                      : typeColor.withValues(alpha: 0.65),
              isSelected: isSelected,
            ),

            const SizedBox(width: 8),

            // Label with premium typography
            Expanded(
              child: Text(
                widget.node.label,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: FluxForgeTheme.fontFamily,
                  fontWeight: isFolder ? FontWeight.w600 : FontWeight.w400,
                  color: matchesSearch
                      ? FluxForgeTheme.accentCyan
                      : isSelected
                          ? FluxForgeTheme.textPrimary
                          : _isHovered
                              ? FluxForgeTheme.textPrimary
                              : FluxForgeTheme.textSecondary,
                  letterSpacing: isFolder ? 0.3 : 0.0,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Duration badge for audio files
            if (widget.node.duration != null)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeepest,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  widget.node.duration!,
                  style: TextStyle(
                    fontFamily: FluxForgeTheme.monoFontFamily,
                    fontSize: 9,
                    color: FluxForgeTheme.textTertiary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),

            // Count badge
            if (widget.node.count != null && widget.node.count! > 0)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: typeColor.withValues(alpha: 0.25),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  '${widget.node.count}',
                  style: TextStyle(
                    fontFamily: FluxForgeTheme.monoFontFamily,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: typeColor.withValues(alpha: 0.8),
                  ),
                ),
              ),

            const SizedBox(width: 6),
          ],
        ),
      ),
    );

    // Wrap in Draggable if the node is draggable (pool audio files)
    if (widget.node.isDraggable && widget.node.data != null) {
      itemWidget = Draggable<Object>(
        data: widget.node.data!,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: typeColor.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: typeColor.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(style.icon, size: 14, color: typeColor),
                const SizedBox(width: 6),
                Text(
                  widget.node.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: FluxForgeTheme.textPrimary,
                    fontFamily: FluxForgeTheme.fontFamily,
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: itemWidget,
        ),
        child: itemWidget,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () {
            if (hasChildren) widget.onToggle(widget.node.id);
            widget.onSelect?.call(widget.node.id, widget.node.type, widget.node.data);
          },
          onDoubleTap: () => widget.onDoubleClick?.call(widget.node.id, widget.node.type, widget.node.data),
          child: itemWidget,
        ),

        // Children with clip for smooth expand/collapse
        if (hasChildren)
          SizeTransition(
            sizeFactor: _expandAnimation,
            axisAlignment: -1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: visibleChildren.map((child) => _TreeItem(
                    node: child,
                    level: widget.level + 1,
                    selectedId: widget.selectedId,
                    expandedIds: widget.expandedIds,
                    onToggle: widget.onToggle,
                    onSelect: widget.onSelect,
                    onDoubleClick: widget.onDoubleClick,
                    searchQuery: widget.searchQuery,
                  )).toList(),
            ),
          ),
      ],
    );
  }

  /// Build vertical indent guide lines for depth visualization
  List<Widget> _buildIndentGuides(int level) {
    if (level == 0) {
      return [const SizedBox(width: 8)];
    }

    final guides = <Widget>[];
    for (int i = 0; i < level; i++) {
      guides.add(
        SizedBox(
          width: 18,
          child: Center(
            child: Container(
              width: 1,
              height: 30,
              color: FluxForgeTheme.borderSubtle.withValues(
                alpha: 0.4 - (i * 0.08).clamp(0.0, 0.3),
              ),
            ),
          ),
        ),
      );
    }
    return guides;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TYPE ICON — Premium icon with subtle glow on selection
// ════════════════════════════════════════════════════════════════════════════

class _TypeIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isSelected;

  const _TypeIcon({
    required this.icon,
    required this.color,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: isSelected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 6,
                  spreadRadius: -1,
                ),
              ],
            )
          : null,
      child: Icon(
        icon,
        size: 15,
        color: color,
      ),
    );
  }
}
