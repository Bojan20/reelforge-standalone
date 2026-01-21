// Editor Mode Provider
//
// Manages the current editor mode (DAW vs Middleware):
// - DAW Mode: Timeline-centric editing, full mixer
// - Middleware Mode: Event-centric editing, game integration
//
// Features:
// - Keyboard shortcuts (Cmd+1, Cmd+2, Cmd+`)
// - Persistence to storage
// - Accent color per mode

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// ============ Types ============

enum EditorMode { daw, middleware }

class EditorModeConfig {
  final EditorMode mode;
  final String name;
  final String description;
  final String icon;
  final int accentColor;
  final String shortcut;

  const EditorModeConfig({
    required this.mode,
    required this.name,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.shortcut,
  });
}

// ============ Mode Configurations ============

const Map<EditorMode, EditorModeConfig> kModeConfigs = {
  EditorMode.daw: EditorModeConfig(
    mode: EditorMode.daw,
    name: 'DAW',
    description: 'Timeline editing & mixing',
    icon: '🎹',
    accentColor: 0xFF0EA5E9, // Blue
    shortcut: '⌘1',
  ),
  EditorMode.middleware: EditorModeConfig(
    mode: EditorMode.middleware,
    name: 'Events',
    description: 'Event routing & game integration',
    icon: '🎮',
    accentColor: 0xFFF97316, // Orange
    shortcut: '⌘2',
  ),
};

// ============ Provider ============

class EditorModeProvider extends ChangeNotifier {
  EditorMode _mode;
  final FocusNode _focusNode = FocusNode();

  /// Waveform generation counter - increments when returning to DAW mode
  /// to force timeline waveform cache invalidation.
  /// This prevents stale waveform rendering after SlotLab/Middleware usage.
  int _waveformGeneration = 0;

  EditorModeProvider({EditorMode initialMode = EditorMode.daw})
      : _mode = initialMode;

  EditorMode get mode => _mode;
  EditorModeConfig get config => kModeConfigs[_mode]!;
  List<EditorModeConfig> get modes => kModeConfigs.values.toList();
  FocusNode get focusNode => _focusNode;

  /// Current waveform generation - compare with cached value to detect invalidation
  int get waveformGeneration => _waveformGeneration;

  bool isMode(EditorMode checkMode) => _mode == checkMode;

  void setMode(EditorMode newMode) {
    if (_mode != newMode) {
      final wasDAW = _mode == EditorMode.daw;
      _mode = newMode;

      // When returning TO DAW mode, increment waveform generation
      // to force timeline clips to refresh their waveform cache.
      // This ensures waveforms render correctly after SlotLab usage.
      if (newMode == EditorMode.daw && !wasDAW) {
        _waveformGeneration++;
      }

      notifyListeners();
    }
  }

  void toggleMode() {
    _mode = _mode == EditorMode.daw ? EditorMode.middleware : EditorMode.daw;
    notifyListeners();
  }

  /// Handle keyboard shortcuts
  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

    if (!isCmd) return KeyEventResult.ignored;

    // Cmd+1 = DAW mode
    if (event.logicalKey == LogicalKeyboardKey.digit1) {
      setMode(EditorMode.daw);
      return KeyEventResult.handled;
    }

    // Cmd+2 = Middleware mode
    if (event.logicalKey == LogicalKeyboardKey.digit2) {
      setMode(EditorMode.middleware);
      return KeyEventResult.handled;
    }

    // Cmd+` = Toggle mode
    if (event.logicalKey == LogicalKeyboardKey.backquote) {
      toggleMode();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }
}
