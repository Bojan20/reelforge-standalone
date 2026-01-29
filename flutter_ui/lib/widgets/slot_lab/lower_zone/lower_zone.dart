/// SlotLab Lower Zone — Collapsible Bottom Panel with Super-Tabs
///
/// Updated 2026-01-29 for super-tab architecture per SL-LZ-P0.2.
///
/// Super-tab structure:
/// - STAGES: Timeline, Event Debug
/// - EVENTS: Event List, RTPC Debugger, Composite Editor
/// - MIX: Bus Hierarchy, Aux Sends, Meters
/// - MUSIC/ALE: ALE Rules, Signals, Transitions, Stability
/// - DSP: EQ, Compressor, Limiter, Gate, Reverb
/// - BAKE: Batch Export, Validation, Package
/// - ENGINE: Profiler, Resources, Stage Ingest
/// - [+] MENU: Command Builder, Game Config, AutoSpatial, Scenarios
///
/// Features:
/// - Collapsible with smooth animation
/// - Resizable (100-500px)
/// - Super-tab + sub-tab navigation with keyboard shortcuts
/// - Auto-expand on tab switch
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../controllers/slot_lab/lower_zone_controller.dart';
import '../../../theme/fluxforge_theme.dart';
import '../../../providers/slot_lab_provider.dart';
import '../stage_trace_widget.dart';
import 'lower_zone_types.dart';
import 'lower_zone_context_bar.dart';
import 'command_builder_panel.dart';
import 'event_list_panel.dart';
import 'bus_meters_panel.dart';

// FabFilter DSP Panels
import '../../fabfilter/fabfilter_compressor_panel.dart';
import '../../fabfilter/fabfilter_limiter_panel.dart';
import '../../fabfilter/fabfilter_gate_panel.dart';
import '../../fabfilter/fabfilter_reverb_panel.dart';

// Middleware Panels
import '../../middleware/rtpc_debugger_panel.dart';
import '../../middleware/bus_hierarchy_panel.dart';
import '../../middleware/dsp_profiler_panel.dart';
import '../../middleware/resource_dashboard_panel.dart';
import '../../middleware/event_debugger_panel.dart';

// SlotLab Panels (simpler versions without required params)
import '../aux_sends_panel.dart';

// ALE Panels
import '../../ale/ale_panel.dart';
import '../../ale/signal_catalog_panel.dart';
import '../../ale/stability_config_panel.dart';

// Stage Ingest Panels
import '../../stage_ingest/stage_ingest_panel.dart';

