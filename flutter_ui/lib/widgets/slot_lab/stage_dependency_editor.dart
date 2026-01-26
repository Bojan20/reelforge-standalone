/// Stage Dependency Editor — P1.14
///
/// Visual editor for defining stage dependencies (which stages must complete
/// before others can trigger). Used for complex audio sequencing like:
/// - WIN_LINE_SHOW depends on WIN_PRESENT
/// - CASCADE_STEP depends on previous CASCADE_STEP
/// - FEATURE_EXIT depends on all FEATURE_STEP stages

import 'package:flutter/material.dart';

// =============================================================================
// STAGE DEPENDENCY MODEL
// =============================================================================

/// Represents a dependency between two stages
class StageDependency {
  final String id;
  final String dependentStage;    // Stage that waits
  final String requiredStage;     // Stage that must complete first
  final int minDelayMs;           // Minimum delay after required stage
  final int maxDelayMs;           // Maximum delay (0 = no limit)
  final bool isBlocking;          // If true, blocks until required completes
  final String? description;

  const StageDependency({
    required this.id,
    required this.dependentStage,
    required this.requiredStage,
    this.minDelayMs = 0,
    this.maxDelayMs = 0,
    this.isBlocking = true,
    this.description,
  });

  StageDependency copyWith({
    String? dependentStage,
    String? requiredStage,
    int? minDelayMs,
    int? maxDelayMs,
    bool? isBlocking,
    String? description,
  }) {
    return StageDependency(
      id: id,
      dependentStage: dependentStage ?? this.dependentStage,
      requiredStage: requiredStage ?? this.requiredStage,
      minDelayMs: minDelayMs ?? this.minDelayMs,
      maxDelayMs: maxDelayMs ?? this.maxDelayMs,
      isBlocking: isBlocking ?? this.isBlocking,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'dependentStage': dependentStage,
    'requiredStage': requiredStage,
    'minDelayMs': minDelayMs,
    'maxDelayMs': maxDelayMs,
    'isBlocking': isBlocking,
    'description': description,
  };

  factory StageDependency.fromJson(Map<String, dynamic> json) {
    return StageDependency(
      id: json['id'] as String,
      dependentStage: json['dependentStage'] as String,
      requiredStage: json['requiredStage'] as String,
      minDelayMs: json['minDelayMs'] as int? ?? 0,
      maxDelayMs: json['maxDelayMs'] as int? ?? 0,
      isBlocking: json['isBlocking'] as bool? ?? true,
      description: json['description'] as String?,
    );
  }
}

// =============================================================================
// STAGE DEPENDENCY EDITOR WIDGET
// =============================================================================

class StageDependencyEditor extends StatefulWidget {
  final List<StageDependency> dependencies;
  final List<String> availableStages;
  final ValueChanged<List<StageDependency>>? onChanged;
  final Color accentColor;

  const StageDependencyEditor({
    super.key,
    required this.dependencies,
    required this.availableStages,
    this.onChanged,
    this.accentColor = const Color(0xFF4A9EFF),
  });

  @override
  State<StageDependencyEditor> createState() => _StageDependencyEditorState();
}

class _StageDependencyEditorState extends State<StageDependencyEditor> {
  late List<StageDependency> _dependencies;
  String? _selectedDependencyId;

  @override
  void initState() {
    super.initState();
    _dependencies = List.from(widget.dependencies);
  }

  @override
  void didUpdateWidget(StageDependencyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dependencies != oldWidget.dependencies) {
      _dependencies = List.from(widget.dependencies);
    }
  }

  void _addDependency() {
    final newDep = StageDependency(
      id: 'dep_${DateTime.now().millisecondsSinceEpoch}',
      dependentStage: widget.availableStages.isNotEmpty
          ? widget.availableStages.first
          : 'STAGE_A',
      requiredStage: widget.availableStages.length > 1
          ? widget.availableStages[1]
          : 'STAGE_B',
    );
    setState(() {
      _dependencies.add(newDep);
      _selectedDependencyId = newDep.id;
    });
    widget.onChanged?.call(_dependencies);
  }

  void _removeDependency(String id) {
    setState(() {
      _dependencies.removeWhere((d) => d.id == id);
      if (_selectedDependencyId == id) {
        _selectedDependencyId = _dependencies.isNotEmpty ? _dependencies.first.id : null;
      }
    });
    widget.onChanged?.call(_dependencies);
  }

