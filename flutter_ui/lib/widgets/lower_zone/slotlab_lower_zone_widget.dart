// SlotLab Lower Zone Widget
//
// Complete Lower Zone for SlotLab section with:
// - Context bar (Super-tabs + Sub-tabs)
// - Spin Control Bar (Outcome, Volatility, Timing, Grid)
// - Content panel (switches based on current tab)
// - Action strip (context-aware actions)
// - Resizable height
// - Integrated SlotLab panels (StageTrace, EventLog, BusHierarchy, Profiler)

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../services/native_file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:provider/provider.dart';

import 'slotlab_lower_zone_controller.dart';
import 'lower_zone_types.dart';
import 'lower_zone_context_bar.dart';
import 'lower_zone_action_strip.dart';
import '../../providers/slot_lab/slot_lab_coordinator.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../services/gdd_import_service.dart' show GddGridConfig;
import '../../providers/middleware_provider.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../providers/mixer_dsp_provider.dart';
import '../../src/rust/native_ffi.dart' show NativeFFI, VolatilityPreset, TimingProfileType, VoicePoolFFI;
import '../../models/slot_audio_events.dart' show SlotCompositeEvent, SlotEventLayer, sortCategoriesHierarchically, sortEventsHierarchically;
import '../../models/timeline_models.dart' show parseWaveformFromJson;
import '../../models/middleware_models.dart' show ActionType, CrossfadeCurve, CrossfadeCurveExtension;
import '../../services/audio_playback_service.dart';
import '../../services/waveform_cache_service.dart';
import '../slot_lab/stage_trace_widget.dart';
import '../slot_lab/event_log_panel.dart';
import '../slot_lab/profiler_panel.dart';
import '../slot_lab/aux_sends_panel.dart';
import '../slot_lab/slot_automation_panel.dart';
import '../fabfilter/fabfilter.dart';
import '../common/audio_waveform_picker_dialog.dart';
import 'realtime_bus_meters.dart';
import 'export_panels.dart';
import '../common/git_panel.dart';
import '../common/analytics_dashboard.dart';
import '../common/documentation_viewer.dart';
import '../../providers/git_provider.dart';
import '../slot_lab/slotlab_bus_mixer.dart';
import '../slot_lab/lower_zone/events/composite_editor_panel.dart';
import 'package:get_it/get_it.dart';
import '../middleware/event_templates_panel.dart';
import '../middleware/event_dependency_graph_panel.dart';
import '../middleware/bus_hierarchy_panel.dart';
import '../middleware/ducking_matrix_panel.dart';
import '../middleware/attenuation_curve_panel.dart';
import '../middleware/audio_signatures_panel.dart';
import '../middleware/dsp_profiler_panel.dart';
import '../middleware/preset_morph_editor_panel.dart';
import '../slot_lab/lower_zone/slotlab_logic_tab.dart';
import '../slot_lab/lower_zone/slotlab_intel_tab.dart';
import '../slot_lab/lower_zone/slotlab_monitor_tab.dart';
import '../slot_lab/lower_zone/slotlab_rtpc_tab.dart';
import '../slot_lab/lower_zone/slotlab_containers_tab.dart';
import '../slot_lab/lower_zone/slotlab_music_tab.dart';
import '../slot_lab/lower_zone/bake/macro_panel.dart';
import '../slot_lab/lower_zone/bake/macro_monitor.dart';
import '../slot_lab/lower_zone/bake/macro_report_viewer.dart';
import '../slot_lab/lower_zone/bake/macro_config_editor.dart';
import '../slot_lab/lower_zone/bake/macro_history.dart';
import '../../services/diagnostics/diagnostics_service.dart';
import '../../providers/slot_lab/slotlab_export_provider.dart';
import '../../providers/slot_lab/slotlab_notification_provider.dart';

class SlotLabLowerZoneWidget extends StatefulWidget {
  final SlotLabLowerZoneController controller;

  /// SlotLab provider for stage trace and event log
  final SlotLabProvider? slotLabProvider;

  /// Callback when Spin button is pressed
  final VoidCallback? onSpin;

  /// Callback when forced outcome is selected
  final void Function(String outcome)? onForceOutcome;

  /// Callback when audio is dropped on a stage
  final void Function(dynamic audio, String stageType)? onAudioDropped;

  /// P0.3: Callback when Pause button is pressed
  final VoidCallback? onPause;

  /// P0.3: Callback when Resume button is pressed
  final VoidCallback? onResume;

  /// P0.3: Callback when Stop button is pressed
  final VoidCallback? onStop;

  /// P14: Callback to build Ultimate Timeline content
  final Widget Function()? onBuildTimelineContent;

  /// P14: Timeline controller from parent (maintains state)
  final dynamic timelineController;

  /// Quick Switcher callback (⌘K)
  final VoidCallback? onQuickSwitcher;

  /// When true, fills all available space instead of using fixed totalHeight
  final bool isFullScreen;

  const SlotLabLowerZoneWidget({
    super.key,
    required this.controller,
    this.slotLabProvider,
    this.onSpin,
    this.onForceOutcome,
    this.onAudioDropped,
    this.onPause,
    this.onResume,
    this.onStop,
    this.onBuildTimelineContent,
    this.timelineController,
    this.onQuickSwitcher,
    this.isFullScreen = false,
  });

  @override
  State<SlotLabLowerZoneWidget> createState() => _SlotLabLowerZoneWidgetState();
}

class _SlotLabLowerZoneWidgetState extends State<SlotLabLowerZoneWidget> {
  /// Pre-computed sub-tab labels for each super-tab (for rich hover preview)
  static final _allSuperTabSubLabels = SlotLabSuperTab.values.map((st) {
    // Create a temporary state to get sub-tab labels for this super-tab
    final tempState = SlotLabLowerZoneState(superTab: st);
    return tempState.subTabLabels;
  }).toList();

  String _selectedOutcome = 'Random';

  // P1.1: Selected values now sync with SlotLabProvider
  VolatilityPreset _selectedVolatility = VolatilityPreset.medium;
  TimingProfileType _selectedTiming = TimingProfileType.normal;
  String _selectedGrid = '5×3';

  // P0.4: Stems export selection (bus IDs selected for export)
  final Set<String> _selectedStemBusIds = {'sfx', 'music', 'voice', 'master'};

  // P2.6: Multi-select layers - track last selected for Shift+click range selection
  String? _lastSelectedLayerId;

  // P2.7: Focus node for keyboard shortcuts (Ctrl+C/V)
  final FocusNode _layerListFocusNode = FocusNode();

