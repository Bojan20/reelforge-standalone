/// ReelForge Left Zone
///
/// Mode-aware layout panel:
/// - DAW mode: Audio files browser + Channel strip
/// - Middleware mode: Wwise-style event/bus hierarchy + Channel
/// - Slot mode: Slot assets browser + Channel
///
/// 1:1 migration from React LeftZone.tsx

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/layout_models.dart' show ChannelStripData, EditorMode;
import 'project_tree.dart';
import 'channel_panel.dart';

/// Left zone tabs (matches React: 'project' | 'channel')
enum LeftZoneTab {
  /// Project browser (tree with folders, events, sounds, buses)
  project,
  /// Channel strip for selected track
  channel,
}

/// Left Zone widget
class LeftZone extends StatefulWidget {
  /// Current editor mode (determines browser content)
  final EditorMode editorMode;
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
    this.editorMode = EditorMode.daw,
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
            projectTabLabel: _projectTabLabel,
            projectTabIcon: _projectTabIcon,
            accentColor: _modeAccentColor,
          ),
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.activeTab) {
      case LeftZoneTab.project:
        return _buildProjectExplorer();
      case LeftZoneTab.channel:
        return _buildChannelPanel();
    }
  }

  /// Get mode-specific tab label
  String get _projectTabLabel {
    switch (widget.editorMode) {
      case EditorMode.daw:
        return 'Browser';
      case EditorMode.middleware:
        return 'Project';
      case EditorMode.slot:
        return 'Assets';
    }
  }

  /// Get mode-specific tab icon
  IconData get _projectTabIcon {
    switch (widget.editorMode) {
      case EditorMode.daw:
        return Icons.audio_file;
      case EditorMode.middleware:
        return Icons.folder_outlined;
      case EditorMode.slot:
        return Icons.casino;
    }
  }

  /// Get mode-specific accent color
  Color get _modeAccentColor {
    switch (widget.editorMode) {
      case EditorMode.daw:
        return ReelForgeTheme.accentBlue;
      case EditorMode.middleware:
        return ReelForgeTheme.accentOrange;
      case EditorMode.slot:
        return ReelForgeTheme.accentGreen;
    }
  }

  Widget _buildProjectExplorer() {
    return Column(
      children: [
        // Mode indicator bar
        _ModeIndicator(
          mode: widget.editorMode,
          accentColor: _modeAccentColor,
        ),
        _SearchBar(
          controller: _searchController,
          onChanged: widget.onSearchChange,
          placeholder: _getSearchPlaceholder(),
        ),
        Expanded(
          child: widget.tree.isEmpty
            ? _buildEmptyBrowser()
            : ProjectTree(
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

  String _getSearchPlaceholder() {
    switch (widget.editorMode) {
      case EditorMode.daw:
        return 'Search audio files...';
      case EditorMode.middleware:
        return 'Search events, buses...';
      case EditorMode.slot:
        return 'Search slot assets...';
    }
  }

  Widget _buildEmptyBrowser() {
    final (icon, message) = switch (widget.editorMode) {
      EditorMode.daw => (Icons.audio_file, 'Drop audio files here\nor import from File menu'),
      EditorMode.middleware => (Icons.account_tree, 'No events defined\nCreate events from Project menu'),
      EditorMode.slot => (Icons.casino, 'No slot assets\nImport from File menu'),
    };

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: _modeAccentColor.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: ReelForgeTheme.textTertiary,
              height: 1.5,
            ),
          ),
        ],
      ),
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
  final String projectTabLabel;
  final IconData projectTabIcon;
  final Color accentColor;

  const _Header({
    required this.activeTab,
    this.onTabChange,
    this.onToggleCollapse,
    required this.projectTabLabel,
    required this.projectTabIcon,
    required this.accentColor,
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
          // Project/Browser tab (mode-specific)
          _Tab(
            label: projectTabLabel,
            icon: projectTabIcon,
            isActive: activeTab == LeftZoneTab.project,
            onTap: () => onTabChange?.call(LeftZoneTab.project),
            accentColor: accentColor,
          ),
          // Channel tab
          _Tab(
            label: 'Channel',
            icon: Icons.tune,
            isActive: activeTab == LeftZoneTab.channel,
            onTap: () => onTabChange?.call(LeftZoneTab.channel),
            accentColor: accentColor,
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
  final Color accentColor;

  const _Tab({
    required this.label,
    required this.icon,
    required this.isActive,
    this.onTap,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? accentColor : ReelForgeTheme.textSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? accentColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
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
// MODE INDICATOR
// ════════════════════════════════════════════════════════════════════════════

class _ModeIndicator extends StatelessWidget {
  final EditorMode mode;
  final Color accentColor;

  const _ModeIndicator({
    required this.mode,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (mode) {
      EditorMode.daw => ('DAW Browser', Icons.audio_file),
      EditorMode.middleware => ('Middleware Project', Icons.account_tree),
      EditorMode.slot => ('Slot Assets', Icons.casino),
    };

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(color: accentColor.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: accentColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
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
  final String placeholder;

  const _SearchBar({
    required this.controller,
    this.onChanged,
    this.placeholder = 'Search...',
  });

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
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle: const TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 12),
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

