/// FluxForge Search Field
///
/// Reusable search field with proper text input handling:
/// - Smooth typing without UI lag
/// - Instant visual feedback
/// - Optional debouncing for expensive operations
/// - Double-click to select all text
/// - Click between letters to position cursor
/// - Clear button
/// - Consistent styling across the app

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Configuration for FluxForgeSearchField styling
class FluxForgeSearchFieldStyle {
  final Color backgroundColor;
  final Color textColor;
  final Color hintColor;
  final Color iconColor;
  final Color borderColor;
  final Color focusBorderColor;
  final double fontSize;
  final double iconSize;
  final double height;
  final BorderRadius borderRadius;
  final EdgeInsets contentPadding;

  const FluxForgeSearchFieldStyle({
    this.backgroundColor = const Color(0xFF0a0a0c),
    this.textColor = Colors.white,
    this.hintColor = const Color(0x4DFFFFFF),
    this.iconColor = const Color(0x80FFFFFF),
    this.borderColor = const Color(0xFF1a1a20),
    this.focusBorderColor = const Color(0xFF4a9eff),
    this.fontSize = 12,
    this.iconSize = 16,
    this.height = 28,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 8),
  });

  /// Dark theme preset (default)
  static const dark = FluxForgeSearchFieldStyle();

  /// Compact style for tight spaces
  static const compact = FluxForgeSearchFieldStyle(
    fontSize: 11,
    iconSize: 14,
    height: 24,
    contentPadding: EdgeInsets.symmetric(horizontal: 6),
  );

  /// Lower zone style
  static const lowerZone = FluxForgeSearchFieldStyle(
    fontSize: 11,
    iconSize: 14,
    height: 26,
    backgroundColor: Color(0xFF0a0a0c),
    borderColor: Color(0xFF2a2a30),
  );
}

/// A search field optimized for smooth typing and instant results.
///
/// Features:
/// - No UI lag during typing
/// - Optional debouncing for expensive filter operations
/// - Proper cursor positioning (click between letters)
/// - Double-click to select all
/// - Clear button when text is present
/// - Keyboard shortcuts (Escape to clear, Enter to submit)
class FluxForgeSearchField extends StatefulWidget {
  /// Hint text shown when field is empty
  final String hintText;

  /// Called immediately on every character change (for local filtering)
  final ValueChanged<String>? onChanged;

  /// Called after debounce period (for expensive operations like API calls)
  /// If null, onChanged is called immediately without debouncing
  final ValueChanged<String>? onDebouncedChanged;

  /// Called when user presses Enter
  final ValueChanged<String>? onSubmitted;

  /// Called when field is cleared (X button or Escape)
  final VoidCallback? onCleared;

  /// Debounce duration in milliseconds (default: 150ms)
  final int debounceMs;

  /// External controller (optional - creates internal one if not provided)
  final TextEditingController? controller;

  /// External focus node (optional)
  final FocusNode? focusNode;

  /// Whether to autofocus when widget is built
  final bool autofocus;

  /// Whether to show the search icon
  final bool showSearchIcon;

  /// Whether to show clear button when text is present
  final bool showClearButton;

  /// Style configuration
  final FluxForgeSearchFieldStyle style;

  /// Prefix widget (replaces search icon if provided)
  final Widget? prefix;

  /// Suffix widget (shown before clear button)
  final Widget? suffix;

  /// Whether the field is enabled
  final bool enabled;

  /// Text input action (default: search)
  final TextInputAction textInputAction;

  const FluxForgeSearchField({
    super.key,
    this.hintText = 'Search...',
    this.onChanged,
    this.onDebouncedChanged,
    this.onSubmitted,
    this.onCleared,
    this.debounceMs = 150,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.showSearchIcon = true,
    this.showClearButton = true,
    this.style = FluxForgeSearchFieldStyle.dark,
    this.prefix,
    this.suffix,
    this.enabled = true,
    this.textInputAction = TextInputAction.search,
  });

  @override
  State<FluxForgeSearchField> createState() => _FluxForgeSearchFieldState();
}

