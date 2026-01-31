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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:provider/provider.dart';

import 'slotlab_lower_zone_controller.dart';
import 'lower_zone_types.dart';
import 'lower_zone_context_bar.dart';
import 'lower_zone_action_strip.dart';
import '../../providers/slot_lab_provider.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../providers/middleware_provider.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../providers/mixer_dsp_provider.dart';
import '../../src/rust/native_ffi.dart';
import '../../models/slot_audio_events.dart' show SlotCompositeEvent, SlotEventLayer;
import '../../models/middleware_models.dart' show ActionType, CrossfadeCurve;
import '../../models/slot_lab_models.dart' show SymbolDefinition, SymbolType;
import '../../services/audio_playback_service.dart';
import '../slot_lab/stage_trace_widget.dart';
import '../slot_lab/event_log_panel.dart';
import '../slot_lab/bus_hierarchy_panel.dart';
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
  });

  @override
  State<SlotLabLowerZoneWidget> createState() => _SlotLabLowerZoneWidgetState();
}

class _SlotLabLowerZoneWidgetState extends State<SlotLabLowerZoneWidget> {
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
    super.dispose();
  }

  /// P2.7: Handle keyboard shortcuts for layer list (Ctrl+C/V, Delete)
  KeyEventResult _handleLayerListKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

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
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: kLowerZoneAnimationDuration,
      height: widget.controller.totalHeight,
      decoration: const BoxDecoration(
        color: LowerZoneColors.bgDeep,
        border: Border(
          top: BorderSide(color: LowerZoneColors.border, width: 1),
        ),
      ),
      clipBehavior: Clip.hardEdge, // Prevent visual overflow
      child: Column(
        // NOTE: Do NOT use mainAxisSize.min — AnimatedContainer has fixed height
        // and we want Column to fill it completely
        children: [
          // Resize handle (fixed: 4px)
          _buildResizeHandle(),
          // Context bar (fixed: 60px) with shortcuts help button
          Row(
            children: [
              Expanded(
                child: LowerZoneContextBar(
                  superTabLabels: SlotLabSuperTab.values.map((t) => t.label).toList(),
                  superTabIcons: SlotLabSuperTab.values.map((t) => t.icon).toList(),
                  selectedSuperTab: widget.controller.superTab.index,
                  subTabLabels: widget.controller.subTabLabels,
                  selectedSubTab: widget.controller.currentSubTabIndex,
                  accentColor: widget.controller.accentColor,
                  isExpanded: widget.controller.isExpanded,
                  onSuperTabSelected: widget.controller.setSuperTabIndex,
                  onSubTabSelected: widget.controller.setSubTabIndex,
                  onToggle: widget.controller.toggle,
                ),
              ),
              // P0.3: Keyboard shortcuts help button
              _buildShortcutsHelpButton(),
            ],
          ),
          // Content panel (only when expanded)
          if (widget.controller.isExpanded)
            Expanded(
              child: Column(
                // NOTE: Do NOT use mainAxisSize.min here — this Column is inside
                // Expanded and needs to fill available space for inner Expanded to work
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

  /// P0.3: Keyboard shortcuts help button
  Widget _buildShortcutsHelpButton() {
    return Tooltip(
      message: 'Keyboard Shortcuts (?)',
      child: GestureDetector(
        onTap: () => KeyboardShortcutsOverlay.show(context),
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(right: 8, top: 2),
          decoration: BoxDecoration(
            color: LowerZoneColors.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: LowerZoneColors.border),
          ),
          child: const Center(
            child: Text(
              '?',
              style: TextStyle(
                color: LowerZoneColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
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
          // Grid dropdown (currently UI-only, future: connect to provider)
          _buildSpinDropdown('Grid', _selectedGrid,
              ['5×3', '5×4', '6×4', 'Custom'],
              (v) => setState(() => _selectedGrid = v)),
          const Spacer(),
          // Spin button
          _buildSpinButton(),
          const SizedBox(width: 8),
          // P0.3: Play/Pause/Stop controls
          _buildPlaybackControls(),
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
  Widget _buildPlaybackControls() {
    final provider = widget.slotLabProvider ?? _tryGetSlotLabProvider();
    if (provider == null) {
      return _buildPauseButtonDisabled();
    }

    final isPlaying = provider.isPlayingStages;
    final isPaused = provider.isPaused;

    return Row(
      // mainAxisSize removed — fills Flexible parent
      children: [
        // Play/Pause toggle button
        Tooltip(
          message: isPaused ? 'Resume (Space)' : (isPlaying ? 'Pause (Space)' : 'No active playback'),
          child: GestureDetector(
            onTap: () {
              if (isPaused) {
                widget.onResume?.call();
              } else if (isPlaying) {
                widget.onPause?.call();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isPlaying || isPaused
                    ? (isPaused
                        ? LowerZoneColors.warning.withValues(alpha: 0.2)
                        : LowerZoneColors.success.withValues(alpha: 0.2))
                    : LowerZoneColors.bgSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isPlaying || isPaused
                      ? (isPaused ? LowerZoneColors.warning : LowerZoneColors.success)
                      : LowerZoneColors.border,
                ),
              ),
              child: Row(
                // mainAxisSize removed — fills Flexible parent
                children: [
                  Icon(
                    isPaused ? Icons.play_arrow : Icons.pause,
                    size: 14,
                    color: isPlaying || isPaused
                        ? (isPaused ? LowerZoneColors.warning : LowerZoneColors.success)
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
            onTap: isPlaying || isPaused ? widget.onStop : null,
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
    switch (widget.controller.superTab) {
      case SlotLabSuperTab.stages:
        return _buildStagesContent();
      case SlotLabSuperTab.events:
        return _buildEventsContent();
      case SlotLabSuperTab.mix:
        return _buildMixContent();
      case SlotLabSuperTab.dsp:
        return _buildDspContent();
      case SlotLabSuperTab.bake:
        return _buildBakeContent();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGES CONTENT — Integrated panels
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStagesContent() {
    final subTab = widget.controller.state.stagesSubTab;
    return switch (subTab) {
      SlotLabStagesSubTab.trace => _buildTracePanel(),
      SlotLabStagesSubTab.timeline => _buildTimelinePanel(),
      SlotLabStagesSubTab.symbols => _buildSymbolsPanel(),
      SlotLabStagesSubTab.timing => _buildProfilerPanel(),
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

  Widget _buildTimelinePanel() => _buildCompactEventTimeline();
  Widget _buildSymbolsPanel() => _buildCompactSymbolsPanel();
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
    };
  }

  Widget _buildFolderPanel() => _buildCompactEventFolder();
  Widget _buildEditorPanel() => _buildCompactCompositeEditor();

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
      SlotLabMixSubTab.buses => LayoutBuilder(
        builder: (context, constraints) => BusHierarchyPanel(
          height: constraints.maxHeight.isFinite ? constraints.maxHeight : 250,
        ),
      ),
      SlotLabMixSubTab.sends => LayoutBuilder(
        builder: (context, constraints) => AuxSendsPanel(
          height: constraints.maxHeight.isFinite ? constraints.maxHeight : 250,
        ),
      ),
      SlotLabMixSubTab.pan => _buildPanPanel(),
      SlotLabMixSubTab.meter => _buildMeterPanel(),
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
    };
  }

  Widget _buildChainPanel() => _buildCompactDspChain();

  /// FabFilter Pro-Q style EQ Panel
  Widget _buildFabFilterEqPanel() {
    return const FabFilterEqPanel(trackId: 0);
  }

  /// FabFilter Pro-C style Compressor Panel
  Widget _buildFabFilterCompressorPanel() {
    return const FabFilterCompressorPanel(trackId: 0);
  }

  /// FabFilter Pro-R style Reverb Panel
  Widget _buildFabFilterReverbPanel() {
    return const FabFilterReverbPanel(trackId: 0);
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
                  color: Color(0xFF40FF90),
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
                        Icon(Icons.check_circle, color: Color(0xFF40FF90)),
                        SizedBox(width: 8),
                        Text('Git repository initialized'),
                      ],
                    ),
                    backgroundColor: const Color(0xFF1A1A20),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Initialize Repository'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF40FF90).withValues(alpha: 0.2),
              foregroundColor: const Color(0xFF40FF90),
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

  /// P2.5: Compact Event Timeline — Connected to SlotLabProvider.lastStages
  Widget _buildCompactEventTimeline() {
    final provider = widget.slotLabProvider ?? _tryGetSlotLabProvider();
    final stages = provider?.lastStages ?? [];

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // mainAxisSize removed — fills Flexible parent
        children: [
          // Header row (compact)
          Row(
            children: [
              _buildPanelHeader('EVENT TIMELINE', Icons.view_timeline),
              const Spacer(),
              Text(
                stages.isEmpty ? 'No stages' : '${stages.length} stages',
                style: TextStyle(
                  fontSize: 10,
                  color: stages.isEmpty ? LowerZoneColors.textMuted : LowerZoneColors.slotLabAccent,
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
              child: stages.isEmpty
                  ? Center(
                      child: Text(
                        'Spin to see stages',
                        style: TextStyle(fontSize: 11, color: LowerZoneColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(4),
                      shrinkWrap: true,
                      itemCount: stages.length,
                      itemBuilder: (context, index) {
                        final stage = stages[index];
                        return _buildStageTimelineItem(stage, index);
                      },
                    ),
            ),
          ),
          const SizedBox(height: 6),
          // Time markers (compact)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTimelineMarker('0', true),
              _buildTimelineMarker('500', false),
              _buildTimelineMarker('1000', false),
              _buildTimelineMarker('1500', false),
              _buildTimelineMarker('2000', false),
            ],
          ),
        ],
      ),
    );
  }

  /// P2.5: Build single stage item for timeline
  Widget _buildStageTimelineItem(dynamic stage, int index) {
    // Stage is a map with 'stage_type', 'delay_ms', etc.
    final stageType = stage['stage_type'] ?? 'UNKNOWN';
    final delayMs = stage['delay_ms'] ?? 0;

    // Color coding by stage type
    Color stageColor = LowerZoneColors.slotLabAccent;
    if (stageType.toString().contains('WIN')) {
      stageColor = LowerZoneColors.success;
    } else if (stageType.toString().contains('REEL')) {
      stageColor = const Color(0xFF40C8FF);
    } else if (stageType.toString().contains('FEATURE')) {
      stageColor = const Color(0xFFFF9040);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: stageColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: stageColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: stageColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              stageType.toString(),
              style: TextStyle(fontSize: 9, color: stageColor, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${delayMs}ms',
            style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineMarker(String label, bool isCurrent) {
    return Column(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isCurrent ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            color: isCurrent ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted,
          ),
        ),
      ],
    );
  }

  /// P2.6: Compact Symbols Panel — Connected to MiddlewareProvider for symbol-to-sound mapping
  Widget _buildCompactSymbolsPanel() {
    // Use SlotLabProjectProvider for symbol definitions
    return Consumer<SlotLabProjectProvider>(
      builder: (context, projectProvider, _) {
        final symbols = projectProvider.symbols;
        final symbolAudio = projectProvider.symbolAudio;

        // Count symbols with any audio assignment
        final mappedSymbolIds = symbolAudio.map((a) => a.symbolId).toSet();
        final mappedCount = symbols.where((s) => mappedSymbolIds.contains(s.id)).length;

        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // mainAxisSize removed — fills Flexible parent
            children: [
              // Header (compact)
              Row(
                children: [
                  _buildPanelHeader('SYMBOL AUDIO', Icons.casino),
                  const Spacer(),
                  Text(
                    '$mappedCount/${symbols.length} mapped',
                    style: TextStyle(
                      fontSize: 10,
                      color: mappedCount > 0 ? LowerZoneColors.success : LowerZoneColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Grid (flexible)
              Flexible(
                fit: FlexFit.loose,
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 1.5,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: symbols.length,
                  itemBuilder: (context, index) {
                    final symbol = symbols[index];
                    final hasAudio = mappedSymbolIds.contains(symbol.id);
                    final audioCount = symbolAudio.where((a) => a.symbolId == symbol.id).length;
                    return _buildSymbolCard(symbol, hasAudio, audioCount);
                  },
                ),
              ),
              const SizedBox(height: 6),
              // Help text (compact)
              Row(
                children: [
                  Text(
                    'Drop audio to assign • ',
                    style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
                  ),
                  GestureDetector(
                    onTap: () => projectProvider.addSymbol(SymbolDefinition(
                      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                      name: 'New Symbol',
                      emoji: '🎰',
                      type: SymbolType.low,
                    )),
                    child: Text(
                      '+ Add Symbol',
                      style: TextStyle(
                        fontSize: 9,
                        color: LowerZoneColors.slotLabAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSymbolCard(SymbolDefinition symbol, bool hasAudio, int audioCount) {
    // Icon based on symbol type
    IconData symbolIcon;
    switch (symbol.type) {
      case SymbolType.wild:
        symbolIcon = Icons.star;
      case SymbolType.scatter:
        symbolIcon = Icons.scatter_plot;
      case SymbolType.bonus:
        symbolIcon = Icons.card_giftcard;
      case SymbolType.high:
      case SymbolType.highPay:
        symbolIcon = Icons.diamond;
      case SymbolType.mediumPay:
        symbolIcon = Icons.square;
      case SymbolType.multiplier:
        symbolIcon = Icons.close;
      case SymbolType.collector:
        symbolIcon = Icons.monetization_on;
      case SymbolType.mystery:
        symbolIcon = Icons.help;
      case SymbolType.low:
      case SymbolType.lowPay:
        symbolIcon = Icons.casino;
      case SymbolType.custom:
        symbolIcon = Icons.extension;
    }

    return Tooltip(
      message: '${symbol.name}\nContexts: ${symbol.contexts.join(", ")}\n${hasAudio ? "$audioCount audio assigned" : "No audio"}',
      child: Container(
        decoration: BoxDecoration(
          color: hasAudio
              ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.1)
              : LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: hasAudio ? LowerZoneColors.slotLabAccent : LowerZoneColors.border,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Emoji or icon
            Text(
              symbol.emoji,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 2),
            Text(
              symbol.name.length > 8 ? '${symbol.name.substring(0, 8)}…' : symbol.name,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: hasAudio ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (hasAudio) ...[
              const SizedBox(height: 1),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.volume_up, size: 8, color: LowerZoneColors.success),
                  const SizedBox(width: 2),
                  Text(
                    '$audioCount',
                    style: TextStyle(fontSize: 8, color: LowerZoneColors.success),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
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

    // Sort categories alphabetically
    final sortedCategories = categoryMap.keys.toList()..sort();

    // Filter events based on selected category
    final filteredEvents = _selectedCategory == 'all'
        ? events
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
    debugPrint('[SlotLab] Event JSON:\n$json');
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
    debugPrint('[SlotLab] Audio paths for ${event.name}:\n$paths');
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
    switch (curve) {
      case CrossfadeCurve.linear:
        return 'Lin';
      case CrossfadeCurve.equalPower:
        return 'EP';
      case CrossfadeCurve.sCurve:
        return 'S';
      case CrossfadeCurve.sinCos:
        return 'SC';
    }
  }

  /// P2.8: Get display name for curve type
  String _getCurveDisplayName(CrossfadeCurve curve) {
    switch (curve) {
      case CrossfadeCurve.linear:
        return 'Linear';
      case CrossfadeCurve.equalPower:
        return 'Equal Power';
      case CrossfadeCurve.sCurve:
        return 'S-Curve';
      case CrossfadeCurve.sinCos:
        return 'Sin/Cos';
    }
  }

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
    debugPrint('[SlotLab] Exporting stems: ${_selectedStemBusIds.join(', ')}');
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
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Package',
        fileName: '${projectProvider.projectName.toLowerCase().replaceAll(' ', '_')}_package.json',
        type: FileType.custom,
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
            debugPrint('[SlotLab] Exporting ${stages.length} stages...');
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
          if (selectedEvent != null && selectedEvent.layers.isNotEmpty) {
            // Remove last layer
            middleware?.removeLayerFromEvent(selectedEvent.id, selectedEvent.layers.last.id);
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
          // Bake all events - show export panel
          final eventCount = middleware?.compositeEvents.length ?? 0;
          if (eventCount == 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No events to bake'),
                duration: Duration(milliseconds: 800),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Baking $eventCount events... (Use Batch Export panel)'),
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
      case CrossfadeCurve.equalPower:
        return math.sin(t * math.pi / 2);
      case CrossfadeCurve.sCurve:
        return (1 - math.cos(t * math.pi)) / 2;
      case CrossfadeCurve.sinCos:
        // Smooth sine-based curve
        return 0.5 - 0.5 * math.cos(t * math.pi);
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
