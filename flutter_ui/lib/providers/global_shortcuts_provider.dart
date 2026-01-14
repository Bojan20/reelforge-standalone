// Global Shortcuts Provider
//
// Cubase-style global keyboard shortcuts:
// - Space: Play/Pause
// - S: Split at cursor
// - G/H: Zoom out/in
// - Cmd+Z/Y: Undo/Redo
// - Delete: Delete selected
// - Cmd+D: Duplicate
// - M: Mute
// - And many more...

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// ============ Types ============

class ShortcutModifiers {
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;
  final bool cmd; // meta on Mac, ctrl on Windows

  const ShortcutModifiers({
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
    this.cmd = false,
  });
}

class ShortcutAction {
  void Function()? onPlayPause;
  void Function()? onStop;
  void Function()? onRecord;
  void Function()? onSave;
  void Function()? onSaveAs;
  void Function()? onOpen;
  void Function()? onNew;
  void Function()? onExport;
  void Function()? onUndo;
  void Function()? onRedo;
  void Function()? onDelete;
  void Function()? onDeselect;
  void Function()? onSelectAll;
  void Function()? onCut;
  void Function()? onCopy;
  void Function()? onPaste;
  void Function()? onDuplicate;
  void Function()? onSplit;
  void Function()? onTrim;
  void Function()? onMute;
  void Function()? onSolo;
  void Function()? onArm;
  void Function()? onZoomIn;
  void Function()? onZoomOut;
  void Function()? onZoomToFit;
  void Function()? onZoomToSelection;
  void Function()? onExpandLoopToContent;
  void Function()? onSetLoopFromSelection;
  void Function()? onGoToStart;
  void Function()? onGoToEnd;
  void Function()? onGoToLeftLocator;
  void Function()? onGoToRightLocator;
  void Function()? onNudgeLeft;
  void Function()? onNudgeRight;
  void Function()? onToggleSnap;
  void Function()? onToggleMetronome;
  void Function()? onToggleMixer;
  void Function()? onToggleInspector;
  void Function()? onToggleBrowser;
  void Function()? onToggleTransport;
  void Function()? onFocusTimeline;
  void Function()? onFocusMixer;
  void Function()? onAddTrack;
  void Function()? onRemoveTrack;
  void Function()? onBounce;
  void Function()? onNormalize;
  void Function()? onReverse;
  void Function()? onFadeIn;
  void Function()? onFadeOut;
  void Function()? onCrossfade;
  void Function()? onQuantize;
  void Function()? onPreferences;
  void Function()? onFullscreen;
  void Function()? onImportAudioFiles;

  // Advanced panel shortcuts (Cubase-style)
  void Function()? onShowLogicalEditor;
  void Function()? onShowScaleAssistant;
  void Function()? onShowGrooveQuantize;
  void Function()? onShowAudioAlignment;
  void Function()? onShowTrackVersions;
  void Function()? onShowMacroControls;
  void Function()? onShowClipGainEnvelope;

  bool Function(String key, ShortcutModifiers modifiers)? onCustom;

  ShortcutAction();
}

// ============ Shortcut Definitions ============

class ShortcutDef {
  final String key;
  final ShortcutModifiers? mod;
  final String display;

  const ShortcutDef({
    required this.key,
    this.mod,
    required this.display,
  });
}

