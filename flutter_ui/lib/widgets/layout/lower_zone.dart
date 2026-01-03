/// ReelForge Lower Zone
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
import '../../theme/reelforge_theme.dart';
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
    this.minHeight = 100,
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
        color: ReelForgeTheme.bgDeep,
        border: Border(
          top: BorderSide(
            color: ReelForgeTheme.borderSubtle,
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
            child: activeTab.content,
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
                ? ReelForgeTheme.accentBlue.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
          child: Center(
            child: Container(
              width: 40,
              height: 3,
              decoration: BoxDecoration(
                color: _isDragging
                    ? ReelForgeTheme.accentBlue
                    : ReelForgeTheme.borderMedium,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(String activeId) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Tabs
          ...widget.tabs.map((tab) => _buildTab(tab, activeId)),

          const Spacer(),

          // Collapse button
          if (widget.onToggleCollapse != null)
            IconButton(
              icon: const Icon(Icons.expand_more, size: 18),
              onPressed: widget.onToggleCollapse,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              color: ReelForgeTheme.textSecondary,
            ),
        ],
      ),
    );
  }

  Widget _buildTab(LowerZoneTab tab, String activeId) {
    final isActive = tab.id == activeId;

    return GestureDetector(
      onTap: () => widget.onTabChange?.call(tab.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            if (tab.icon != null) ...[
              Icon(tab.icon!, size: 14, color: isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 11,
                color: isActive
                    ? ReelForgeTheme.accentBlue
                    : ReelForgeTheme.textSecondary,
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
              ? ReelForgeTheme.accentBlue.withValues(alpha: 0.1)
              : ReelForgeTheme.bgMid,
          border: Border(
            left: BorderSide(
              color: selected
                  ? ReelForgeTheme.accentBlue
                  : isMaster
                      ? ReelForgeTheme.warningOrange
                      : Colors.transparent,
              width: 2,
            ),
            right: BorderSide(color: ReelForgeTheme.borderSubtle),
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
                    ? ReelForgeTheme.warningOrange.withValues(alpha: 0.2)
                    : ReelForgeTheme.bgElevated,
                border: Border(
                  bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
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
                        color: ReelForgeTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isMaster)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: ReelForgeTheme.warningOrange,
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
                        activeColor: ReelForgeTheme.accentBlue,
                        inactiveColor: ReelForgeTheme.bgDeepest,
                      ),
                    ),
                    Text(
                      _panDisplay,
                      style: ReelForgeTheme.monoSmall.copyWith(fontSize: 9),
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
                                    color: ReelForgeTheme.textSecondary,
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
                style: ReelForgeTheme.monoSmall.copyWith(
                  fontSize: 10,
                  color: volume > 1 ? ReelForgeTheme.errorRed : null,
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
                              ? ReelForgeTheme.errorRed
                              : ReelForgeTheme.bgDeepest,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: muted
                                ? ReelForgeTheme.errorRed
                                : ReelForgeTheme.borderSubtle,
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
                                  : ReelForgeTheme.textSecondary,
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
                              ? ReelForgeTheme.warningOrange
                              : ReelForgeTheme.bgDeepest,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: soloed
                                ? ReelForgeTheme.warningOrange
                                : ReelForgeTheme.borderSubtle,
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
                                  : ReelForgeTheme.textSecondary,
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
              ? ReelForgeTheme.bgElevated
              : ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: hasPlugin && !(insert?.bypassed ?? false)
                ? ReelForgeTheme.accentBlue.withValues(alpha: 0.5)
                : ReelForgeTheme.borderSubtle,
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
                color: hasPlugin && !(insert?.bypassed ?? false)
                    ? ReelForgeTheme.accentGreen
                    : ReelForgeTheme.borderSubtle,
              ),
            ),
            const SizedBox(width: 4),
            // Name
            Expanded(
              child: Text(
                hasPlugin ? insert!.name : '+',
                style: TextStyle(
                  fontSize: 8,
                  color: hasPlugin
                      ? (insert!.bypassed
                          ? ReelForgeTheme.textSecondary
                          : ReelForgeTheme.textPrimary)
                      : ReelForgeTheme.textSecondary,
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
            color: ReelForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(
            children: [
              // Track
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: ReelForgeTheme.borderSubtle,
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
                    color: ReelForgeTheme.textPrimary,
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
                      color: ReelForgeTheme.bgDeepest,
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
    if (db >= 0) return ReelForgeTheme.errorRed;
    if (db >= -6) return ReelForgeTheme.warningOrange;
    return ReelForgeTheme.accentGreen;
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
                  color: ReelForgeTheme.bgDeepest,
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
                              ? ReelForgeTheme.errorRed
                              : ReelForgeTheme.textPrimary,
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
                  color: ReelForgeTheme.bgDeepest,
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
                              ? ReelForgeTheme.errorRed
                              : ReelForgeTheme.textPrimary,
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
