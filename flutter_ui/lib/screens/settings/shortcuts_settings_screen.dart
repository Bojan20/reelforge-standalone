/// Keyboard Shortcuts Settings Screen
///
/// Allows users to view and customize keyboard shortcuts:
/// - View all shortcuts grouped by category
/// - Click to edit a shortcut
/// - Capture new key combination
/// - Reset to defaults

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../theme/reelforge_theme.dart';
import '../../providers/global_shortcuts_provider.dart';

/// Shortcut category for grouping
enum ShortcutCategory {
  transport('Transport'),
  file('File'),
  edit('Edit'),
  timeline('Timeline'),
  zoom('Zoom'),
  loop('Loop'),
  navigation('Navigation'),
  toggle('Toggle Panels'),
  track('Track'),
  audio('Audio'),
  fades('Fades'),
  misc('Miscellaneous');

  final String label;
  const ShortcutCategory(this.label);
}

/// Shortcut entry with metadata
class ShortcutEntry {
  final String id;
  final String name;
  final ShortcutCategory category;
  final ShortcutDef defaultDef;
  ShortcutDef? customDef;

  ShortcutEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.defaultDef,
    this.customDef,
  });

  ShortcutDef get currentDef => customDef ?? defaultDef;
  bool get isCustomized => customDef != null;
}

class ShortcutsSettingsScreen extends StatefulWidget {
  const ShortcutsSettingsScreen({super.key});

  @override
  State<ShortcutsSettingsScreen> createState() => _ShortcutsSettingsScreenState();
}

class _ShortcutsSettingsScreenState extends State<ShortcutsSettingsScreen> {
  late List<ShortcutEntry> _shortcuts;
  String? _editingId;
  String _searchQuery = '';
  ShortcutCategory? _filterCategory;

  @override
  void initState() {
    super.initState();
    _initShortcuts();
    _loadCustomShortcuts();
  }

