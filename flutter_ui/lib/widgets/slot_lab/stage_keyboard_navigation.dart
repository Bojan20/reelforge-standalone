// ═══════════════════════════════════════════════════════════════════════════
// P3.8: STAGE KEYBOARD NAVIGATION — Keyboard controls for stage lists
// ═══════════════════════════════════════════════════════════════════════════
//
// Provides keyboard navigation for stage-related widgets:
// - Arrow Up/Down: Previous/Next stage
// - Home/End: First/Last stage
// - Page Up/Down: Jump by 10 stages
// - Enter/Space: Select stage
// - Escape: Clear selection
//
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../src/rust/native_ffi.dart';

/// P3.8: Callback for stage navigation events
typedef OnStageNavigate = void Function(int index);
typedef OnStageSelect = void Function(SlotLabStageEvent stage);

/// P3.8: Keyboard navigation controller for stage lists
class StageNavigationController extends ChangeNotifier {
  final List<SlotLabStageEvent> stages;
  int _selectedIndex = -1;
  final int pageSize;

  StageNavigationController({
    required this.stages,
    this.pageSize = 10,
  });

  int get selectedIndex => _selectedIndex;
  bool get hasSelection => _selectedIndex >= 0 && _selectedIndex < stages.length;
  SlotLabStageEvent? get selectedStage =>
      hasSelection ? stages[_selectedIndex] : null;

  void selectIndex(int index) {
    if (index >= 0 && index < stages.length && index != _selectedIndex) {
      _selectedIndex = index;
      notifyListeners();
    }
  }

  void selectFirst() {
    if (stages.isNotEmpty) {
      selectIndex(0);
    }
  }

  void selectLast() {
    if (stages.isNotEmpty) {
      selectIndex(stages.length - 1);
    }
  }

  void selectPrevious() {
    if (_selectedIndex > 0) {
      selectIndex(_selectedIndex - 1);
    } else if (_selectedIndex == -1 && stages.isNotEmpty) {
      selectIndex(stages.length - 1);
    }
  }

  void selectNext() {
    if (_selectedIndex < stages.length - 1) {
      selectIndex(_selectedIndex + 1);
    } else if (_selectedIndex == -1 && stages.isNotEmpty) {
      selectIndex(0);
    }
  }

  void pageUp() {
    final newIndex = (_selectedIndex - pageSize).clamp(0, stages.length - 1);
    if (stages.isNotEmpty) {
      selectIndex(newIndex);
    }
  }

  void pageDown() {
    final newIndex = (_selectedIndex + pageSize).clamp(0, stages.length - 1);
    if (stages.isNotEmpty) {
      selectIndex(newIndex);
    }
  }

  void clearSelection() {
    if (_selectedIndex != -1) {
      _selectedIndex = -1;
      notifyListeners();
    }
  }

  /// Update stages list (resets selection if list changed)
  void updateStages(List<SlotLabStageEvent> newStages) {
    if (stages.length != newStages.length) {
      _selectedIndex = -1;
    } else if (_selectedIndex >= newStages.length) {
      _selectedIndex = newStages.isNotEmpty ? newStages.length - 1 : -1;
    }
  }
}

/// P3.8: Keyboard navigation wrapper widget
class StageKeyboardNavigator extends StatefulWidget {
  final List<SlotLabStageEvent> stages;
  final OnStageSelect? onStageSelect;
  final OnStageNavigate? onNavigate;
  final Widget Function(BuildContext context, StageNavigationController controller) builder;
  final bool autofocus;

  const StageKeyboardNavigator({
    super.key,
    required this.stages,
    required this.builder,
    this.onStageSelect,
    this.onNavigate,
    this.autofocus = false,
  });

  @override
  State<StageKeyboardNavigator> createState() => _StageKeyboardNavigatorState();
}

class _StageKeyboardNavigatorState extends State<StageKeyboardNavigator> {
  late StageNavigationController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = StageNavigationController(stages: widget.stages);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(StageKeyboardNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stages != oldWidget.stages) {
      _controller.updateStages(widget.stages);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    widget.onNavigate?.call(_controller.selectedIndex);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // Arrow navigation
    if (key == LogicalKeyboardKey.arrowUp) {
      _controller.selectPrevious();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _controller.selectNext();
      return KeyEventResult.handled;
    }

    // Home/End
    if (key == LogicalKeyboardKey.home) {
      _controller.selectFirst();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _controller.selectLast();
      return KeyEventResult.handled;
    }

    // Page Up/Down
    if (key == LogicalKeyboardKey.pageUp) {
      _controller.pageUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _controller.pageDown();
      return KeyEventResult.handled;
    }

    // Enter/Space to select
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      if (_controller.hasSelection) {
        widget.onStageSelect?.call(_controller.selectedStage!);
        return KeyEventResult.handled;
      }
    }

    // Escape to clear
    if (key == LogicalKeyboardKey.escape) {
      _controller.clearSelection();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Stage list navigation. Use arrow keys to navigate, '
          'Enter to select, Escape to clear selection.',
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => widget.builder(context, _controller),
          ),
        ),
      ),
    );
  }
}

/// P3.8: Simple navigable stage list item
class NavigableStageItem extends StatelessWidget {
  final SlotLabStageEvent stage;
  final bool isSelected;
  final VoidCallback? onTap;
  final Color? stageColor;

  const NavigableStageItem({
    super.key,
    required this.stage,
    this.isSelected = false,
    this.onTap,
    this.stageColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = stageColor ?? const Color(0xFF4A9EFF);

    return Semantics(
      label: 'Stage ${stage.stageType} at ${stage.timestampMs.toStringAsFixed(0)} milliseconds'
          '${isSelected ? ', selected' : ''}',
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: isSelected
                ? Border.all(color: color.withValues(alpha: 0.5))
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  stage.stageType,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${stage.timestampMs.toStringAsFixed(0)}ms',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// P3.8: Keyboard shortcuts help tooltip
class StageNavigationHelp extends StatelessWidget {
  const StageNavigationHelp({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      richMessage: const TextSpan(
        children: [
          TextSpan(
            text: 'Keyboard Shortcuts\n',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: '↑/↓  Previous/Next\n'),
          TextSpan(text: 'Home  First stage\n'),
          TextSpan(text: 'End   Last stage\n'),
          TextSpan(text: 'PgUp/PgDn  Jump 10\n'),
          TextSpan(text: 'Enter  Select\n'),
          TextSpan(text: 'Esc   Clear'),
        ],
      ),
      child: const Icon(
        Icons.keyboard,
        color: Colors.white38,
        size: 16,
      ),
    );
  }
}
