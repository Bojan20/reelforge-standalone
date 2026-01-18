/// Glass Left Zone
///
/// Liquid Glass styled left zone panel with tabbed interface:
/// - Browser tab (Project tree / Audio files / Assets)
/// - Channel tab (Channel Inspector with Volume, Pan, Inserts, Sends)
///
/// Maintains feature parity with classic LeftZone while using Glass styling.

import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../models/layout_models.dart' show ChannelStripData, EditorMode, InsertSlot, SendSlot;
import '../../models/timeline_models.dart' as timeline;
import '../layout/left_zone.dart' show LeftZoneTab;
import '../layout/project_tree.dart' show ProjectTreeNode, TreeItemType;
import 'glass_widgets.dart';

/// Glass-styled Left Zone with Browser and Channel tabs
class GlassLeftZone extends StatefulWidget {
  /// Current editor mode (determines browser content type)
  final EditorMode editorMode;

  /// Whether the zone is collapsed
  final bool collapsed;

  /// Project tree data for browser
  final List<ProjectTreeNode> tree;

  /// Currently selected item ID
  final String? selectedId;

  /// Callback when item is selected
  final void Function(String id, TreeItemType type, dynamic data)? onSelect;

  /// Callback when item is double-clicked
  final void Function(String id, TreeItemType type, dynamic data)? onDoubleClick;

  /// Search query for filtering tree
  final String searchQuery;

  /// Callback when search query changes
  final ValueChanged<String>? onSearchChange;

  /// Callback to add new item
  final void Function(TreeItemType type)? onAdd;

  /// Callback to toggle collapse
  final VoidCallback? onToggleCollapse;

  /// Currently active tab
  final LeftZoneTab activeTab;

  /// Callback when tab changes
  final ValueChanged<LeftZoneTab>? onTabChange;

  /// Channel data for channel inspector
  final ChannelStripData? channelData;

  /// Channel callbacks
  final void Function(String channelId, double volume)? onChannelVolumeChange;
  final void Function(String channelId, double pan)? onChannelPanChange;
  final void Function(String channelId, double pan)? onChannelPanRightChange;
  final void Function(String channelId)? onChannelMuteToggle;
  final void Function(String channelId)? onChannelSoloToggle;
  final void Function(String channelId)? onChannelArmToggle;
  final void Function(String channelId)? onChannelMonitorToggle;
  final void Function(String channelId, int slotIndex)? onChannelInsertClick;
  final void Function(String channelId, int sendIndex)? onChannelSendClick;
  final void Function(String channelId, int sendIndex, double level)? onChannelSendLevelChange;
  final void Function(String channelId)? onChannelEQToggle;
  final void Function(String channelId)? onChannelOutputClick;
  final void Function(String channelId)? onChannelInputClick;
  final void Function(String channelId, int slotIndex, bool bypassed)? onChannelInsertBypassToggle;
  final void Function(String channelId, int slotIndex, double wetDry)? onChannelInsertWetDryChange;
  final void Function(String channelId, int slotIndex)? onChannelInsertRemove;
  final void Function(String channelId, int slotIndex)? onChannelInsertOpenEditor;

  /// Clip inspector data
  final timeline.TimelineClip? selectedClip;
  final timeline.TimelineTrack? selectedClipTrack;
  final ValueChanged<timeline.TimelineClip>? onClipChanged;

  const GlassLeftZone({
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
    this.onChannelPanRightChange,
    this.onChannelMuteToggle,
    this.onChannelSoloToggle,
    this.onChannelArmToggle,
    this.onChannelMonitorToggle,
    this.onChannelInsertClick,
    this.onChannelSendClick,
    this.onChannelSendLevelChange,
    this.onChannelEQToggle,
    this.onChannelOutputClick,
    this.onChannelInputClick,
    this.onChannelInsertBypassToggle,
    this.onChannelInsertWetDryChange,
    this.onChannelInsertRemove,
    this.onChannelInsertOpenEditor,
    this.selectedClip,
    this.selectedClipTrack,
    this.onClipChanged,
  });

  @override
  State<GlassLeftZone> createState() => _GlassLeftZoneState();
}

class _GlassLeftZoneState extends State<GlassLeftZone> {
  final TextEditingController _searchController = TextEditingController();