  void _initShortcuts() {
    _shortcuts = [
      // Transport
      ShortcutEntry(
        id: 'playPause',
        name: 'Play / Pause',
        category: ShortcutCategory.transport,
        defaultDef: kShortcuts['playPause']!,
      ),
      ShortcutEntry(
        id: 'stop',
        name: 'Stop',
        category: ShortcutCategory.transport,
        defaultDef: kShortcuts['stop']!,
      ),
      ShortcutEntry(
        id: 'record',
        name: 'Record',
        category: ShortcutCategory.transport,
        defaultDef: kShortcuts['record']!,
      ),

      // File
      ShortcutEntry(
        id: 'save',
        name: 'Save Project',
        category: ShortcutCategory.file,
        defaultDef: kShortcuts['save']!,
      ),
      ShortcutEntry(
        id: 'saveAs',
        name: 'Save As...',
        category: ShortcutCategory.file,
        defaultDef: kShortcuts['saveAs']!,
      ),
      ShortcutEntry(
        id: 'open',
        name: 'Open Project',
        category: ShortcutCategory.file,
        defaultDef: kShortcuts['open']!,
      ),
      ShortcutEntry(
        id: 'new',
        name: 'New Project',
        category: ShortcutCategory.file,
        defaultDef: kShortcuts['new']!,
      ),
      ShortcutEntry(
        id: 'export',
        name: 'Export Audio',
        category: ShortcutCategory.file,
        defaultDef: kShortcuts['export']!,
      ),

      // Edit
      ShortcutEntry(
        id: 'undo',
        name: 'Undo',
        category: ShortcutCategory.edit,
        defaultDef: kShortcuts['undo']!,
      ),
      ShortcutEntry(
        id: 'redo',
        name: 'Redo',
        category: ShortcutCategory.edit,
        defaultDef: kShortcuts['redo']!,
      ),
      ShortcutEntry(
        id: 'delete',
        name: 'Delete',
        category: ShortcutCategory.edit,
        defaultDef: kShortcuts['delete']!,
      ),
      ShortcutEntry(
        id: 'selectAll',
        name: 'Select All',
        category: ShortcutCategory.edit,
        defaultDef: kShortcuts['selectAll']!,
      ),
      ShortcutEntry(
        id: 'cut',
        name: 'Cut',
        category: ShortcutCategory.edit,
        defaultDef: kShortcuts['cut']!,
      ),
      ShortcutEntry(
        id: 'copy',
        name: 'Copy',
        category: ShortcutCategory.edit,
        defaultDef: kShortcuts['copy']!,
      ),
      ShortcutEntry(
        id: 'paste',
        name: 'Paste',
        category: ShortcutCategory.edit,
        defaultDef: kShortcuts['paste']!,
      ),
      ShortcutEntry(
        id: 'duplicate',
        name: 'Duplicate',
        category: ShortcutCategory.edit,
        defaultDef: kShortcuts['duplicate']!,
      ),

      // Timeline
      ShortcutEntry(
        id: 'split',
        name: 'Split at Cursor',
        category: ShortcutCategory.timeline,
        defaultDef: kShortcuts['split']!,
      ),
      ShortcutEntry(
        id: 'trim',
        name: 'Trim',
        category: ShortcutCategory.timeline,
        defaultDef: kShortcuts['trim']!,
      ),
      ShortcutEntry(
        id: 'mute',
        name: 'Mute',
        category: ShortcutCategory.timeline,
        defaultDef: kShortcuts['mute']!,
      ),
      ShortcutEntry(
        id: 'solo',
        name: 'Solo',
        category: ShortcutCategory.timeline,
        defaultDef: kShortcuts['solo']!,
      ),
      ShortcutEntry(
        id: 'arm',
        name: 'Arm for Recording',
        category: ShortcutCategory.timeline,
        defaultDef: kShortcuts['arm']!,
      ),

      // Zoom
      ShortcutEntry(
        id: 'zoomIn',
        name: 'Zoom In',
        category: ShortcutCategory.zoom,
        defaultDef: kShortcuts['zoomIn']!,
      ),
      ShortcutEntry(
        id: 'zoomOut',
        name: 'Zoom Out',
        category: ShortcutCategory.zoom,
        defaultDef: kShortcuts['zoomOut']!,
      ),
      ShortcutEntry(
        id: 'zoomToFit',
        name: 'Zoom to Fit',
        category: ShortcutCategory.zoom,
        defaultDef: kShortcuts['zoomToFit']!,
      ),
      ShortcutEntry(
        id: 'zoomToSelection',
        name: 'Zoom to Selection',
        category: ShortcutCategory.zoom,
        defaultDef: kShortcuts['zoomToSelection']!,
      ),

      // Loop
      ShortcutEntry(
        id: 'expandLoopToContent',
        name: 'Expand Loop to Content',
        category: ShortcutCategory.loop,
        defaultDef: kShortcuts['expandLoopToContent']!,
      ),
      ShortcutEntry(
        id: 'setLoopFromSelection',
        name: 'Set Loop from Selection',
        category: ShortcutCategory.loop,
        defaultDef: kShortcuts['setLoopFromSelection']!,
      ),

      // Navigation
      ShortcutEntry(
        id: 'goToStart',
        name: 'Go to Start',
        category: ShortcutCategory.navigation,
        defaultDef: kShortcuts['goToStart']!,
      ),
      ShortcutEntry(
        id: 'goToEnd',
        name: 'Go to End',
        category: ShortcutCategory.navigation,
        defaultDef: kShortcuts['goToEnd']!,
      ),
      ShortcutEntry(
        id: 'goToLeftLocator',
        name: 'Go to Left Locator',
        category: ShortcutCategory.navigation,
        defaultDef: kShortcuts['goToLeftLocator']!,
      ),
      ShortcutEntry(
        id: 'goToRightLocator',
        name: 'Go to Right Locator',
        category: ShortcutCategory.navigation,
        defaultDef: kShortcuts['goToRightLocator']!,
      ),
      ShortcutEntry(
        id: 'nudgeLeft',
        name: 'Nudge Left',
        category: ShortcutCategory.navigation,
        defaultDef: kShortcuts['nudgeLeft']!,
      ),
      ShortcutEntry(
        id: 'nudgeRight',
        name: 'Nudge Right',
        category: ShortcutCategory.navigation,
        defaultDef: kShortcuts['nudgeRight']!,
      ),

      // Toggle
      ShortcutEntry(
        id: 'toggleSnap',
        name: 'Toggle Snap',
        category: ShortcutCategory.toggle,
        defaultDef: kShortcuts['toggleSnap']!,
      ),
      ShortcutEntry(
        id: 'toggleMetronome',
        name: 'Toggle Metronome',
        category: ShortcutCategory.toggle,
        defaultDef: kShortcuts['toggleMetronome']!,
      ),
      ShortcutEntry(
        id: 'toggleMixer',
        name: 'Toggle Mixer',
        category: ShortcutCategory.toggle,
        defaultDef: kShortcuts['toggleMixer']!,
      ),
      ShortcutEntry(
        id: 'toggleInspector',
        name: 'Toggle Inspector',
        category: ShortcutCategory.toggle,
        defaultDef: kShortcuts['toggleInspector']!,
      ),
      ShortcutEntry(
        id: 'toggleBrowser',
        name: 'Toggle Browser',
        category: ShortcutCategory.toggle,
        defaultDef: kShortcuts['toggleBrowser']!,
      ),

      // Track
      ShortcutEntry(
        id: 'addTrack',
        name: 'Add Track',
        category: ShortcutCategory.track,
        defaultDef: kShortcuts['addTrack']!,
      ),
      ShortcutEntry(
        id: 'removeTrack',
        name: 'Remove Track',
        category: ShortcutCategory.track,
        defaultDef: kShortcuts['removeTrack']!,
      ),

      // Audio
      ShortcutEntry(
        id: 'bounce',
        name: 'Bounce Selection',
        category: ShortcutCategory.audio,
        defaultDef: kShortcuts['bounce']!,
      ),
      ShortcutEntry(
        id: 'normalize',
        name: 'Normalize',
        category: ShortcutCategory.audio,
        defaultDef: kShortcuts['normalize']!,
      ),
      ShortcutEntry(
        id: 'reverse',
        name: 'Reverse',
        category: ShortcutCategory.audio,
        defaultDef: kShortcuts['reverse']!,
      ),

      // Fades
      ShortcutEntry(
        id: 'fadeIn',
        name: 'Create Fade In',
        category: ShortcutCategory.fades,
        defaultDef: kShortcuts['fadeIn']!,
      ),
      ShortcutEntry(
        id: 'fadeOut',
        name: 'Create Fade Out',
        category: ShortcutCategory.fades,
        defaultDef: kShortcuts['fadeOut']!,
      ),
      ShortcutEntry(
        id: 'crossfade',
        name: 'Create Crossfade',
        category: ShortcutCategory.fades,
        defaultDef: kShortcuts['crossfade']!,
      ),

      // Misc
      ShortcutEntry(
        id: 'quantize',
        name: 'Quantize',
        category: ShortcutCategory.misc,
        defaultDef: kShortcuts['quantize']!,
      ),
      ShortcutEntry(
        id: 'preferences',
        name: 'Preferences',
        category: ShortcutCategory.misc,
        defaultDef: kShortcuts['preferences']!,
      ),
      ShortcutEntry(
        id: 'fullscreen',
        name: 'Toggle Fullscreen',
        category: ShortcutCategory.misc,
        defaultDef: kShortcuts['fullscreen']!,
      ),
    ];
  }

