// Panel Focus Provider — SPEC-14
//
// Tracks which major UI panel currently has keyboard focus.
// Renders a 1px brandGold border around the active panel,
// giving the user a clear visual affordance for where shortcuts land.
//
// Usage:
//   FocusablePanel(id: FocusPanelId.helixCanvas, child: ...)
//   GetIt.instance<PanelFocusProvider>().focus(FocusPanelId.helixDock)

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PANEL IDs
// ═══════════════════════════════════════════════════════════════════════════

/// Identifies each major focusable panel in the application.
enum FocusPanelId {
  // HELIX panels
  helixCanvas,
  helixDock,
  helixSpine,

  // DAW panels
  dawTimeline,
  dawLowerZone,

  // SlotLab panels
  slotLabCanvas,
  slotLabLowerZone,
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

/// Manages which panel currently has keyboard focus.
/// Lightweight ChangeNotifier — no FFI, no audio thread contact.
class PanelFocusProvider extends ChangeNotifier {
  FocusPanelId? _focused;

  /// Currently focused panel. `null` = no panel focused.
  FocusPanelId? get focused => _focused;

  /// Returns true if [panel] is the currently focused panel.
  bool isFocused(FocusPanelId panel) => _focused == panel;

  /// Focus a panel. If already focused → no-op (avoids spurious rebuilds).
  void focus(FocusPanelId panel) {
    if (_focused == panel) return;
    _focused = panel;
    notifyListeners();
  }

  /// Clear focus.
  void blur() {
    if (_focused == null) return;
    _focused = null;
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET: FocusablePanel
// ═══════════════════════════════════════════════════════════════════════════

/// Wraps a panel widget. On tap → registers focus with [PanelFocusProvider].
/// When focused → renders a 1px brandGold (#C8A96E) border overlay.
///
/// The border is rendered as a DecoratedBox overlay so it doesn't affect layout.
class FocusablePanel extends StatelessWidget {
  final FocusPanelId id;
  final Widget child;
  final bool enabled;

  const FocusablePanel({
    super.key,
    required this.id,
    required this.child,
    this.enabled = true,
  });

  static const Color _kFocusColor = Color(0xFFC8A96E); // brandGold

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) {
        try {
          GetIt.instance<PanelFocusProvider>().focus(id);
        } catch (_) {}
      },
      child: ListenableBuilder(
        listenable: _provider,
        builder: (context, inner) {
          final focused = _provider.isFocused(id);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            foregroundDecoration: focused
                ? BoxDecoration(
                    border: Border.all(color: _kFocusColor, width: 1),
                  )
                : null,
            child: inner ?? child,
          );
        },
        child: child,
      ),
    );
  }

  PanelFocusProvider get _provider {
    try {
      return GetIt.instance<PanelFocusProvider>();
    } catch (_) {
      // Not registered yet — return a dummy provider so the panel still renders.
      return _DummyPanelFocusProvider();
    }
  }
}

// Fallback if GetIt not yet initialised (edge case during hot-restart)
class _DummyPanelFocusProvider extends PanelFocusProvider {
  @override
  bool isFocused(FocusPanelId panel) => false;
}
