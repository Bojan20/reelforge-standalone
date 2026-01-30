/// Keyboard Navigation Service
///
/// Comprehensive keyboard navigation system for SlotLab:
/// - Arrow key navigation between UI elements
/// - Tab order management
/// - Quick action shortcuts
/// - Focus trap management for dialogs/panels
/// - Navigation zones (timeline, events, mixer)
///
/// Created: 2026-01-30 (P4.22)

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════
// NAVIGATION ZONE TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Navigation zones in the UI
enum NavZone {
  /// Slot preview / reels area
  slotPreview,

  /// Events panel (left/right side)
  eventsPanel,

  /// Lower zone tabs and content
  lowerZone,

  /// Audio browser / pool
  audioBrowser,

  /// Mixer channels
  mixer,

  /// Timeline tracks
  timeline,

  /// Dialog overlay
  dialog,

  /// Menu
  menu,

  /// Global (no specific zone)
  global,
}

extension NavZoneExtension on NavZone {
  String get displayName {
    switch (this) {
      case NavZone.slotPreview:
        return 'Slot Preview';
      case NavZone.eventsPanel:
        return 'Events';
      case NavZone.lowerZone:
        return 'Lower Zone';
      case NavZone.audioBrowser:
        return 'Audio Browser';
      case NavZone.mixer:
        return 'Mixer';
      case NavZone.timeline:
        return 'Timeline';
      case NavZone.dialog:
        return 'Dialog';
      case NavZone.menu:
        return 'Menu';
      case NavZone.global:
        return 'Global';
    }
  }
}

/// Navigation direction
enum NavDirection {
  up,
  down,
  left,
  right,
  next,
  previous,
}

// ═══════════════════════════════════════════════════════════════════════════
// KEYBOARD SHORTCUT MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Keyboard shortcut definition
class KeyboardShortcut {
  final String id;
  final String label;
  final String description;
  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;
  final NavZone? zone; // Null = global shortcut
  final VoidCallback? action;

  const KeyboardShortcut({
    required this.id,
    required this.label,
    required this.key,
    this.description = '',
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
    this.zone,
    this.action,
  });

  /// Check if this shortcut matches the given key event
  bool matches(KeyEvent event) {
    if (event.logicalKey != key) return false;

    final keyboard = HardwareKeyboard.instance;
    if (ctrl && !keyboard.isControlPressed) return false;
    if (shift && !keyboard.isShiftPressed) return false;
    if (alt && !keyboard.isAltPressed) return false;
    if (meta && !keyboard.isMetaPressed) return false;

    // Also check that no extra modifiers are pressed
    if (!ctrl && keyboard.isControlPressed) return false;
    if (!shift && keyboard.isShiftPressed) return false;
    if (!alt && keyboard.isAltPressed) return false;
    if (!meta && keyboard.isMetaPressed) return false;

    return true;
  }

  /// Get human-readable shortcut string
  String get shortcutString {
    final parts = <String>[];
    if (ctrl) parts.add('Ctrl');
    if (shift) parts.add('Shift');
    if (alt) parts.add('Alt');
    if (meta) parts.add('Cmd');
    parts.add(_keyLabel(key));
    return parts.join('+');
  }

  String _keyLabel(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    if (label.isNotEmpty) return label;

    // Handle special keys
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.arrowUp) return '↑';
    if (key == LogicalKeyboardKey.arrowDown) return '↓';
    if (key == LogicalKeyboardKey.arrowLeft) return '←';
    if (key == LogicalKeyboardKey.arrowRight) return '→';
    if (key == LogicalKeyboardKey.delete) return 'Del';
    if (key == LogicalKeyboardKey.backspace) return 'Backspace';
    if (key == LogicalKeyboardKey.home) return 'Home';
    if (key == LogicalKeyboardKey.end) return 'End';
    if (key == LogicalKeyboardKey.pageUp) return 'PgUp';
    if (key == LogicalKeyboardKey.pageDown) return 'PgDn';

