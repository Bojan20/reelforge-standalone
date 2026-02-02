/// Keyboard Navigation Service
///
/// Full keyboard navigation support for FluxForge Studio DAW.
/// Manages FocusNode hierarchy, Tab/Arrow navigation, and focus indicators.
///
/// Features:
/// - FocusNode management for all focusable widgets
/// - Tab/Shift+Tab traversal
/// - Arrow key navigation (up/down tracks, left/right params)
/// - Enter to edit, Escape to cancel
/// - Focus indicators (blue outline)
/// - Shortcuts overlay integration

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════
// NAVIGATION CONTEXT
// ═══════════════════════════════════════════════════════════════════════════

/// Defines the navigation context/region
enum NavigationContext {
  /// Timeline track list
  tracks,

  /// Mixer channel strips
  mixer,

  /// Lower zone panels
  lowerZone,

  /// Inspector parameters
  inspector,

  /// Browser/file list
  browser,

  /// Plugin slots
  plugins,

  /// Timeline clips
  clips,

  /// Global (top-level navigation)
  global,
}

/// Navigation direction for arrow keys
enum NavigationDirection {
  up,
  down,
  left,
  right,
}

// ═══════════════════════════════════════════════════════════════════════════
// FOCUSABLE ITEM
// ═══════════════════════════════════════════════════════════════════════════

/// Represents a focusable item in the navigation hierarchy
class FocusableItem {
  /// Unique identifier for this item
  final String id;

  /// The context this item belongs to
  final NavigationContext context;

  /// The FocusNode for this item
  final FocusNode focusNode;

  /// Index within its context (for arrow navigation)
  final int index;

  /// Parent item ID (for hierarchical navigation)
  final String? parentId;

  /// Whether this item is editable (Enter to edit)
  final bool editable;

  /// Callback when item is activated (Enter)
  final VoidCallback? onActivate;

  /// Callback when edit is cancelled (Escape)
  final VoidCallback? onCancel;

  /// Custom data attached to this item
  final dynamic data;

  FocusableItem({
    required this.id,
    required this.context,
    required this.focusNode,
    this.index = 0,
    this.parentId,
    this.editable = false,
    this.onActivate,
    this.onCancel,
    this.data,
  });

  /// Request focus for this item
  void focus() {
    if (focusNode.canRequestFocus) {
      focusNode.requestFocus();
    }
  }

  /// Check if this item has focus
  bool get hasFocus => focusNode.hasFocus;

  @override
  String toString() => 'FocusableItem($id, ctx=$context, idx=$index)';
}

// ═══════════════════════════════════════════════════════════════════════════
// NAVIGATION EVENT
// ═══════════════════════════════════════════════════════════════════════════

/// Event emitted when navigation occurs
class NavigationEvent {
  /// The item being navigated to
  final FocusableItem? target;

  /// The previous focused item
  final FocusableItem? previous;

  /// The navigation direction (if arrow nav)
  final NavigationDirection? direction;

  /// Whether this was Tab navigation
  final bool isTabNavigation;

  /// Timestamp of event
  final DateTime timestamp;

  NavigationEvent({
    this.target,
    this.previous,
    this.direction,
    this.isTabNavigation = false,
  }) : timestamp = DateTime.now();
}

// ═══════════════════════════════════════════════════════════════════════════
// KEYBOARD NAVIGATION SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing keyboard navigation across the application
class KeyboardNavigationService {
  KeyboardNavigationService._();
  static final instance = KeyboardNavigationService._();

  // ═══════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════

  /// All registered focusable items by ID
  final Map<String, FocusableItem> _items = {};

  /// Items grouped by context
  final Map<NavigationContext, List<FocusableItem>> _contextItems = {};

  /// Current navigation context
  NavigationContext _currentContext = NavigationContext.global;

  /// Currently focused item ID
  String? _focusedItemId;

  /// Whether navigation service is enabled
  bool _enabled = true;

  /// Stream controller for navigation events
  final _navigationController = StreamController<NavigationEvent>.broadcast();

  /// Focus indicator color
  Color _focusColor = const Color(0xFF4A9EFF);

  /// Focus indicator width
  double _focusWidth = 2.0;

  // ═══════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Stream of navigation events
  Stream<NavigationEvent> get navigationEvents => _navigationController.stream;

  /// Current navigation context
  NavigationContext get currentContext => _currentContext;

  /// Currently focused item
  FocusableItem? get focusedItem =>
      _focusedItemId != null ? _items[_focusedItemId] : null;

  /// Whether service is enabled
  bool get isEnabled => _enabled;