  // Section expanded states for channel inspector
  bool _channelExpanded = true;
  bool _insertsExpanded = true;
  bool _sendsExpanded = false;
  bool _routingExpanded = false;
  bool _clipExpanded = true;
  bool _clipGainExpanded = true;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery;
  }

  @override
  void didUpdateWidget(GlassLeftZone oldWidget) {
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

  /// Get mode-specific tab label
  String get _browserTabLabel {
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
  IconData get _browserTabIcon {
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
        return LiquidGlassTheme.accentBlue;
      case EditorMode.middleware:
        return LiquidGlassTheme.accentOrange;
      case EditorMode.slot:
        return LiquidGlassTheme.accentGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsed) return const SizedBox.shrink();

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurAmount,
          sigmaY: LiquidGlassTheme.blurAmount,
        ),
        child: Container(
          width: 280,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Colors.white.withValues(alpha: 0.1),
                Colors.white.withValues(alpha: 0.05),
                Colors.white.withValues(alpha: 0.03),
              ],
            ),
            border: Border(
              right: BorderSide(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          // Browser tab
          _GlassTab(
            label: _browserTabLabel,
            icon: _browserTabIcon,
            isActive: widget.activeTab == LeftZoneTab.project,
            accentColor: _modeAccentColor,
            onTap: () => widget.onTabChange?.call(LeftZoneTab.project),
          ),
          const SizedBox(width: 4),
          // Channel tab
          _GlassTab(
            label: 'Channel',
            icon: Icons.tune,
            isActive: widget.activeTab == LeftZoneTab.channel,
            accentColor: _modeAccentColor,
            onTap: () => widget.onTabChange?.call(LeftZoneTab.channel),
          ),
          const Spacer(),
          // Collapse button
          if (widget.onToggleCollapse != null)
            GlassIconButton(
              icon: Icons.chevron_left,
              size: 24,
              onTap: widget.onToggleCollapse,
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.activeTab) {
      case LeftZoneTab.project:
        return _buildBrowserContent();
      case LeftZoneTab.channel:
        return _buildChannelContent();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BROWSER CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBrowserContent() {
    return Column(
      children: [
        // Mode indicator
        _buildModeIndicator(),
        // Search bar
        _buildSearchBar(),
        // Tree or empty state
        Expanded(
          child: widget.tree.isEmpty
              ? _buildEmptyBrowser()
              : _buildTreeView(),
        ),
      ],
    );
  }

  Widget _buildModeIndicator() {
    final (label, icon) = switch (widget.editorMode) {
      EditorMode.daw => ('DAW Browser', Icons.audio_file),
      EditorMode.middleware => ('Middleware Project', Icons.account_tree),
      EditorMode.slot => ('Slot Assets', Icons.casino),
    };

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _modeAccentColor.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: _modeAccentColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: _modeAccentColor),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: _modeAccentColor,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.search,
                size: 14,
                color: LiquidGlassTheme.textTertiary,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: widget.onSearchChange,
                style: const TextStyle(
                  fontSize: 12,
                  color: LiquidGlassTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: _getSearchPlaceholder(),
                  hintStyle: const TextStyle(
                    color: LiquidGlassTheme.textTertiary,
                    fontSize: 12,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              GlassIconButton(
                icon: Icons.close,
                size: 20,
                onTap: () {
                  _searchController.clear();
                  widget.onSearchChange?.call('');
                },
              ),
          ],
        ),
      ),
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
          Icon(
            icon,
            size: 48,
            color: _modeAccentColor.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: LiquidGlassTheme.textTertiary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeView() {
    final items = _flattenTree(widget.tree, 0);

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildTreeItem(items[index]),
    );
  }

  List<_FlatTreeItem> _flattenTree(List<ProjectTreeNode> nodes, int depth) {
    final List<_FlatTreeItem> items = [];

    for (final node in nodes) {
      items.add(_FlatTreeItem(node: node, depth: depth));

      if (node.children.isNotEmpty) {
        items.addAll(_flattenTree(node.children, depth + 1));
      }
    }

    return items;
  }

  Widget _buildTreeItem(_FlatTreeItem item) {
    final node = item.node;
    final isSelected = node.id == widget.selectedId;
    final isFolder = node.children.isNotEmpty;
    final color = _getColorForType(node.type);

    return GestureDetector(
      onTap: () => widget.onSelect?.call(node.id, node.type, node.data),
      onDoubleTap: () => widget.onDoubleClick?.call(node.id, node.type, node.data),
      child: AnimatedContainer(
        duration: LiquidGlassTheme.animFast,
        margin: const EdgeInsets.only(bottom: 2),
        padding: EdgeInsets.only(
          left: 8 + (item.depth * 16),
          right: 8,
          top: 6,
          bottom: 6,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? _modeAccentColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(color: _modeAccentColor.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          children: [
            // Folder chevron
            if (isFolder)
              Icon(
                Icons.keyboard_arrow_down,
                size: 14,
                color: LiquidGlassTheme.textTertiary,
              )
            else
              const SizedBox(width: 14),
            const SizedBox(width: 4),
            // Type icon
            Icon(
              _getIconForType(node.type),
              size: 14,
              color: color,
            ),
            const SizedBox(width: 8),
            // Label
            Expanded(
              child: Text(
                node.label,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected
                      ? _modeAccentColor
                      : LiquidGlassTheme.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForType(TreeItemType type) {
    switch (type) {
      case TreeItemType.folder:
        return Icons.folder;
      case TreeItemType.sound:
        return Icons.audio_file;
      case TreeItemType.event:
        return Icons.bolt;
      case TreeItemType.bus:
        return Icons.route;
      case TreeItemType.state:
        return Icons.flag;
      case TreeItemType.switch_:
        return Icons.toggle_on;
      case TreeItemType.rtpc:
        return Icons.show_chart;
      case TreeItemType.music:
        return Icons.music_note;
    }
  }

  Color _getColorForType(TreeItemType type) {
    switch (type) {
      case TreeItemType.folder:
        return LiquidGlassTheme.accentYellow;
      case TreeItemType.sound:
        return LiquidGlassTheme.accentGreen;
      case TreeItemType.event:
        return LiquidGlassTheme.accentOrange;
      case TreeItemType.bus:
        return LiquidGlassTheme.accentBlue;
      case TreeItemType.state:
        return LiquidGlassTheme.accentPurple;
      case TreeItemType.switch_:
        return LiquidGlassTheme.accentPink;
      case TreeItemType.rtpc:
        return LiquidGlassTheme.accentCyan;
      case TreeItemType.music:
        return LiquidGlassTheme.accentBlue;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANNEL CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildChannelContent() {
    final hasChannel = widget.channelData != null;
    final hasClip = widget.selectedClip != null;

    if (!hasChannel && !hasClip) {
      return _buildEmptyChannel();
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        // Channel header
        if (hasChannel) _buildChannelHeader(),

        // Channel controls
        if (hasChannel) ...[
          const SizedBox(height: 8),
          _buildChannelControls(),
        ],

        // Inserts section
        if (hasChannel) ...[
          const SizedBox(height: 8),
          _buildInsertsSection(),
        ],

        // Sends section
        if (hasChannel) ...[
          const SizedBox(height: 8),
          _buildSendsSection(),
        ],

        // Routing section
        if (hasChannel) ...[
          const SizedBox(height: 8),
          _buildRoutingSection(),
        ],

        // Divider if both channel and clip
        if (hasChannel && hasClip) ...[
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 12),
        ],

        // Clip section
        if (hasClip) ...[
          _buildClipSection(),
          const SizedBox(height: 8),
          _buildClipGainSection(),
        ],
      ],
    );
  }

  Widget _buildEmptyChannel() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.tune_outlined,
            size: 48,
            color: LiquidGlassTheme.textTertiary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select a track',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: LiquidGlassTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'or clip to inspect',
            style: TextStyle(
              fontSize: 11,
              color: LiquidGlassTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelHeader() {
    final ch = widget.channelData!;

    return GlassContainer(
      padding: EdgeInsets.zero,
      borderRadius: 8,
      tintOpacity: 0.08,
      child: Column(
        children: [
          // Name and type with color bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: ch.color, width: 4),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ch.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: LiquidGlassTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ch.type.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: ch.color,
                        ),
                      ),
                    ],
                  ),
                ),
                // EQ quick access
                GlassIconButton(
                  icon: Icons.graphic_eq,
                  size: 32,
                  isActive: ch.inserts.any((i) => i.name.contains('EQ')),
                  activeColor: LiquidGlassTheme.accentCyan,
                  onTap: () => widget.onChannelEQToggle?.call(ch.id),
                ),
              ],
            ),
          ),
          // Stereo meter
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                children: [
                  Expanded(child: _GlassMeter(level: ch.peakL)),
                  Container(width: 1, color: Colors.black.withValues(alpha: 0.5)),
                  Expanded(child: _GlassMeter(level: ch.peakR)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelControls() {
    final ch = widget.channelData!;

    return _GlassSection(
      title: 'Channel',
      expanded: _channelExpanded,
      onToggle: () => setState(() => _channelExpanded = !_channelExpanded),
      child: Column(
        children: [
          // Volume
          _GlassFaderRow(
            label: 'Volume',
            value: ch.volume,
            min: -70,
            max: 12,
            defaultValue: 0,
            formatValue: _formatDb,
            color: LiquidGlassTheme.accentGreen,
            onChanged: (v) => widget.onChannelVolumeChange?.call(ch.id, v),
          ),
          const SizedBox(height: 10),
          // Pan - stereo has dual pan (L/R), mono has single
          if (ch.isStereo) ...[
            // Stereo dual pan (Pro Tools style)
            _GlassFaderRow(
              label: 'Pan L',
              value: ch.pan * 100,
              min: -100,
              max: 100,
              defaultValue: -100, // Pro Tools: L defaults hard left
              formatValue: _formatPan,
              color: LiquidGlassTheme.accentCyan,
              onChanged: (v) => widget.onChannelPanChange?.call(ch.id, v / 100),
            ),
            const SizedBox(height: 6),
            _GlassFaderRow(
              label: 'Pan R',
              value: ch.panRight * 100,
              min: -100,
              max: 100,
              defaultValue: 100, // Pro Tools: R defaults hard right
              formatValue: _formatPan,
              color: LiquidGlassTheme.accentCyan,
              onChanged: (v) => widget.onChannelPanRightChange?.call(ch.id, v / 100),
            ),
          ] else ...[
            // Mono single pan
            _GlassFaderRow(
              label: 'Pan',
              value: ch.pan * 100,
              min: -100,
              max: 100,
              defaultValue: 0,
              formatValue: _formatPan,
              color: LiquidGlassTheme.accentCyan,
              onChanged: (v) => widget.onChannelPanChange?.call(ch.id, v / 100),
            ),
          ],
          const SizedBox(height: 12),
          // M/S/R/I buttons
          Row(
            children: [
              Expanded(
                child: _GlassStateButton(
                  label: 'M',
                  tooltip: 'Mute',
                  active: ch.mute,
                  activeColor: LiquidGlassTheme.accentOrange,
                  onTap: () => widget.onChannelMuteToggle?.call(ch.id),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _GlassStateButton(
                  label: 'S',
                  tooltip: 'Solo',
                  active: ch.solo,
                  activeColor: LiquidGlassTheme.accentYellow,
                  onTap: () => widget.onChannelSoloToggle?.call(ch.id),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _GlassStateButton(
                  label: 'R',
                  tooltip: 'Record Arm',
                  active: ch.armed,
                  activeColor: LiquidGlassTheme.accentRed,
                  onTap: () => widget.onChannelArmToggle?.call(ch.id),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _GlassStateButton(
                  label: 'I',
                  tooltip: 'Input Monitor',
                  active: ch.inputMonitor,
                  activeColor: LiquidGlassTheme.accentBlue,
                  onTap: () => widget.onChannelMonitorToggle?.call(ch.id),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInsertsSection() {
    final ch = widget.channelData!;
    final usedCount = ch.inserts.where((i) => !i.isEmpty).length;

    return _GlassSection(
      title: 'Inserts',
      subtitle: '$usedCount/8',
      expanded: _insertsExpanded,
      onToggle: () => setState(() => _insertsExpanded = !_insertsExpanded),
      child: Column(
        children: [
          _GlassGroupLabel('Pre-Fader'),
          for (int i = 0; i < 4; i++)
            _GlassInsertSlot(
              index: i,
              insert: i < ch.inserts.length ? ch.inserts[i] : InsertSlot.empty(i),
              onTap: () => widget.onChannelInsertClick?.call(ch.id, i),
              onBypassToggle: () {
                final insert = i < ch.inserts.length ? ch.inserts[i] : InsertSlot.empty(i);
                widget.onChannelInsertBypassToggle?.call(ch.id, i, !insert.bypassed);
              },
              onWetDryChange: (v) => widget.onChannelInsertWetDryChange?.call(ch.id, i, v),
              onRemove: () => widget.onChannelInsertRemove?.call(ch.id, i),
              onOpenEditor: () => widget.onChannelInsertOpenEditor?.call(ch.id, i),
            ),
          const SizedBox(height: 6),
          _GlassGroupLabel('Post-Fader'),
          for (int i = 4; i < 8; i++)
            _GlassInsertSlot(
              index: i,
              insert: i < ch.inserts.length ? ch.inserts[i] : InsertSlot.empty(i),
              onTap: () => widget.onChannelInsertClick?.call(ch.id, i),
              onBypassToggle: () {
                final insert = i < ch.inserts.length ? ch.inserts[i] : InsertSlot.empty(i);
                widget.onChannelInsertBypassToggle?.call(ch.id, i, !insert.bypassed);
              },
              onWetDryChange: (v) => widget.onChannelInsertWetDryChange?.call(ch.id, i, v),
              onRemove: () => widget.onChannelInsertRemove?.call(ch.id, i),
              onOpenEditor: () => widget.onChannelInsertOpenEditor?.call(ch.id, i),
            ),
        ],
      ),
    );
  }

  Widget _buildSendsSection() {
    final ch = widget.channelData!;

    return _GlassSection(
      title: 'Sends',
      subtitle: '4 aux',
      expanded: _sendsExpanded,
      onToggle: () => setState(() => _sendsExpanded = !_sendsExpanded),
      child: Column(
        children: [
          for (int i = 0; i < 4; i++)
            _GlassSendSlot(
              index: i,
              send: i < ch.sends.length ? ch.sends[i] : null,
              onTap: () => widget.onChannelSendClick?.call(ch.id, i),
              onLevelChange: (level) =>
                  widget.onChannelSendLevelChange?.call(ch.id, i, level),
            ),
        ],
      ),
    );
  }

  Widget _buildRoutingSection() {
    final ch = widget.channelData!;

    return _GlassSection(
      title: 'Routing',
      expanded: _routingExpanded,
      onToggle: () => setState(() => _routingExpanded = !_routingExpanded),
      child: Column(
        children: [
          _GlassRoutingRow(
            label: 'Input',
            value: ch.input.isNotEmpty ? ch.input : 'None',
            onTap: () => widget.onChannelInputClick?.call(ch.id),
          ),
          const SizedBox(height: 6),
          _GlassRoutingRow(
            label: 'Output',
            value: ch.output,
            onTap: () => widget.onChannelOutputClick?.call(ch.id),
          ),
        ],
      ),
    );
  }

  Widget _buildClipSection() {
    final clip = widget.selectedClip!;

    return _GlassSection(
      title: clip.name,
      subtitle: 'CLIP',
      color: clip.color ?? LiquidGlassTheme.accentBlue,
      expanded: _clipExpanded,
      onToggle: () => setState(() => _clipExpanded = !_clipExpanded),
      child: Column(
        children: [
          _GlassInfoRow('Position', _formatTime(clip.startTime)),
          _GlassInfoRow('Duration', _formatTime(clip.duration)),
          _GlassInfoRow('End', _formatTime(clip.startTime + clip.duration)),
          if (clip.sourceFile != null)
            _GlassInfoRow('Source', clip.sourceFile!.split('/').last),
          if (widget.selectedClipTrack != null)
            _GlassInfoRow('Track', widget.selectedClipTrack!.name),
        ],
      ),
    );
  }

  Widget _buildClipGainSection() {
    final clip = widget.selectedClip!;

    return _GlassSection(
      title: 'Gain & Fades',
      expanded: _clipGainExpanded,
      onToggle: () => setState(() => _clipGainExpanded = !_clipGainExpanded),
      child: Column(
        children: [
          // Gain
          _GlassFaderRow(
            label: 'Gain',
            value: clip.gain,
            min: 0,
            max: 2,
            defaultValue: 1,
            formatValue: (v) => _formatDbWithUnit(_linearToDb(v)),
            color: clip.locked
                ? LiquidGlassTheme.textTertiary
                : LiquidGlassTheme.accentCyan,
            onChanged: clip.locked
                ? null
                : (v) => widget.onClipChanged?.call(clip.copyWith(gain: v)),
          ),
          const SizedBox(height: 10),
          // Fade In
          _GlassFaderRow(
            label: 'Fade In',
            value: clip.fadeIn * 1000,
            min: 0,
            max: clip.duration * 500,
            defaultValue: 0,
            formatValue: (v) => '${v.toStringAsFixed(0)}ms',
            color: clip.locked
                ? LiquidGlassTheme.textTertiary
                : LiquidGlassTheme.accentGreen,
            onChanged: clip.locked
                ? null
                : (v) => widget.onClipChanged?.call(clip.copyWith(fadeIn: v / 1000)),
          ),
          const SizedBox(height: 10),
          // Fade Out
          _GlassFaderRow(
            label: 'Fade Out',
            value: clip.fadeOut * 1000,
            min: 0,
            max: clip.duration * 500,
            defaultValue: 0,
            formatValue: (v) => '${v.toStringAsFixed(0)}ms',
            color: clip.locked
                ? LiquidGlassTheme.textTertiary
                : LiquidGlassTheme.accentOrange,
            onChanged: clip.locked
                ? null
                : (v) => widget.onClipChanged?.call(clip.copyWith(fadeOut: v / 1000)),
          ),
          const SizedBox(height: 12),
          // Mute/Lock buttons
          Row(
            children: [
              Expanded(
                child: _GlassStateButton(
                  label: clip.muted ? 'UNMUTE' : 'MUTE',
                  active: clip.muted,
                  activeColor: LiquidGlassTheme.accentRed,
                  onTap: () =>
                      widget.onClipChanged?.call(clip.copyWith(muted: !clip.muted)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GlassStateButton(
                  label: clip.locked ? 'UNLOCK' : 'LOCK',
                  active: clip.locked,
                  activeColor: LiquidGlassTheme.accentYellow,
                  onTap: () =>
                      widget.onClipChanged?.call(clip.copyWith(locked: !clip.locked)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FORMATTERS
  // ═══════════════════════════════════════════════════════════════════════════

  String _formatDb(double db) {
    if (db <= -70) return '-∞';
    return db >= 0 ? '+${db.toStringAsFixed(1)}' : db.toStringAsFixed(1);
  }

  String _formatDbWithUnit(double db) {
    if (db <= -70) return '-∞ dB';
    return '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';
  }

  String _formatPan(double v) {
    if (v.abs() < 1) return 'C';
    return v < 0 ? 'L${v.abs().round()}' : 'R${v.round()}';
  }

  String _formatTime(double seconds) {
    if (seconds < 1) return '${(seconds * 1000).toStringAsFixed(0)}ms';
    if (seconds < 60) return '${seconds.toStringAsFixed(2)}s';
    final mins = (seconds / 60).floor();
    final secs = seconds % 60;
    return '$mins:${secs.toStringAsFixed(2).padLeft(5, '0')}';
  }

  double _linearToDb(double linear) {
    if (linear <= 0) return -70;
    return 20 * (math.log(linear) / math.ln10);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER CLASSES
// ═══════════════════════════════════════════════════════════════════════════

class _FlatTreeItem {
  final ProjectTreeNode node;
  final int depth;

  _FlatTreeItem({required this.node, required this.depth});
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS UI COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════

class _GlassTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color accentColor;
  final VoidCallback? onTap;

  const _GlassTab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? accentColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isActive
              ? Border.all(color: accentColor.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? accentColor : LiquidGlassTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? accentColor : LiquidGlassTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? color;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const _GlassSection({
    required this.title,
    this.subtitle,
    this.color,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: EdgeInsets.zero,
      borderRadius: 8,
      tintOpacity: 0.06,
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: color != null
                  ? BoxDecoration(
                      border: Border(
                        left: BorderSide(color: color!, width: 3),
                      ),
                    )
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: LiquidGlassTheme.textPrimary,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              subtitle!,
                              style: const TextStyle(
                                fontSize: 9,
                                fontFamily: 'JetBrains Mono',
                                color: LiquidGlassTheme.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: LiquidGlassTheme.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          // Content
          if (expanded)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _GlassMeter extends StatelessWidget {
  final double level;

  const _GlassMeter({required this.level});

  @override
  Widget build(BuildContext context) {
    final clampedLevel = level.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        color: Colors.transparent,
        child: FractionallySizedBox(
          widthFactor: clampedLevel,
          alignment: Alignment.centerLeft,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  LiquidGlassTheme.accentGreen,
                  clampedLevel > 0.7
                      ? LiquidGlassTheme.accentYellow
                      : LiquidGlassTheme.accentGreen,
                  clampedLevel > 0.9
                      ? LiquidGlassTheme.accentRed
                      : LiquidGlassTheme.accentYellow,
                ],
                stops: const [0.0, 0.7, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassFaderRow extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final String Function(double) formatValue;
  final Color color;
  final ValueChanged<double>? onChanged;

  const _GlassFaderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.formatValue,
    required this.color,
    this.onChanged,
  });

  @override
  State<_GlassFaderRow> createState() => _GlassFaderRowState();
}

class _GlassFaderRowState extends State<_GlassFaderRow> {
  double _dragStartX = 0;
  double _dragStartNorm = 0;

  double _valueToNormalized(double value) {
    if (value <= widget.min) return 0.0;
    if (value >= widget.max) return 1.0;
    return (value - widget.min) / (widget.max - widget.min);
  }

  double _normalizedToValue(double normalized) {
    if (normalized <= 0.0) return widget.min;
    if (normalized >= 1.0) return widget.max;
    return widget.min + (normalized * (widget.max - widget.min));
  }

  void _handleDragStart(DragStartDetails details, double width) {
    _dragStartX = details.localPosition.dx;
    _dragStartNorm = _valueToNormalized(widget.value);
  }

  void _handleDragUpdate(DragUpdateDetails details, double width) {
    if (widget.onChanged == null) return;

    final deltaX = details.localPosition.dx - _dragStartX;
    final deltaNorm = deltaX / width;
    final newNorm = (_dragStartNorm + deltaNorm).clamp(0.0, 1.0);
    final newValue = _normalizedToValue(newNorm);

    widget.onChanged!(newValue);
  }

  @override
  Widget build(BuildContext context) {
    final percentage = _valueToNormalized(widget.value);

    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 10,
              color: LiquidGlassTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) =>
                  _handleDragStart(d, constraints.maxWidth),
              onHorizontalDragUpdate: (d) =>
                  _handleDragUpdate(d, constraints.maxWidth),
              onDoubleTap: () => widget.onChanged?.call(widget.defaultValue),
              child: Container(
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Stack(
                  children: [
                    // Fill
                    FractionallySizedBox(
                      widthFactor: percentage,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              widget.color.withValues(alpha: 0.5),
                              widget.color,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    // Center mark for pan
                    if (widget.label == 'Pan')
                      Positioned(
                        left: constraints.maxWidth / 2 - 0.5,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 1,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            widget.formatValue(widget.value),
            style: const TextStyle(
              fontSize: 10,
              fontFamily: 'JetBrains Mono',
              color: LiquidGlassTheme.textSecondary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _GlassStateButton extends StatefulWidget {
  final String label;
  final String? tooltip;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _GlassStateButton({
    required this.label,
    this.tooltip,
    required this.active,
    required this.activeColor,
    this.onTap,
  });

  @override
  State<_GlassStateButton> createState() => _GlassStateButtonState();
}

class _GlassStateButtonState extends State<_GlassStateButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final showActive = _pressed ? !widget.active : widget.active;

    final button = GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: showActive
              ? widget.activeColor.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: showActive
                ? widget.activeColor.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
            width: showActive ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: showActive
                  ? widget.activeColor
                  : LiquidGlassTheme.textSecondary,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

class _GlassGroupLabel extends StatelessWidget {
  final String label;

  const _GlassGroupLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 2),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: LiquidGlassTheme.textTertiary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassInsertSlot extends StatefulWidget {
  final int index;
  final InsertSlot insert;
  final VoidCallback? onTap;
  final VoidCallback? onBypassToggle;
  final ValueChanged<double>? onWetDryChange;
  final VoidCallback? onRemove;
  final VoidCallback? onOpenEditor;

  const _GlassInsertSlot({
    required this.index,
    required this.insert,
    this.onTap,
    this.onBypassToggle,
    this.onWetDryChange,
    this.onRemove,
    this.onOpenEditor,
  });

  @override
  State<_GlassInsertSlot> createState() => _GlassInsertSlotState();
}

class _GlassInsertSlotState extends State<_GlassInsertSlot> {
  bool _isHovered = false;
  bool _showWetDry = false;

  @override
  Widget build(BuildContext context) {
    final hasPlugin = !widget.insert.isEmpty;
    final isEq = widget.insert.name.toLowerCase().contains('eq');
    final accentColor = widget.index < 4 ? LiquidGlassTheme.accentBlue : LiquidGlassTheme.accentOrange;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _showWetDry = false;
      }),
      child: GestureDetector(
        onTap: hasPlugin ? null : widget.onTap,
        onSecondaryTap: hasPlugin ? () => setState(() => _showWetDry = !_showWetDry) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: hasPlugin
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: hasPlugin && !widget.insert.bypassed
                  ? (isEq ? LiquidGlassTheme.accentCyan : accentColor).withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Bypass toggle
                  GestureDetector(
                    onTap: hasPlugin ? widget.onBypassToggle : null,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasPlugin
                            ? (widget.insert.bypassed ? Colors.transparent : accentColor)
                            : Colors.white.withValues(alpha: 0.1),
                        border: Border.all(
                          color: hasPlugin
                              ? (widget.insert.bypassed ? LiquidGlassTheme.textDisabled : accentColor)
                              : Colors.white.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                        boxShadow: hasPlugin && !widget.insert.bypassed
                            ? [BoxShadow(color: accentColor.withValues(alpha: 0.4), blurRadius: 4)]
                            : null,
                      ),
                      child: widget.insert.bypassed && hasPlugin
                          ? Center(child: Container(width: 5, height: 1.5, color: LiquidGlassTheme.textDisabled))
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Name - tap to open plugin picker
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onTap,
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        hasPlugin ? widget.insert.name : '+ Insert ${widget.index + 1}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: hasPlugin ? FontWeight.w500 : FontWeight.w400,
                          color: hasPlugin
                              ? (widget.insert.bypassed ? LiquidGlassTheme.textTertiary : LiquidGlassTheme.textPrimary)
                              : LiquidGlassTheme.textTertiary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Wet/Dry indicator
                  if (hasPlugin && widget.insert.wetDry < 0.99)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '${widget.insert.wetDryPercent}%',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: LiquidGlassTheme.accentCyan.withValues(alpha: 0.8)),
                      ),
                    ),
                  // Expand wet/dry on hover
                  if (hasPlugin && _isHovered)
                    GestureDetector(
                      onTap: () => setState(() => _showWetDry = !_showWetDry),
                      child: Icon(_showWetDry ? Icons.expand_less : Icons.expand_more, size: 14, color: LiquidGlassTheme.textTertiary),
                    ),
                  // Icon for EQ
                  if (isEq && hasPlugin)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.graphic_eq, size: 12, color: LiquidGlassTheme.accentCyan),
                    ),
                  // Open Editor button
                  if (hasPlugin && _isHovered)
                    GestureDetector(
                      onTap: widget.onOpenEditor,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Tooltip(
                          message: 'Open Editor',
                          waitDuration: const Duration(milliseconds: 500),
                          child: Icon(Icons.open_in_new, size: 14, color: LiquidGlassTheme.textTertiary),
                        ),
                      ),
                    ),
                  // Remove button
                  if (hasPlugin && _isHovered)
                    GestureDetector(
                      onTap: widget.onRemove,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Tooltip(
                          message: 'Remove',
                          waitDuration: const Duration(milliseconds: 500),
                          child: Icon(Icons.close, size: 14, color: LiquidGlassTheme.textTertiary),
                        ),
                      ),
                    ),
                ],
              ),
              // Wet/Dry slider
              if (_showWetDry && hasPlugin)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Text('D', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: LiquidGlassTheme.textTertiary)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: SizedBox(
                          height: 20,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                              activeTrackColor: LiquidGlassTheme.accentCyan,
                              inactiveTrackColor: Colors.black.withValues(alpha: 0.3),
                              thumbColor: LiquidGlassTheme.accentCyan,
                              overlayColor: LiquidGlassTheme.accentCyan.withValues(alpha: 0.2),
                            ),
                            child: Slider(
                              value: widget.insert.wetDry,
                              min: 0.0,
                              max: 1.0,
                              onChanged: widget.onWetDryChange,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('W', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: LiquidGlassTheme.accentCyan)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassSendSlot extends StatefulWidget {
  final int index;
  final SendSlot? send;
  final VoidCallback? onTap;
  final ValueChanged<double>? onLevelChange;

  const _GlassSendSlot({
    required this.index,
    this.send,
    this.onTap,
    this.onLevelChange,
  });

  @override
  State<_GlassSendSlot> createState() => _GlassSendSlotState();
}

class _GlassSendSlotState extends State<_GlassSendSlot> {
  double _dragStartX = 0;
  double _dragStartValue = 0;
  static const double _faderWidth = 50.0;

  void _handleDragStart(DragStartDetails details) {
    _dragStartX = details.localPosition.dx;
    _dragStartValue = widget.send?.level ?? 0.0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.onLevelChange == null) return;
    final deltaX = details.localPosition.dx - _dragStartX;
    final deltaPercent = deltaX / _faderWidth;
    final newValue = (_dragStartValue + deltaPercent).clamp(0.0, 1.0);
    widget.onLevelChange!(newValue);
  }

  @override
  Widget build(BuildContext context) {
    final hasDestination =
        widget.send?.destination != null && widget.send!.destination!.isNotEmpty;
    final level = widget.send?.level ?? 0.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: 28,
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hasDestination
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: hasDestination
                ? LiquidGlassTheme.accentBlue.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            // Send number
            SizedBox(
              width: 20,
              child: Text(
                '${widget.index + 1}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: LiquidGlassTheme.textTertiary,
                ),
              ),
            ),
            // Destination
            Expanded(
              child: Text(
                hasDestination ? widget.send!.destination! : 'No Send',
                style: TextStyle(
                  fontSize: 10,
                  color: hasDestination
                      ? LiquidGlassTheme.textPrimary
                      : LiquidGlassTheme.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Level bar
            if (hasDestination) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: _faderWidth,
                child: GestureDetector(
                  onHorizontalDragStart: _handleDragStart,
                  onHorizontalDragUpdate: _handleDragUpdate,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: level,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          color: LiquidGlassTheme.accentBlue,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GlassRoutingRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _GlassRoutingRow({
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: LiquidGlassTheme.textTertiary,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: LiquidGlassTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: LiquidGlassTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _GlassInfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: LiquidGlassTheme.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
                color: LiquidGlassTheme.textSecondary,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
