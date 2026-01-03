/// ReelForge Left Zone
///
/// Two-tab layout panel:
/// - Project Explorer: Wwise-style project hierarchy browser
/// - Channel: Cubase-style channel strip for selected track

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/layout_models.dart';
import 'project_tree.dart';
import 'channel_panel.dart';

// Re-export types for convenience
export 'project_tree.dart' show TreeItemType, ProjectTreeNode, treeItemIcons;

/// Left zone tabs
enum LeftZoneTab { project, channel }

/// Left Zone widget
class LeftZone extends StatefulWidget {
  final bool collapsed;
  final List<ProjectTreeNode> tree;
  final String? selectedId;
  final void Function(String id, TreeItemType type, dynamic data)? onSelect;
  final void Function(String id, TreeItemType type, dynamic data)? onDoubleClick;
  final String searchQuery;
  final ValueChanged<String>? onSearchChange;
  final void Function(TreeItemType type)? onAdd;
  final VoidCallback? onToggleCollapse;
  final LeftZoneTab activeTab;
  final ValueChanged<LeftZoneTab>? onTabChange;
  final ChannelStripData? channelData;
  final void Function(String channelId, double volume)? onChannelVolumeChange;
  final void Function(String channelId, double pan)? onChannelPanChange;
  final void Function(String channelId)? onChannelMuteToggle;
  final void Function(String channelId)? onChannelSoloToggle;
  final void Function(String channelId, int slotIndex)? onChannelInsertClick;
  final void Function(String channelId, int sendIndex, double level)? onChannelSendLevelChange;
  final void Function(String channelId)? onChannelEQToggle;
  final void Function(String channelId)? onChannelOutputClick;

  const LeftZone({
    super.key,
    this.collapsed = false,
    this.tree = const [],
    this.selectedId,
    this.onSelect,
    this.onDoubleClick,
    this.searchQuery = '',
    this.onSearchChange,
    this.onAdd,
    this.onToggleCollapse,
    this.activeTab = LeftZoneTab.project,
    this.onTabChange,
    this.channelData,
    this.onChannelVolumeChange,
    this.onChannelPanChange,
    this.onChannelMuteToggle,
    this.onChannelSoloToggle,
    this.onChannelInsertClick,
    this.onChannelSendLevelChange,
    this.onChannelEQToggle,
    this.onChannelOutputClick,
  });

  @override
  State<LeftZone> createState() => _LeftZoneState();
}

class _LeftZoneState extends State<LeftZone> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery;
  }

  @override
  void didUpdateWidget(LeftZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsed) return const SizedBox.shrink();

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        border: Border(
          right: BorderSide(color: ReelForgeTheme.borderSubtle, width: 1),
        ),
      ),
      child: Column(
        children: [
          _Header(
            activeTab: widget.activeTab,
            onTabChange: widget.onTabChange,
            onToggleCollapse: widget.onToggleCollapse,
          ),
          Expanded(
            child: widget.activeTab == LeftZoneTab.project
                ? _buildProjectExplorer()
                : _buildChannelPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectExplorer() {
    return Column(
      children: [
        _SearchBar(
          controller: _searchController,
          onChanged: widget.onSearchChange,
        ),
        Expanded(
          child: ProjectTree(
            nodes: widget.tree,
            selectedId: widget.selectedId,
            searchQuery: widget.searchQuery,
            onSelect: widget.onSelect,
            onDoubleClick: widget.onDoubleClick,
            onAdd: widget.onAdd,
          ),
        ),
      ],
    );
  }

  Widget _buildChannelPanel() {
    final channel = widget.channelData;
    if (channel == null) return const ChannelPanelEmpty();

    return ChannelPanel(
      channel: channel,
      onVolumeChange: widget.onChannelVolumeChange,
      onPanChange: widget.onChannelPanChange,
      onMuteToggle: widget.onChannelMuteToggle,
      onSoloToggle: widget.onChannelSoloToggle,
      onInsertClick: widget.onChannelInsertClick,
      onSendLevelChange: widget.onChannelSendLevelChange,
      onEQToggle: widget.onChannelEQToggle,
      onOutputClick: widget.onChannelOutputClick,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// HEADER
// ════════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final LeftZoneTab activeTab;
  final ValueChanged<LeftZoneTab>? onTabChange;
  final VoidCallback? onToggleCollapse;

  const _Header({
    required this.activeTab,
    this.onTabChange,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: ReelForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          _Tab(
            label: 'Project',
            icon: Icons.folder_outlined,
            isActive: activeTab == LeftZoneTab.project,
            onTap: () => onTabChange?.call(LeftZoneTab.project),
          ),
          _Tab(
            label: 'Channel',
            icon: Icons.tune,
            isActive: activeTab == LeftZoneTab.channel,
            onTap: () => onTabChange?.call(LeftZoneTab.channel),
          ),
          const Spacer(),
          if (onToggleCollapse != null)
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 18),
              onPressed: onToggleCollapse,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              color: ReelForgeTheme.textSecondary,
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback? onTap;

  const _Tab({
    required this.label,
    required this.icon,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? ReelForgeTheme.accentBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SEARCH BAR
// ════════════════════════════════════════════════════════════════════════════

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const _SearchBar({required this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.search, size: 14, color: ReelForgeTheme.textSecondary),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: const TextStyle(fontSize: 12, color: ReelForgeTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 12),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                },
                color: ReelForgeTheme.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}
