// Keyboard Focus Mode Provider
//
// Pro Tools-style Keyboard Focus Mode that enables single-key commands
// without modifier keys when focused on timeline/edit window.
//
// When enabled:
// - A-Z keys directly trigger editing commands
// - Number keys for track selection, navigation
// - No modifier needed (Cmd/Ctrl/Alt)
//
// Commands Mode (Pro Tools style):
// - A: Toggle Automation mode
// - B: Fade both (in/out)
// - C: Copy
// - D: Duplicate
// - E: Edit tool
// - F: Fade tool / Fade-in
// - G: Grab/Grid toggle
// - H: Heal separation
// - I: Insert silence
// - J: Join clips
// - K: Trim End to cursor
// - L: Loop playback
// - M: Mute clip
// - N: Next clip
// - O: Open plugin
// - P: Previous clip
// - Q: Quantize
// - R: Rename clip
// - S: Separate (split)
// - T: Trim tool
// - U: Strip silence
// - V: Paste
// - W: Close window
// - X: Cut
// - Y: Redo (alternative)
// - Z: Zoom tool

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Focus mode state
enum KeyboardFocusMode {
  /// Normal mode - standard shortcuts with modifiers
  normal,

  /// Commands mode - single-key commands (Pro Tools "Commands Focus")
  commands,
}

/// Keyboard command types
enum KeyboardCommand {
  // Edit commands
  toggleAutomation,
  fadeBoth,
  copy,
  duplicate,
  editTool,
  fadeTool,
  gridToggle,
  healSeparation,
  insertSilence,
  joinClips,
  trimEndToCursor,
  loopPlayback,
  muteClip,
  nextClip,
  openPlugin,
  previousClip,
  quantize,
  renameClip,
  separate,
  trimTool,
  stripSilence,
  paste,
  closeWindow,
  cut,
  redo,
  zoomTool,

  // Number key commands
  selectTrack1,
  selectTrack2,
  selectTrack3,
  selectTrack4,
  selectTrack5,
  selectTrack6,
  selectTrack7,
  selectTrack8,
  selectTrack9,
  selectTrack10,

  // Navigation (arrow keys in focus mode)
  nudgeLeft,
  nudgeRight,
  nudgeUp,
  nudgeDown,

  // Playback
  play,
  stop,
  record,

  // Special
  escape,
}

/// Command configuration
class KeyboardCommandConfig {
  final KeyboardCommand command;
  final String displayName;
  final String description;
  final IconData icon;

  const KeyboardCommandConfig({
    required this.command,
    required this.displayName,
    required this.description,
    required this.icon,
  });
}

