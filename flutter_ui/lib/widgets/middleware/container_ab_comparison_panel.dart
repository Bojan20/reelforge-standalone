/// FluxForge Studio Container A/B Comparison Panel
///
/// P4.2: Container A/B comparison
/// - Side-by-side comparison of two container configurations
/// - Quick toggle between A and B
/// - Copy settings between slots
/// - Visual diff highlighting
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// A/B SLOT MODEL
// ═══════════════════════════════════════════════════════════════════════════════

enum ABSlot { a, b }

class ContainerSnapshot {
  final String type; // blend, random, sequence
  final Map<String, dynamic> data;
  final DateTime timestamp;

  const ContainerSnapshot({
    required this.type,
    required this.data,
    required this.timestamp,
  });

  ContainerSnapshot copyWith({
    String? type,
    Map<String, dynamic>? data,
    DateTime? timestamp,
  }) {
    return ContainerSnapshot(
      type: type ?? this.type,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class ContainerABComparisonPanel extends StatefulWidget {
  final int containerId;
  final String containerType; // blend, random, sequence
  final VoidCallback? onClose;

  const ContainerABComparisonPanel({
    super.key,
    required this.containerId,
    required this.containerType,
    this.onClose,
  });

  @override
  State<ContainerABComparisonPanel> createState() => _ContainerABComparisonPanelState();
}

class _ContainerABComparisonPanelState extends State<ContainerABComparisonPanel>
    with SingleTickerProviderStateMixin {
  ABSlot _activeSlot = ABSlot.a;
  ContainerSnapshot? _slotA;
  ContainerSnapshot? _slotB;
  late AnimationController _toggleController;
  late Animation<double> _toggleAnimation;
  bool _showDiff = false;

  @override
  void initState() {
    super.initState();
    _toggleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _toggleAnimation = CurvedAnimation(
      parent: _toggleController,
      curve: Curves.easeInOut,
    );

    // Capture initial state as slot A
    _captureCurrentState(ABSlot.a);
  }

  @override
  void dispose() {
    _toggleController.dispose();
    super.dispose();
  }

  void _captureCurrentState(ABSlot slot) {
    final provider = context.read<MiddlewareProvider>();
    Map<String, dynamic>? data;

    switch (widget.containerType) {
      case 'blend':
        final container = provider.blendContainers.where((c) => c.id == widget.containerId).firstOrNull;
        if (container != null) {
          data = _blendToData(container);
        }
        break;
      case 'random':
        final container = provider.randomContainers.where((c) => c.id == widget.containerId).firstOrNull;
        if (container != null) {
          data = _randomToData(container);
        }
        break;
      case 'sequence':
        final container = provider.sequenceContainers.where((c) => c.id == widget.containerId).firstOrNull;
        if (container != null) {
          data = _sequenceToData(container);
        }
        break;
    }

    if (data != null) {
      final snapshot = ContainerSnapshot(
        type: widget.containerType,
        data: data,
        timestamp: DateTime.now(),
      );

      setState(() {
        if (slot == ABSlot.a) {
          _slotA = snapshot;
        } else {
          _slotB = snapshot;
        }
      });
    }
  }

  void _applySnapshot(ContainerSnapshot snapshot) {
    final provider = context.read<MiddlewareProvider>();

    switch (snapshot.type) {
      case 'blend':
        final container = _dataToBlend(snapshot.data, widget.containerId);
        provider.updateBlendContainer(container);
        break;
      case 'random':
        final container = _dataToRandom(snapshot.data, widget.containerId);
        provider.updateRandomContainer(container);
        break;
      case 'sequence':
        final container = _dataToSequence(snapshot.data, widget.containerId);
        provider.updateSequenceContainer(container);
        break;
    }
  }

  void _toggleSlot() {
    final targetSlot = _activeSlot == ABSlot.a ? ABSlot.b : ABSlot.a;
    final targetSnapshot = targetSlot == ABSlot.a ? _slotA : _slotB;

    if (targetSnapshot != null) {
      _applySnapshot(targetSnapshot);
      setState(() => _activeSlot = targetSlot);

      if (targetSlot == ABSlot.b) {
        _toggleController.forward();
      } else {
        _toggleController.reverse();
      }
    }
  }

  void _copyAToB() {
    if (_slotA != null) {
      setState(() {
        _slotB = _slotA!.copyWith(timestamp: DateTime.now());
      });
    }
  }

  void _copyBToA() {
    if (_slotB != null) {
      setState(() {
        _slotA = _slotB!.copyWith(timestamp: DateTime.now());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildToggleBar(),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Slot A
                Expanded(child: _buildSlotPanel(ABSlot.a)),
                const SizedBox(width: 16),
                // Slot B
                Expanded(child: _buildSlotPanel(ABSlot.b)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.compare, color: Colors.cyan, size: 20),
        const SizedBox(width: 8),
        Text(
          'A/B Comparison',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getTypeColor(widget.containerType).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${widget.containerType.toUpperCase()} #${widget.containerId}',
            style: TextStyle(
              color: _getTypeColor(widget.containerType),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Spacer(),
        // Diff toggle
        GestureDetector(
          onTap: () => setState(() => _showDiff = !_showDiff),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _showDiff
                  ? Colors.yellow.withValues(alpha: 0.2)
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _showDiff ? Colors.yellow : FluxForgeTheme.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.difference,
                  size: 14,
                  color: _showDiff ? Colors.yellow : FluxForgeTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Show Diff',
                  style: TextStyle(
                    color: _showDiff ? Colors.yellow : FluxForgeTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.onClose != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: FluxForgeTheme.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(Icons.close, size: 14, color: FluxForgeTheme.textSecondary),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildToggleBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildSlotButton(ABSlot.a),
          const SizedBox(width: 12),
          // Toggle button
          GestureDetector(
            onTap: (_slotA != null && _slotB != null) ? _toggleSlot : null,
            child: AnimatedBuilder(
              animation: _toggleAnimation,
              builder: (context, child) {
                return Container(
                  width: 80,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.withValues(alpha: 1 - _toggleAnimation.value),
                        Colors.green.withValues(alpha: _toggleAnimation.value),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (_activeSlot == ABSlot.a ? Colors.blue : Colors.green)
                            .withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 200),
                        left: _activeSlot == ABSlot.a ? 4 : 44,
                        top: 4,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              _activeSlot == ABSlot.a ? 'A' : 'B',
                              style: TextStyle(
                                color: _activeSlot == ABSlot.a ? Colors.blue : Colors.green,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          _buildSlotButton(ABSlot.b),
        ],
      ),
    );
  }

  Widget _buildSlotButton(ABSlot slot) {
    final isActive = _activeSlot == slot;
    final snapshot = slot == ABSlot.a ? _slotA : _slotB;
    final color = slot == ABSlot.a ? Colors.blue : Colors.green;
    final label = slot == ABSlot.a ? 'A' : 'B';

    return GestureDetector(
      onTap: () {
        if (snapshot != null && !isActive) {
          _applySnapshot(snapshot);
          setState(() => _activeSlot = slot);
          if (slot == ABSlot.b) {
            _toggleController.forward();
          } else {
            _toggleController.reverse();
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? color : FluxForgeTheme.border,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: snapshot != null ? color : FluxForgeTheme.surface,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: snapshot != null ? Colors.white : FluxForgeTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Slot $label',
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  snapshot != null ? _formatTime(snapshot.timestamp) : 'Empty',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotPanel(ABSlot slot) {
    final snapshot = slot == ABSlot.a ? _slotA : _slotB;
    final otherSnapshot = slot == ABSlot.a ? _slotB : _slotA;
    final color = slot == ABSlot.a ? Colors.blue : Colors.green;
    final label = slot == ABSlot.a ? 'A' : 'B';
    final isActive = _activeSlot == slot;

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? color : FluxForgeTheme.border,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Slot $label',
                        style: TextStyle(
                          color: FluxForgeTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (snapshot != null)
                        Text(
                          'Captured: ${_formatTime(snapshot.timestamp)}',
                          style: TextStyle(
                            color: FluxForgeTheme.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _captureCurrentState(slot),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt, size: 12, color: color),
                        const SizedBox(width: 4),
                        Text(
                          'Capture',
                          style: TextStyle(color: color, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: snapshot == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.camera_alt_outlined,
                          size: 32,
                          color: FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Click "Capture" to save\ncurrent settings',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: FluxForgeTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: _buildSnapshotPreview(snapshot, otherSnapshot, color),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotPreview(
    ContainerSnapshot snapshot,
    ContainerSnapshot? otherSnapshot,
    Color color,
  ) {
    switch (snapshot.type) {
      case 'blend':
        return _buildBlendPreview(snapshot.data, otherSnapshot?.data, color);
      case 'random':
        return _buildRandomPreview(snapshot.data, otherSnapshot?.data, color);
      case 'sequence':
        return _buildSequencePreview(snapshot.data, otherSnapshot?.data, color);
      default:
        return Text('Unknown type', style: TextStyle(color: FluxForgeTheme.textSecondary));
    }
  }

  Widget _buildBlendPreview(Map<String, dynamic> data, Map<String, dynamic>? otherData, Color color) {
    final children = data['children'] as List<dynamic>? ?? [];
    final otherChildren = otherData?['children'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPreviewRow('RTPC ID', '${data['rtpcId'] ?? 0}',
            isDiff: _showDiff && otherData != null && data['rtpcId'] != otherData['rtpcId']),
        _buildPreviewRow('Curve', CrossfadeCurve.values[(data['crossfadeCurve'] as int?) ?? 0].displayName,
            isDiff: _showDiff && otherData != null && data['crossfadeCurve'] != otherData['crossfadeCurve']),
        const SizedBox(height: 12),
        Text(
          'Children (${children.length})',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...children.asMap().entries.map((e) {
          final child = e.value as Map<String, dynamic>;
          final otherChild = e.key < otherChildren.length ? otherChildren[e.key] as Map<String, dynamic> : null;
          final isDiff = _showDiff && otherChild != null && !_mapsEqual(child, otherChild);

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDiff ? Colors.yellow.withValues(alpha: 0.1) : color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isDiff ? Colors.yellow : color.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                if (isDiff)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.change_history, size: 12, color: Colors.yellow),
                  ),
                Expanded(
                  child: Text(
                    child['name'] as String? ?? 'Child',
                    style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 10),
                  ),
                ),
                Text(
                  '${((child['rtpcStart'] as num?)?.toStringAsFixed(2) ?? '0')} - ${((child['rtpcEnd'] as num?)?.toStringAsFixed(2) ?? '1')}',
                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRandomPreview(Map<String, dynamic> data, Map<String, dynamic>? otherData, Color color) {
    final children = data['children'] as List<dynamic>? ?? [];
    final modes = ['Random', 'Shuffle', 'Round Robin'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPreviewRow('Mode', modes[(data['mode'] as int?) ?? 0],
            isDiff: _showDiff && otherData != null && data['mode'] != otherData['mode']),
        _buildPreviewRow(
          'Pitch Range',
          '${((data['globalPitchMin'] as num?)?.toStringAsFixed(2) ?? '0')} to ${((data['globalPitchMax'] as num?)?.toStringAsFixed(2) ?? '0')}',
          isDiff: _showDiff && otherData != null &&
              (data['globalPitchMin'] != otherData['globalPitchMin'] ||
               data['globalPitchMax'] != otherData['globalPitchMax']),
        ),
        const SizedBox(height: 12),
        Text(
          'Children (${children.length})',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...children.map((c) {
          final child = c as Map<String, dynamic>;
          final weight = (child['weight'] as num?)?.toDouble() ?? 1.0;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    child['name'] as String? ?? 'Child',
                    style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 10),
                  ),
                ),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.backgroundDeep,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (weight / 3.0).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${weight.toStringAsFixed(1)}',
                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSequencePreview(Map<String, dynamic> data, Map<String, dynamic>? otherData, Color color) {
    final steps = data['steps'] as List<dynamic>? ?? [];
    final behaviors = ['Stop', 'Loop', 'Ping-Pong', 'Hold'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPreviewRow('End Behavior', behaviors[(data['endBehavior'] as int?) ?? 0],
            isDiff: _showDiff && otherData != null && data['endBehavior'] != otherData['endBehavior']),
        _buildPreviewRow('Speed', '${((data['speed'] as num?)?.toStringAsFixed(1) ?? '1.0')}x',
            isDiff: _showDiff && otherData != null && data['speed'] != otherData['speed']),
        const SizedBox(height: 12),
        Text(
          'Steps (${steps.length})',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...steps.asMap().entries.map((entry) {
          final step = entry.value as Map<String, dynamic>;
          final delay = (step['delayMs'] as num?)?.toInt() ?? 0;
          final duration = (step['durationMs'] as num?)?.toInt() ?? 100;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${entry.key + 1}',
                      style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    step['childName'] as String? ?? 'Step',
                    style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 10),
                  ),
                ),
                Text(
                  '@${delay}ms (${duration}ms)',
                  style: TextStyle(color: color, fontSize: 8),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPreviewRow(String label, String value, {bool isDiff = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: isDiff ? const EdgeInsets.all(4) : EdgeInsets.zero,
      decoration: isDiff
          ? BoxDecoration(
              color: Colors.yellow.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.yellow.withValues(alpha: 0.5)),
            )
          : null,
      child: Row(
        children: [
          if (isDiff)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.change_history, size: 12, color: Colors.yellow),
            ),
          SizedBox(
            width: isDiff ? 70 : 80,
            child: Text(
              label,
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isDiff ? Colors.yellow : FluxForgeTheme.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Row(
      children: [
        // Copy A → B
        GestureDetector(
          onTap: _slotA != null ? _copyAToB : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _slotA != null
                  ? Colors.blue.withValues(alpha: 0.2)
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _slotA != null ? Colors.blue : FluxForgeTheme.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'A',
                  style: TextStyle(
                    color: _slotA != null ? Colors.blue : FluxForgeTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: _slotA != null ? Colors.blue : FluxForgeTheme.textSecondary,
                ),
                Text(
                  'B',
                  style: TextStyle(
                    color: _slotA != null ? Colors.green : FluxForgeTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Copy B → A
        GestureDetector(
          onTap: _slotB != null ? _copyBToA : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _slotB != null
                  ? Colors.green.withValues(alpha: 0.2)
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _slotB != null ? Colors.green : FluxForgeTheme.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'B',
                  style: TextStyle(
                    color: _slotB != null ? Colors.green : FluxForgeTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: _slotB != null ? Colors.green : FluxForgeTheme.textSecondary,
                ),
                Text(
                  'A',
                  style: TextStyle(
                    color: _slotB != null ? Colors.blue : FluxForgeTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        // Active indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (_activeSlot == ABSlot.a ? Colors.blue : Colors.green).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                size: 16,
                color: _activeSlot == ABSlot.a ? Colors.blue : Colors.green,
              ),
              const SizedBox(width: 6),
              Text(
                'Active: ${_activeSlot == ABSlot.a ? 'A' : 'B'}',
                style: TextStyle(
                  color: _activeSlot == ABSlot.a ? Colors.blue : Colors.green,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _blendToData(BlendContainer container) {
    return {
      'name': container.name,
      'rtpcId': container.rtpcId,
      'crossfadeCurve': container.crossfadeCurve.index,
      'enabled': container.enabled,
      'children': container.children.map((c) => {
        'name': c.name,
        'rtpcStart': c.rtpcStart,
        'rtpcEnd': c.rtpcEnd,
        'crossfadeWidth': c.crossfadeWidth,
        'audioPath': c.audioPath,
      }).toList(),
    };
  }

  BlendContainer _dataToBlend(Map<String, dynamic> data, int id) {
    final children = (data['children'] as List<dynamic>?)?.asMap().entries.map((e) {
      final childData = e.value as Map<String, dynamic>;
      return BlendChild(
        id: e.key + 1,
        name: childData['name'] as String? ?? 'Child ${e.key + 1}',
        rtpcStart: (childData['rtpcStart'] as num?)?.toDouble() ?? 0.0,
        rtpcEnd: (childData['rtpcEnd'] as num?)?.toDouble() ?? 1.0,
        crossfadeWidth: (childData['crossfadeWidth'] as num?)?.toDouble() ?? 0.1,
        audioPath: childData['audioPath'] as String?,
      );
    }).toList() ?? [];

    return BlendContainer(
      id: id,
      name: data['name'] as String? ?? 'Blend',
      rtpcId: data['rtpcId'] as int? ?? 0,
      crossfadeCurve: CrossfadeCurve.values[(data['crossfadeCurve'] as int?) ?? 0],
      enabled: data['enabled'] as bool? ?? true,
      children: children,
    );
  }

  Map<String, dynamic> _randomToData(RandomContainer container) {
    return {
      'name': container.name,
      'mode': container.mode.index,
      'enabled': container.enabled,
      'globalPitchMin': container.globalPitchMin,
      'globalPitchMax': container.globalPitchMax,
      'globalVolumeMin': container.globalVolumeMin,
      'globalVolumeMax': container.globalVolumeMax,
      'children': container.children.map((c) => {
        'name': c.name,
        'weight': c.weight,
        'pitchMin': c.pitchMin,
        'pitchMax': c.pitchMax,
        'volumeMin': c.volumeMin,
        'volumeMax': c.volumeMax,
        'audioPath': c.audioPath,
      }).toList(),
    };
  }

  RandomContainer _dataToRandom(Map<String, dynamic> data, int id) {
    final children = (data['children'] as List<dynamic>?)?.asMap().entries.map((e) {
      final childData = e.value as Map<String, dynamic>;
      return RandomChild(
        id: e.key + 1,
        name: childData['name'] as String? ?? 'Child ${e.key + 1}',
        weight: (childData['weight'] as num?)?.toDouble() ?? 1.0,
        pitchMin: (childData['pitchMin'] as num?)?.toDouble() ?? 0.0,
        pitchMax: (childData['pitchMax'] as num?)?.toDouble() ?? 0.0,
        volumeMin: (childData['volumeMin'] as num?)?.toDouble() ?? 1.0,
        volumeMax: (childData['volumeMax'] as num?)?.toDouble() ?? 1.0,
        audioPath: childData['audioPath'] as String?,
      );
    }).toList() ?? [];

    return RandomContainer(
      id: id,
      name: data['name'] as String? ?? 'Random',
      mode: RandomMode.values[(data['mode'] as int?) ?? 0],
      enabled: data['enabled'] as bool? ?? true,
      globalPitchMin: (data['globalPitchMin'] as num?)?.toDouble() ?? 0.0,
      globalPitchMax: (data['globalPitchMax'] as num?)?.toDouble() ?? 0.0,
      globalVolumeMin: (data['globalVolumeMin'] as num?)?.toDouble() ?? 1.0,
      globalVolumeMax: (data['globalVolumeMax'] as num?)?.toDouble() ?? 1.0,
      children: children,
    );
  }

  Map<String, dynamic> _sequenceToData(SequenceContainer container) {
    return {
      'name': container.name,
      'endBehavior': container.endBehavior.index,
      'speed': container.speed,
      'enabled': container.enabled,
      'steps': container.steps.map((s) => {
        'index': s.index,
        'childId': s.childId,
        'childName': s.childName,
        'audioPath': s.audioPath,
        'delayMs': s.delayMs,
        'durationMs': s.durationMs,
        'fadeInMs': s.fadeInMs,
        'fadeOutMs': s.fadeOutMs,
        'loopCount': s.loopCount,
        'volume': s.volume,
      }).toList(),
    };
  }

  SequenceContainer _dataToSequence(Map<String, dynamic> data, int id) {
    final steps = (data['steps'] as List<dynamic>?)?.asMap().entries.map((e) {
      final stepData = e.value as Map<String, dynamic>;
      return SequenceStep(
        index: stepData['index'] as int? ?? e.key,
        childId: stepData['childId'] as int? ?? e.key + 1,
        childName: stepData['childName'] as String? ?? 'Step ${e.key + 1}',
        audioPath: stepData['audioPath'] as String?,
        delayMs: (stepData['delayMs'] as num?)?.toDouble() ?? 0.0,
        durationMs: (stepData['durationMs'] as num?)?.toDouble() ?? 100.0,
        fadeInMs: (stepData['fadeInMs'] as num?)?.toDouble() ?? 0.0,
        fadeOutMs: (stepData['fadeOutMs'] as num?)?.toDouble() ?? 0.0,
        loopCount: stepData['loopCount'] as int? ?? 1,
        volume: (stepData['volume'] as num?)?.toDouble() ?? 1.0,
      );
    }).toList() ?? [];

    return SequenceContainer(
      id: id,
      name: data['name'] as String? ?? 'Sequence',
      endBehavior: SequenceEndBehavior.values[(data['endBehavior'] as int?) ?? 0],
      speed: (data['speed'] as num?)?.toDouble() ?? 1.0,
      enabled: data['enabled'] as bool? ?? true,
      steps: steps,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════════

  Color _getTypeColor(String type) {
    switch (type) {
      case 'blend':
        return Colors.purple;
      case 'random':
        return Colors.orange;
      case 'sequence':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DIALOG WRAPPER
// ═══════════════════════════════════════════════════════════════════════════════

class ContainerABComparisonDialog extends StatelessWidget {
  final int containerId;
  final String containerType;

  const ContainerABComparisonDialog({
    super.key,
    required this.containerId,
    required this.containerType,
  });

  static Future<void> show(
    BuildContext context, {
    required int containerId,
    required String containerType,
  }) {
    return showDialog(
      context: context,
      builder: (context) => ContainerABComparisonDialog(
        containerId: containerId,
        containerType: containerType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 900,
        height: 600,
        decoration: BoxDecoration(
          color: FluxForgeTheme.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FluxForgeTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ContainerABComparisonPanel(
          containerId: containerId,
          containerType: containerType,
          onClose: () => Navigator.pop(context),
        ),
      ),
    );
  }
}