  // P0 PERFORMANCE: Cache built tab widgets to avoid re-creating on every switch
  final Map<SlotLabSuperTab, Widget> _cachedTabs = {};
  SlotLabSuperTab? _lastSuperTab;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);

    // P1.1: Sync initial state from provider
    _syncFromProvider();
  }

  /// P1.1: Sync dropdown states from SlotLabProvider
  void _syncFromProvider() {
    final provider = widget.slotLabProvider ?? _tryGetSlotLabProvider();
    if (provider != null) {
      _selectedVolatility = provider.volatilityPreset;
      _selectedTiming = provider.timingProfile;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _layerListFocusNode.dispose();
    _tlScrollController.dispose();
    super.dispose();
  }

  /// P2.7: Handle keyboard shortcuts for layer list (Ctrl+C/V, Delete)
  KeyEventResult _handleLayerListKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // EditableText guard — suppress shortcuts during text editing (CLAUDE.md)
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus.context != null) {
      final editable = primaryFocus.context!.findAncestorWidgetOfExactType<EditableText>();
      if (editable != null) return KeyEventResult.ignored;
    }

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    final middleware = context.read<MiddlewareProvider>();
    final selectedEvent = middleware.selectedCompositeEvent;
    if (selectedEvent == null) return KeyEventResult.ignored;

    // Ctrl+C: Copy selected layers
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (middleware.hasMultipleLayersSelected) {
        middleware.copySelectedLayers(selectedEvent.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied ${middleware.selectedLayerIds.length} layers'),
            duration: const Duration(seconds: 1),
          ),
        );
      } else if (middleware.selectedLayerId != null) {
        middleware.copyLayer(selectedEvent.id, middleware.selectedLayerId!);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied layer'), duration: Duration(seconds: 1)),
        );
      }
      return KeyEventResult.handled;
    }

    // Ctrl+V: Paste layers
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (middleware.hasLayersInClipboard) {
        final pasted = middleware.pasteSelectedLayers(selectedEvent.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pasted ${pasted.length} layers'),
            duration: const Duration(seconds: 1),
          ),
        );
      } else if (middleware.hasLayerInClipboard) {
        middleware.pasteLayer(selectedEvent.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pasted layer'), duration: Duration(seconds: 1)),
        );
      }
      return KeyEventResult.handled;
    }

    // Delete/Backspace: Delete selected layers
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (middleware.hasMultipleLayersSelected) {
        middleware.deleteSelectedLayers(selectedEvent.id);
      } else if (middleware.selectedLayerId != null) {
        middleware.removeLayerFromEvent(selectedEvent.id, middleware.selectedLayerId!);
      }
      return KeyEventResult.handled;
    }

    // Ctrl+A: Select all layers
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyA) {
      for (final layer in selectedEvent.layers) {
        middleware.toggleLayerSelection(layer.id);
      }
      return KeyEventResult.handled;
    }

    // Escape: Clear selection
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      middleware.clearLayerSelection();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _onControllerChanged() {
    // P0 PERFORMANCE: Invalidate cached tab when sub-tab changes
    final currentTab = widget.controller.superTab;
    if (_lastSuperTab == currentTab) {
      // Sub-tab or height changed — only invalidate current tab cache
      _cachedTabs.remove(currentTab);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // P0 FIX: When collapsed, total height = 4 (resize) + 32 (context bar) = 36px
    final isCollapsed = !widget.controller.isExpanded;
    final totalHeight = widget.controller.totalHeight;

    final content = Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Main content (fills entire height)
        Container(
          decoration: const BoxDecoration(color: LowerZoneColors.bgDeep),
          clipBehavior: Clip.hardEdge,
          child: Column(
            mainAxisSize: widget.isFullScreen ? MainAxisSize.max : MainAxisSize.min,
            children: [
              // Resize handle (fixed: 4px) — hidden in fullscreen
              if (!widget.isFullScreen) _buildResizeHandle(),
              // Context bar (dynamic: 60px expanded, 32px collapsed) with shortcuts help button
              SizedBox(
                height: isCollapsed ? kContextBarCollapsedHeight : kContextBarHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: ListenableBuilder(
                        listenable: DiagnosticsService.instance,
                        builder: (context, _) {
                          final findingsCount = DiagnosticsService.instance.liveFindings.length;
                          return LowerZoneContextBar(
                            superTabLabels: SlotLabSuperTab.values.map((t) => t.label).toList(),
                            superTabIcons: SlotLabSuperTab.values.map((t) => t.icon).toList(),
                            superTabColors: SlotLabSuperTab.values.map((t) => t.color).toList(),
                            superTabTooltips: SlotLabSuperTab.values.map((t) => t.tooltip).toList(),
                            selectedSuperTab: widget.controller.superTab.index,
                            subTabLabels: widget.controller.subTabLabels,
                            selectedSubTab: widget.controller.currentSubTabIndex,
                            accentColor: widget.controller.accentColor,
                            isExpanded: widget.controller.isExpanded,
                            onSuperTabSelected: widget.controller.setSuperTabIndex,
                            onSubTabSelected: widget.controller.setSubTabIndex,
                            onToggle: widget.controller.toggle,
                            // Visual group separators: STAGES | EVENTS+MIX+DSP | RTPC+CONTAINERS+MUSIC | LOGIC+INTEL+MONITOR | BAKE
                            superTabGroupBreaks: const [0, 3, 6, 9],
                            // Diagnostics findings badge on MONITOR tab (index 9)
                            superTabBadges: findingsCount > 0 ? {SlotLabSuperTab.monitor.index: findingsCount} : null,
                            // Sub-tab group separators per super-tab
                            subTabGroupBreaks: widget.controller.subTabGroupBreaks,
                            subTabTooltips: widget.controller.subTabTooltips,
                            breadcrumbCategory: widget.controller.superTab.category,
                            onQuickSwitcher: widget.onQuickSwitcher,
                            superTabSubLabels: _allSuperTabSubLabels,
                          );
                        },
                      ),
                    ),
                    // P0.3: Keyboard shortcuts help button (adapts to context bar height)
                    _buildShortcutsHelpButton(),
                  ],
                ),
              ),
              // Content panel (only when expanded)
              if (!isCollapsed)
                Expanded(
                  child: Column(
                    children: [
                      // Spin Control Bar (fixed: 32px)
                      _buildSpinControlBar(),
                      // Content panel (flexible)
                      Expanded(
                        child: ClipRect(child: _buildContentPanel()),
                      ),
                      // Action strip (fixed: 36px)
                      _buildActionStrip(),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Top border line - positioned at top, doesn't affect layout
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 1,
            color: LowerZoneColors.border,
          ),
        ),
      ],
    );

    // In fullscreen mode, fill all available space
    if (widget.isFullScreen) {
      return content;
    }

    // Normal mode: fixed height with animation
    return SizedBox(
      height: totalHeight,
      child: content,
    );
  }

  Widget _buildResizeHandle() {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        widget.controller.adjustHeight(-details.delta.dy);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: Container(
          height: 4,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 40,
              height: 3,
              decoration: BoxDecoration(
                color: LowerZoneColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// P0.3: Keyboard shortcuts help button (adapts to collapsed/expanded state)
  Widget _buildShortcutsHelpButton() {
    // Smaller button when collapsed to fit in 32px height
    final isCollapsed = !widget.controller.isExpanded;
    final buttonSize = isCollapsed ? 22.0 : 26.0;
    final fontSize = isCollapsed ? 11.0 : 13.0;

    // Use Align to center vertically within the row instead of margin
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Tooltip(
          message: 'Keyboard Shortcuts (?)',
          child: GestureDetector(
            onTap: () => KeyboardShortcutsOverlay.show(context),
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                color: LowerZoneColors.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: LowerZoneColors.border),
              ),
              child: Center(
                child: Text(
                  '?',
                  style: TextStyle(
                    color: LowerZoneColors.textSecondary,
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Spin Control Bar — always visible in SlotLab
  /// P1.1: Dropdowns now connected to SlotLabProvider
  Widget _buildSpinControlBar() {
    final provider = widget.slotLabProvider ?? _tryGetSlotLabProvider();

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: LowerZoneColors.bgMid,
        border: Border(
          bottom: BorderSide(color: LowerZoneColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Text(
            'SPIN:',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: LowerZoneColors.slotLabAccent,
            ),
          ),
          const SizedBox(width: 8),
          // Outcome dropdown (force outcome)
          _buildSpinDropdown('Outcome', _selectedOutcome,
              ['Random', 'SmallWin', 'BigWin', 'FreeSpins', 'Jackpot', 'Lose'],
              (v) => setState(() { _selectedOutcome = v; widget.onForceOutcome?.call(v); })),
          // P1.1: Volatility dropdown — connected to provider
          _buildVolatilityDropdown(provider),
          // P1.1: Timing dropdown — connected to provider
          _buildTimingDropdown(provider),
          // Grid dropdown — connected to SlotLabProjectProvider
          _buildGridDropdown(),
          const Spacer(),
          // Spin button
          _buildSpinButton(),
          const SizedBox(width: 8),
          // P0.3: Play/Pause/Stop controls — Selector rebuilds only on preview state change
          Selector<MiddlewareProvider, bool>(
            selector: (_, mw) => mw.isPreviewingEvent,
            builder: (context, _, child) => _buildPlaybackControls(),
          ),
        ],
      ),
    );
  }

  /// P1.1: Volatility dropdown connected to SlotLabProvider
  Widget _buildVolatilityDropdown(SlotLabProvider? provider) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: provider != null
              ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.1)
              : LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: provider != null ? LowerZoneColors.slotLabAccent : LowerZoneColors.border,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<VolatilityPreset>(
            value: _selectedVolatility,
            dropdownColor: LowerZoneColors.bgDeep,
            isDense: true,
            icon: Icon(Icons.arrow_drop_down, size: 14, color: LowerZoneColors.textMuted),
            items: VolatilityPreset.values.map((v) => DropdownMenuItem(
              value: v,
              child: Text(
                v.name[0].toUpperCase() + v.name.substring(1), // Capitalize
                style: const TextStyle(fontSize: 10),
              ),
            )).toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedVolatility = v);
                provider?.setVolatilityPreset(v);
              }
            },
            style: TextStyle(
              fontSize: 10,
              color: LowerZoneColors.slotLabAccent,
            ),
          ),
        ),
      ),
    );
  }

  /// P1.1: Timing profile dropdown connected to SlotLabProvider
  Widget _buildTimingDropdown(SlotLabProvider? provider) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: provider != null
              ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.1)
              : LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: provider != null ? LowerZoneColors.slotLabAccent : LowerZoneColors.border,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<TimingProfileType>(
            value: _selectedTiming,
            dropdownColor: LowerZoneColors.bgDeep,
            isDense: true,
            icon: Icon(Icons.arrow_drop_down, size: 14, color: LowerZoneColors.textMuted),
            items: TimingProfileType.values.map((t) => DropdownMenuItem(
              value: t,
              child: Text(
                t.name[0].toUpperCase() + t.name.substring(1), // Capitalize
                style: const TextStyle(fontSize: 10),
              ),
            )).toList(),
            onChanged: (t) {
              if (t != null) {
                setState(() => _selectedTiming = t);
                provider?.setTimingProfile(t);
              }
            },
            style: TextStyle(
              fontSize: 10,
              color: LowerZoneColors.slotLabAccent,
            ),
          ),
        ),
      ),
    );
  }

  /// Grid dropdown — connected to SlotLabProjectProvider
  Widget _buildGridDropdown() {
    final projectProvider = context.read<SlotLabProjectProvider>();
    final gridConfig = projectProvider.gridConfig;
    // Derive current label from provider state
    final cols = gridConfig?.columns ?? 5;
    final rows = gridConfig?.rows ?? 3;
    final currentLabel = '${cols}×$rows';
    const gridOptions = ['5×3', '5×4', '6×4', '3×3', '4×5'];
    // Ensure current value is in options
    final displayValue = gridOptions.contains(currentLabel) ? currentLabel : gridOptions.first;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: LowerZoneColors.slotLabAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: LowerZoneColors.slotLabAccent),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: displayValue,
            dropdownColor: LowerZoneColors.bgDeep,
            isDense: true,
            icon: Icon(Icons.arrow_drop_down, size: 14, color: LowerZoneColors.textMuted),
            items: gridOptions.map((o) => DropdownMenuItem(
              value: o,
              child: Text(o, style: const TextStyle(fontSize: 10)),
            )).toList(),
            onChanged: (v) {
              if (v != null) {
                final parts = v.split('×');
                final newCols = int.tryParse(parts[0]) ?? 5;
                final newRows = int.tryParse(parts[1]) ?? 3;
                projectProvider.setGridConfig(GddGridConfig(
                  columns: newCols,
                  rows: newRows,
                  mechanic: gridConfig?.mechanic ?? 'ways',
                ));
                setState(() => _selectedGrid = v);
              }
            },
            style: TextStyle(
              fontSize: 10,
              color: LowerZoneColors.slotLabAccent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpinDropdown(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: LowerZoneColors.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            dropdownColor: LowerZoneColors.bgDeep,
            isDense: true,
            icon: Icon(Icons.arrow_drop_down, size: 14, color: LowerZoneColors.textMuted),
            items: options.map((o) => DropdownMenuItem(
              value: o,
              child: Text(o, style: const TextStyle(fontSize: 10)),
            )).toList(),
            onChanged: (v) => v != null ? onChanged(v) : null,
            style: TextStyle(
              fontSize: 10,
              color: LowerZoneColors.slotLabAccent,
            ),
          ),
        ),
      ),
    );
  }

  /// Reusable empty state for context-dependent / inactive sub-tabs
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LowerZoneColors.textTertiary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: LowerZoneColors.textTertiary.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: LowerZoneColors.textTertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: LowerZoneColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: LowerZoneColors.textTertiary, fontSize: 10),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: LowerZoneColors.slotLabAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.slotLabAccent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(
                      color: LowerZoneColors.slotLabAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
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

  Widget _buildSpinButton() {
    return GestureDetector(
      onTap: widget.onSpin,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: LowerZoneColors.slotLabAccent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.slotLabAccent),
        ),
        child: Row(
          // mainAxisSize removed — fills Flexible parent
          children: [
            Icon(Icons.casino, size: 14, color: LowerZoneColors.slotLabAccent),
            const SizedBox(width: 4),
            Text(
              'Spin',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: LowerZoneColors.slotLabAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// P0.3: Professional Play/Pause/Stop controls with state awareness
  /// Also supports playing selected middleware event when stages are idle
  Widget _buildPlaybackControls() {
    final provider = widget.slotLabProvider ?? _tryGetSlotLabProvider();
    if (provider == null) {
      return _buildPauseButtonDisabled();
    }

    final isStagesPlaying = provider.isPlayingStages;
    final isPaused = provider.isPaused;

    // Check if a middleware event preview is active
    final middleware = _tryGetMiddlewareProvider();
    final isEventPreviewing = middleware?.isPreviewingEvent ?? false;
    final selectedEvent = middleware?.selectedCompositeEvent;
    final hasSelectedEvent = selectedEvent != null;

    // Combined playing state: either stages or event preview
    final isPlaying = isStagesPlaying || isEventPreviewing;

    return Row(
      // mainAxisSize removed — fills Flexible parent
      children: [
        // Play/Pause toggle button
        Tooltip(
          message: isPaused
              ? 'Resume (Space)'
              : isStagesPlaying
                  ? 'Pause (Space)'
                  : isEventPreviewing
                      ? 'Stop Preview (Space)'
                      : hasSelectedEvent
                          ? 'Play "${selectedEvent.name}" (Space)'
                          : 'No event selected',
          child: GestureDetector(
            onTap: () {
              if (isPaused) {
                widget.onResume?.call();
              } else if (isStagesPlaying) {
                widget.onPause?.call();
              } else if (isEventPreviewing) {
                // Stop current event preview
                middleware?.stopPreviewEvent();
              } else if (hasSelectedEvent) {
                // Play selected event immediately
                middleware?.togglePreviewEvent(selectedEvent.id);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isPlaying || isPaused
                    ? (isPaused
                        ? LowerZoneColors.warning.withValues(alpha: 0.2)
                        : isEventPreviewing
                            ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.2)
                            : LowerZoneColors.success.withValues(alpha: 0.2))
                    : hasSelectedEvent
                        ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.08)
                        : LowerZoneColors.bgSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isPlaying || isPaused
                      ? (isPaused
                          ? LowerZoneColors.warning
                          : isEventPreviewing
                              ? LowerZoneColors.slotLabAccent
                              : LowerZoneColors.success)
                      : hasSelectedEvent
                          ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.4)
                          : LowerZoneColors.border,
                ),
              ),
              child: Row(
                // mainAxisSize removed — fills Flexible parent
                children: [
                  Icon(
                    isEventPreviewing
                        ? Icons.stop
                        : isPaused || !isPlaying
                            ? Icons.play_arrow
                            : Icons.pause,
                    size: 14,
                    color: isPlaying || isPaused
                        ? (isPaused
                            ? LowerZoneColors.warning
                            : isEventPreviewing
                                ? LowerZoneColors.slotLabAccent
                                : LowerZoneColors.success)
                        : hasSelectedEvent
                            ? LowerZoneColors.slotLabAccent
                            : LowerZoneColors.textMuted,
                  ),
                  if (isPaused) ...[
                    const SizedBox(width: 2),
                    Text(
                      'PAUSED',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: LowerZoneColors.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Stop button
        Tooltip(
          message: 'Stop (Esc)',
          child: GestureDetector(
            onTap: isPlaying || isPaused
                ? () {
                    if (isEventPreviewing) {
                      middleware?.stopPreviewEvent();
                    }
                    if (isStagesPlaying || isPaused) {
                      widget.onStop?.call();
                    }
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isPlaying || isPaused
                    ? LowerZoneColors.error.withValues(alpha: 0.1)
                    : LowerZoneColors.bgSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isPlaying || isPaused
                      ? LowerZoneColors.error.withValues(alpha: 0.5)
                      : LowerZoneColors.border,
                ),
              ),
              child: Icon(
                Icons.stop,
                size: 14,
                color: isPlaying || isPaused
                    ? LowerZoneColors.error
                    : LowerZoneColors.textMuted,
              ),
            ),
          ),
        ),
        // Stage progress indicator
        if (isPlaying && !isPaused) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgDeepest,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '${provider.currentStageIndex + 1}/${provider.lastStages.length}',
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: LowerZoneColors.success,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Disabled pause button when provider is not available
  Widget _buildPauseButtonDisabled() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Icon(Icons.pause, size: 14, color: LowerZoneColors.textMuted),
    );
  }

  Widget _buildContentPanel() {
    return Container(
      color: LowerZoneColors.bgDeep,
      child: _getContentForCurrentTab(),
    );
  }

  Widget _getContentForCurrentTab() {
    final tab = widget.controller.superTab;
    // P0 PERFORMANCE: Invalidate cache when switching tabs to force fresh sub-tab state,
    // but keep previously visited tabs cached for instant back-navigation
    if (_lastSuperTab != tab) {
      // Invalidate the NEW tab so it picks up current sub-tab state
      _cachedTabs.remove(tab);
      _lastSuperTab = tab;
    }
    return _cachedTabs.putIfAbsent(tab, () => _buildTabContent(tab));
  }

  Widget _buildTabContent(SlotLabSuperTab tab) {
    return switch (tab) {
      SlotLabSuperTab.stages => _buildStagesContent(),
      SlotLabSuperTab.events => _buildEventsContent(),
      SlotLabSuperTab.mix => _buildMixContent(),
      SlotLabSuperTab.dsp => _buildDspContent(),
      SlotLabSuperTab.rtpc => SlotLabRtpcTabContent(subTab: widget.controller.state.rtpcSubTab),
      SlotLabSuperTab.containers => SlotLabContainersTabContent(subTab: widget.controller.state.containersSubTab),
      SlotLabSuperTab.music => SlotLabMusicTabContent(subTab: widget.controller.state.musicSubTab),
      SlotLabSuperTab.bake => _buildBakeContent(),
      SlotLabSuperTab.logic => SlotLabLogicTabContent(subTab: widget.controller.state.logicSubTab),
      SlotLabSuperTab.intel => SlotLabIntelTabContent(subTab: widget.controller.state.intelSubTab),
      SlotLabSuperTab.monitor => SlotLabMonitorTabContent(subTab: widget.controller.state.monitorSubTab),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGES CONTENT — Integrated panels
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStagesContent() {
    final subTab = widget.controller.state.stagesSubTab;
    return switch (subTab) {
      SlotLabStagesSubTab.trace => _buildTracePanel(),
      SlotLabStagesSubTab.timeline => _buildTimelinePanel(),
      SlotLabStagesSubTab.timing => _buildProfilerPanel(),
      SlotLabStagesSubTab.layerTimeline => _buildEmptyState(
        icon: Icons.layers,
        title: 'Layer Timeline',
        subtitle: 'Start a spin to see layer-by-layer audio playback timeline',
        actionLabel: 'Spin',
        onAction: widget.onSpin,
      ),
    };
  }

  Widget _buildTracePanel() {
    // Try to get SlotLabProvider from widget or context
    final provider = widget.slotLabProvider ?? _tryGetSlotLabProvider();
    if (provider == null) {
      return _buildNoProviderPanel('Stage Trace', Icons.timeline, 'SlotLabProvider');
    }
    // Use LayoutBuilder to get available height
    return LayoutBuilder(
      builder: (context, constraints) => StageTraceWidget(
        provider: provider,
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 200,
        showMiniProgress: true,
        onAudioDropped: widget.onAudioDropped,
      ),
    );
  }

  Widget _buildTimelinePanel() {
    // Event-Layer Timeline — shows events with audio layers as tracks
    return _buildEventLayerTimeline();
  }

  Widget _buildProfilerPanel() {
    return LayoutBuilder(
      builder: (context, constraints) => ProfilerPanel(
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 250,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENTS CONTENT — Integrated panels
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEventsContent() {
    final subTab = widget.controller.state.eventsSubTab;
    return switch (subTab) {
      SlotLabEventsSubTab.folder => _buildFolderPanel(),
      SlotLabEventsSubTab.editor => _buildEditorPanel(),
      SlotLabEventsSubTab.layers => _buildEventLogPanel(),
      SlotLabEventsSubTab.pool => _buildPoolPanel(),
      SlotLabEventsSubTab.auto => _buildAutomationPanel(),
      SlotLabEventsSubTab.templates => const EventTemplatesPanel(),
      SlotLabEventsSubTab.depGraph => _buildDepGraphPanel(),
    };
  }

  Widget _buildFolderPanel() => _buildCompactEventFolder();
  Widget _buildEditorPanel() => const CompositeEditorPanel();

  Widget _buildDepGraphPanel() {
    return Selector<MiddlewareProvider, List<SlotCompositeEvent>>(
      selector: (_, mw) => mw.compositeEvents,
      shouldRebuild: (prev, next) => prev.length != next.length || !identical(prev, next),
      builder: (context, events, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return EventDependencyGraphPanel(
              events: events,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
            );
          },
        );
      },
    );
  }

  Widget _buildEventLogPanel() {
    // Event Log requires both providers
    final slotLabProvider = widget.slotLabProvider ?? _tryGetSlotLabProvider();
    final middlewareProvider = _tryGetMiddlewareProvider();
    if (slotLabProvider == null || middlewareProvider == null) {
      return _buildNoProviderPanel('Event Log', Icons.list_alt, 'SlotLab/Middleware');
    }
    return LayoutBuilder(
      builder: (context, constraints) => EventLogPanel(
        slotLabProvider: slotLabProvider,
        middlewareProvider: middlewareProvider,
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 250,
      ),
    );
  }

  Widget _buildPoolPanel() => _buildCompactVoicePool();

  /// Automation panel for batch event creation
  Widget _buildAutomationPanel() {
    final middlewareProvider = _tryGetMiddlewareProvider();
    return SlotAutomationPanel(
      onEventsGenerated: middlewareProvider != null
          ? (events) {
              // Create events in middleware from automation specs
              for (final spec in events) {
                if (spec.audioPath.isEmpty && spec.actionType != ActionType.stop) continue;

                // Create composite event with auto-generated name
                final event = middlewareProvider.createCompositeEvent(
                  name: spec.eventId,
                  category: spec.bus,
                );

                // Add trigger stage
                if (spec.stage.isNotEmpty) {
                  middlewareProvider.addTriggerStage(event.id, spec.stage);
                }

                // Add audio layer (if not a stop-only event)
                if (spec.audioPath.isNotEmpty) {
                  final fileName = spec.audioPath.split('/').last;
                  middlewareProvider.addLayerToEvent(
                    event.id,
                    audioPath: spec.audioPath,
                    name: fileName,
                  );

                  // Update layer with volume/pan via updateEventLayer
                  final addedLayer = middlewareProvider.compositeEvents
                      .where((e) => e.id == event.id)
                      .firstOrNull
                      ?.layers
                      .lastOrNull;
                  if (addedLayer != null) {
                    middlewareProvider.updateEventLayer(
                      event.id,
                      addedLayer.copyWith(
                        volume: spec.volume,
                        pan: spec.pan,
                      ),
                    );
                  }
                }
              }
            }
          : null,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIX CONTENT — Integrated panels
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMixContent() {
    final subTab = widget.controller.state.mixSubTab;
    return switch (subTab) {
      SlotLabMixSubTab.buses => const SlotLabBusMixer(),
      SlotLabMixSubTab.sends => LayoutBuilder(
        builder: (context, constraints) => AuxSendsPanel(
          height: constraints.maxHeight.isFinite ? constraints.maxHeight : 250,
        ),
      ),
      SlotLabMixSubTab.pan => _buildPanPanel(),
      SlotLabMixSubTab.meter => _buildMeterPanel(),
      SlotLabMixSubTab.hierarchy => const BusHierarchyPanel(),
      SlotLabMixSubTab.ducking => const DuckingMatrixPanel(),
    };
  }

  Widget _buildPanPanel() => _buildCompactPanPanel();

  /// P1.4: Real-time bus meters with FFI integration
  Widget _buildMeterPanel() => const RealTimeBusMeters();

  // ═══════════════════════════════════════════════════════════════════════════
  // DSP CONTENT — FabFilter Integration
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDspContent() {
    final subTab = widget.controller.state.dspSubTab;
    return switch (subTab) {
      SlotLabDspSubTab.chain => _buildChainPanel(),
      SlotLabDspSubTab.eq => _buildFabFilterEqPanel(),
      SlotLabDspSubTab.comp => _buildFabFilterCompressorPanel(),
      SlotLabDspSubTab.reverb => _buildFabFilterReverbPanel(),
      SlotLabDspSubTab.gate => _buildFabFilterGatePanel(),
      SlotLabDspSubTab.limiter => _buildFabFilterLimiterPanel(),
      SlotLabDspSubTab.attenuation => const AttenuationCurvePanel(),
      SlotLabDspSubTab.signatures => const AudioSignaturesPanel(),
      SlotLabDspSubTab.dspProfiler => const DspProfilerPanel(),
      SlotLabDspSubTab.layerDsp => _buildEmptyState(
        icon: Icons.tune,
        title: 'Layer DSP',
        subtitle: 'Select an event layer in the Inspector to edit its DSP chain',
      ),
      SlotLabDspSubTab.presetMorph => const PresetMorphEditorPanel(),
      SlotLabDspSubTab.spatial => _buildEmptyState(
        icon: Icons.surround_sound,
        title: 'Spatial Audio',
        subtitle: 'Select an event layer in the Inspector to design spatial positioning',
      ),
    };
  }

  Widget _buildChainPanel() => _buildCompactDspChain();

  /// FF-Q EQ Panel
  Widget _buildFabFilterEqPanel() {
    return const FabFilterEqPanel(trackId: 0);
  }

  /// FF-C Compressor Panel
  Widget _buildFabFilterCompressorPanel() {
    return const FabFilterCompressorPanel(trackId: 0);
  }

  /// FF-R Reverb Panel
  Widget _buildFabFilterReverbPanel() {
    return const FabFilterReverbPanel(trackId: 0);
  }

  /// FF-G Gate Panel
  Widget _buildFabFilterGatePanel() {
    return const FabFilterGatePanel(trackId: 0);
  }

  /// FF-L Limiter Panel
  Widget _buildFabFilterLimiterPanel() {
    return const FabFilterLimiterPanel(trackId: 0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BAKE CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBakeContent() {
    final subTab = widget.controller.state.bakeSubTab;
    return switch (subTab) {
      SlotLabBakeSubTab.export => _buildExportPanel(),
      SlotLabBakeSubTab.stems => _buildStemsPanel(),
      SlotLabBakeSubTab.variations => _buildVariationsPanel(),
      SlotLabBakeSubTab.package => _buildPackagePanel(),
      SlotLabBakeSubTab.git => _buildGitPanel(),
      SlotLabBakeSubTab.analytics => _buildAnalyticsPanel(),
      SlotLabBakeSubTab.docs => _buildDocsPanel(),
      SlotLabBakeSubTab.macro => const MacroPanel(),
      SlotLabBakeSubTab.macroMon => const MacroMonitor(),
      SlotLabBakeSubTab.macroReport => const MacroReportViewer(),
      SlotLabBakeSubTab.macroConfig => const MacroConfigEditor(),
      SlotLabBakeSubTab.macroHistory => const MacroHistory(),
    };
  }

  /// P2.1: Functional batch export panel for SlotLab events
  Widget _buildExportPanel() => const SlotLabBatchExportPanel();

  Widget _buildStemsPanel() => _buildCompactStemsPanel();
  Widget _buildVariationsPanel() => _buildCompactVariationsPanel();
  Widget _buildPackagePanel() => _buildCompactPackagePanel();

  /// P3-05: Git version control panel
  Widget _buildGitPanel() {
    return Consumer<SlotLabProjectProvider>(
      builder: (context, projectProvider, _) {
        final projectPath = projectProvider.projectPath;

        if (projectPath == null || projectPath.isEmpty) {
          return _buildNoProjectPanel();
        }

        // Initialize GitProvider with project path
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!GitProvider.instance.isInitialized ||
              GitProvider.instance.repoPath != projectPath) {
            GitProvider.instance.init(projectPath);
          }
        });

        return ListenableBuilder(
          listenable: GitProvider.instance,
          builder: (context, _) {
            final state = GitProvider.instance.state;

            if (state.isLoading && !state.isRepo) {
              return const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: LowerZoneColors.success,
                ),
              );
            }

            if (!state.isRepo) {
              return _buildInitRepoPanel(projectPath);
            }

            return GitPanel(
              repoPath: projectPath,
            );
          },
        );
      },
    );
  }

  /// P3-07: Analytics dashboard panel
  Widget _buildAnalyticsPanel() {
    return const AnalyticsDashboard();
  }

  /// P3-10: Documentation generator panel
  Widget _buildDocsPanel() {
    return const DocumentationViewer();
  }

  /// Panel shown when no project is loaded
  Widget _buildNoProjectPanel() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 48,
            color: Colors.white24,
          ),
          const SizedBox(height: 12),
          Text(
            'No Project Loaded',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Save your project to enable version control',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// Panel to initialize a new git repository
  Widget _buildInitRepoPanel(String projectPath) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.source_outlined,
            size: 48,
            color: Colors.white24,
          ),
          const SizedBox(height: 12),
          Text(
            'No Git Repository',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Initialize a repository to track changes',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              final success = await GitProvider.instance.initRepo();
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: LowerZoneColors.success),
                        SizedBox(width: 8),
                        Text('Git repository initialized'),
                      ],
                    ),
                    backgroundColor: LowerZoneColors.bgMid,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Initialize Repository'),
            style: ElevatedButton.styleFrom(
              backgroundColor: LowerZoneColors.success.withValues(alpha: 0.2),
              foregroundColor: LowerZoneColors.success,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  SlotLabProvider? _tryGetSlotLabProvider() {
    try {
      return context.read<SlotLabProvider>();
    } catch (_) {
      return null;
    }
  }

  MiddlewareProvider? _tryGetMiddlewareProvider() {
    try {
      return context.read<MiddlewareProvider>();
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPACT PANEL IMPLEMENTATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPanelHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: LowerZoneColors.slotLabAccent),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.slotLabAccent,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT-LAYER TIMELINE — DAW-style waveform view with unified scroll
  // ═══════════════════════════════════════════════════════════════════════════

  static const double _kTlTrackHeight = 56.0;
  static const double _kTlHeaderHeight = 32.0;
  static const double _kTlLabelWidth = 120.0;
  static const double _kTlRulerHeight = 20.0;

  String? _tlSelectedEventId;
  String? _tlSelectedLayerId;
  double _tlPixelsPerSecond = 100.0;
  String? _tlDraggingLayerId;
  final ScrollController _tlScrollController = ScrollController();
  // Waveform cache: layerId → waveform peaks (Float32List for 50% memory savings)
  final Map<String, Float32List> _tlWaveformCache = {};
  // Duration cache: layerId → seconds
  final Map<String, double> _tlDurationCache = {};

  /// Cached event structure fingerprint to skip unnecessary timeline rebuilds
  int _tlLastEventFingerprint = 0;

  Widget _buildEventLayerTimeline() {
    return Selector<MiddlewareProvider, List<SlotCompositeEvent>>(
      selector: (_, mw) => mw.compositeEvents,
      shouldRebuild: (prev, next) {
        // Only rebuild when composite events actually changed
        if (prev.length != next.length) return true;
        for (int i = 0; i < prev.length; i++) {
          if (prev[i].id != next[i].id ||
              prev[i].layers.length != next[i].layers.length ||
              prev[i].modifiedAt != next[i].modifiedAt) {
            return true;
          }
        }
        return false;
      },
      builder: (context, events, _) {
        final mw = context.read<MiddlewareProvider>();
        if (events.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.view_timeline, size: 32, color: LowerZoneColors.textMuted),
                const SizedBox(height: 8),
                Text('No events yet',
                  style: TextStyle(fontSize: 12, color: LowerZoneColors.textMuted)),
                const SizedBox(height: 4),
                Text('Drop audio on the slot machine to create events',
                  style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted.withValues(alpha: 0.6))),
              ],
            ),
          );
        }

        // Sync: populate from memory cache; schedule cold loads outside build
        _syncTlWaveformsFromCache(events);

        final totalRows = _countTotalRows(events);

        // Calculate total timeline duration across all events
        double maxEndSeconds = 2.0;
        for (final event in events) {
          for (final layer in event.layers) {
            final offsetSec = layer.offsetMs / 1000.0;
            final dur = _tlDurationCache[layer.id] ?? (layer.durationSeconds ?? 1.0);
            final endSec = offsetSec + dur;
            if (endSec > maxEndSeconds) maxEndSeconds = endSec;
          }
          final eventDur = event.totalDurationSeconds;
          if (eventDur > maxEndSeconds) maxEndSeconds = eventDur;
        }
        maxEndSeconds += 0.5;

        final totalWidth = maxEndSeconds * _tlPixelsPerSecond;

        return Column(
          children: [
            // Toolbar
            _buildTlToolbar(events),
            // Timeline area: fixed labels (left) + unified scroll (right)
            Expanded(
              child: Container(
                color: LowerZoneColors.bgDeepest,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Fixed label column (left) ──
                    SizedBox(
                      width: _kTlLabelWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Empty header aligned with ruler
                          Container(
                            height: _kTlRulerHeight,
                            color: const Color(0xFF14141A),
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 6),
                            child: Text('EVENT / LAYER',
                              style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold,
                                color: Colors.white24, letterSpacing: 0.5)),
                          ),
                          // Track labels
                          Expanded(
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: totalRows,
                              itemBuilder: (ctx, i) {
                                final (event, layer, isHeader) = _rowAtIndex(events, i);
                                return _buildTlLabel(event, layer, isHeader, mw);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Divider
                    Container(width: 1, color: Colors.white.withValues(alpha: 0.08)),
                    // ── Unified scrollable area (right) ──
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _tlScrollController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: totalWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Time ruler
                              SizedBox(
                                height: _kTlRulerHeight,
                                width: totalWidth,
                                child: CustomPaint(
                                  painter: _TlRulerPainter(
                                    pixelsPerSecond: _tlPixelsPerSecond,
                                    maxSeconds: maxEndSeconds,
                                  ),
                                ),
                              ),
                              // Waveform tracks
                              Expanded(
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: totalRows,
                                  itemBuilder: (ctx, i) {
                                    final (event, layer, isHeader) = _rowAtIndex(events, i);
                                    return _buildTlTrackContent(
                                      event, layer, isHeader, mw, maxEndSeconds, totalWidth,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Toolbar with zoom + event count
  Widget _buildTlToolbar(List<SlotCompositeEvent> events) {
    final totalLayers = events.fold<int>(0, (s, e) => s + e.layers.length);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgSurface,
        border: Border(bottom: BorderSide(color: LowerZoneColors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.view_timeline, size: 13, color: LowerZoneColors.slotLabAccent),
          const SizedBox(width: 6),
          Text('TIMELINE',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.7), letterSpacing: 0.5)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: LowerZoneColors.slotLabAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${events.length} events • $totalLayers layers',
              style: TextStyle(fontSize: 9, color: LowerZoneColors.slotLabAccent),
            ),
          ),
          const Spacer(),
          // Zoom controls
          _buildTlZoomButton(Icons.zoom_out, () =>
            setState(() => _tlPixelsPerSecond = (_tlPixelsPerSecond * 0.8).clamp(30.0, 500.0))),
          const SizedBox(width: 4),
          Text('${_tlPixelsPerSecond.toInt()}px/s',
            style: const TextStyle(fontSize: 8, color: Colors.white24, fontFamily: 'monospace')),
          const SizedBox(width: 4),
          _buildTlZoomButton(Icons.zoom_in, () =>
            setState(() => _tlPixelsPerSecond = (_tlPixelsPerSecond * 1.25).clamp(30.0, 500.0))),
        ],
      ),
    );
  }

  Widget _buildTlZoomButton(IconData icon, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 20, height: 20,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 14, color: Colors.white54),
        ),
      ),
    );
  }

  /// Total rows: 1 event header + N layers per event
  int _countTotalRows(List<SlotCompositeEvent> events) {
    int count = 0;
    for (final e in events) {
      count += 1 + e.layers.length;
    }
    return count;
  }

  /// Get event+layer for a given flat row index
  (SlotCompositeEvent, SlotEventLayer?, bool isHeader) _rowAtIndex(
      List<SlotCompositeEvent> events, int index) {
    int cursor = 0;
    for (final event in events) {
      if (cursor == index) return (event, null, true);
      cursor++;
      for (final layer in event.layers) {
        if (cursor == index) return (event, layer, false);
        cursor++;
      }
    }
    return (events.first, null, true);
  }

  /// Color per event based on its category or trigger stage
  Color _eventColor(SlotCompositeEvent event) {
    final stage = event.triggerStages.isNotEmpty ? event.triggerStages.first : '';
    if (stage.contains('WIN')) return const Color(0xFFFFD700);
    if (stage.contains('REEL')) return const Color(0xFF40C8FF);
    if (stage.contains('SPIN')) return const Color(0xFF4A9EFF);
    if (stage.contains('FEATURE') || stage.contains('FREE')) return const Color(0xFFFF9040);
    if (stage.contains('CASCADE')) return const Color(0xFFFF6B6B);
    if (stage.contains('BONUS')) return const Color(0xFF9370DB);
    if (stage.contains('MUSIC') || stage.contains('AMBIENT')) return const Color(0xFF40FF90);
    return event.color;
  }

  // ── Track label (fixed left column) ──

  Widget _buildTlLabel(
    SlotCompositeEvent event,
    SlotEventLayer? layer,
    bool isHeader,
    MiddlewareProvider mw,
  ) {
    final color = _eventColor(event);

    if (isHeader) {
      // Event header row
      final isSelected = _tlSelectedEventId == event.id;
      return GestureDetector(
        onTap: () => setState(() {
          _tlSelectedEventId = event.id;
          _tlSelectedLayerId = null;
        }),
        child: Container(
          height: _kTlHeaderHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : LowerZoneColors.bgSurface,
            border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.3))),
          ),
          child: Row(
            children: [
              Container(width: 6, height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.name,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: LowerZoneColors.textPrimary),
                      overflow: TextOverflow.ellipsis),
                    if (event.triggerStages.isNotEmpty)
                      Text(event.triggerStages.first,
                        style: TextStyle(fontSize: 7, color: color.withValues(alpha: 0.7)),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${event.layers.length}',
                  style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    // Layer label row
    final l = layer!;
    final isSelected = _tlSelectedLayerId == l.id;
    final hasAudio = l.audioPath.isNotEmpty;
    final trackColors = [
      const Color(0xFF4A9EFF), const Color(0xFF40FF90), const Color(0xFFFF9040),
      const Color(0xFF40C8FF), const Color(0xFF9370DB), const Color(0xFFFF4060),
    ];
    final layerIndex = event.layers.indexOf(l);
    final trackColor = l.muted ? Colors.grey : trackColors[layerIndex % trackColors.length];

    return GestureDetector(
      onTap: () => setState(() {
        _tlSelectedEventId = event.id;
        _tlSelectedLayerId = l.id;
      }),
      child: Container(
        height: _kTlTrackHeight,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.1)
              : const Color(0xFF14141A),
          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    color: trackColor.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text('${layerIndex + 1}',
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: trackColor)),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    l.name.isNotEmpty ? l.name : l.audioPath.split('/').last,
                    style: const TextStyle(fontSize: 8, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mute
                _buildTlTrackBtn('M',
                  l.muted ? LowerZoneColors.error : Colors.white24,
                  () => mw.updateEventLayer(event.id, l.copyWith(muted: !l.muted))),
                const SizedBox(width: 4),
                // Solo
                _buildTlTrackBtn('S',
                  l.solo ? LowerZoneColors.middlewareAccent : Colors.white24,
                  () => mw.updateEventLayer(event.id, l.copyWith(solo: !l.solo))),
                const SizedBox(width: 4),
                // Preview
                if (hasAudio)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        AudioPlaybackService.instance.stopSource(PlaybackSource.browser);
                        AudioPlaybackService.instance.previewFile(
                          l.audioPath, volume: l.volume, source: PlaybackSource.browser);
                      },
                      child: const Icon(Icons.play_arrow, size: 12, color: LowerZoneColors.success),
                    ),
                  ),
                const Spacer(),
                // Delete
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      _tlWaveformCache.remove(l.id);
                      _tlDurationCache.remove(l.id);
                      _tlWaveformLoaded.remove(l.id);
                      mw.removeLayerFromEvent(event.id, l.id);
                    },
                    child: const Icon(Icons.close, size: 10, color: Colors.white24),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTlTrackBtn(String label, Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(label,
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }

  // ── Waveform track content (scrollable right area — unified scroll) ──

  Widget _buildTlTrackContent(
    SlotCompositeEvent event,
    SlotEventLayer? layer,
    bool isHeader,
    MiddlewareProvider mw,
    double maxSeconds,
    double totalWidth,
  ) {
    final color = _eventColor(event);

    if (isHeader) {
      // Event header track — duration bar
      final duration = math.max(event.totalDurationSeconds, 0.5);
      final widthPx = (duration * _tlPixelsPerSecond).clamp(30.0, totalWidth);

      return Container(
        height: _kTlHeaderHeight,
        width: totalWidth,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.04),
          border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.3))),
        ),
        child: Stack(
          children: [
            // Grid lines
            CustomPaint(
              size: Size(totalWidth, _kTlHeaderHeight),
              painter: _TlGridPainter(pixelsPerSecond: _tlPixelsPerSecond, maxSeconds: maxSeconds),
            ),
            // Event duration bar
            Positioned(
              left: 0, top: 6, bottom: 6,
              child: Container(
                width: widthPx,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.12)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.centerLeft,
                child: Text(
                  '${event.name} • ${duration.toStringAsFixed(1)}s',
                  style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Layer waveform track
    final l = layer!;
    final layerIndex = event.layers.indexOf(l);
    final waveform = _tlWaveformCache[l.id];
    final duration = _tlDurationCache[l.id] ?? (l.durationSeconds ?? 1.0);
    final offsetSec = l.offsetMs / 1000.0;
    final waveformWidth = duration * _tlPixelsPerSecond;
    final offsetPixels = offsetSec * _tlPixelsPerSecond;
    final isDragging = _tlDraggingLayerId == l.id;
    final hasAudio = l.audioPath.isNotEmpty;
    final fileName = hasAudio ? l.audioPath.split('/').last : 'No audio';

    final trackColors = [
      const Color(0xFF4A9EFF), const Color(0xFF40FF90), const Color(0xFFFF9040),
      const Color(0xFF40C8FF), const Color(0xFF9370DB), const Color(0xFFFF4060),
    ];
    final trackColor = l.muted ? Colors.grey : trackColors[layerIndex % trackColors.length];

    return Container(
      height: _kTlTrackHeight,
      width: totalWidth,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Stack(
        children: [
          // Grid lines
          CustomPaint(
            size: Size(totalWidth, _kTlTrackHeight),
            painter: _TlGridPainter(pixelsPerSecond: _tlPixelsPerSecond, maxSeconds: maxSeconds),
          ),
          // Waveform block at offset position
          Positioned(
            left: offsetPixels,
            top: 3,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                final deltaMs = (details.delta.dx / _tlPixelsPerSecond) * 1000.0;
                final newOffset = (l.offsetMs + deltaMs).clamp(0.0, maxSeconds * 1000.0);
                mw.updateEventLayer(event.id, l.copyWith(offsetMs: newOffset));
              },
              onHorizontalDragStart: (_) => setState(() => _tlDraggingLayerId = l.id),
              onHorizontalDragEnd: (_) => setState(() => _tlDraggingLayerId = null),
              child: MouseRegion(
                cursor: isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
                child: Container(
                  width: waveformWidth.clamp(10.0, totalWidth),
                  height: 50,
                  decoration: BoxDecoration(
                    color: trackColor.withValues(alpha: isDragging ? 0.25 : 0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isDragging
                          ? trackColor.withValues(alpha: 0.8)
                          : trackColor.withValues(alpha: 0.4),
                      width: isDragging ? 1.5 : 1.0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Stack(
                      children: [
                        // Waveform
                        if (waveform != null && waveform.isNotEmpty)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _TlWaveformPainter(
                                data: waveform,
                                color: trackColor,
                                isMuted: l.muted,
                              ),
                            ),
                          )
                        else
                          Center(
                            child: Text(
                              hasAudio ? 'Loading...' : 'No audio',
                              style: const TextStyle(fontSize: 8, color: Colors.white24),
                            ),
                          ),
                        // File name label
                        Positioned(
                          left: 4, top: 2,
                          child: Text(fileName,
                            style: TextStyle(fontSize: 8, color: trackColor.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500)),
                        ),
                        // Offset + duration
                        Positioned(
                          right: 4, bottom: 2,
                          child: Text(
                            '${l.offsetMs.toInt()}ms  ${duration.toStringAsFixed(1)}s',
                            style: const TextStyle(fontSize: 7, color: Colors.white38, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Waveform loading for timeline (DAW-grade: sync cache + batch cold load) ──

  /// Track which layers have been cold-loaded (prevent duplicate FFI calls)
  final Set<String> _tlWaveformLoaded = {};

  /// Synchronous cache check — runs in build(), O(1) per layer.
  /// Cold misses are batched and loaded outside build via postFrameCallback.
  void _syncTlWaveformsFromCache(List<SlotCompositeEvent> events) {
    final coldMissLayers = <SlotEventLayer>[];

    for (final event in events) {
      for (final layer in event.layers) {
        if (layer.audioPath.isEmpty) continue;
        if (_tlWaveformCache.containsKey(layer.id)) continue;

        // Layer has inline waveformData — use directly
        if (layer.waveformData != null && layer.waveformData!.isNotEmpty) {
          _tlWaveformCache[layer.id] = Float32List.fromList(
            layer.waveformData!.map((v) => v.toDouble()).toList(),
          );
          _ensureTlDuration(layer);
          continue;
        }

        // Check WaveformCacheService memory (O(1), no allocation)
        final cached = WaveformCacheService.instance.getMemorySync(layer.audioPath);
        if (cached != null) {
          _tlWaveformCache[layer.id] = cached;
          _ensureTlDuration(layer);
          continue;
        }

        // Cold miss — schedule for batch FFI load (outside build)
        if (!_tlWaveformLoaded.contains(layer.id)) {
          coldMissLayers.add(layer);
        }
        _ensureTlDuration(layer);
      }
    }

    // Batch cold load in next frame (NOT in build)
    if (coldMissLayers.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _batchLoadWaveforms(coldMissLayers);
      });
    }
  }

  /// Batch-load cold miss waveforms via FFI, then single setState.
  /// Each FFI call is ~5-15ms for small audio files (2048 peak samples = 8KB).
  void _batchLoadWaveforms(List<SlotEventLayer> layers) {
    bool anyNew = false;

    for (final layer in layers) {
      if (_tlWaveformCache.containsKey(layer.id)) continue;
      if (_tlWaveformLoaded.contains(layer.id)) continue;
      _tlWaveformLoaded.add(layer.id);

      try {
        final cacheKey = 'tl-${layer.id}';
        final json = NativeFFI.instance.generateWaveformFromFile(layer.audioPath, cacheKey);
        if (json != null) {
          final (left, right) = parseWaveformFromJson(json, maxSamples: 2048);
          if (left != null) {
            Float32List waveform;
            if (right != null && right.length == left.length) {
              waveform = Float32List(left.length);
              for (int i = 0; i < left.length; i++) {
                waveform[i] = (left[i] + right[i]) * 0.5;
              }
            } else {
              waveform = Float32List.fromList(left);
            }
            _tlWaveformCache[layer.id] = waveform;
            // Store in WaveformCacheService memory for cross-session reuse
            WaveformCacheService.instance.putMemorySync(layer.audioPath, waveform);
            anyNew = true;
          }
        }
      } catch (_) {
        // FFI may not be available
      }
    }

    // Single setState for ALL loaded waveforms (not one per waveform)
    if (anyNew && mounted) {
      setState(() {});
    }
  }

  void _ensureTlDuration(SlotEventLayer layer) {
    if (_tlDurationCache.containsKey(layer.id)) return;
    final dur = layer.durationSeconds;
    if (dur != null && dur > 0) {
      _tlDurationCache[layer.id] = dur;
    } else {
      try {
        final d = NativeFFI.instance.getAudioFileDuration(layer.audioPath);
        if (d > 0) {
          _tlDurationCache[layer.id] = d;
        }
      } catch (_) {
        // FFI may not be available
      }
    }
  }

  // ─── P1.4: Event Folder State ─────────────────────────────────────────────
  String _selectedCategory = 'all';

  /// P1.4: Compact Event Folder — Connected to MiddlewareProvider composite events
  Widget _buildCompactEventFolder() {
    final middleware = _tryGetMiddlewareProvider();
    if (middleware == null) {
      return _buildNoProviderPanel('Event Folder', Icons.folder_special, 'MiddlewareProvider');
    }

    final events = middleware.compositeEvents;

    // Group events by category
    final categoryMap = <String, List<SlotCompositeEvent>>{};
    for (final event in events) {
      final cat = event.category.isNotEmpty ? event.category : 'uncategorized';
      categoryMap.putIfAbsent(cat, () => []).add(event);
    }

    // Sort categories by game flow hierarchy
    final sortedCategories = sortCategoriesHierarchically(categoryMap.keys);

    // Filter events based on selected category, sort within categories alphabetically
    for (final cat in categoryMap.keys) {
      categoryMap[cat]!.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    final filteredEvents = _selectedCategory == 'all'
        ? sortEventsHierarchically(events)
        : categoryMap[_selectedCategory] ?? [];

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // mainAxisSize removed — fills Flexible parent
        children: [
          // Header (compact)
          Row(
            children: [
              _buildPanelHeader('EVENT FOLDER', Icons.folder_special),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: LowerZoneColors.slotLabAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${events.length}',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: LowerZoneColors.slotLabAccent),
                ),
              ),
              const Spacer(),
              // Add event button (compact)
              GestureDetector(
                onTap: () {
                  final category = _selectedCategory == 'all' ? 'general' : _selectedCategory;
                  middleware.createCompositeEvent(
                    name: 'New Event ${DateTime.now().millisecondsSinceEpoch % 1000}',
                    category: category,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: LowerZoneColors.slotLabAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.slotLabAccent),
                  ),
                  child: Row(
                    // mainAxisSize removed — fills Flexible parent
                    children: [
                      Icon(Icons.add, size: 10, color: LowerZoneColors.slotLabAccent),
                      const SizedBox(width: 2),
                      Text('New', style: TextStyle(fontSize: 9, color: LowerZoneColors.slotLabAccent)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Main content (flexible with row)
          Flexible(
            fit: FlexFit.loose,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Folder tree (categories) - fixed width
                SizedBox(
                  width: 130,
                  child: Container(
                    decoration: BoxDecoration(
                      color: LowerZoneColors.bgDeepest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: LowerZoneColors.border),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: ListView(
                      padding: const EdgeInsets.all(3),
                      shrinkWrap: true,
                      children: [
                        _buildFolderItemConnected(
                          'All Events',
                          Icons.folder_special,
                          events.length,
                          _selectedCategory == 'all',
                          () => setState(() => _selectedCategory = 'all'),
                        ),
                        const Divider(height: 6, color: LowerZoneColors.border),
                        ...sortedCategories.map((cat) => _buildFolderItemConnected(
                          cat[0].toUpperCase() + cat.substring(1),
                          _selectedCategory == cat ? Icons.folder_open : Icons.folder,
                          categoryMap[cat]!.length,
                          _selectedCategory == cat,
                          () => setState(() => _selectedCategory = cat),
                        )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Event list - flexible
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: LowerZoneColors.bgDeepest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: LowerZoneColors.border),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: filteredEvents.isEmpty
                        ? _buildNoEventsMessage()
                        : ListView.builder(
                            padding: const EdgeInsets.all(3),
                            shrinkWrap: true,
                            itemCount: filteredEvents.length,
                            itemBuilder: (context, index) {
                              final event = filteredEvents[index];
                              return _buildEventItemConnected(event, middleware);
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// P1.4: Folder item connected to category selection
  Widget _buildFolderItemConnected(String name, IconData icon, int count, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isSelected ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? LowerZoneColors.slotLabAccent : LowerZoneColors.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.2)
                    : LowerZoneColors.bgMid,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// P1.4: Event item connected to MiddlewareProvider
  Widget _buildEventItemConnected(SlotCompositeEvent event, MiddlewareProvider middleware) {
    final hasAudio = event.layers.isNotEmpty;
    final isSelected = middleware.selectedCompositeEvent?.id == event.id;

    return GestureDetector(
      onTap: () => middleware.selectCompositeEvent(event.id),
      // SL-RP-P1.1: Context menu on right-click
      onSecondaryTapUp: (details) => _showEventContextMenu(context, event, middleware, details.globalPosition),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isSelected
              ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.15)
              : LowerZoneColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: isSelected
              ? Border.all(color: LowerZoneColors.slotLabAccent)
              : null,
        ),
        child: Row(
          children: [
            // Audio indicator
            Icon(
              hasAudio ? Icons.volume_up : Icons.volume_off,
              size: 12,
              color: hasAudio ? LowerZoneColors.success : LowerZoneColors.textMuted,
            ),
            const SizedBox(width: 6),
            // Event color dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: event.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            // Event name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.name,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? LowerZoneColors.slotLabAccent : LowerZoneColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (event.triggerStages.isNotEmpty)
                    Text(
                      event.triggerStages.take(2).join(', '),
                      style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
                    ),
                ],
              ),
            ),
            // Layer count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: LowerZoneColors.bgDeepest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${event.layers.length}L',
                style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
              ),
            ),
            const SizedBox(width: 4),
            // Play button
            GestureDetector(
              onTap: () {
                final middleware = context.read<MiddlewareProvider>();
                middleware.previewCompositeEvent(event.id);
              },
              child: Icon(
                Icons.play_arrow,
                size: 14,
                color: isSelected ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// SL-RP-P1.1: Event context menu (duplicate, export, test)
  void _showEventContextMenu(
    BuildContext context,
    SlotCompositeEvent event,
    MiddlewareProvider middleware,
    Offset position,
  ) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.copy, size: 16, color: LowerZoneColors.slotLabAccent),
              const SizedBox(width: 8),
              const Text('Duplicate', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'test',
          child: Row(
            children: [
              Icon(Icons.play_circle, size: 16, color: LowerZoneColors.success),
              const SizedBox(width: 8),
              const Text('Test Playback', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'export_json',
          child: Row(
            children: [
              Icon(Icons.code, size: 16, color: LowerZoneColors.textMuted),
              const SizedBox(width: 8),
              const Text('Export as JSON', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'export_audio',
          child: Row(
            children: [
              Icon(Icons.audio_file, size: 16, color: LowerZoneColors.textMuted),
              const SizedBox(width: 8),
              const Text('Export Audio Bundle', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 16, color: LowerZoneColors.error),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(fontSize: 12, color: LowerZoneColors.error)),
            ],
          ),
        ),
      ],
    );

    if (!mounted || result == null) return;

    switch (result) {
      case 'duplicate':
        middleware.duplicateCompositeEvent(event.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Duplicated: ${event.name}'),
            duration: const Duration(seconds: 1),
          ),
        );
        break;
      case 'test':
        middleware.previewCompositeEvent(event.id);
        break;
      case 'export_json':
        _exportEventAsJson(event);
        break;
      case 'export_audio':
        _exportEventAudioBundle(event);
        break;
      case 'delete':
        _confirmDeleteEvent(context, event, middleware);
        break;
    }
  }

  /// SL-RP-P1.1: Export event as JSON
  void _exportEventAsJson(SlotCompositeEvent event) {
    final json = event.toJson();
    // Copy to clipboard
    Clipboard.setData(ClipboardData(text: json.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Event JSON copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// SL-RP-P1.1: Export event audio bundle
  void _exportEventAudioBundle(SlotCompositeEvent event) {
    if (event.layers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No audio layers to export')),
      );
      return;
    }
    // For now just show paths, future: create ZIP bundle
    final paths = event.layers.map((l) => l.audioPath).join('\n');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${event.layers.length} audio file(s) in ${event.name}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// SL-RP-P1.1: Confirm delete with dialog
  void _confirmDeleteEvent(BuildContext context, SlotCompositeEvent event, MiddlewareProvider middleware) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LowerZoneColors.bgMid,
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: LowerZoneColors.error),
            const SizedBox(width: 8),
            const Text('Delete Event', style: TextStyle(fontSize: 14)),
          ],
        ),
        content: Text(
          'Delete "${event.name}"?\n\nThis will remove the event and all its layers.',
          style: const TextStyle(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              middleware.deleteCompositeEvent(event.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Deleted: ${event.name}')),
              );
            },
            child: Text('Delete', style: TextStyle(color: LowerZoneColors.error)),
          ),
        ],
      ),
    );
  }

  /// P1.4: No events placeholder
  Widget _buildNoEventsMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy,
            size: 32,
            color: LowerZoneColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          const Text(
            'No events in this folder',
            style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
          ),
          const SizedBox(height: 4),
          const Text(
            'Click "New Event" to create one',
            style: TextStyle(fontSize: 9, color: LowerZoneColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderItem(String name, IconData icon, int count, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isSelected ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.1) : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: isSelected ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? LowerZoneColors.slotLabAccent : LowerZoneColors.textPrimary,
              ),
            ),
          ),
          Text('$count', style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildEventItem(String name, bool hasAudio) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            hasAudio ? Icons.volume_up : Icons.volume_off,
            size: 12,
            color: hasAudio ? LowerZoneColors.success : LowerZoneColors.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(name, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary)),
          ),
          Icon(Icons.play_arrow, size: 12, color: LowerZoneColors.textMuted),
        ],
      ),
    );
  }

  // P2.7: Selected event ID for composite editor
  String? _selectedEventId;

  /// P2.7: Compact Composite Editor — Connected to MiddlewareProvider.compositeEvents
  ///
  /// FIX 2026-01-25: Uses Consumer to ensure UI rebuilds when
  /// layer parameters (volume, pan, delay) are changed via sliders.
  Widget _buildCompactCompositeEditor() {
    // Use Consumer to ensure rebuilds when provider changes
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final events = middleware.compositeEvents;

        // Find selected event
        SlotCompositeEvent? selectedEvent;
        if (_selectedEventId != null) {
          selectedEvent = events.where((e) => e.id == _selectedEventId).firstOrNull;
        }
        selectedEvent ??= events.firstOrNull;

        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // mainAxisSize removed — fills Flexible parent
            children: [
              // Header (compact)
              Row(
                children: [
                  _buildPanelHeader('COMPOSITE EDITOR', Icons.edit),
                  const Spacer(),
                  if (events.isNotEmpty)
                    SizedBox(
                      width: 120,
                      height: 24,
                      child: DropdownButton<String>(
                        value: selectedEvent?.id,
                        hint: const Text('Select', style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
                        dropdownColor: LowerZoneColors.bgMid,
                        style: TextStyle(fontSize: 9, color: LowerZoneColors.slotLabAccent),
                        underline: const SizedBox(),
                        isDense: true,
                        isExpanded: true,
                        items: events.map((e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(e.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9)),
                        )).toList(),
                        onChanged: (id) => setState(() => _selectedEventId = id),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Main content (flexible)
              Flexible(
                fit: FlexFit.loose,
                child: Container(
                  decoration: BoxDecoration(
                    color: LowerZoneColors.bgDeepest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.border),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: selectedEvent == null
                      ? const Center(
                          child: Text(
                            'No events. Create one in Events Folder.',
                            style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                          ),
                        )
                      : Column(
                          // mainAxisSize removed — fills Flexible parent
                          children: [
                            // Event header (compact)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: LowerZoneColors.slotLabAccent.withValues(alpha: 0.1),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(4),
                                  topRight: Radius.circular(4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      selectedEvent.name,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: LowerZoneColors.slotLabAccent),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text('${selectedEvent.layers.length}L', style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
                                ],
                              ),
                            ),
                            // Layers list (flexible) - P2.7: Wrapped with Focus for keyboard shortcuts
                            Flexible(
                              fit: FlexFit.loose,
                              child: Focus(
                                focusNode: _layerListFocusNode,
                                onKeyEvent: _handleLayerListKeyEvent,
                                child: GestureDetector(
                                  // Request focus on tap to enable keyboard shortcuts
                                  onTap: () => _layerListFocusNode.requestFocus(),
                                  child: selectedEvent.layers.isEmpty
                                      ? const Center(
                                          child: Text('No layers', style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
                                        )
                                      : ListView.builder(
                                          padding: const EdgeInsets.all(3),
                                          shrinkWrap: true,
                                          itemCount: selectedEvent.layers.length,
                                          itemBuilder: (context, index) {
                                            final event = selectedEvent!;
                                            final layer = event.layers[index];
                                            return _buildInteractiveLayerItem(
                                              eventId: event.id,
                                              layer: layer,
                                              index: index,
                                            );
                                          },
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// SL-P1.1 FIX: Interactive layer item with editable parameters
  /// P2.6: Multi-select support with Ctrl/Shift+click
  Widget _buildInteractiveLayerItem({
    required String eventId,
    required SlotEventLayer layer,
    required int index,
  }) {
    final audioName = layer.audioPath.split('/').last;
    final middleware = context.read<MiddlewareProvider>();
    final isSelected = middleware.isLayerSelected(layer.id);
    final hasMultiSelect = middleware.hasMultipleLayersSelected;

    return Listener(
      // P2.6: Use Listener for reliable modifier key detection (per CLAUDE.md)
      onPointerDown: (event) {
        if (event.buttons != kPrimaryButton) return;

        // P2.7: Request focus to enable keyboard shortcuts
        _layerListFocusNode.requestFocus();

        final isCtrl = HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        final isShift = HardwareKeyboard.instance.isShiftPressed;

        if (isShift && _lastSelectedLayerId != null) {
          // Shift+click: Range selection
          middleware.selectLayerRange(eventId, _lastSelectedLayerId!, layer.id);
        } else if (isCtrl) {
          // Ctrl/Cmd+click: Toggle selection
          middleware.toggleLayerSelection(layer.id);
        } else {
          // Normal click: Single select
          middleware.selectLayer(layer.id);
        }
        _lastSelectedLayerId = layer.id;
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? LowerZoneColors.slotLabAccent.withOpacity(0.15) : LowerZoneColors.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? LowerZoneColors.slotLabAccent : Colors.white.withOpacity(0.05),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: checkbox, name, mute, play, delete
            Row(
              children: [
                // P2.6: Selection checkbox
                GestureDetector(
                  onTap: () => middleware.toggleLayerSelection(layer.id),
                  child: Icon(
                    isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 14,
                    color: isSelected ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.drag_indicator, size: 12, color: LowerZoneColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'L${index + 1}: $audioName',
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? LowerZoneColors.slotLabAccent : LowerZoneColors.textPrimary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Mute toggle
                GestureDetector(
                  onTap: () {
                    middleware.updateEventLayer(eventId, layer.copyWith(muted: !layer.muted));
                  },
                  child: Icon(
                    layer.muted ? Icons.volume_off : Icons.volume_up,
                    size: 14,
                    color: layer.muted ? Colors.red : LowerZoneColors.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                // Preview play
                GestureDetector(
                  onTap: () {
                    if (layer.audioPath.isNotEmpty) {
                      AudioPlaybackService.instance.previewFile(
                        layer.audioPath,
                        volume: layer.volume,
                        source: PlaybackSource.browser,
                      );
                    }
                  },
                  child: Icon(Icons.play_arrow, size: 14, color: LowerZoneColors.slotLabAccent),
                ),
                const SizedBox(width: 8),
                // Delete (single or multi)
                GestureDetector(
                  onTap: () {
                    if (hasMultiSelect && isSelected) {
                      // Delete all selected layers
                      middleware.deleteSelectedLayers(eventId);
                    } else {
                      // Delete single layer
                      middleware.removeLayerFromEvent(eventId, layer.id);
                    }
                  },
                  child: Icon(
                    hasMultiSelect && isSelected ? Icons.delete_sweep : Icons.close,
                    size: 14,
                    color: hasMultiSelect && isSelected ? Colors.red : LowerZoneColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Volume slider
            _buildParameterSlider(
              label: 'Vol',
              value: layer.volume,
              min: 0.0,
              max: 1.0,
              displayValue: '${(layer.volume * 100).toInt()}%',
              onChanged: (v) => middleware.updateEventLayer(eventId, layer.copyWith(volume: v)),
            ),
            const SizedBox(height: 4),
            // Pan slider
            _buildParameterSlider(
              label: 'Pan',
              value: (layer.pan + 1) / 2, // Convert -1..1 to 0..1 for slider
              min: 0.0,
              max: 1.0,
              displayValue: layer.pan == 0 ? 'C' : '${(layer.pan * 100).toInt().abs()}${layer.pan > 0 ? 'R' : 'L'}',
              onChanged: (v) => middleware.updateEventLayer(eventId, layer.copyWith(pan: (v * 2) - 1)),
            ),
            const SizedBox(height: 4),
            // Delay slider
            _buildParameterSlider(
              label: 'Delay',
              value: (layer.offsetMs / 2000).clamp(0.0, 1.0), // 0-2000ms range
              min: 0.0,
              max: 1.0,
              displayValue: '${layer.offsetMs.toInt()}ms',
              onChanged: (v) => middleware.updateEventLayer(eventId, layer.copyWith(offsetMs: v * 2000)),
            ),
            const SizedBox(height: 6),
            // P2.8: Fade Controls section
            _buildFadeControlsSection(eventId, layer, middleware),
          ],
        ),
      ),
    );
  }

  /// P2.8: Build fade controls section with visual curve overlay
  Widget _buildFadeControlsSection(String eventId, SlotEventLayer layer, MiddlewareProvider middleware) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with expand/collapse and visual curve preview
        Row(
          children: [
            Text(
              'FADES',
              style: TextStyle(
                fontSize: 8,
                color: (layer.fadeInMs > 0 || layer.fadeOutMs > 0)
                    ? LowerZoneColors.slotLabAccent
                    : LowerZoneColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            // Visual fade curve preview (mini waveform representation)
            Expanded(
              child: SizedBox(
                height: 16,
                child: CustomPaint(
                  painter: _FadeCurvePainter(
                    fadeInMs: layer.fadeInMs,
                    fadeOutMs: layer.fadeOutMs,
                    fadeInCurve: layer.fadeInCurve,
                    fadeOutCurve: layer.fadeOutCurve,
                    color: LowerZoneColors.slotLabAccent,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Fade In slider
        _buildParameterSlider(
          label: 'In',
          value: (layer.fadeInMs / 1000).clamp(0.0, 1.0), // 0-1000ms range
          min: 0.0,
          max: 1.0,
          displayValue: '${layer.fadeInMs.toInt()}ms',
          onChanged: (v) => middleware.updateEventLayer(eventId, layer.copyWith(fadeInMs: v * 1000)),
        ),
        const SizedBox(height: 2),
        // Fade Out slider
        _buildParameterSlider(
          label: 'Out',
          value: (layer.fadeOutMs / 1000).clamp(0.0, 1.0), // 0-1000ms range
          min: 0.0,
          max: 1.0,
          displayValue: '${layer.fadeOutMs.toInt()}ms',
          onChanged: (v) => middleware.updateEventLayer(eventId, layer.copyWith(fadeOutMs: v * 1000)),
        ),
        const SizedBox(height: 2),
        // Curve type selectors (compact row)
        Row(
          children: [
            const SizedBox(width: 32),
            // Fade In Curve
            _buildCompactCurveSelector(
              label: 'In:',
              value: layer.fadeInCurve,
              onChanged: (curve) => middleware.updateEventLayer(eventId, layer.copyWith(fadeInCurve: curve)),
            ),
            const SizedBox(width: 12),
            // Fade Out Curve
            _buildCompactCurveSelector(
              label: 'Out:',
              value: layer.fadeOutCurve,
              onChanged: (curve) => middleware.updateEventLayer(eventId, layer.copyWith(fadeOutCurve: curve)),
            ),
          ],
        ),
      ],
    );
  }

  /// P2.8: Compact curve type selector
  Widget _buildCompactCurveSelector({
    required String label,
    required CrossfadeCurve value,
    required ValueChanged<CrossfadeCurve> onChanged,
  }) {
    return Row(
      // mainAxisSize removed — fills Flexible parent
      children: [
        Text(label, style: const TextStyle(fontSize: 7, color: LowerZoneColors.textMuted)),
        const SizedBox(width: 4),
        PopupMenuButton<CrossfadeCurve>(
          initialValue: value,
          onSelected: onChanged,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              // mainAxisSize removed — fills Flexible parent
              children: [
                Text(
                  _getCurveShortName(value),
                  style: const TextStyle(fontSize: 7, color: LowerZoneColors.textSecondary),
                ),
                const Icon(Icons.arrow_drop_down, size: 10, color: LowerZoneColors.textMuted),
              ],
            ),
          ),
          itemBuilder: (context) => CrossfadeCurve.values.map((curve) {
            return PopupMenuItem<CrossfadeCurve>(
              value: curve,
              height: 28,
              child: Text(_getCurveDisplayName(curve), style: const TextStyle(fontSize: 10)),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// P2.8: Get short name for curve type (for compact display)
  String _getCurveShortName(CrossfadeCurve curve) {
    return switch (curve) {
      CrossfadeCurve.linear => 'Lin',
      CrossfadeCurve.log3 => 'L3',
      CrossfadeCurve.sine => 'Sin',
      CrossfadeCurve.log1 => 'L1',
      CrossfadeCurve.invSCurve => 'IS',
      CrossfadeCurve.sCurve => 'S',
      CrossfadeCurve.exp1 => 'E1',
      CrossfadeCurve.exp3 => 'E3',
      CrossfadeCurve.equalPower => 'EP',
      CrossfadeCurve.sinCos => 'SC',
    };
  }

  /// P2.8: Get display name for curve type
  String _getCurveDisplayName(CrossfadeCurve curve) => curve.displayName;

  /// Compact parameter slider for layer editing
  Widget _buildParameterSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(label, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: LowerZoneColors.slotLabAccent,
              inactiveTrackColor: Colors.white.withOpacity(0.1),
              thumbColor: LowerZoneColors.slotLabAccent,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            displayValue,
            style: const TextStyle(fontSize: 8, color: LowerZoneColors.textSecondary),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  /// P2.8: Compact Voice Pool — Connected to MiddlewareProvider.getVoicePoolStats()
  Widget _buildCompactVoicePool() {
    // P0.2 FIX: Use real FFI data instead of fake ratios
    final nativeStats = NativeFFI.instance.getVoicePoolStats();

    final totalVoices = nativeStats.maxVoices;
    final activeVoices = nativeStats.activeCount;
    final virtualVoices = 0; // Virtual voices tracked separately if needed
    final stealCount = 0; // Steal count tracked via events

    // Real per-bus data from FFI (no more fake ratios!)
    final busStats = <String, (int, int)>{
      'SFX': (nativeStats.sfxVoices, 16),
      'Music': (nativeStats.musicVoices, 8),
      'Voice': (nativeStats.voiceVoices, 4),
      'Ambient': (nativeStats.ambienceVoices, 12),
      'Aux': (nativeStats.auxVoices, 8),
    };

    final usagePercent = totalVoices > 0 ? activeVoices / totalVoices : 0.0;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // mainAxisSize removed — fills Flexible parent
        children: [
          // Header (compact)
          Row(
            children: [
              _buildPanelHeader('VOICE POOL', Icons.queue_music),
              const Spacer(),
              Text(
                '$activeVoices/$totalVoices',
                style: TextStyle(fontSize: 10, color: usagePercent > 0.8 ? LowerZoneColors.warning : LowerZoneColors.slotLabAccent),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Stats row (compact)
          Row(
            children: [
              _buildStatBadge('Virtual', '$virtualVoices', virtualVoices > 0 ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted),
              const SizedBox(width: 6),
              _buildStatBadge('Steals', '$stealCount', stealCount > 0 ? LowerZoneColors.warning : LowerZoneColors.textMuted),
            ],
          ),
          const SizedBox(height: 8),
          // Usage bar (compact)
          Container(
            height: 16,
            decoration: BoxDecoration(
              color: LowerZoneColors.bgDeepest,
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: usagePercent,
              child: Container(
                decoration: BoxDecoration(
                  color: usagePercent > 0.8 ? LowerZoneColors.warning : LowerZoneColors.slotLabAccent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Bus stats (flexible)
          Flexible(
            fit: FlexFit.loose,
            child: ListView(
              shrinkWrap: true,
              children: busStats.entries.map((entry) {
                final (used, limit) = entry.value;
                return _buildVoiceUsageRow(entry.key, used, limit);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Row(
        // mainAxisSize removed — fills Flexible parent
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }

  Widget _buildVoiceUsageRow(String busName, int used, int limit) {
    final ratio = limit > 0 ? used / limit : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(busName, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary))),
          Expanded(
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color: LowerZoneColors.bgDeepest,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: ratio,
                child: Container(
                  decoration: BoxDecoration(
                    color: ratio > 0.8 ? LowerZoneColors.warning : LowerZoneColors.slotLabAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 40, child: Text('$used/$limit', style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted))),
        ],
      ),
    );
  }

  /// Compact Pan Panel
  Widget _buildCompactPanPanel() {
    // P0.3 FIX: Connect to MixerDSPProvider for real pan values
    final mixerProvider = context.read<MixerDSPProvider>();
    final buses = mixerProvider.buses;

    // Map bus IDs to display names
    final displayBuses = [
      ('sfx', 'SFX'),
      ('music', 'Music'),
      ('voice', 'Voice'),
      ('ambience', 'Ambient'),
    ];

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // mainAxisSize removed — fills Flexible parent
        children: [
          _buildPanelHeader('STEREO PANNER', Icons.surround_sound),
          const SizedBox(height: 8),
          Flexible(
            fit: FlexFit.loose,
            child: Row(
              children: displayBuses.map((entry) {
                final (busId, displayName) = entry;
                final bus = buses.firstWhere(
                  (b) => b.id == busId,
                  orElse: () => MixerBus(id: busId, name: displayName),
                );
                return _buildPanChannel(displayName, bus.pan, busId, mixerProvider);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanChannel(String name, double pan, String busId, MixerDSPProvider provider) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Text(name, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: LowerZoneColors.textSecondary)),
            const SizedBox(height: 8),
            Expanded(
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  // Interactive pan control
                  final newPan = (pan + details.delta.dx / 60).clamp(-1.0, 1.0);
                  provider.setBusPan(busId, newPan);
                },
                onDoubleTap: () {
                  // Double-tap to center
                  provider.setBusPan(busId, 0.0);
                },
                child: Container(
                  width: 80,
                  decoration: BoxDecoration(
                    color: LowerZoneColors.bgDeepest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.border),
                  ),
                  child: Stack(
                    children: [
                      // Center line
                      Center(
                        child: Container(width: 1, color: LowerZoneColors.border),
                      ),
                      // Pan indicator
                      Center(
                        child: Transform.translate(
                          offset: Offset(pan * 30, 0),
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: LowerZoneColors.slotLabAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      // L/R labels
                      const Positioned(left: 4, top: 4, child: Text('L', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted))),
                      const Positioned(right: 4, top: 4, child: Text('R', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted))),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(pan == 0 ? 'C' : '${(pan * 100).toInt().abs()}${pan > 0 ? 'R' : 'L'}',
              style: TextStyle(fontSize: 9, color: LowerZoneColors.slotLabAccent)),
          ],
        ),
      ),
    );
  }

  // Note: Compact Meter Panel replaced by RealTimeBusMeters widget (P1.4)

  /// Compact DSP Chain
  Widget _buildCompactDspChain() {
    // P0.1 FIX: Connect to DspChainProvider (trackId 0 = master bus)
    final dspProvider = DspChainProvider.instance;
    final chain = dspProvider.getChain(0);
    final nodes = chain.nodes;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // mainAxisSize removed — fills Flexible parent
        children: [
          _buildPanelHeader('SIGNAL CHAIN', Icons.link),
          const SizedBox(height: 8),
          Flexible(
            fit: FlexFit.loose,
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  // mainAxisSize removed — fills Flexible parent
                  children: [
                    _buildDspNode('IN', Icons.input, isEndpoint: true),
                    _buildDspArrow(),
                    // Dynamic nodes from DspChainProvider
                    if (nodes.isEmpty)
                      _buildDspNode('—', Icons.add, isActive: false)
                    else
                      ...nodes.expand((node) => [
                            _buildDspNode(
                              node.type.shortName,
                              _iconForDspType(node.type),
                              isActive: !node.bypass,
                            ),
                            _buildDspArrow(),
                          ]),
                    _buildDspNode('OUT', Icons.output, isEndpoint: true),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper: Get icon for DSP node type
  IconData _iconForDspType(DspNodeType type) {
    return switch (type) {
      DspNodeType.eq => Icons.equalizer,
      DspNodeType.compressor => Icons.compress,
      DspNodeType.limiter => Icons.volume_up,
      DspNodeType.gate => Icons.volume_off,
      DspNodeType.expander => Icons.unfold_more,
      DspNodeType.reverb => Icons.waves,
      DspNodeType.delay => Icons.timer,
      DspNodeType.saturation => Icons.whatshot,
      DspNodeType.deEsser => Icons.speaker_notes_off,
      DspNodeType.pultec => Icons.tune,
      DspNodeType.api550 => Icons.graphic_eq,
      DspNodeType.neve1073 => Icons.surround_sound,
      DspNodeType.multibandSaturation => Icons.whatshot,
      DspNodeType.haasDelay => Icons.spatial_audio_off,
      DspNodeType.stereoImager => Icons.surround_sound,
      DspNodeType.multibandStereoImager => Icons.surround_sound,
    };
  }

  Widget _buildDspNode(String label, IconData icon, {bool isEndpoint = false, bool isActive = false}) {
    final color = isEndpoint ? LowerZoneColors.textMuted : (isActive ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted);
    return Container(
      width: 70,
      height: 60,
      decoration: BoxDecoration(
        color: isActive && !isEndpoint ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.1) : LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isActive && !isEndpoint ? LowerZoneColors.slotLabAccent : LowerZoneColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildDspArrow() {
    return Container(
      width: 20,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: LowerZoneColors.border,
    );
  }

  // Note: Compact EQ, Compressor, and Reverb panels replaced by FabFilter widgets

  // Note: _buildCompactExportPanel removed — replaced by SlotLabBatchExportPanel (P2.1)

  /// Helper method for Package panel option rows
  Widget _buildExportOption(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textMuted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: LowerZoneColors.textPrimary)),
        ],
      ),
    );
  }

  /// Compact Stems Panel — Connected to MixerDSPProvider buses
  Widget _buildCompactStemsPanel() {
    // P0.4 FIX: Read from MixerDSPProvider and use interactive checkboxes
    final mixerProvider = context.read<MixerDSPProvider>();
    final buses = mixerProvider.buses;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // mainAxisSize removed — fills Flexible parent
        children: [
          Row(
            children: [
              _buildPanelHeader('STEM EXPORT', Icons.account_tree),
              const Spacer(),
              Text(
                '${_selectedStemBusIds.length}/${buses.length} selected',
                style: TextStyle(fontSize: 10, color: LowerZoneColors.slotLabAccent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            fit: FlexFit.loose,
            child: Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: LowerZoneColors.bgDeepest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: LowerZoneColors.border),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(4),
                shrinkWrap: true,
                itemCount: buses.length,
                itemBuilder: (context, index) {
                  final bus = buses[index];
                  final isSelected = _selectedStemBusIds.contains(bus.id);
                  return _buildStemItem(bus.name, isSelected, bus.id, index);
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildActionButton('Export Stems', Icons.download, _exportStems),
            ],
          ),
        ],
      ),
    );
  }

  /// P0.4: Toggle stem selection
  void _toggleStemSelection(String busId) {
    setState(() {
      if (_selectedStemBusIds.contains(busId)) {
        _selectedStemBusIds.remove(busId);
      } else {
        _selectedStemBusIds.add(busId);
      }
    });
  }

  /// P0.4: Export selected stems
  void _exportStems() {
    if (_selectedStemBusIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one bus to export')),
      );
      return;
    }
    // TODO: Implement actual stem export via offline rendering
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exporting ${_selectedStemBusIds.length} stems...')),
    );
  }

  Widget _buildStemItem(String name, bool isSelected, String busId, int busIndex) {
    return GestureDetector(
      onTap: () => _toggleStemSelection(busId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.5) : LowerZoneColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14,
              color: isSelected ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted,
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(name, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary))),
            Text('Bus $busIndex', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: LowerZoneColors.slotLabAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.slotLabAccent),
        ),
        child: Row(
          // mainAxisSize removed — fills Flexible parent
          children: [
            Icon(icon, size: 12, color: LowerZoneColors.slotLabAccent),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: LowerZoneColors.slotLabAccent)),
          ],
        ),
      ),
    );
  }

  /// Compact Variations Panel — Connected to RandomContainer for variation generation
  Widget _buildCompactVariationsPanel() {
    final middleware = _tryGetMiddlewareProvider();
    if (middleware == null) {
      return const Center(child: Text('No middleware', style: TextStyle(color: LowerZoneColors.textMuted)));
    }

    final randomContainers = middleware.randomContainers;
    final variationCount = randomContainers.fold<int>(0, (sum, c) => sum + c.children.length);

    // Get global variation values from first container or use defaults
    final firstContainer = randomContainers.isNotEmpty ? randomContainers.first : null;
    final pitchRange = firstContainer != null
        ? (firstContainer.globalPitchMax - firstContainer.globalPitchMin).abs()
        : 0.1;
    final volumeRange = firstContainer != null
        ? (firstContainer.globalVolumeMax - firstContainer.globalVolumeMin).abs()
        : 0.05;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // mainAxisSize removed — fills Flexible parent
        children: [
          Row(
            children: [
              _buildPanelHeader('BATCH VARIATIONS', Icons.auto_awesome),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: LowerZoneColors.slotLabAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${randomContainers.length} containers',
                  style: TextStyle(fontSize: 10, color: LowerZoneColors.slotLabAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            fit: FlexFit.loose,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    // mainAxisSize removed — fills Flexible parent
                    children: [
                      _buildInteractiveVariationSlider(
                        'Pitch',
                        pitchRange,
                        maxRange: 0.24, // ±12 semitones = 24% range
                        onChanged: (value) => _applyVariationToAll(middleware, pitchRange: value),
                        formatValue: (v) => '±${(v * 100 / 2).toStringAsFixed(0)}%',
                      ),
                      _buildInteractiveVariationSlider(
                        'Volume',
                        volumeRange,
                        maxRange: 0.2, // ±10dB = 20% range
                        onChanged: (value) => _applyVariationToAll(middleware, volumeRange: value),
                        formatValue: (v) => '±${(v * 100 / 2).toStringAsFixed(0)}%',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 80,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: LowerZoneColors.bgDeepest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.border),
                  ),
                  child: Column(
                    // mainAxisSize removed — fills Flexible parent
                    children: [
                      Text('Children', style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
                      const SizedBox(height: 4),
                      Text('$variationCount', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: LowerZoneColors.slotLabAccent)),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _resetVariations(middleware),
                        child: Tooltip(
                          message: 'Reset all variations to zero',
                          child: Icon(Icons.refresh, size: 16, color: LowerZoneColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                randomContainers.isEmpty ? 'No containers' : 'Applies to all containers',
                style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Apply variation settings to all random containers
  void _applyVariationToAll(MiddlewareProvider middleware, {double? pitchRange, double? volumeRange}) {
    for (final container in middleware.randomContainers) {
      final currentPitch = pitchRange ?? (container.globalPitchMax - container.globalPitchMin).abs();
      final currentVolume = volumeRange ?? (container.globalVolumeMax - container.globalVolumeMin).abs();

      middleware.randomContainerSetGlobalVariation(
        container.id,
        pitchMin: -currentPitch / 2,
        pitchMax: currentPitch / 2,
        volumeMin: -currentVolume / 2,
        volumeMax: currentVolume / 2,
      );
    }
  }

  /// Reset all variations to zero
  void _resetVariations(MiddlewareProvider middleware) {
    for (final container in middleware.randomContainers) {
      middleware.randomContainerSetGlobalVariation(
        container.id,
        pitchMin: 0,
        pitchMax: 0,
        volumeMin: 0,
        volumeMax: 0,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All variations reset to zero'),
        duration: Duration(milliseconds: 800),
      ),
    );
  }

  Widget _buildInteractiveVariationSlider(
    String label,
    double value, {
    required double maxRange,
    required ValueChanged<double> onChanged,
    required String Function(double) formatValue,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 50, child: Text(label, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textMuted))),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: LowerZoneColors.slotLabAccent,
                inactiveTrackColor: LowerZoneColors.bgDeepest,
                thumbColor: LowerZoneColors.slotLabAccent,
                overlayColor: LowerZoneColors.slotLabAccent.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: value.clamp(0.0, maxRange),
                min: 0.0,
                max: maxRange,
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 35,
            child: Text(
              formatValue(value),
              style: TextStyle(fontSize: 9, color: LowerZoneColors.slotLabAccent),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// Compact Package Panel — Connected to MiddlewareProvider for event count
  Widget _buildCompactPackagePanel() {
    final middleware = _tryGetMiddlewareProvider();
    final eventCount = middleware?.compositeEvents.length ?? 0;
    // Estimate ~400KB per event average
    final estimatedSizeMb = (eventCount * 0.4).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // mainAxisSize removed — fills Flexible parent
        children: [
          Row(
            children: [
              _buildPanelHeader('GAME PACKAGE', Icons.inventory_2),
              const Spacer(),
              Text(
                '$eventCount events',
                style: TextStyle(fontSize: 10, color: LowerZoneColors.slotLabAccent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            fit: FlexFit.loose,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    // mainAxisSize removed — fills Flexible parent
                    children: [
                      _buildExportOption('Platform', 'All'),
                      _buildExportOption('Compression', 'Vorbis Q6'),
                      _buildExportOption('Total Events', '$eventCount'),
                      _buildExportOption('Est. Size', '~$estimatedSizeMb MB'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 90,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        LowerZoneColors.slotLabAccent.withValues(alpha: 0.2),
                        LowerZoneColors.slotLabAccent.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.slotLabAccent),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download, size: 28, color: LowerZoneColors.slotLabAccent),
                      const SizedBox(height: 6),
                      Text(
                        'PACKAGE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: LowerZoneColors.slotLabAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildActionButton('Build Package', Icons.inventory_2, () => _buildPackageExport(middleware)),
            ],
          ),
        ],
      ),
    );
  }

  /// Export package with all events, symbols, and contexts
  Future<void> _buildPackageExport(MiddlewareProvider? middleware) async {
    if (middleware == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No middleware provider')),
      );
      return;
    }

    final events = middleware.compositeEvents;
    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No events to export')),
      );
      return;
    }

    // Get project provider for full export
    final projectProvider = context.read<SlotLabProjectProvider>();

    // Build package JSON
    final packageData = {
      'version': '1.0',
      'timestamp': DateTime.now().toIso8601String(),
      'project': {
        'name': projectProvider.projectName,
        'symbols': projectProvider.symbols.map((s) => {
          'id': s.id,
          'name': s.name,
          'emoji': s.emoji,
          'type': s.type.name,
        }).toList(),
        'contexts': projectProvider.contexts.map((c) => {
          'id': c.id,
          'name': c.displayName,
          'type': c.type.name,
          'layerCount': c.layerCount,
        }).toList(),
      },
      'events': events.map((e) => {
        'id': e.id,
        'name': e.name,
        'stages': e.triggerStages,
        'layers': e.layers.map((l) => {
          'id': l.id,
          'name': l.name,
          'audioPath': l.audioPath,
          'volume': l.volume,
          'pan': l.pan,
          'offsetMs': l.offsetMs,
          'busId': l.busId,
        }).toList(),
      }).toList(),
      'containers': {
        'blend': middleware.blendContainers.length,
        'random': middleware.randomContainers.length,
        'sequence': middleware.sequenceContainers.length,
      },
    };

    // Convert to JSON string
    final jsonString = const JsonEncoder.withIndent('  ').convert(packageData);

    // Try to save to file
    try {
      final result = await NativeFilePicker.saveFileCompat(
        dialogTitle: 'Save Package',
        fileName: '${projectProvider.projectName.toLowerCase().replaceAll(' ', '_')}_package.json',
        allowedExtensions: ['json'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsString(jsonString);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Package saved: ${events.length} events'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Export failed: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EMPTY STATE PANELS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNoProviderPanel(String title, IconData icon, String providerName) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: LowerZoneColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: LowerZoneColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Requires $providerName',
            style: const TextStyle(
              fontSize: 11,
              color: LowerZoneColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION STRIP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Helper to get icon for DSP processor type
  IconData _dspTypeIcon(DspNodeType type) {
    return switch (type) {
      DspNodeType.eq => Icons.equalizer,
      DspNodeType.compressor => Icons.compress,
      DspNodeType.limiter => Icons.vertical_align_top,
      DspNodeType.gate => Icons.door_sliding_outlined,
      DspNodeType.expander => Icons.expand,
      DspNodeType.reverb => Icons.waves,
      DspNodeType.delay => Icons.timer,
      DspNodeType.saturation => Icons.whatshot,
      DspNodeType.deEsser => Icons.record_voice_over,
      DspNodeType.pultec => Icons.tune,
      DspNodeType.api550 => Icons.graphic_eq,
      DspNodeType.neve1073 => Icons.surround_sound,
      DspNodeType.multibandSaturation => Icons.whatshot,
      DspNodeType.haasDelay => Icons.spatial_audio_off,
      DspNodeType.stereoImager => Icons.surround_sound,
      DspNodeType.multibandStereoImager => Icons.surround_sound,
    };
  }

  Widget _buildActionStrip() {
    final slotLab = widget.slotLabProvider ?? _tryGetSlotLabProvider();
    final middleware = _tryGetMiddlewareProvider();

    final actions = switch (widget.controller.superTab) {
      SlotLabSuperTab.stages => SlotLabActions.forStages(
        onRecord: () {
          // Start recording stage events
          slotLab?.startStageRecording();
        },
        onStop: () {
          slotLab?.stopStageRecording();
        },
        onClear: () {
          slotLab?.clearStages();
        },
        onExport: () {
          // Export stages to JSON
          final stages = slotLab?.lastStages ?? [];
          if (stages.isNotEmpty) {
            // TODO: Show export dialog
          }
        },
      ),
      SlotLabSuperTab.events => SlotLabActions.forEvents(
        onAddLayer: () async {
          final selectedEvent = middleware?.selectedCompositeEvent;
          if (selectedEvent != null) {
            // Show audio picker dialog
            final audioPath = await AudioWaveformPickerDialog.show(
              context,
              title: 'Select audio for ${selectedEvent.name}',
            );
            if (audioPath != null && middleware != null) {
              // Extract filename for layer name
              final fileName = audioPath.split('/').last.split('.').first;
              // Add layer using named parameters
              middleware.addLayerToEvent(
                selectedEvent.id,
                audioPath: audioPath,
                name: fileName,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added audio layer to ${selectedEvent.name}'),
                  duration: const Duration(milliseconds: 800),
                ),
              );
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Select an event first'),
                duration: Duration(milliseconds: 800),
              ),
            );
          }
        },
        onRemove: () {
          final selectedEvent = middleware?.selectedCompositeEvent;
          if (selectedEvent != null && middleware != null) {
            // Delete the selected event (with confirmation)
            _confirmDeleteEvent(context, selectedEvent, middleware);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Select an event first'),
                duration: Duration(milliseconds: 800),
              ),
            );
          }
        },
        onDuplicate: () {
          final selectedEvent = middleware?.selectedCompositeEvent;
          if (selectedEvent != null) {
            middleware?.duplicateCompositeEvent(selectedEvent.id);
          }
        },
        onPreview: () {
          final selectedEvent = middleware?.selectedCompositeEvent;
          if (selectedEvent != null) {
            middleware?.previewCompositeEvent(selectedEvent.id);
          }
        },
      ),
      SlotLabSuperTab.mix => SlotLabActions.forMix(
        onMute: () {
          // Toggle mute on SFX bus (primary slot audio bus)
          final mixer = context.read<MixerDSPProvider>();
          mixer.toggleMute('sfx');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('SFX bus mute: ${mixer.buses.firstWhere((b) => b.id == "sfx").muted ? "ON" : "OFF"}'),
              duration: const Duration(milliseconds: 800),
            ),
          );
        },
        onSolo: () {
          // Toggle solo on SFX bus
          final mixer = context.read<MixerDSPProvider>();
          mixer.toggleSolo('sfx');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('SFX bus solo: ${mixer.buses.firstWhere((b) => b.id == "sfx").solo ? "ON" : "OFF"}'),
              duration: const Duration(milliseconds: 800),
            ),
          );
        },
        onReset: () {
          // Reset mixer to defaults
          final mixer = context.read<MixerDSPProvider>();
          mixer.reset();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mixer reset to defaults'),
              duration: Duration(milliseconds: 800),
            ),
          );
        },
        onMeters: () {
          // Show meters panel
          widget.controller.setSubTabIndex(3); // Switch to Meter sub-tab
        },
      ),
      SlotLabSuperTab.dsp => SlotLabActions.forDsp(
        onInsert: () async {
          // Show popup menu to select DSP processor type
          final RenderBox button = context.findRenderObject() as RenderBox;
          final position = button.localToGlobal(Offset.zero);

          final selected = await showMenu<DspNodeType>(
            context: context,
            position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 200, position.dy),
            items: DspNodeType.values.map((type) => PopupMenuItem<DspNodeType>(
              value: type,
              child: Row(
                children: [
                  Icon(_dspTypeIcon(type), size: 16),
                  const SizedBox(width: 8),
                  Text(type.fullName),
                ],
              ),
            )).toList(),
          );

          if (selected != null) {
            final dspChain = context.read<DspChainProvider>();
            dspChain.addNode(0, selected); // Track 0 = master bus
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added ${selected.fullName} to DSP chain'),
                duration: const Duration(milliseconds: 800),
              ),
            );
          }
        },
        onRemove: () {
          // Remove last processor from chain
          final dspChain = context.read<DspChainProvider>();
          final chain = dspChain.getChain(0); // Track 0 = master bus
          if (chain.nodes.isNotEmpty) {
            final lastNode = chain.nodes.last;
            dspChain.removeNode(0, lastNode.id);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Removed ${lastNode.name} from DSP chain'),
                duration: const Duration(milliseconds: 800),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('DSP chain is empty'),
                duration: Duration(milliseconds: 800),
              ),
            );
          }
        },
        onReorder: () {
          // Show reorder info - drag-drop reorder is available in DSP panel
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Use drag-drop in DSP panel to reorder processors'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        onCopyChain: () {
          // Copy DSP chain configuration to clipboard
          final dspChain = context.read<DspChainProvider>();
          final chain = dspChain.getChain(0);
          final chainInfo = chain.nodes.map((n) => n.type.shortName).join(' → ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('DSP Chain: ${chainInfo.isEmpty ? "(empty)" : chainInfo}'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
      SlotLabSuperTab.bake => SlotLabActions.forBake(
        onValidate: () {
          // Validate all events - check if audio paths exist
          final events = middleware?.compositeEvents ?? [];
          int valid = 0;
          int invalid = 0;
          final issues = <String>[];

          for (final event in events) {
            bool eventValid = true;
            for (final layer in event.layers) {
              if (layer.audioPath.isEmpty) {
                eventValid = false;
                issues.add('${event.name}: Layer missing audio');
              }
            }
            if (event.layers.isEmpty) {
              eventValid = false;
              issues.add('${event.name}: No layers');
            }
            if (eventValid) {
              valid++;
            } else {
              invalid++;
            }
          }

          if (events.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No events to validate'),
                duration: Duration(seconds: 2),
              ),
            );
          } else if (invalid == 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ All $valid events valid!'),
                backgroundColor: Colors.green[700],
                duration: const Duration(seconds: 2),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⚠️ $valid valid, $invalid invalid: ${issues.take(2).join(", ")}'),
                backgroundColor: Colors.orange[700],
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
        onBakeAll: () {
          // Bake all events via export provider
          final eventCount = middleware?.compositeEvents.length ?? 0;
          if (eventCount == 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No events to bake'),
                duration: Duration(milliseconds: 800),
              ),
            );
          } else {
            final exportProvider = GetIt.instance<SlotLabExportProvider>();
            exportProvider.selectAllSections();
            final result = exportProvider.export({
              'events': middleware?.compositeEvents.map((e) => e.toJson()).toList() ?? [],
              'eventCount': eventCount,
            });

            // Notify via middleware notifications
            final notif = GetIt.instance<SlotLabNotificationProvider>();
            notif.push(
              type: NotificationType.export_,
              severity: result.success ? NotificationSeverity.success : NotificationSeverity.error,
              title: result.success ? 'Export Complete' : 'Export Failed',
              body: result.success
                  ? '$eventCount events exported (${((result.byteSize ?? 0) / 1024).toStringAsFixed(1)} KB)'
                  : result.error ?? 'Unknown error',
            );

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result.success
                    ? 'Baked $eventCount events (${exportProvider.selectedFormat.name})'
                    : 'Export failed: ${result.error}'),
                duration: const Duration(seconds: 2),
              ),
            );
            // Switch to Batch Export sub-tab
            widget.controller.setSubTabIndex(0);
          }
        },
        onPackage: () {
          // Create package - show package panel
          final eventCount = middleware?.compositeEvents.length ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Creating package with $eventCount events... (Use Package panel)'),
              duration: const Duration(seconds: 2),
            ),
          );
          // Switch to Package sub-tab
          widget.controller.setSubTabIndex(2);
        },
      ),
      SlotLabSuperTab.rtpc => SlotLabActions.forMiddleware(
        onReset: null,
        onInspect: () {
          widget.controller.setRtpcSubTab(SlotLabRtpcSubTab.debugger);
        },
        onSimulate: null,
      ),
      SlotLabSuperTab.containers => SlotLabActions.forMiddleware(
        onReset: null,
        onInspect: null,
        onSimulate: null,
      ),
      SlotLabSuperTab.music => SlotLabActions.forMiddleware(
        onReset: null,
        onInspect: null,
        onSimulate: null,
      ),
      SlotLabSuperTab.logic => SlotLabActions.forMiddleware(
        onReset: () {
          middleware?.resetToDefaults();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Middleware state reset to defaults'),
              duration: Duration(milliseconds: 800),
            ),
          );
        },
        onInspect: () {
          widget.controller.setLogicSubTab(SlotLabLogicSubTab.behavior);
        },
        onSimulate: () {
          widget.controller.setLogicSubTab(SlotLabLogicSubTab.simulation);
        },
      ),
      SlotLabSuperTab.intel => SlotLabActions.forMiddleware(
        onReset: null,
        onInspect: () {
          widget.controller.setIntelSubTab(SlotLabIntelSubTab.inspector);
        },
        onSimulate: () {
          widget.controller.setIntelSubTab(SlotLabIntelSubTab.sim);
        },
      ),
      SlotLabSuperTab.monitor => SlotLabActions.forMiddleware(
        onReset: null,
        onInspect: () {
          widget.controller.setMonitorSubTab(SlotLabMonitorSubTab.debug);
        },
        onSimulate: null,
      ),
    };

    // Get stage count from provider if available
    String statusText = 'Stages: --';
    if (slotLab != null) {
      final stageCount = slotLab.lastStages.length;
      statusText = 'Stages: $stageCount';
    }

    return LowerZoneActionStrip(
      actions: actions,
      accentColor: widget.controller.accentColor,
      statusText: statusText,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════

class _TimelinePainter extends CustomPainter {
  final Color color;
  _TimelinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = LowerZoneColors.border.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Draw vertical grid lines
    for (int i = 0; i < 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Draw stage blocks
    final stages = [
      (0.0, 0.05, 'SPIN'),
      (0.1, 0.3, 'REEL'),
      (0.35, 0.1, 'STOP'),
      (0.5, 0.15, 'EVAL'),
      (0.7, 0.25, 'WIN'),
    ];

    for (int i = 0; i < stages.length; i++) {
      final start = stages[i].$1;
      final duration = stages[i].$2;
      final y = 20.0 + i * 25.0;

      final rect = Rect.fromLTWH(
        start * size.width,
        y,
        duration * size.width,
        18,
      );

      final paint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Note: _EqCurvePainter and _ReverbDecayPainter removed — replaced by FabFilter widgets

// ═══════════════════════════════════════════════════════════════════════════
// P0.3: KEYBOARD SHORTCUTS OVERLAY
// ═══════════════════════════════════════════════════════════════════════════

/// Shows keyboard shortcuts overlay dialog for SlotLab Lower Zone
class KeyboardShortcutsOverlay {
  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => const _KeyboardShortcutsDialog(),
    );
  }
}

class _KeyboardShortcutsDialog extends StatelessWidget {
  const _KeyboardShortcutsDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: LowerZoneColors.bgDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: LowerZoneColors.border),
      ),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(20),
        child: Column(
          // mainAxisSize removed — fills Flexible parent
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.keyboard, color: LowerZoneColors.textPrimary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Keyboard Shortcuts',
                  style: TextStyle(
                    color: LowerZoneColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: LowerZoneColors.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: LowerZoneColors.border, height: 1),
            const SizedBox(height: 16),

            // Super Tabs section
            _buildSection('Super Tabs', [
              ('1', 'STAGES tab'),
              ('2', 'EVENTS tab'),
              ('3', 'MIX tab'),
              ('4', 'DSP tab'),
              ('5', 'BAKE tab'),
            ]),
            const SizedBox(height: 16),

            // Sub Tabs section
            _buildSection('Sub Tabs (within STAGES)', [
              ('Q', 'Trace sub-tab'),
              ('W', 'Timeline sub-tab'),
              ('E', 'Symbols sub-tab'),
              ('R', 'Timing sub-tab'),
            ]),
            const SizedBox(height: 16),

            // General section
            _buildSection('General', [
              ('`', 'Toggle expand/collapse'),
              ('Esc', 'Close/collapse'),
              ('?', 'Show this help'),
            ]),
            const SizedBox(height: 16),

            // Slot Preview section
            _buildSection('Slot Preview', [
              ('Space', 'Spin / Stop'),
              ('1-7', 'Force outcomes (debug)'),
              ('T', 'Toggle turbo mode'),
            ]),

            const SizedBox(height: 20),
            // Footer hint
            Center(
              child: Text(
                'Press Esc or click outside to close',
                style: TextStyle(
                  color: LowerZoneColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<(String, String)> shortcuts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: LowerZoneColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...shortcuts.map((s) => _buildShortcutRow(s.$1, s.$2)),
      ],
    );
  }

  Widget _buildShortcutRow(String key, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: LowerZoneColors.border),
            ),
            child: Text(
              key,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: LowerZoneColors.textPrimary,
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            description,
            style: const TextStyle(
              color: LowerZoneColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// P2.8: FADE CURVE PAINTER
// =============================================================================

/// Custom painter for visualizing fade in/out curves on layer items
class _FadeCurvePainter extends CustomPainter {
  final double fadeInMs;
  final double fadeOutMs;
  final CrossfadeCurve fadeInCurve;
  final CrossfadeCurve fadeOutCurve;
  final Color color;

  _FadeCurvePainter({
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.fadeInCurve,
    required this.fadeOutCurve,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.4)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Background line at y = height (bottom, representing 0 volume)
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = Colors.white.withOpacity(0.1)
        ..strokeWidth = 0.5,
    );

    // Calculate fade regions as percentage of total width
    // Assume total duration is ~2000ms for visualization purposes
    const totalDurationMs = 2000.0;
    final fadeInWidth = (fadeInMs / totalDurationMs).clamp(0.0, 0.4) * size.width;
    final fadeOutWidth = (fadeOutMs / totalDurationMs).clamp(0.0, 0.4) * size.width;

    final path = Path();

    // Start from bottom-left (0 volume at start)
    path.moveTo(0, size.height);

    // Fade In curve (rise from bottom to top = 0 to 1 volume)
    if (fadeInMs > 0 && fadeInWidth > 2) {
      const steps = 20;
      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = fadeInWidth * t;
        final y = size.height - (size.height * _applyCurve(t, fadeInCurve));
        path.lineTo(x, y);
      }
    } else {
      // No fade in - instant rise to top
      path.lineTo(0, 0);
    }

    // Sustain section (flat at top = full volume)
    final sustainStartX = fadeInWidth > 0 ? fadeInWidth : 0.0;
    final sustainEndX = size.width - (fadeOutWidth > 0 ? fadeOutWidth : 0.0);
    path.lineTo(sustainStartX, 0);
    path.lineTo(sustainEndX, 0);

    // Fade Out curve (descend from top to bottom = 1 to 0 volume)
    if (fadeOutMs > 0 && fadeOutWidth > 2) {
      const steps = 20;
      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = sustainEndX + (fadeOutWidth * t);
        final y = size.height * _applyCurve(t, fadeOutCurve);
        path.lineTo(x, y);
      }
    } else {
      // No fade out - instant drop to bottom
      path.lineTo(size.width, 0);
    }

    // Close path at bottom-right
    path.lineTo(size.width, size.height);
    path.close();

    // Draw filled area
    canvas.drawPath(path, paint);

    // Draw outline
    canvas.drawPath(path, linePaint);
  }

  /// Apply curve transformation to normalized value (0-1)
  double _applyCurve(double t, CrossfadeCurve curve) {
    switch (curve) {
      case CrossfadeCurve.linear:
        return t;
      case CrossfadeCurve.log3:
      case CrossfadeCurve.equalPower:
        return math.sin(t * math.pi / 2);
      case CrossfadeCurve.log1:
        return math.log(1 + t * (math.e - 1));
      case CrossfadeCurve.sCurve:
        return (1 - math.cos(t * math.pi)) / 2;
      case CrossfadeCurve.invSCurve:
        return t < 0.5 ? 4 * t * t * t : 1 - 4 * (1 - t) * (1 - t) * (1 - t);
      case CrossfadeCurve.sine:
      case CrossfadeCurve.sinCos:
        return 0.5 - 0.5 * math.cos(t * math.pi);
      case CrossfadeCurve.exp1:
        return (math.exp(t) - 1) / (math.e - 1);
      case CrossfadeCurve.exp3:
        return (math.exp(3 * t) - 1) / (math.exp(3) - 1);
    }
  }

  @override
  bool shouldRepaint(_FadeCurvePainter oldDelegate) {
    return oldDelegate.fadeInMs != fadeInMs ||
        oldDelegate.fadeOutMs != fadeOutMs ||
        oldDelegate.fadeInCurve != fadeInCurve ||
        oldDelegate.fadeOutCurve != fadeOutCurve ||
        oldDelegate.color != color;
  }
}

/// Time ruler painter for timeline
class _TlRulerPainter extends CustomPainter {
  final double pixelsPerSecond;
  final double maxSeconds;

  const _TlRulerPainter({required this.pixelsPerSecond, required this.maxSeconds});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1.0;
    final textStyle = TextStyle(fontSize: 8, color: Colors.white38, fontFamily: 'monospace');

    double tickInterval;
    if (pixelsPerSecond >= 200) {
      tickInterval = 0.1;
    } else if (pixelsPerSecond >= 80) {
      tickInterval = 0.25;
    } else {
      tickInterval = 0.5;
    }

    for (double t = 0; t <= maxSeconds; t += tickInterval) {
      final x = t * pixelsPerSecond;
      if (x > size.width) break;

      final isMajor = (t * 1000).round() % 1000 == 0;
      final tickHeight = isMajor ? 12.0 : 6.0;

      paint.color = Colors.white.withValues(alpha: isMajor ? 0.2 : 0.08);
      canvas.drawLine(Offset(x, size.height - tickHeight), Offset(x, size.height), paint);

      if (isMajor) {
        final tp = TextPainter(
          text: TextSpan(text: '${t.toStringAsFixed(0)}s', style: textStyle),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(x + 2, 2));
      }
    }

    // Bottom border
    paint.color = Colors.white.withValues(alpha: 0.08);
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), paint);
  }

  @override
  bool shouldRepaint(_TlRulerPainter oldDelegate) =>
      oldDelegate.pixelsPerSecond != pixelsPerSecond || oldDelegate.maxSeconds != maxSeconds;
}

/// Waveform painter — renders absolute peak values (0-1) as mirrored waveform
class _TlWaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final bool isMuted;

  // Pre-allocated paints (zero allocation in paint())
  late final Paint _fillPaint;
  late final Paint _strokePaint;
  late final Paint _centerPaint;

  _TlWaveformPainter({required this.data, required this.color, this.isMuted = false}) {
    final waveColor = isMuted ? Colors.grey.withValues(alpha: 0.4) : color.withValues(alpha: 0.7);
    _fillPaint = Paint()
      ..color = (isMuted ? Colors.grey.withValues(alpha: 0.15) : color.withValues(alpha: 0.2))
      ..style = PaintingStyle.fill;
    _strokePaint = Paint()
      ..color = waveColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    _centerPaint = Paint()
      ..color = waveColor.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final centerY = size.height / 2;
    final scaleY = size.height / 2 * 0.85;
    final w = size.width.toInt();
    final samplesPerPixel = data.length / size.width;
    final len = data.length;

    // Pre-compute peaks ONCE (not 3x)
    final peaks = Float32List(w);
    for (int x = 0; x < w; x++) {
      final start = (x * samplesPerPixel).floor();
      final end = ((x + 1) * samplesPerPixel).floor().clamp(0, len);
      if (start >= len) break;
      double peak = 0.0;
      for (int i = start; i < end && i < len; i++) {
        final s = data[i].abs();
        if (s > peak) peak = s > 1.0 ? 1.0 : s;
      }
      peaks[x] = peak;
    }

    // Fill path (mirrored waveform)
    final fillPath = Path();
    fillPath.moveTo(0, centerY);
    for (int x = 0; x < w; x++) {
      fillPath.lineTo(x.toDouble(), centerY - peaks[x] * scaleY);
    }
    for (int x = w - 1; x >= 0; x--) {
      fillPath.lineTo(x.toDouble(), centerY + peaks[x] * scaleY);
    }
    fillPath.close();
    canvas.drawPath(fillPath, _fillPaint);

    // Stroke path (vertical bars)
    final strokePath = Path();
    for (int x = 0; x < w; x++) {
      final y1 = centerY - peaks[x] * scaleY;
      final y2 = centerY + peaks[x] * scaleY;
      if (x == 0) strokePath.moveTo(0, y1);
      strokePath.lineTo(x.toDouble(), y1);
      strokePath.lineTo(x.toDouble(), y2);
    }
    canvas.drawPath(strokePath, _strokePaint);

    // Center line
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), _centerPaint);
  }

  @override
  bool shouldRepaint(_TlWaveformPainter oldDelegate) =>
      !identical(oldDelegate.data, data) || oldDelegate.color != color || oldDelegate.isMuted != isMuted;
}

/// Grid line painter for track backgrounds
class _TlGridPainter extends CustomPainter {
  final double pixelsPerSecond;
  final double maxSeconds;

  const _TlGridPainter({required this.pixelsPerSecond, required this.maxSeconds});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;

    for (double t = 0; t <= maxSeconds; t += 1.0) {
      final x = t * pixelsPerSecond;
      if (x > size.width) break;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_TlGridPainter oldDelegate) =>
      oldDelegate.pixelsPerSecond != pixelsPerSecond;
}
