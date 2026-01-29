/// P2.5: Track Notes Panel — Rich text notes per track
///
/// Allows users to attach notes, comments, and session info to tracks.
/// Supports basic formatting (bold, italic, bullet lists).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Track note model
class TrackNote {
  final String trackId;
  final String trackName;
  String content;
  DateTime lastModified;
  NoteColor color;
  bool isPinned;

  TrackNote({
    required this.trackId,
    required this.trackName,
    this.content = '',
    DateTime? lastModified,
    this.color = NoteColor.none,
    this.isPinned = false,
  }) : lastModified = lastModified ?? DateTime.now();

  TrackNote copyWith({
    String? trackId,
    String? trackName,
    String? content,
    DateTime? lastModified,
    NoteColor? color,
    bool? isPinned,
  }) {
    return TrackNote(
      trackId: trackId ?? this.trackId,
      trackName: trackName ?? this.trackName,
      content: content ?? this.content,
      lastModified: lastModified ?? this.lastModified,
      color: color ?? this.color,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toJson() => {
    'trackId': trackId,
    'trackName': trackName,
    'content': content,
    'lastModified': lastModified.toIso8601String(),
    'color': color.index,
    'isPinned': isPinned,
  };

  factory TrackNote.fromJson(Map<String, dynamic> json) => TrackNote(
    trackId: json['trackId'] as String,
    trackName: json['trackName'] as String,
    content: json['content'] as String? ?? '',
    lastModified: DateTime.tryParse(json['lastModified'] as String? ?? '') ?? DateTime.now(),
    color: NoteColor.values[json['color'] as int? ?? 0],
    isPinned: json['isPinned'] as bool? ?? false,
  );
}

/// Note color options
enum NoteColor {
  none,
  red,
  orange,
  yellow,
  green,
  blue,
  purple,
  pink,
}

extension NoteColorExtension on NoteColor {
  Color get color {
    switch (this) {
      case NoteColor.none:
        return const Color(0xFF2A2A35);
      case NoteColor.red:
        return const Color(0xFFFF4060);
      case NoteColor.orange:
        return const Color(0xFFFF9040);
      case NoteColor.yellow:
        return const Color(0xFFFFD040);
      case NoteColor.green:
        return const Color(0xFF40FF90);
      case NoteColor.blue:
        return const Color(0xFF4A9EFF);
      case NoteColor.purple:
        return const Color(0xFF9060FF);
      case NoteColor.pink:
        return const Color(0xFFFF60C0);
    }
  }

  Color get backgroundColor {
    if (this == NoteColor.none) return const Color(0xFF1A1A20);
    return color.withValues(alpha: 0.15);
  }
}

/// Track Notes Panel widget
class TrackNotesPanel extends StatefulWidget {
  /// All track notes
  final List<TrackNote> notes;

  /// Currently selected track ID (if any)
  final String? selectedTrackId;

  /// Callback when note is updated
  final ValueChanged<TrackNote>? onNoteUpdated;

  /// Callback when note is deleted
  final ValueChanged<String>? onNoteDeleted;

  /// Callback when a track is selected
  final ValueChanged<String>? onTrackSelected;

  const TrackNotesPanel({
    super.key,
    required this.notes,
    this.selectedTrackId,
    this.onNoteUpdated,
    this.onNoteDeleted,
    this.onTrackSelected,
  });

  @override
  State<TrackNotesPanel> createState() => _TrackNotesPanelState();
}

class _TrackNotesPanelState extends State<TrackNotesPanel> {
  String? _editingNoteId;
  final TextEditingController _editController = TextEditingController();
  final FocusNode _editFocusNode = FocusNode();
  String _searchQuery = '';
  bool _showPinnedOnly = false;

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  List<TrackNote> get _filteredNotes {
    var filtered = widget.notes.where((note) {
      if (_showPinnedOnly && !note.isPinned) return false;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return note.trackName.toLowerCase().contains(query) ||
               note.content.toLowerCase().contains(query);
      }
      return true;
    }).toList();

    // Sort: pinned first, then by last modified
    filtered.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.lastModified.compareTo(a.lastModified);
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          Expanded(
            child: _filteredNotes.isEmpty
                ? _buildEmptyState()
                : _buildNotesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A20),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2A2A35)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.sticky_note_2, size: 14, color: Color(0xFF4A9EFF)),
          const SizedBox(width: 8),
          const Text(
            'Track Notes',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFFE0E0E8),
            ),
          ),
          const Spacer(),
          // Pinned filter toggle
          _buildIconButton(
            icon: _showPinnedOnly ? Icons.push_pin : Icons.push_pin_outlined,
            tooltip: _showPinnedOnly ? 'Show all' : 'Show pinned only',
            isActive: _showPinnedOnly,
            onTap: () => setState(() => _showPinnedOnly = !_showPinnedOnly),
          ),
          const SizedBox(width: 4),
          // Note count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${widget.notes.where((n) => n.content.isNotEmpty).length}',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF808090),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextField(
        style: const TextStyle(fontSize: 11, color: Color(0xFFE0E0E8)),
        decoration: InputDecoration(
          hintText: 'Search notes...',
          hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF606070)),
          prefixIcon: const Icon(Icons.search, size: 14, color: Color(0xFF606070)),
          filled: true,
          fillColor: const Color(0xFF1A1A20),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFF2A2A35)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFF2A2A35)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFF4A9EFF)),
          ),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _showPinnedOnly ? Icons.push_pin_outlined : Icons.note_alt_outlined,
            size: 32,
            color: const Color(0xFF404050),
          ),
          const SizedBox(height: 8),
          Text(
            _showPinnedOnly
                ? 'No pinned notes'
                : _searchQuery.isNotEmpty
                    ? 'No notes match your search'
                    : 'No track notes yet',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF606070),
            ),
          ),
          if (!_showPinnedOnly && _searchQuery.isEmpty) ...[
            const SizedBox(height: 4),
            const Text(
              'Select a track to add notes',
              style: TextStyle(
                fontSize: 10,
                color: Color(0xFF505060),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _filteredNotes.length,
      itemBuilder: (context, index) {
        final note = _filteredNotes[index];
        return _buildNoteCard(note);
      },
    );
  }

  Widget _buildNoteCard(TrackNote note) {
    final isEditing = _editingNoteId == note.trackId;
    final isSelected = widget.selectedTrackId == note.trackId;

    return GestureDetector(
      onTap: () => widget.onTrackSelected?.call(note.trackId),
      onDoubleTap: () => _startEditing(note),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: note.color.backgroundColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4A9EFF)
                : note.color == NoteColor.none
                    ? const Color(0xFF2A2A35)
                    : note.color.color.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildNoteHeader(note),
            // Content
            if (isEditing)
              _buildEditingContent(note)
            else
              _buildDisplayContent(note),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteHeader(TrackNote note) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: note.color == NoteColor.none
            ? const Color(0xFF1A1A20)
            : note.color.color.withValues(alpha: 0.2),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
      ),
      child: Row(
        children: [
          // Pin indicator
          if (note.isPinned)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.push_pin, size: 10, color: Color(0xFFFF9040)),
            ),
          // Track name
          Expanded(
            child: Text(
              note.trackName,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE0E0E8),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Last modified
          Text(
            _formatTimestamp(note.lastModified),
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF606070),
            ),
          ),
          const SizedBox(width: 8),
          // Actions
          _buildNoteActions(note),
        ],
      ),
    );
  }

  Widget _buildNoteActions(TrackNote note) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Color picker
        PopupMenuButton<NoteColor>(
          tooltip: 'Change color',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          icon: Icon(
            Icons.palette_outlined,
            size: 12,
            color: note.color == NoteColor.none
                ? const Color(0xFF606070)
                : note.color.color,
          ),
          itemBuilder: (context) => NoteColor.values.map((color) {
            return PopupMenuItem<NoteColor>(
              value: color,
              height: 32,
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color == NoteColor.none
                          ? const Color(0xFF2A2A35)
                          : color.color,
                      borderRadius: BorderRadius.circular(4),
                      border: note.color == color
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    color == NoteColor.none ? 'None' : color.name,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            );
          }).toList(),
          onSelected: (color) {
            final updated = note.copyWith(
              color: color,
              lastModified: DateTime.now(),
            );
            widget.onNoteUpdated?.call(updated);
          },
        ),
        // Pin toggle
        _buildIconButton(
          icon: note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
          tooltip: note.isPinned ? 'Unpin' : 'Pin',
          size: 12,
          isActive: note.isPinned,
          onTap: () {
            final updated = note.copyWith(
              isPinned: !note.isPinned,
              lastModified: DateTime.now(),
            );
            widget.onNoteUpdated?.call(updated);
          },
        ),
        // Delete
        _buildIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete note',
          size: 12,
          onTap: () => _confirmDelete(note),
        ),
      ],
    );
  }

  Widget _buildDisplayContent(TrackNote note) {
    if (note.content.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        child: const Text(
          'Double-click to add notes...',
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: Color(0xFF505060),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      child: Text(
        note.content,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFFB0B0B8),
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildEditingContent(TrackNote note) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Formatting toolbar
          _buildFormattingToolbar(),
          const SizedBox(height: 4),
          // Text field
          TextField(
            controller: _editController,
            focusNode: _editFocusNode,
            maxLines: null,
            minLines: 3,
            style: const TextStyle(fontSize: 11, color: Color(0xFFE0E0E8)),
            decoration: InputDecoration(
              hintText: 'Enter notes...',
              hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF505060)),
              filled: true,
              fillColor: const Color(0xFF0A0A0C),
              contentPadding: const EdgeInsets.all(8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Color(0xFF2A2A35)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Color(0xFF2A2A35)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Color(0xFF4A9EFF)),
              ),
            ),
            onSubmitted: (_) => _saveNote(note),
          ),
          const SizedBox(height: 8),
          // Save/Cancel buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancelEditing,
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 11, color: Color(0xFF808090)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _saveNote(note),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A9EFF),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormattingToolbar() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFormatButton(Icons.format_bold, 'Bold', () => _insertFormatting('**', '**')),
          _buildFormatButton(Icons.format_italic, 'Italic', () => _insertFormatting('_', '_')),
          _buildFormatButton(Icons.format_list_bulleted, 'Bullet', () => _insertFormatting('\n• ', '')),
          _buildFormatButton(Icons.check_box_outlined, 'Checkbox', () => _insertFormatting('\n[ ] ', '')),
          const VerticalDivider(width: 8, color: Color(0xFF2A2A35)),
          _buildFormatButton(Icons.access_time, 'Timestamp', _insertTimestamp),
        ],
      ),
    );
  }

  Widget _buildFormatButton(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 14),
      tooltip: tooltip,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      color: const Color(0xFF808090),
      hoverColor: const Color(0xFF4A9EFF).withValues(alpha: 0.2),
      onPressed: onTap,
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    double size = 14,
    bool isActive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: size,
            color: isActive ? const Color(0xFF4A9EFF) : const Color(0xFF606070),
          ),
        ),
      ),
    );
  }

  void _startEditing(TrackNote note) {
    setState(() {
      _editingNoteId = note.trackId;
      _editController.text = note.content;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      _editFocusNode.requestFocus();
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingNoteId = null;
      _editController.clear();
    });
  }

  void _saveNote(TrackNote note) {
    final updated = note.copyWith(
      content: _editController.text,
      lastModified: DateTime.now(),
    );
    widget.onNoteUpdated?.call(updated);
    setState(() {
      _editingNoteId = null;
      _editController.clear();
    });
  }

  void _insertFormatting(String prefix, String suffix) {
    final text = _editController.text;
    final selection = _editController.selection;
    final selectedText = selection.textInside(text);

    final newText = text.replaceRange(
      selection.start,
      selection.end,
      '$prefix$selectedText$suffix',
    );

    _editController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + prefix.length + selectedText.length + suffix.length,
      ),
    );
  }

  void _insertTimestamp() {
    final now = DateTime.now();
    final timestamp = '${now.month}/${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    _insertFormatting('[$timestamp] ', '');
  }

  void _confirmDelete(TrackNote note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A20),
        title: const Text(
          'Delete Note?',
          style: TextStyle(fontSize: 14, color: Color(0xFFE0E0E8)),
        ),
        content: Text(
          'Delete note for "${note.trackName}"?',
          style: const TextStyle(fontSize: 12, color: Color(0xFF808090)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onNoteDeleted?.call(note.trackId);
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF4060)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${dt.month}/${dt.day}';
  }
}

/// Compact track notes badge for channel strip
class TrackNoteBadge extends StatelessWidget {
  final TrackNote? note;
  final VoidCallback? onTap;

  const TrackNoteBadge({
    super.key,
    this.note,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasContent = note != null && note!.content.isNotEmpty;

    return Tooltip(
      message: hasContent ? 'View note' : 'Add note',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: hasContent
                ? (note!.color == NoteColor.none
                    ? const Color(0xFF4A9EFF).withValues(alpha: 0.2)
                    : note!.color.backgroundColor)
                : const Color(0xFF1A1A20),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: hasContent
                  ? (note!.color == NoteColor.none
                      ? const Color(0xFF4A9EFF)
                      : note!.color.color)
                  : const Color(0xFF2A2A35),
            ),
          ),
          child: Icon(
            hasContent ? Icons.sticky_note_2 : Icons.note_add_outlined,
            size: 12,
            color: hasContent
                ? (note!.color == NoteColor.none
                    ? const Color(0xFF4A9EFF)
                    : note!.color.color)
                : const Color(0xFF505060),
          ),
        ),
      ),
    );
  }
}