/// Complete command mapping
final Map<LogicalKeyboardKey, KeyboardCommand> kCommandsFocusMapping = {
  // Letters A-Z
  LogicalKeyboardKey.keyA: KeyboardCommand.toggleAutomation,
  LogicalKeyboardKey.keyB: KeyboardCommand.fadeBoth,
  LogicalKeyboardKey.keyC: KeyboardCommand.copy,
  LogicalKeyboardKey.keyD: KeyboardCommand.duplicate,
  LogicalKeyboardKey.keyE: KeyboardCommand.editTool,
  LogicalKeyboardKey.keyF: KeyboardCommand.fadeTool,
  LogicalKeyboardKey.keyG: KeyboardCommand.gridToggle,
  LogicalKeyboardKey.keyH: KeyboardCommand.healSeparation,
  LogicalKeyboardKey.keyI: KeyboardCommand.insertSilence,
  LogicalKeyboardKey.keyJ: KeyboardCommand.joinClips,
  LogicalKeyboardKey.keyK: KeyboardCommand.trimEndToCursor,
  LogicalKeyboardKey.keyL: KeyboardCommand.loopPlayback,
  LogicalKeyboardKey.keyM: KeyboardCommand.muteClip,
  LogicalKeyboardKey.keyN: KeyboardCommand.nextClip,
  LogicalKeyboardKey.keyO: KeyboardCommand.openPlugin,
  LogicalKeyboardKey.keyP: KeyboardCommand.previousClip,
  LogicalKeyboardKey.keyQ: KeyboardCommand.quantize,
  LogicalKeyboardKey.keyR: KeyboardCommand.renameClip,
  LogicalKeyboardKey.keyS: KeyboardCommand.separate,
  LogicalKeyboardKey.keyT: KeyboardCommand.trimTool,
  LogicalKeyboardKey.keyU: KeyboardCommand.stripSilence,
  LogicalKeyboardKey.keyV: KeyboardCommand.paste,
  LogicalKeyboardKey.keyW: KeyboardCommand.closeWindow,
  LogicalKeyboardKey.keyX: KeyboardCommand.cut,
  LogicalKeyboardKey.keyY: KeyboardCommand.redo,
  LogicalKeyboardKey.keyZ: KeyboardCommand.zoomTool,

  // Number keys for track selection
  LogicalKeyboardKey.digit1: KeyboardCommand.selectTrack1,
  LogicalKeyboardKey.digit2: KeyboardCommand.selectTrack2,
  LogicalKeyboardKey.digit3: KeyboardCommand.selectTrack3,
  LogicalKeyboardKey.digit4: KeyboardCommand.selectTrack4,
  LogicalKeyboardKey.digit5: KeyboardCommand.selectTrack5,
  LogicalKeyboardKey.digit6: KeyboardCommand.selectTrack6,
  LogicalKeyboardKey.digit7: KeyboardCommand.selectTrack7,
  LogicalKeyboardKey.digit8: KeyboardCommand.selectTrack8,
  LogicalKeyboardKey.digit9: KeyboardCommand.selectTrack9,
  LogicalKeyboardKey.digit0: KeyboardCommand.selectTrack10,

  // Navigation
  LogicalKeyboardKey.arrowLeft: KeyboardCommand.nudgeLeft,
  LogicalKeyboardKey.arrowRight: KeyboardCommand.nudgeRight,
  LogicalKeyboardKey.arrowUp: KeyboardCommand.nudgeUp,
  LogicalKeyboardKey.arrowDown: KeyboardCommand.nudgeDown,

  // Playback (always work in focus mode)
  LogicalKeyboardKey.space: KeyboardCommand.play,
  LogicalKeyboardKey.enter: KeyboardCommand.stop,

  // Escape exits focus mode
  LogicalKeyboardKey.escape: KeyboardCommand.escape,
};