const kShortcuts = <String, ShortcutDef>{
  // Transport
  'playPause': ShortcutDef(key: ' ', display: 'Space'),
  'stop': ShortcutDef(key: 'Enter', mod: ShortcutModifiers(cmd: true), display: '⌘↵'),
  'record': ShortcutDef(key: 'R', display: 'R'),

  // File
  'save': ShortcutDef(key: 'S', mod: ShortcutModifiers(cmd: true), display: '⌘S'),
  'saveAs': ShortcutDef(key: 'S', mod: ShortcutModifiers(cmd: true, shift: true), display: '⌘⇧S'),
  'open': ShortcutDef(key: 'O', mod: ShortcutModifiers(cmd: true), display: '⌘O'),
  'new': ShortcutDef(key: 'N', mod: ShortcutModifiers(cmd: true), display: '⌘N'),
  'export': ShortcutDef(key: 'E', mod: ShortcutModifiers(cmd: true), display: '⌘E'),

  // Edit
  'undo': ShortcutDef(key: 'Z', mod: ShortcutModifiers(cmd: true), display: '⌘Z'),
  'redo': ShortcutDef(key: 'Z', mod: ShortcutModifiers(cmd: true, shift: true), display: '⌘⇧Z'),
  'delete': ShortcutDef(key: 'Delete', display: '⌫'),
  'selectAll': ShortcutDef(key: 'A', mod: ShortcutModifiers(cmd: true), display: '⌘A'),
  'cut': ShortcutDef(key: 'X', mod: ShortcutModifiers(cmd: true), display: '⌘X'),
  'copy': ShortcutDef(key: 'C', mod: ShortcutModifiers(cmd: true), display: '⌘C'),
  'paste': ShortcutDef(key: 'V', mod: ShortcutModifiers(cmd: true), display: '⌘V'),
  'duplicate': ShortcutDef(key: 'D', mod: ShortcutModifiers(cmd: true), display: '⌘D'),

  // Timeline
  'split': ShortcutDef(key: 'S', display: 'S'),
  'trim': ShortcutDef(key: 'T', display: 'T'),
  'mute': ShortcutDef(key: 'M', display: 'M'),
  'solo': ShortcutDef(key: 'S', mod: ShortcutModifiers(alt: true), display: '⌥S'),
  'arm': ShortcutDef(key: 'A', mod: ShortcutModifiers(alt: true), display: '⌥A'),

  // Zoom
  'zoomIn': ShortcutDef(key: 'H', display: 'H'),
  'zoomOut': ShortcutDef(key: 'G', display: 'G'),
  'zoomToFit': ShortcutDef(key: '0', mod: ShortcutModifiers(cmd: true), display: '⌘0'),
  'zoomToSelection': ShortcutDef(key: 'Z', display: 'Z'),

  // Loop
  'expandLoopToContent': ShortcutDef(key: 'L', display: 'L'),
  'setLoopFromSelection': ShortcutDef(key: 'L', mod: ShortcutModifiers(shift: true), display: '⇧L'),

  // Navigation
  'goToStart': ShortcutDef(key: 'Home', display: 'Home'),
  'goToEnd': ShortcutDef(key: 'End', display: 'End'),
  'goToLeftLocator': ShortcutDef(key: '1', display: '1'),
  'goToRightLocator': ShortcutDef(key: '2', display: '2'),
  'nudgeLeft': ShortcutDef(key: 'ArrowLeft', display: '←'),
  'nudgeRight': ShortcutDef(key: 'ArrowRight', display: '→'),

  // Toggles
  'toggleSnap': ShortcutDef(key: 'N', display: 'N'),
  'toggleMetronome': ShortcutDef(key: 'C', display: 'C'),
  'toggleMixer': ShortcutDef(key: 'F3', display: 'F3'),
  'toggleInspector': ShortcutDef(key: 'I', display: 'I'),
  'toggleBrowser': ShortcutDef(key: 'B', display: 'B'),

  // Track
  'addTrack': ShortcutDef(key: 'T', mod: ShortcutModifiers(cmd: true), display: '⌘T'),
  'removeTrack': ShortcutDef(key: 'T', mod: ShortcutModifiers(cmd: true, shift: true), display: '⌘⇧T'),

  // Audio
  'bounce': ShortcutDef(key: 'B', mod: ShortcutModifiers(cmd: true), display: '⌘B'),
  'normalize': ShortcutDef(key: 'N', mod: ShortcutModifiers(cmd: true, shift: true), display: '⌘⇧N'),
  'reverse': ShortcutDef(key: 'R', mod: ShortcutModifiers(cmd: true, shift: true), display: '⌘⇧R'),

  // Fades
  'fadeIn': ShortcutDef(key: 'F', display: 'F'),
  'fadeOut': ShortcutDef(key: 'F', mod: ShortcutModifiers(shift: true), display: '⇧F'),
  'crossfade': ShortcutDef(key: 'X', display: 'X'),

  // Misc
  'quantize': ShortcutDef(key: 'Q', display: 'Q'),
  'preferences': ShortcutDef(key: ',', mod: ShortcutModifiers(cmd: true), display: '⌘,'),
  'fullscreen': ShortcutDef(key: 'F11', display: 'F11'),
  'escape': ShortcutDef(key: 'Escape', display: 'Esc'),

  // Advanced panels (Cubase-style Shift+Cmd shortcuts)
  'logicalEditor': ShortcutDef(key: 'L', mod: ShortcutModifiers(cmd: true, shift: true), display: '⇧⌘L'),
  'scaleAssistant': ShortcutDef(key: 'K', mod: ShortcutModifiers(cmd: true, shift: true), display: '⇧⌘K'),
  'grooveQuantize': ShortcutDef(key: 'Q', mod: ShortcutModifiers(cmd: true, shift: true), display: '⇧⌘Q'),
  'audioAlignment': ShortcutDef(key: 'A', mod: ShortcutModifiers(cmd: true, shift: true), display: '⇧⌘A'),
  'trackVersions': ShortcutDef(key: 'V', mod: ShortcutModifiers(cmd: true, shift: true), display: '⇧⌘V'),
  'macroControls': ShortcutDef(key: 'M', mod: ShortcutModifiers(cmd: true, shift: true), display: '⇧⌘M'),
  'clipGainEnvelope': ShortcutDef(key: 'G', mod: ShortcutModifiers(cmd: true, shift: true), display: '⇧⌘G'),
};