class _FluxForgeSearchFieldState extends State<FluxForgeSearchField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  Timer? _debounceTimer;
  bool _isNotEmpty = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    _isNotEmpty = _controller.text.isNotEmpty;

    // Listen for text changes
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(FluxForgeSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      if (oldWidget.controller == null) {
        _controller.removeListener(_onTextChanged);
        _controller.dispose();
      }
      _controller = widget.controller ?? TextEditingController();
      _controller.addListener(_onTextChanged);
      _isNotEmpty = _controller.text.isNotEmpty;
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (oldWidget.focusNode == null) {
        _focusNode.removeListener(_onFocusChanged);
        _focusNode.dispose();
      }
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _focusNode.removeListener(_onFocusChanged);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() => _isFocused = _focusNode.hasFocus);
    }
  }

  void _onTextChanged() {
    final text = _controller.text;
    final wasNotEmpty = _isNotEmpty;
    _isNotEmpty = text.isNotEmpty;

    // Update clear button visibility without full rebuild
    if (wasNotEmpty != _isNotEmpty && mounted) {
      setState(() {});
    }

    // Call immediate callback
    widget.onChanged?.call(text);

    // Handle debounced callback
    if (widget.onDebouncedChanged != null) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(
        Duration(milliseconds: widget.debounceMs),
        () {
          if (mounted) {
            widget.onDebouncedChanged?.call(text);
          }
        },
      );
    }
  }

  void _clear() {
    _controller.clear();
    _focusNode.requestFocus();
    widget.onCleared?.call();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_controller.text.isNotEmpty) {
          _clear();
        } else {
          _focusNode.unfocus();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;

    return KeyboardListener(
      focusNode: FocusNode(skipTraversal: true),
      onKeyEvent: _handleKeyEvent,
      child: Container(
        height: style.height,
        decoration: BoxDecoration(
          color: style.backgroundColor,
          borderRadius: style.borderRadius,
          border: Border.all(
            color: _isFocused ? style.focusBorderColor : style.borderColor,
            width: _isFocused ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Prefix / Search icon
            if (widget.prefix != null) ...[
              SizedBox(width: style.contentPadding.left),
              widget.prefix!,
              const SizedBox(width: 6),
            ] else if (widget.showSearchIcon) ...[
              SizedBox(width: style.contentPadding.left),
              Icon(
                Icons.search,
                size: style.iconSize,
                color: style.iconColor,
              ),
              const SizedBox(width: 6),
            ] else ...[
              SizedBox(width: style.contentPadding.left),
            ],

            // Text field - the core input
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                autofocus: widget.autofocus,
                textInputAction: widget.textInputAction,
                style: TextStyle(
                  fontSize: style.fontSize,
                  color: style.textColor,
                  // Ensure proper cursor rendering
                  height: 1.2,
                ),
                // Critical: Minimal decoration for smooth input
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(
                    fontSize: style.fontSize,
                    color: style.hintColor,
                  ),
                  // No borders - container handles that
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  // Dense layout
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  // Disable counter and other decorations
                  counterText: '',
                ),
                // Enable proper text selection behaviors
                enableInteractiveSelection: true,
                // Allow standard text editing shortcuts
                enableSuggestions: false,
                autocorrect: false,
                // Submit on Enter
                onSubmitted: widget.onSubmitted,
                // Cursor styling
                cursorColor: style.focusBorderColor,
                cursorWidth: 1.5,
              ),
            ),

            // Suffix widget
            if (widget.suffix != null) ...[
              const SizedBox(width: 4),
              widget.suffix!,
            ],

            // Clear button
            if (widget.showClearButton && _isNotEmpty) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _clear,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    size: style.iconSize - 2,
                    color: style.iconColor,
                  ),
                ),
              ),
            ],

            SizedBox(width: style.contentPadding.right),
          ],
        ),
      ),
    );
  }
}

/// Simplified search field that just stores the query locally
/// and calls onChanged for every keystroke (no debouncing).
///
/// Use this for small lists (< 100 items) where filtering is instant.
class SimpleSearchField extends StatelessWidget {
  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final FluxForgeSearchFieldStyle style;

  const SimpleSearchField({
    super.key,
    this.hintText = 'Search...',
    required this.onChanged,
    this.controller,
    this.style = FluxForgeSearchFieldStyle.dark,
  });

  @override
  Widget build(BuildContext context) {
    return FluxForgeSearchField(
      hintText: hintText,
      onChanged: onChanged,
      controller: controller,
      style: style,
    );
  }
}

/// Search field with debouncing for expensive operations.
///
/// Use this for large lists (100+ items) or API calls.
class DebouncedSearchField extends StatelessWidget {
  final String hintText;
  final ValueChanged<String> onSearch;
  final int debounceMs;
  final TextEditingController? controller;
  final FluxForgeSearchFieldStyle style;

  const DebouncedSearchField({
    super.key,
    this.hintText = 'Search...',
    required this.onSearch,
    this.debounceMs = 200,
    this.controller,
    this.style = FluxForgeSearchFieldStyle.dark,
  });

  @override
  Widget build(BuildContext context) {
    return FluxForgeSearchField(
      hintText: hintText,
      onDebouncedChanged: onSearch,
      debounceMs: debounceMs,
      controller: controller,
      style: style,
    );
  }
}
