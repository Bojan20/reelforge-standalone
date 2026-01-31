/// Command Palette (P1.2)
///
/// VS Code-style command palette with fuzzy search and keyboard navigation.
/// Open with Cmd+K (Mac) or Ctrl+K (Windows/Linux).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lower_zone/lower_zone_types.dart';

/// Single command definition
class Command {
  final String label;
  final String? description;
  final IconData? icon;
  final VoidCallback onExecute;
  final List<String> keywords;
  final String? shortcut; // Display shortcut hint (e.g., "⌘S")

  const Command({
    required this.label,
    this.description,
    this.icon,
    required this.onExecute,
    this.keywords = const [],
    this.shortcut,
  });
}

/// Pre-built FluxForge DAW commands
class FluxForgeCommands {
  /// Generate DAW commands with callbacks
  static List<Command> forDaw({
    required VoidCallback onNewProject,
    required VoidCallback onOpenProject,
    required VoidCallback onSaveProject,
    required VoidCallback onExport,
    required VoidCallback onUndo,
    required VoidCallback onRedo,
    required VoidCallback onToggleMixer,
    required VoidCallback onToggleTimeline,
    required VoidCallback onAddTrack,
    required VoidCallback onDeleteTrack,
    required VoidCallback onToggleMetronome,
    required VoidCallback onToggleSnap,
    required VoidCallback onZoomIn,
    required VoidCallback onZoomOut,
    required VoidCallback onGoToStart,
    required VoidCallback onGoToEnd,
  }) {
    return [
      // File commands
      Command(
        label: 'New Project',
        description: 'Create a new empty project',
        icon: Icons.add_box,
        onExecute: onNewProject,
        keywords: ['new', 'create', 'project', 'file'],
        shortcut: '⌘N',
      ),
      Command(
        label: 'Open Project',
        description: 'Open an existing project',
        icon: Icons.folder_open,
        onExecute: onOpenProject,
        keywords: ['open', 'load', 'project', 'file'],
        shortcut: '⌘O',
      ),
      Command(
        label: 'Save Project',
        description: 'Save current project',
        icon: Icons.save,
        onExecute: onSaveProject,
        keywords: ['save', 'project', 'file'],
        shortcut: '⌘S',
      ),
      Command(
        label: 'Export Audio',
        description: 'Export project to audio file',
        icon: Icons.file_download,
        onExecute: onExport,
        keywords: ['export', 'bounce', 'render', 'wav', 'mp3'],
        shortcut: '⌘⇧E',
      ),

      // Edit commands
      Command(
        label: 'Undo',
        description: 'Undo last action',
        icon: Icons.undo,
        onExecute: onUndo,
        keywords: ['undo', 'back', 'revert'],
        shortcut: '⌘Z',
      ),
      Command(
        label: 'Redo',
        description: 'Redo last undone action',
        icon: Icons.redo,
        onExecute: onRedo,
        keywords: ['redo', 'forward'],
        shortcut: '⌘⇧Z',
      ),

      // View commands
      Command(
        label: 'Toggle Mixer',
        description: 'Show/hide mixer panel',
        icon: Icons.tune,
        onExecute: onToggleMixer,
        keywords: ['mixer', 'fader', 'console', 'view'],
        shortcut: 'M',
      ),
      Command(
        label: 'Toggle Timeline',
        description: 'Show/hide timeline panel',
        icon: Icons.view_timeline,
        onExecute: onToggleTimeline,
        keywords: ['timeline', 'arrangement', 'view'],
        shortcut: 'T',
      ),

      // Track commands
      Command(
        label: 'Add Audio Track',
        description: 'Create new audio track',
        icon: Icons.add,
        onExecute: onAddTrack,
        keywords: ['add', 'new', 'track', 'audio', 'create'],
        shortcut: '⌘⇧T',
      ),
      Command(
        label: 'Delete Track',
        description: 'Delete selected track',
        icon: Icons.delete,
        onExecute: onDeleteTrack,
        keywords: ['delete', 'remove', 'track'],
        shortcut: '⌫',
      ),

      // Transport commands
      Command(
        label: 'Toggle Metronome',
        description: 'Turn metronome on/off',
        icon: Icons.timer,
        onExecute: onToggleMetronome,
        keywords: ['metronome', 'click', 'tempo'],
        shortcut: 'C',
      ),
      Command(
        label: 'Toggle Snap',
        description: 'Turn grid snap on/off',
        icon: Icons.grid_on,
        onExecute: onToggleSnap,
        keywords: ['snap', 'grid', 'quantize'],
        shortcut: 'G',
      ),

      // Navigation commands
      Command(
        label: 'Zoom In',
        description: 'Zoom in on timeline',
        icon: Icons.zoom_in,
        onExecute: onZoomIn,
        keywords: ['zoom', 'in', 'magnify'],
        shortcut: '⌘+',
      ),
      Command(
        label: 'Zoom Out',
        description: 'Zoom out on timeline',
        icon: Icons.zoom_out,
        onExecute: onZoomOut,
        keywords: ['zoom', 'out', 'shrink'],
        shortcut: '⌘-',
      ),
      Command(
        label: 'Go to Start',
        description: 'Jump to project start',
        icon: Icons.first_page,
        onExecute: onGoToStart,
        keywords: ['start', 'beginning', 'home'],
        shortcut: 'Home',
      ),
      Command(
        label: 'Go to End',
        description: 'Jump to project end',
        icon: Icons.last_page,
        onExecute: onGoToEnd,
        keywords: ['end', 'finish'],
        shortcut: 'End',
      ),
    ];
  }
}