  /// Focus indicator color
  Color get focusColor => _focusColor;

  /// Focus indicator width
  double get focusWidth => _focusWidth;

  /// Number of registered items
  int get itemCount => _items.length;

  /// Get items in a context
  List<FocusableItem> getItemsInContext(NavigationContext context) {
    return List.unmodifiable(_contextItems[context] ?? []);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Enable or disable navigation
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Set focus indicator color
  void setFocusColor(Color color) {
    _focusColor = color;
  }

  /// Set focus indicator width
  void setFocusWidth(double width) {
    _focusWidth = width;
  }

  /// Set current navigation context
  void setContext(NavigationContext context) {
    _currentContext = context;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Register a focusable item
  FocusableItem register({
    required String id,
    required NavigationContext context,
    FocusNode? focusNode,
    int index = 0,
    String? parentId,
    bool editable = false,
    VoidCallback? onActivate,
    VoidCallback? onCancel,
    dynamic data,
  }) {
    // Create or use provided FocusNode
    final node = focusNode ?? FocusNode(debugLabel: id);

    // Create item
    final item = FocusableItem(
      id: id,
      context: context,
      focusNode: node,
      index: index,
      parentId: parentId,
      editable: editable,
      onActivate: onActivate,
      onCancel: onCancel,
      data: data,
    );

    // Listen for focus changes
    node.addListener(() => _onFocusChanged(item));

    // Register
    _items[id] = item;
    _contextItems.putIfAbsent(context, () => []).add(item);

    // Sort context items by index
    _contextItems[context]!.sort((a, b) => a.index.compareTo(b.index));

    return item;
  }

  /// Unregister a focusable item
  void unregister(String id) {
    final item = _items.remove(id);
    if (item != null) {
      _contextItems[item.context]?.remove(item);
      item.focusNode.dispose();

      if (_focusedItemId == id) {
        _focusedItemId = null;
      }
    }
  }

  /// Unregister all items in a context
  void unregisterContext(NavigationContext context) {
    final items = _contextItems.remove(context) ?? [];
    for (final item in items) {
      _items.remove(item.id);
      item.focusNode.dispose();
    }
  }

  /// Clear all registrations
  void clear() {
    for (final item in _items.values) {
      item.focusNode.dispose();
    }
    _items.clear();
    _contextItems.clear();
    _focusedItemId = null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // NAVIGATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Focus an item by ID
  bool focusItem(String id) {
    final item = _items[id];
    if (item == null) return false;

    item.focus();
    return true;
  }

  /// Navigate in a direction within current context
  bool navigate(NavigationDirection direction) {
    if (!_enabled) return false;

    final items = _contextItems[_currentContext] ?? [];
    if (items.isEmpty) return false;

    final currentIndex = _getCurrentIndexInContext();

    int nextIndex;
    switch (direction) {
      case NavigationDirection.up:
      case NavigationDirection.left:
        nextIndex = currentIndex > 0 ? currentIndex - 1 : items.length - 1;
        break;
      case NavigationDirection.down:
      case NavigationDirection.right:
        nextIndex = currentIndex < items.length - 1 ? currentIndex + 1 : 0;
        break;
    }

    final target = items[nextIndex];
    final previous = focusedItem;

    target.focus();

    _navigationController.add(NavigationEvent(
      target: target,
      previous: previous,
      direction: direction,
    ));

    return true;
  }

  /// Navigate to next item (Tab)
  bool navigateNext() {
    if (!_enabled) return false;

    final allItems = _items.values.toList();
    if (allItems.isEmpty) return false;

    final currentIndex =
        _focusedItemId != null ? allItems.indexWhere((i) => i.id == _focusedItemId) : -1;

    final nextIndex = (currentIndex + 1) % allItems.length;
    final target = allItems[nextIndex];
    final previous = focusedItem;

    target.focus();

    _navigationController.add(NavigationEvent(
      target: target,
      previous: previous,
      isTabNavigation: true,
    ));

    return true;
  }

  /// Navigate to previous item (Shift+Tab)
  bool navigatePrevious() {
    if (!_enabled) return false;

    final allItems = _items.values.toList();
    if (allItems.isEmpty) return false;

    final currentIndex =
        _focusedItemId != null ? allItems.indexWhere((i) => i.id == _focusedItemId) : 0;

    final prevIndex = currentIndex > 0 ? currentIndex - 1 : allItems.length - 1;
    final target = allItems[prevIndex];
    final previous = focusedItem;

    target.focus();

    _navigationController.add(NavigationEvent(
      target: target,
      previous: previous,
      isTabNavigation: true,
    ));

    return true;
  }

  /// Activate current item (Enter)
  bool activateCurrent() {
    final item = focusedItem;
    if (item?.onActivate != null) {
      item!.onActivate!();
      return true;
    }
    return false;
  }

  /// Cancel current operation (Escape)
  bool cancelCurrent() {
    final item = focusedItem;
    if (item?.onCancel != null) {
      item!.onCancel!();
      return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // KEY HANDLING
  // ═══════════════════════════════════════════════════════════════════════

  /// Handle a key event
  /// Returns true if the event was handled
  bool handleKeyEvent(KeyEvent event) {
    if (!_enabled) return false;
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // Tab navigation
    if (key == LogicalKeyboardKey.tab) {
      return shift ? navigatePrevious() : navigateNext();
    }

    // Arrow navigation
    if (key == LogicalKeyboardKey.arrowUp) {
      return navigate(NavigationDirection.up);
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return navigate(NavigationDirection.down);
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return navigate(NavigationDirection.left);
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return navigate(NavigationDirection.right);
    }

    // Enter to activate
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      return activateCurrent();
    }

    // Escape to cancel
    if (key == LogicalKeyboardKey.escape) {
      return cancelCurrent();
    }

    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  void _onFocusChanged(FocusableItem item) {
    if (item.hasFocus) {
      _focusedItemId = item.id;
      _currentContext = item.context;
    }
  }

  int _getCurrentIndexInContext() {
    final items = _contextItems[_currentContext] ?? [];
    if (_focusedItemId == null) return 0;

    final index = items.indexWhere((i) => i.id == _focusedItemId);
    return index >= 0 ? index : 0;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DISPOSAL
  // ═══════════════════════════════════════════════════════════════════════

  /// Dispose the service
  void dispose() {
    clear();
    _navigationController.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FOCUS INDICATOR WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Widget that shows a focus indicator around its child
class FocusIndicator extends StatefulWidget {
  final Widget child;
  final String itemId;
  final NavigationContext context;
  final int index;
  final bool editable;
  final VoidCallback? onActivate;
  final VoidCallback? onCancel;
  final dynamic data;

  /// Border radius for the focus indicator
  final BorderRadius? borderRadius;

  /// Custom focus color (overrides service default)
  final Color? focusColor;

  /// Custom focus width (overrides service default)
  final double? focusWidth;

  const FocusIndicator({
    super.key,
    required this.child,
    required this.itemId,
    required this.context,
    this.index = 0,
    this.editable = false,
    this.onActivate,
    this.onCancel,
    this.data,
    this.borderRadius,
    this.focusColor,
    this.focusWidth,
  });

  @override
  State<FocusIndicator> createState() => _FocusIndicatorState();
}

class _FocusIndicatorState extends State<FocusIndicator> {
  FocusableItem? _item;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _registerItem();
  }

  @override
  void didUpdateWidget(FocusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId) {
      _unregisterItem();
      _registerItem();
    }
  }

  @override
  void dispose() {
    _unregisterItem();
    super.dispose();
  }

  void _registerItem() {
    _item = KeyboardNavigationService.instance.register(
      id: widget.itemId,
      context: widget.context,
      index: widget.index,
      editable: widget.editable,
      onActivate: widget.onActivate,
      onCancel: widget.onCancel,
      data: widget.data,
    );
    _item!.focusNode.addListener(_onFocusChange);
  }

  void _unregisterItem() {
    if (_item != null) {
      _item!.focusNode.removeListener(_onFocusChange);
      KeyboardNavigationService.instance.unregister(widget.itemId);
      _item = null;
    }
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _hasFocus = _item?.hasFocus ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = KeyboardNavigationService.instance;
    final color = widget.focusColor ?? service.focusColor;
    final width = widget.focusWidth ?? service.focusWidth;
    final radius = widget.borderRadius ?? BorderRadius.circular(4);

    return Focus(
      focusNode: _item?.focusNode,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: _hasFocus
              ? Border.all(color: color, width: width)
              : Border.all(color: Colors.transparent, width: width),
          boxShadow: _hasFocus
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// KEYBOARD NAVIGATION WRAPPER
// ═══════════════════════════════════════════════════════════════════════════

/// Wrapper widget that enables keyboard navigation for its subtree
class KeyboardNavigationWrapper extends StatelessWidget {
  final Widget child;

  /// Whether to handle key events
  final bool enabled;

  const KeyboardNavigationWrapper({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        KeyboardNavigationService.instance.handleKeyEvent(event);
      },
      child: child,
    );
  }
}
