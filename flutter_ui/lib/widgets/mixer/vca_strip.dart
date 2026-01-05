// VCA Fader Strip Widget
// Professional VCA fader control like Cubase/Pro Tools

import 'dart:ffi' as ffi;
import 'package:flutter/material.dart';

// VCA data model
class VcaData {
  final int id;
  String name;
  double levelDb;
  bool muted;
  bool soloed;
  Color color;
  List<int> memberTrackIds;

  VcaData({
    required this.id,
    required this.name,
    this.levelDb = 0.0,
    this.muted = false,
    this.soloed = false,
    this.color = const Color(0xFFff9040),
    this.memberTrackIds = const [],
  });
}

/// VCA Fader Strip - Orange theme to distinguish from regular channel strips
class VcaFaderStrip extends StatefulWidget {
  final VcaData vca;
  final VoidCallback? onLevelChanged;
  final VoidCallback? onMuteChanged;
  final VoidCallback? onSoloChanged;
  final VoidCallback? onEditMembers;
  final VoidCallback? onDelete;

  const VcaFaderStrip({
    super.key,
    required this.vca,
    this.onLevelChanged,
    this.onMuteChanged,
    this.onSoloChanged,
    this.onEditMembers,
    this.onDelete,
  });

  @override
  State<VcaFaderStrip> createState() => _VcaFaderStripState();
}

