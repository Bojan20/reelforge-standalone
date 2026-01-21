/// Context Editor Widget
///
/// Editor for ALE contexts with layers, constraints, and entry/exit policies.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ale_provider.dart';

/// Context list and editor widget
class ContextEditor extends StatefulWidget {
  final VoidCallback? onContextChanged;

  const ContextEditor({
    super.key,
    this.onContextChanged,
  });

  @override
  State<ContextEditor> createState() => _ContextEditorState();
}

class _ContextEditorState extends State<ContextEditor> {
  String? _selectedContextId;
  bool _isEditing = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AleProvider>(
      builder: (context, ale, child) {
        final contexts = ale.profile?.contexts ?? {};
        final activeContextId = ale.state.activeContextId;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2a2a35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(contexts.length),

              // Context list
              Expanded(
                child: contexts.isEmpty
                    ? _buildEmptyState()
                    : _buildContextList(
                        contexts,
                        activeContextId,
                        ale,
                      ),
              ),

              // Selected context details
              if (_selectedContextId != null && contexts.containsKey(_selectedContextId))
                _buildContextDetails(contexts[_selectedContextId]!, ale),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(int contextCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_special, color: Color(0xFF4a9eff), size: 18),
          const SizedBox(width: 8),
          const Text(
            'Contexts',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF2a2a35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$contextCount',
              style: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 11,
              ),
            ),
          ),
          const Spacer(),
          _ActionButton(
            icon: Icons.add,
            tooltip: 'Add Context',
            onPressed: () => _showAddContextDialog(context),
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
          const Icon(
            Icons.folder_off,
            color: Color(0xFF666666),
            size: 32,
          ),
          const SizedBox(height: 8),
          const Text(
            'No contexts defined',
            style: TextStyle(color: Color(0xFF666666), fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _showAddContextDialog(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Context'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4a9eff),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextList(
    Map<String, AleContext> contexts,
    String? activeContextId,
    AleProvider ale,
  ) {
    final sortedIds = contexts.keys.toList()
      ..sort((a, b) {
        // Active context first
        if (a == activeContextId) return -1;
        if (b == activeContextId) return 1;
        // Then alphabetically
        return a.compareTo(b);
      });

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: sortedIds.length,
      itemBuilder: (context, index) {
        final id = sortedIds[index];
        final ctx = contexts[id]!;
        final isActive = id == activeContextId;
        final isSelected = id == _selectedContextId;

        return _ContextTile(
          context: ctx,
          isActive: isActive,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedContextId = isSelected ? null : id;
            });
          },
          onDoubleTap: () {
            if (!isActive) {
              ale.enterContext(id);
              widget.onContextChanged?.call();
            }
          },
          onActivate: isActive
              ? null
              : () {
                  ale.enterContext(id);
                  widget.onContextChanged?.call();
                },
          onDeactivate: isActive
              ? () {
                  ale.exitContext();
                  widget.onContextChanged?.call();
                }
              : null,
        );
      },
    );
  }

  Widget _buildContextDetails(AleContext ctx, AleProvider ale) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        border: Border(
          top: BorderSide(color: Color(0xFF2a2a35)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Context name
          Row(
            children: [
              Expanded(
                child: Text(
                  ctx.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              _ActionButton(
                icon: _isEditing ? Icons.check : Icons.edit,
                tooltip: _isEditing ? 'Done' : 'Edit',
                onPressed: () => setState(() => _isEditing = !_isEditing),
              ),
            ],
          ),

          if (ctx.description != null) ...[
            const SizedBox(height: 4),
            Text(
              ctx.description!,
              style: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 11,
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Layers preview
          const Text(
            'Layers',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 24,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: ctx.layers.length,
              itemBuilder: (context, index) {
                final layer = ctx.layers[index];
                final isActive = index <= ctx.currentLevel;

                return Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? _getLayerColor(index).withValues(alpha: 0.2)
                        : const Color(0xFF2a2a35),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isActive
                          ? _getLayerColor(index)
                          : const Color(0xFF3a3a45),
                    ),
                  ),
                  child: Text(
                    layer.assetId.isEmpty ? 'L${index + 1}' : layer.assetId,
                    style: TextStyle(
                      color: isActive
                          ? _getLayerColor(index)
                          : const Color(0xFF666666),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  setState(() => _selectedContextId = null);
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF888888),
                ),
                child: const Text('Close'),
              ),
              const SizedBox(width: 8),
              if (ctx.id != ale.state.activeContextId)
                ElevatedButton.icon(
                  onPressed: () {
                    ale.enterContext(ctx.id);
                    widget.onContextChanged?.call();
                  },
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Enter'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4a9eff),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 32),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getLayerColor(int index) {
    const colors = [
      Color(0xFF4a9eff),
      Color(0xFF40c8ff),
      Color(0xFF40ff90),
      Color(0xFFffff40),
      Color(0xFFff9040),
      Color(0xFFff4060),
    ];
    return colors[index % colors.length];
  }

  void _showAddContextDialog(BuildContext context) {
    final idController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a20),
        title: const Text(
          'Add Context',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idController,
              decoration: const InputDecoration(
                labelText: 'Context ID',
                hintText: 'e.g., BASE, FREESPINS',
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'e.g., Base Game',
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Implement context creation via FFI
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4a9eff),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

/// Context list tile
class _ContextTile extends StatelessWidget {
  final AleContext context;
  final bool isActive;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onActivate;
  final VoidCallback? onDeactivate;

  const _ContextTile({
    required this.context,
    this.isActive = false,
    this.isSelected = false,
    this.onTap,
    this.onDoubleTap,
    this.onActivate,
    this.onDeactivate,
  });

  @override
  Widget build(BuildContext context) {
    final ctx = this.context;

    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF2a2a35)
                  : isActive
                      ? const Color(0xFF4a9eff).withValues(alpha: 0.1)
                      : const Color(0xFF121216),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF4a9eff)
                    : isSelected
                        ? const Color(0xFF3a3a45)
                        : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                // Status indicator
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? const Color(0xFF40ff90)
                        : const Color(0xFF3a3a45),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: const Color(0xFF40ff90).withValues(alpha: 0.5),
                              blurRadius: 6,
                            )
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),

                // Context info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ctx.id,
                        style: TextStyle(
                          color: isActive ? Colors.white : const Color(0xFFcccccc),
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                      if (ctx.name != ctx.id)
                        Text(
                          ctx.name,
                          style: const TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),

                // Layer count badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2a2a35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${ctx.layers.length}L',
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 10,
                    ),
                  ),
                ),

                // Action button
                if (onActivate != null || onDeactivate != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _ActionButton(
                      icon: isActive ? Icons.stop : Icons.play_arrow,
                      tooltip: isActive ? 'Exit' : 'Enter',
                      color: isActive ? const Color(0xFFff4060) : const Color(0xFF40ff90),
                      onPressed: isActive ? onDeactivate : onActivate,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small action button
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final Color? color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    this.tooltip,
    this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: const Color(0xFF2a2a35),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: color ?? const Color(0xFF888888),
            size: 14,
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}