// ============ Provider ============

class GlobalShortcutsProvider extends ChangeNotifier {
  ShortcutAction actions = ShortcutAction();
  bool enabled = true;
  // HTML input elements to ignore (for web platform)
  // ignore: unused_field
  final Set<String> _ignoreElements = {'input', 'textarea', 'select'};

  void setActions(ShortcutAction newActions) {
    actions = newActions;
    notifyListeners();
  }

  void setEnabled(bool value) {
    enabled = value;
    notifyListeners();
  }

  /// Handle a key event and dispatch to appropriate action
  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (!enabled) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    final mod = ShortcutModifiers(
      ctrl: HardwareKeyboard.instance.isControlPressed,
      shift: isShift,
      alt: isAlt,
      meta: HardwareKeyboard.instance.isMetaPressed,
      cmd: isCmd,
    );

    // Try custom handler first
    final keyLabel = event.character ?? key.keyLabel;
    if (actions.onCustom?.call(keyLabel.toLowerCase(), mod) == true) {
      return KeyEventResult.handled;
    }

    // Space - Play/Pause
    if (key == LogicalKeyboardKey.space && !isCmd && !isAlt) {
      actions.onPlayPause?.call();
      return KeyEventResult.handled;
    }

    // Cmd+Enter - Stop
    if (key == LogicalKeyboardKey.enter && isCmd) {
      actions.onStop?.call();
      return KeyEventResult.handled;
    }

    // Cmd+S - Save
    if (key == LogicalKeyboardKey.keyS && isCmd && !isShift && !isAlt) {
      actions.onSave?.call();
      return KeyEventResult.handled;
    }

    // Cmd+Z - Undo
    if (key == LogicalKeyboardKey.keyZ && isCmd && !isShift && !isAlt) {
      actions.onUndo?.call();
      return KeyEventResult.handled;
    }

    // Cmd+Shift+Z or Cmd+Y - Redo
    if ((key == LogicalKeyboardKey.keyZ && isCmd && isShift) ||
        (key == LogicalKeyboardKey.keyY && isCmd)) {
      actions.onRedo?.call();
      return KeyEventResult.handled;
    }

    // Delete/Backspace - Delete selected
    if ((key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) &&
        !isCmd) {
      actions.onDelete?.call();
      return KeyEventResult.handled;
    }