class CommandPalette extends StatefulWidget {
  final List<Command> commands;

  const CommandPalette({super.key, required this.commands});

  static Future<void> show(BuildContext context, List<Command> commands) {
    return showDialog(context: context, builder: (_) => CommandPalette(commands: commands));
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  List<Command> _filteredCommands = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _filteredCommands = widget.commands;
    _searchController.addListener(_filterCommands);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _filterCommands() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredCommands = query.isEmpty ? widget.commands : widget.commands.where((cmd) {
        return cmd.label.toLowerCase().contains(query) ||
            (cmd.description?.toLowerCase().contains(query) ?? false) ||
            cmd.keywords.any((k) => k.toLowerCase().contains(query));
      }).toList();
      _selectedIndex = 0;
    });
  }

  void _executeSelected() {
    if (_filteredCommands.isNotEmpty && _selectedIndex < _filteredCommands.length) {
      _filteredCommands[_selectedIndex].onExecute();
      Navigator.pop(context);
    }
  }

  void _moveSelection(int delta) {
    if (_filteredCommands.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, _filteredCommands.length - 1);
    });
    // Scroll to keep selected item visible
    final itemHeight = 56.0; // Approximate item height
    final scrollOffset = _selectedIndex * itemHeight;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        scrollOffset,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _executeSelected();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.pop(context);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Center(
          child: Container(
            width: 600,
            constraints: const BoxConstraints(maxHeight: 500),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgDeep,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: LowerZoneColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: LowerZoneColors.border.withValues(alpha: 0.5)),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 14, color: LowerZoneColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Type a command or search...',
                      hintStyle: const TextStyle(color: LowerZoneColors.textMuted),
                      prefixIcon: const Icon(Icons.search, color: LowerZoneColors.dawAccent),
                      border: InputBorder.none,
                      suffixText: '${_filteredCommands.length} commands',
                      suffixStyle: const TextStyle(fontSize: 11, color: LowerZoneColors.textTertiary),
                    ),
                    // Enable proper text selection behaviors
                    enableInteractiveSelection: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    cursorColor: LowerZoneColors.dawAccent,
                  ),
                ),
                // Command list
                Flexible(
                  child: _filteredCommands.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No commands found',
                              style: TextStyle(color: LowerZoneColors.textMuted),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          shrinkWrap: true,
                          itemCount: _filteredCommands.length,
                          itemBuilder: (context, index) {
                            final cmd = _filteredCommands[index];
                            final isSelected = index == _selectedIndex;
                            return MouseRegion(
                              onEnter: (_) => setState(() => _selectedIndex = index),
                              child: GestureDetector(
                                onTap: () {
                                  cmd.onExecute();
                                  Navigator.pop(context);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? LowerZoneColors.dawAccent.withValues(alpha: 0.15)
                                        : Colors.transparent,
                                    border: Border(
                                      left: BorderSide(
                                        color: isSelected ? LowerZoneColors.dawAccent : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Icon
                                      SizedBox(
                                        width: 28,
                                        child: cmd.icon != null
                                            ? Icon(cmd.icon, size: 16, color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.textSecondary)
                                            : null,
                                      ),
                                      // Label + description
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              cmd.label,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: isSelected ? LowerZoneColors.textPrimary : LowerZoneColors.textSecondary,
                                                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                                              ),
                                            ),
                                            if (cmd.description != null)
                                              Text(
                                                cmd.description!,
                                                style: const TextStyle(fontSize: 11, color: LowerZoneColors.textTertiary),
                                              ),
                                          ],
                                        ),
                                      ),
                                      // Shortcut badge
                                      if (cmd.shortcut != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: LowerZoneColors.bgMid,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: LowerZoneColors.border),
                                          ),
                                          child: Text(
                                            cmd.shortcut!,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: LowerZoneColors.textTertiary,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
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
