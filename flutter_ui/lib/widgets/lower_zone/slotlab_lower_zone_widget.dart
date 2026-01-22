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

  const SlotLabLowerZoneWidget({
    super.key,
    required this.controller,
    this.slotLabProvider,
    this.onSpin,
    this.onForceOutcome,
    this.onAudioDropped,
  });

  @override
  State<SlotLabLowerZoneWidget> createState() => _SlotLabLowerZoneWidgetState();
}

class _SlotLabLowerZoneWidgetState extends State<SlotLabLowerZoneWidget> {
  String _selectedOutcome = 'Random';
  String _selectedVolatility = 'Medium';
  String _selectedTiming = 'Normal';
  String _selectedGrid = '5×3';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
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
  Widget _buildSpinControlBar() {
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
          _buildSpinDropdown('Outcome', _selectedOutcome,
              ['Random', 'SmallWin', 'BigWin', 'FreeSpins', 'Jackpot', 'Lose'],
              (v) => setState(() { _selectedOutcome = v; widget.onForceOutcome?.call(v); })),
          _buildSpinDropdown('Volatility', _selectedVolatility,
              ['Low', 'Medium', 'High', 'Studio'],
              (v) => setState(() => _selectedVolatility = v)),
          _buildSpinDropdown('Timing', _selectedTiming,
              ['Normal', 'Turbo', 'Mobile', 'Studio'],
              (v) => setState(() => _selectedTiming = v)),
          _buildSpinDropdown('Grid', _selectedGrid,
              ['5×3', '5×4', '6×4', 'Custom'],
              (v) => setState(() => _selectedGrid = v)),
          const Spacer(),
          // Spin button
          _buildSpinButton(),
          const SizedBox(width: 8),
          // Pause button
          _buildPauseButton(),
        ],
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

  Widget _buildPauseButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Icon(Icons.pause, size: 14, color: LowerZoneColors.textSecondary),
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

  /// Compact Event Timeline
  Widget _buildCompactEventTimeline() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('EVENT TIMELINE', Icons.view_timeline),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: LowerZoneColors.bgDeepest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: LowerZoneColors.border),
              ),
              child: CustomPaint(
                painter: _TimelinePainter(color: LowerZoneColors.slotLabAccent),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 8),
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

  /// Compact Symbols Panel
  Widget _buildCompactSymbolsPanel() {
    final symbols = ['WILD', 'SCATTER', 'BONUS', '7', 'BAR', 'CHERRY', 'BELL', 'ORANGE'];
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('SYMBOL AUDIO', Icons.casino),
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
              itemBuilder: (context, index) => _buildSymbolCard(symbols[index], index < 3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSymbolCard(String symbol, bool hasAudio) {
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
            Icons.casino,
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

  /// Compact Event Folder
  Widget _buildCompactEventFolder() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('EVENT FOLDER', Icons.folder_special),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                // Folder tree
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
                        _buildFolderItem('Spins', Icons.folder_open, 12, true),
                        _buildFolderItem('Wins', Icons.folder, 8, false),
                        _buildFolderItem('Features', Icons.folder, 15, false),
                        _buildFolderItem('UI', Icons.folder, 6, false),
                        _buildFolderItem('Ambient', Icons.folder, 3, false),
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
                    child: ListView(
                      padding: const EdgeInsets.all(4),
                      children: [
                        _buildEventItem('SPIN_START', true),
                        _buildEventItem('REEL_SPIN', true),
                        _buildEventItem('REEL_STOP_0', true),
                        _buildEventItem('REEL_STOP_1', true),
                        _buildEventItem('REEL_STOP_2', true),
                        _buildEventItem('ANTICIPATION_ON', false),
                      ],
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

  /// Compact Composite Editor
  Widget _buildCompactCompositeEditor() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('COMPOSITE EDITOR', Icons.edit),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: LowerZoneColors.bgDeepest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: LowerZoneColors.border),
              ),
              child: Column(
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
                          'SPIN_START',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: LowerZoneColors.slotLabAccent,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.edit, size: 14, color: LowerZoneColors.textMuted),
                      ],
                    ),
                  ),
                  // Layers list
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(4),
                      children: [
                        _buildLayerItem('Layer 1: spin_whoosh.wav', 0.0, 0.8),
                        _buildLayerItem('Layer 2: reel_start.wav', 50.0, 1.0),
                        _buildLayerItem('Layer 3: ambient_bed.wav', 0.0, 0.4),
                      ],
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

  /// Compact Voice Pool
  Widget _buildCompactVoicePool() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildPanelHeader('VOICE POOL', Icons.queue_music),
              const Spacer(),
              Text('12 / 48 voices', style: TextStyle(fontSize: 10, color: LowerZoneColors.slotLabAccent)),
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
              widthFactor: 12 / 48,
              child: Container(
                decoration: BoxDecoration(
                  color: LowerZoneColors.slotLabAccent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _buildVoiceUsageRow('SFX', 5, 16),
                _buildVoiceUsageRow('Music', 2, 8),
                _buildVoiceUsageRow('Voice', 1, 4),
                _buildVoiceUsageRow('Ambient', 3, 12),
                _buildVoiceUsageRow('UI', 1, 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceUsageRow(String busName, int used, int limit) {
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
                widthFactor: used / limit,
                child: Container(
                  decoration: BoxDecoration(
                    color: used / limit > 0.8 ? LowerZoneColors.warning : LowerZoneColors.slotLabAccent,
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
