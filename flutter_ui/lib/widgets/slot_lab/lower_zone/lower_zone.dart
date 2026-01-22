/// SlotLab Lower Zone — Collapsible Bottom Panel
///
/// Tabbed interface for:
/// - Timeline: Stage trace visualization
/// - Command Builder: Auto Event Builder
/// - Event List: Event browser
/// - Meters: Audio bus meters
///
/// Features:
/// - Collapsible with smooth animation
/// - Resizable (100-500px)
/// - Tab switching with keyboard shortcuts (1-4, `)
/// - Auto-expand on tab switch
///
/// Based on SLOTLAB_AUTO_EVENT_BUILDER_FINAL.md Section 15.6
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../controllers/slot_lab/lower_zone_controller.dart';
import '../../../theme/fluxforge_theme.dart';
import '../stage_trace_widget.dart';
import '../../../providers/slot_lab_provider.dart';
import 'command_builder_panel.dart';
import 'event_list_panel.dart';
import 'bus_meters_panel.dart';
// FabFilter DSP Panels
import '../../fabfilter/fabfilter_compressor_panel.dart';
import '../../fabfilter/fabfilter_limiter_panel.dart';
import '../../fabfilter/fabfilter_gate_panel.dart';
import '../../fabfilter/fabfilter_reverb_panel.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LOWER ZONE WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Main lower zone widget for SlotLab screen
class LowerZone extends StatelessWidget {
  const LowerZone({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LowerZoneController>(
      builder: (context, controller, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Resize handle (at top of lower zone)
            if (controller.isExpanded) _ResizeHandle(controller: controller),

            // Header: Tabs + Collapse button
            _LowerZoneHeader(controller: controller),

            // Content (animated)
            AnimatedContainer(
              duration: kLowerZoneAnimationDuration,
              height: controller.isExpanded ? controller.height : 0,
              curve: Curves.easeOutCubic,
              child: ClipRect(
                child: _LowerZoneContent(controller: controller),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RESIZE HANDLE
// ═══════════════════════════════════════════════════════════════════════════

class _ResizeHandle extends StatefulWidget {
  final LowerZoneController controller;

  const _ResizeHandle({required this.controller});

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _isHovering = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _isHovering || _isDragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onVerticalDragStart: (_) => setState(() => _isDragging = true),
        onVerticalDragUpdate: (details) {
          // Negative delta = dragging up = increase height
          widget.controller.adjustHeight(-details.delta.dy);
        },
        onVerticalDragEnd: (_) => setState(() => _isDragging = false),
        child: Container(
          height: 6,
          color: isActive
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.3)
              : Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isActive ? 60 : 40,
              height: 3,
              decoration: BoxDecoration(
                color: isActive
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════

class _LowerZoneHeader extends StatelessWidget {
  final LowerZoneController controller;

  const _LowerZoneHeader({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kLowerZoneHeaderHeight,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          top: BorderSide(
            color: FluxForgeTheme.borderSubtle,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),

          // Collapse/Expand button
          _CollapseButton(controller: controller),

          const SizedBox(width: 8),

          // Divider
          Container(
            width: 1,
            height: 20,
            color: FluxForgeTheme.borderSubtle,
          ),

          const SizedBox(width: 8),

          // Tab buttons
          for (final tab in LowerZoneTab.values) ...[
            _TabButton(
              config: kLowerZoneTabConfigs[tab]!,
              isActive: controller.isTabActive(tab),
              onTap: () => controller.switchTo(tab),
            ),
            const SizedBox(width: 4),
          ],

          const Spacer(),

          // Height indicator (when expanded)
          if (controller.isExpanded)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${controller.height.round()}px',
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COLLAPSE BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class _CollapseButton extends StatelessWidget {
  final LowerZoneController controller;

  const _CollapseButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: controller.isExpanded ? 'Collapse (`)' : 'Expand (`)',
      child: InkWell(
        onTap: controller.toggle,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: AnimatedRotation(
            duration: kLowerZoneAnimationDuration,
            turns: controller.isExpanded ? 0 : 0.5,
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class _TabButton extends StatefulWidget {
  final LowerZoneTabConfig config;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.config,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = widget.isActive || _isHovering;

    return Tooltip(
      message: '${widget.config.description} (${widget.config.shortcutKey})',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
                  : _isHovering
                      ? FluxForgeTheme.bgDeep.withValues(alpha: 0.5)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: widget.isActive
                  ? Border.all(
                      color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.config.icon,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.config.label,
                  style: TextStyle(
                    color: isHighlighted
                        ? FluxForgeTheme.textPrimary
                        : FluxForgeTheme.textSecondary,
                    fontSize: 12,
                    fontWeight:
                        widget.isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(width: 4),
                // Shortcut hint
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    widget.config.shortcutKey,
                    style: TextStyle(
                      color: FluxForgeTheme.textMuted,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTENT
// ═══════════════════════════════════════════════════════════════════════════

class _LowerZoneContent extends StatelessWidget {
  final LowerZoneController controller;

  const _LowerZoneContent({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: IndexedStack(
        index: controller.activeTab.index,
        children: [
          // Timeline - Stage Trace
          _TimelineContent(),

          // Command Builder
          const CommandBuilderPanel(),

          // Event List
          const EventListPanel(),

          // Meters - Live audio bus meters
          const BusMetersPanel(),

          // DSP Panels (FabFilter-style)
          // Compressor - Pro-C style
          const FabFilterCompressorPanel(trackId: 0),

          // Limiter - Pro-L style
          const FabFilterLimiterPanel(trackId: 0),

          // Gate - Pro-G style
          const FabFilterGatePanel(trackId: 0),

          // Reverb - Pro-R style
          const FabFilterReverbPanel(trackId: 0),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TIMELINE CONTENT (Stage Trace)
// ═══════════════════════════════════════════════════════════════════════════

class _TimelineContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Try to get SlotLabProvider, show placeholder if not available
    try {
      final provider = context.watch<SlotLabProvider>();
      return StageTraceWidget(
        provider: provider,
        height: double.infinity,
        showMiniProgress: false,
      );
    } catch (_) {
      // Provider not available
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline,
              size: 48,
              color: FluxForgeTheme.textMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'Stage Timeline',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Run a spin to see stage trace',
              style: TextStyle(
                color: FluxForgeTheme.textMuted.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
  }
}
