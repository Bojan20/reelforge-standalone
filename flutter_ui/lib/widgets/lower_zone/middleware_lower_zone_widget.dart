// Middleware Lower Zone Widget
//
// Complete Lower Zone for Middleware section with:
// - Context bar (Super-tabs + Sub-tabs)
// - Slot Context Bar (Stage, Feature, State, Target, Trigger)
// - Content panel (switches based on current tab)
// - Action strip (context-aware actions)
// - Resizable height
// - Integrated Middleware panels (Ducking, Random, Sequence, Blend, Bus Hierarchy, etc.)

import 'dart:convert';
import 'dart:io' show Directory, File;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../utils/path_validator.dart';
import 'package:provider/provider.dart';

import 'middleware_lower_zone_controller.dart';
import '../../models/middleware_models.dart';
import 'lower_zone_types.dart';
import 'lower_zone_context_bar.dart';
import 'lower_zone_action_strip.dart';
import '../../providers/middleware_provider.dart';
import '../../models/slot_audio_events.dart' show SlotEventLayer;
import '../common/audio_waveform_picker_dialog.dart';
import '../middleware/ducking_matrix_panel.dart';
import '../middleware/random_container_panel.dart';
import '../middleware/sequence_container_panel.dart';
import '../middleware/blend_container_panel.dart';
import '../middleware/bus_hierarchy_panel.dart';
import '../middleware/events_folder_panel.dart';
import '../middleware/event_debugger_panel.dart';
import '../middleware/rtpc_debugger_panel.dart';
import '../middleware/dsp_profiler_panel.dart';
import '../middleware/priority_tier_preset_panel.dart';
import '../middleware/state_machine_graph.dart';
import '../middleware/container_groups_panel.dart';
import '../middleware/event_profiler_advanced.dart';
import '../middleware/spatial_designer_widget.dart';
import '../slot_lab/lower_zone/events/composite_editor_panel.dart';

class MiddlewareLowerZoneWidget extends StatefulWidget {
  final MiddlewareLowerZoneController controller;

  /// Callback when slot context changes
  final void Function(Map<String, String> context)? onSlotContextChanged;

  const MiddlewareLowerZoneWidget({
    super.key,
    required this.controller,
    this.onSlotContextChanged,
  });

  @override
  State<MiddlewareLowerZoneWidget> createState() => _MiddlewareLowerZoneWidgetState();
}

class _MiddlewareLowerZoneWidgetState extends State<MiddlewareLowerZoneWidget> {
  // Slot context state
  String _selectedStage = 'SPIN_START';
  String _selectedFeature = 'BASE';
  String _selectedState = 'idle';
  String _selectedTarget = 'sfx';
  String _selectedTrigger = 'onEnter';

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