    return key.debugName ?? '?';
  }

  KeyboardShortcut copyWith({
    String? id,
    String? label,
    String? description,
    LogicalKeyboardKey? key,
    bool? ctrl,
    bool? shift,
    bool? alt,
    bool? meta,
    NavZone? zone,
    VoidCallback? action,
  }) {
    return KeyboardShortcut(
      id: id ?? this.id,
      label: label ?? this.label,
      description: description ?? this.description,
      key: key ?? this.key,
      ctrl: ctrl ?? this.ctrl,
      shift: shift ?? this.shift,
      alt: alt ?? this.alt,
      meta: meta ?? this.meta,
      zone: zone ?? this.zone,
      action: action ?? this.action,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// KEYBOARD NAVIGATION SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing keyboard navigation
class KeyboardNavService extends ChangeNotifier {
  KeyboardNavService._();
  static final instance = KeyboardNavService._();

  // State
  NavZone _currentZone = NavZone.global;
  final List<NavZone> _zoneStack = [];
  final Map<String, KeyboardShortcut> _shortcuts = {};
  final List<KeyboardShortcut> _builtInShortcuts = [];
  bool _focusTrapEnabled = false;
  bool _initialized = false;

  // Callbacks
  void Function(NavDirection direction)? onNavigate;
  void Function(NavZone zone)? onZoneChanged;

  // Getters
  NavZone get currentZone => _currentZone;
  bool get focusTrapEnabled => _focusTrapEnabled;
  bool get initialized => _initialized;
  List<KeyboardShortcut> get allShortcuts => [
        ..._builtInShortcuts,
        ..._shortcuts.values,
      ];

  /// Initialize the service
  void init() {
    if (_initialized) return;

    _registerBuiltInShortcuts();
    _initialized = true;
    debugPrint('[KeyboardNavService] Initialized');
  }

  void _registerBuiltInShortcuts() {
    _builtInShortcuts.addAll([
      // Navigation
      const KeyboardShortcut(
        id: 'nav.up',
        label: 'Navigate Up',
        key: LogicalKeyboardKey.arrowUp,
        description: 'Move focus up',
      ),
      const KeyboardShortcut(
        id: 'nav.down',
        label: 'Navigate Down',
        key: LogicalKeyboardKey.arrowDown,
        description: 'Move focus down',
      ),
      const KeyboardShortcut(
        id: 'nav.left',
        label: 'Navigate Left',
        key: LogicalKeyboardKey.arrowLeft,
        description: 'Move focus left',
      ),
      const KeyboardShortcut(
        id: 'nav.right',
        label: 'Navigate Right',
        key: LogicalKeyboardKey.arrowRight,
        description: 'Move focus right',
      ),

      // Zone switching
      KeyboardShortcut(
        id: 'zone.events',
        label: 'Focus Events',
        key: LogicalKeyboardKey.digit1,
        ctrl: true,
        description: 'Focus events panel',
      ),
      KeyboardShortcut(
        id: 'zone.slot',
        label: 'Focus Slot Preview',
        key: LogicalKeyboardKey.digit2,
        ctrl: true,
        description: 'Focus slot preview area',
      ),
      KeyboardShortcut(
        id: 'zone.lower',
        label: 'Focus Lower Zone',
        key: LogicalKeyboardKey.digit3,
        ctrl: true,
        description: 'Focus lower zone',
      ),
      KeyboardShortcut(
        id: 'zone.browser',
        label: 'Focus Audio Browser',
        key: LogicalKeyboardKey.digit4,
        ctrl: true,
        description: 'Focus audio browser',
      ),

      // Actions
      const KeyboardShortcut(
        id: 'action.play',
        label: 'Play/Pause',
        key: LogicalKeyboardKey.space,
        description: 'Toggle playback',
      ),
      KeyboardShortcut(
        id: 'action.spin',
        label: 'Spin',
        key: LogicalKeyboardKey.enter,
        description: 'Trigger spin',
        zone: NavZone.slotPreview,
      ),
      KeyboardShortcut(
        id: 'action.delete',
        label: 'Delete',
        key: LogicalKeyboardKey.delete,
        description: 'Delete selected item',
      ),
      KeyboardShortcut(
        id: 'action.duplicate',
        label: 'Duplicate',
        key: LogicalKeyboardKey.keyD,
        ctrl: true,
        description: 'Duplicate selected item',
      ),
      KeyboardShortcut(
        id: 'action.selectAll',
        label: 'Select All',
        key: LogicalKeyboardKey.keyA,
        ctrl: true,
        description: 'Select all items',
      ),
      KeyboardShortcut(
        id: 'action.escape',
        label: 'Cancel/Close',
        key: LogicalKeyboardKey.escape,
        description: 'Cancel current action or close dialog',
      ),
    ]);
  }

  /// Handle key event
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }

    // Check for navigation keys
    if (_handleNavigationKey(event)) {
      return true;
    }

    // Check shortcuts (zone-specific first, then global)
    final zoneShortcuts = allShortcuts
        .where((s) => s.zone == _currentZone)
        .toList();
    final globalShortcuts = allShortcuts
        .where((s) => s.zone == null)
        .toList();

    for (final shortcut in [...zoneShortcuts, ...globalShortcuts]) {
      if (shortcut.matches(event)) {
        debugPrint('[KeyboardNavService] Triggered: ${shortcut.id}');
        shortcut.action?.call();
        return true;
      }
    }

    return false;
  }

  bool _handleNavigationKey(KeyEvent event) {
    NavDirection? direction;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        direction = NavDirection.up;
        break;
      case LogicalKeyboardKey.arrowDown:
        direction = NavDirection.down;
        break;
      case LogicalKeyboardKey.arrowLeft:
        direction = NavDirection.left;
        break;
      case LogicalKeyboardKey.arrowRight:
        direction = NavDirection.right;
        break;
      case LogicalKeyboardKey.tab:
        direction = HardwareKeyboard.instance.isShiftPressed
            ? NavDirection.previous
            : NavDirection.next;
        break;
      default:
        return false;
    }

    onNavigate?.call(direction);
    return true;
  }

  /// Set current navigation zone
  void setZone(NavZone zone) {
    if (_currentZone == zone) return;
    _currentZone = zone;
    onZoneChanged?.call(zone);
    notifyListeners();
    debugPrint('[KeyboardNavService] Zone: $zone');
  }

  /// Push zone onto stack (for dialogs/overlays)
  void pushZone(NavZone zone) {
    _zoneStack.add(_currentZone);
    setZone(zone);
  }

  /// Pop zone from stack
  void popZone() {
    if (_zoneStack.isEmpty) return;
    final previousZone = _zoneStack.removeLast();
    setZone(previousZone);
  }

  /// Enable focus trap (prevent tabbing outside current zone)
  void enableFocusTrap() {
    _focusTrapEnabled = true;
    notifyListeners();
  }

  /// Disable focus trap
  void disableFocusTrap() {
    _focusTrapEnabled = false;
    notifyListeners();
  }

  /// Register a custom shortcut
  void registerShortcut(KeyboardShortcut shortcut) {
    _shortcuts[shortcut.id] = shortcut;
    notifyListeners();
    debugPrint('[KeyboardNavService] Registered: ${shortcut.id}');
  }

  /// Unregister a custom shortcut
  void unregisterShortcut(String id) {
    _shortcuts.remove(id);
    notifyListeners();
  }

  /// Get shortcut by ID
  KeyboardShortcut? getShortcut(String id) {
    return _shortcuts[id] ??
        _builtInShortcuts.where((s) => s.id == id).firstOrNull;
  }

  /// Get all shortcuts for a zone
  List<KeyboardShortcut> getShortcutsForZone(NavZone zone) {
    return allShortcuts.where((s) => s.zone == zone || s.zone == null).toList();
  }

  /// Get shortcuts grouped by category
  Map<String, List<KeyboardShortcut>> getGroupedShortcuts() {
    final groups = <String, List<KeyboardShortcut>>{};

    for (final shortcut in allShortcuts) {
      final category = shortcut.id.split('.').first;
      final categoryName = _categoryDisplayName(category);
      groups.putIfAbsent(categoryName, () => []).add(shortcut);
    }

    return groups;
  }

  String _categoryDisplayName(String category) {
    switch (category) {
      case 'nav':
        return 'Navigation';
      case 'zone':
        return 'Zone Switching';
      case 'action':
        return 'Actions';
      default:
        return category.substring(0, 1).toUpperCase() + category.substring(1);
    }
  }
}