class _VcaFaderStripState extends State<VcaFaderStrip> {
  late double _levelDb;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _levelDb = widget.vca.levelDb;
  }

  @override
  void didUpdateWidget(VcaFaderStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging) {
      _levelDb = widget.vca.levelDb;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        border: Border.all(
          color: widget.vca.color.withValues(alpha: 0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(color: Color(0xFF3a3a40), height: 1),
          Expanded(child: _buildFader()),
          const Divider(color: Color(0xFF3a3a40), height: 1),
          _buildButtons(),
          const Divider(color: Color(0xFF3a3a40), height: 1),
          _buildMemberCount(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            widget.vca.color.withValues(alpha: 0.3),
            widget.vca.color.withValues(alpha: 0.1),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: widget.vca.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              widget.vca.name,
              style: const TextStyle(
                color: Color(0xFFe0e0e0),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _buildVcaLabel(),
        ],
      ),
    );
  }

  Widget _buildVcaLabel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: widget.vca.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: widget.vca.color.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Text(
        'VCA',
        style: TextStyle(
          color: widget.vca.color,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildFader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          // dB scale
          _buildDbScale(),
          const SizedBox(width: 4),
          // Fader
          Expanded(child: _buildFaderTrack()),
          const SizedBox(width: 4),
          // Value display
          _buildValueDisplay(),
        ],
      ),
    );
  }

  Widget _buildDbScale() {
    return SizedBox(
      width: 16,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _dbLabel('+12'),
          _dbLabel('+6'),
          _dbLabel('0'),
          _dbLabel('-6'),
          _dbLabel('-12'),
          _dbLabel('-24'),
          _dbLabel('-∞'),
        ],
      ),
    );
  }

  Widget _dbLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF6a6a70),
        fontSize: 8,
      ),
    );
  }

  Widget _buildFaderTrack() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final normalized = _dbToNormalized(_levelDb);
        final capPosition = height * (1 - normalized);

        return GestureDetector(
          onVerticalDragStart: (_) => setState(() => _isDragging = true),
          onVerticalDragUpdate: (details) {
            final newNormalized = 1 - (details.localPosition.dy / height);
            setState(() {
              _levelDb = _normalizedToDb(newNormalized.clamp(0.0, 1.0));
            });
            widget.onLevelChanged?.call();
          },
          onVerticalDragEnd: (_) => setState(() => _isDragging = false),
          onDoubleTap: () {
            setState(() => _levelDb = 0.0);
            widget.onLevelChanged?.call();
          },
          child: Container(
            width: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF0a0a0c),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: const Color(0xFF3a3a40),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                // Filled portion
                Positioned(
                  left: 2,
                  right: 2,
                  bottom: 2,
                  height: (height - 4) * normalized,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          widget.vca.color.withValues(alpha: 0.6),
                          widget.vca.color.withValues(alpha: 0.3),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Fader cap
                Positioned(
                  left: 0,
                  right: 0,
                  top: capPosition - 8,
                  child: Container(
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          widget.vca.color,
                          widget.vca.color.withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: widget.vca.color.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 12,
                        height: 2,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
                // 0dB line
                Positioned(
                  left: 0,
                  right: 0,
                  top: height * (1 - _dbToNormalized(0)),
                  child: Container(
                    height: 1,
                    color: const Color(0xFF4a9eff).withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildValueDisplay() {
    return SizedBox(
      width: 24,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _levelDb <= -60 ? '-∞' : '${_levelDb.toStringAsFixed(1)}',
            style: TextStyle(
              color: widget.vca.color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Text(
            'dB',
            style: TextStyle(
              color: Color(0xFF6a6a70),
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _buildButton(
              label: 'M',
              active: widget.vca.muted,
              activeColor: const Color(0xFFff4040),
              onTap: () => widget.onMuteChanged?.call(),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildButton(
              label: 'S',
              active: widget.vca.soloed,
              activeColor: const Color(0xFFffff40),
              onTap: () => widget.onSoloChanged?.call(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: active ? activeColor : const Color(0xFF2a2a30),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? activeColor : const Color(0xFF3a3a40),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.black : const Color(0xFF8a8a90),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemberCount() {
    return GestureDetector(
      onTap: widget.onEditMembers,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 14,
              color: widget.vca.color.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text(
              '${widget.vca.memberTrackIds.length}',
              style: TextStyle(
                color: widget.vca.color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _dbToNormalized(double db) {
    // Map -60dB to 0, +12dB to 1
    if (db <= -60) return 0;
    if (db >= 12) return 1;
    return (db + 60) / 72;
  }

  double _normalizedToDb(double normalized) {
    // Map 0 to -60dB, 1 to +12dB
    return normalized * 72 - 60;
  }
}

/// VCA Member Editor Dialog
class VcaMemberEditor extends StatefulWidget {
  final VcaData vca;
  final List<int> availableTrackIds;
  final String Function(int trackId) getTrackName;
  final void Function(List<int> memberIds) onMembersChanged;

  const VcaMemberEditor({
    super.key,
    required this.vca,
    required this.availableTrackIds,
    required this.getTrackName,
    required this.onMembersChanged,
  });

  @override
  State<VcaMemberEditor> createState() => _VcaMemberEditorState();
}

class _VcaMemberEditorState extends State<VcaMemberEditor> {
  late Set<int> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.vca.memberTrackIds);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF3a3a40),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          const Text(
            'Select tracks to control:',
            style: TextStyle(
              color: Color(0xFF8a8a90),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          _buildTrackList(),
          const SizedBox(height: 16),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.vca.color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Edit ${widget.vca.name}',
          style: const TextStyle(
            color: Color(0xFFe0e0e0),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildTrackList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: widget.availableTrackIds.length,
        itemBuilder: (context, index) {
          final trackId = widget.availableTrackIds[index];
          final isSelected = _selectedIds.contains(trackId);

          return CheckboxListTile(
            title: Text(
              widget.getTrackName(trackId),
              style: const TextStyle(
                color: Color(0xFFe0e0e0),
                fontSize: 12,
              ),
            ),
            value: isSelected,
            activeColor: widget.vca.color,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedIds.add(trackId);
                } else {
                  _selectedIds.remove(trackId);
                }
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            contentPadding: EdgeInsets.zero,
          );
        },
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Color(0xFF8a8a90)),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            widget.onMembersChanged(_selectedIds.toList());
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.vca.color,
          ),
          child: const Text(
            'Apply',
            style: TextStyle(color: Colors.black),
          ),
        ),
      ],
    );
  }
}

/// VCA Create Dialog
class VcaCreateDialog extends StatefulWidget {
  final void Function(String name, Color color) onCreate;

  const VcaCreateDialog({
    super.key,
    required this.onCreate,
  });

  @override
  State<VcaCreateDialog> createState() => _VcaCreateDialogState();
}

class _VcaCreateDialogState extends State<VcaCreateDialog> {
  final _nameController = TextEditingController(text: 'VCA 1');
  Color _selectedColor = const Color(0xFFff9040);

  static const _colorOptions = [
    Color(0xFFff9040), // Orange
    Color(0xFF4a9eff), // Blue
    Color(0xFF40ff90), // Green
    Color(0xFFff4060), // Red
    Color(0xFFff40ff), // Magenta
    Color(0xFFffff40), // Yellow
    Color(0xFF40c8ff), // Cyan
    Color(0xFFa040ff), // Purple
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a20),
      title: const Text(
        'Create VCA Fader',
        style: TextStyle(color: Color(0xFFe0e0e0)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Color(0xFFe0e0e0)),
            decoration: const InputDecoration(
              labelText: 'Name',
              labelStyle: TextStyle(color: Color(0xFF8a8a90)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF3a3a40)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF4a9eff)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Color:',
            style: TextStyle(color: Color(0xFF8a8a90)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _colorOptions.map((color) {
              final isSelected = color == _selectedColor;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = color),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onCreate(_nameController.text, _selectedColor);
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedColor,
          ),
          child: const Text(
            'Create',
            style: TextStyle(color: Colors.black),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
