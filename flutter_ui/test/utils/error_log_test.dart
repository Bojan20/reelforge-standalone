/// H-011 — Tests for the silentCatch / silentRun / silentCatchAsync helpers.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/utils/error_log.dart';

void main() {
  group('silentCatch', () {
    test('returns the callback result when no exception fires', () {
      final result = silentCatch<int>('happy path', () => 42);
      expect(result, 42);
    });

    test('returns null when the callback throws', () {
      final result = silentCatch<int>('error path', () {
        throw StateError('boom');
      });
      expect(result, isNull);
    });

    test('handles a non-Error throw (string, dynamic) gracefully', () {
      final result = silentCatch<int>('weird throw', () {
        throw 'a literal string';
      });
      expect(result, isNull);
    });
  });

  group('silentCatchOr', () {
    test('returns callback result on success', () {
      final result =
          silentCatchOr<List<int>>('list path', const [1, 2], () => [3, 4, 5]);
      expect(result, [3, 4, 5]);
    });

    test('returns fallback on throw', () {
      final result = silentCatchOr<List<int>>('list path', const [1, 2], () {
        throw RangeError('out of bounds');
      });
      expect(result, [1, 2]);
    });
  });

  group('silentRun', () {
    test('runs the action when it does not throw', () {
      var ran = false;
      silentRun('happy', () {
        ran = true;
      });
      expect(ran, isTrue);
    });

    test('swallows the throw without rethrow', () {
      // Test framework would fail if the throw escapes.
      silentRun('throws', () {
        throw FormatException('bad input');
      });
      // Reached without rethrow → success.
    });
  });

  group('silentCatchAsync', () {
    test('returns the awaited value on success', () async {
      final result = await silentCatchAsync<int>(
        'async happy',
        () async => 7,
      );
      expect(result, 7);
    });

    test('returns null on synchronous throw inside the future body', () async {
      final result = await silentCatchAsync<int>('async sync throw', () async {
        throw StateError('inside');
      });
      expect(result, isNull);
    });

    test('returns null on asynchronous throw', () async {
      final result = await silentCatchAsync<int>('async future throw', () {
        return Future<int>.error(Exception('later'));
      });
      expect(result, isNull);
    });
  });
}
