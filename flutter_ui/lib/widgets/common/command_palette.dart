// Command Palette / Widget Search
//
// VS Code-style command palette for quick navigation:
// - Ctrl+Shift+P (Cmd+Shift+P on Mac) to open
// - Search widgets, panels, and actions
// - Recent items tracking
// - Keyboard navigation
//
// Implements gap identified in Ultimate System Analysis:
// "No Ctrl+Shift+P style 'go to widget' search"

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';

/// Command type for categorization
enum CommandCategory {
  navigation,
  action,
  widget,
  settings,
  help,
}

/// A command/action that can be executed from the palette
class PaletteCommand {
  final String id;
  final String label;
  final String? description;
  final CommandCategory category;
  final IconData icon;
  final VoidCallback? onExecute;
  final List<String> keywords;
  final String? shortcut;

  const PaletteCommand({
    required this.id,
    required this.label,
    this.description,
    required this.category,
    required this.icon,
    this.onExecute,
    this.keywords = const [],
    this.shortcut,
  });

  /// Match score for search (higher = better match)
  int matchScore(String query) {
    if (query.isEmpty) return 100;

    final q = query.toLowerCase();
    final l = label.toLowerCase();

    // Exact match
    if (l == q) return 1000;

    // Starts with
    if (l.startsWith(q)) return 500;

    // Contains
    if (l.contains(q)) return 300;

    // Keyword match
    for (final keyword in keywords) {
      if (keyword.toLowerCase().contains(q)) return 200;
    }

    // Description match
    if (description?.toLowerCase().contains(q) ?? false) return 100;

    return 0;
  }
}

/// Command Palette overlay widget
class CommandPalette extends StatefulWidget {
  final List<PaletteCommand> commands;
  final VoidCallback onClose;
  final Function(PaletteCommand)? onCommandSelected;

