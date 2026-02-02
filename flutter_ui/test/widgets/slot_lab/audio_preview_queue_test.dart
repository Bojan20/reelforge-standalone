/// Audio Preview Queue Tests (P12.1.13)
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/slot_lab/audio_preview_queue.dart';

void main() {
  group('AudioQueueItem', () {
    test('creates with required fields', () {
      final item = AudioQueueItem(
        id: 'test_1',
        audioPath: '/audio/test.wav',
        displayName: 'Test Audio',
      );

      expect(item.id, 'test_1');
      expect(item.audioPath, '/audio/test.wav');
      expect(item.displayName, 'Test Audio');
      expect(item.duration, isNull);
    });

    test('fileName extracts last path component', () {
      final item = AudioQueueItem(
        id: 'test_1',
        audioPath: '/path/to/audio/sound.wav',
        displayName: 'Sound',
      );

      expect(item.fileName, 'sound.wav');
    });

    test('handles path with no separators', () {
      final item = AudioQueueItem(
        id: 'test_1',
        audioPath: 'sound.wav',
        displayName: 'Sound',
      );

      expect(item.fileName, 'sound.wav');
    });

    test('addedAt is set to now if not provided', () {
      final before = DateTime.now();
      final item = AudioQueueItem(
        id: 'test_1',
        audioPath: '/audio/test.wav',
        displayName: 'Test',
      );
      final after = DateTime.now();

      expect(item.addedAt.isAfter(before.subtract(const Duration(seconds: 1))), true);
      expect(item.addedAt.isBefore(after.add(const Duration(seconds: 1))), true);
    });
  });

  group('QueuePlaybackState', () {
    test('has all expected values', () {
      expect(QueuePlaybackState.values, contains(QueuePlaybackState.stopped));
      expect(QueuePlaybackState.values, contains(QueuePlaybackState.playing));
      expect(QueuePlaybackState.values, contains(QueuePlaybackState.paused));
    });
  });
}