    // Escape - Deselect
    if (key == LogicalKeyboardKey.escape) {
      actions.onDeselect?.call();
      return KeyEventResult.handled;
    }

    // Cmd+A - Select all
    if (key == LogicalKeyboardKey.keyA && isCmd && !isShift && !isAlt) {
      actions.onSelectAll?.call();
      return KeyEventResult.handled;
    }

    // Cmd+D - Duplicate
    if (key == LogicalKeyboardKey.keyD && isCmd && !isShift && !isAlt) {
      actions.onDuplicate?.call();
      return KeyEventResult.handled;
    }

    // H - Zoom in (only if callback exists)
    if (key == LogicalKeyboardKey.keyH && !isCmd && !isAlt && !isShift) {
      if (actions.onZoomIn != null) {
        actions.onZoomIn!();
        return KeyEventResult.handled;
      }
    }

    // G - Zoom out (only if callback exists)
    if (key == LogicalKeyboardKey.keyG && !isCmd && !isAlt && !isShift) {
      if (actions.onZoomOut != null) {
        actions.onZoomOut!();
        return KeyEventResult.handled;
      }
    }

    // L - Expand loop to content (only if callback exists)
    if (key == LogicalKeyboardKey.keyL && !isCmd && !isAlt && !isShift) {
      if (actions.onExpandLoopToContent != null) {
        actions.onExpandLoopToContent!();
        return KeyEventResult.handled;
      }
    }

    // Shift+L - Set loop from selection
    if (key == LogicalKeyboardKey.keyL && isShift && !isCmd && !isAlt) {
      if (actions.onSetLoopFromSelection != null) {
        actions.onSetLoopFromSelection!();
        return KeyEventResult.handled;
      }
    }

    // S (without cmd) - Split (only if callback exists)
    if (key == LogicalKeyboardKey.keyS && !isCmd && !isAlt && !isShift) {
      if (actions.onSplit != null) {
        actions.onSplit!();
        return KeyEventResult.handled;
      }
    }

    // M - Mute (only if callback exists)
    if (key == LogicalKeyboardKey.keyM && !isCmd && !isAlt && !isShift) {
      if (actions.onMute != null) {
        actions.onMute!();
        return KeyEventResult.handled;
      }
    }

    // Arrow Left - Nudge left
    if (key == LogicalKeyboardKey.arrowLeft && !isCmd && !isShift) {
      actions.onNudgeLeft?.call();
      return KeyEventResult.handled;
    }

    // Arrow Right - Nudge right
    if (key == LogicalKeyboardKey.arrowRight && !isCmd && !isShift) {
      actions.onNudgeRight?.call();
      return KeyEventResult.handled;
    }

    // Home - Go to start
    if (key == LogicalKeyboardKey.home) {
      actions.onGoToStart?.call();
      return KeyEventResult.handled;
    }

    // End - Go to end
    if (key == LogicalKeyboardKey.end) {
      actions.onGoToEnd?.call();
      return KeyEventResult.handled;
    }

    // N - Toggle snap
    if (key == LogicalKeyboardKey.keyN && !isCmd && !isAlt && !isShift) {
      actions.onToggleSnap?.call();
      return KeyEventResult.handled;
    }

    // I - Toggle inspector
    if (key == LogicalKeyboardKey.keyI && !isCmd && !isAlt && !isShift) {
      actions.onToggleInspector?.call();
      return KeyEventResult.handled;
    }

    // B (without cmd) - Toggle browser
    if (key == LogicalKeyboardKey.keyB && !isCmd && !isAlt && !isShift) {
      actions.onToggleBrowser?.call();
      return KeyEventResult.handled;
    }

    // F - Fade in
    if (key == LogicalKeyboardKey.keyF && !isCmd && !isAlt && !isShift) {
      actions.onFadeIn?.call();
      return KeyEventResult.handled;
    }