/// Command descriptions for UI display
const Map<KeyboardCommand, KeyboardCommandConfig> kCommandConfigs = {
  KeyboardCommand.toggleAutomation: KeyboardCommandConfig(
    command: KeyboardCommand.toggleAutomation,
    displayName: 'Automation',
    description: 'Toggle automation read/write mode',
    icon: Icons.auto_graph,
  ),
  KeyboardCommand.fadeBoth: KeyboardCommandConfig(
    command: KeyboardCommand.fadeBoth,
    displayName: 'Fade Both',
    description: 'Create fade-in and fade-out on selection',
    icon: Icons.gradient,
  ),
  KeyboardCommand.copy: KeyboardCommandConfig(
    command: KeyboardCommand.copy,
    displayName: 'Copy',
    description: 'Copy selected clips to clipboard',
    icon: Icons.copy,
  ),
  KeyboardCommand.duplicate: KeyboardCommandConfig(
    command: KeyboardCommand.duplicate,
    displayName: 'Duplicate',
    description: 'Duplicate selected clips',
    icon: Icons.control_point_duplicate,
  ),
  KeyboardCommand.editTool: KeyboardCommandConfig(
    command: KeyboardCommand.editTool,
    displayName: 'Edit Tool',
    description: 'Switch to selection/edit tool',
    icon: Icons.edit,
  ),
  KeyboardCommand.fadeTool: KeyboardCommandConfig(
    command: KeyboardCommand.fadeTool,
    displayName: 'Fade Tool',
    description: 'Switch to fade/crossfade tool',
    icon: Icons.wb_twilight,
  ),
  KeyboardCommand.gridToggle: KeyboardCommandConfig(
    command: KeyboardCommand.gridToggle,
    displayName: 'Grid Toggle',
    description: 'Toggle snap-to-grid',
    icon: Icons.grid_on,
  ),
  KeyboardCommand.healSeparation: KeyboardCommandConfig(
    command: KeyboardCommand.healSeparation,
    displayName: 'Heal',
    description: 'Heal clip separation (join at edit point)',
    icon: Icons.healing,
  ),
  KeyboardCommand.insertSilence: KeyboardCommandConfig(
    command: KeyboardCommand.insertSilence,
    displayName: 'Insert Silence',
    description: 'Insert silence at cursor position',
    icon: Icons.space_bar,
  ),
  KeyboardCommand.joinClips: KeyboardCommandConfig(
    command: KeyboardCommand.joinClips,
    displayName: 'Join Clips',
    description: 'Join selected clips into one',
    icon: Icons.merge,
  ),
  KeyboardCommand.trimEndToCursor: KeyboardCommandConfig(
    command: KeyboardCommand.trimEndToCursor,
    displayName: 'Trim End',
    description: 'Trim clip end to cursor position',
    icon: Icons.content_cut,
  ),
  KeyboardCommand.loopPlayback: KeyboardCommandConfig(
    command: KeyboardCommand.loopPlayback,
    displayName: 'Loop',
    description: 'Toggle loop playback',
    icon: Icons.loop,
  ),
  KeyboardCommand.muteClip: KeyboardCommandConfig(
    command: KeyboardCommand.muteClip,
    displayName: 'Mute Clip',
    description: 'Mute/unmute selected clips',
    icon: Icons.volume_off,
  ),
  KeyboardCommand.nextClip: KeyboardCommandConfig(
    command: KeyboardCommand.nextClip,
    displayName: 'Next Clip',
    description: 'Navigate to next clip',
    icon: Icons.skip_next,
  ),
  KeyboardCommand.openPlugin: KeyboardCommandConfig(
    command: KeyboardCommand.openPlugin,
    displayName: 'Open Plugin',
    description: 'Open plugin window for selected insert',
    icon: Icons.extension,
  ),
  KeyboardCommand.previousClip: KeyboardCommandConfig(
    command: KeyboardCommand.previousClip,
    displayName: 'Previous Clip',
    description: 'Navigate to previous clip',
    icon: Icons.skip_previous,
  ),
  KeyboardCommand.quantize: KeyboardCommandConfig(
    command: KeyboardCommand.quantize,
    displayName: 'Quantize',
    description: 'Quantize selected MIDI notes',
    icon: Icons.view_module,
  ),
  KeyboardCommand.renameClip: KeyboardCommandConfig(
    command: KeyboardCommand.renameClip,
    displayName: 'Rename',
    description: 'Rename selected clip',
    icon: Icons.drive_file_rename_outline,
  ),
  KeyboardCommand.separate: KeyboardCommandConfig(
    command: KeyboardCommand.separate,
    displayName: 'Separate',
    description: 'Split clip at cursor (Pro Tools: Separate)',
    icon: Icons.call_split,
  ),
  KeyboardCommand.trimTool: KeyboardCommandConfig(
    command: KeyboardCommand.trimTool,
    displayName: 'Trim Tool',
    description: 'Switch to trim tool',
    icon: Icons.crop,
  ),
  KeyboardCommand.stripSilence: KeyboardCommandConfig(
    command: KeyboardCommand.stripSilence,
    displayName: 'Strip Silence',
    description: 'Remove silent sections from clips',
    icon: Icons.remove_circle_outline,
  ),
  KeyboardCommand.paste: KeyboardCommandConfig(
    command: KeyboardCommand.paste,
    displayName: 'Paste',
    description: 'Paste clips from clipboard',
    icon: Icons.paste,
  ),
  KeyboardCommand.closeWindow: KeyboardCommandConfig(
    command: KeyboardCommand.closeWindow,
    displayName: 'Close Window',
    description: 'Close current window/panel',
    icon: Icons.close,
  ),
  KeyboardCommand.cut: KeyboardCommandConfig(
    command: KeyboardCommand.cut,
    displayName: 'Cut',
    description: 'Cut selected clips to clipboard',
    icon: Icons.content_cut,
  ),
  KeyboardCommand.redo: KeyboardCommandConfig(
    command: KeyboardCommand.redo,
    displayName: 'Redo',
    description: 'Redo last undone action',
    icon: Icons.redo,
  ),
  KeyboardCommand.zoomTool: KeyboardCommandConfig(
    command: KeyboardCommand.zoomTool,
    displayName: 'Zoom Tool',
    description: 'Switch to zoom tool',
    icon: Icons.zoom_in,
  ),
};

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Keyboard Focus Mode Provider
///
/// Manages Pro Tools-style keyboard focus mode where single keys
/// directly trigger editing commands without modifiers.
class KeyboardFocusProvider extends ChangeNotifier {
  KeyboardFocusMode _mode = KeyboardFocusMode.normal;
  bool _isEnabled = true;

