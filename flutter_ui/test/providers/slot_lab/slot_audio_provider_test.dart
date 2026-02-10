import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/slot_lab/slot_audio_provider.dart';
import 'package:fluxforge_ui/src/rust/native_ffi.dart';

void main() {
  late SlotAudioProvider provider;
  late int notifyCount;

  setUp(() {
    provider = SlotAudioProvider();
    notifyCount = 0;
    provider.addListener(() => notifyCount++);
  });

  tearDown(() {
    provider.dispose();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 1: Initial State
  // ═══════════════════════════════════════════════════════════════════════════

  group('Initial state', () {
    test('autoTriggerAudio defaults to true', () {
      expect(provider.autoTriggerAudio, isTrue);
    });

    test('aleAutoSync defaults to true', () {
      expect(provider.aleAutoSync, isTrue);
    });

    test('persistedLowerZoneTabIndex defaults to 1', () {
      expect(provider.persistedLowerZoneTabIndex, 1);
    });

    test('persistedLowerZoneExpanded defaults to false', () {
      expect(provider.persistedLowerZoneExpanded, isFalse);
    });

    test('persistedLowerZoneHeight defaults to 250.0', () {
      expect(provider.persistedLowerZoneHeight, 250.0);
    });

    test('waveformCache starts empty', () {
      expect(provider.waveformCache, isEmpty);
    });

    test('clipIdCache starts empty', () {
      expect(provider.clipIdCache, isEmpty);
    });

    test('persistedCompositeEvents starts empty', () {
      expect(provider.persistedCompositeEvents, isEmpty);
    });

    test('persistedTracks starts empty', () {
      expect(provider.persistedTracks, isEmpty);
    });

    test('persistedEventToRegionMap starts empty', () {
      expect(provider.persistedEventToRegionMap, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 2: Configuration Setters
  // ═══════════════════════════════════════════════════════════════════════════

  group('Configuration setters', () {
    test('setAutoTriggerAudio changes value', () {
      provider.setAutoTriggerAudio(false);
      expect(provider.autoTriggerAudio, isFalse);
    });

    test('setAutoTriggerAudio can re-enable', () {
      provider.setAutoTriggerAudio(false);
      provider.setAutoTriggerAudio(true);
      expect(provider.autoTriggerAudio, isTrue);
    });

    test('setAleAutoSync changes value', () {
      provider.setAleAutoSync(false);
      expect(provider.aleAutoSync, isFalse);
    });

    test('setAleAutoSync can re-enable', () {
      provider.setAleAutoSync(false);
      provider.setAleAutoSync(true);
      expect(provider.aleAutoSync, isTrue);
    });

    test('setBetAmount does not throw', () {
      expect(() => provider.setBetAmount(5.0), returnsNormally);
    });

    test('setTotalReels does not throw', () {
      expect(() => provider.setTotalReels(6), returnsNormally);
    });

    test('setBetAmount accepts zero', () {
      expect(() => provider.setBetAmount(0.0), returnsNormally);
    });

    test('setTotalReels accepts 1', () {
      expect(() => provider.setTotalReels(1), returnsNormally);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 3: Lower Zone State Persistence
  // ═══════════════════════════════════════════════════════════════════════════

  group('Lower zone state persistence', () {
    test('setLowerZoneTabIndex changes value', () {
      provider.setLowerZoneTabIndex(3);
      expect(provider.persistedLowerZoneTabIndex, 3);
    });

    test('setLowerZoneTabIndex ignores same value', () {
      provider.setLowerZoneTabIndex(1); // same as default
      expect(provider.persistedLowerZoneTabIndex, 1);
    });

    test('setLowerZoneTabIndex accepts 0', () {
      provider.setLowerZoneTabIndex(0);
      expect(provider.persistedLowerZoneTabIndex, 0);
    });

    test('setLowerZoneTabIndex accepts high value', () {
      provider.setLowerZoneTabIndex(99);
      expect(provider.persistedLowerZoneTabIndex, 99);
    });

    test('setLowerZoneExpanded changes to true', () {
      provider.setLowerZoneExpanded(true);
      expect(provider.persistedLowerZoneExpanded, isTrue);
    });

    test('setLowerZoneExpanded changes back to false', () {
      provider.setLowerZoneExpanded(true);
      provider.setLowerZoneExpanded(false);
      expect(provider.persistedLowerZoneExpanded, isFalse);
    });

    test('setLowerZoneHeight changes value', () {
      provider.setLowerZoneHeight(400.0);
      expect(provider.persistedLowerZoneHeight, 400.0);
    });

    test('setLowerZoneHeight accepts zero', () {
      provider.setLowerZoneHeight(0.0);
      expect(provider.persistedLowerZoneHeight, 0.0);
    });

    test('setLowerZoneHeight accepts large value', () {
      provider.setLowerZoneHeight(1000.0);
      expect(provider.persistedLowerZoneHeight, 1000.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 4: Persisted Data Stores
  // ═══════════════════════════════════════════════════════════════════════════

  group('Persisted data stores', () {
    test('persistedCompositeEvents can be assigned and read', () {
      final events = [
        {'id': 'evt_1', 'name': 'Spin Sound'},
        {'id': 'evt_2', 'name': 'Win Sound'},
      ];
      provider.persistedCompositeEvents = events;
      expect(provider.persistedCompositeEvents, hasLength(2));
      expect(provider.persistedCompositeEvents[0]['id'], 'evt_1');
      expect(provider.persistedCompositeEvents[1]['name'], 'Win Sound');
    });

    test('persistedCompositeEvents can be cleared', () {
      provider.persistedCompositeEvents = [
        {'id': 'evt_1'},
      ];
      provider.persistedCompositeEvents.clear();
      expect(provider.persistedCompositeEvents, isEmpty);
    });

    test('persistedTracks can be assigned and read', () {
      final tracks = [
        {'id': 'trk_1', 'name': 'SFX Track'},
        {'id': 'trk_2', 'name': 'Music Track'},
        {'id': 'trk_3', 'name': 'VO Track'},
      ];
      provider.persistedTracks = tracks;
      expect(provider.persistedTracks, hasLength(3));
      expect(provider.persistedTracks[2]['name'], 'VO Track');
    });

    test('persistedTracks can be cleared', () {
      provider.persistedTracks = [
        {'id': 'trk_1'},
      ];
      provider.persistedTracks.clear();
      expect(provider.persistedTracks, isEmpty);
    });

    test('persistedEventToRegionMap can be assigned and read', () {
      provider.persistedEventToRegionMap = {
        'evt_1': 'region_a',
        'evt_2': 'region_b',
      };
      expect(provider.persistedEventToRegionMap, hasLength(2));
      expect(provider.persistedEventToRegionMap['evt_1'], 'region_a');
      expect(provider.persistedEventToRegionMap['evt_2'], 'region_b');
    });

    test('persistedEventToRegionMap can be cleared', () {
      provider.persistedEventToRegionMap = {'evt_1': 'region_a'};
      provider.persistedEventToRegionMap.clear();
      expect(provider.persistedEventToRegionMap, isEmpty);
    });

    test('persistedEventToRegionMap supports update', () {
      provider.persistedEventToRegionMap = {'evt_1': 'region_a'};
      provider.persistedEventToRegionMap['evt_1'] = 'region_b';
      expect(provider.persistedEventToRegionMap['evt_1'], 'region_b');
    });

    test('persisted data stores are independent', () {
      provider.persistedCompositeEvents = [
        {'id': 'a'},
      ];
      provider.persistedTracks = [
        {'id': 'b'},
      ];
      provider.persistedEventToRegionMap = {'c': 'd'};

      expect(provider.persistedCompositeEvents, hasLength(1));
      expect(provider.persistedTracks, hasLength(1));
      expect(provider.persistedEventToRegionMap, hasLength(1));

      provider.persistedCompositeEvents.clear();
      expect(provider.persistedTracks, hasLength(1));
      expect(provider.persistedEventToRegionMap, hasLength(1));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 5: Waveform Cache Management
  // ═══════════════════════════════════════════════════════════════════════════

  group('Waveform cache management', () {
    test('waveformCache can store and retrieve entries', () {
      provider.waveformCache['spin_sfx'] = [0.1, 0.5, -0.3, 0.8];
      expect(provider.waveformCache['spin_sfx'], hasLength(4));
      expect(provider.waveformCache['spin_sfx']![0], 0.1);
    });

    test('waveformCache stores multiple entries independently', () {
      provider.waveformCache['file_a'] = [0.1, 0.2];
      provider.waveformCache['file_b'] = [0.3, 0.4, 0.5];
      expect(provider.waveformCache, hasLength(2));
      expect(provider.waveformCache['file_a'], hasLength(2));
      expect(provider.waveformCache['file_b'], hasLength(3));
    });

    test('waveformCache entries can be overwritten', () {
      provider.waveformCache['key'] = [1.0];
      provider.waveformCache['key'] = [2.0, 3.0];
      expect(provider.waveformCache['key'], [2.0, 3.0]);
    });

    test('waveformCache entries can be removed', () {
      provider.waveformCache['key'] = [1.0];
      provider.waveformCache.remove('key');
      expect(provider.waveformCache.containsKey('key'), isFalse);
    });

    test('waveformCache returns null for unknown key', () {
      expect(provider.waveformCache['nonexistent'], isNull);
    });

    test('clipIdCache can store and retrieve entries', () {
      provider.clipIdCache['clip_a'] = 42;
      expect(provider.clipIdCache['clip_a'], 42);
    });

    test('clipIdCache stores multiple entries', () {
      provider.clipIdCache['clip_a'] = 1;
      provider.clipIdCache['clip_b'] = 2;
      provider.clipIdCache['clip_c'] = 3;
      expect(provider.clipIdCache, hasLength(3));
    });

    test('clipIdCache entries can be overwritten', () {
      provider.clipIdCache['key'] = 10;
      provider.clipIdCache['key'] = 20;
      expect(provider.clipIdCache['key'], 20);
    });

    test('clipIdCache entries can be removed', () {
      provider.clipIdCache['key'] = 5;
      provider.clipIdCache.remove('key');
      expect(provider.clipIdCache.containsKey('key'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 6: Notification Behavior
  // ═══════════════════════════════════════════════════════════════════════════

  group('Notification behavior', () {
    test('setAutoTriggerAudio notifies listeners', () {
      provider.setAutoTriggerAudio(false);
      expect(notifyCount, 1);
    });

    test('setAutoTriggerAudio notifies even when setting same value', () {
      // Already true, setting true again still notifies (unconditional)
      provider.setAutoTriggerAudio(true);
      expect(notifyCount, 1);
    });

    test('setAleAutoSync notifies listeners', () {
      provider.setAleAutoSync(false);
      expect(notifyCount, 1);
    });

    test('setAleAutoSync notifies even when setting same value', () {
      provider.setAleAutoSync(true);
      expect(notifyCount, 1);
    });

    test('multiple configuration changes accumulate notifications', () {
      provider.setAutoTriggerAudio(false);
      provider.setAleAutoSync(false);
      provider.setAutoTriggerAudio(true);
      expect(notifyCount, 3);
    });

    test('setBetAmount does NOT notify listeners', () {
      provider.setBetAmount(10.0);
      expect(notifyCount, 0);
    });

    test('setTotalReels does NOT notify listeners', () {
      provider.setTotalReels(6);
      expect(notifyCount, 0);
    });

    test('setLowerZoneTabIndex does NOT notify listeners', () {
      provider.setLowerZoneTabIndex(5);
      expect(notifyCount, 0);
    });

    test('setLowerZoneExpanded does NOT notify listeners', () {
      provider.setLowerZoneExpanded(true);
      expect(notifyCount, 0);
    });

    test('setLowerZoneHeight does NOT notify listeners', () {
      provider.setLowerZoneHeight(500.0);
      expect(notifyCount, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 7: Symbol Detection Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  group('containsWild', () {
    test('returns false for null', () {
      expect(provider.containsWild(null), isFalse);
    });

    test('returns false for empty list', () {
      expect(provider.containsWild([]), isFalse);
    });

    test('returns true when list contains 0 (wild)', () {
      expect(provider.containsWild([1, 2, 0, 3]), isTrue);
    });

    test('returns true when list contains 10 (wild)', () {
      expect(provider.containsWild([1, 2, 10, 3]), isTrue);
    });

    test('returns true when list contains both 0 and 10', () {
      expect(provider.containsWild([0, 10]), isTrue);
    });

    test('returns false when no wild symbols', () {
      expect(provider.containsWild([1, 2, 3, 4, 5]), isFalse);
    });

    test('returns false for list with 9 (scatter, not wild)', () {
      expect(provider.containsWild([9]), isFalse);
    });
  });

  group('containsScatter', () {
    test('returns false for null', () {
      expect(provider.containsScatter(null), isFalse);
    });

    test('returns false for empty list', () {
      expect(provider.containsScatter([]), isFalse);
    });

    test('returns true when list contains 9', () {
      expect(provider.containsScatter([1, 9, 3]), isTrue);
    });

    test('returns false when no scatter symbol', () {
      expect(provider.containsScatter([0, 1, 2, 3, 10]), isFalse);
    });

    test('returns true when list is only scatter', () {
      expect(provider.containsScatter([9]), isTrue);
    });
  });

  group('containsSeven', () {
    test('returns false for null', () {
      expect(provider.containsSeven(null), isFalse);
    });

    test('returns false for empty list', () {
      expect(provider.containsSeven([]), isFalse);
    });

    test('returns true when list contains 7', () {
      expect(provider.containsSeven([1, 7, 3]), isTrue);
    });

    test('returns false when no seven', () {
      expect(provider.containsSeven([0, 1, 2, 3, 9, 10]), isFalse);
    });

    test('returns true for list of only sevens', () {
      expect(provider.containsSeven([7, 7, 7]), isTrue);
    });
  });

  group('containsHighPaySymbol', () {
    test('returns false for null', () {
      expect(provider.containsHighPaySymbol(null), isFalse);
    });

    test('returns false for empty list', () {
      expect(provider.containsHighPaySymbol([]), isFalse);
    });

    test('returns true for 0 (wild)', () {
      expect(provider.containsHighPaySymbol([0]), isTrue);
    });

    test('returns true for 7 (seven)', () {
      expect(provider.containsHighPaySymbol([7]), isTrue);
    });

    test('returns true for 8', () {
      expect(provider.containsHighPaySymbol([8]), isTrue);
    });

    test('returns true for 10 (wild)', () {
      expect(provider.containsHighPaySymbol([10]), isTrue);
    });

    test('returns false for low-pay only symbols', () {
      expect(provider.containsHighPaySymbol([1, 2, 3, 4, 5, 6]), isFalse);
    });

    test('returns false for scatter only (9 is not high pay)', () {
      expect(provider.containsHighPaySymbol([9]), isFalse);
    });

    test('returns true with mixed symbols including high pay', () {
      expect(provider.containsHighPaySymbol([1, 2, 3, 8, 5]), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 8: calculateWinLinePan
  // ═══════════════════════════════════════════════════════════════════════════

  group('calculateWinLinePan', () {
    test('returns 0.0 when result is null', () {
      expect(provider.calculateWinLinePan(0, null), 0.0);
    });

    test('returns 0.0 when lineIndex has no matching line win', () {
      final result = _makeSpinResult(lineWins: [
        const LineWin(
          lineIndex: 5,
          symbolId: 1,
          symbolName: 'cherry',
          matchCount: 3,
          winAmount: 10.0,
          positions: [
            [0, 1],
            [1, 1],
            [2, 1],
          ],
        ),
      ]);
      expect(provider.calculateWinLinePan(99, result), 0.0);
    });

    test('returns 0.0 when matching line win has empty positions', () {
      final result = _makeSpinResult(lineWins: [
        const LineWin(
          lineIndex: 0,
          symbolId: 1,
          symbolName: 'cherry',
          matchCount: 0,
          winAmount: 0.0,
          positions: [],
        ),
      ]);
      expect(provider.calculateWinLinePan(0, result), 0.0);
    });

    test('returns -1.0 for positions all on leftmost reel (reel 0)', () {
      // With default 5 reels, all positions at x=0 -> normalized=0 -> pan=-1
      final result = _makeSpinResult(lineWins: [
        const LineWin(
          lineIndex: 0,
          symbolId: 1,
          symbolName: 'cherry',
          matchCount: 3,
          winAmount: 10.0,
          positions: [
            [0, 0],
            [0, 1],
            [0, 2],
          ],
        ),
      ]);
      expect(provider.calculateWinLinePan(0, result), -1.0);
    });

    test('returns 1.0 for positions all on rightmost reel (reel 4)', () {
      // With 5 reels, all x=4 -> normalized=1 -> pan=1
      final result = _makeSpinResult(lineWins: [
        const LineWin(
          lineIndex: 0,
          symbolId: 1,
          symbolName: 'cherry',
          matchCount: 3,
          winAmount: 10.0,
          positions: [
            [4, 0],
            [4, 1],
            [4, 2],
          ],
        ),
      ]);
      expect(provider.calculateWinLinePan(0, result), 1.0);
    });

    test('returns 0.0 for positions centered at reel 2 on 5-reel grid', () {
      // avgX = 2, normalized = 2/4 = 0.5, pan = 0.5*2-1 = 0.0
      final result = _makeSpinResult(lineWins: [
        const LineWin(
          lineIndex: 0,
          symbolId: 1,
          symbolName: 'cherry',
          matchCount: 3,
          winAmount: 10.0,
          positions: [
            [2, 0],
            [2, 1],
            [2, 2],
          ],
        ),
      ]);
      expect(provider.calculateWinLinePan(0, result), closeTo(0.0, 0.001));
    });

    test('returns correct pan for spread positions', () {
      // Positions at reels 0, 1, 2 -> avgX = 1.0
      // normalized = 1/4 = 0.25, pan = 0.25*2-1 = -0.5
      final result = _makeSpinResult(lineWins: [
        const LineWin(
          lineIndex: 0,
          symbolId: 1,
          symbolName: 'cherry',
          matchCount: 3,
          winAmount: 10.0,
          positions: [
            [0, 0],
            [1, 1],
            [2, 2],
          ],
        ),
      ]);
      expect(provider.calculateWinLinePan(0, result), closeTo(-0.5, 0.001));
    });

    test('returns correct pan for right-biased positions', () {
      // Positions at reels 2, 3, 4 -> avgX = 3.0
      // normalized = 3/4 = 0.75, pan = 0.75*2-1 = 0.5
      final result = _makeSpinResult(lineWins: [
        const LineWin(
          lineIndex: 1,
          symbolId: 2,
          symbolName: 'bar',
          matchCount: 3,
          winAmount: 20.0,
          positions: [
            [2, 0],
            [3, 1],
            [4, 2],
          ],
        ),
      ]);
      expect(provider.calculateWinLinePan(1, result), closeTo(0.5, 0.001));
    });

    test('handles totalReels=1 edge case by returning 0', () {
      // When totalReels is 1, division by zero guard returns 0.0
      provider.setTotalReels(1);
      final result = _makeSpinResult(lineWins: [
        const LineWin(
          lineIndex: 0,
          symbolId: 1,
          symbolName: 'cherry',
          matchCount: 1,
          winAmount: 5.0,
          positions: [
            [0, 0],
          ],
        ),
      ]);
      expect(provider.calculateWinLinePan(0, result), 0.0);
    });

    test('respects setTotalReels for pan calculation', () {
      // 3 reels: positions at reel 0 -> normalized=0/2=0 -> pan=-1
      provider.setTotalReels(3);
      final result = _makeSpinResult(lineWins: [
        const LineWin(
          lineIndex: 0,
          symbolId: 1,
          symbolName: 'cherry',
          matchCount: 2,
          winAmount: 10.0,
          positions: [
            [0, 0],
            [0, 1],
          ],
        ),
      ]);
      expect(provider.calculateWinLinePan(0, result), -1.0);
    });

    test('pan is clamped between -1.0 and 1.0', () {
      // Even with extreme values, pan should be clamped
      final result = _makeSpinResult(lineWins: [
        const LineWin(
          lineIndex: 0,
          symbolId: 1,
          symbolName: 'cherry',
          matchCount: 3,
          winAmount: 10.0,
          positions: [
            [4, 0],
            [4, 1],
            [4, 2],
          ],
        ),
      ]);
      final pan = provider.calculateWinLinePan(0, result);
      expect(pan, greaterThanOrEqualTo(-1.0));
      expect(pan, lessThanOrEqualTo(1.0));
    });

    test('selects correct line from multiple line wins', () {
      final result = _makeSpinResult(lineWins: [
        const LineWin(
          lineIndex: 0,
          symbolId: 1,
          symbolName: 'cherry',
          matchCount: 3,
          winAmount: 10.0,
          positions: [
            [0, 0],
            [0, 1],
            [0, 2],
          ],
        ),
        const LineWin(
          lineIndex: 1,
          symbolId: 2,
          symbolName: 'bar',
          matchCount: 3,
          winAmount: 20.0,
          positions: [
            [4, 0],
            [4, 1],
            [4, 2],
          ],
        ),
      ]);
      // Line 0 => all at reel 0 => pan -1
      expect(provider.calculateWinLinePan(0, result), -1.0);
      // Line 1 => all at reel 4 => pan 1
      expect(provider.calculateWinLinePan(1, result), 1.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 9: Dispose safety
  // ═══════════════════════════════════════════════════════════════════════════

  group('Dispose', () {
    test('dispose does not throw', () {
      final p = SlotAudioProvider();
      expect(() => p.dispose(), returnsNormally);
    });

    test('can create multiple instances independently', () {
      final p1 = SlotAudioProvider();
      final p2 = SlotAudioProvider();

      p1.setAutoTriggerAudio(false);
      expect(p1.autoTriggerAudio, isFalse);
      expect(p2.autoTriggerAudio, isTrue);

      p1.dispose();
      p2.dispose();
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// TEST HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/// Create a minimal SlotLabSpinResult for testing.
SlotLabSpinResult _makeSpinResult({
  List<LineWin> lineWins = const [],
  double totalWin = 0.0,
  double winRatio = 0.0,
  double bet = 1.0,
}) {
  return SlotLabSpinResult(
    spinId: 'test_spin',
    grid: const [
      [1, 2, 3],
      [4, 5, 6],
      [7, 8, 9],
      [1, 2, 3],
      [4, 5, 6],
    ],
    bet: bet,
    totalWin: totalWin,
    winRatio: winRatio,
    lineWins: lineWins,
    featureTriggered: false,
    nearMiss: false,
    isFreeSpins: false,
    multiplier: 1.0,
    cascadeCount: 0,
  );
}
