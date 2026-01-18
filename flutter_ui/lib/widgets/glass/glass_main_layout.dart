/// Glass Main Layout
///
/// Liquid Glass styled main application layout that integrates:
/// - GlassAppShell (animated background)
/// - GlassControlBar (top bar)
/// - GlassInspector (right panel)
/// - GlassBrowser (left panel)
/// - LowerZoneGlass (bottom zone)
/// - GlassTransportBar (transport)

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../models/layout_models.dart';
import 'glass_app_shell.dart';
import 'glass_control_bar.dart';
import 'glass_panels.dart';
import 'glass_transport.dart';
import '../layout/lower_zone_glass.dart';

/// Glass-styled main layout wrapper
class GlassMainLayout extends StatefulWidget {
  // Editor mode
  final EditorMode editorMode;
  final ValueChanged<EditorMode>? onEditorModeChange;

  // Transport state
  final bool isPlaying;
  final bool isRecording;
  final bool loopEnabled;
  final bool metronomeEnabled;
  final double tempo;
  final TimeSignature timeSignature;
  final double currentTime;
  final TimeDisplayMode timeDisplayMode;

  // Transport callbacks
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;
  final VoidCallback? onRewind;
  final VoidCallback? onForward;
  final VoidCallback? onLoopToggle;
  final VoidCallback? onMetronomeToggle;
  final VoidCallback? onTimeDisplayModeChange;
  final ValueChanged<double>? onTempoChange;

  // Zone visibility
  final bool showLeftZone;
  final bool showRightZone;
  final bool showLowerZone;
  final VoidCallback? onToggleLeftZone;
  final VoidCallback? onToggleRightZone;
  final VoidCallback? onToggleLowerZone;

  // System info
  final double cpuUsage;
  final double memoryUsage;
  final String projectName;
  final VoidCallback? onSave;

  // Menu callbacks
  final MenuCallbacks? menuCallbacks;

  // Main content
  final Widget child;

  // Left zone content
  final Widget? leftZoneContent;
  final List<GlassBrowserItem>? browserItems;
  final String? selectedBrowserItemId;
  final ValueChanged<String>? onBrowserItemSelect;

  // Right zone content
  final Widget? rightZoneContent;
  final String? inspectorTitle;
  final List<GlassInspectorSection>? inspectorSections;

  // Lower zone
  final String? lowerZoneActiveTabId;
  final List<LowerZoneTab>? lowerZoneTabs;
  final ValueChanged<String>? onLowerZoneTabChange;
  final Widget? lowerZoneContent;

  const GlassMainLayout({
    super.key,
    this.editorMode = EditorMode.daw,
    this.onEditorModeChange,
    this.isPlaying = false,
    this.isRecording = false,
    this.loopEnabled = false,
    this.metronomeEnabled = false,
    this.tempo = 120,
    this.timeSignature = const TimeSignature(4, 4),
    this.currentTime = 0,
    this.timeDisplayMode = TimeDisplayMode.bars,
    this.onPlay,
    this.onStop,
    this.onRecord,
    this.onRewind,
    this.onForward,
    this.onLoopToggle,
    this.onMetronomeToggle,
    this.onTimeDisplayModeChange,
    this.onTempoChange,
    this.showLeftZone = true,
    this.showRightZone = true,
    this.showLowerZone = true,
    this.onToggleLeftZone,
    this.onToggleRightZone,
    this.onToggleLowerZone,
    this.cpuUsage = 0,
    this.memoryUsage = 0,
    this.projectName = 'Untitled',
    this.onSave,
    this.menuCallbacks,
    required this.child,
    this.leftZoneContent,
    this.browserItems,
    this.selectedBrowserItemId,
    this.onBrowserItemSelect,
    this.rightZoneContent,
    this.inspectorTitle,
    this.inspectorSections,
    this.lowerZoneActiveTabId,
    this.lowerZoneTabs,
    this.onLowerZoneTabChange,
    this.lowerZoneContent,
  });

  @override
  State<GlassMainLayout> createState() => _GlassMainLayoutState();
}

class _GlassMainLayoutState extends State<GlassMainLayout> {
  // Zone widths
  double _leftZoneWidth = 240;
  double _rightZoneWidth = 280;
  double _lowerZoneHeight = 200;

  // Resize state
  bool _isResizingLeft = false;
  bool _isResizingRight = false;
  bool _isResizingLower = false;

