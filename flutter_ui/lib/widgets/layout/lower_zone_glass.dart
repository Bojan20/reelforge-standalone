/// FluxForge Studio Lower Zone - Liquid Glass Edition
///
/// macOS Tahoe-inspired glass design with:
/// - Frosted blur background
/// - Specular highlights
/// - Glass-styled tabs and controls

import 'dart:ui';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../theme/liquid_glass_theme.dart';
import '../../models/layout_models.dart';
import '../glass/glass_widgets.dart';

/// Lower zone widget with Liquid Glass styling
class LowerZoneGlass extends StatefulWidget {
  final bool collapsed;
  final List<LowerZoneTab> tabs;
  final List<TabGroup>? tabGroups;
  final String? activeTabId;
  final ValueChanged<String>? onTabChange;
  final VoidCallback? onToggleCollapse;
  final double height;
  final ValueChanged<double>? onHeightChange;
  final double minHeight;
  final double maxHeight;

  const LowerZoneGlass({
    super.key,
    this.collapsed = false,
    this.tabs = const [],
    this.tabGroups,
    this.activeTabId,
    this.onTabChange,
    this.onToggleCollapse,
    this.height = 300,
    this.onHeightChange,
    this.minHeight = 300,
    this.maxHeight = 500,
  });

  @override
  State<LowerZoneGlass> createState() => _LowerZoneGlassState();
}