  void _notifySlotContextChanged() {
    widget.onSlotContextChanged?.call({
      'stage': _selectedStage,
      'feature': _selectedFeature,
      'state': _selectedState,
      'target': _selectedTarget,
      'trigger': _selectedTrigger,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: kLowerZoneAnimationDuration,
      height: widget.controller.totalHeight,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: LowerZoneColors.bgDeep,
        border: Border(
          top: BorderSide(color: LowerZoneColors.border, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Resize handle
          _buildResizeHandle(),
          // Context bar
          LowerZoneContextBar(
            superTabLabels: MiddlewareSuperTab.values.map((t) => t.label).toList(),
            superTabIcons: MiddlewareSuperTab.values.map((t) => t.icon).toList(),
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
            // Slot Context Bar (Middleware specific)
            _buildSlotContextBar(),
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

  /// Slot Context Bar — always visible in Middleware when expanded
  Widget _buildSlotContextBar() {
    return Container(
      height: kSlotContextBarHeight,
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
            'SLOT:',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: LowerZoneColors.middlewareAccent,
            ),
          ),
          const SizedBox(width: 8),
          _buildContextDropdown(
            'Stage',
            _selectedStage,
            ['SPIN_START', 'REEL_STOP', 'WIN_PRESENT', 'FEATURE_ENTER', 'JACKPOT_TRIGGER', 'CASCADE_STEP'],
            (v) => setState(() { _selectedStage = v; _notifySlotContextChanged(); }),
          ),
          _buildContextDropdown(
            'Feature',
            _selectedFeature,
            ['BASE', 'FREESPINS', 'BONUS', 'HOLDWIN', 'JACKPOT', 'RESPIN'],
            (v) => setState(() { _selectedFeature = v; _notifySlotContextChanged(); }),
          ),
          _buildContextDropdown(
            'State',
            _selectedState,
            ['idle', 'spinning', 'presenting', 'celebrating', 'waiting'],
            (v) => setState(() { _selectedState = v; _notifySlotContextChanged(); }),
          ),
          _buildContextDropdown(
            'Target',
            _selectedTarget,
            ['sfx', 'music', 'voice', 'ambience', 'ui', 'reels'],
            (v) => setState(() { _selectedTarget = v; _notifySlotContextChanged(); }),
          ),
          _buildContextDropdown(
            'Trigger',
            _selectedTrigger,
            ['onEnter', 'onExit', 'onWin', 'onLose', 'onSpin', 'onStop'],
            (v) => setState(() { _selectedTrigger = v; _notifySlotContextChanged(); }),
          ),
          const Spacer(),
          // Quick test button
          _buildQuickTestButton(),
        ],
      ),
    );
  }

  Widget _buildContextDropdown(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        height: 20,
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
            icon: Icon(Icons.arrow_drop_down, size: 12, color: LowerZoneColors.textMuted),
            items: options.map((o) => DropdownMenuItem(
              value: o,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$label:',
                    style: const TextStyle(
                      fontSize: 8,
                      color: LowerZoneColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(o, style: const TextStyle(fontSize: 9)),
                ],
              ),
            )).toList(),
            selectedItemBuilder: (context) => options.map((o) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$label:',
                  style: const TextStyle(
                    fontSize: 8,
                    color: LowerZoneColors.textTertiary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  o,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: LowerZoneColors.middlewareAccent,
                  ),
                ),
              ],
            )).toList(),
            onChanged: (v) => v != null ? onChanged(v) : null,
            style: TextStyle(
              fontSize: 9,
              color: LowerZoneColors.middlewareAccent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickTestButton() {
    return GestureDetector(
      onTap: () {
        // Trigger test event with current context
        try {
          final mw = context.read<MiddlewareProvider>();
          mw.postEvent(_selectedStage);
        } catch (_) {
          // Provider not available
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: LowerZoneColors.middlewareAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: LowerZoneColors.middlewareAccent.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow, size: 12, color: LowerZoneColors.middlewareAccent),
            const SizedBox(width: 4),
            Text(
              'Test',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: LowerZoneColors.middlewareAccent,
              ),
            ),
          ],
        ),
      ),
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
      case MiddlewareSuperTab.events:
        return _buildEventsContent();
      case MiddlewareSuperTab.containers:
        return _buildContainersContent();
      case MiddlewareSuperTab.routing:
        return _buildRoutingContent();
      case MiddlewareSuperTab.rtpc:
        return _buildRtpcContent();
      case MiddlewareSuperTab.deliver:
        return _buildDeliverContent();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENTS CONTENT — Integrated panels
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEventsContent() {
    final subTab = widget.controller.state.eventsSubTab;
    return switch (subTab) {
      MiddlewareEventsSubTab.browser => const EventsFolderPanel(),
      MiddlewareEventsSubTab.editor => const CompositeEditorPanel(),
      MiddlewareEventsSubTab.debug => const EventDebuggerPanel(),
      MiddlewareEventsSubTab.stateGraph => _buildStateGraphPanel(),
    };
  }


  /// Compact actions panel
  Widget _buildCompactActionsPanel() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('EVENT ACTIONS', Icons.play_circle),
          const SizedBox(height: 6),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1.8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: 8,
              itemBuilder: (context, index) {
                final actions = [
                  ('Post Event', Icons.send, true),
                  ('Set State', Icons.settings, true),
                  ('Set Switch', Icons.toggle_on, false),
                  ('Set RTPC', Icons.tune, true),
                  ('Stop All', Icons.stop, false),
                  ('Seek', Icons.fast_forward, false),
                  ('Pause', Icons.pause, false),
                  ('Resume', Icons.play_arrow, false),
                ];
                return _buildActionCard(actions[index].$1, actions[index].$2, actions[index].$3);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(String name, IconData icon, bool isEnabled) {
    return Container(
      decoration: BoxDecoration(
        color: isEnabled
            ? LowerZoneColors.middlewareAccent.withValues(alpha: 0.1)
            : LowerZoneColors.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isEnabled ? LowerZoneColors.middlewareAccent : LowerZoneColors.border,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 20,
            color: isEnabled ? LowerZoneColors.middlewareAccent : LowerZoneColors.textMuted,
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: TextStyle(
              fontSize: 9,
              fontWeight: isEnabled ? FontWeight.bold : FontWeight.normal,
              color: isEnabled ? LowerZoneColors.middlewareAccent : LowerZoneColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: LowerZoneColors.middlewareAccent),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.middlewareAccent,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTAINERS CONTENT — Fully integrated panels
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContainersContent() {
    final subTab = widget.controller.state.containersSubTab;
    return switch (subTab) {
      MiddlewareContainersSubTab.random => const RandomContainerPanel(),
      MiddlewareContainersSubTab.sequence => const SequenceContainerPanel(),
      MiddlewareContainersSubTab.blend => const BlendContainerPanel(),
      MiddlewareContainersSubTab.switchTab => _buildSwitchContainerPanel(),
      MiddlewareContainersSubTab.groups => const ContainerGroupsPanel(),
    };
  }

  Widget _buildSwitchContainerPanel() => _buildCompactSwitchContainer();

  // ═══════════════════════════════════════════════════════════════════════════
  // ROUTING CONTENT — Fully integrated panels
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRoutingContent() {
    final subTab = widget.controller.state.routingSubTab;
    return switch (subTab) {
      MiddlewareRoutingSubTab.buses => const BusHierarchyPanel(),
      MiddlewareRoutingSubTab.ducking => const DuckingMatrixPanel(),
      MiddlewareRoutingSubTab.matrix => _buildMatrixPanel(),
      MiddlewareRoutingSubTab.priority => const PriorityTierPresetPanel(),
      MiddlewareRoutingSubTab.spatial => _buildSpatialDesignerPanel(),
    };
  }

  Widget _buildMatrixPanel() => _buildCompactRoutingMatrix();

  // ═══════════════════════════════════════════════════════════════════════════
  // RTPC CONTENT — Partially integrated
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRtpcContent() {
    final subTab = widget.controller.state.rtpcSubTab;
    return switch (subTab) {
      MiddlewareRtpcSubTab.curves => _buildCurvesPanel(),
      MiddlewareRtpcSubTab.bindings => _buildBindingsPanel(),
      MiddlewareRtpcSubTab.meters => const RtpcDebuggerPanel(),
      MiddlewareRtpcSubTab.profiler => const DspProfilerPanel(),
      MiddlewareRtpcSubTab.advanced => _buildAdvancedProfilerPanel(),
    };
  }

  Widget _buildCurvesPanel() => _buildCompactRtpcCurves();
  Widget _buildBindingsPanel() => _buildCompactBindingsPanel();
  Widget _buildMetersPanel() => _buildCompactMetersPanel();

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW PANEL BUILDERS — State Graph, Spatial, Advanced Profiler
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStateGraphPanel() {
    return Selector<MiddlewareProvider, List<StateGroup>>(
      selector: (_, p) => p.stateGroups,
      builder: (ctx, groups, _) {
        final group = groups.isNotEmpty ? groups.first : null;
        return StateMachineGraph(
          stateGroup: group,
          showTransitions: true,
          onStateChangeRequested: (groupId, stateId) {
            ctx.read<MiddlewareProvider>().setState(groupId, stateId);
          },
        );
      },
    );
  }

  Widget _buildSpatialDesignerPanel() {
    return SpatialDesignerWidget(
      position: const SpatialPosition(x: 0, y: 0, z: 0),
      onPositionChanged: (pos) {
        // Spatial position update — connected to AutoSpatial engine
      },
    );
  }

  Widget _buildAdvancedProfilerPanel() {
    return Consumer<MiddlewareProvider>(
      builder: (ctx, provider, _) {
        final stats = provider.getProfilerStats();
        final entries = [
          ProfilerEntry(
            eventId: 'Total Events',
            latencyUs: stats.avgLatencyUs.toInt(),
            callCount: stats.totalEvents,
            avgLatencyUs: stats.avgLatencyUs,
          ),
          ProfilerEntry(
            eventId: 'Events/sec',
            latencyUs: stats.maxLatencyUs.toInt(),
            callCount: stats.eventsPerSecond,
            avgLatencyUs: stats.maxLatencyUs,
          ),
          ProfilerEntry(
            eventId: 'Voice Starts',
            latencyUs: 0,
            callCount: stats.voiceStarts,
            avgLatencyUs: 0,
          ),
          ProfilerEntry(
            eventId: 'Voice Steals',
            latencyUs: 0,
            callCount: stats.voiceSteals,
            avgLatencyUs: 0,
          ),
          if (stats.errors > 0)
            ProfilerEntry(
              eventId: 'Errors',
              latencyUs: 0,
              callCount: stats.errors,
              avgLatencyUs: 0,
            ),
        ];
        return EventProfilerAdvanced(entries: entries);
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DELIVER CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDeliverContent() {
    final subTab = widget.controller.state.deliverSubTab;
    return switch (subTab) {
      MiddlewareDeliverSubTab.bake => _buildBakePanel(),
      MiddlewareDeliverSubTab.soundbank => _buildSoundbankPanel(),
      MiddlewareDeliverSubTab.validate => _buildValidatePanel(),
      MiddlewareDeliverSubTab.package => _buildPackagePanel(),
    };
  }

  Widget _buildBakePanel() => _buildCompactBakePanel();
  Widget _buildSoundbankPanel() => _buildCompactSoundbankPanel();
  Widget _buildValidatePanel() => _buildCompactValidatePanel();
  Widget _buildPackagePanel() => _buildCompactPackagePanel();

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPACT PANEL IMPLEMENTATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Compact Switch Container
  Widget _buildCompactSwitchContainer() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('SWITCH CONTAINER', Icons.swap_horiz),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              children: [
                // Switch variable selector
                Container(
                  width: 150,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: LowerZoneColors.bgDeepest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Switch Variable',
                        style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: LowerZoneColors.middlewareAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'GameState',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: LowerZoneColors.middlewareAccent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...['BASE', 'FREESPINS', 'BONUS', 'JACKPOT'].map(
                        (state) => _buildSwitchStateItem(state, state == 'BASE'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Assigned sounds
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: LowerZoneColors.bgDeepest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: LowerZoneColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Assigned Sound: BASE',
                          style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
                        ),
                        const SizedBox(height: 8),
                        _buildAssignedSoundItem('base_music_loop.wav', true),
                        _buildAssignedSoundItem('base_ambient.wav', false),
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

  Widget _buildSwitchStateItem(String state, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? LowerZoneColors.middlewareAccent.withValues(alpha: 0.15) : null,
        borderRadius: BorderRadius.circular(4),
        border: isSelected ? Border.all(color: LowerZoneColors.middlewareAccent) : null,
      ),
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 12,
            color: isSelected ? LowerZoneColors.middlewareAccent : LowerZoneColors.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            state,
            style: TextStyle(
              fontSize: 9,
              color: isSelected ? LowerZoneColors.middlewareAccent : LowerZoneColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedSoundItem(String name, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            Icons.audio_file,
            size: 14,
            color: isActive ? LowerZoneColors.success : LowerZoneColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
            ),
          ),
          Icon(Icons.play_arrow, size: 14, color: LowerZoneColors.textMuted),
        ],
      ),
    );
  }

  /// Compact Routing Matrix
  Widget _buildCompactRoutingMatrix() {
    final sources = ['Track 1', 'Track 2', 'Track 3', 'Track 4'];
    final destinations = ['SFX', 'Music', 'Voice', 'Master'];

    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('ROUTING MATRIX', Icons.grid_on),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: LowerZoneColors.bgDeepest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: LowerZoneColors.border),
              ),
              child: Column(
                children: [
                  // Header row
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: LowerZoneColors.bgMid,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 60),
                        ...destinations.map((d) => Expanded(
                          child: Center(
                            child: Text(
                              d,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: LowerZoneColors.textSecondary,
                              ),
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                  // Matrix rows
                  Expanded(
                    child: ListView.builder(
                      itemCount: sources.length,
                      itemBuilder: (context, row) {
                        return Container(
                          height: 32,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: LowerZoneColors.border.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 60,
                                child: Center(
                                  child: Text(
                                    sources[row],
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: LowerZoneColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              ...List.generate(
                                destinations.length,
                                (col) => Expanded(
                                  child: Center(
                                    child: _buildMatrixCell(row == col),
                                  ),
                                ),
                              ),
                            ],
                          ),
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

  Widget _buildMatrixCell(bool isConnected) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: isConnected ? LowerZoneColors.middlewareAccent : LowerZoneColors.bgSurface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: isConnected ? LowerZoneColors.middlewareAccent : LowerZoneColors.border,
        ),
      ),
      child: isConnected
          ? Icon(Icons.check, size: 10, color: LowerZoneColors.bgDeep)
          : null,
    );
  }

  /// Compact RTPC Curves — reads from provider
  int _selectedCurveRtpcId = -1;

  Widget _buildCompactRtpcCurves() {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final rtpcDefs = middleware.rtpcDefinitions;

        if (rtpcDefs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPanelHeader('RTPC CURVES', Icons.show_chart),
                const SizedBox(height: 6),
                const Expanded(
                  child: Center(
                    child: Text(
                      'No RTPC parameters defined.\nCreate RTPCs in the Meters tab.',
                      style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Auto-select first if none selected
        if (_selectedCurveRtpcId < 0 || !rtpcDefs.any((r) => r.id == _selectedCurveRtpcId)) {
          _selectedCurveRtpcId = rtpcDefs.first.id;
        }

        final selectedRtpc = rtpcDefs.firstWhere(
          (r) => r.id == _selectedCurveRtpcId,
          orElse: () => rtpcDefs.first,
        );

        return Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPanelHeader('RTPC CURVES', Icons.show_chart),
              const SizedBox(height: 6),
              Expanded(
                child: Row(
                  children: [
                    // RTPC list — real from provider
                    SizedBox(
                      width: 120,
                      child: Container(
                        decoration: BoxDecoration(
                          color: LowerZoneColors.bgDeepest,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: LowerZoneColors.border),
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(4),
                          itemCount: rtpcDefs.length,
                          itemBuilder: (ctx, i) {
                            final rtpc = rtpcDefs[i];
                            final isSelected = rtpc.id == _selectedCurveRtpcId;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedCurveRtpcId = rtpc.id),
                              child: _buildCurveListItem(rtpc.name, isSelected),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Curve display — renders the real RtpcCurve
                    Expanded(
                      child: Column(
                        children: [
                          // RTPC info header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: LowerZoneColors.bgDeepest,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              border: Border.all(color: LowerZoneColors.border),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  selectedRtpc.name,
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: LowerZoneColors.textPrimary),
                                ),
                                const Spacer(),
                                Text(
                                  '${selectedRtpc.currentValue.toStringAsFixed(1)} / ${selectedRtpc.min.toStringAsFixed(0)}-${selectedRtpc.max.toStringAsFixed(0)}',
                                  style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: LowerZoneColors.middlewareAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: Text(
                                    '${(selectedRtpc.normalizedValue * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: LowerZoneColors.middlewareAccent),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Curve canvas
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: LowerZoneColors.bgDeepest,
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
                                border: Border.all(color: LowerZoneColors.border),
                              ),
                              child: CustomPaint(
                                painter: _RtpcCurvePainter(
                                  color: LowerZoneColors.middlewareAccent,
                                  curve: selectedRtpc.curve,
                                  currentValue: selectedRtpc.normalizedValue,
                                ),
                                size: Size.infinite,
                              ),
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
      },
    );
  }

  Widget _buildCurveListItem(String name, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isSelected ? LowerZoneColors.middlewareAccent.withValues(alpha: 0.1) : null,
        borderRadius: BorderRadius.circular(4),
        border: isSelected ? Border.all(color: LowerZoneColors.middlewareAccent) : null,
      ),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 9,
          color: isSelected ? LowerZoneColors.middlewareAccent : LowerZoneColors.textSecondary,
        ),
      ),
    );
  }

  /// Compact Bindings Panel — reads from provider
  Widget _buildCompactBindingsPanel() {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final audioBindings = middleware.rtpcBindings;
        final dspBindings = middleware.dspBindingsList;
        final rtpcDefs = middleware.rtpcDefs;

        final hasBindings = audioBindings.isNotEmpty || dspBindings.isNotEmpty;

        if (!hasBindings) {
          return Container(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPanelHeader('PARAMETER BINDINGS', Icons.link),
                const SizedBox(height: 6),
                const Expanded(
                  child: Center(
                    child: Text(
                      'No parameter bindings.\nCreate RTPC bindings to connect parameters.',
                      style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPanelHeader('PARAMETER BINDINGS', Icons.link),
              const SizedBox(height: 6),
              Expanded(
                child: ListView(
                  children: [
                    // Audio bindings (volume, pan, sends)
                    for (final binding in audioBindings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _buildBindingRow(
                          rtpcDefs[binding.rtpcId]?.name ?? 'RTPC #${binding.rtpcId}',
                          binding.target.displayName,
                          '${binding.target.defaultRange.$1.toStringAsFixed(1)}-${binding.target.defaultRange.$2.toStringAsFixed(1)}',
                          binding.curve.points.isEmpty ? 'Linear' : '${binding.curve.points.length}pt',
                          binding.enabled,
                        ),
                      ),
                    // DSP bindings (filter, compressor, etc.)
                    for (final binding in dspBindings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _buildBindingRow(
                          rtpcDefs[binding.rtpcId]?.name ?? 'RTPC #${binding.rtpcId}',
                          binding.label ?? 'DSP T${binding.trackId}:S${binding.slotIndex}:P${binding.paramIndex}',
                          '${binding.target.defaultRange.$1.toStringAsFixed(1)}-${binding.target.defaultRange.$2.toStringAsFixed(1)}',
                          binding.curve.points.isEmpty ? 'Linear' : '${binding.curve.points.length}pt',
                          binding.enabled,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBindingRow(String source, String target, String range, String curve, bool enabled) {
    final opacity = enabled ? 1.0 : 0.4;
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: enabled ? LowerZoneColors.border : LowerZoneColors.border.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            _buildBindingChip(source, LowerZoneColors.middlewareAccent),
            const Icon(Icons.arrow_right_alt, size: 16, color: LowerZoneColors.textMuted),
            Flexible(child: _buildBindingChip(target, const Color(0xFF40C8FF))),
            const SizedBox(width: 4),
            Text(range, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: LowerZoneColors.bgMid,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(curve, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textSecondary)),
            ),
            if (!enabled) ...[
              const SizedBox(width: 4),
              const Icon(Icons.visibility_off, size: 10, color: LowerZoneColors.textMuted),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBindingChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Compact Meters Panel — reads live RTPC values from provider
  Widget _buildCompactMetersPanel() {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final rtpcDefs = middleware.rtpcDefinitions;

        if (rtpcDefs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPanelHeader('REAL-TIME METERS', Icons.bar_chart),
                const SizedBox(height: 6),
                const Expanded(
                  child: Center(
                    child: Text(
                      'No RTPC parameters defined.',
                      style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPanelHeader('REAL-TIME METERS', Icons.bar_chart),
              const SizedBox(height: 6),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final rtpc in rtpcDefs.take(8))
                      _buildMeterColumn(
                        rtpc.name.length > 8 ? rtpc.name.substring(0, 8) : rtpc.name,
                        rtpc.normalizedValue,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMeterColumn(String label, double value) {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: 24,
            decoration: BoxDecoration(
              color: LowerZoneColors.bgDeepest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: LowerZoneColors.border),
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                FractionallySizedBox(
                  heightFactor: value,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          value > 0.8 ? LowerZoneColors.error : LowerZoneColors.middlewareAccent,
                          value > 0.8
                              ? LowerZoneColors.error.withValues(alpha: 0.5)
                              : LowerZoneColors.middlewareAccent.withValues(alpha: 0.5),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${(value * 100).toInt()}',
          style: const TextStyle(fontSize: 9, color: LowerZoneColors.textPrimary),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 7, color: LowerZoneColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Compact Bake Panel
  Widget _buildCompactBakePanel() {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final events = middleware.compositeEvents;
        int totalLayers = 0;
        int withAudio = 0;
        for (final e in events) {
          totalLayers += e.layers.length;
          if (e.layers.isNotEmpty) withAudio++;
        }

        return Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPanelHeader('AUDIO BAKING', Icons.local_fire_department),
              const SizedBox(height: 6),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: LowerZoneColors.bgDeepest,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: LowerZoneColors.border),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildBakeOption('Events', '${events.length}'),
                            _buildBakeOption('Layers', '$totalLayers'),
                            _buildBakeOption('With Audio', '$withAudio'),
                            _buildBakeOption('Format', 'JSON'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: events.isEmpty ? null : () async {
                        final result = await FilePicker.platform.saveFile(
                          dialogTitle: 'Export Events',
                          fileName: 'events_export.json',
                          type: FileType.custom,
                          allowedExtensions: ['json'],
                        );
                        if (result != null && context.mounted) {
                          final json = jsonEncode(middleware.exportEventsToJson());
                          await File(result).writeAsString(json);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Exported to $result')),
                            );
                          }
                        }
                      },
                      child: Container(
                        width: 100,
                        decoration: BoxDecoration(
                          color: LowerZoneColors.middlewareAccent.withValues(alpha: events.isEmpty ? 0.05 : 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: events.isEmpty ? LowerZoneColors.border : LowerZoneColors.middlewareAccent),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.local_fire_department, size: 28, color: events.isEmpty ? LowerZoneColors.textMuted : LowerZoneColors.middlewareAccent),
                            const SizedBox(height: 4),
                            Text(
                              'BAKE',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: events.isEmpty ? LowerZoneColors.textMuted : LowerZoneColors.middlewareAccent,
                              ),
                            ),
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
      },
    );
  }

  Widget _buildBakeOption(String label, String value) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textMuted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary)),
        ],
      ),
    );
  }

  /// Compact Soundbank Panel
  Widget _buildCompactSoundbankPanel() {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final events = middleware.compositeEvents;
        // Group events by category
        final categories = <String, int>{};
        int totalLayers = 0;
        for (final e in events) {
          categories[e.category] = (categories[e.category] ?? 0) + 1;
          totalLayers += e.layers.length;
        }
        final catEntries = categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

        return Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildPanelHeader('SOUNDBANK', Icons.sd_storage),
                  const Spacer(),
                  Text('${events.length} events · $totalLayers layers', style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: catEntries.isEmpty
                    ? const Center(child: Text('No events — create events first', style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted)))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: catEntries.take(6).map((entry) {
                          final hasAudio = events.where((e) => e.category == entry.key).any((e) => e.layers.isNotEmpty);
                          return _buildSoundbankItem(entry.key, '${entry.value} events', hasAudio);
                        }).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSoundbankItem(String name, String detail, bool hasAudio) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: hasAudio ? LowerZoneColors.success.withValues(alpha: 0.3) : LowerZoneColors.border),
      ),
      child: Row(
        children: [
          Icon(
            hasAudio ? Icons.check_circle : Icons.circle_outlined,
            size: 14,
            color: hasAudio ? LowerZoneColors.success : LowerZoneColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary))),
          Text(detail, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
        ],
      ),
    );
  }

  /// Compact Validate Panel
  Widget _buildCompactValidatePanel() {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final events = middleware.compositeEvents;
        final results = <(String, bool)>[];

        // Check: events with no audio layers
        final emptyEvents = events.where((e) => e.layers.isEmpty).toList();
        if (emptyEvents.isEmpty) {
          results.add(('All events have audio layers', true));
        } else {
          for (final e in emptyEvents.take(3)) {
            results.add(('Missing audio: ${e.name}', false));
          }
          if (emptyEvents.length > 3) {
            results.add(('...and ${emptyEvents.length - 3} more without audio', false));
          }
        }

        // Check: events with no trigger stages
        final noStages = events.where((e) => e.triggerStages.isEmpty).toList();
        if (noStages.isEmpty) {
          results.add(('All events have trigger stages', true));
        } else {
          results.add(('${noStages.length} events missing trigger stages', false));
        }

        // Check: total event count
        if (events.isNotEmpty) {
          results.add(('${events.length} events registered', true));
        } else {
          results.add(('No events created', false));
        }

        // Check: layers with missing audio paths
        int missingPaths = 0;
        for (final e in events) {
          for (final l in e.layers) {
            if (l.audioPath.isEmpty) missingPaths++;
          }
        }
        if (missingPaths == 0 && events.isNotEmpty) {
          results.add(('All layers have audio files', true));
        } else if (missingPaths > 0) {
          results.add(('$missingPaths layers missing audio file', false));
        }

        return Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildPanelHeader('VALIDATOR', Icons.check_circle),
                  const Spacer(),
                  Text(
                    '${results.where((r) => !r.$2).length} issues',
                    style: TextStyle(
                      fontSize: 9,
                      color: results.any((r) => !r.$2) ? LowerZoneColors.error : LowerZoneColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: LowerZoneColors.bgDeepest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.border),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: results.isEmpty
                      ? const Center(child: Text('No data to validate', style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted)))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: results.take(6).map((r) => _buildValidationResult(r.$1, r.$2)).toList(),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildValidationResult(String message, bool isValid) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isValid ? LowerZoneColors.success : LowerZoneColors.error).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.warning,
            size: 14,
            color: isValid ? LowerZoneColors.success : LowerZoneColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 10,
                color: isValid ? LowerZoneColors.textPrimary : LowerZoneColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact Package Panel
  Widget _buildCompactPackagePanel() {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final events = middleware.compositeEvents;
        int totalLayers = 0;
        int withAudio = 0;
        final categories = <String>{};
        for (final e in events) {
          totalLayers += e.layers.length;
          if (e.layers.isNotEmpty) withAudio++;
          categories.add(e.category);
        }

        return Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPanelHeader('EXPORT PACKAGE', Icons.inventory_2),
              const SizedBox(height: 6),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildPackageOption('Events', '${events.length}'),
                          _buildPackageOption('Layers', '$totalLayers'),
                          _buildPackageOption('With Audio', '$withAudio / ${events.length}'),
                          _buildPackageOption('Categories', '${categories.length}'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final result = await FilePicker.platform.getDirectoryPath(
                          dialogTitle: 'Select Output Directory',
                        );
                        if (result != null && context.mounted) {
                          final packageDir = Directory('$result/FluxForge_Package');
                          await packageDir.create(recursive: true);
                          final eventsJson = jsonEncode(middleware.exportEventsToJson());
                          await File('${packageDir.path}/events.json').writeAsString(eventsJson);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Package created: ${packageDir.path}')),
                            );
                          }
                        }
                      },
                      child: Container(
                        width: 100,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              LowerZoneColors.middlewareAccent.withValues(alpha: 0.2),
                              LowerZoneColors.middlewareAccent.withValues(alpha: 0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: LowerZoneColors.middlewareAccent),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.download, size: 28, color: LowerZoneColors.middlewareAccent),
                            const SizedBox(height: 4),
                            Text(
                              'EXPORT',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: LowerZoneColors.middlewareAccent,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              events.isEmpty ? 'No data' : 'Ready',
                              style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
                            ),
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
      },
    );
  }

  Widget _buildPackageOption(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION STRIP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActionStrip() {
    MiddlewareProvider? middleware;
    try {
      middleware = context.read<MiddlewareProvider>();
    } catch (_) {
      // Provider not available
    }

    // Build comprehensive parameter strip for selected layer
    Widget? parameterStrip;

    if (middleware != null && widget.controller.superTab == MiddlewareSuperTab.events) {
      final selectedEvent = middleware.selectedCompositeEvent;

      if (selectedEvent != null && selectedEvent.layers.isNotEmpty) {
        // Get first layer or selected layer
        final layer = selectedEvent.layers.first;

        parameterStrip = _buildLayerParameterStrip(
          layer: layer,
          eventId: selectedEvent.id,
          middleware: middleware,
          looping: selectedEvent.looping,
          onLoopChanged: (newLooping) {
            final updatedEvent = selectedEvent.copyWith(looping: newLooping);
            middleware?.updateCompositeEvent(updatedEvent);
          },
        );
      } else {
      }
    } else {
    }

    final actions = switch (widget.controller.superTab) {
      MiddlewareSuperTab.events => MiddlewareActions.forEvents(
        onNewEvent: () {
          middleware?.createCompositeEvent(
            name: 'New Event ${DateTime.now().millisecondsSinceEpoch % 1000}',
            category: 'general',
          );
        },
        onDelete: () {
          final selectedId = middleware?.selectedCompositeEvent?.id;
          if (selectedId != null) {
            middleware?.deleteCompositeEvent(selectedId);
          }
        },
        onDuplicate: () {
          final selectedId = middleware?.selectedCompositeEvent?.id;
          if (selectedId != null) {
            middleware?.duplicateCompositeEvent(selectedId);
          }
        },
        onTest: () {
          final selectedId = middleware?.selectedCompositeEvent?.id;
          if (selectedId != null) {
            middleware?.previewCompositeEvent(selectedId);
          }
        },
      ),
      MiddlewareSuperTab.containers => MiddlewareActions.forContainers(
        onAddSound: () async {
          // Pick audio file and add to current container type
          final subTab = widget.controller.state.containersSubTab;
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: PathValidator.allowedExtensions,
          );
          if (result != null && result.files.isNotEmpty && middleware != null) {
            final name = result.files.first.name.replaceAll(RegExp(r'\.[^.]+$'), '');

            switch (subTab) {
              case MiddlewareContainersSubTab.blend:
                if (middleware.blendContainers.isNotEmpty) {
                  middleware.addBlendChild(
                    middleware.blendContainers.first.id,
                    name: name,
                    rtpcStart: 0.0,
                    rtpcEnd: 1.0,
                  );
                }
                break;
              case MiddlewareContainersSubTab.random:
                if (middleware.randomContainers.isNotEmpty) {
                  middleware.addRandomChild(
                    middleware.randomContainers.first.id,
                    name: name,
                    weight: 1.0,
                  );
                }
                break;
              case MiddlewareContainersSubTab.sequence:
                if (middleware.sequenceContainers.isNotEmpty) {
                  final seq = middleware.sequenceContainers.first;
                  middleware.addSequenceStep(
                    seq.id,
                    childId: seq.steps.length,
                    childName: name,
                    delayMs: 0.0,
                    durationMs: 1000.0,
                  );
                }
                break;
              case MiddlewareContainersSubTab.switchTab:
                break;
              case MiddlewareContainersSubTab.groups:
                break;
            }
          }
        },
        onBalance: () {
          // Balance weights in random container (equal distribution)
          if (middleware != null && middleware.randomContainers.isNotEmpty) {
            final container = middleware.randomContainers.first;
            if (container.children.isNotEmpty) {
              final equalWeight = 1.0 / container.children.length;
            }
          }
        },
        onShuffle: () {
          // Shuffle order in sequence container
          if (middleware != null && middleware.sequenceContainers.isNotEmpty) {
          }
        },
        onTest: () {
          // Test the current container
          final subTab = widget.controller.state.containersSubTab;
          if (middleware != null) {
            switch (subTab) {
              case MiddlewareContainersSubTab.blend:
                if (middleware.blendContainers.isNotEmpty) {
                }
                break;
              case MiddlewareContainersSubTab.random:
                if (middleware.randomContainers.isNotEmpty) {
                }
                break;
              case MiddlewareContainersSubTab.sequence:
                if (middleware.sequenceContainers.isNotEmpty) {
                }
                break;
              default:
            }
          }
        },
      ),
      MiddlewareSuperTab.routing => MiddlewareActions.forRouting(
        onAddRule: () {
          middleware?.addDuckingRule(
            sourceBus: 'SFX',
            sourceBusId: 0,
            targetBus: 'Master',
            targetBusId: 5,
            duckAmountDb: -12.0,
          );
        },
        onRemove: () {
          // Remove first/selected ducking rule
          if (middleware != null && middleware.duckingRules.isNotEmpty) {
            final rule = middleware.duckingRules.first;
            middleware.removeDuckingRule(rule.id);
          }
        },
        onCopy: () {
          // Copy ducking rules to clipboard as JSON
          if (middleware != null && middleware.duckingRules.isNotEmpty) {
            final json = jsonEncode(middleware.duckingRules.map((r) => {
              'sourceBus': r.sourceBus,
              'targetBus': r.targetBus,
              'duckAmountDb': r.duckAmountDb,
              'attackMs': r.attackMs,
              'releaseMs': r.releaseMs,
            }).toList());
          }
        },
        onTest: () {
          // Test ducking by triggering a notification
          if (middleware != null && middleware.duckingRules.isNotEmpty) {
          }
        },
      ),
      MiddlewareSuperTab.rtpc => MiddlewareActions.forRtpc(
        onAddPoint: () {
          // Add curve point to first RTPC definition
          if (middleware != null && middleware.rtpcDefinitions.isNotEmpty) {
            final rtpc = middleware.rtpcDefinitions.first;
            final newPoint = RtpcCurvePoint(
              x: 0.5,
              y: 0.5,
            );
            middleware.addRtpcCurvePoint(rtpc.id, newPoint);
          }
        },
        onRemove: () {
          // Remove last curve point from first RTPC
          if (middleware != null && middleware.rtpcDefinitions.isNotEmpty) {
            final rtpc = middleware.rtpcDefinitions.first;
            if (rtpc.curve != null && rtpc.curve!.points.isNotEmpty) {
              middleware.removeRtpcCurvePoint(rtpc.id, rtpc.curve!.points.length - 1);
            }
          }
        },
        onReset: () {
          // Reset first RTPC to default value
          if (middleware != null && middleware.rtpcDefinitions.isNotEmpty) {
            final rtpc = middleware.rtpcDefinitions.first;
            middleware.resetRtpc(rtpc.id);
          }
        },
        onPreview: () {
          // Preview RTPC effect
          if (middleware != null && middleware.rtpcDefinitions.isNotEmpty) {
            final rtpc = middleware.rtpcDefinitions.first;
          }
        },
      ),
      MiddlewareSuperTab.deliver => MiddlewareActions.forDeliver(
        onValidate: () {
          // Validate all events and show results
          if (middleware != null) {
            final events = middleware.compositeEvents;
            int errors = 0;
            int warnings = 0;
            for (final event in events) {
              if (event.layers.isEmpty) errors++;
              if (event.triggerStages.isEmpty) warnings++;
            }
            final msg = 'Validation: ${events.length} events, $errors errors, $warnings warnings';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)),
            );
          }
        },
        onBake: () async {
          // Export events to JSON file
          if (middleware != null) {
            final result = await FilePicker.platform.saveFile(
              dialogTitle: 'Export Events',
              fileName: 'events_export.json',
              type: FileType.custom,
              allowedExtensions: ['json'],
            );
            if (result != null) {
              final json = jsonEncode(middleware.exportEventsToJson());
              await File(result).writeAsString(json);
            }
          }
        },
        onPackage: () async {
          // Create soundbank package
          final result = await FilePicker.platform.getDirectoryPath(
            dialogTitle: 'Select Output Directory',
          );
          if (result != null && middleware != null) {
            // Create package directory structure
            final packageDir = Directory('$result/FluxForge_Package');
            await packageDir.create(recursive: true);

            // Export events
            final eventsJson = jsonEncode(middleware.exportEventsToJson());
            await File('${packageDir.path}/events.json').writeAsString(eventsJson);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Package created: ${packageDir.path}')),
            );
          }
        },
      ),
    };

    // Get event count from provider if available
    String statusText = 'Events: --';
    if (middleware != null) {
      statusText = 'Events: ${middleware.compositeEvents.length}';
    }

    return LowerZoneActionStrip(
      actions: actions,
      accentColor: widget.controller.accentColor,
      statusText: statusText,
      leftContent: parameterStrip,
    );
  }

  /// Comprehensive layer parameter strip with all controls
  Widget _buildLayerParameterStrip({
    required SlotEventLayer layer,
    required String eventId,
    required MiddlewareProvider middleware,
    required bool looping,
    required ValueChanged<bool> onLoopChanged,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Volume control
          _buildCompactVolumeControl(
            layer.volume,
            (newVolume) {
              final updatedLayer = layer.copyWith(volume: newVolume);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
          ),
          _buildParamDivider(),
          // Pan control
          _buildCompactPanControl(
            layer.pan,
            (newPan) {
              final updatedLayer = layer.copyWith(pan: newPan);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
          ),
          _buildParamDivider(),
          // Bus selector
          _buildCompactBusSelector(
            layer.busId ?? 0,
            (newBusId) {
              final updatedLayer = layer.copyWith(busId: newBusId);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
          ),
          _buildParamDivider(),
          // Offset/Delay control
          _buildCompactOffsetControl(
            layer.offsetMs,
            (newOffset) {
              final updatedLayer = layer.copyWith(offsetMs: newOffset);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
          ),
          _buildParamDivider(),
          // Mute/Solo toggles
          _buildMuteSoloToggles(
            muted: layer.muted,
            solo: layer.solo,
            onMuteChanged: (muted) {
              final updatedLayer = layer.copyWith(muted: muted);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
            onSoloChanged: (solo) {
              final updatedLayer = layer.copyWith(solo: solo);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
          ),
          _buildParamDivider(),
          // Loop toggle (event-level setting)
          _buildLoopToggle(looping, onLoopChanged),
          _buildParamDivider(),
          // ActionType indicator
          _buildActionTypeSelector(
            layer.actionType,
            (newType) {
              final updatedLayer = layer.copyWith(actionType: newType);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
          ),
          _buildParamDivider(),
          // === FADE CONTROLS ===
          // Fade In control
          _buildCompactFadeControl(
            label: 'FadeIn',
            fadeMs: layer.fadeInMs,
            curve: layer.fadeInCurve,
            color: Colors.lightGreen,
            onFadeChanged: (newFade) {
              final updatedLayer = layer.copyWith(fadeInMs: newFade);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
            onCurveChanged: (newCurve) {
              final updatedLayer = layer.copyWith(fadeInCurve: newCurve);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
          ),
          _buildParamDivider(),
          // Fade Out control
          _buildCompactFadeControl(
            label: 'FadeOut',
            fadeMs: layer.fadeOutMs,
            curve: layer.fadeOutCurve,
            color: Colors.deepOrange,
            onFadeChanged: (newFade) {
              final updatedLayer = layer.copyWith(fadeOutMs: newFade);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
            onCurveChanged: (newCurve) {
              final updatedLayer = layer.copyWith(fadeOutCurve: newCurve);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
          ),
          _buildParamDivider(),
          // === TRIM CONTROLS ===
          _buildCompactTrimControl(
            trimStartMs: layer.trimStartMs,
            trimEndMs: layer.trimEndMs,
            durationMs: (layer.durationSeconds ?? 0) * 1000,
            onTrimStartChanged: (newTrimStart) {
              final updatedLayer = layer.copyWith(trimStartMs: newTrimStart);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
            onTrimEndChanged: (newTrimEnd) {
              final updatedLayer = layer.copyWith(trimEndMs: newTrimEnd);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
          ),
          _buildParamDivider(),
          // === AUDIO PATH ===
          _buildAudioPathSelector(
            audioPath: layer.audioPath,
            onPathChanged: (newPath) {
              final updatedLayer = layer.copyWith(audioPath: newPath);
              middleware.updateEventLayer(eventId, updatedLayer);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildParamDivider() {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: LowerZoneColors.border.withValues(alpha: 0.5),
    );
  }

  /// Compact volume control with dB display
  Widget _buildCompactVolumeControl(double volume, ValueChanged<double> onChanged) {
    // Convert linear to dB for display
    String formatVolume(double v) {
      if (v <= 0.001) return '-∞';
      final db = 20 * math.log(v.clamp(0.001, 2.0)) / math.ln10;
      return '${db.toStringAsFixed(1)}dB';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.volume_up, size: 14, color: Colors.orange),
        const SizedBox(width: 4),
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: Colors.orange,
              inactiveTrackColor: LowerZoneColors.bgSurface,
              thumbColor: Colors.orange,
              overlayColor: Colors.orange.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: volume.clamp(0.0, 2.0),
              min: 0.0,
              max: 2.0, // Allow +6dB boost
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 40,
          child: Text(
            formatVolume(volume),
            style: TextStyle(
              fontSize: 9,
              color: Colors.orange,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  /// Compact bus selector dropdown
  Widget _buildCompactBusSelector(int busId, ValueChanged<int> onChanged) {
    const buses = [
      (0, 'SFX', Colors.cyan),
      (1, 'Music', Colors.purple),
      (2, 'Voice', Colors.amber),
      (3, 'Ambience', Colors.teal),
      (4, 'Aux', Colors.pink),
      (5, 'Master', Colors.red),
    ];

    final currentBus = buses.firstWhere(
      (b) => b.$1 == busId,
      orElse: () => buses[0],
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.route, size: 14, color: currentBus.$3),
        const SizedBox(width: 4),
        PopupMenuButton<int>(
          initialValue: busId,
          onSelected: onChanged,
          tooltip: 'Select Bus',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 60),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: currentBus.$3.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: currentBus.$3.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentBus.$2,
                  style: TextStyle(
                    fontSize: 10,
                    color: currentBus.$3,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(Icons.arrow_drop_down, size: 14, color: currentBus.$3),
              ],
            ),
          ),
          itemBuilder: (context) => buses.map((bus) {
            return PopupMenuItem<int>(
              value: bus.$1,
              height: 28,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: bus.$3,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(bus.$2, style: const TextStyle(fontSize: 12)),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Compact offset/delay control
  Widget _buildCompactOffsetControl(double offsetMs, ValueChanged<double> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.schedule, size: 14, color: Colors.green),
        const SizedBox(width: 4),
        SizedBox(
          width: 60,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: Colors.green,
              inactiveTrackColor: LowerZoneColors.bgSurface,
              thumbColor: Colors.green,
              overlayColor: Colors.green.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: offsetMs.clamp(0.0, 2000.0),
              min: 0.0,
              max: 2000.0,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 45,
          child: Text(
            '${offsetMs.toInt()}ms',
            style: TextStyle(
              fontSize: 9,
              color: Colors.green,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  /// Mute/Solo toggle buttons
  Widget _buildMuteSoloToggles({
    required bool muted,
    required bool solo,
    required ValueChanged<bool> onMuteChanged,
    required ValueChanged<bool> onSoloChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mute button
        GestureDetector(
          onTap: () => onMuteChanged(!muted),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: muted ? Colors.red.withValues(alpha: 0.3) : LowerZoneColors.bgSurface,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: muted ? Colors.red : LowerZoneColors.border,
              ),
            ),
            child: Text(
              'M',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: muted ? Colors.red : LowerZoneColors.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Solo button
        GestureDetector(
          onTap: () => onSoloChanged(!solo),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: solo ? Colors.amber.withValues(alpha: 0.3) : LowerZoneColors.bgSurface,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: solo ? Colors.amber : LowerZoneColors.border,
              ),
            ),
            child: Text(
              'S',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: solo ? Colors.amber : LowerZoneColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Loop toggle (event-level setting for seamless looping)
  Widget _buildLoopToggle(bool looping, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!looping),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: looping ? Colors.blue.withValues(alpha: 0.3) : LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: looping ? Colors.blue : LowerZoneColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              looping ? Icons.repeat_on : Icons.repeat,
              size: 12,
              color: looping ? Colors.blue : LowerZoneColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              'Loop',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: looping ? Colors.blue : LowerZoneColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ActionType selector (Play/Stop/etc)
  Widget _buildActionTypeSelector(String actionType, ValueChanged<String> onChanged) {
    const actionTypes = [
      ('Play', Colors.green, Icons.play_arrow),
      ('Stop', Colors.red, Icons.stop),
      ('Pause', Colors.orange, Icons.pause),
      ('SetVolume', Colors.blue, Icons.volume_up),
    ];

    final current = actionTypes.firstWhere(
      (a) => a.$1 == actionType,
      orElse: () => actionTypes[0],
    );

    return PopupMenuButton<String>(
      initialValue: actionType,
      onSelected: onChanged,
      tooltip: 'Action Type',
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: current.$2.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: current.$2.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(current.$3, size: 12, color: current.$2),
            const SizedBox(width: 4),
            Text(
              current.$1,
              style: TextStyle(
                fontSize: 10,
                color: current.$2,
                fontWeight: FontWeight.bold,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 14, color: current.$2),
          ],
        ),
      ),
      itemBuilder: (context) => actionTypes.map((action) {
        return PopupMenuItem<String>(
          value: action.$1,
          height: 28,
          child: Row(
            children: [
              Icon(action.$3, size: 14, color: action.$2),
              const SizedBox(width: 8),
              Text(action.$1, style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW PARAMETER CONTROLS — FadeIn/FadeOut/Trim/AudioPath
  // ═══════════════════════════════════════════════════════════════════════════

  /// Compact fade control with time slider and curve selector
  Widget _buildCompactFadeControl({
    required String label,
    required double fadeMs,
    required CrossfadeCurve curve,
    required Color color,
    required ValueChanged<double> onFadeChanged,
    required ValueChanged<CrossfadeCurve> onCurveChanged,
  }) {
    const curves = [
      (CrossfadeCurve.linear, 'Linear', Icons.linear_scale),
      (CrossfadeCurve.equalPower, 'EqPow', Icons.auto_graph),
      (CrossfadeCurve.sCurve, 'S-Curve', Icons.ssid_chart),
      (CrossfadeCurve.sinCos, 'Sin/Cos', Icons.waves),
    ];

    final currentCurve = curves.firstWhere(
      (c) => c.$1 == curve,
      orElse: () => curves[0],
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon
        Icon(
          label == 'FadeIn' ? Icons.trending_up : Icons.trending_down,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        // Time slider
        SizedBox(
          width: 60,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: color,
              inactiveTrackColor: LowerZoneColors.bgSurface,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: fadeMs.clamp(0.0, 5000.0),
              min: 0.0,
              max: 5000.0, // Up to 5 seconds fade
              onChanged: onFadeChanged,
            ),
          ),
        ),
        // Time display
        SizedBox(
          width: 42,
          child: Text(
            '${fadeMs.toInt()}ms',
            style: TextStyle(
              fontSize: 9,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ),
        // Curve selector
        PopupMenuButton<CrossfadeCurve>(
          initialValue: curve,
          onSelected: onCurveChanged,
          tooltip: '$label Curve',
          padding: EdgeInsets.zero,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(currentCurve.$3, size: 10, color: color),
                Icon(Icons.arrow_drop_down, size: 12, color: color),
              ],
            ),
          ),
          itemBuilder: (context) => curves.map((c) {
            return PopupMenuItem<CrossfadeCurve>(
              value: c.$1,
              height: 28,
              child: Row(
                children: [
                  Icon(c.$3, size: 14, color: c.$1 == curve ? color : Colors.grey),
                  const SizedBox(width: 8),
                  Text(c.$2, style: TextStyle(fontSize: 11, color: c.$1 == curve ? color : null)),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Compact trim control with start/end markers
  Widget _buildCompactTrimControl({
    required double trimStartMs,
    required double trimEndMs,
    required double durationMs,
    required ValueChanged<double> onTrimStartChanged,
    required ValueChanged<double> onTrimEndChanged,
  }) {
    final maxDuration = durationMs > 0 ? durationMs : 10000.0; // Default 10s if unknown

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.content_cut, size: 14, color: Colors.pink),
        const SizedBox(width: 4),
        // Trim Start
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Start', style: TextStyle(fontSize: 8, color: LowerZoneColors.textTertiary)),
            SizedBox(
              width: 50,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                  activeTrackColor: Colors.pink,
                  inactiveTrackColor: LowerZoneColors.bgSurface,
                  thumbColor: Colors.pink,
                ),
                child: Slider(
                  value: trimStartMs.clamp(0.0, maxDuration),
                  min: 0.0,
                  max: maxDuration,
                  onChanged: onTrimStartChanged,
                ),
              ),
            ),
            Text(
              '${trimStartMs.toInt()}ms',
              style: TextStyle(fontSize: 8, color: Colors.pink, fontFamily: 'monospace'),
            ),
          ],
        ),
        const SizedBox(width: 8),
        // Trim End
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('End', style: TextStyle(fontSize: 8, color: LowerZoneColors.textTertiary)),
            SizedBox(
              width: 50,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                  activeTrackColor: Colors.pink,
                  inactiveTrackColor: LowerZoneColors.bgSurface,
                  thumbColor: Colors.pink,
                ),
                child: Slider(
                  value: trimEndMs.clamp(0.0, maxDuration),
                  min: 0.0,
                  max: maxDuration,
                  onChanged: onTrimEndChanged,
                ),
              ),
            ),
            Text(
              trimEndMs > 0 ? '${trimEndMs.toInt()}ms' : 'End',
              style: TextStyle(fontSize: 8, color: Colors.pink, fontFamily: 'monospace'),
            ),
          ],
        ),
      ],
    );
  }

  /// Audio path selector with file picker
  Widget _buildAudioPathSelector({
    required String audioPath,
    required ValueChanged<String> onPathChanged,
  }) {
    final fileName = audioPath.isNotEmpty
        ? audioPath.split('/').last.split('\\').last
        : 'No file';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.audio_file, size: 14, color: Colors.purple),
        const SizedBox(width: 4),
        // File name display (clickable)
        GestureDetector(
          onTap: () async {
            // Show audio file picker dialog
            final newPath = await AudioWaveformPickerDialog.show(
              context,
              title: 'Select Audio File',
              initialDirectory: audioPath.isNotEmpty
                  ? audioPath.substring(0, audioPath.lastIndexOf('/'))
                  : null,
            );
            if (newPath != null && newPath.isNotEmpty) {
              onPathChanged(newPath);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            constraints: const BoxConstraints(maxWidth: 120),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.purple.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    fileName,
                    style: TextStyle(
                      fontSize: 9,
                      color: audioPath.isNotEmpty ? Colors.purple : LowerZoneColors.textTertiary,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.folder_open, size: 10, color: Colors.purple),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Compact pan control for action strip
  Widget _buildCompactPanControl(double pan, ValueChanged<double> onChanged) {
    String formatPan(double v) {
      if (v.abs() < 0.01) return 'C';
      final percent = (v.abs() * 100).toInt();
      return v < 0 ? 'L$percent' : 'R$percent';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label
        Text(
          'Pan',
          style: TextStyle(
            fontSize: LowerZoneTypography.sizeLabel,
            color: LowerZoneColors.textSecondary,
          ),
        ),
        const SizedBox(width: 8),
        // Slider
        SizedBox(
          width: 100,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: Colors.cyan,
              inactiveTrackColor: LowerZoneColors.bgSurface,
              thumbColor: Colors.cyan,
              overlayColor: Colors.cyan.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: pan,
              min: -1.0,
              max: 1.0,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Value display
        SizedBox(
          width: 32,
          child: Text(
            formatPan(pan),
            style: TextStyle(
              fontSize: LowerZoneTypography.sizeBadge,
              color: Colors.cyan,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Quick presets
        _buildPanPresetButton('L', -1.0, pan, onChanged),
        _buildPanPresetButton('C', 0.0, pan, onChanged),
        _buildPanPresetButton('R', 1.0, pan, onChanged),
      ],
    );
  }

  Widget _buildPanPresetButton(String label, double value, double currentPan, ValueChanged<double> onChanged) {
    final isActive = (currentPan - value).abs() < 0.01;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.cyan.withValues(alpha: 0.3) : LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isActive ? Colors.cyan : LowerZoneColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? Colors.cyan : LowerZoneColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RTPC CURVE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _RtpcCurvePainter extends CustomPainter {
  final Color color;
  final RtpcCurve? curve;
  final double currentValue; // normalized 0-1

  _RtpcCurvePainter({required this.color, this.curve, this.currentValue = -1});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final gridPaint = Paint()
      ..color = LowerZoneColors.border.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Draw grid
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (int i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Evaluate the real curve at multiple points
    final curveObj = curve ?? const RtpcCurve();
    final path = Path();
    final fillPath = Path();

    const steps = 50;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = t * size.width;
      final y = size.height * (1.0 - curveObj.evaluate(t));
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(0, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw curve control points
    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    if (curve != null) {
      for (final pt in curve!.points) {
        final px = pt.x * size.width;
        final py = size.height * (1.0 - pt.y);
        canvas.drawCircle(Offset(px, py), 4, pointPaint);
      }
    }

    // Draw current value indicator
    if (currentValue >= 0 && currentValue <= 1) {
      final cx = currentValue * size.width;
      final cy = size.height * (1.0 - curveObj.evaluate(currentValue));
      final indicatorPaint = Paint()
        ..color = const Color(0xFFFFD700)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy), 5, indicatorPaint);
      // Vertical line at current position
      final linePaint = Paint()
        ..color = const Color(0xFFFFD700).withValues(alpha: 0.4)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RtpcCurvePainter oldDelegate) =>
      curve != oldDelegate.curve ||
      currentValue != oldDelegate.currentValue ||
      color != oldDelegate.color;
}
