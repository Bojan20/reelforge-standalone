// SlotLab Lower Zone Widget
//
// Complete Lower Zone for SlotLab section with:
// - Context bar (Super-tabs + Sub-tabs)
// - Spin Control Bar (Outcome, Volatility, Timing, Grid)
// - Content panel (switches based on current tab)
// - Action strip (context-aware actions)
// - Resizable height
// - Integrated SlotLab panels (StageTrace, EventLog, BusHierarchy, Profiler)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'slotlab_lower_zone_controller.dart';
import 'lower_zone_types.dart';
import 'lower_zone_context_bar.dart';
import 'lower_zone_action_strip.dart';
import '../../providers/slot_lab_provider.dart';
import '../../providers/middleware_provider.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../providers/mixer_dsp_provider.dart';
import '../../src/rust/native_ffi.dart';
import '../../models/slot_audio_events.dart' show SlotCompositeEvent, SlotEventLayer;
import '../../models/middleware_models.dart' show ActionType;
import '../../services/audio_playback_service.dart';
import '../slot_lab/stage_trace_widget.dart';
import '../slot_lab/event_log_panel.dart';
import '../slot_lab/bus_hierarchy_panel.dart';
import '../slot_lab/profiler_panel.dart';
import '../slot_lab/aux_sends_panel.dart';
import '../slot_lab/slot_automation_panel.dart';
import '../fabfilter/fabfilter.dart';
import 'realtime_bus_meters.dart';
import 'export_panels.dart';

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
    super.dispose();
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
          // Context bar (fixed: 60px)
          LowerZoneContextBar(
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
          mainAxisSize: MainAxisSize.min,
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
      mainAxisSize: MainAxisSize.min,
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
                mainAxisSize: MainAxisSize.min,
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
    };
  }

  /// P2.1: Functional batch export panel for SlotLab events
  Widget _buildExportPanel() => const SlotLabBatchExportPanel();

  Widget _buildStemsPanel() => _buildCompactStemsPanel();
  Widget _buildVariationsPanel() => _buildCompactVariationsPanel();
  Widget _buildPackagePanel() => _buildCompactPackagePanel();

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
        mainAxisSize: MainAxisSize.min,
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
    final middleware = _tryGetMiddlewareProvider();

    // Standard slot symbols
    final symbols = ['WILD', 'SCATTER', 'BONUS', '7', 'BAR', 'CHERRY', 'BELL', 'ORANGE'];

    // Check which symbols have events mapped (via stage SYMBOL_LAND_xxx)
    final mappedSymbols = <String>{};
    if (middleware != null) {
      for (final event in middleware.compositeEvents) {
        for (final stage in event.triggerStages) {
          if (stage.toUpperCase().startsWith('SYMBOL_LAND_')) {
            final symbol = stage.substring('SYMBOL_LAND_'.length);
            mappedSymbols.add(symbol.toUpperCase());
          }
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header (compact)
          Row(
            children: [
              _buildPanelHeader('SYMBOL AUDIO', Icons.casino),
              const Spacer(),
              Text(
                '${mappedSymbols.length}/${symbols.length} mapped',
                style: TextStyle(
                  fontSize: 10,
                  color: mappedSymbols.isNotEmpty ? LowerZoneColors.success : LowerZoneColors.textMuted,
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
                final hasAudio = mappedSymbols.contains(symbol);
                return _buildSymbolCard(symbol, hasAudio);
              },
            ),
          ),
          const SizedBox(height: 6),
          // Help text (compact)
          Text(
            'Map symbols via SYMBOL_LAND_xxx stages',
            style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildSymbolCard(String symbol, bool hasAudio) {
    // Symbol-specific icons
    IconData symbolIcon = Icons.casino;
    if (symbol == 'WILD') symbolIcon = Icons.star;
    if (symbol == 'SCATTER') symbolIcon = Icons.scatter_plot;
    if (symbol == 'BONUS') symbolIcon = Icons.card_giftcard;
    if (symbol == '7') symbolIcon = Icons.filter_7;
    if (symbol == 'CHERRY') symbolIcon = Icons.local_dining;
    if (symbol == 'BELL') symbolIcon = Icons.notifications;

    return Container(
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
          Icon(
            symbolIcon,
            size: 20,
            color: hasAudio ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted,
          ),
          const SizedBox(height: 4),
          Text(
            symbol,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: hasAudio ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted,
            ),
          ),
          if (hasAudio) ...[
            const SizedBox(height: 2),
            Icon(Icons.volume_up, size: 10, color: LowerZoneColors.success),
          ],
        ],
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
        mainAxisSize: MainAxisSize.min,
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
                    mainAxisSize: MainAxisSize.min,
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
  Widget _buildCompactCompositeEditor() {
    final middleware = _tryGetMiddlewareProvider();
    if (middleware == null) {
      return _buildNoProviderPanel('Composite Editor', Icons.edit, 'MiddlewareProvider');
    }

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
        mainAxisSize: MainAxisSize.min,
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
                      mainAxisSize: MainAxisSize.min,
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
                        // Layers list (flexible)
                        Flexible(
                          fit: FlexFit.loose,
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
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// SL-P1.1 FIX: Interactive layer item with editable parameters
  Widget _buildInteractiveLayerItem({
    required String eventId,
    required SlotEventLayer layer,
    required int index,
  }) {
    final audioName = layer.audioPath.split('/').last;
    final middleware = context.read<MiddlewareProvider>();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: name, mute, play, delete
          Row(
            children: [
              Icon(Icons.drag_indicator, size: 12, color: LowerZoneColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'L${index + 1}: $audioName',
                  style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
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
              // Delete
              GestureDetector(
                onTap: () => middleware.removeLayerFromEvent(eventId, layer.id),
                child: const Icon(Icons.close, size: 14, color: LowerZoneColors.textMuted),
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
        ],
      ),
    );
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
        mainAxisSize: MainAxisSize.min,
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
        mainAxisSize: MainAxisSize.min,
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
        mainAxisSize: MainAxisSize.min,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPanelHeader('SIGNAL CHAIN', Icons.link),
          const SizedBox(height: 8),
          Flexible(
            fit: FlexFit.loose,
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
        mainAxisSize: MainAxisSize.min,
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
          mainAxisSize: MainAxisSize.min,
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
    final randomContainers = middleware?.randomContainers ?? [];
    final variationCount = randomContainers.fold<int>(0, (sum, c) => sum + c.children.length);

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildPanelHeader('BATCH VARIATIONS', Icons.auto_awesome),
              const Spacer(),
              Text(
                '$variationCount variations',
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildVariationSlider('Pitch', '±10%', 0.1),
                      _buildVariationSlider('Volume', '±5%', 0.05),
                      _buildVariationSlider('Pan', '±20%', 0.2),
                      _buildVariationSlider('Delay', '±50ms', 0.15),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Count', style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
                      const SizedBox(height: 4),
                      Text('$variationCount', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: LowerZoneColors.slotLabAccent)),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () {},
                        child: Icon(Icons.refresh, size: 16, color: LowerZoneColors.textMuted),
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
              _buildActionButton('Generate', Icons.auto_awesome, () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVariationSlider(String label, String range, double value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 50, child: Text(label, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textMuted))),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: LowerZoneColors.bgDeepest,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.center,
                widthFactor: value.clamp(0.1, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: LowerZoneColors.slotLabAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(range, style: TextStyle(fontSize: 9, color: LowerZoneColors.slotLabAccent)),
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
        mainAxisSize: MainAxisSize.min,
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
                    mainAxisSize: MainAxisSize.min,
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
              _buildActionButton('Build Package', Icons.inventory_2, () {}),
            ],
          ),
        ],
      ),
    );
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
        onAddLayer: () {
          final selectedEvent = middleware?.selectedCompositeEvent;
          if (selectedEvent != null) {
            // Show audio picker dialog to add layer
            debugPrint('[SlotLab] Add layer to event: ${selectedEvent.name}');
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
          // Toggle mute on selected bus
          debugPrint('[SlotLab] Mix: Mute toggled');
        },
        onSolo: () {
          // Toggle solo on selected bus
          debugPrint('[SlotLab] Mix: Solo toggled');
        },
        onReset: () {
          // Reset mixer to defaults
          debugPrint('[SlotLab] Mix: Reset to defaults');
        },
        onMeters: () {
          // Show meters panel
          widget.controller.setSubTabIndex(3); // Switch to Meter sub-tab
        },
      ),
      SlotLabSuperTab.dsp => SlotLabActions.forDsp(
        onInsert: () {
          // Insert DSP processor
          debugPrint('[SlotLab] DSP: Insert processor');
        },
        onRemove: () {
          // Remove selected processor
          debugPrint('[SlotLab] DSP: Remove processor');
        },
        onReorder: () {
          // Enter reorder mode
          debugPrint('[SlotLab] DSP: Reorder mode');
        },
        onCopyChain: () {
          // Copy DSP chain
          debugPrint('[SlotLab] DSP: Copy chain');
        },
      ),
      SlotLabSuperTab.bake => SlotLabActions.forBake(
        onValidate: () {
          // Validate all events
          final eventCount = middleware?.compositeEvents.length ?? 0;
          debugPrint('[SlotLab] Bake: Validating $eventCount events...');
        },
        onBakeAll: () {
          // Bake all events
          debugPrint('[SlotLab] Bake: Baking all events...');
        },
        onPackage: () {
          // Create package
          debugPrint('[SlotLab] Bake: Creating package...');
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