  void _updateDependency(StageDependency updated) {
    setState(() {
      final index = _dependencies.indexWhere((d) => d.id == updated.id);
      if (index >= 0) {
        _dependencies[index] = updated;
      }
    });
    widget.onChanged?.call(_dependencies);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(),

          // Dependency list
          Expanded(
            child: _dependencies.isEmpty
                ? _buildEmptyState()
                : _buildDependencyList(),
          ),

          // Selected dependency editor
          if (_selectedDependencyId != null)
            _buildDependencyEditor(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_tree, size: 16, color: widget.accentColor),
          const SizedBox(width: 8),
          const Text(
            'Stage Dependencies',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '${_dependencies.length} rules',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            color: widget.accentColor,
            onPressed: _addDependency,
            tooltip: 'Add dependency',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.link_off,
            size: 32,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          Text(
            'No dependencies defined',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _addDependency,
            icon: Icon(Icons.add, size: 14, color: widget.accentColor),
            label: Text(
              'Add dependency',
              style: TextStyle(color: widget.accentColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDependencyList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _dependencies.length,
      itemBuilder: (context, index) {
        final dep = _dependencies[index];
        final isSelected = dep.id == _selectedDependencyId;

        return GestureDetector(
          onTap: () => setState(() => _selectedDependencyId = dep.id),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? widget.accentColor.withValues(alpha: 0.15)
                  : const Color(0xFF242430),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? widget.accentColor.withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                // Dependent stage
                Expanded(
                  child: Text(
                    dep.dependentStage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Arrow
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.arrow_back,
                    size: 12,
                    color: dep.isBlocking
                        ? const Color(0xFFFF6B6B)
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                ),

                // Required stage
                Expanded(
                  child: Text(
                    dep.requiredStage,
                    style: TextStyle(
                      color: widget.accentColor,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Delay indicator
                if (dep.minDelayMs > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '+${dep.minDelayMs}ms',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 9,
                      ),
                    ),
                  ),

                // Delete button
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  color: Colors.white.withValues(alpha: 0.5),
                  onPressed: () => _removeDependency(dep.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDependencyEditor() {
    final dep = _dependencies.firstWhere(
      (d) => d.id == _selectedDependencyId,
      orElse: () => _dependencies.first,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stage selectors row
          Row(
            children: [
              // Dependent stage dropdown
              Expanded(
                child: _buildStageDropdown(
                  label: 'Waits for',
                  value: dep.dependentStage,
                  onChanged: (v) => _updateDependency(dep.copyWith(dependentStage: v)),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_back, size: 16, color: Color(0xFFFF6B6B)),
              ),

              // Required stage dropdown
              Expanded(
                child: _buildStageDropdown(
                  label: 'Requires',
                  value: dep.requiredStage,
                  onChanged: (v) => _updateDependency(dep.copyWith(requiredStage: v)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Timing controls row
          Row(
            children: [
              // Min delay
              Expanded(
                child: _buildNumberField(
                  label: 'Min delay (ms)',
                  value: dep.minDelayMs,
                  onChanged: (v) => _updateDependency(dep.copyWith(minDelayMs: v)),
                ),
              ),

              const SizedBox(width: 12),

              // Max delay
              Expanded(
                child: _buildNumberField(
                  label: 'Max delay (ms)',
                  value: dep.maxDelayMs,
                  onChanged: (v) => _updateDependency(dep.copyWith(maxDelayMs: v)),
                ),
              ),

              const SizedBox(width: 12),

              // Blocking toggle
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Blocking',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Switch(
                    value: dep.isBlocking,
                    onChanged: (v) => _updateDependency(dep.copyWith(isBlocking: v)),
                    activeColor: widget.accentColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStageDropdown({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF242430),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButton<String>(
            value: widget.availableStages.contains(value) ? value : null,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: const Color(0xFF2A2A35),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
            items: widget.availableStages.map((stage) {
              return DropdownMenuItem(
                value: stage,
                child: Text(stage, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNumberField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF242430),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => onChanged(value + 10),
                    child: const Icon(Icons.arrow_drop_up, size: 14, color: Colors.white54),
                  ),
                  GestureDetector(
                    onTap: () => onChanged((value - 10).clamp(0, 10000)),
                    child: const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white54),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// PRESET DEPENDENCIES
// =============================================================================

/// Common stage dependency presets
class StageDependencyPresets {
  static List<StageDependency> get winPresentation => [
    const StageDependency(
      id: 'preset_win_line',
      dependentStage: 'WIN_LINE_SHOW',
      requiredStage: 'WIN_PRESENT',
      minDelayMs: 100,
      description: 'Win lines show after win presentation',
    ),
    const StageDependency(
      id: 'preset_rollup',
      dependentStage: 'ROLLUP_START',
      requiredStage: 'WIN_LINE_SHOW',
      minDelayMs: 500,
      description: 'Rollup starts after win lines',
    ),
  ];

  static List<StageDependency> get cascade => [
    const StageDependency(
      id: 'preset_cascade_step',
      dependentStage: 'CASCADE_STEP',
      requiredStage: 'CASCADE_START',
      minDelayMs: 0,
      description: 'Cascade steps require cascade start',
    ),
    const StageDependency(
      id: 'preset_cascade_end',
      dependentStage: 'CASCADE_END',
      requiredStage: 'CASCADE_STEP',
      minDelayMs: 300,
      description: 'Cascade end after last step',
    ),
  ];

  static List<StageDependency> get freeSpins => [
    const StageDependency(
      id: 'preset_fs_spin',
      dependentStage: 'FREESPIN_SPIN_START',
      requiredStage: 'FREESPIN_TRIGGER',
      minDelayMs: 1000,
      description: 'First free spin after trigger animation',
    ),
    const StageDependency(
      id: 'preset_fs_end',
      dependentStage: 'FREESPIN_END',
      requiredStage: 'FREESPIN_SPIN_END',
      minDelayMs: 500,
      description: 'Free spins end after last spin',
    ),
  ];
}