  // Command callbacks - set by parent widgets
  final Map<KeyboardCommand, VoidCallback?> _commandHandlers = {};

  // Visual feedback
  KeyboardCommand? _lastExecutedCommand;
  DateTime? _lastCommandTime;

  // Focus node for keyboard events
  final FocusNode _focusNode = FocusNode(debugLabel: 'KeyboardFocusProvider');

  // ═══ Getters ═══

  KeyboardFocusMode get mode => _mode;
  bool get isCommandsMode => _mode == KeyboardFocusMode.commands;
  bool get isEnabled => _isEnabled;
  FocusNode get focusNode => _focusNode;
  KeyboardCommand? get lastExecutedCommand => _lastExecutedCommand;

  /// Check if last command was executed recently (for visual feedback)
  bool get showCommandFeedback {
    if (_lastCommandTime == null) return false;
    return DateTime.now().difference(_lastCommandTime!).inMilliseconds < 500;
  }

  // ═══ Mode Control ═══

  /// Enable/disable keyboard focus mode
  void setEnabled(bool enabled) {
    if (_isEnabled != enabled) {
      _isEnabled = enabled;
      if (!enabled) {
        _mode = KeyboardFocusMode.normal;
      }
      notifyListeners();
    }
  }

  /// Set focus mode
  void setMode(KeyboardFocusMode mode) {
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }
  }

  /// Toggle between normal and commands mode
  void toggleMode() {
    _mode = _mode == KeyboardFocusMode.normal
        ? KeyboardFocusMode.commands
        : KeyboardFocusMode.normal;
    notifyListeners();
  }

  /// Enable commands focus mode
  void enableCommandsMode() => setMode(KeyboardFocusMode.commands);

  /// Exit to normal mode
  void exitCommandsMode() => setMode(KeyboardFocusMode.normal);

  // ═══ Command Registration ═══

  /// Register a handler for a specific command
  void registerHandler(KeyboardCommand command, VoidCallback? handler) {
    _commandHandlers[command] = handler;
  }

  /// Register multiple handlers at once
  void registerHandlers(Map<KeyboardCommand, VoidCallback?> handlers) {
    _commandHandlers.addAll(handlers);
  }

  /// Unregister a handler
  void unregisterHandler(KeyboardCommand command) {
    _commandHandlers.remove(command);
  }

  /// Clear all handlers
  void clearHandlers() {
    _commandHandlers.clear();
  }

  // ═══ Command Execution ═══

  /// Execute a command directly
  void executeCommand(KeyboardCommand command) {
    final handler = _commandHandlers[command];
    if (handler != null) {
      handler();
      _lastExecutedCommand = command;
      _lastCommandTime = DateTime.now();
      notifyListeners();
    }
  }

  /// Handle key event (called from keyboard listener)
  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (!_isEnabled) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Skip shortcuts when user is typing in a text field (e.g. track rename)
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus.context != null) {
      final editable = primaryFocus.context!
          .findAncestorWidgetOfExactType<EditableText>();
      if (editable != null) return KeyEventResult.ignored;
    }

    // In commands mode, single keys trigger commands
    if (_mode == KeyboardFocusMode.commands) {
      return _handleCommandsModeKey(event);
    }

    // In normal mode, check for toggle shortcut
    return _handleNormalModeKey(event);
  }

  /// Handle key in commands mode
  KeyEventResult _handleCommandsModeKey(KeyEvent event) {
    final key = event.logicalKey;

    // Check for mapped command (uses custom mappings if set)
    final command = effectiveMapping[key];
    if (command != null) {
      // Escape exits commands mode
      if (command == KeyboardCommand.escape) {
        exitCommandsMode();
        return KeyEventResult.handled;
      }

      // Execute the command
      executeCommand(command);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Handle key in normal mode (check for mode toggle)
  KeyEventResult _handleNormalModeKey(KeyEvent event) {
    final key = event.logicalKey;
    final isCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    // Cmd+Shift+A = Toggle commands focus mode (like Pro Tools)
    if (isCmd && isShift && !isAlt && key == LogicalKeyboardKey.keyA) {
      toggleMode();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ═══ UI Helpers ═══

  /// Get display name for current mode
  String get modeDisplayName {
    switch (_mode) {
      case KeyboardFocusMode.normal:
        return 'Normal';
      case KeyboardFocusMode.commands:
        return 'Commands';
    }
  }

  /// Get icon for current mode
  IconData get modeIcon {
    switch (_mode) {
      case KeyboardFocusMode.normal:
        return Icons.keyboard;
      case KeyboardFocusMode.commands:
        return Icons.keyboard_command_key;
    }
  }

  /// Get color for current mode
  Color get modeColor {
    switch (_mode) {
      case KeyboardFocusMode.normal:
        return const Color(0xFF4a9eff); // Blue
      case KeyboardFocusMode.commands:
        return const Color(0xFFff9040); // Orange - indicates active commands mode
    }
  }

  /// Get all available commands with their keys
  List<MapEntry<String, KeyboardCommandConfig>> getCommandList() {
    return kCommandsFocusMapping.entries
        .where((e) => kCommandConfigs.containsKey(e.value))
        .map((e) {
          final keyLabel = _getKeyLabel(e.key);
          final config = kCommandConfigs[e.value]!;
          return MapEntry(keyLabel, config);
        })
        .toList();
  }

  /// Get key label for display
  String _getKeyLabel(LogicalKeyboardKey key) {
    // Handle special keys
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.arrowLeft) return '←';
    if (key == LogicalKeyboardKey.arrowRight) return '→';
    if (key == LogicalKeyboardKey.arrowUp) return '↑';
    if (key == LogicalKeyboardKey.arrowDown) return '↓';

    // For letters and numbers, use the key label
    final label = key.keyLabel;
    return label.length == 1 ? label.toUpperCase() : label;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P3.1: KEYBOARD SHORTCUTS CUSTOMIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Custom key mappings (overrides defaults)
  final Map<LogicalKeyboardKey, KeyboardCommand> _customMappings = {};

  /// Whether custom mappings are active
  bool get hasCustomMappings => _customMappings.isNotEmpty;

  /// Get current effective mapping (custom or default)
  Map<LogicalKeyboardKey, KeyboardCommand> get effectiveMapping {
    if (_customMappings.isEmpty) return kCommandsFocusMapping;
    final merged = Map<LogicalKeyboardKey, KeyboardCommand>.from(kCommandsFocusMapping);
    merged.addAll(_customMappings);
    return merged;
  }

  /// Get the key currently assigned to a command
  LogicalKeyboardKey? getKeyForCommand(KeyboardCommand command) {
    final mapping = effectiveMapping;
    for (final entry in mapping.entries) {
      if (entry.value == command) return entry.key;
    }
    return null;
  }

  /// Get the command currently assigned to a key
  KeyboardCommand? getCommandForKey(LogicalKeyboardKey key) {
    return effectiveMapping[key];
  }

  /// Remap a command to a new key
  /// Returns the previously assigned command (if any) for conflict detection
  KeyboardCommand? remapCommand(KeyboardCommand command, LogicalKeyboardKey newKey) {
    // Check what was previously at this key
    final previousCommand = effectiveMapping[newKey];

    // Remove command from its old key in custom mappings
    _customMappings.removeWhere((k, v) => v == command);

    // Assign new key
    _customMappings[newKey] = command;

    notifyListeners();
    return previousCommand;
  }

  /// Swap two commands' keys
  void swapCommands(KeyboardCommand cmd1, KeyboardCommand cmd2) {
    final key1 = getKeyForCommand(cmd1);
    final key2 = getKeyForCommand(cmd2);

    if (key1 != null && key2 != null) {
      _customMappings[key1] = cmd2;
      _customMappings[key2] = cmd1;
      notifyListeners();
    }
  }

  /// Remove custom mapping for a command (revert to default)
  void resetCommandMapping(KeyboardCommand command) {
    _customMappings.removeWhere((k, v) => v == command);
    notifyListeners();
  }

  /// Reset all custom mappings to defaults
  void resetAllMappings() {
    _customMappings.clear();
    notifyListeners();
  }

  /// Export custom mappings as JSON for persistence
  Map<String, dynamic> exportMappings() {
    if (_customMappings.isEmpty) return {};
    final json = <String, dynamic>{};
    for (final entry in _customMappings.entries) {
      json[entry.key.keyId.toString()] = entry.value.name;
    }
    return json;
  }

  /// Import custom mappings from JSON
  void importMappings(Map<String, dynamic> json) {
    _customMappings.clear();
    for (final entry in json.entries) {
      final keyId = int.tryParse(entry.key);
      if (keyId == null) continue;

      // Find matching LogicalKeyboardKey
      LogicalKeyboardKey? key;
      for (final defaultKey in kCommandsFocusMapping.keys) {
        if (defaultKey.keyId == keyId) {
          key = defaultKey;
          break;
        }
      }
      if (key == null) continue;

      // Find matching command
      final commandName = entry.value as String?;
      if (commandName == null) continue;

      KeyboardCommand? command;
      for (final cmd in KeyboardCommand.values) {
        if (cmd.name == commandName) {
          command = cmd;
          break;
        }
      }
      if (command == null) continue;

      _customMappings[key] = command;
    }
    notifyListeners();
  }

  /// Get list of all commands with their current key assignments
  List<({KeyboardCommand command, LogicalKeyboardKey? key, bool isCustom})> getCustomizableCommands() {
    final result = <({KeyboardCommand command, LogicalKeyboardKey? key, bool isCustom})>[];

    for (final command in KeyboardCommand.values) {
      // Skip non-customizable commands
      if (command == KeyboardCommand.escape) continue;
      if (command == KeyboardCommand.play) continue; // Space is fixed
      if (command == KeyboardCommand.stop) continue; // Enter is fixed

      final currentKey = getKeyForCommand(command);
      final defaultKey = kCommandsFocusMapping.entries
          .where((e) => e.value == command)
          .map((e) => e.key)
          .firstOrNull;

      final isCustom = currentKey != defaultKey;

      result.add((command: command, key: currentKey, isCustom: isCustom));
    }

    return result;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _commandHandlers.clear();
    _customMappings.clear();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET: Commands Focus Indicator
// ═══════════════════════════════════════════════════════════════════════════════

/// Visual indicator for commands focus mode
class CommandsFocusIndicator extends StatelessWidget {
  final KeyboardFocusProvider provider;
  final VoidCallback? onTap;

  const CommandsFocusIndicator({
    super.key,
    required this.provider,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final isActive = provider.isCommandsMode;

        return GestureDetector(
          onTap: onTap ?? provider.toggleMode,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? provider.modeColor.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isActive
                    ? provider.modeColor
                    : const Color(0xFF3a3a40),
                width: isActive ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  provider.modeIcon,
                  size: 14,
                  color: isActive
                      ? provider.modeColor
                      : const Color(0xFF808090),
                ),
                const SizedBox(width: 4),
                Text(
                  isActive ? 'CMD' : 'A-Z',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isActive
                        ? provider.modeColor
                        : const Color(0xFF808090),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET: Command Feedback Overlay
// ═══════════════════════════════════════════════════════════════════════════════

/// Shows brief feedback when a command is executed
class CommandFeedbackOverlay extends StatelessWidget {
  final KeyboardFocusProvider provider;

  const CommandFeedbackOverlay({
    super.key,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        if (!provider.showCommandFeedback || provider.lastExecutedCommand == null) {
          return const SizedBox.shrink();
        }

        final config = kCommandConfigs[provider.lastExecutedCommand];
        if (config == null) return const SizedBox.shrink();

        return Positioned(
          top: 100,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: provider.showCommandFeedback ? 1.0 : 0.0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xE0202028),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF4a9eff),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      config.icon,
                      size: 20,
                      color: const Color(0xFF4a9eff),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      config.displayName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
