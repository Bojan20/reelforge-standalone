/// Sprint 15 Faza 4.D.3 — async edge case tests for the HELIX screen's
/// `Timer.cancel()` contract.
///
/// `HelixScreen.initState()` schedules a 3-second `Timer` (stored in
/// `_visionInitTimer`) that calls `CortexVisionService.init() +
/// captureFullWindow()` after a delay.  If the screen is disposed during
/// that window the timer MUST be cancelled in `dispose()` or the async
/// callback will run against a dead BuildContext and either crash or
/// silently leak state into the next mount.
///
/// These tests are pure Dart (no widget pumping required) — they exercise
/// the contract every `Timer`-with-cancel pattern in HelixScreen relies on:
///
///   1. Cancelled timers do NOT fire their callback (`Zone` guarantee).
///   2. Cancelling an already-fired timer is a no-op (no exception).
///   3. Cancelling twice is idempotent (matches `dispose()` re-entrancy).
///   4. `isActive` reports `false` after cancel.
///   5. The recommended `if (!mounted) return;` early-out at the top of
///      the callback survives the post-async-gap state lookup.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

void main() {
  group('Timer cancel race contract (Sprint 15 Faza 4.D.3)', () {
    test('cancelled timer does NOT fire its callback', () {
      FakeAsync().run((async) {
        var fired = false;
        final timer = Timer(const Duration(seconds: 3), () {
          fired = true;
        });
        // Simulate dispose() arriving before the 3-second window elapses.
        timer.cancel();
        async.elapse(const Duration(seconds: 5));
        expect(fired, isFalse,
            reason: 'Cancelled Timer must never invoke its callback');
        expect(timer.isActive, isFalse);
      });
    });

    test('cancelling an already-fired timer is a no-op', () {
      FakeAsync().run((async) {
        var fireCount = 0;
        final timer = Timer(const Duration(seconds: 1), () {
          fireCount += 1;
        });
        async.elapse(const Duration(seconds: 2));
        expect(fireCount, 1);
        expect(timer.isActive, isFalse);
        // dispose() may legitimately fire after the timer already ran —
        // calling cancel() on a fired timer must not throw.
        expect(() => timer.cancel(), returnsNormally);
        // No double-fire.
        async.elapse(const Duration(seconds: 5));
        expect(fireCount, 1);
      });
    });

    test('cancelling twice is idempotent (matches dispose re-entrancy)', () {
      FakeAsync().run((async) {
        final timer = Timer(const Duration(seconds: 3), () {});
        expect(() {
          timer.cancel();
          timer.cancel();
          timer.cancel();
        }, returnsNormally);
        async.elapse(const Duration(seconds: 5));
        expect(timer.isActive, isFalse);
      });
    });

    test('isActive flips to false immediately after cancel', () {
      FakeAsync().run((async) {
        final timer = Timer(const Duration(seconds: 3), () {});
        expect(timer.isActive, isTrue);
        timer.cancel();
        expect(timer.isActive, isFalse);
      });
    });

    test(
        'Timer? field pattern: null-safe cancel survives never-started state',
        () {
      // This mirrors the production pattern in HelixScreen.dispose():
      //   _visionInitTimer?.cancel();
      // If the post-frame callback never fired (e.g. screen torn down
      // before the first frame), the field stays null and the cancel
      // must be a no-op.
      // The Timer? field is intentionally never initialized — this
      // simulates dispose() arriving before the post-frame callback
      // had a chance to assign the timer.  The `?.cancel()` chain
      // must short-circuit safely.
      Timer? maybeTimer = _buildMaybeTimer(initializeIt: false);
      expect(() => maybeTimer?.cancel(), returnsNormally);
      expect(maybeTimer, isNull);
    });

    test(
        'mid-await mounted check pattern: callback can short-circuit '
        'when state was disposed during async gap', () async {
      // Simulates: Timer fires, callback awaits something, and BY THE TIME
      // the await resolves the State has been disposed.  The production
      // code uses `if (!mounted) return;` AFTER each await.  This test
      // codifies the contract that such a guard prevents downstream work.
      var mounted = true;
      var didCaptureAfterDispose = false;

      Future<void> simulatedCallback() async {
        // Pre-await mounted check (HelixScreen line 460).
        if (!mounted) return;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        // Post-await mounted check (HelixScreen line 463).
        if (!mounted) return;
        didCaptureAfterDispose = true;
      }

      // Kick off the callback, THEN flip mounted to false during the
      // await gap (simulates dispose() running between Timer fire and
      // the await resolving).
      final future = simulatedCallback();
      mounted = false;
      await future;

      expect(didCaptureAfterDispose, isFalse,
          reason:
              'Mid-await `if (!mounted) return;` must short-circuit when '
              'State was disposed during the async gap');
    });

    test('FakeAsync exposes pending timer count for leak detection', () {
      // Helper used by an earlier test — declared as a tear-off so the
      // analyzer treats the resulting `Timer?` as runtime-nullable
      // (not statically-null) and stops flagging the cancel as dead.
      // (No-op body to keep the test self-contained.)
      FakeAsync().run((async) {
        Timer(const Duration(seconds: 3), () {});
        Timer(const Duration(seconds: 1), () {});
        expect(async.pendingTimers.length, 2,
            reason:
                'When `dispose()` forgets to cancel a Timer it shows up '
                'in `pendingTimers` and FakeAsync flags the leak.');
        for (final t in async.pendingTimers) {
          t.cancel();
        }
        expect(async.pendingTimers.length, 0);
      });
    });
  });
}

/// Helper that returns a `Timer?` — either a live one or `null`.
///
/// Used so the analyzer's null-promotion can't statically infer that
/// `Timer? maybeTimer = ...` is always null, which would otherwise mark
/// the subsequent `?.cancel()` as dead code.
Timer? _buildMaybeTimer({required bool initializeIt}) {
  if (initializeIt) {
    return Timer(const Duration(seconds: 1), () {});
  }
  return null;
}
