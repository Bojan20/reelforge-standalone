// Keyboard Shortcuts Overlay
//
// Modal overlay showing all keyboard shortcuts organized by category.
// Triggered by pressing '?' key anywhere in the application.
//
// Features:
// - Categorized shortcut display (Transport, Edit, View, etc.)
// - Search filtering
// - Keyboard navigation
// - Platform-aware modifier keys (Cmd vs Ctrl)

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lower_zone/lower_zone_types.dart';

/// Shortcut category for organization
enum ShortcutCategory {
  transport,
  edit,
  view,
  tools,
  mixer,
  timeline,
  slotLab,
  global,
}

extension ShortcutCategoryX on ShortcutCategory {
  String get label {
    switch (this) {
      case ShortcutCategory.transport:
        return 'Transport';
      case ShortcutCategory.edit:
        return 'Edit';
      case ShortcutCategory.view:
        return 'View';
      case ShortcutCategory.tools:
        return 'Tools';
      case ShortcutCategory.mixer:
        return 'Mixer';
      case ShortcutCategory.timeline:
        return 'Timeline';
      case ShortcutCategory.slotLab:
        return 'Slot Lab';
      case ShortcutCategory.global:
        return 'Global';
    }
  }

  IconData get icon {
    switch (this) {
      case ShortcutCategory.transport:
        return Icons.play_arrow;
      case ShortcutCategory.edit:
        return Icons.edit;
      case ShortcutCategory.view:
        return Icons.visibility;
      case ShortcutCategory.tools:
        return Icons.build;
      case ShortcutCategory.mixer:
        return Icons.tune;
      case ShortcutCategory.timeline:
        return Icons.timeline;
      case ShortcutCategory.slotLab:
        return Icons.casino;
      case ShortcutCategory.global:
        return Icons.public;
    }
  }
}

/// A keyboard shortcut definition
class KeyboardShortcut {
  final String id;
  final String label;
  final String shortcut;
  final ShortcutCategory category;
  final String? description;

  const KeyboardShortcut({
    required this.id,
    required this.label,
    required this.shortcut,
    required this.category,
    this.description,
  });

  /// Get platform-appropriate shortcut string
  String get displayShortcut {
    final isMac = Platform.isMacOS;
    return shortcut
        .replaceAll('Mod+', isMac ? '⌘' : 'Ctrl+')
        .replaceAll('Alt+', isMac ? '⌥' : 'Alt+')
        .replaceAll('Shift+', isMac ? '⇧' : 'Shift+');
  }
}