    // Shift+F - Fade out
    if (key == LogicalKeyboardKey.keyF && isShift && !isCmd && !isAlt) {
      actions.onFadeOut?.call();
      return KeyEventResult.handled;
    }

    // X (without cmd) - Crossfade
    if (key == LogicalKeyboardKey.keyX && !isCmd && !isAlt && !isShift) {
      actions.onCrossfade?.call();
      return KeyEventResult.handled;
    }

    // Shift+Cmd+I - Import Audio Files
    if (key == LogicalKeyboardKey.keyI && isCmd && isShift && !isAlt) {
      if (actions.onImportAudioFiles != null) {
        actions.onImportAudioFiles!();
        return KeyEventResult.handled;
      }
    }

    // Alt+Cmd+E - Export Audio
    if (key == LogicalKeyboardKey.keyE && isCmd && isAlt && !isShift) {
      if (actions.onExport != null) {
        actions.onExport!();
        return KeyEventResult.handled;
      }
    }

    // ========== Advanced Panel Shortcuts (Shift+Cmd) ==========

    // Shift+Cmd+L - Logical Editor
    if (key == LogicalKeyboardKey.keyL && isCmd && isShift && !isAlt) {
      if (actions.onShowLogicalEditor != null) {
        actions.onShowLogicalEditor!();
        return KeyEventResult.handled;
      }
    }

    // Shift+Cmd+K - Scale Assistant
    if (key == LogicalKeyboardKey.keyK && isCmd && isShift && !isAlt) {
      if (actions.onShowScaleAssistant != null) {
        actions.onShowScaleAssistant!();
        return KeyEventResult.handled;
      }
    }

    // Shift+Cmd+Q - Groove Quantize
    if (key == LogicalKeyboardKey.keyQ && isCmd && isShift && !isAlt) {
      if (actions.onShowGrooveQuantize != null) {
        actions.onShowGrooveQuantize!();
        return KeyEventResult.handled;
      }
    }

    // Shift+Cmd+A - Audio Alignment
    if (key == LogicalKeyboardKey.keyA && isCmd && isShift && !isAlt) {
      if (actions.onShowAudioAlignment != null) {
        actions.onShowAudioAlignment!();
        return KeyEventResult.handled;
      }
    }

    // Shift+Cmd+V - Track Versions
    if (key == LogicalKeyboardKey.keyV && isCmd && isShift && !isAlt) {
      if (actions.onShowTrackVersions != null) {
        actions.onShowTrackVersions!();
        return KeyEventResult.handled;
      }
    }

    // Shift+Cmd+M - Macro Controls
    if (key == LogicalKeyboardKey.keyM && isCmd && isShift && !isAlt) {
      if (actions.onShowMacroControls != null) {
        actions.onShowMacroControls!();
        return KeyEventResult.handled;
      }
    }

    // Shift+Cmd+G - Clip Gain Envelope
    if (key == LogicalKeyboardKey.keyG && isCmd && isShift && !isAlt) {
      if (actions.onShowClipGainEnvelope != null) {
        actions.onShowClipGainEnvelope!();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }
}

/// Format shortcut for display
String formatShortcut(String key, {ShortcutModifiers? mod}) {
  final parts = <String>[];

  if (mod?.cmd == true) parts.add('⌘');
  if (mod?.shift == true) parts.add('⇧');
  if (mod?.alt == true) parts.add('⌥');

  // Format special keys
  String displayKey = key;
  switch (key.toLowerCase()) {
    case ' ':
      displayKey = 'Space';
    case 'arrowup':
      displayKey = '↑';
    case 'arrowdown':
      displayKey = '↓';
    case 'arrowleft':
      displayKey = '←';
    case 'arrowright':
      displayKey = '→';
    case 'escape':
      displayKey = 'Esc';
    case 'backspace':
      displayKey = '⌫';
    case 'delete':
      displayKey = '⌦';
    case 'enter':
      displayKey = '↵';
    default:
      displayKey = key.length == 1 ? key.toUpperCase() : key;
  }

  parts.add(displayKey);
  return parts.join();
}
