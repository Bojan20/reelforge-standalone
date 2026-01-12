/// FluxForge Studio Lower Zone
///
/// Dockable panel area with tabs:
/// - Mixer
/// - Editor
/// - Browser
/// - Profiler
/// - Console
///
/// 1:1 migration from React LowerZone.tsx

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../theme/fluxforge_theme.dart';
import '../../models/layout_models.dart';

/// Lower zone widget
class LowerZone extends StatefulWidget {
  /// Whether zone is collapsed
  final bool collapsed;

  /// Available tabs
  final List<LowerZoneTab> tabs;

  /// Tab groups for hierarchical organization
  final List<TabGroup>? tabGroups;

  /// Active tab ID
  final String? activeTabId;

  /// On tab change
  final ValueChanged<String>? onTabChange;

  /// On collapse toggle
  final VoidCallback? onToggleCollapse;

  /// Initial height
  final double height;

  /// On height change
  final ValueChanged<double>? onHeightChange;

  /// Min height
  final double minHeight;

  /// Max height
  final double maxHeight;

  const LowerZone({
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
  State<LowerZone> createState() => _LowerZoneState();
}

class _LowerZoneState extends State<LowerZone> {
  double _height = 300;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _height = widget.height;
  }

  @override
  void didUpdateWidget(LowerZone oldWidget) {
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
      orElse: () => widget.tabs.isNotEmpty ? widget.tabs.first : const LowerZoneTab(
        id: 'empty',
        label: 'Empty',
        content: SizedBox(),
      ),
    );

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(
          top: BorderSide(
            color: FluxForgeTheme.borderSubtle,
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
          height: 6,
          decoration: BoxDecoration(
            color: _isDragging
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
          child: Center(
            child: Container(
              width: 40,
              height: 3,
              decoration: BoxDecoration(
                color: _isDragging
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.borderMedium,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(String activeId) {
    // Find which group contains the active tab
    final activeGroup = widget.tabGroups?.firstWhere(
      (g) => g.tabs.contains(activeId),
      orElse: () => const TabGroup(id: '', label: '', tabs: []),
    );

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
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
                    : widget.tabs.map((tab) => _buildTab(tab, activeId)).toList(),
              ),
            ),
          ),

          // Collapse button
          if (widget.onToggleCollapse != null)
            IconButton(
              icon: const Icon(Icons.expand_more, size: 18),
              onPressed: widget.onToggleCollapse,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              color: FluxForgeTheme.textSecondary,
            ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedTabs(String activeId, String? activeGroupId) {
    final List<Widget> widgets = [];

    for (int i = 0; i < widget.tabGroups!.length; i++) {
      final group = widget.tabGroups![i];
      final groupTabs = widget.tabs.where((t) => group.tabs.contains(t.id)).toList();
      final isActiveGroup = activeGroupId == group.id;
      final hasMultipleTabs = groupTabs.length > 1;

      // Separator between groups
      if (i > 0) {
        widgets.add(Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: FluxForgeTheme.borderSubtle,
        ));
      }

      if (hasMultipleTabs) {
        // Group with dropdown
        widgets.add(_buildGroupDropdown(group, groupTabs, isActiveGroup, activeId));
      } else if (groupTabs.isNotEmpty) {
        // Single tab in group
        widgets.add(_buildTab(groupTabs.first, activeId));
      }
    }

    return widgets;
  }

  Widget _buildGroupDropdown(TabGroup group, List<LowerZoneTab> groupTabs, bool isActiveGroup, String activeId) {
    return PopupMenuButton<String>(
      onSelected: (tabId) {
        widget.onTabChange?.call(tabId);
      },
      offset: const Offset(0, 28),
      color: FluxForgeTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      itemBuilder: (context) => groupTabs.map((tab) {
        final isActive = activeId == tab.id;
        return PopupMenuItem<String>(
          value: tab.id,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? FluxForgeTheme.accentBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tab.icon != null) ...[
                  Icon(tab.icon!, size: 12, color: isActive ? Colors.white : FluxForgeTheme.textSecondary),
                  const SizedBox(width: 6),
                ],
                Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isActive ? Colors.white : FluxForgeTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActiveGroup ? FluxForgeTheme.bgElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border(
            bottom: BorderSide(
              color: isActiveGroup ? FluxForgeTheme.accentBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              group.label,
              style: TextStyle(
                fontSize: 11,
                color: isActiveGroup ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
                fontWeight: isActiveGroup ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: isActiveGroup ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(LowerZoneTab tab, String activeId) {
    final isActive = tab.id == activeId;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTabChange?.call(tab.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? FluxForgeTheme.accentBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            if (tab.icon != null) ...[
              Icon(tab.icon!, size: 14, color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 11,
                color: isActive
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.textSecondary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============ Mixer Strip Component ============

/// Mixer strip widget
class MixerStrip extends StatelessWidget {
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
  final void Function(int slotIndex, InsertSlot insert)? onInsertBypass;
  final VoidCallback? onSelect;
  final bool selected;

  const MixerStrip({
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
    this.onInsertBypass,
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
    // Insert slots (always show 4)
    final insertSlots = List<InsertSlot?>.generate(
      4,
      (i) => i < inserts.length ? inserts[i] : null,
    );

    return GestureDetector(
      onTap: onSelect,
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 1),
        decoration: BoxDecoration(
          color: selected
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.1)
              : FluxForgeTheme.bgMid,
          border: Border(
            left: BorderSide(
              color: selected
                  ? FluxForgeTheme.accentBlue
                  : isMaster
                      ? FluxForgeTheme.warningOrange
                      : Colors.transparent,
              width: 2,
            ),
            right: BorderSide(color: FluxForgeTheme.borderSubtle),
          ),
        ),
        child: Column(
          children: [
            // Channel name
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isMaster
                    ? FluxForgeTheme.warningOrange.withValues(alpha: 0.2)
                    : FluxForgeTheme.bgElevated,
                border: Border(
                  bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: FluxForgeTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isMaster)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.warningOrange,
                        borderRadius: BorderRadius.circular(2),
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
            ...insertSlots.asMap().entries.map((entry) {
              final idx = entry.key;
              final insert = entry.value;
              return _buildInsertSlot(idx, insert);
            }),

            // Pan (not for master)
            if (!isMaster && onPanChange != null)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderThemeData(
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: SliderComponentShape.noOverlay,
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: pan,
                        min: -1,
                        max: 1,
                        onChanged: onPanChange,
                        activeColor: FluxForgeTheme.accentBlue,
                        inactiveColor: FluxForgeTheme.bgDeepest,
                      ),
                    ),
                    Text(
                      _panDisplay,
                      style: FluxForgeTheme.monoSmall.copyWith(fontSize: 9),
                    ),
                  ],
                ),
              ),

            // Fader + Meter section
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    // Meter
                    _CanvasMeter(
                      levelL: meterLevel,
                      levelR: meterLevelR ?? meterLevel,
                      peakL: peakHold,
                      peakR: peakHoldR,
                      height: double.infinity,
                    ),

                    const SizedBox(width: 4),

                    // Fader
                    Expanded(
                      child: _buildFader(),
                    ),

                    // dB scale
                    SizedBox(
                      width: 20,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [6, 0, -6, -12, -24, -48]
                            .map((db) => Text(
                                  db.toString(),
                                  style: TextStyle(
                                    fontSize: 7,
                                    color: FluxForgeTheme.textSecondary,
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
              child: Text(
                '$_volumeDbStr dB',
                style: FluxForgeTheme.monoSmall.copyWith(
                  fontSize: 10,
                  color: volume > 1 ? FluxForgeTheme.errorRed : null,
                ),
              ),
            ),

            // M/S buttons
            Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onMuteToggle,
                      child: Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: muted
                              ? FluxForgeTheme.errorRed
                              : FluxForgeTheme.bgDeepest,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: muted
                                ? FluxForgeTheme.errorRed
                                : FluxForgeTheme.borderSubtle,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'M',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: muted
                                  ? Colors.white
                                  : FluxForgeTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: GestureDetector(
                      onTap: onSoloToggle,
                      child: Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: soloed
                              ? FluxForgeTheme.warningOrange
                              : FluxForgeTheme.bgDeepest,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: soloed
                                ? FluxForgeTheme.warningOrange
                                : FluxForgeTheme.borderSubtle,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'S',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: soloed
                                  ? Colors.black
                                  : FluxForgeTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
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

    return GestureDetector(
      onTap: () => onInsertClick?.call(index, insert),
      child: Container(
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: hasPlugin
              ? FluxForgeTheme.bgElevated
              : FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: hasPlugin && !insert.bypassed
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                : FluxForgeTheme.borderSubtle,
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
                color: hasPlugin && !insert.bypassed
                    ? FluxForgeTheme.accentGreen
                    : FluxForgeTheme.borderSubtle,
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
                      ? (insert.bypassed
                          ? FluxForgeTheme.textSecondary
                          : FluxForgeTheme.textPrimary)
                      : FluxForgeTheme.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFader() {
    // Convert volume (0-1.5) to fader position (0-1)
    final faderPos = (volume / 1.5).clamp(0.0, 1.0);

    return LayoutBuilder(builder: (context, constraints) {
      return GestureDetector(
        onVerticalDragUpdate: (details) {
          if (onVolumeChange == null) return;
          final height = constraints.maxHeight;
          final delta = -details.delta.dy / height;
          final newVolume = (volume + delta * 1.5).clamp(0.0, 1.5);
          onVolumeChange!(newVolume);
        },
        onDoubleTap: () => onVolumeChange?.call(1.0), // Reset to 0dB
        child: Container(
          width: 12,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(
            children: [
              // Track
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.borderSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Thumb
              Positioned(
                left: 0,
                right: 0,
                bottom: faderPos * (constraints.maxHeight - 20),
                child: Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.textPrimary,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 8,
                      height: 2,
                      color: FluxForgeTheme.bgDeepest,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// GPU-accelerated meter rendering
class _CanvasMeter extends StatelessWidget {
  final double levelL;
  final double levelR;
  final double? peakL;
  final double? peakR;
  final double height;

  const _CanvasMeter({
    required this.levelL,
    required this.levelR,
    this.peakL,
    this.peakR,
    required this.height,
  });

  double _dbToPercent(double linear) {
    if (linear <= 0.00003) return 0; // Noise floor
    final db = 20 * (math.log(linear) / math.ln10);
    if (db <= -60) return 0;
    if (db >= 6) return 1;
    return (db + 60) / 66;
  }

  Color _getColor(double db) {
    if (db >= 0) return FluxForgeTheme.errorRed;
    if (db >= -6) return FluxForgeTheme.warningOrange;
    return FluxForgeTheme.accentGreen;
  }

  @override
  Widget build(BuildContext context) {
    final pctL = _dbToPercent(levelL);
    final pctR = _dbToPercent(levelR);
    final pctPL = _dbToPercent(peakL ?? levelL);
    final pctPR = _dbToPercent(peakR ?? levelR);

    final dbL = levelL <= 0 ? -60.0 : 20 * (math.log(levelL) / math.ln10);
    final dbR = levelR <= 0 ? -60.0 : 20 * (math.log(levelR) / math.ln10);

    return SizedBox(
      width: 12,
      child: Row(
        children: [
          // Left meter
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              return Container(
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeepest,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Fill
                    FractionallySizedBox(
                      heightFactor: pctL,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _getColor(dbL),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Peak hold
                    if (pctPL > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: pctPL * constraints.maxHeight - 1,
                        child: Container(
                          height: 2,
                          color: dbL >= 0
                              ? FluxForgeTheme.errorRed
                              : FluxForgeTheme.textPrimary,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(width: 1),
          // Right meter
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              return Container(
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeepest,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Fill
                    FractionallySizedBox(
                      heightFactor: pctR,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _getColor(dbR),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Peak hold
                    if (pctPR > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: pctPR * constraints.maxHeight - 1,
                        child: Container(
                          height: 2,
                          color: dbR >= 0
                              ? FluxForgeTheme.errorRed
                              : FluxForgeTheme.textPrimary,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