/// Default shortcuts for FluxForge Studio
class FluxForgeShortcuts {
  static const List<KeyboardShortcut> all = [
    // Transport
    KeyboardShortcut(
      id: 'play_pause',
      label: 'Play / Pause',
      shortcut: 'Space',
      category: ShortcutCategory.transport,
    ),
    KeyboardShortcut(
      id: 'stop',
      label: 'Stop',
      shortcut: 'Enter',
      category: ShortcutCategory.transport,
    ),
    KeyboardShortcut(
      id: 'record',
      label: 'Record',
      shortcut: 'R',
      category: ShortcutCategory.transport,
    ),
    KeyboardShortcut(
      id: 'loop',
      label: 'Toggle Loop',
      shortcut: 'L',
      category: ShortcutCategory.transport,
    ),
    KeyboardShortcut(
      id: 'return_to_zero',
      label: 'Return to Zero',
      shortcut: '0',
      category: ShortcutCategory.transport,
    ),
    KeyboardShortcut(
      id: 'go_to_end',
      label: 'Go to End',
      shortcut: 'End',
      category: ShortcutCategory.transport,
    ),

    // Edit
    KeyboardShortcut(
      id: 'undo',
      label: 'Undo',
      shortcut: 'Mod+Z',
      category: ShortcutCategory.edit,
    ),
    KeyboardShortcut(
      id: 'redo',
      label: 'Redo',
      shortcut: 'Mod+Shift+Z',
      category: ShortcutCategory.edit,
    ),
    KeyboardShortcut(
      id: 'cut',
      label: 'Cut',
      shortcut: 'Mod+X',
      category: ShortcutCategory.edit,
    ),
    KeyboardShortcut(
      id: 'copy',
      label: 'Copy',
      shortcut: 'Mod+C',
      category: ShortcutCategory.edit,
    ),
    KeyboardShortcut(
      id: 'paste',
      label: 'Paste',
      shortcut: 'Mod+V',
      category: ShortcutCategory.edit,
    ),
    KeyboardShortcut(
      id: 'duplicate',
      label: 'Duplicate',
      shortcut: 'Mod+D',
      category: ShortcutCategory.edit,
    ),
    KeyboardShortcut(
      id: 'delete',
      label: 'Delete',
      shortcut: 'Delete',
      category: ShortcutCategory.edit,
    ),
    KeyboardShortcut(
      id: 'select_all',
      label: 'Select All',
      shortcut: 'Mod+A',
      category: ShortcutCategory.edit,
    ),
    KeyboardShortcut(
      id: 'split',
      label: 'Split at Cursor',
      shortcut: 'S',
      category: ShortcutCategory.edit,
    ),

    // View
    KeyboardShortcut(
      id: 'zoom_in',
      label: 'Zoom In',
      shortcut: 'Mod+=',
      category: ShortcutCategory.view,
    ),
    KeyboardShortcut(
      id: 'zoom_out',
      label: 'Zoom Out',
      shortcut: 'Mod+-',
      category: ShortcutCategory.view,
    ),
    KeyboardShortcut(
      id: 'zoom_fit',
      label: 'Zoom to Fit',
      shortcut: 'Mod+0',
      category: ShortcutCategory.view,
    ),
    KeyboardShortcut(
      id: 'zoom_selection',
      label: 'Zoom to Selection',
      shortcut: 'Mod+Shift+F',
      category: ShortcutCategory.view,
    ),
    KeyboardShortcut(
      id: 'toggle_lower_zone',
      label: 'Toggle Lower Zone',
      shortcut: 'Mod+L',
      category: ShortcutCategory.view,
    ),
    KeyboardShortcut(
      id: 'toggle_mixer',
      label: 'Toggle Mixer',
      shortcut: 'Mod+M',
      category: ShortcutCategory.view,
    ),

    // Tools
    KeyboardShortcut(
      id: 'select_tool',
      label: 'Select Tool',
      shortcut: 'V',
      category: ShortcutCategory.tools,
    ),
    KeyboardShortcut(
      id: 'range_tool',
      label: 'Range Tool',
      shortcut: 'R',
      category: ShortcutCategory.tools,
    ),
    KeyboardShortcut(
      id: 'trim_tool',
      label: 'Trim Tool',
      shortcut: 'T',
      category: ShortcutCategory.tools,
    ),
    KeyboardShortcut(
      id: 'fade_tool',
      label: 'Fade Tool',
      shortcut: 'F',
      category: ShortcutCategory.tools,
    ),
    KeyboardShortcut(
      id: 'pencil_tool',
      label: 'Pencil Tool',
      shortcut: 'P',
      category: ShortcutCategory.tools,
    ),
    KeyboardShortcut(
      id: 'eraser_tool',
      label: 'Eraser Tool',
      shortcut: 'E',
      category: ShortcutCategory.tools,
    ),

    // Mixer
    KeyboardShortcut(
      id: 'mute_track',
      label: 'Mute Track',
      shortcut: 'M',
      category: ShortcutCategory.mixer,
    ),
    KeyboardShortcut(
      id: 'solo_track',
      label: 'Solo Track',
      shortcut: 'S',
      category: ShortcutCategory.mixer,
    ),
    KeyboardShortcut(
      id: 'arm_track',
      label: 'Arm Track',
      shortcut: 'Mod+R',
      category: ShortcutCategory.mixer,
    ),
    KeyboardShortcut(
      id: 'reset_fader',
      label: 'Reset Fader to 0dB',
      shortcut: 'Alt+Click',
      category: ShortcutCategory.mixer,
    ),

    // Timeline
    KeyboardShortcut(
      id: 'snap_toggle',
      label: 'Toggle Snap',
      shortcut: 'N',
      category: ShortcutCategory.timeline,
    ),
    KeyboardShortcut(
      id: 'grid_toggle',
      label: 'Toggle Grid',
      shortcut: 'G',
      category: ShortcutCategory.timeline,
    ),
    KeyboardShortcut(
      id: 'cursor_left',
      label: 'Move Cursor Left',
      shortcut: '←',
      category: ShortcutCategory.timeline,
    ),
    KeyboardShortcut(
      id: 'cursor_right',
      label: 'Move Cursor Right',
      shortcut: '→',
      category: ShortcutCategory.timeline,
    ),
    KeyboardShortcut(
      id: 'next_marker',
      label: 'Next Marker',
      shortcut: 'Shift+→',
      category: ShortcutCategory.timeline,
    ),
    KeyboardShortcut(
      id: 'prev_marker',
      label: 'Previous Marker',
      shortcut: 'Shift+←',
      category: ShortcutCategory.timeline,
    ),

    // Slot Lab
    KeyboardShortcut(
      id: 'spin',
      label: 'Spin',
      shortcut: 'Space',
      category: ShortcutCategory.slotLab,
    ),
    KeyboardShortcut(
      id: 'force_lose',
      label: 'Force Lose',
      shortcut: '1',
      category: ShortcutCategory.slotLab,
    ),
    KeyboardShortcut(
      id: 'force_small_win',
      label: 'Force Small Win',
      shortcut: '2',
      category: ShortcutCategory.slotLab,
    ),
    KeyboardShortcut(
      id: 'force_big_win',
      label: 'Force Big Win',
      shortcut: '3',
      category: ShortcutCategory.slotLab,
    ),
    KeyboardShortcut(
      id: 'force_mega_win',
      label: 'Force Mega Win',
      shortcut: '4',
      category: ShortcutCategory.slotLab,
    ),
    KeyboardShortcut(
      id: 'force_free_spins',
      label: 'Force Free Spins',
      shortcut: '6',
      category: ShortcutCategory.slotLab,
    ),

    // Global
    KeyboardShortcut(
      id: 'save',
      label: 'Save Project',
      shortcut: 'Mod+S',
      category: ShortcutCategory.global,
    ),
    KeyboardShortcut(
      id: 'save_as',
      label: 'Save As...',
      shortcut: 'Mod+Shift+S',
      category: ShortcutCategory.global,
    ),
    KeyboardShortcut(
      id: 'open',
      label: 'Open Project',
      shortcut: 'Mod+O',
      category: ShortcutCategory.global,
    ),
    KeyboardShortcut(
      id: 'new_project',
      label: 'New Project',
      shortcut: 'Mod+N',
      category: ShortcutCategory.global,
    ),
    KeyboardShortcut(
      id: 'command_palette',
      label: 'Command Palette',
      shortcut: 'Mod+Shift+P',
      category: ShortcutCategory.global,
    ),
    KeyboardShortcut(
      id: 'shortcuts_overlay',
      label: 'Show Shortcuts',
      shortcut: '?',
      category: ShortcutCategory.global,
    ),
    KeyboardShortcut(
      id: 'preferences',
      label: 'Preferences',
      shortcut: 'Mod+,',
      category: ShortcutCategory.global,
    ),
  ];
}