// Spatial Panels
import '../../spatial/auto_spatial_panel.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LOWER ZONE WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Main lower zone widget for SlotLab screen with super-tab navigation
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

            // NEW: Context Bar with super-tabs + sub-tabs
            LowerZoneContextBar(
              activeSuperTab: controller.activeSuperTab,
              activeSubTabIndex: controller.activeSubTabIndex,
              onSuperTabChanged: controller.switchToSuperTab,
              onSubTabChanged: controller.switchToSubTab,
              onMenuItemSelected: controller.selectMenuItem,
              isExpanded: controller.isExpanded,
              onToggleExpanded: controller.toggle,
            ),

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
    final superConfig = getSuperTabConfig(widget.controller.activeSuperTab);

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
              ? superConfig.accentColor.withValues(alpha: 0.3)
              : Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isActive ? 60 : 40,
              height: 3,
              decoration: BoxDecoration(
                color: isActive
                    ? superConfig.accentColor
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
// CONTENT (Super-Tab Based)
// ═══════════════════════════════════════════════════════════════════════════

class _LowerZoneContent extends StatelessWidget {
  final LowerZoneController controller;

  const _LowerZoneContent({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: _buildContentForSuperTab(context),
    );
  }

  Widget _buildContentForSuperTab(BuildContext context) {
    // Handle menu panels first
    if (controller.activeMenuPanel != null) {
      return _buildMenuPanelContent(controller.activeMenuPanel!);
    }

    // Build content based on active super-tab
    switch (controller.activeSuperTab) {
      case SuperTab.stages:
        return _buildStagesContent(context);
      case SuperTab.events:
        return _buildEventsContent(context);
      case SuperTab.mix:
        return _buildMixContent(context);
      case SuperTab.musicAle:
        return _buildMusicAleContent(context);
      case SuperTab.dsp:
        return _buildDspContent(context);
      case SuperTab.bake:
        return _buildBakeContent(context);
      case SuperTab.engine:
        return _buildEngineContent(context);
      case SuperTab.menu:
        // Menu super-tab should not be directly selected
        return _buildPlaceholder('Select a panel from the [+] menu');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGES SUPER-TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStagesContent(BuildContext context) {
    final subIndex = controller.activeSubTabIndex;
    switch (subIndex) {
      case 0: // Timeline
        return _TimelineContent();
      case 1: // Event Debug
        return const EventDebuggerPanel();
      default:
        return _TimelineContent();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENTS SUPER-TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEventsContent(BuildContext context) {
    final subIndex = controller.activeSubTabIndex;
    switch (subIndex) {
      case 0: // Event List
        return const EventListPanel();
      case 1: // RTPC Debugger
        return const RtpcDebuggerPanel();
      case 2: // Composite Editor
        // TODO: Implement CompositeEditorPanel (SL-LZ-P0.3)
        return _buildPlaceholder('Composite Editor\n(Coming Soon - SL-LZ-P0.3)');
      default:
        return const EventListPanel();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIX SUPER-TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMixContent(BuildContext context) {
    final subIndex = controller.activeSubTabIndex;
    switch (subIndex) {
      case 0: // Bus Hierarchy
        return const BusHierarchyPanel();
      case 1: // Aux Sends
        return const AuxSendsPanel();
      case 2: // Meters
        return const BusMetersPanel();
      default:
        return const BusHierarchyPanel();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MUSIC/ALE SUPER-TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMusicAleContent(BuildContext context) {
    final subIndex = controller.activeSubTabIndex;
    switch (subIndex) {
      case 0: // ALE Rules
        return const AlePanel();
      case 1: // Signals
        return const SignalCatalogPanel();
      case 2: // Transitions
        // Transition editor is part of ALE panel
        return const AlePanel();
      case 3: // Stability
        return const StabilityConfigPanel();
      default:
        return const AlePanel();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DSP SUPER-TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDspContent(BuildContext context) {
    final subIndex = controller.activeSubTabIndex;
    switch (subIndex) {
      case 0: // EQ
        // TODO: Add FabFilterEQPanel when available
        return _buildPlaceholder('Pro-Q Style EQ\n(Coming Soon)');
      case 1: // Compressor
        return const FabFilterCompressorPanel(trackId: 0);
      case 2: // Limiter
        return const FabFilterLimiterPanel(trackId: 0);
      case 3: // Gate
        return const FabFilterGatePanel(trackId: 0);
      case 4: // Reverb
        return const FabFilterReverbPanel(trackId: 0);
      default:
        return const FabFilterCompressorPanel(trackId: 0);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BAKE SUPER-TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBakeContent(BuildContext context) {
    final subIndex = controller.activeSubTabIndex;
    switch (subIndex) {
      case 0: // Batch Export
        // TODO: Implement BatchExportPanel (SL-LZ-P0.4)
        return _buildPlaceholder('Batch Export\n(Coming Soon - SL-LZ-P0.4)');
      case 1: // Validation
        return _buildPlaceholder('Validation Checks\n(Coming Soon)');
      case 2: // Package
        return _buildPlaceholder('Package Builder\n(Coming Soon)');
      default:
        return _buildPlaceholder('Batch Export\n(Coming Soon - SL-LZ-P0.4)');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ENGINE SUPER-TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEngineContent(BuildContext context) {
    final subIndex = controller.activeSubTabIndex;
    switch (subIndex) {
      case 0: // Profiler
        return const DspProfilerPanel();
      case 1: // Resources
        return const ResourceDashboardPanel();
      case 2: // Stage Ingest
        return const StageIngestPanel();
      default:
        return const DspProfilerPanel();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MENU PANELS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMenuPanelContent(String menuItemId) {
    switch (menuItemId) {
      case 'commandBuilder':
        return const CommandBuilderPanel();
      case 'gameConfig':
        return _buildPlaceholder('Game Configuration\n(Coming Soon)');
      case 'autoSpatial':
        return const AutoSpatialPanel();
      case 'scenarios':
        return _buildPlaceholder('Test Scenarios\n(Coming Soon)');
      default:
        return _buildPlaceholder('Unknown Panel');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLACEHOLDER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPlaceholder(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction,
            size: 48,
            color: FluxForgeTheme.textMuted.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 14,
            ),
          ),
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
