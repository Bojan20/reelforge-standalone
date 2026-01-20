/// Scenario Editor Panel
///
/// Visual editor for DemoScenario creation and management:
/// - Create/Edit/Delete scenarios
/// - Visual spin sequence editor
/// - Drag & drop reordering
/// - Loop mode configuration
/// - Import/Export JSON
/// - Playback preview
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';
import '../../src/rust/native_ffi.dart';
import '../../src/rust/slot_lab_v2_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SCENARIO EDITOR
// ═══════════════════════════════════════════════════════════════════════════════

class ScenarioEditorPanel extends StatefulWidget {
  final VoidCallback? onClose;
  final ValueChanged<DemoScenario>? onScenarioSelected;
  final ValueChanged<DemoScenario>? onScenarioChanged;

  const ScenarioEditorPanel({
    super.key,
    this.onClose,
    this.onScenarioSelected,
    this.onScenarioChanged,
  });

  @override
  State<ScenarioEditorPanel> createState() => _ScenarioEditorPanelState();
}

class _ScenarioEditorPanelState extends State<ScenarioEditorPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // State
  List<ScenarioInfo> _scenarios = [];
  DemoScenario? _selectedScenario;
  DemoScenario? _editingScenario;
  bool _isDirty = false;
  bool _isLoading = false;

  // Form controllers
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _loopMode = 'once';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadScenarios();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _loadScenarios() {
    setState(() => _isLoading = true);
    try {
      final scenarios = NativeFFI.instance.slotLabScenarioList();
      setState(() {
        _scenarios = scenarios;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('[ScenarioEditor] Failed to load scenarios: $e');
    }
  }

  void _selectScenario(ScenarioInfo info) {
    final scenario = NativeFFI.instance.slotLabScenarioGet(info.id);
    if (scenario != null) {
      setState(() {
        _selectedScenario = scenario;
        _editingScenario = scenario;
        _nameController.text = scenario.name;
        _descController.text = scenario.description;
        _loopMode = scenario.loopMode;
        _isDirty = false;
      });
      widget.onScenarioSelected?.call(scenario);
    }
  }

  void _createNewScenario() {
    final newScenario = DemoScenario(
      id: 'scenario_${DateTime.now().millisecondsSinceEpoch}',
      name: 'New Scenario',
      description: 'Custom demo scenario',
      sequence: [],
      loopMode: 'once',
    );
    setState(() {
      _selectedScenario = null;
      _editingScenario = newScenario;
      _nameController.text = newScenario.name;
      _descController.text = newScenario.description;
      _loopMode = newScenario.loopMode;
      _isDirty = true;
    });
    _tabController.animateTo(1); // Switch to editor tab
  }

  void _markDirty() {
    if (!_isDirty) {
      setState(() => _isDirty = true);
    }
  }

  void _saveScenario() {
    if (_editingScenario == null) return;

    final updated = DemoScenario(
      id: _editingScenario!.id,
      name: _nameController.text,
      description: _descController.text,
      sequence: _editingScenario!.sequence,
      loopMode: _loopMode,
    );

    final json = jsonEncode(updated.toJson());
    if (NativeFFI.instance.slotLabScenarioRegister(json)) {
      setState(() {
        _editingScenario = updated;
        _selectedScenario = updated;
        _isDirty = false;
      });
      _loadScenarios();
      widget.onScenarioChanged?.call(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scenario saved')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save scenario')),
      );
    }
  }

  void _deleteScenario(ScenarioInfo info) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        title: const Text('Delete Scenario', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${info.name}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: FluxForgeTheme.accentRed),
            onPressed: () {
              // Note: deletion would need FFI support
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Scenario deletion not yet implemented in FFI')),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),
          // Tab bar
          _buildTabBar(),
          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildScenarioList(),
                _buildScenarioEditor(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.playlist_play, size: 18, color: FluxForgeTheme.accent),
          const SizedBox(width: 8),
          const Text(
            'Scenario Editor',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          if (_isDirty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Modified',
                style: TextStyle(color: Colors.orange, fontSize: 11),
              ),
            ),
          const SizedBox(width: 8),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: widget.onClose,
              color: FluxForgeTheme.textMuted,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: FluxForgeTheme.accent,
        unselectedLabelColor: FluxForgeTheme.textMuted,
        indicatorColor: FluxForgeTheme.accent,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'SCENARIOS'),
          Tab(text: 'EDITOR'),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO LIST TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildScenarioList() {
    return Column(
      children: [
        // Toolbar
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.surface,
            border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                onPressed: _createNewScenario,
                tooltip: 'New Scenario',
                color: FluxForgeTheme.textMuted,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _loadScenarios,
                tooltip: 'Refresh',
                color: FluxForgeTheme.textMuted,
              ),
              const Spacer(),
              Text(
                '${_scenarios.length} scenarios',
                style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _scenarios.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.playlist_remove, size: 48, color: FluxForgeTheme.textMuted),
                          const SizedBox(height: 8),
                          Text(
                            'No scenarios found',
                            style: TextStyle(color: FluxForgeTheme.textMuted),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Create Scenario'),
                            onPressed: _createNewScenario,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _scenarios.length,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, index) => _buildScenarioCard(_scenarios[index]),
                    ),
        ),
      ],
    );
  }

  Widget _buildScenarioCard(ScenarioInfo scenario) {
    final isSelected = _selectedScenario?.id == scenario.id;

    IconData loopIcon;
    switch (scenario.loopMode) {
      case 'loop':
        loopIcon = Icons.loop;
        break;
      case 'ping_pong':
        loopIcon = Icons.swap_horiz;
        break;
      default:
        loopIcon = Icons.arrow_forward;
    }

    return Card(
      color: isSelected ? FluxForgeTheme.bgElevated : FluxForgeTheme.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _selectScenario(scenario),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(loopIcon, color: FluxForgeTheme.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scenario.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${scenario.spinCount} spins • ${scenario.loopMode}',
                      style: TextStyle(
                        color: FluxForgeTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 16),
                onPressed: () {
                  _selectScenario(scenario);
                  _tabController.animateTo(1);
                },
                color: FluxForgeTheme.textMuted,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: () => _deleteScenario(scenario),
                color: FluxForgeTheme.accentRed.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO EDITOR TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildScenarioEditor() {
    if (_editingScenario == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 48, color: FluxForgeTheme.textMuted),
            const SizedBox(height: 8),
            Text(
              'Select or create a scenario to edit',
              style: TextStyle(color: FluxForgeTheme.textMuted),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Toolbar
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.surface,
            border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
          ),
          child: Row(
            children: [
              // Export
              TextButton.icon(
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Export'),
                onPressed: _exportScenario,
                style: TextButton.styleFrom(
                  foregroundColor: FluxForgeTheme.textMuted,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              // Import
              TextButton.icon(
                icon: const Icon(Icons.upload, size: 16),
                label: const Text('Import'),
                onPressed: _importScenario,
                style: TextButton.styleFrom(
                  foregroundColor: FluxForgeTheme.textMuted,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              const Spacer(),
              // Save
              ElevatedButton(
                onPressed: _isDirty ? _saveScenario : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: FluxForgeTheme.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: FluxForgeTheme.border,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
        // Editor content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Metadata
                _buildSectionHeader('Scenario Info'),
                const SizedBox(height: 12),
                _buildTextField(
                  label: 'Name',
                  controller: _nameController,
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  label: 'Description',
                  controller: _descController,
                  onChanged: (_) => _markDirty(),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                _buildLoopModeSelector(),
                const SizedBox(height: 24),

                // Spin sequence
                _buildSectionHeader('Spin Sequence'),
                const SizedBox(height: 8),
                _buildSequenceToolbar(),
                const SizedBox(height: 8),
                _buildSpinSequence(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoopModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Loop Mode',
          style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'once', label: Text('Once'), icon: Icon(Icons.arrow_forward, size: 16)),
            ButtonSegment(value: 'loop', label: Text('Loop'), icon: Icon(Icons.loop, size: 16)),
            ButtonSegment(value: 'ping_pong', label: Text('Ping Pong'), icon: Icon(Icons.swap_horiz, size: 16)),
          ],
          selected: {_loopMode},
          onSelectionChanged: (set) {
            setState(() => _loopMode = set.first);
            _markDirty();
          },
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return FluxForgeTheme.accent;
              }
              return FluxForgeTheme.surface;
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildSequenceToolbar() {
    return Row(
      children: [
        // Add spin button
        PopupMenuButton<String>(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 16, color: Colors.white),
                SizedBox(width: 4),
                Text('Add Spin', style: TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
          onSelected: _addSpinWithOutcome,
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'lose', child: Text('Lose')),
            const PopupMenuItem(value: 'small_win', child: Text('Small Win')),
            const PopupMenuItem(value: 'medium_win', child: Text('Medium Win')),
            const PopupMenuItem(value: 'big_win', child: Text('Big Win')),
            const PopupMenuItem(value: 'mega_win', child: Text('Mega Win')),
            const PopupMenuItem(value: 'epic_win', child: Text('Epic Win')),
            const PopupMenuItem(value: 'free_spins', child: Text('Free Spins Trigger')),
            const PopupMenuItem(value: 'near_miss', child: Text('Near Miss')),
            const PopupMenuItem(value: 'cascade', child: Text('Cascade')),
            const PopupMenuItem(value: 'jackpot', child: Text('Jackpot')),
          ],
        ),
        const SizedBox(width: 8),
        // Clear all
        TextButton.icon(
          icon: Icon(Icons.clear_all, size: 16, color: FluxForgeTheme.textMuted),
          label: Text('Clear', style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12)),
          onPressed: () {
            if (_editingScenario != null && _editingScenario!.sequence.isNotEmpty) {
              setState(() {
                _editingScenario = DemoScenario(
                  id: _editingScenario!.id,
                  name: _editingScenario!.name,
                  description: _editingScenario!.description,
                  sequence: [],
                  loopMode: _editingScenario!.loopMode,
                );
              });
              _markDirty();
            }
          },
        ),
        const Spacer(),
        Text(
          '${_editingScenario?.sequence.length ?? 0} spins',
          style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildSpinSequence() {
    final sequence = _editingScenario?.sequence ?? [];

    if (sequence.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.border, style: BorderStyle.solid),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_add, size: 32, color: FluxForgeTheme.textMuted),
            const SizedBox(height: 8),
            Text(
              'No spins in sequence',
              style: TextStyle(color: FluxForgeTheme.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              'Click "Add Spin" to begin',
              style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sequence.length,
      onReorder: (oldIndex, newIndex) {
        if (oldIndex < newIndex) newIndex--;
        setState(() {
          final item = sequence.removeAt(oldIndex);
          sequence.insert(newIndex, item);
          _editingScenario = DemoScenario(
            id: _editingScenario!.id,
            name: _editingScenario!.name,
            description: _editingScenario!.description,
            sequence: sequence,
            loopMode: _editingScenario!.loopMode,
          );
        });
        _markDirty();
      },
      itemBuilder: (context, index) => _buildSpinItem(sequence[index], index),
    );
  }

  Widget _buildSpinItem(ScriptedSpin spin, int index) {
    final outcome = spin.outcome;
    final outcomeType = outcome['type'] as String? ?? 'custom';
    final note = spin.note;
    final delay = spin.delayBeforeMs;

    Color color;
    IconData icon;
    switch (outcomeType) {
      case 'lose':
        color = FluxForgeTheme.textMuted;
        icon = Icons.close;
        break;
      case 'small_win':
        color = Colors.green.shade400;
        icon = Icons.check;
        break;
      case 'medium_win':
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'big_win':
        color = Colors.orange;
        icon = Icons.star;
        break;
      case 'mega_win':
        color = Colors.purple;
        icon = Icons.star;
        break;
      case 'epic_win':
        color = Colors.red;
        icon = Icons.stars;
        break;
      case 'free_spins':
        color = Colors.cyan;
        icon = Icons.autorenew;
        break;
      case 'near_miss':
        color = Colors.amber;
        icon = Icons.warning;
        break;
      case 'cascade':
        color = Colors.blue;
        icon = Icons.layers;
        break;
      case 'jackpot':
        color = Colors.yellow;
        icon = Icons.diamond;
        break;
      default:
        color = FluxForgeTheme.accent;
        icon = Icons.help_outline;
    }

    return Card(
      key: ValueKey('spin_$index'),
      color: FluxForgeTheme.surface,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: 18),
        ),
        title: Row(
          children: [
            Text(
              '#${index + 1}',
              style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
            ),
            const SizedBox(width: 8),
            Text(
              _outcomeLabel(outcomeType),
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            if (delay != null) ...[
              Icon(Icons.timer, size: 12, color: FluxForgeTheme.textMuted),
              const SizedBox(width: 2),
              Text(
                '${delay.toInt()}ms',
                style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
              ),
              const SizedBox(width: 8),
            ],
            if (note != null && note.isNotEmpty)
              Expanded(
                child: Text(
                  note,
                  style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 16),
              onPressed: () => _editSpin(index),
              color: FluxForgeTheme.textMuted,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              onPressed: () => _deleteSpin(index),
              color: FluxForgeTheme.accentRed.withValues(alpha: 0.7),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const Icon(Icons.drag_handle, size: 16, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  String _outcomeLabel(String type) {
    switch (type) {
      case 'lose': return 'Lose';
      case 'small_win': return 'Small Win';
      case 'medium_win': return 'Medium Win';
      case 'big_win': return 'Big Win';
      case 'mega_win': return 'Mega Win';
      case 'epic_win': return 'Epic Win';
      case 'free_spins': return 'Free Spins';
      case 'near_miss': return 'Near Miss';
      case 'cascade': return 'Cascade';
      case 'jackpot': return 'Jackpot';
      default: return type;
    }
  }

  void _addSpinWithOutcome(String outcomeType) {
    if (_editingScenario == null) return;

    final newSpin = ScriptedSpin(
      outcome: {'type': outcomeType},
      delayBeforeMs: null,
      note: null,
    );

    final newSequence = List<ScriptedSpin>.from(_editingScenario!.sequence)..add(newSpin);
    setState(() {
      _editingScenario = DemoScenario(
        id: _editingScenario!.id,
        name: _editingScenario!.name,
        description: _editingScenario!.description,
        sequence: newSequence,
        loopMode: _editingScenario!.loopMode,
      );
    });
    _markDirty();
  }

  void _editSpin(int index) {
    if (_editingScenario == null) return;
    final spin = _editingScenario!.sequence[index];

    showDialog(
      context: context,
      builder: (context) => _SpinEditDialog(
        spin: spin,
        onSave: (updated) {
          final newSequence = List<ScriptedSpin>.from(_editingScenario!.sequence);
          newSequence[index] = updated;
          setState(() {
            _editingScenario = DemoScenario(
              id: _editingScenario!.id,
              name: _editingScenario!.name,
              description: _editingScenario!.description,
              sequence: newSequence,
              loopMode: _editingScenario!.loopMode,
            );
          });
          _markDirty();
        },
      ),
    );
  }

  void _deleteSpin(int index) {
    if (_editingScenario == null) return;

    final newSequence = List<ScriptedSpin>.from(_editingScenario!.sequence);
    newSequence.removeAt(index);
    setState(() {
      _editingScenario = DemoScenario(
        id: _editingScenario!.id,
        name: _editingScenario!.name,
        description: _editingScenario!.description,
        sequence: newSequence,
        loopMode: _editingScenario!.loopMode,
      );
    });
    _markDirty();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    ValueChanged<String>? onChanged,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          maxLines: maxLines,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: FluxForgeTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: FluxForgeTheme.accent),
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IMPORT/EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  void _exportScenario() {
    if (_editingScenario == null) return;

    final scenario = DemoScenario(
      id: _editingScenario!.id,
      name: _nameController.text,
      description: _descController.text,
      sequence: _editingScenario!.sequence,
      loopMode: _loopMode,
    );

    final json = const JsonEncoder.withIndent('  ').convert(scenario.toJson());
    Clipboard.setData(ClipboardData(text: json));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scenario JSON copied to clipboard')),
    );
  }

  void _importScenario() {
    showDialog(
      context: context,
      builder: (context) => _ImportScenarioDialog(
        onImport: (json) {
          try {
            final map = jsonDecode(json) as Map<String, dynamic>;
            final scenario = DemoScenario.fromJson(map);
            setState(() {
              _editingScenario = scenario;
              _nameController.text = scenario.name;
              _descController.text = scenario.description;
              _loopMode = scenario.loopMode;
            });
            _markDirty();
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Invalid JSON: $e')),
            );
          }
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPIN EDIT DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class _SpinEditDialog extends StatefulWidget {
  final ScriptedSpin spin;
  final ValueChanged<ScriptedSpin> onSave;

  const _SpinEditDialog({required this.spin, required this.onSave});

  @override
  State<_SpinEditDialog> createState() => _SpinEditDialogState();
}

class _SpinEditDialogState extends State<_SpinEditDialog> {
  late String _outcomeType;
  late TextEditingController _delayController;
  late TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _outcomeType = widget.spin.outcome['type'] as String? ?? 'lose';
    _delayController = TextEditingController(
      text: widget.spin.delayBeforeMs?.toInt().toString() ?? '',
    );
    _noteController = TextEditingController(text: widget.spin.note ?? '');
  }

  @override
  void dispose() {
    _delayController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      title: const Text('Edit Spin', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Outcome Type', style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            DropdownButton<String>(
              value: _outcomeType,
              isExpanded: true,
              dropdownColor: FluxForgeTheme.surface,
              style: const TextStyle(color: Colors.white),
              items: const [
                DropdownMenuItem(value: 'lose', child: Text('Lose')),
                DropdownMenuItem(value: 'small_win', child: Text('Small Win')),
                DropdownMenuItem(value: 'medium_win', child: Text('Medium Win')),
                DropdownMenuItem(value: 'big_win', child: Text('Big Win')),
                DropdownMenuItem(value: 'mega_win', child: Text('Mega Win')),
                DropdownMenuItem(value: 'epic_win', child: Text('Epic Win')),
                DropdownMenuItem(value: 'free_spins', child: Text('Free Spins')),
                DropdownMenuItem(value: 'near_miss', child: Text('Near Miss')),
                DropdownMenuItem(value: 'cascade', child: Text('Cascade')),
                DropdownMenuItem(value: 'jackpot', child: Text('Jackpot')),
              ],
              onChanged: (v) => setState(() => _outcomeType = v ?? 'lose'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _delayController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Delay Before (ms)',
                labelStyle: TextStyle(color: FluxForgeTheme.textMuted),
                hintText: 'e.g., 500',
                hintStyle: TextStyle(color: FluxForgeTheme.textMuted.withValues(alpha: 0.5)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Note',
                labelStyle: TextStyle(color: FluxForgeTheme.textMuted),
                hintText: 'Optional note',
                hintStyle: TextStyle(color: FluxForgeTheme.textMuted.withValues(alpha: 0.5)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final delay = double.tryParse(_delayController.text);
            final note = _noteController.text.isEmpty ? null : _noteController.text;
            widget.onSave(ScriptedSpin(
              outcome: {'type': _outcomeType},
              delayBeforeMs: delay,
              note: note,
            ));
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// IMPORT SCENARIO DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class _ImportScenarioDialog extends StatefulWidget {
  final ValueChanged<String> onImport;

  const _ImportScenarioDialog({required this.onImport});

  @override
  State<_ImportScenarioDialog> createState() => _ImportScenarioDialogState();
}

class _ImportScenarioDialogState extends State<_ImportScenarioDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      title: const Text('Import Scenario', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 400,
        height: 300,
        child: TextField(
          controller: _controller,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
          maxLines: null,
          expands: true,
          decoration: InputDecoration(
            hintText: 'Paste scenario JSON here...',
            hintStyle: TextStyle(color: FluxForgeTheme.textMuted),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onImport(_controller.text);
            Navigator.pop(context);
          },
          child: const Text('Import'),
        ),
      ],
    );
  }
}