/// Keyboard Shortcuts Overlay Widget
class KeyboardShortcutsOverlay extends StatefulWidget {
  final VoidCallback onClose;

  const KeyboardShortcutsOverlay({
    super.key,
    required this.onClose,
  });

  @override
  State<KeyboardShortcutsOverlay> createState() => _KeyboardShortcutsOverlayState();

  /// Show the shortcuts overlay
  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => KeyboardShortcutsOverlay(
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }
}

class _KeyboardShortcutsOverlayState extends State<KeyboardShortcutsOverlay> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  ShortcutCategory? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<KeyboardShortcut> get _filteredShortcuts {
    var shortcuts = FluxForgeShortcuts.all;

    // Filter by category
    if (_selectedCategory != null) {
      shortcuts = shortcuts.where((s) => s.category == _selectedCategory).toList();
    }

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      shortcuts = shortcuts.where((s) {
        return s.label.toLowerCase().contains(query) ||
            s.shortcut.toLowerCase().contains(query) ||
            (s.description?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    return shortcuts;
  }

  Map<ShortcutCategory, List<KeyboardShortcut>> get _groupedShortcuts {
    final grouped = <ShortcutCategory, List<KeyboardShortcut>>{};
    for (final shortcut in _filteredShortcuts) {
      grouped.putIfAbsent(shortcut.category, () => []).add(shortcut);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
        }
      },
      child: Center(
        child: Container(
          width: 800,
          height: 600,
          decoration: BoxDecoration(
            color: LowerZoneColors.bgDeep,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LowerZoneColors.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              _buildHeader(),
              // Search and Filter
              _buildSearchBar(),
              // Category tabs
              _buildCategoryTabs(),
              // Shortcuts list
              Expanded(child: _buildShortcutsList()),
              // Footer
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(Icons.keyboard, color: LowerZoneColors.dawAccent, size: 24),
          const SizedBox(width: 12),
          const Text(
            'Keyboard Shortcuts',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: LowerZoneColors.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, color: LowerZoneColors.textMuted),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        style: const TextStyle(color: LowerZoneColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search shortcuts...',
          hintStyle: const TextStyle(color: LowerZoneColors.textMuted),
          prefixIcon: const Icon(Icons.search, color: LowerZoneColors.textMuted),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.clear, color: LowerZoneColors.textMuted),
                  splashRadius: 16,
                )
              : null,
          filled: true,
          fillColor: LowerZoneColors.bgMid,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildCategoryChip(null, 'All'),
          ...ShortcutCategory.values.map((cat) => _buildCategoryChip(cat, cat.label)),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(ShortcutCategory? category, String label) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedCategory = category),
        backgroundColor: LowerZoneColors.bgSurface,
        selectedColor: LowerZoneColors.dawAccent.withOpacity(0.3),
        checkmarkColor: LowerZoneColors.dawAccent,
        labelStyle: TextStyle(
          color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.textSecondary,
          fontSize: 12,
        ),
        side: BorderSide(
          color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.border,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  Widget _buildShortcutsList() {
    final grouped = _groupedShortcuts;
    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: LowerZoneColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No shortcuts found',
              style: TextStyle(color: LowerZoneColors.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: grouped.entries.expand((entry) {
        return [
          // Category header
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Row(
              children: [
                Icon(entry.key.icon, size: 16, color: LowerZoneColors.dawAccent),
                const SizedBox(width: 8),
                Text(
                  entry.key.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: LowerZoneColors.dawAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Divider(color: LowerZoneColors.border, thickness: 1),
                ),
              ],
            ),
          ),
          // Shortcuts in category
          ...entry.value.map(_buildShortcutRow),
        ];
      }).toList(),
    );
  }

  Widget _buildShortcutRow(KeyboardShortcut shortcut) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shortcut.label,
              style: const TextStyle(
                color: LowerZoneColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: LowerZoneColors.border),
            ),
            child: Text(
              shortcut.displayShortcut,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: LowerZoneColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Press ',
            style: TextStyle(color: LowerZoneColors.textMuted, fontSize: 12),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: LowerZoneColors.border),
            ),
            child: const Text(
              'Esc',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: LowerZoneColors.textSecondary,
              ),
            ),
          ),
          Text(
            ' or ',
            style: TextStyle(color: LowerZoneColors.textMuted, fontSize: 12),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: LowerZoneColors.border),
            ),
            child: const Text(
              '?',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: LowerZoneColors.textSecondary,
              ),
            ),
          ),
          Text(
            ' to close',
            style: TextStyle(color: LowerZoneColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