  Future<void> _loadCustomShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('custom_shortcuts');
    if (json != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(json);
        for (final entry in _shortcuts) {
          if (data.containsKey(entry.id)) {
            final custom = data[entry.id] as Map<String, dynamic>;
            entry.customDef = ShortcutDef(
              key: custom['key'] as String,
              display: custom['display'] as String,
              mod: custom['mod'] != null
                  ? ShortcutModifiers(
                      ctrl: custom['mod']['ctrl'] ?? false,
                      shift: custom['mod']['shift'] ?? false,
                      alt: custom['mod']['alt'] ?? false,
                      meta: custom['mod']['meta'] ?? false,
                      cmd: custom['mod']['cmd'] ?? false,
                    )
                  : null,
            );
          }
        }
        setState(() {});
      } catch (e) {
        debugPrint('Error loading custom shortcuts: $e');
      }
    }
  }

  Future<void> _saveCustomShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> data = {};
    for (final entry in _shortcuts) {
      if (entry.isCustomized) {
        data[entry.id] = {
          'key': entry.customDef!.key,
          'display': entry.customDef!.display,
          if (entry.customDef!.mod != null)
            'mod': {
              'ctrl': entry.customDef!.mod!.ctrl,
              'shift': entry.customDef!.mod!.shift,
              'alt': entry.customDef!.mod!.alt,
              'meta': entry.customDef!.mod!.meta,
              'cmd': entry.customDef!.mod!.cmd,
            },
        };
      }
    }
    await prefs.setString('custom_shortcuts', jsonEncode(data));
  }

  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ReelForgeTheme.bgMid,
        title: const Text('Reset Shortcuts', style: TextStyle(color: ReelForgeTheme.textPrimary)),
        content: const Text(
          'This will reset all keyboard shortcuts to their default values. Continue?',
          style: TextStyle(color: ReelForgeTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              for (final entry in _shortcuts) {
                entry.customDef = null;
              }
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('custom_shortcuts');
              setState(() {});
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Reset', style: TextStyle(color: ReelForgeTheme.accentRed)),
          ),
        ],
      ),
    );
  }

  void _startEditing(String id) {
    setState(() => _editingId = id);
  }

  void _cancelEditing() {
    setState(() => _editingId = null);
  }

  void _handleKeyCapture(KeyEvent event, ShortcutEntry entry) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;

    // Escape cancels
    if (key == LogicalKeyboardKey.escape) {
      _cancelEditing();
      return;
    }

    // Build modifiers
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    final isCmd = isMeta || isCtrl;

    // Build display string
    final parts = <String>[];
    if (isCmd) parts.add('⌘');
    if (isShift) parts.add('⇧');
    if (isAlt) parts.add('⌥');

    // Get key label
    String keyLabel;
    if (key == LogicalKeyboardKey.space) {
      keyLabel = 'Space';
    } else if (key == LogicalKeyboardKey.enter) {
      keyLabel = '↵';
    } else if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      keyLabel = '⌫';
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      keyLabel = '←';
    } else if (key == LogicalKeyboardKey.arrowRight) {
      keyLabel = '→';
    } else if (key == LogicalKeyboardKey.arrowUp) {
      keyLabel = '↑';
    } else if (key == LogicalKeyboardKey.arrowDown) {
      keyLabel = '↓';
    } else if (key == LogicalKeyboardKey.home) {
      keyLabel = 'Home';
    } else if (key == LogicalKeyboardKey.end) {
      keyLabel = 'End';
    } else {
      keyLabel = key.keyLabel.toUpperCase();
    }
    parts.add(keyLabel);

    final display = parts.join('');

    // Update entry
    entry.customDef = ShortcutDef(
      key: key.keyLabel,
      display: display,
      mod: ShortcutModifiers(
        ctrl: isCtrl,
        shift: isShift,
        alt: isAlt,
        meta: isMeta,
        cmd: isCmd,
      ),
    );

    _saveCustomShortcuts();
    setState(() => _editingId = null);
  }

  List<ShortcutEntry> get _filteredShortcuts {
    var list = _shortcuts;

    // Filter by category
    if (_filterCategory != null) {
      list = list.where((e) => e.category == _filterCategory).toList();
    }

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      list = list.where((e) =>
          e.name.toLowerCase().contains(query) ||
          e.currentDef.display.toLowerCase().contains(query)).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    // Group by category
    final grouped = <ShortcutCategory, List<ShortcutEntry>>{};
    for (final entry in _filteredShortcuts) {
      grouped.putIfAbsent(entry.category, () => []).add(entry);
    }

    return Scaffold(
      backgroundColor: ReelForgeTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: ReelForgeTheme.bgMid,
        title: const Text('Keyboard Shortcuts', style: TextStyle(color: ReelForgeTheme.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: ReelForgeTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('Reset All'),
            onPressed: _resetToDefaults,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and filter bar
          Container(
            padding: const EdgeInsets.all(12),
            color: ReelForgeTheme.bgMid,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search shortcuts...',
                      hintStyle: const TextStyle(color: ReelForgeTheme.textMuted),
                      prefixIcon: const Icon(Icons.search, color: ReelForgeTheme.textMuted),
                      filled: true,
                      fillColor: ReelForgeTheme.bgDeep,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    style: const TextStyle(color: ReelForgeTheme.textPrimary),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<ShortcutCategory?>(
                  value: _filterCategory,
                  hint: const Text('All Categories', style: TextStyle(color: ReelForgeTheme.textSecondary)),
                  dropdownColor: ReelForgeTheme.bgMid,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All Categories', style: TextStyle(color: ReelForgeTheme.textPrimary)),
                    ),
                    ...ShortcutCategory.values.map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.label, style: const TextStyle(color: ReelForgeTheme.textPrimary)),
                        )),
                  ],
                  onChanged: (v) => setState(() => _filterCategory = v),
                ),
              ],
            ),
          ),

          // Shortcuts list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final category in grouped.keys) ...[
                  // Category header
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Text(
                      category.label,
                      style: const TextStyle(
                        color: ReelForgeTheme.accentOrange,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  // Shortcut rows
                  Container(
                    decoration: BoxDecoration(
                      color: ReelForgeTheme.bgMid,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < grouped[category]!.length; i++)
                          _buildShortcutRow(grouped[category]![i], i == grouped[category]!.length - 1),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutRow(ShortcutEntry entry, bool isLast) {
    final isEditing = _editingId == entry.id;

    return Focus(
      onKeyEvent: isEditing ? (node, event) {
        _handleKeyCapture(event, entry);
        return KeyEventResult.handled;
      } : null,
      autofocus: isEditing,
      child: InkWell(
        onTap: () => _startEditing(entry.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: isLast ? null : Border(
              bottom: BorderSide(color: ReelForgeTheme.bgDeep.withOpacity(0.5)),
            ),
            color: isEditing ? ReelForgeTheme.accentBlue.withOpacity(0.1) : null,
          ),
          child: Row(
            children: [
              // Action name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: const TextStyle(
                        color: ReelForgeTheme.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                    if (entry.isCustomized)
                      const Text(
                        'Customized',
                        style: TextStyle(
                          color: ReelForgeTheme.accentCyan,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),

              // Shortcut key
              if (isEditing)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: ReelForgeTheme.accentBlue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: ReelForgeTheme.accentBlue),
                  ),
                  child: const Text(
                    'Press key...',
                    style: TextStyle(
                      color: ReelForgeTheme.accentBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: ReelForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.currentDef.display,
                    style: TextStyle(
                      color: entry.isCustomized
                          ? ReelForgeTheme.accentCyan
                          : ReelForgeTheme.textSecondary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

              const SizedBox(width: 8),

              // Reset button (if customized)
              if (entry.isCustomized && !isEditing)
                IconButton(
                  icon: const Icon(Icons.restore, size: 18),
                  color: ReelForgeTheme.textMuted,
                  tooltip: 'Reset to default',
                  onPressed: () {
                    entry.customDef = null;
                    _saveCustomShortcuts();
                    setState(() {});
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
