/// Cycle Actions Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// #25: Sequential action cycling — each invocation executes the next step.
///
/// Features:
/// - Create/edit/delete cycle actions
/// - Add command or action steps with reorder
/// - Execute cycles manually, reset position
/// - Built-in presets (Monitor Mode, Grid Resolution, Zoom, Smart Mute)
library;

import 'package:flutter/material.dart';
import '../../../../services/cycle_action_service.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class CycleActionsPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const CycleActionsPanel({super.key, this.onAction});

  @override
  State<CycleActionsPanel> createState() => _CycleActionsPanelState();
}

class _CycleActionsPanelState extends State<CycleActionsPanel> {
  final _service = CycleActionService.instance;
  String? _selectedCycleId;
  bool _showAddStep = false;

  late TextEditingController _stepLabelCtrl;
  late TextEditingController _stepTargetCtrl;
  late FocusNode _stepLabelFocus;
  late FocusNode _stepTargetFocus;
  CycleStepType _newStepType = CycleStepType.command;

  late TextEditingController _cycleNameCtrl;
  late FocusNode _cycleNameFocus;
  bool _showAddCycle = false;

  @override
  void initState() {
    super.initState();
    _stepLabelCtrl = TextEditingController();
    _stepTargetCtrl = TextEditingController();
    _stepLabelFocus = FocusNode();
    _stepTargetFocus = FocusNode();
    _cycleNameCtrl = TextEditingController();
    _cycleNameFocus = FocusNode();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _stepLabelCtrl.dispose();
    _stepTargetCtrl.dispose();
    _stepLabelFocus.dispose();
    _stepTargetFocus.dispose();
    _cycleNameCtrl.dispose();
    _cycleNameFocus.dispose();
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  CycleAction? get _selectedCycle =>
      _selectedCycleId != null ? _service.getCycle(_selectedCycleId!) : null;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 240, child: _buildCycleList()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        Expanded(flex: 2, child: _buildStepsEditor()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        SizedBox(width: 200, child: _buildActionsPanel()),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LEFT: Cycle List
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildCycleList() {
    final cycles = _service.cycles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(
            children: [
              FabSectionLabel('CYCLES'),
              const Spacer(),
              _iconBtn(Icons.add, 'New Cycle', () => setState(() => _showAddCycle = !_showAddCycle)),
              _iconBtn(Icons.auto_awesome, 'Load Presets', () => _service.loadPresets()),
            ],
          ),
        ),
        if (_showAddCycle) _buildAddCycleForm(),
        Expanded(
          child: cycles.isEmpty
              ? Center(
                  child: Text(
                    'No cycles defined.\nClick + or load presets.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: cycles.length,
                  itemBuilder: (_, i) => _buildCycleItem(cycles[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildAddCycleForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 26,
              child: TextField(
                controller: _cycleNameCtrl,
                focusNode: _cycleNameFocus,
                style: const TextStyle(fontSize: 11, color: FabFilterColors.textPrimary),
                decoration: _inputDeco('Cycle name...'),
                onSubmitted: (_) => _createCycle(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _iconBtn(Icons.check, 'Create', _createCycle),
        ],
      ),
    );
  }

  void _createCycle() {
    final name = _cycleNameCtrl.text.trim();
    if (name.isEmpty) return;
    final id = 'cycle_${DateTime.now().millisecondsSinceEpoch}';
    _service.addCycle(CycleAction(id: id, name: name, steps: []));
    _cycleNameCtrl.clear();
    setState(() {
      _showAddCycle = false;
      _selectedCycleId = id;
    });
  }

  Widget _buildCycleItem(CycleAction cycle) {
    final selected = cycle.id == _selectedCycleId;
    return InkWell(
      onTap: () => setState(() => _selectedCycleId = cycle.id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? FabFilterColors.cyan.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(color: FabFilterColors.cyan.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          children: [
            Icon(Icons.replay, size: 14,
              color: selected ? FabFilterColors.cyan : FabFilterColors.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cycle.name, style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? FabFilterColors.textPrimary : FabFilterColors.textSecondary,
                  ), overflow: TextOverflow.ellipsis),
                  if (cycle.description != null)
                    Text(cycle.description!, style: TextStyle(
                      fontSize: 9, color: FabFilterColors.textTertiary,
                    ), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Text('${cycle.stepCount}', style: TextStyle(
              fontSize: 10, color: FabFilterColors.textTertiary)),
            const SizedBox(width: 4),
            Container(
              width: 16, height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cycle.isEmpty
                    ? Colors.transparent
                    : FabFilterColors.cyan.withValues(alpha: 0.2),
              ),
              child: Text(
                cycle.isEmpty ? '-' : '${cycle.currentIndex + 1}',
                style: TextStyle(fontSize: 9, color: FabFilterColors.cyan),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CENTER: Steps Editor
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildStepsEditor() {
    final cycle = _selectedCycle;
    if (cycle == null) {
      return Center(child: Text('Select a cycle to view steps',
        style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 12)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(
            children: [
              FabSectionLabel('STEPS'),
              const SizedBox(width: 8),
              Text(cycle.name, style: const TextStyle(
                fontSize: 11, color: FabFilterColors.cyan)),
              const Spacer(),
              _iconBtn(Icons.add, 'Add Step', () =>
                setState(() => _showAddStep = !_showAddStep)),
            ],
          ),
        ),
        if (_showAddStep) _buildAddStepForm(),
        Expanded(
          child: cycle.steps.isEmpty
              ? Center(child: Text('No steps. Click + to add.',
                  style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 11)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: cycle.steps.length,
                  itemBuilder: (_, i) => _buildStepItem(cycle, i),
                ),
        ),
      ],
    );
  }

  Widget _buildAddStepForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _typeChip('Command', CycleStepType.command),
            const SizedBox(width: 4),
            _typeChip('Action', CycleStepType.action),
          ]),
          const SizedBox(height: 6),
          SizedBox(height: 26, child: TextField(
            controller: _stepLabelCtrl,
            focusNode: _stepLabelFocus,
            style: const TextStyle(fontSize: 11, color: FabFilterColors.textPrimary),
            decoration: _inputDeco('Step label...'),
          )),
          const SizedBox(height: 4),
          SizedBox(height: 26, child: TextField(
            controller: _stepTargetCtrl,
            focusNode: _stepTargetFocus,
            style: const TextStyle(fontSize: 11, color: FabFilterColors.textPrimary),
            decoration: _inputDeco(
              _newStepType == CycleStepType.command
                  ? 'Command ID (e.g. view.zoom_fit)...'
                  : 'Action name (e.g. setMonitorMode)...',
            ),
            onSubmitted: (_) => _addStep(),
          )),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _iconBtn(Icons.close, 'Cancel', () => setState(() => _showAddStep = false)),
            const SizedBox(width: 4),
            _iconBtn(Icons.check, 'Add', _addStep),
          ]),
        ],
      ),
    );
  }

  Widget _typeChip(String label, CycleStepType type) {
    final active = _newStepType == type;
    return GestureDetector(
      onTap: () => setState(() => _newStepType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? FabFilterColors.cyan.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? FabFilterColors.cyan : FabFilterColors.border),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 10,
          color: active ? FabFilterColors.cyan : FabFilterColors.textTertiary,
        )),
      ),
    );
  }

  void _addStep() {
    final cycleId = _selectedCycleId;
    if (cycleId == null) return;

    final label = _stepLabelCtrl.text.trim();
    final target = _stepTargetCtrl.text.trim();
    if (label.isEmpty || target.isEmpty) return;

    final id = 'step_${DateTime.now().millisecondsSinceEpoch}';
    final step = _newStepType == CycleStepType.command
        ? CycleStep.command(id: id, label: label, commandId: target)
        : CycleStep.action(id: id, label: label, actionName: target);

    _service.addStep(cycleId, step);
    _stepLabelCtrl.clear();
    _stepTargetCtrl.clear();
    setState(() => _showAddStep = false);
  }

  Widget _buildStepItem(CycleAction cycle, int index) {
    final step = cycle.steps[index];
    final isCurrent = index == cycle.currentIndex;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isCurrent ? FabFilterColors.cyan.withValues(alpha: 0.1) : FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: isCurrent
            ? Border.all(color: FabFilterColors.cyan.withValues(alpha: 0.3))
            : Border.all(color: FabFilterColors.border.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(width: 20, child: Text('${index + 1}', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              color: isCurrent ? FabFilterColors.cyan : FabFilterColors.textTertiary))),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: _stepColor(step.type).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              step.type == CycleStepType.command ? 'CMD'
                  : step.type == CycleStepType.action ? 'ACT' : 'IF',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                color: _stepColor(step.type)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label, style: TextStyle(fontSize: 11,
                  color: isCurrent ? FabFilterColors.textPrimary : FabFilterColors.textSecondary),
                  overflow: TextOverflow.ellipsis),
                Text(step.commandId ?? step.actionName ?? 'conditional',
                  style: TextStyle(fontSize: 9, color: FabFilterColors.textTertiary),
                  overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          _iconBtn(Icons.arrow_upward, 'Move Up',
            index > 0 ? () => _service.moveStepUp(cycle.id, index) : null),
          _iconBtn(Icons.arrow_downward, 'Move Down',
            index < cycle.steps.length - 1 ? () => _service.moveStepDown(cycle.id, index) : null),
          _iconBtn(Icons.close, 'Remove',
            () => _service.removeStep(cycle.id, step.id)),
        ],
      ),
    );
  }

  Color _stepColor(CycleStepType type) => switch (type) {
    CycleStepType.command => FabFilterColors.cyan,
    CycleStepType.action => FabFilterColors.green,
    CycleStepType.conditional => FabFilterColors.orange,
  };

  // ═════════════════════════════════════════════════════════════════════════
  // RIGHT: Actions Panel
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildActionsPanel() {
    final cycle = _selectedCycle;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FabSectionLabel('ACTIONS'),
          const SizedBox(height: 8),
          _actionButton(Icons.play_arrow, 'Execute Next',
            cycle != null && !cycle.isEmpty
                ? () {
                    _service.executeCycle(cycle.id);
                    widget.onAction?.call('cycleExecute', {'cycleId': cycle.id});
                  }
                : null),
          const SizedBox(height: 4),
          _actionButton(Icons.restart_alt, 'Reset',
            cycle != null ? () => _service.resetCycle(cycle.id) : null),
          const SizedBox(height: 4),
          _actionButton(Icons.copy, 'Duplicate',
            cycle != null ? () => _service.duplicateCycle(cycle.id) : null),
          const SizedBox(height: 4),
          _actionButton(Icons.delete_outline, 'Delete',
            cycle != null ? () {
              _service.removeCycle(cycle.id);
              setState(() => _selectedCycleId = null);
            } : null),
          const SizedBox(height: 12),
          _actionButton(Icons.refresh, 'Reset All',
            _service.count > 0 ? () => _service.resetAll() : null),
          const Spacer(),
          if (cycle != null) ...[
            const Divider(color: FabFilterColors.border, height: 16),
            Text('Steps: ${cycle.stepCount}',
              style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
            Text('Position: ${cycle.isEmpty ? "-" : "${cycle.currentIndex + 1}/${cycle.stepCount}"}',
              style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
            if (cycle.currentStep != null)
              Text('Next: ${cycle.currentStep!.label}',
                style: TextStyle(fontSize: 10, color: FabFilterColors.cyan)),
          ],
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return SizedBox(
      width: 24, height: 24,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        color: FabFilterColors.textSecondary,
        disabledColor: FabFilterColors.textDisabled,
        onPressed: onPressed,
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback? onPressed) {
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: 28,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: enabled ? FabFilterColors.bgMid : FabFilterColors.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FabFilterColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14,
                color: enabled ? FabFilterColors.textSecondary : FabFilterColors.textDisabled),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11,
                color: enabled ? FabFilterColors.textSecondary : FabFilterColors.textDisabled)),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: FabFilterColors.textTertiary, fontSize: 11),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: FabFilterColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: FabFilterColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: FabFilterColors.cyan),
    ),
    filled: true,
    fillColor: FabFilterColors.bgMid,
  );
}
