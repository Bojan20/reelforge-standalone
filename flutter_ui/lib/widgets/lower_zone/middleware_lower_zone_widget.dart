// Middleware Lower Zone Widget
//
// Complete Lower Zone for Middleware section with:
// - Context bar (Super-tabs + Sub-tabs)
// - Slot Context Bar (Stage, Feature, State, Target, Trigger)
// - Content panel (switches based on current tab)
// - Action strip (context-aware actions)
// - Resizable height
// - Integrated Middleware panels (Ducking, Random, Sequence, Blend, Bus Hierarchy, etc.)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'middleware_lower_zone_controller.dart';
import 'lower_zone_types.dart';
import 'lower_zone_context_bar.dart';
import 'lower_zone_action_strip.dart';
import '../../providers/middleware_provider.dart';
import '../middleware/ducking_matrix_panel.dart';
import '../middleware/random_container_panel.dart';
import '../middleware/sequence_container_panel.dart';
import '../middleware/blend_container_panel.dart';
import '../middleware/bus_hierarchy_panel.dart';
import '../middleware/event_editor_panel.dart';
import '../middleware/events_folder_panel.dart';
import '../middleware/event_debugger_panel.dart';
import '../middleware/rtpc_debugger_panel.dart';
import '../middleware/dsp_profiler_panel.dart';
import '../middleware/priority_tier_preset_panel.dart';
// AuxSendPanel requires external dependencies, use placeholder for now

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

  /// Slot Context Bar — always visible in Middleware
  Widget _buildSlotContextBar() {
    return Container(
      height: 28,
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
      MiddlewareEventsSubTab.editor => const EventEditorPanel(),
      MiddlewareEventsSubTab.triggers => _buildTriggersPanel(),
      MiddlewareEventsSubTab.debug => const EventDebuggerPanel(),
    };
  }

  Widget _buildTriggersPanel() => _buildCompactTriggersPanel();

  /// Compact triggers panel
  Widget _buildCompactTriggersPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('TRIGGER CONDITIONS', Icons.bolt),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                // Trigger list
                Expanded(
                  flex: 2,
                  child: _buildTriggersList(),
                ),
                const SizedBox(width: 12),
                // Trigger editor
                Expanded(
                  flex: 3,
                  child: _buildTriggerEditor(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTriggersList() {
    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: ListView(
        padding: const EdgeInsets.all(4),
        children: [
          _buildTriggerItem('OnSpinStart', 'Stage == SPIN_START', true),
          _buildTriggerItem('OnBigWin', 'WinTier >= 3', false),
          _buildTriggerItem('OnFeature', 'Feature != BASE', false),
          _buildTriggerItem('OnJackpot', 'Jackpot == true', false),
        ],
      ),
    );
  }

  Widget _buildTriggerItem(String name, String condition, bool isSelected) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isSelected ? LowerZoneColors.middlewareAccent.withValues(alpha: 0.1) : null,
        border: Border(
          left: BorderSide(
            color: isSelected ? LowerZoneColors.middlewareAccent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isSelected ? LowerZoneColors.middlewareAccent : LowerZoneColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            condition,
            style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildTriggerEditor() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OnSpinStart',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: LowerZoneColors.middlewareAccent,
            ),
          ),
          const SizedBox(height: 12),
          _buildConditionRow('Stage', '==', 'SPIN_START'),
          const Spacer(),
          Row(
            children: [
              _buildEditorButton(Icons.add, 'Add Condition'),
              const Spacer(),
              _buildEditorButton(Icons.check, 'Apply', isPrimary: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConditionRow(String param, String op, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          _buildConditionChip(param, LowerZoneColors.textPrimary),
          const SizedBox(width: 8),
          _buildConditionChip(op, LowerZoneColors.middlewareAccent),
          const SizedBox(width: 8),
          _buildConditionChip(value, LowerZoneColors.success),
          const Spacer(),
          Icon(Icons.delete_outline, size: 14, color: LowerZoneColors.textMuted),
        ],
      ),
    );
  }

  Widget _buildConditionChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildEditorButton(IconData icon, String label, {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isPrimary
            ? LowerZoneColors.middlewareAccent.withValues(alpha: 0.2)
            : LowerZoneColors.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isPrimary ? LowerZoneColors.middlewareAccent : LowerZoneColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isPrimary ? LowerZoneColors.middlewareAccent : LowerZoneColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isPrimary ? LowerZoneColors.middlewareAccent : LowerZoneColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Compact actions panel
  Widget _buildCompactActionsPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('EVENT ACTIONS', Icons.play_circle),
          const SizedBox(height: 12),
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
    };
  }

  Widget _buildCurvesPanel() => _buildCompactRtpcCurves();
  Widget _buildBindingsPanel() => _buildCompactBindingsPanel();
  Widget _buildMetersPanel() => _buildCompactMetersPanel();

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
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('SWITCH CONTAINER', Icons.swap_horiz),
          const SizedBox(height: 12),
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
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('ROUTING MATRIX', Icons.grid_on),
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

  /// Compact RTPC Curves
  Widget _buildCompactRtpcCurves() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('RTPC CURVES', Icons.show_chart),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                // Curve list
                SizedBox(
                  width: 120,
                  child: Container(
                    decoration: BoxDecoration(
                      color: LowerZoneColors.bgDeepest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: LowerZoneColors.border),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(4),
                      children: [
                        _buildCurveListItem('Volume → Distance', true),
                        _buildCurveListItem('Pitch → Speed', false),
                        _buildCurveListItem('LPF → Distance', false),
                        _buildCurveListItem('Reverb → Room', false),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Curve editor
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: LowerZoneColors.bgDeepest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: LowerZoneColors.border),
                    ),
                    child: CustomPaint(
                      painter: _RtpcCurvePainter(color: LowerZoneColors.middlewareAccent),
                      size: Size.infinite,
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

  /// Compact Bindings Panel
  Widget _buildCompactBindingsPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('PARAMETER BINDINGS', Icons.link),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _buildBindingRow('WinAmount', 'Volume', '0-1', 'Linear'),
                _buildBindingRow('Distance', 'LPF Cutoff', '0-1000', 'Exp'),
                _buildBindingRow('Speed', 'Pitch', '0.5-2.0', 'Linear'),
                _buildBindingRow('Health', 'Reverb Send', '0-100', 'S-Curve'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBindingRow(String source, String target, String range, String curve) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Row(
        children: [
          _buildBindingChip(source, LowerZoneColors.middlewareAccent),
          Icon(Icons.arrow_right_alt, size: 16, color: LowerZoneColors.textMuted),
          _buildBindingChip(target, const Color(0xFF40C8FF)),
          const Spacer(),
          Text(range, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(curve, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textSecondary)),
          ),
        ],
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
      ),
    );
  }

  /// Compact Meters Panel
  Widget _buildCompactMetersPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('REAL-TIME METERS', Icons.bar_chart),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMeterColumn('WinAmount', 0.7),
                _buildMeterColumn('Distance', 0.3),
                _buildMeterColumn('Speed', 0.5),
                _buildMeterColumn('Health', 0.9),
                _buildMeterColumn('Tension', 0.4),
                _buildMeterColumn('Progress', 0.6),
              ],
            ),
          ),
        ],
      ),
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
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('AUDIO BAKING', Icons.local_fire_department),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                // Bake settings
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: LowerZoneColors.bgDeepest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: LowerZoneColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBakeOption('Format', 'WAV 48kHz/24bit'),
                        _buildBakeOption('Quality', 'High'),
                        _buildBakeOption('Normalize', 'Peak -1dB'),
                        _buildBakeOption('Dithering', 'None'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Bake button
                Container(
                  width: 100,
                  decoration: BoxDecoration(
                    color: LowerZoneColors.middlewareAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.middlewareAccent),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.local_fire_department, size: 32, color: LowerZoneColors.middlewareAccent),
                      const SizedBox(height: 8),
                      Text(
                        'BAKE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: LowerZoneColors.middlewareAccent,
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

  Widget _buildBakeOption(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('SOUNDBANK GENERATOR', Icons.sd_storage),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _buildSoundbankItem('Init.bnk', '2.4 MB', true),
                _buildSoundbankItem('Base_Game.bnk', '12.8 MB', true),
                _buildSoundbankItem('FreeSpins.bnk', '8.1 MB', false),
                _buildSoundbankItem('Jackpot.bnk', '4.2 MB', false),
                _buildSoundbankItem('UI_Sounds.bnk', '1.6 MB', true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundbankItem(String name, String size, bool isLoaded) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isLoaded ? LowerZoneColors.success.withValues(alpha: 0.3) : LowerZoneColors.border),
      ),
      child: Row(
        children: [
          Icon(
            isLoaded ? Icons.check_circle : Icons.circle_outlined,
            size: 14,
            color: isLoaded ? LowerZoneColors.success : LowerZoneColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary))),
          Text(size, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
        ],
      ),
    );
  }

  /// Compact Validate Panel
  Widget _buildCompactValidatePanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildPanelHeader('REFERENCE VALIDATOR', Icons.check_circle),
              const Spacer(),
              _buildEditorButton(Icons.refresh, 'Validate All', isPrimary: true),
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
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  _buildValidationResult('All events have audio', true),
                  _buildValidationResult('All switches have defaults', true),
                  _buildValidationResult('No orphan RTPCs', true),
                  _buildValidationResult('Missing audio: feature_win.wav', false),
                  _buildValidationResult('Unused event: old_bonus_sound', false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationResult(String message, bool isValid) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
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
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPanelHeader('EXPORT PACKAGE', Icons.inventory_2),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _buildPackageOption('Platform', 'All'),
                      _buildPackageOption('Compression', 'Vorbis Q5'),
                      _buildPackageOption('Banks', '5 selected'),
                      _buildPackageOption('Size', '~28.5 MB'),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 120,
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
                      Icon(Icons.download, size: 32, color: LowerZoneColors.middlewareAccent),
                      const SizedBox(height: 8),
                      Text(
                        'EXPORT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: LowerZoneColors.middlewareAccent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Ready',
                        style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
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

  Widget _buildPackageOption(String label, String value) {
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

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER PANELS
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

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION STRIP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActionStrip() {
    final actions = switch (widget.controller.superTab) {
      MiddlewareSuperTab.events => MiddlewareActions.forEvents(),
      MiddlewareSuperTab.containers => MiddlewareActions.forContainers(),
      MiddlewareSuperTab.routing => MiddlewareActions.forRouting(),
      MiddlewareSuperTab.rtpc => MiddlewareActions.forRtpc(),
      MiddlewareSuperTab.deliver => MiddlewareActions.forDeliver(),
    };

    // Get event count from provider if available
    String statusText = 'Events: --';
    try {
      final mw = context.read<MiddlewareProvider>();
      statusText = 'Events: ${mw.compositeEvents.length}';
    } catch (_) {
      // Provider not available
    }

    return LowerZoneActionStrip(
      actions: actions,
      accentColor: widget.controller.accentColor,
      statusText: statusText,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RTPC CURVE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _RtpcCurvePainter extends CustomPainter {
  final Color color;

  _RtpcCurvePainter({required this.color});

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

    // Draw an exponential decay curve
    final path = Path();
    final fillPath = Path();

    path.moveTo(0, size.height * 0.9);
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, size.height * 0.9);

    const steps = 50;
    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final x = t * size.width;
      // Exponential decay: y = start * e^(-k*x)
      final y = size.height * (0.9 - 0.8 * (1 - (1 / (1 + 3 * t))));
      path.lineTo(x, y);
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw control points
    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final points = [
      Offset(0, size.height * 0.9),
      Offset(size.width * 0.3, size.height * 0.5),
      Offset(size.width * 0.7, size.height * 0.2),
      Offset(size.width, size.height * 0.15),
    ];

    for (final point in points) {
      canvas.drawCircle(point, 4, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