  const CommandPalette({
    super.key,
    required this.commands,
    required this.onClose,
    this.onCommandSelected,
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();

  /// Show the command palette as an overlay
  static void show(
    BuildContext context, {
    required List<PaletteCommand> commands,
    Function(PaletteCommand)? onCommandSelected,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => CommandPalette(
        commands: commands,
        onClose: () => Navigator.of(ctx).pop(),
        onCommandSelected: (cmd) {
          Navigator.of(ctx).pop();
          onCommandSelected?.call(cmd);
          cmd.onExecute?.call();
        },
      ),
    );
  }
}

class _CommandPaletteState extends State<CommandPalette> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  int _selectedIndex = 0;
  List<PaletteCommand> _filteredCommands = [];
  static final List<String> _recentCommandIds = [];

  @override
  void initState() {
    super.initState();
    _filteredCommands = _getFilteredCommands('');
    _focusNode.requestFocus();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _filteredCommands = _getFilteredCommands(_searchController.text);
      _selectedIndex = 0;
    });
  }

  List<PaletteCommand> _getFilteredCommands(String query) {
    final scored = widget.commands
        .map((cmd) => (cmd: cmd, score: cmd.matchScore(query)))
        .where((item) => item.score > 0)
        .toList();

    // Sort by score, then by recent usage
    scored.sort((a, b) {
      // Boost recent commands
      final aRecent = _recentCommandIds.indexOf(a.cmd.id);
      final bRecent = _recentCommandIds.indexOf(b.cmd.id);
      final aBoost = aRecent >= 0 ? 50 - aRecent : 0;
      final bBoost = bRecent >= 0 ? 50 - bRecent : 0;

      return (b.score + bBoost).compareTo(a.score + aBoost);
    });

    return scored.map((s) => s.cmd).toList();
  }

  void _executeCommand(PaletteCommand command) {
    // Track recent commands
    _recentCommandIds.remove(command.id);
    _recentCommandIds.insert(0, command.id);
    if (_recentCommandIds.length > 10) {
      _recentCommandIds.removeLast();
    }

    widget.onCommandSelected?.call(command);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % _filteredCommands.length;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1 + _filteredCommands.length) %
            _filteredCommands.length;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_filteredCommands.isNotEmpty) {
        _executeCommand(_filteredCommands[_selectedIndex]);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: _handleKeyEvent,
          child: Container(
            width: 600,
            constraints: const BoxConstraints(maxHeight: 500),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: FluxForgeTheme.accentBlue.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSearchBar(),
                if (_filteredCommands.isNotEmpty) _buildCommandList(),
                if (_filteredCommands.isEmpty) _buildEmptyState(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: FluxForgeTheme.bgDeep,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            color: FluxForgeTheme.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Search widgets, panels, and actions...',
                hintStyle: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'ESC to close',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandList() {
    return Flexible(
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _filteredCommands.length,
        itemBuilder: (context, index) {
          final command = _filteredCommands[index];
          final isSelected = index == _selectedIndex;

          return _CommandItem(
            command: command,
            isSelected: isSelected,
            isRecent: _recentCommandIds.contains(command.id),
            onTap: () => _executeCommand(command),
            onHover: (hovering) {
              if (hovering) {
                setState(() => _selectedIndex = index);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            color: FluxForgeTheme.textSecondary,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            'No matching commands',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandItem extends StatelessWidget {
  final PaletteCommand command;
  final bool isSelected;
  final bool isRecent;
  final VoidCallback onTap;
  final Function(bool) onHover;

  const _CommandItem({
    required this.command,
    required this.isSelected,
    required this.isRecent,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: isSelected
                ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              // Category icon
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _getCategoryColor(command.category).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  command.icon,
                  color: _getCategoryColor(command.category),
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),

              // Label and description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          command.label,
                          style: TextStyle(
                            color: FluxForgeTheme.textPrimary,
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                        if (isRecent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.accentOrange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'Recent',
                              style: TextStyle(
                                color: FluxForgeTheme.accentOrange,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (command.description != null)
                      Text(
                        command.description!,
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),

              // Category badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  command.category.name,
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ),

              // Shortcut
              if (command.shortcut != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: FluxForgeTheme.textSecondary.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    command.shortcut!,
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(CommandCategory category) {
    switch (category) {
      case CommandCategory.navigation:
        return FluxForgeTheme.accentBlue;
      case CommandCategory.action:
        return FluxForgeTheme.accentGreen;
      case CommandCategory.widget:
        return FluxForgeTheme.accentCyan;
      case CommandCategory.settings:
        return FluxForgeTheme.accentOrange;
      case CommandCategory.help:
        return FluxForgeTheme.textSecondary;
    }
  }
}

/// Mixin for screens that support the command palette
mixin CommandPaletteMixin<T extends StatefulWidget> on State<T> {
  List<PaletteCommand> get paletteCommands => [];

  void showCommandPalette() {
    CommandPalette.show(
      context,
      commands: paletteCommands,
      onCommandSelected: onCommandSelected,
    );
  }

  void onCommandSelected(PaletteCommand command) {
    // Override in subclass for custom handling
  }
}

/// Global command palette controller
class CommandPaletteController {
  static final CommandPaletteController instance = CommandPaletteController._();
  CommandPaletteController._();

  final List<PaletteCommand> _globalCommands = [];
  final Map<String, List<PaletteCommand>> _contextCommands = {};

  /// Register global commands (always available)
  void registerGlobalCommands(List<PaletteCommand> commands) {
    _globalCommands.addAll(commands);
  }

  /// Register context-specific commands
  void registerContextCommands(String context, List<PaletteCommand> commands) {
    _contextCommands[context] = commands;
  }

  /// Unregister context commands
  void unregisterContextCommands(String context) {
    _contextCommands.remove(context);
  }

  /// Get all commands for current context
  List<PaletteCommand> getCommands({String? context}) {
    final commands = [..._globalCommands];
    if (context != null && _contextCommands.containsKey(context)) {
      commands.addAll(_contextCommands[context]!);
    }
    return commands;
  }

  /// Show the command palette
  void show(BuildContext context, {String? contextName}) {
    CommandPalette.show(
      context,
      commands: getCommands(context: contextName),
    );
  }
}

/// Default FluxForge commands
class FluxForgeCommands {
  static List<PaletteCommand> getDefaultCommands({
    required VoidCallback onNavigateToDAW,
    required VoidCallback onNavigateToSlotLab,
    required VoidCallback onNavigateToMiddleware,
    required VoidCallback onOpenSettings,
    required VoidCallback onOpenHelp,
    VoidCallback? onNewProject,
    VoidCallback? onOpenProject,
    VoidCallback? onSaveProject,
    VoidCallback? onExport,
    VoidCallback? onUndo,
    VoidCallback? onRedo,
  }) {
    return [
      // Navigation
      PaletteCommand(
        id: 'nav.daw',
        label: 'Go to DAW',
        description: 'Open the DAW timeline view',
        category: CommandCategory.navigation,
        icon: Icons.audiotrack,
        keywords: ['timeline', 'tracks', 'arrangement'],
        shortcut: '⌘1',
        onExecute: onNavigateToDAW,
      ),
      PaletteCommand(
        id: 'nav.slotlab',
        label: 'Go to Slot Lab',
        description: 'Open the Slot Lab audio design environment',
        category: CommandCategory.navigation,
        icon: Icons.casino,
        keywords: ['slot', 'game', 'casino', 'reels'],
        shortcut: '⌘2',
        onExecute: onNavigateToSlotLab,
      ),
      PaletteCommand(
        id: 'nav.middleware',
        label: 'Go to Middleware',
        description: 'Open the middleware configuration',
        category: CommandCategory.navigation,
        icon: Icons.settings_input_component,
        keywords: ['events', 'rtpc', 'states', 'switches'],
        shortcut: '⌘3',
        onExecute: onNavigateToMiddleware,
      ),

      // Actions
      if (onNewProject != null)
        PaletteCommand(
          id: 'action.new',
          label: 'New Project',
          description: 'Create a new FluxForge project',
          category: CommandCategory.action,
          icon: Icons.add_circle_outline,
          keywords: ['create', 'new', 'project'],
          shortcut: '⌘N',
          onExecute: onNewProject,
        ),
      if (onOpenProject != null)
        PaletteCommand(
          id: 'action.open',
          label: 'Open Project',
          description: 'Open an existing project',
          category: CommandCategory.action,
          icon: Icons.folder_open,
          keywords: ['open', 'load', 'project'],
          shortcut: '⌘O',
          onExecute: onOpenProject,
        ),
      if (onSaveProject != null)
        PaletteCommand(
          id: 'action.save',
          label: 'Save Project',
          description: 'Save the current project',
          category: CommandCategory.action,
          icon: Icons.save,
          keywords: ['save', 'write'],
          shortcut: '⌘S',
          onExecute: onSaveProject,
        ),
      if (onExport != null)
        PaletteCommand(
          id: 'action.export',
          label: 'Export Audio',
          description: 'Export audio to file',
          category: CommandCategory.action,
          icon: Icons.upload_file,
          keywords: ['export', 'bounce', 'render'],
          shortcut: '⌘E',
          onExecute: onExport,
        ),
      if (onUndo != null)
        PaletteCommand(
          id: 'action.undo',
          label: 'Undo',
          description: 'Undo last action',
          category: CommandCategory.action,
          icon: Icons.undo,
          keywords: ['undo', 'revert'],
          shortcut: '⌘Z',
          onExecute: onUndo,
        ),
      if (onRedo != null)
        PaletteCommand(
          id: 'action.redo',
          label: 'Redo',
          description: 'Redo last undone action',
          category: CommandCategory.action,
          icon: Icons.redo,
          keywords: ['redo'],
          shortcut: '⌘⇧Z',
          onExecute: onRedo,
        ),

      // Widgets
      PaletteCommand(
        id: 'widget.mixer',
        label: 'Mixer Panel',
        description: 'Open the mixer panel',
        category: CommandCategory.widget,
        icon: Icons.tune,
        keywords: ['mixer', 'faders', 'volume', 'pan'],
      ),
      PaletteCommand(
        id: 'widget.eq',
        label: 'EQ Panel',
        description: 'Open the equalizer panel',
        category: CommandCategory.widget,
        icon: Icons.equalizer,
        keywords: ['eq', 'equalizer', 'frequency', 'bands'],
      ),
      PaletteCommand(
        id: 'widget.compressor',
        label: 'Compressor Panel',
        description: 'Open the compressor panel',
        category: CommandCategory.widget,
        icon: Icons.compress,
        keywords: ['compressor', 'dynamics', 'threshold', 'ratio'],
      ),
      PaletteCommand(
        id: 'widget.reverb',
        label: 'Reverb Panel',
        description: 'Open the reverb panel',
        category: CommandCategory.widget,
        icon: Icons.waves,
        keywords: ['reverb', 'space', 'room', 'decay'],
      ),
      PaletteCommand(
        id: 'widget.limiter',
        label: 'Limiter Panel',
        description: 'Open the limiter panel',
        category: CommandCategory.widget,
        icon: Icons.horizontal_rule,
        keywords: ['limiter', 'ceiling', 'loudness'],
      ),
      PaletteCommand(
        id: 'widget.gate',
        label: 'Gate Panel',
        description: 'Open the gate panel',
        category: CommandCategory.widget,
        icon: Icons.door_front_door,
        keywords: ['gate', 'noise', 'threshold'],
      ),
      PaletteCommand(
        id: 'widget.metering',
        label: 'Metering Panel',
        description: 'Open the metering panel',
        category: CommandCategory.widget,
        icon: Icons.show_chart,
        keywords: ['meters', 'lufs', 'peak', 'rms', 'levels'],
      ),
      PaletteCommand(
        id: 'widget.browser',
        label: 'Audio Browser',
        description: 'Open the audio file browser',
        category: CommandCategory.widget,
        icon: Icons.folder,
        keywords: ['browser', 'files', 'audio', 'samples'],
      ),
      PaletteCommand(
        id: 'widget.eventlog',
        label: 'Event Log',
        description: 'Open the event log panel',
        category: CommandCategory.widget,
        icon: Icons.list_alt,
        keywords: ['events', 'log', 'history'],
      ),
      PaletteCommand(
        id: 'widget.profiler',
        label: 'DSP Profiler',
        description: 'Open the DSP performance profiler',
        category: CommandCategory.widget,
        icon: Icons.speed,
        keywords: ['profiler', 'cpu', 'performance', 'load'],
      ),
      PaletteCommand(
        id: 'widget.statemachine',
        label: 'State Machine Graph',
        description: 'Open the visual state machine editor',
        category: CommandCategory.widget,
        icon: Icons.account_tree,
        keywords: ['state', 'machine', 'graph', 'nodes'],
      ),
      PaletteCommand(
        id: 'widget.reelstrip',
        label: 'Reel Strip Editor',
        description: 'Open the visual reel strip editor',
        category: CommandCategory.widget,
        icon: Icons.view_column,
        keywords: ['reel', 'strip', 'symbols', 'slot'],
      ),
      PaletteCommand(
        id: 'widget.audition',
        label: 'In-Context Audition',
        description: 'Open the in-context auditioning panel',
        category: CommandCategory.widget,
        icon: Icons.play_circle,
        keywords: ['audition', 'preview', 'context'],
      ),

      // Debug & Monitoring Widgets
      PaletteCommand(
        id: 'widget.voicepool',
        label: 'Voice Pool Stats',
        description: 'Monitor engine voice pool utilization',
        category: CommandCategory.widget,
        icon: Icons.multitrack_audio,
        keywords: ['voice', 'pool', 'stats', 'polyphony', 'utilization'],
      ),
      PaletteCommand(
        id: 'widget.statetransitions',
        label: 'State Transition History',
        description: 'View state and switch group transition log',
        category: CommandCategory.widget,
        icon: Icons.history,
        keywords: ['state', 'transition', 'history', 'log', 'debug'],
      ),
      PaletteCommand(
        id: 'widget.containermetrics',
        label: 'Container Metrics',
        description: 'View container storage statistics',
        category: CommandCategory.widget,
        icon: Icons.storage,
        keywords: ['container', 'blend', 'random', 'sequence', 'metrics'],
      ),
      PaletteCommand(
        id: 'widget.duckingmatrix',
        label: 'Ducking Matrix',
        description: 'Configure bus ducking relationships',
        category: CommandCategory.widget,
        icon: Icons.grid_on,
        keywords: ['ducking', 'sidechain', 'bus', 'matrix'],
      ),
      PaletteCommand(
        id: 'widget.blendcontainer',
        label: 'Blend Container',
        description: 'RTPC-based sound crossfading',
        category: CommandCategory.widget,
        icon: Icons.tune,
        keywords: ['blend', 'crossfade', 'rtpc', 'container'],
      ),
      PaletteCommand(
        id: 'widget.randomcontainer',
        label: 'Random Container',
        description: 'Weighted random sound selection',
        category: CommandCategory.widget,
        icon: Icons.shuffle,
        keywords: ['random', 'weighted', 'variation', 'container'],
      ),
      PaletteCommand(
        id: 'widget.sequencecontainer',
        label: 'Sequence Container',
        description: 'Timed sound sequences',
        category: CommandCategory.widget,
        icon: Icons.queue_music,
        keywords: ['sequence', 'timeline', 'steps', 'container'],
      ),
      PaletteCommand(
        id: 'widget.musicsystem',
        label: 'Music System',
        description: 'Beat-synchronized music and stingers',
        category: CommandCategory.widget,
        icon: Icons.music_note,
        keywords: ['music', 'stinger', 'beat', 'sync', 'tempo'],
      ),
      PaletteCommand(
        id: 'widget.autospatial',
        label: 'AutoSpatial Panel',
        description: 'UI-driven spatial audio positioning',
        category: CommandCategory.widget,
        icon: Icons.surround_sound,
        keywords: ['spatial', 'pan', 'position', 'auto', '3d'],
      ),
      PaletteCommand(
        id: 'widget.ale',
        label: 'Adaptive Layer Engine',
        description: 'Dynamic music layer system',
        category: CommandCategory.widget,
        icon: Icons.layers,
        keywords: ['adaptive', 'layer', 'engine', 'ale', 'dynamic', 'music'],
      ),
      PaletteCommand(
        id: 'widget.stageingest',
        label: 'Stage Ingest',
        description: 'Engine event import and mapping',
        category: CommandCategory.widget,
        icon: Icons.input,
        keywords: ['stage', 'ingest', 'import', 'adapter', 'engine'],
      ),
      PaletteCommand(
        id: 'widget.routingmatrix',
        label: 'Routing Matrix',
        description: 'Track to bus routing visualization',
        category: CommandCategory.widget,
        icon: Icons.route,
        keywords: ['routing', 'matrix', 'bus', 'send', 'track'],
      ),

      // Settings
      PaletteCommand(
        id: 'settings.preferences',
        label: 'Preferences',
        description: 'Open application preferences',
        category: CommandCategory.settings,
        icon: Icons.settings,
        keywords: ['settings', 'preferences', 'options'],
        shortcut: '⌘,',
        onExecute: onOpenSettings,
      ),
      PaletteCommand(
        id: 'settings.audio',
        label: 'Audio Settings',
        description: 'Configure audio device and buffer settings',
        category: CommandCategory.settings,
        icon: Icons.headphones,
        keywords: ['audio', 'device', 'buffer', 'latency'],
      ),
      PaletteCommand(
        id: 'settings.theme',
        label: 'Theme Settings',
        description: 'Customize the application theme',
        category: CommandCategory.settings,
        icon: Icons.palette,
        keywords: ['theme', 'color', 'appearance'],
      ),
      PaletteCommand(
        id: 'settings.keybindings',
        label: 'Keyboard Shortcuts',
        description: 'View and customize keyboard shortcuts',
        category: CommandCategory.settings,
        icon: Icons.keyboard,
        keywords: ['keyboard', 'shortcuts', 'keys', 'bindings'],
      ),

      // Help
      PaletteCommand(
        id: 'help.docs',
        label: 'Documentation',
        description: 'Open the documentation',
        category: CommandCategory.help,
        icon: Icons.menu_book,
        keywords: ['docs', 'documentation', 'manual', 'help'],
        shortcut: 'F1',
        onExecute: onOpenHelp,
      ),
      PaletteCommand(
        id: 'help.about',
        label: 'About FluxForge',
        description: 'About FluxForge Studio',
        category: CommandCategory.help,
        icon: Icons.info_outline,
        keywords: ['about', 'version', 'info'],
      ),
    ];
  }

  /// Get Slot Lab specific commands
  static List<PaletteCommand> getSlotLabCommands({
    VoidCallback? onSpin,
    VoidCallback? onForceBigWin,
    VoidCallback? onForceFreespins,
    VoidCallback? onToggleTurbo,
  }) {
    return [
      if (onSpin != null)
        PaletteCommand(
          id: 'slotlab.spin',
          label: 'Spin',
          description: 'Perform a spin in the slot preview',
          category: CommandCategory.action,
          icon: Icons.refresh,
          keywords: ['spin', 'play'],
          shortcut: 'Space',
          onExecute: onSpin,
        ),
      if (onForceBigWin != null)
        PaletteCommand(
          id: 'slotlab.bigwin',
          label: 'Force Big Win',
          description: 'Force a big win outcome for testing',
          category: CommandCategory.action,
          icon: Icons.star,
          keywords: ['big', 'win', 'force', 'test'],
          shortcut: '3',
          onExecute: onForceBigWin,
        ),
      if (onForceFreespins != null)
        PaletteCommand(
          id: 'slotlab.freespins',
          label: 'Force Free Spins',
          description: 'Force free spins trigger for testing',
          category: CommandCategory.action,
          icon: Icons.card_giftcard,
          keywords: ['free', 'spins', 'force', 'test'],
          shortcut: '6',
          onExecute: onForceFreespins,
        ),
      if (onToggleTurbo != null)
        PaletteCommand(
          id: 'slotlab.turbo',
          label: 'Toggle Turbo Mode',
          description: 'Toggle turbo spin mode',
          category: CommandCategory.action,
          icon: Icons.fast_forward,
          keywords: ['turbo', 'fast', 'speed'],
          shortcut: 'T',
          onExecute: onToggleTurbo,
        ),
    ];
  }

  /// Get DAW specific commands
  static List<PaletteCommand> getDAWCommands({
    VoidCallback? onPlay,
    VoidCallback? onStop,
    VoidCallback? onRecord,
    VoidCallback? onAddTrack,
    VoidCallback? onDeleteTrack,
    VoidCallback? onSplitClip,
    VoidCallback? onMergeClips,
  }) {
    return [
      if (onPlay != null)
        PaletteCommand(
          id: 'daw.play',
          label: 'Play',
          description: 'Start playback',
          category: CommandCategory.action,
          icon: Icons.play_arrow,
          keywords: ['play', 'start'],
          shortcut: 'Space',
          onExecute: onPlay,
        ),
      if (onStop != null)
        PaletteCommand(
          id: 'daw.stop',
          label: 'Stop',
          description: 'Stop playback',
          category: CommandCategory.action,
          icon: Icons.stop,
          keywords: ['stop'],
          onExecute: onStop,
        ),
      if (onRecord != null)
        PaletteCommand(
          id: 'daw.record',
          label: 'Record',
          description: 'Start recording',
          category: CommandCategory.action,
          icon: Icons.fiber_manual_record,
          keywords: ['record', 'arm'],
          shortcut: 'R',
          onExecute: onRecord,
        ),
      if (onAddTrack != null)
        PaletteCommand(
          id: 'daw.addtrack',
          label: 'Add Track',
          description: 'Add a new track',
          category: CommandCategory.action,
          icon: Icons.add,
          keywords: ['add', 'track', 'new'],
          shortcut: '⌘T',
          onExecute: onAddTrack,
        ),
      if (onDeleteTrack != null)
        PaletteCommand(
          id: 'daw.deletetrack',
          label: 'Delete Track',
          description: 'Delete selected track',
          category: CommandCategory.action,
          icon: Icons.delete,
          keywords: ['delete', 'remove', 'track'],
          shortcut: '⌘⌫',
          onExecute: onDeleteTrack,
        ),
      if (onSplitClip != null)
        PaletteCommand(
          id: 'daw.split',
          label: 'Split Clip',
          description: 'Split clip at playhead',
          category: CommandCategory.action,
          icon: Icons.content_cut,
          keywords: ['split', 'cut', 'clip'],
          shortcut: 'S',
          onExecute: onSplitClip,
        ),
      if (onMergeClips != null)
        PaletteCommand(
          id: 'daw.merge',
          label: 'Merge Clips',
          description: 'Merge selected clips',
          category: CommandCategory.action,
          icon: Icons.merge,
          keywords: ['merge', 'join', 'clips'],
          shortcut: '⌘M',
          onExecute: onMergeClips,
        ),
    ];
  }
}