class _LowerZoneGlassState extends State<LowerZoneGlass> {
  double _height = 300;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _height = widget.height;
  }

  @override
  void didUpdateWidget(LowerZoneGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.height != widget.height) {
      _height = widget.height;
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _height = (_height - details.delta.dy)
          .clamp(widget.minHeight, widget.maxHeight);
    });
    widget.onHeightChange?.call(_height);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsed) {
      return const SizedBox.shrink();
    }

    final activeTab = widget.tabs.firstWhere(
      (t) => t.id == widget.activeTabId,
      orElse: () => widget.tabs.isNotEmpty
          ? widget.tabs.first
          : const LowerZoneTab(
              id: 'empty',
              label: 'Empty',
              content: SizedBox(),
            ),
    );

    // Glass container with frosted blur - same style as timeline
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurAmount,
          sigmaY: LiquidGlassTheme.blurAmount,
        ),
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            // Glass gradient - matches timeline styling
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.06),
                Colors.white.withValues(alpha: 0.03),
                Colors.black.withValues(alpha: 0.1),
              ],
            ),
            // Subtle top border
            border: const Border(
              top: BorderSide(
                color: Color(0x14FFFFFF), // alpha 0.08
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              // Resize handle
              _buildResizeHandle(),
              // Tab bar
              _buildTabBar(activeTab.id),
              // Content
              Expanded(
                child: activeTab.getContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResizeHandle() {
    return GestureDetector(
      onVerticalDragStart: (_) => setState(() => _isDragging = true),
      onVerticalDragUpdate: _handleDragUpdate,
      onVerticalDragEnd: (_) => setState(() => _isDragging = false),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: Container(
          height: 8,
          decoration: BoxDecoration(
            color: _isDragging
                ? LiquidGlassTheme.accentBlue.withValues(alpha: 0.2)
                : Colors.transparent,
          ),
          child: Center(
            child: AnimatedContainer(
              duration: LiquidGlassTheme.animFast,
              width: _isDragging ? 60 : 40,
              height: 4,
              decoration: BoxDecoration(
                color: _isDragging
                    ? LiquidGlassTheme.accentBlue
                    : Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
                boxShadow: _isDragging
                    ? LiquidGlassTheme.activeGlow(LiquidGlassTheme.accentBlue)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(String activeId) {
    final activeGroup = widget.tabGroups?.firstWhere(
      (g) => g.tabs.contains(activeId),
      orElse: () => const TabGroup(id: '', label: '', tabs: []),
    );

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          // Tabs with horizontal scroll
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.tabGroups != null
                    ? _buildGroupedTabs(activeId, activeGroup?.id)
                    : widget.tabs
                        .map((tab) => _buildTab(tab, activeId))
                        .toList(),
              ),
            ),
          ),

          // Collapse button
          if (widget.onToggleCollapse != null)
            GlassIconButton(
              icon: Icons.expand_more,
              onTap: widget.onToggleCollapse,
              size: 28,
              tooltip: 'Collapse',
            ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedTabs(String activeId, String? activeGroupId) {
    final List<Widget> widgets = [];

    for (int i = 0; i < widget.tabGroups!.length; i++) {
      final group = widget.tabGroups![i];
      final groupTabs =
          widget.tabs.where((t) => group.tabs.contains(t.id)).toList();
      final isActiveGroup = activeGroupId == group.id;
      final hasMultipleTabs = groupTabs.length > 1;

      // Separator between groups
      if (i > 0) {
        widgets.add(Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: Colors.white.withValues(alpha: 0.1),
        ));
      }

      if (hasMultipleTabs) {
        widgets.add(
            _buildGroupDropdown(group, groupTabs, isActiveGroup, activeId));
      } else if (groupTabs.isNotEmpty) {
        widgets.add(_buildTab(groupTabs.first, activeId));
      }
    }

    return widgets;
  }

  Widget _buildGroupDropdown(TabGroup group, List<LowerZoneTab> groupTabs,
      bool isActiveGroup, String activeId) {
    return PopupMenuButton<String>(
      onSelected: (tabId) => widget.onTabChange?.call(tabId),
      offset: const Offset(0, 32),
      color: const Color(0xE61a1a2e), // Glass-like popup
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      itemBuilder: (context) => groupTabs.map((tab) {
        final isActive = activeId == tab.id;
        return PopupMenuItem<String>(
          value: tab.id,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? LiquidGlassTheme.accentBlue.withValues(alpha: 0.3)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: isActive
                  ? Border.all(
                      color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.5))
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tab.icon != null) ...[
                  Icon(
                    tab.icon!,
                    size: 14,
                    color: isActive
                        ? LiquidGlassTheme.accentBlue
                        : LiquidGlassTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive
                        ? LiquidGlassTheme.accentBlue
                        : LiquidGlassTheme.textPrimary,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
      child: _buildGroupButton(group, isActiveGroup),
    );
  }

  Widget _buildGroupButton(TabGroup group, bool isActive) {
    return AnimatedContainer(
      duration: LiquidGlassTheme.animFast,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? LiquidGlassTheme.accentBlue.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? LiquidGlassTheme.accentBlue.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.1),
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.2),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            group.label,
            style: TextStyle(
              fontSize: 11,
              color: isActive
                  ? LiquidGlassTheme.accentBlue
                  : LiquidGlassTheme.textSecondary,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down,
            size: 14,
            color: isActive
                ? LiquidGlassTheme.accentBlue
                : LiquidGlassTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildTab(LowerZoneTab tab, String activeId) {
    final isActive = tab.id == activeId;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTabChange?.call(tab.id),
      child: AnimatedContainer(
        duration: LiquidGlassTheme.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: isActive
              ? LiquidGlassTheme.accentBlue.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isActive
              ? Border.all(
                  color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.4))
              : null,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tab.icon != null) ...[
              Icon(
                tab.icon!,
                size: 14,
                color: isActive
                    ? LiquidGlassTheme.accentBlue
                    : LiquidGlassTheme.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 11,
                color: isActive
                    ? LiquidGlassTheme.accentBlue
                    : LiquidGlassTheme.textSecondary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// GLASS MIXER STRIP
// ============================================================================

/// Mixer strip with Liquid Glass styling
class MixerStripGlass extends StatelessWidget {
  final String id;
  final String name;
  final bool isMaster;
  final double volume;
  final double pan;
  final bool muted;
  final bool soloed;
  final double meterLevel;
  final double? meterLevelR;
  final double? peakHold;
  final double? peakHoldR;
  final List<InsertSlot> inserts;
  final ValueChanged<double>? onVolumeChange;
  final ValueChanged<double>? onPanChange;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final void Function(int slotIndex, InsertSlot? insert)? onInsertClick;
  final VoidCallback? onSelect;
  final bool selected;

  const MixerStripGlass({
    super.key,
    required this.id,
    required this.name,
    this.isMaster = false,
    this.volume = 1.0,
    this.pan = 0,
    this.muted = false,
    this.soloed = false,
    this.meterLevel = 0,
    this.meterLevelR,
    this.peakHold,
    this.peakHoldR,
    this.inserts = const [],
    this.onVolumeChange,
    this.onPanChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onInsertClick,
    this.onSelect,
    this.selected = false,
  });

  String get _volumeDbStr {
    if (volume <= 0) return '-∞';
    final db = 20 * (math.log(volume) / math.ln10);
    return db <= -60 ? '-∞' : db.toStringAsFixed(1);
  }

  String get _panDisplay {
    if (pan == 0) return 'C';
    return pan < 0
        ? 'L${(pan.abs() * 100).round()}'
        : 'R${(pan * 100).round()}';
  }

  @override
  Widget build(BuildContext context) {
    final accentColor =
        isMaster ? LiquidGlassTheme.accentOrange : LiquidGlassTheme.accentBlue;

    return GestureDetector(
      onTap: onSelect,
      child: GlassContainer(
        width: 80,
        margin: const EdgeInsets.only(right: 2),
        tintOpacity: selected ? 0.12 : 0.06,
        tintColor: selected ? accentColor : Colors.white,
        border: Border(
          left: BorderSide(
            color: selected
                ? accentColor
                : isMaster
                    ? accentColor.withValues(alpha: 0.5)
                    : Colors.transparent,
            width: 3,
          ),
        ),
        borderRadius: 8,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Channel name
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isMaster
                    ? accentColor.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isMaster
                            ? accentColor
                            : LiquidGlassTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isMaster)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow:
                            LiquidGlassTheme.activeGlow(accentColor),
                      ),
                      child: const Text(
                        'M',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Inserts
            ...List.generate(4, (idx) {
              final insert = idx < inserts.length ? inserts[idx] : null;
              return _buildInsertSlot(idx, insert);
            }),

            // Pan knob (not for master)
            if (!isMaster && onPanChange != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: GlassKnob(
                  value: (pan + 1) / 2, // Convert -1..1 to 0..1
                  onChanged: (v) => onPanChange?.call(v * 2 - 1),
                  size: 36,
                  label: _panDisplay,
                  bipolar: true,
                ),
              ),

            // Fader + Meter section
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    // Meters
                    GlassMeter(
                      value: meterLevel,
                      peak: peakHold,
                      width: 6,
                    ),
                    const SizedBox(width: 2),
                    GlassMeter(
                      value: meterLevelR ?? meterLevel,
                      peak: peakHoldR ?? peakHold,
                      width: 6,
                    ),
                    const SizedBox(width: 6),

                    // Fader
                    Expanded(
                      child: GlassFader(
                        value: (volume / 1.5).clamp(0, 1),
                        onChanged: (v) => onVolumeChange?.call(v * 1.5),
                        color: accentColor,
                      ),
                    ),

                    // dB scale
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 18,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [6, 0, -6, -12, -24, -48]
                            .map((db) => Text(
                                  db.toString(),
                                  style: const TextStyle(
                                    fontSize: 7,
                                    color: LiquidGlassTheme.textTertiary,
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Volume display
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Center(
                child: Text(
                  '$_volumeDbStr dB',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: volume > 1
                        ? LiquidGlassTheme.accentRed
                        : LiquidGlassTheme.textPrimary,
                  ),
                ),
              ),
            ),

            // M/S buttons
            Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: 'M',
                      isActive: muted,
                      activeColor: LiquidGlassTheme.accentRed,
                      onTap: onMuteToggle,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GlassButton(
                      label: 'S',
                      isActive: soloed,
                      activeColor: LiquidGlassTheme.accentYellow,
                      onTap: onSoloToggle,
                      compact: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsertSlot(int index, InsertSlot? insert) {
    final hasPlugin = insert != null && !insert.isEmpty;
    final isBypassed = insert?.bypassed ?? false;

    return GestureDetector(
      onTap: () => onInsertClick?.call(index, insert),
      child: Container(
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: hasPlugin
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: hasPlugin && !isBypassed
                ? LiquidGlassTheme.accentGreen.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            // Power indicator
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasPlugin && !isBypassed
                    ? LiquidGlassTheme.accentGreen
                    : Colors.white.withValues(alpha: 0.2),
                boxShadow: hasPlugin && !isBypassed
                    ? [
                        BoxShadow(
                          color: LiquidGlassTheme.accentGreen
                              .withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 4),
            // Name
            Expanded(
              child: Text(
                hasPlugin ? insert.name : '+',
                style: TextStyle(
                  fontSize: 8,
                  color: hasPlugin
                      ? (isBypassed
                          ? LiquidGlassTheme.textTertiary
                          : LiquidGlassTheme.textPrimary)
                      : LiquidGlassTheme.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
