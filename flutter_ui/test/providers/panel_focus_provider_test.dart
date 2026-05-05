// SPEC-14 — `PanelFocusProvider` powers the 1px brandGold border that
// tells the user which major UI panel is currently receiving keyboard
// shortcuts (Spine / Canvas / Dock / DAW Timeline / Lower Zone / etc).
//
// The provider is a tight ChangeNotifier — no FFI, no audio thread, no
// async — so the contract is small but load-bearing:
//
//   * `focus(panel)` updates state AND fires `notifyListeners`
//   * focusing the SAME panel twice must NOT fire (avoids spurious
//     `AnimatedContainer` repaint storms when a tap-down event lands
//     on the already-focused panel)
//   * `blur()` clears focus AND fires
//   * `blur()` on already-cleared state must NOT fire
//   * `isFocused(panel)` mirrors the latest `focused` getter
//
// Spurious notifications would cause every `FocusablePanel` in the
// tree to rebuild on every gesture, which compounds badly when the
// user drags a slider or scrubs a timeline (touch events fire at
// ~60Hz and each one would trigger a full panel rebuild).

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/panel_focus_provider.dart';

void main() {
  group('PanelFocusProvider — initial state', () {
    test('starts with no panel focused', () {
      final p = PanelFocusProvider();
      expect(p.focused, isNull);
    });

    test('isFocused returns false for every panel id on a fresh provider', () {
      final p = PanelFocusProvider();
      for (final id in FocusPanelId.values) {
        expect(p.isFocused(id), isFalse,
            reason: '$id should not be focused on a fresh provider');
      }
    });
  });

  group('PanelFocusProvider.focus', () {
    test('focusing a panel updates the focused getter', () {
      final p = PanelFocusProvider();
      p.focus(FocusPanelId.helixCanvas);
      expect(p.focused, FocusPanelId.helixCanvas);
    });

    test('focusing fires notifyListeners exactly once', () {
      final p = PanelFocusProvider();
      var notifyCount = 0;
      p.addListener(() => notifyCount++);
      p.focus(FocusPanelId.helixDock);
      expect(notifyCount, 1);
    });

    test('focusing the SAME panel twice does NOT fire (anti-spam guard)', () {
      // Tap-down events on an already-focused panel must not trigger a
      // notify — otherwise every `FocusablePanel` in the tree rebuilds
      // on every pointer event and `AnimatedContainer` runs its 150ms
      // animation against itself, eating frame budget.
      final p = PanelFocusProvider();
      var notifyCount = 0;
      p.focus(FocusPanelId.helixSpine);
      p.addListener(() => notifyCount++);
      p.focus(FocusPanelId.helixSpine); // already focused — must no-op
      p.focus(FocusPanelId.helixSpine);
      p.focus(FocusPanelId.helixSpine);
      expect(notifyCount, 0,
          reason: 'identical focus() calls must not notify');
    });

    test('switching between panels fires once per actual transition', () {
      final p = PanelFocusProvider();
      var notifyCount = 0;
      p.addListener(() => notifyCount++);
      p.focus(FocusPanelId.helixSpine); // null → spine
      p.focus(FocusPanelId.helixCanvas); // spine → canvas
      p.focus(FocusPanelId.helixDock); // canvas → dock
      p.focus(FocusPanelId.helixDock); // dock → dock (no-op)
      expect(notifyCount, 3);
    });
  });

  group('PanelFocusProvider.isFocused', () {
    test('returns true for the focused panel and false for all others', () {
      final p = PanelFocusProvider();
      p.focus(FocusPanelId.dawTimeline);
      for (final id in FocusPanelId.values) {
        if (id == FocusPanelId.dawTimeline) {
          expect(p.isFocused(id), isTrue);
        } else {
          expect(p.isFocused(id), isFalse);
        }
      }
    });

    test('updates atomically — no stale read between focus() and notify', () {
      final p = PanelFocusProvider();
      FocusPanelId? observed;
      p.addListener(() => observed = p.focused);
      p.focus(FocusPanelId.slotLabCanvas);
      expect(observed, FocusPanelId.slotLabCanvas);
    });
  });

  group('PanelFocusProvider.blur', () {
    test('blur clears focus when something is focused', () {
      final p = PanelFocusProvider();
      p.focus(FocusPanelId.helixCanvas);
      p.blur();
      expect(p.focused, isNull);
    });

    test('blur fires notifyListeners when state actually changes', () {
      final p = PanelFocusProvider();
      p.focus(FocusPanelId.helixCanvas);
      var notifyCount = 0;
      p.addListener(() => notifyCount++);
      p.blur();
      expect(notifyCount, 1);
    });

    test('blur on already-cleared state does NOT fire (anti-spam guard)', () {
      // Same anti-spam invariant as focus — a UI route that calls
      // blur() on every Escape press must not flood listeners when the
      // panel system was already idle.
      final p = PanelFocusProvider();
      var notifyCount = 0;
      p.addListener(() => notifyCount++);
      p.blur();
      p.blur();
      p.blur();
      expect(notifyCount, 0);
    });

    test('after blur, isFocused returns false for every id', () {
      final p = PanelFocusProvider();
      p.focus(FocusPanelId.helixDock);
      p.blur();
      for (final id in FocusPanelId.values) {
        expect(p.isFocused(id), isFalse);
      }
    });
  });

  group('FocusPanelId enum cardinality', () {
    test('exposes the canonical 7-panel surface', () {
      // If a panel is added or removed, the SPEC-14 cycle order in
      // `_HelixScreenState._cyclePanelFocus` and the `_panelLabel`
      // switch must both be updated. Pinning the count makes that
      // refactor impossible to forget.
      expect(FocusPanelId.values.length, 7);
      expect(
        FocusPanelId.values,
        containsAll([
          FocusPanelId.helixCanvas,
          FocusPanelId.helixDock,
          FocusPanelId.helixSpine,
          FocusPanelId.dawTimeline,
          FocusPanelId.dawLowerZone,
          FocusPanelId.slotLabCanvas,
          FocusPanelId.slotLabLowerZone,
        ]),
      );
    });
  });

  group('PanelFocusProvider — focus → blur → focus round-trip', () {
    test('full transition cycle preserves notify cardinality', () {
      final p = PanelFocusProvider();
      var notifyCount = 0;
      p.addListener(() => notifyCount++);
      p.focus(FocusPanelId.helixSpine); // 1
      p.blur(); // 2
      p.focus(FocusPanelId.helixSpine); // 3 (state actually changed)
      p.focus(FocusPanelId.helixCanvas); // 4
      p.blur(); // 5
      p.blur(); // no-op
      expect(notifyCount, 5);
      expect(p.focused, isNull);
    });
  });
}
