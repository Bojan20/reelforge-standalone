/// Session Notes Panel (P3.6) — Project-wide notes editor
///
/// Features:
/// - Basic rich text editing (bold, italic, lists)
/// - Auto-save to project file
/// - Word/character count
/// - Timestamp insertion
/// - Export to text file
///
/// Created: 2026-01-29
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../theme/fluxforge_theme.dart';

/// Session notes callback for auto-save
typedef OnNotesChanged = void Function(String notes);

/// Session Notes Panel - Simple rich text editor for project notes
class SessionNotesPanel extends StatefulWidget {
  /// Initial notes content
  final String initialNotes;

  /// Callback when notes change (for auto-save)
  final OnNotesChanged? onNotesChanged;

  /// Debounce duration for auto-save
  final Duration autoSaveDebounce;

  const SessionNotesPanel({
    super.key,
    this.initialNotes = '',
    this.onNotesChanged,
    this.autoSaveDebounce = const Duration(seconds: 2),
  });

  @override
  State<SessionNotesPanel> createState() => _SessionNotesPanelState();
}

class _SessionNotesPanelState extends State<SessionNotesPanel> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  Timer? _autoSaveTimer;

  // Formatting state
  bool _isBold = false;
  bool _isItalic = false;
  bool _hasUnsavedChanges = false;

  // Stats
  int _wordCount = 0;
  int _charCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNotes);
    _focusNode = FocusNode();
    _updateStats();

    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _hasUnsavedChanges = true;
      _updateStats();
    });

    // Debounced auto-save
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(widget.autoSaveDebounce, () {
      if (_hasUnsavedChanges) {
        widget.onNotesChanged?.call(_controller.text);
        setState(() => _hasUnsavedChanges = false);
      }
    });
  }

  void _updateStats() {
    final text = _controller.text;
    _charCount = text.length;
    _wordCount = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          // Toolbar
          _buildToolbar(),

          // Editor
          Expanded(
            child: _buildEditor(),
          ),

          // Status bar
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          // Title
          Icon(
            Icons.notes,
            size: 14,
            color: FluxForgeTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            'SESSION NOTES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(width: 16),

          // Formatting buttons
          _buildToolbarButton(
            icon: Icons.format_bold,
            tooltip: 'Bold (Ctrl+B)',
            isActive: _isBold,
            onTap: () => _insertFormatting('**', '**'),
          ),
          _buildToolbarButton(
            icon: Icons.format_italic,
            tooltip: 'Italic (Ctrl+I)',
            isActive: _isItalic,
            onTap: () => _insertFormatting('_', '_'),
          ),
          _buildToolbarButton(
            icon: Icons.format_list_bulleted,
            tooltip: 'Bullet List',
            onTap: () => _insertAtLineStart('• '),
          ),
          _buildToolbarButton(
            icon: Icons.format_list_numbered,
            tooltip: 'Numbered List',
            onTap: () => _insertNumberedList(),
          ),

          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 16,
            color: FluxForgeTheme.borderSubtle,
          ),
          const SizedBox(width: 8),

          // Insert timestamp
          _buildToolbarButton(
            icon: Icons.schedule,
            tooltip: 'Insert Timestamp',
            onTap: _insertTimestamp,
          ),

          // Insert separator
          _buildToolbarButton(
            icon: Icons.horizontal_rule,
            tooltip: 'Insert Separator',
            onTap: () => _insertText('\n---\n'),
          ),

          const Spacer(),

          // Clear button
          _buildToolbarButton(
            icon: Icons.delete_outline,
            tooltip: 'Clear Notes',
            onTap: _confirmClear,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: isActive ? FluxForgeTheme.accentBlue.withAlpha(77) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 14,
            color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (event) {
          if (event is RawKeyDownEvent) {
            if (event.isControlPressed || event.isMetaPressed) {
              if (event.logicalKey == LogicalKeyboardKey.keyB) {
                _insertFormatting('**', '**');
              } else if (event.logicalKey == LogicalKeyboardKey.keyI) {
                _insertFormatting('_', '_');
              }
            }
          }
        },
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: TextStyle(
            fontSize: 12,
            color: FluxForgeTheme.textPrimary,
            fontFamily: 'monospace',
            height: 1.5,
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.all(12),
            border: InputBorder.none,
            hintText: 'Enter session notes here...\n\n'
                '• Mix notes\n'
                '• Client feedback\n'
                '• TODO items\n'
                '• Revision history',
            hintStyle: TextStyle(
              fontSize: 12,
              color: FluxForgeTheme.textSecondary.withAlpha(100),
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          // Word count
          Text(
            '$_wordCount words',
            style: TextStyle(
              fontSize: 9,
              color: FluxForgeTheme.textSecondary,
              fontFamily: 'monospace',
            ),
          ),

          const SizedBox(width: 12),

          // Character count
          Text(
            '$_charCount chars',
            style: TextStyle(
              fontSize: 9,
              color: FluxForgeTheme.textSecondary,
              fontFamily: 'monospace',
            ),
          ),

          const Spacer(),

          // Unsaved indicator
          if (_hasUnsavedChanges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(51),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit,
                    size: 8,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 2),
                  const Text(
                    'EDITING',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentGreen.withAlpha(51),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check,
                    size: 8,
                    color: FluxForgeTheme.accentGreen,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'SAVED',
                    style: TextStyle(
                      color: FluxForgeTheme.accentGreen,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _insertFormatting(String prefix, String suffix) {
    final text = _controller.text;
    final selection = _controller.selection;

    if (selection.isCollapsed) {
      // No selection - insert markers and place cursor between them
      final newText = text.substring(0, selection.start) +
          prefix +
          suffix +
          text.substring(selection.end);
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + prefix.length),
      );
    } else {
      // Wrap selection
      final selectedText = text.substring(selection.start, selection.end);
      final newText = text.substring(0, selection.start) +
          prefix +
          selectedText +
          suffix +
          text.substring(selection.end);
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: selection.start + prefix.length,
          extentOffset: selection.end + prefix.length,
        ),
      );
    }
    _focusNode.requestFocus();
  }

  void _insertAtLineStart(String prefix) {
    final text = _controller.text;
    final selection = _controller.selection;

    // Find start of current line
    int lineStart = selection.start;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }

    final newText = text.substring(0, lineStart) + prefix + text.substring(lineStart);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + prefix.length),
    );
    _focusNode.requestFocus();
  }

  void _insertNumberedList() {
    final text = _controller.text;
    final selection = _controller.selection;

    // Count existing numbered items before cursor
    final beforeCursor = text.substring(0, selection.start);
    final lines = beforeCursor.split('\n');
    int lastNumber = 0;
    for (final line in lines.reversed) {
      final match = RegExp(r'^(\d+)\. ').firstMatch(line);
      if (match != null) {
        lastNumber = int.parse(match.group(1)!);
        break;
      }
    }

    _insertAtLineStart('${lastNumber + 1}. ');
  }

  void _insertTimestamp() {
    final now = DateTime.now();
    final timestamp = '[${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}] ';
    _insertText(timestamp);
  }

  void _insertText(String text) {
    final currentText = _controller.text;
    final selection = _controller.selection;

    final newText = currentText.substring(0, selection.start) +
        text +
        currentText.substring(selection.end);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
    _focusNode.requestFocus();
  }

  void _confirmClear() {
    if (_controller.text.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        title: Text(
          'Clear Notes',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 14,
          ),
        ),
        content: Text(
          'Are you sure you want to clear all session notes?\nThis action cannot be undone.',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: FluxForgeTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _controller.clear();
              widget.onNotesChanged?.call('');
            },
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact notes indicator for status bars
class NotesIndicator extends StatelessWidget {
  final bool hasNotes;
  final int wordCount;
  final VoidCallback? onTap;

  const NotesIndicator({
    super.key,
    required this.hasNotes,
    this.wordCount = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: hasNotes
              ? FluxForgeTheme.accentBlue.withAlpha(40)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasNotes ? Icons.notes : Icons.note_add,
              size: 12,
              color: hasNotes
                  ? FluxForgeTheme.accentBlue
                  : FluxForgeTheme.textSecondary,
            ),
            if (hasNotes && wordCount > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$wordCount',
                style: TextStyle(
                  fontSize: 9,
                  color: FluxForgeTheme.accentBlue,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
