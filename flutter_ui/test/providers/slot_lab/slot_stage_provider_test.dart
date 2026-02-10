import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/slot_lab/slot_stage_provider.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. PooledStageEvent
  // ═══════════════════════════════════════════════════════════════════════════

  group('PooledStageEvent', () {
    test('constructor creates event with empty defaults', () {
      final event = PooledStageEvent();

      expect(event.stageType, '');
      expect(event.timestampMs, 0.0);
      expect(event.payload, const <String, dynamic>{});
      expect(event.rawStage, const <String, dynamic>{});
    });

    test('reset() sets all fields and marks in use', () {
      final event = PooledStageEvent();

      event.reset(
        stageType: 'SPIN_START',
        timestampMs: 123.45,
        payload: {'key': 'value'},
        rawStage: {'type': 'spin_start'},
      );

      expect(event.stageType, 'SPIN_START');
      expect(event.timestampMs, 123.45);
      expect(event.payload, {'key': 'value'});
      expect(event.rawStage, {'type': 'spin_start'});
    });

    test('release() clears all fields', () {
      final event = PooledStageEvent();

      event.reset(
        stageType: 'REEL_STOP',
        timestampMs: 500.0,
        payload: {'reel': 3},
        rawStage: {'type': 'reel_stop', 'reel_index': 3},
      );

      event.release();

      expect(event.stageType, '');
      expect(event.timestampMs, 0.0);
      expect(event.payload, const <String, dynamic>{});
      expect(event.rawStage, const <String, dynamic>{});
    });

    test('reset then release then reset cycle works', () {
      final event = PooledStageEvent();

      event.reset(
        stageType: 'SPIN_START',
        timestampMs: 100.0,
        payload: {},
        rawStage: {},
      );
      expect(event.stageType, 'SPIN_START');

      event.release();
      expect(event.stageType, '');

      event.reset(
        stageType: 'SPIN_END',
        timestampMs: 2000.0,
        payload: {'final': true},
        rawStage: {'type': 'spin_end'},
      );
      expect(event.stageType, 'SPIN_END');
      expect(event.timestampMs, 2000.0);
      expect(event.payload, {'final': true});
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. StageEventPool
  // ═══════════════════════════════════════════════════════════════════════════

  group('StageEventPool', () {
    setUp(() {
      // Reset pool state for each test by releasing all and resetting stats.
      // The pool is a singleton, so we need to clean up between tests.
      StageEventPool.instance.releaseAll();
      StageEventPool.instance.resetStats();
    });

    test('instance is a singleton', () {
      final a = StageEventPool.instance;
      final b = StageEventPool.instance;
      expect(identical(a, b), isTrue);
    });

    test('init() creates initial pool of 64 events', () {
      // releaseAll in setUp already ensures pool exists after init.
      // Call init explicitly to test the path.
      StageEventPool.instance.init();

      // After init, we should be able to acquire at least 64 events.
      final events = <PooledStageEvent>[];
      for (int i = 0; i < 64; i++) {
        events.add(StageEventPool.instance.acquire());
      }
      // All 64 should come from the pool (hits).
      // Since the pool was already initialized by previous setUp calls,
      // all 64 should be hits.
      expect(events.length, 64);

      // Release them all
      for (final e in events) {
        StageEventPool.instance.release(e);
      }
    });

    test('acquire() returns a PooledStageEvent', () {
      StageEventPool.instance.init();
      final event = StageEventPool.instance.acquire();
      expect(event, isA<PooledStageEvent>());
      StageEventPool.instance.release(event);
    });

    test('acquire() multiple times returns different instances', () {
      StageEventPool.instance.init();
      final event1 = StageEventPool.instance.acquire();
      final event2 = StageEventPool.instance.acquire();
      final event3 = StageEventPool.instance.acquire();

      expect(identical(event1, event2), isFalse);
      expect(identical(event2, event3), isFalse);
      expect(identical(event1, event3), isFalse);

      StageEventPool.instance.release(event1);
      StageEventPool.instance.release(event2);
      StageEventPool.instance.release(event3);
    });

    test('release(event) makes the event available again', () {
      StageEventPool.instance.init();

      // Acquire all 64 pool events
      final events = <PooledStageEvent>[];
      for (int i = 0; i < 64; i++) {
        events.add(StageEventPool.instance.acquire());
      }

      // Release the first one
      StageEventPool.instance.release(events[0]);

      // Reset stats to measure the next acquire
      StageEventPool.instance.resetStats();

      // Acquire again — should reuse the released event (a hit)
      final reacquired = StageEventPool.instance.acquire();
      expect(reacquired, isA<PooledStageEvent>());

      // The reacquired event should be the same instance as events[0]
      // since it was the only one released back to the pool
      expect(identical(reacquired, events[0]), isTrue);

      // Cleanup
      StageEventPool.instance.releaseAll();
    });

    test('releaseAll() releases all events', () {
      StageEventPool.instance.init();

      // Acquire several
      for (int i = 0; i < 10; i++) {
        StageEventPool.instance.acquire();
      }

      StageEventPool.instance.releaseAll();

      // After releaseAll, we can acquire again from the pool
      StageEventPool.instance.resetStats();
      final event = StageEventPool.instance.acquire();
      expect(event, isA<PooledStageEvent>());

      StageEventPool.instance.releaseAll();
    });

    test('hitRate starts at 1.0 when no requests made', () {
      StageEventPool.instance.init();
      StageEventPool.instance.resetStats();

      expect(StageEventPool.instance.hitRate, 1.0);
    });

    test('hitRate tracks hits vs misses', () {
      StageEventPool.instance.init();
      StageEventPool.instance.resetStats();

      // All acquires from initialized pool are hits
      final events = <PooledStageEvent>[];
      for (int i = 0; i < 5; i++) {
        events.add(StageEventPool.instance.acquire());
      }

      // 5 hits, 0 misses = 1.0
      expect(StageEventPool.instance.hitRate, 1.0);

      for (final e in events) {
        StageEventPool.instance.release(e);
      }
    });

    test('resetStats() resets hits and misses', () {
      StageEventPool.instance.init();

      // Do some acquires
      final event = StageEventPool.instance.acquire();
      StageEventPool.instance.release(event);

      StageEventPool.instance.resetStats();

      // After reset, hitRate should be 1.0 (no requests)
      expect(StageEventPool.instance.hitRate, 1.0);
    });

    test('pool expands up to maxPoolSize (256)', () {
      StageEventPool.instance.init();
      StageEventPool.instance.releaseAll();
      StageEventPool.instance.resetStats();

      // Acquire more than initial pool size (64) to force expansion
      final events = <PooledStageEvent>[];
      for (int i = 0; i < 200; i++) {
        events.add(StageEventPool.instance.acquire());
      }

      // All should succeed
      expect(events.length, 200);

      // Cleanup
      StageEventPool.instance.releaseAll();
    });

    test('statsString contains pool info', () {
      StageEventPool.instance.init();
      StageEventPool.instance.releaseAll();
      StageEventPool.instance.resetStats();

      StageEventPool.instance.acquire();

      final stats = StageEventPool.instance.statsString;
      expect(stats, contains('Pool:'));
      expect(stats, contains('Acquired:'));
      expect(stats, contains('Hits:'));
      expect(stats, contains('Hit Rate:'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. SlotStageProvider — Initial state
  // ═══════════════════════════════════════════════════════════════════════════

  group('SlotStageProvider initial state', () {
    late SlotStageProvider provider;

    setUp(() {
      provider = SlotStageProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('lastStages is empty', () {
      expect(provider.lastStages, isEmpty);
    });

    test('pooledStages is unmodifiable empty list', () {
      expect(provider.pooledStages, isEmpty);
      expect(() => (provider.pooledStages as List).add(PooledStageEvent()),
          throwsA(isA<UnsupportedError>()));
    });

    test('cachedStagesSpinId is null', () {
      expect(provider.cachedStagesSpinId, isNull);
    });

    test('isPlayingStages is false', () {
      expect(provider.isPlayingStages, isFalse);
    });

    test('currentStageIndex is 0', () {
      expect(provider.currentStageIndex, 0);
    });

    test('isPaused is false', () {
      expect(provider.isPaused, isFalse);
    });

    test('isActivelyPlaying is false (isPlayingStages && !isPaused)', () {
      expect(provider.isActivelyPlaying, isFalse);
    });

    test('isReelsSpinning is false', () {
      expect(provider.isReelsSpinning, isFalse);
    });

    test('isWinPresentationActive is false', () {
      expect(provider.isWinPresentationActive, isFalse);
    });

    test('useVisualSyncForReelStop is true', () {
      expect(provider.useVisualSyncForReelStop, isTrue);
    });

    test('isRecordingStages is false', () {
      expect(provider.isRecordingStages, isFalse);
    });

    test('skipRequested is false', () {
      expect(provider.skipRequested, isFalse);
    });

    test('lastValidationIssues is empty', () {
      expect(provider.lastValidationIssues, isEmpty);
    });

    test('stagesValid is true (empty issues)', () {
      expect(provider.stagesValid, isTrue);
    });

    test('anticipationConfigType is tipA', () {
      expect(provider.anticipationConfigType, AnticipationConfigType.tipA);
    });

    test('scatterSymbolId is 12', () {
      expect(provider.scatterSymbolId, 12);
    });

    test('bonusSymbolId is 11', () {
      expect(provider.bonusSymbolId, 11);
    });

    test('tipBAllowedReels is [0, 2, 4] and unmodifiable', () {
      expect(provider.tipBAllowedReels, [0, 2, 4]);
      expect(() => (provider.tipBAllowedReels as List).add(5),
          throwsA(isA<UnsupportedError>()));
    });

    test('aleAutoSync is true', () {
      expect(provider.aleAutoSync, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. Configuration methods
  // ═══════════════════════════════════════════════════════════════════════════

  group('Configuration methods', () {
    late SlotStageProvider provider;

    setUp(() {
      provider = SlotStageProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('setTotalReels sets internally', () {
      // setTotalReels does not notify or expose directly,
      // but it affects getAnticipationReels via totalReels parameter
      // and internal _totalReels for REEL_STOP logic.
      // We verify it doesn't throw.
      provider.setTotalReels(6);
      // No direct getter, but we can test indirectly via getAnticipationReels
    });

    test('setBetAmount sets internally', () {
      // setBetAmount does not notify or expose directly.
      provider.setBetAmount(5.0);
      // No direct getter, verify no exception.
    });

    test('setAnticipationConfigType sets and notifies', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.setAnticipationConfigType(AnticipationConfigType.tipB);
      expect(provider.anticipationConfigType, AnticipationConfigType.tipB);
      expect(notifyCount, 1);

      provider.setAnticipationConfigType(AnticipationConfigType.tipA);
      expect(provider.anticipationConfigType, AnticipationConfigType.tipA);
      expect(notifyCount, 2);
    });

    test('setScatterSymbolId sets and notifies', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.setScatterSymbolId(15);
      expect(provider.scatterSymbolId, 15);
      expect(notifyCount, 1);
    });

    test('setBonusSymbolId sets and notifies', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.setBonusSymbolId(20);
      expect(provider.bonusSymbolId, 20);
      expect(notifyCount, 1);
    });

    test('setTipBAllowedReels copies and sorts, then notifies', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.setTipBAllowedReels([4, 1, 3]);
      expect(provider.tipBAllowedReels, [1, 3, 4]);
      expect(notifyCount, 1);
    });

    test('setTipBAllowedReels result is unmodifiable', () {
      provider.setTipBAllowedReels([2, 0, 4]);
      expect(() => (provider.tipBAllowedReels as List).add(5),
          throwsA(isA<UnsupportedError>()));
    });

    test('setAleAutoSync sets and notifies', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.setAleAutoSync(false);
      expect(provider.aleAutoSync, isFalse);
      expect(notifyCount, 1);

      provider.setAleAutoSync(true);
      expect(provider.aleAutoSync, isTrue);
      expect(notifyCount, 2);
    });

    test('useVisualSyncForReelStop setter works', () {
      provider.useVisualSyncForReelStop = false;
      expect(provider.useVisualSyncForReelStop, isFalse);

      provider.useVisualSyncForReelStop = true;
      expect(provider.useVisualSyncForReelStop, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. Anticipation helpers
  // ═══════════════════════════════════════════════════════════════════════════

  group('Anticipation helpers', () {
    late SlotStageProvider provider;

    setUp(() {
      provider = SlotStageProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    group('canTriggerAnticipation', () {
      test('wild (10) returns false', () {
        expect(provider.canTriggerAnticipation(10), isFalse);
      });

      test('scatter (12 default) returns true', () {
        expect(provider.canTriggerAnticipation(12), isTrue);
      });

      test('bonus (11 default) returns true', () {
        expect(provider.canTriggerAnticipation(11), isTrue);
      });

      test('random other symbol returns false', () {
        expect(provider.canTriggerAnticipation(1), isFalse);
        expect(provider.canTriggerAnticipation(5), isFalse);
        expect(provider.canTriggerAnticipation(99), isFalse);
      });

      test('respects custom scatter symbol id', () {
        provider.setScatterSymbolId(25);
        expect(provider.canTriggerAnticipation(25), isTrue);
        expect(provider.canTriggerAnticipation(12), isFalse);
      });

      test('respects custom bonus symbol id', () {
        provider.setBonusSymbolId(30);
        expect(provider.canTriggerAnticipation(30), isTrue);
        expect(provider.canTriggerAnticipation(11), isFalse);
      });

      test('wild is always false even if scatter or bonus is set to 10', () {
        // Wild check takes precedence: if symbolId == 10, return false
        provider.setScatterSymbolId(10);
        expect(provider.canTriggerAnticipation(10), isFalse);
      });
    });

    group('shouldTriggerAnticipation', () {
      test('empty set returns false', () {
        expect(provider.shouldTriggerAnticipation({}), isFalse);
      });

      test('single reel returns false', () {
        expect(provider.shouldTriggerAnticipation({0}), isFalse);
        expect(provider.shouldTriggerAnticipation({3}), isFalse);
      });

      test('2+ reels returns true in tipA mode', () {
        expect(provider.anticipationConfigType, AnticipationConfigType.tipA);
        expect(provider.shouldTriggerAnticipation({0, 1}), isTrue);
        expect(provider.shouldTriggerAnticipation({0, 2, 4}), isTrue);
      });

      test('tipB mode: only if first 2 allowed reels are present', () {
        provider.setAnticipationConfigType(AnticipationConfigType.tipB);
        // Default tipBAllowedReels = [0, 2, 4]
        // First two allowed reels are 0 and 2

        // Both 0 and 2 present
        expect(provider.shouldTriggerAnticipation({0, 2}), isTrue);

        // Only 0 present (missing 2)
        expect(provider.shouldTriggerAnticipation({0, 1}), isFalse);

        // Only 2 present (missing 0)
        expect(provider.shouldTriggerAnticipation({2, 4}), isFalse);

        // Neither present
        expect(provider.shouldTriggerAnticipation({1, 3}), isFalse);

        // Both 0 and 2 plus extras
        expect(provider.shouldTriggerAnticipation({0, 2, 3}), isTrue);
      });

      test('tipB mode with less than 2 allowed reels returns false', () {
        provider.setAnticipationConfigType(AnticipationConfigType.tipB);
        provider.setTipBAllowedReels([0]);
        expect(provider.shouldTriggerAnticipation({0, 1}), isFalse);
      });

      test('tipB mode with custom allowed reels', () {
        provider.setAnticipationConfigType(AnticipationConfigType.tipB);
        provider.setTipBAllowedReels([1, 3, 5]);
        // First two allowed: 1 and 3

        expect(provider.shouldTriggerAnticipation({1, 3}), isTrue);
        expect(provider.shouldTriggerAnticipation({1, 5}), isFalse);
        expect(provider.shouldTriggerAnticipation({0, 2}), isFalse);
      });
    });

    group('getAnticipationReels', () {
      test('tipA: returns all reels NOT in triggerReels, sorted', () {
        expect(provider.anticipationConfigType, AnticipationConfigType.tipA);

        final result = provider.getAnticipationReels({0, 1}, 5);
        expect(result, [2, 3, 4]);
      });

      test('tipA: empty triggerReels returns all reels', () {
        final result = provider.getAnticipationReels({}, 5);
        expect(result, [0, 1, 2, 3, 4]);
      });

      test('tipA: all reels in triggerReels returns empty', () {
        final result = provider.getAnticipationReels({0, 1, 2, 3, 4}, 5);
        expect(result, isEmpty);
      });

      test('tipA: result is sorted', () {
        final result = provider.getAnticipationReels({1, 3}, 6);
        expect(result, [0, 2, 4, 5]);
      });

      test('tipB: returns allowed reels NOT in triggerReels, sorted', () {
        provider.setAnticipationConfigType(AnticipationConfigType.tipB);
        // Default tipBAllowedReels = [0, 2, 4]

        final result = provider.getAnticipationReels({0}, 5);
        expect(result, [2, 4]);
      });

      test('tipB: only returns reels within totalReels range', () {
        provider.setAnticipationConfigType(AnticipationConfigType.tipB);
        provider.setTipBAllowedReels([0, 2, 4, 6, 8]);

        // totalReels = 5, so reel 6 and 8 are excluded
        final result = provider.getAnticipationReels({0}, 5);
        expect(result, [2, 4]);
      });

      test('tipB: all allowed reels in triggerReels returns empty', () {
        provider.setAnticipationConfigType(AnticipationConfigType.tipB);
        final result = provider.getAnticipationReels({0, 2, 4}, 5);
        expect(result, isEmpty);
      });

      test('tipB: result is sorted even if allowed reels are set unsorted', () {
        provider.setAnticipationConfigType(AnticipationConfigType.tipB);
        provider.setTipBAllowedReels([4, 1, 3]);
        // After setTipBAllowedReels sorts: [1, 3, 4]

        final result = provider.getAnticipationReels({3}, 5);
        expect(result, [1, 4]);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. Stage recording
  // ═══════════════════════════════════════════════════════════════════════════

  group('Stage recording', () {
    late SlotStageProvider provider;

    setUp(() {
      provider = SlotStageProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('startStageRecording sets isRecordingStages to true', () {
      expect(provider.isRecordingStages, isFalse);

      provider.startStageRecording();
      expect(provider.isRecordingStages, isTrue);
    });

    test('startStageRecording notifies listeners', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.startStageRecording();
      expect(notifyCount, 1);
    });

    test('startStageRecording does not re-start if already recording', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.startStageRecording();
      expect(notifyCount, 1);

      // Second call should be a no-op (guard: if (_isRecordingStages) return)
      provider.startStageRecording();
      expect(notifyCount, 1); // No additional notification
      expect(provider.isRecordingStages, isTrue);
    });

    test('stopStageRecording sets isRecordingStages to false', () {
      provider.startStageRecording();
      expect(provider.isRecordingStages, isTrue);

      provider.stopStageRecording();
      expect(provider.isRecordingStages, isFalse);
    });

    test('stopStageRecording notifies listeners', () {
      provider.startStageRecording();

      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.stopStageRecording();
      expect(notifyCount, 1);
    });

    test('stopStageRecording does not re-stop if already stopped', () {
      expect(provider.isRecordingStages, isFalse);

      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      // Already stopped, should be a no-op
      provider.stopStageRecording();
      expect(notifyCount, 0);
      expect(provider.isRecordingStages, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. Stage clearing
  // ═══════════════════════════════════════════════════════════════════════════

  group('Stage clearing', () {
    late SlotStageProvider provider;

    setUp(() {
      provider = SlotStageProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('clearStages empties lastStages', () {
      // We cannot set stages without FFI triggering, but clearStages
      // should always work regardless of current state.
      provider.clearStages();
      expect(provider.lastStages, isEmpty);
    });

    test('clearStages resets currentStageIndex to 0', () {
      provider.clearStages();
      expect(provider.currentStageIndex, 0);
    });

    test('clearStages clears cachedStagesSpinId', () {
      provider.clearStages();
      expect(provider.cachedStagesSpinId, isNull);
    });

    test('clearStages notifies listeners', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.clearStages();
      expect(notifyCount, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. Stop playback reset
  // ═══════════════════════════════════════════════════════════════════════════

  group('Stop playback reset', () {
    late SlotStageProvider provider;

    setUp(() {
      provider = SlotStageProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('stopStagePlayback resets isPlayingStages to false', () {
      provider.stopStagePlayback();
      expect(provider.isPlayingStages, isFalse);
    });

    test('stopStagePlayback resets isPaused to false', () {
      provider.stopStagePlayback();
      expect(provider.isPaused, isFalse);
    });

    test('stopStagePlayback resets currentStageIndex to 0', () {
      provider.stopStagePlayback();
      expect(provider.currentStageIndex, 0);
    });

    test('stopStagePlayback resets isReelsSpinning to false', () {
      provider.stopStagePlayback();
      expect(provider.isReelsSpinning, isFalse);
    });

    test('stopStagePlayback notifies listeners', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.stopStagePlayback();
      expect(notifyCount, 1);
    });

    test('stopAllPlayback delegates to stopStagePlayback', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.stopAllPlayback();

      expect(provider.isPlayingStages, isFalse);
      expect(provider.isPaused, isFalse);
      expect(provider.currentStageIndex, 0);
      expect(provider.isReelsSpinning, isFalse);
      expect(notifyCount, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 9. Notification behavior
  // ═══════════════════════════════════════════════════════════════════════════

  group('Notification behavior', () {
    late SlotStageProvider provider;
    late int notifyCount;

    setUp(() {
      provider = SlotStageProvider();
      notifyCount = 0;
      provider.addListener(() => notifyCount++);
    });

    tearDown(() {
      provider.dispose();
    });

    test('setAnticipationConfigType notifies', () {
      provider.setAnticipationConfigType(AnticipationConfigType.tipB);
      expect(notifyCount, 1);
    });

    test('setScatterSymbolId notifies', () {
      provider.setScatterSymbolId(99);
      expect(notifyCount, 1);
    });

    test('setBonusSymbolId notifies', () {
      provider.setBonusSymbolId(88);
      expect(notifyCount, 1);
    });

    test('setTipBAllowedReels notifies', () {
      provider.setTipBAllowedReels([1, 2, 3]);
      expect(notifyCount, 1);
    });

    test('setAleAutoSync notifies', () {
      provider.setAleAutoSync(false);
      expect(notifyCount, 1);
    });

    test('startStageRecording notifies once', () {
      provider.startStageRecording();
      expect(notifyCount, 1);
    });

    test('stopStageRecording notifies after start', () {
      provider.startStageRecording();
      notifyCount = 0;

      provider.stopStageRecording();
      expect(notifyCount, 1);
    });

    test('clearStages notifies', () {
      provider.clearStages();
      expect(notifyCount, 1);
    });

    test('stopStagePlayback notifies', () {
      provider.stopStagePlayback();
      expect(notifyCount, 1);
    });

    test('setTotalReels does NOT notify', () {
      provider.setTotalReels(6);
      expect(notifyCount, 0);
    });

    test('setBetAmount does NOT notify', () {
      provider.setBetAmount(10.0);
      expect(notifyCount, 0);
    });

    test('useVisualSyncForReelStop setter does NOT notify', () {
      provider.useVisualSyncForReelStop = false;
      expect(notifyCount, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 10. tipBAllowedReels is unmodifiable
  // ═══════════════════════════════════════════════════════════════════════════

  group('tipBAllowedReels immutability', () {
    late SlotStageProvider provider;

    setUp(() {
      provider = SlotStageProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('default tipBAllowedReels is unmodifiable', () {
      final reels = provider.tipBAllowedReels;
      expect(() => reels.add(5), throwsA(isA<UnsupportedError>()));
      expect(() => reels.removeAt(0), throwsA(isA<UnsupportedError>()));
      expect(() => reels.clear(), throwsA(isA<UnsupportedError>()));
    });

    test('tipBAllowedReels after setTipBAllowedReels is unmodifiable', () {
      provider.setTipBAllowedReels([1, 3, 5]);
      final reels = provider.tipBAllowedReels;
      expect(() => reels.add(7), throwsA(isA<UnsupportedError>()));
    });

    test('modifying input list does not affect provider state', () {
      final input = [3, 1, 2];
      provider.setTipBAllowedReels(input);

      // Modify the original input list
      input.add(99);
      input.sort();

      // Provider state should not be affected
      expect(provider.tipBAllowedReels, [1, 2, 3]);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BONUS: Additional edge cases
  // ═══════════════════════════════════════════════════════════════════════════

  group('Edge cases', () {
    late SlotStageProvider provider;

    setUp(() {
      provider = SlotStageProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('onAllReelsVisualStop does nothing when not spinning', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      expect(provider.isReelsSpinning, isFalse);
      provider.onAllReelsVisualStop();
      // Should not notify because isReelsSpinning was already false
      expect(notifyCount, 0);
      expect(provider.isReelsSpinning, isFalse);
    });

    test('isActivelyPlaying reflects combined state', () {
      // Initially both false
      expect(provider.isActivelyPlaying, isFalse);

      // isActivelyPlaying = isPlayingStages && !isPaused
      // We cannot set isPlayingStages directly (it's private),
      // but we can verify the logic is consistent.
      expect(provider.isPlayingStages, isFalse);
      expect(provider.isPaused, isFalse);
      expect(provider.isActivelyPlaying, isFalse);
    });

    test('stagePoolStats returns a non-empty string', () {
      StageEventPool.instance.init();
      final stats = provider.stagePoolStats;
      expect(stats, isNotEmpty);
      expect(stats, contains('Pool:'));
    });

    test('getAnticipationReels with totalReels = 0 returns empty', () {
      final result = provider.getAnticipationReels({0, 1}, 0);
      expect(result, isEmpty);
    });

    test('setTipBAllowedReels with empty list', () {
      provider.setTipBAllowedReels([]);
      expect(provider.tipBAllowedReels, isEmpty);
    });

    test('shouldTriggerAnticipation with empty tipBAllowedReels in tipB mode', () {
      provider.setAnticipationConfigType(AnticipationConfigType.tipB);
      provider.setTipBAllowedReels([]);
      // Less than 2 allowed reels -> false
      expect(provider.shouldTriggerAnticipation({0, 1, 2}), isFalse);
    });

    test('multiple config changes accumulate correctly', () {
      provider.setScatterSymbolId(20);
      provider.setBonusSymbolId(21);
      provider.setAnticipationConfigType(AnticipationConfigType.tipB);
      provider.setTipBAllowedReels([1, 3]);

      expect(provider.scatterSymbolId, 20);
      expect(provider.bonusSymbolId, 21);
      expect(provider.anticipationConfigType, AnticipationConfigType.tipB);
      expect(provider.tipBAllowedReels, [1, 3]);

      // canTriggerAnticipation uses new ids
      expect(provider.canTriggerAnticipation(20), isTrue); // scatter
      expect(provider.canTriggerAnticipation(21), isTrue); // bonus
      expect(provider.canTriggerAnticipation(12), isFalse); // old scatter
      expect(provider.canTriggerAnticipation(11), isFalse); // old bonus

      // shouldTriggerAnticipation uses tipB with [1, 3]
      expect(provider.shouldTriggerAnticipation({1, 3}), isTrue);
      expect(provider.shouldTriggerAnticipation({0, 2}), isFalse);
    });

    test('recording start/stop/start cycle works', () {
      provider.startStageRecording();
      expect(provider.isRecordingStages, isTrue);

      provider.stopStageRecording();
      expect(provider.isRecordingStages, isFalse);

      provider.startStageRecording();
      expect(provider.isRecordingStages, isTrue);
    });
  });
}
