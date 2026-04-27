/// Regression test for FLUX_MASTER_TODO 0.5 — CortexHands modifier
/// propagation bug.
///
/// Before the fix, `cmd+shift+M` injected `KeyData` only through
/// `platformDispatcher.onKeyData`, which delivers to the engine pipeline
/// but never mutates `HardwareKeyboard.instance` state. As a result
/// `HardwareKeyboard.instance.isMetaPressed` / `isShiftPressed` stayed
/// `false` for synthesized chords, and any widget using `Shortcuts`
/// (which queries that state) silently rejected the chord.
///
/// This test injects a `cmd+shift+m` chord via `pressKey` and asserts
/// that `HardwareKeyboard.instance` reports both modifier keys held
/// at the moment the main key fires, then released after key-up.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/cortex_hands_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CortexHandsService modifier propagation', () {
    setUp(() {
      // Drain any state from previous tests — HardwareKeyboard is a singleton
      // and asserts on duplicate-down events, so we start clean.
      HardwareKeyboard.instance.clearState();
    });

    test('cmd+shift+m flips HardwareKeyboard state during chord', () async {
      // Sample state at three moments: right after press, after release.
      // We can't easily intercept mid-flight without rewiring, so we use
      // a listener that records every state change.
      final samples = <Set<LogicalKeyboardKey>>[];
      void recorder() {
        samples.add(Set<LogicalKeyboardKey>.from(
          HardwareKeyboard.instance.logicalKeysPressed,
        ));
      }

      HardwareKeyboard.instance.addHandler((event) {
        recorder();
        return false;
      });

      await CortexHandsService.instance.pressKey('cmd+shift+m');

      // After the chord finishes, all keys should be released.
      expect(
        HardwareKeyboard.instance.logicalKeysPressed,
        isEmpty,
        reason: 'all keys released after chord completes',
      );

      // During the chord we expect to have observed at least one sample
      // where BOTH meta and shift were pressed simultaneously with M.
      final chordPeak = samples.any((pressed) =>
          (pressed.contains(LogicalKeyboardKey.metaLeft) ||
              pressed.contains(LogicalKeyboardKey.meta)) &&
          (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
              pressed.contains(LogicalKeyboardKey.shift)) &&
          pressed.contains(LogicalKeyboardKey.keyM));
      expect(
        chordPeak,
        isTrue,
        reason: 'cmd+shift+m must register all three keys held at the same '
            'moment so that Shortcuts.isMetaPressed sees them. Observed '
            'sequences: $samples',
      );
    });

    test('single key "f" works without modifiers leaking', () async {
      await CortexHandsService.instance.pressKey('f');
      expect(HardwareKeyboard.instance.isMetaPressed, isFalse);
      expect(HardwareKeyboard.instance.isShiftPressed, isFalse);
      expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
    });

    test('cmd+z releases meta after chord', () async {
      await CortexHandsService.instance.pressKey('cmd+z');
      expect(HardwareKeyboard.instance.isMetaPressed, isFalse,
          reason: 'meta must be released after up-event');
      expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
    });
  });
}
