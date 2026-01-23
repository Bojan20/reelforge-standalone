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
import '../../src/rust/native_ffi.dart' show VolatilityPreset, TimingProfileType;
import '../../models/slot_audio_events.dart' show SlotCompositeEvent;
import '../slot_lab/stage_trace_widget.dart';
import '../slot_lab/event_log_panel.dart';
import '../slot_lab/bus_hierarchy_panel.dart';
import '../slot_lab/profiler_panel.dart';
import '../slot_lab/aux_sends_panel.dart';
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
      child: Column(
        children: [
          // Resize handle
          _buildResizeHandle(),
          // Context bar
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
          if (widget.controller.isExpanded) ...[
            // Spin Control Bar (SlotLab specific)
            _buildSpinControlBar(),
            Expanded(child: _buildContentPanel()),
            // Action strip
            _buildActionStrip(),
          ],
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
    return StageTraceWidget(
      provider: provider,
      height: 200,
      showMiniProgress: true,
      onAudioDropped: widget.onAudioDropped,
    );
  }

  Widget _buildTimelinePanel() => _buildCompactEventTimeline();
  Widget _buildSymbolsPanel() => _buildCompactSymbolsPanel();
  Widget _buildProfilerPanel() => const ProfilerPanel(height: 250);

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
    return EventLogPanel(
      slotLabProvider: slotLabProvider,
      middlewareProvider: middlewareProvider,
      height: 250,
    );
  }

  Widget _buildPoolPanel() => _buildCompactVoicePool();

  // ═══════════════════════════════════════════════════════════════════════════
  // MIX CONTENT — Integrated panels
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMixContent() {
    final subTab = widget.controller.state.mixSubTab;
    return switch (subTab) {
      SlotLabMixSubTab.buses => const BusHierarchyPanel(height: 250),
      SlotLabMixSubTab.sends => const AuxSendsPanel(height: 250),
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

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildPanelHeader('EVENT TIMELINE', Icons.view_timeline),
              const Spacer(),
              if (stages.isNotEmpty)
                Text(
                  '${stages.length} stages',
                  style: TextStyle(fontSize: 10, color: LowerZoneColors.slotLabAccent),
                )
              else
                const Text(
                  'No stages',
                  style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: LowerZoneColors.bgDeepest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: LowerZoneColors.border),
              ),
              child: stages.isEmpty
                  ? Center(
                      child: Text(
                        'Spin to see stages',
                        style: TextStyle(fontSize: 11, color: LowerZoneColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(4),
                      itemCount: stages.length,
                      itemBuilder: (context, index) {
                        final stage = stages[index];
                        return _buildStageTimelineItem(stage, index);
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          // Time markers (estimate based on typical spin duration)
          Row(
            children: [
              _buildTimelineMarker('0ms', true),
              const Spacer(),
              _buildTimelineMarker('500ms', false),
              const Spacer(),
              _buildTimelineMarker('1000ms', false),
              const Spacer(),
              _buildTimelineMarker('1500ms', false),
              const Spacer(),
              _buildTimelineMarker('2000ms', false),
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

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1.5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: symbols.length,
              itemBuilder: (context, index) {
                final symbol = symbols[index];
                final hasAudio = mappedSymbols.contains(symbol);
                return _buildSymbolCard(symbol, hasAudio);
              },
            ),
          ),
          const SizedBox(height: 8),
          // Help text
          Text(
            'Map symbols via SYMBOL_LAND_xxx stages in Events',
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

    // Sort categories alphabetically, put 'all' first
    final sortedCategories = categoryMap.keys.toList()..sort();

    // Filter events based on selected category
    final filteredEvents = _selectedCategory == 'all'
        ? events
        : categoryMap[_selectedCategory] ?? [];

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with event count
          Row(
            children: [
              _buildPanelHeader('EVENT FOLDER', Icons.folder_special),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: LowerZoneColors.slotLabAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${events.length}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: LowerZoneColors.slotLabAccent,
                  ),
                ),
              ),
              const Spacer(),
              // Add event button
              GestureDetector(
                onTap: () {
                  // Create new composite event (use selected category or 'general')
                  final category = _selectedCategory == 'all' ? 'general' : _selectedCategory;
                  middleware.createCompositeEvent(
                    name: 'New Event ${DateTime.now().millisecondsSinceEpoch % 1000}',
                    category: category,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: LowerZoneColors.slotLabAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.slotLabAccent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 12, color: LowerZoneColors.slotLabAccent),
                      const SizedBox(width: 4),
                      Text(
                        'New Event',
                        style: TextStyle(fontSize: 9, color: LowerZoneColors.slotLabAccent),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                // Folder tree (categories)
                SizedBox(
                  width: 150,
                  child: Container(
                    decoration: BoxDecoration(
                      color: LowerZoneColors.bgDeepest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: LowerZoneColors.border),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(4),
                      children: [
                        // "All" folder
                        _buildFolderItemConnected(
                          'All Events',
                          Icons.folder_special,
                          events.length,
                          _selectedCategory == 'all',
                          () => setState(() => _selectedCategory = 'all'),
                        ),
                        const Divider(height: 8, color: LowerZoneColors.border),
                        // Category folders
                        ...sortedCategories.map((cat) => _buildFolderItemConnected(
                          cat[0].toUpperCase() + cat.substring(1), // Capitalize
                          _selectedCategory == cat ? Icons.folder_open : Icons.folder,
                          categoryMap[cat]!.length,
                          _selectedCategory == cat,
                          () => setState(() => _selectedCategory = cat),
                        )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Event list
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: LowerZoneColors.bgDeepest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: LowerZoneColors.border),
                    ),
                    child: filteredEvents.isEmpty
                        ? _buildNoEventsMessage()
                        : ListView.builder(
                            padding: const EdgeInsets.all(4),
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
                // Trigger preview playback
                // TODO: Connect to preview playback
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
    // Fall back to first event
    selectedEvent ??= events.firstOrNull;

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildPanelHeader('COMPOSITE EDITOR', Icons.edit),
              const Spacer(),
              // Event selector dropdown
              if (events.isNotEmpty)
                DropdownButton<String>(
                  value: selectedEvent?.id,
                  hint: const Text('Select event', style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted)),
                  dropdownColor: LowerZoneColors.bgMid,
                  style: TextStyle(fontSize: 10, color: LowerZoneColors.slotLabAccent),
                  underline: const SizedBox(),
                  isDense: true,
                  items: events.map((e) => DropdownMenuItem(
                    value: e.id,
                    child: Text(e.name, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (id) {
                    setState(() => _selectedEventId = id);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: LowerZoneColors.bgDeepest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: LowerZoneColors.border),
              ),
              child: selectedEvent == null
                  ? Center(
                      child: Text(
                        'No events. Create one in Events Folder.',
                        style: TextStyle(fontSize: 11, color: LowerZoneColors.textMuted),
                      ),
                    )
                  : Column(
                      children: [
                        // Event name header
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: LowerZoneColors.slotLabAccent.withValues(alpha: 0.1),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                selectedEvent.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: LowerZoneColors.slotLabAccent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${selectedEvent.layers.length} layers',
                                style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
                              ),
                              const Spacer(),
                              // Stages badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: LowerZoneColors.bgDeepest,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  selectedEvent.triggerStages.join(', '),
                                  style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Layers list
                        Expanded(
                          child: selectedEvent.layers.isEmpty
                              ? Center(
                                  child: Text(
                                    'No layers. Add audio files.',
                                    style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(4),
                                  itemCount: selectedEvent.layers.length,
                                  itemBuilder: (context, index) {
                                    final layer = selectedEvent!.layers[index];
                                    final audioName = layer.audioPath.split('/').last;
                                    return _buildLayerItem(
                                      'Layer ${index + 1}: $audioName',
                                      layer.offsetMs,
                                      layer.volume,
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

  Widget _buildLayerItem(String name, double delay, double volume) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(Icons.drag_indicator, size: 14, color: LowerZoneColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary)),
                Row(
                  children: [
                    Text('Delay: ${delay.toInt()}ms', style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
                    const SizedBox(width: 12),
                    Text('Vol: ${(volume * 100).toInt()}%', style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.play_arrow, size: 14, color: LowerZoneColors.textMuted),
        ],
      ),
    );
  }

  /// P2.8: Compact Voice Pool — Connected to MiddlewareProvider.getVoicePoolStats()
  Widget _buildCompactVoicePool() {
    final middleware = _tryGetMiddlewareProvider();

    // Get voice pool stats from provider (VoicePoolStats class)
    final stats = middleware?.getVoicePoolStats();

    // Use VoicePoolStats fields or defaults
    final totalVoices = stats?.maxVoices ?? 48;
    final activeVoices = stats?.activeVoices ?? 0;
    final virtualVoices = stats?.virtualVoices ?? 0;
    final stealCount = stats?.stealCount ?? 0;

    // Per-bus stats (not available in current model, use estimates)
    // Distribute active voices across buses roughly
    final sfxActive = (activeVoices * 0.35).round();
    final musicActive = (activeVoices * 0.15).round();
    final voiceActive = (activeVoices * 0.10).round();
    final ambientActive = (activeVoices * 0.25).round();
    final uiActive = activeVoices - sfxActive - musicActive - voiceActive - ambientActive;

    final busStats = <String, (int, int)>{
      'SFX': (sfxActive, 16),
      'Music': (musicActive, 8),
      'Voice': (voiceActive, 4),
      'Ambient': (ambientActive, 12),
      'UI': (uiActive, 8),
    };

    final usagePercent = totalVoices > 0 ? activeVoices / totalVoices : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildPanelHeader('VOICE POOL', Icons.queue_music),
              const Spacer(),
              // Voice count
              Text(
                '$activeVoices / $totalVoices voices',
                style: TextStyle(
                  fontSize: 10,
                  color: usagePercent > 0.8 ? LowerZoneColors.warning : LowerZoneColors.slotLabAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Stats row
          Row(
            children: [
              _buildStatBadge('Virtual', '$virtualVoices', virtualVoices > 0 ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted),
              const SizedBox(width: 8),
              _buildStatBadge('Steals', '$stealCount', stealCount > 0 ? LowerZoneColors.warning : LowerZoneColors.textMuted),
            ],
          ),
          const SizedBox(height: 12),
          // Voice usage bar
          Container(
            height: 20,
            decoration: BoxDecoration(
              color: LowerZoneColors.bgDeepest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: usagePercent,
              child: Container(
                decoration: BoxDecoration(
                  color: usagePercent > 0.8 ? LowerZoneColors.warning : LowerZoneColors.slotLabAccent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
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
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('STEREO PANNER', Icons.surround_sound),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                _buildPanChannel('SFX', 0.0),
                _buildPanChannel('Music', 0.0),
                _buildPanChannel('Voice', 0.1),
                _buildPanChannel('Ambient', 0.0),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanChannel(String name, double pan) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Text(name, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: LowerZoneColors.textSecondary)),
            const SizedBox(height: 8),
            Expanded(
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
            const SizedBox(height: 4),
            Text(pan == 0 ? 'C' : '${(pan * 100).toInt()}${pan > 0 ? 'R' : 'L'}',
              style: TextStyle(fontSize: 9, color: LowerZoneColors.slotLabAccent)),
          ],
        ),
      ),
    );
  }

  // Note: Compact Meter Panel replaced by RealTimeBusMeters widget (P1.4)

  /// Compact DSP Chain
  Widget _buildCompactDspChain() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('SIGNAL CHAIN', Icons.link),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildDspNode('INPUT', Icons.input, isEndpoint: true),
                  _buildDspArrow(),
                  _buildDspNode('EQ', Icons.equalizer, isActive: true),
                  _buildDspArrow(),
                  _buildDspNode('COMP', Icons.compress, isActive: true),
                  _buildDspArrow(),
                  _buildDspNode('LIMIT', Icons.volume_up, isActive: false),
                  _buildDspArrow(),
                  _buildDspNode('REVERB', Icons.waves, isActive: true),
                  _buildDspArrow(),
                  _buildDspNode('OUTPUT', Icons.output, isEndpoint: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

  /// Compact Stems Panel
  Widget _buildCompactStemsPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('STEM EXPORT', Icons.account_tree),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _buildStemItem('SFX Bus', true),
                _buildStemItem('Music Bus', true),
                _buildStemItem('Voice Bus', true),
                _buildStemItem('Ambient Bus', false),
                _buildStemItem('Master Mix', true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStemItem(String name, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isSelected ? LowerZoneColors.slotLabAccent.withValues(alpha: 0.1) : LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected ? LowerZoneColors.slotLabAccent : LowerZoneColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: isSelected ? LowerZoneColors.slotLabAccent : LowerZoneColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary))),
        ],
      ),
    );
  }

  /// Compact Variations Panel
  Widget _buildCompactVariationsPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('BATCH VARIATIONS', Icons.auto_awesome),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _buildVariationSlider('Pitch', '±10%'),
                      _buildVariationSlider('Volume', '±5%'),
                      _buildVariationSlider('Pan', '±20%'),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 100,
                  decoration: BoxDecoration(
                    color: LowerZoneColors.bgDeepest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Variations', style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
                      const SizedBox(height: 8),
                      Text('8', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: LowerZoneColors.slotLabAccent)),
                      const SizedBox(height: 8),
                      Icon(Icons.refresh, size: 20, color: LowerZoneColors.textMuted),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariationSlider(String label, String range) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
                widthFactor: 0.4,
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

  /// Compact Package Panel
  Widget _buildCompactPackagePanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('GAME PACKAGE', Icons.inventory_2),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _buildExportOption('Platform', 'All'),
                      _buildExportOption('Compression', 'Vorbis Q6'),
                      _buildExportOption('Total Events', '44'),
                      _buildExportOption('Est. Size', '~18.2 MB'),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 100,
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
                      Icon(Icons.download, size: 32, color: LowerZoneColors.slotLabAccent),
                      const SizedBox(height: 8),
                      Text(
                        'PACKAGE',
                        style: TextStyle(
                          fontSize: 11,
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
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLACEHOLDER PANELS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPlaceholderPanel(String title, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: LowerZoneColors.textMuted),
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
          const Text(
            'Coming soon...',
            style: TextStyle(
              fontSize: 11,
              color: LowerZoneColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

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
    final actions = switch (widget.controller.superTab) {
      SlotLabSuperTab.stages => SlotLabActions.forStages(),
      SlotLabSuperTab.events => SlotLabActions.forEvents(),
      SlotLabSuperTab.mix => SlotLabActions.forMix(),
      SlotLabSuperTab.dsp => SlotLabActions.forDsp(),
      SlotLabSuperTab.bake => SlotLabActions.forBake(),
    };

    // Get stage count from provider if available
    String statusText = 'Stages: --';
    final provider = widget.slotLabProvider ?? _tryGetSlotLabProvider();
    if (provider != null) {
      final stageCount = provider.lastStages.length;
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