  @override
  Widget build(BuildContext context) {
    return GlassAppShell(
      child: Column(
        children: [
          // Control Bar
          GlassControlBar(
            editorMode: widget.editorMode,
            onEditorModeChange: widget.onEditorModeChange,
            isPlaying: widget.isPlaying,
            isRecording: widget.isRecording,
            loopEnabled: widget.loopEnabled,
            metronomeEnabled: widget.metronomeEnabled,
            tempo: widget.tempo,
            timeSignature: widget.timeSignature,
            currentTime: widget.currentTime,
            timeDisplayMode: widget.timeDisplayMode,
            onPlay: widget.onPlay,
            onStop: widget.onStop,
            onRecord: widget.onRecord,
            onRewind: widget.onRewind,
            onForward: widget.onForward,
            onLoopToggle: widget.onLoopToggle,
            onMetronomeToggle: widget.onMetronomeToggle,
            onTimeDisplayModeChange: widget.onTimeDisplayModeChange,
            onTempoChange: widget.onTempoChange,
            onToggleLeftZone: widget.onToggleLeftZone,
            onToggleRightZone: widget.onToggleRightZone,
            onToggleLowerZone: widget.onToggleLowerZone,
            cpuUsage: widget.cpuUsage,
            memoryUsage: widget.memoryUsage,
            projectName: widget.projectName,
            onSave: widget.onSave,
            menuCallbacks: widget.menuCallbacks,
          ),

          // Main content area
          Expanded(
            child: Row(
              children: [
                // Left Zone (Browser)
                if (widget.showLeftZone) ...[
                  SizedBox(
                    width: _leftZoneWidth,
                    child: widget.leftZoneContent ??
                        GlassBrowser(
                          title: 'Project',
                          items: widget.browserItems ?? [],
                          selectedId: widget.selectedBrowserItemId,
                          onSelect: widget.onBrowserItemSelect,
                          onClose: widget.onToggleLeftZone,
                        ),
                  ),
                  _buildResizeHandle(
                    isHorizontal: true,
                    isResizing: _isResizingLeft,
                    onDragStart: () =>
                        setState(() => _isResizingLeft = true),
                    onDragEnd: () =>
                        setState(() => _isResizingLeft = false),
                    onDrag: (delta) {
                      setState(() {
                        _leftZoneWidth =
                            (_leftZoneWidth + delta).clamp(180, 400);
                      });
                    },
                  ),
                ],

                // Center content
                Expanded(
                  child: Column(
                    children: [
                      // Main content
                      Expanded(
                        child: _GlassContentArea(child: widget.child),
                      ),

                      // Lower Zone
                      if (widget.showLowerZone) ...[
                        _buildResizeHandle(
                          isHorizontal: false,
                          isResizing: _isResizingLower,
                          onDragStart: () =>
                              setState(() => _isResizingLower = true),
                          onDragEnd: () =>
                              setState(() => _isResizingLower = false),
                          onDrag: (delta) {
                            setState(() {
                              _lowerZoneHeight =
                                  (_lowerZoneHeight - delta).clamp(150, 500);
                            });
                          },
                        ),
                        SizedBox(
                          height: _lowerZoneHeight,
                          child: widget.lowerZoneContent ??
                              LowerZoneGlass(
                                tabs: widget.lowerZoneTabs ?? [],
                                activeTabId: widget.lowerZoneActiveTabId,
                                onTabChange: widget.onLowerZoneTabChange,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Right Zone (Inspector)
                if (widget.showRightZone) ...[
                  _buildResizeHandle(
                    isHorizontal: true,
                    isResizing: _isResizingRight,
                    onDragStart: () =>
                        setState(() => _isResizingRight = true),
                    onDragEnd: () =>
                        setState(() => _isResizingRight = false),
                    onDrag: (delta) {
                      setState(() {
                        _rightZoneWidth =
                            (_rightZoneWidth - delta).clamp(200, 400);
                      });
                    },
                  ),
                  SizedBox(
                    width: _rightZoneWidth,
                    child: widget.rightZoneContent ??
                        GlassInspector(
                          title: widget.inspectorTitle ?? 'Inspector',
                          sections: widget.inspectorSections ?? [],
                          onClose: widget.onToggleRightZone,
                        ),
                  ),
                ],
              ],
            ),
          ),

          // Transport Bar (bottom)
          GlassTransportBar(
            isPlaying: widget.isPlaying,
            isRecording: widget.isRecording,
            loopEnabled: widget.loopEnabled,
            metronomeEnabled: widget.metronomeEnabled,
            tempo: widget.tempo,
            timeSigNum: widget.timeSignature.numerator,
            timeSigDenom: widget.timeSignature.denominator,
            currentTime: widget.currentTime,
            timeDisplayMode: _mapTimeDisplayMode(widget.timeDisplayMode),
            onPlay: widget.onPlay,
            onStop: widget.onStop,
            onRecord: widget.onRecord,
            onRewind: widget.onRewind,
            onForward: widget.onForward,
            onLoopToggle: widget.onLoopToggle,
            onMetronomeToggle: widget.onMetronomeToggle,
            onTimeDisplayTap: widget.onTimeDisplayModeChange,
            onTempoChange: widget.onTempoChange,
          ),
        ],
      ),
    );
  }

  GlassTimeDisplayMode _mapTimeDisplayMode(TimeDisplayMode mode) {
    switch (mode) {
      case TimeDisplayMode.bars:
        return GlassTimeDisplayMode.bars;
      case TimeDisplayMode.timecode:
        return GlassTimeDisplayMode.timecode;
      case TimeDisplayMode.samples:
        return GlassTimeDisplayMode.samples;
    }
  }

  Widget _buildResizeHandle({
    required bool isHorizontal,
    required bool isResizing,
    required VoidCallback onDragStart,
    required VoidCallback onDragEnd,
    required ValueChanged<double> onDrag,
  }) {
    return MouseRegion(
      cursor: isHorizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        onPanStart: (_) => onDragStart(),
        onPanEnd: (_) => onDragEnd(),
        onPanUpdate: (d) => onDrag(isHorizontal ? d.delta.dx : d.delta.dy),
        child: AnimatedContainer(
          duration: LiquidGlassTheme.animFast,
          width: isHorizontal ? 6 : null,
          height: isHorizontal ? null : 6,
          decoration: BoxDecoration(
            color: isResizing
                ? LiquidGlassTheme.accentBlue.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
          child: Center(
            child: Container(
              width: isHorizontal ? 2 : 40,
              height: isHorizontal ? 40 : 2,
              decoration: BoxDecoration(
                color: isResizing
                    ? LiquidGlassTheme.accentBlue
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass-styled content area with subtle border
class _GlassContentArea extends StatelessWidget {
  final Widget child;

  const _GlassContentArea({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: LiquidGlassTheme.blurLight,
            sigmaY: LiquidGlassTheme.blurLight,
          ),
          child: Container(
            color: Colors.black.withValues(alpha: 0.2),
            child: child,
          ),
        ),
      ),
    );
  }
}
