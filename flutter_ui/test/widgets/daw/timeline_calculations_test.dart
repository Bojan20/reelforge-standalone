/// Timeline Calculation Tests
///
/// Tests for DAW timeline math utilities:
/// - Pixels ↔ seconds conversion
/// - Snap-to-grid calculations
/// - BPM to milliseconds
/// - Time signature handling
/// - SMPTE timecode formatting
/// - Clip overlap detection
/// - Crossfade duration
@Tags(['widget'])
library;

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/timeline_models.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // Pixels ↔ Seconds Conversion
  // ═══════════════════════════════════════════════════════════════════════════

  group('Pixels-to-seconds conversion', () {
    test('100 pixels at 100 px/sec = 1 second', () {
      const pixelsPerSecond = 100.0;
      const pixels = 100.0;
      final seconds = pixels / pixelsPerSecond;
      expect(seconds, 1.0);
    });

    test('different zoom levels', () {
      // Zoom in (more pixels per second = wider view)
      const zoomIn = 200.0; // px/sec
      expect(100.0 / zoomIn, 0.5); // 100px = 0.5s at zoom in

      // Zoom out (fewer pixels per second = compressed view)
      const zoomOut = 50.0; // px/sec
      expect(100.0 / zoomOut, 2.0); // 100px = 2s at zoom out
    });

    test('seconds-to-pixels conversion', () {
      const pixelsPerSecond = 150.0;
      const seconds = 3.5;
      final pixels = seconds * pixelsPerSecond;
      expect(pixels, 525.0);
    });

    test('roundtrip preserves value', () {
      const pps = 120.0;
      const originalSeconds = 5.25;
      final pixels = originalSeconds * pps;
      final restored = pixels / pps;
      expect(restored, closeTo(originalSeconds, 0.0001));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Snap-to-Grid Calculations
  // ═══════════════════════════════════════════════════════════════════════════

  group('Snap-to-grid', () {
    test('snap to quarter notes at 120 BPM', () {
      // 120 BPM = 2 beats per second
      // Quarter note = 1 beat = 0.5 seconds
      final result = snapToGrid(0.37, 1.0, 120.0);
      expect(result, closeTo(0.5, 0.001));
    });

    test('snap to eighth notes at 120 BPM', () {
      // 120 BPM = 2 beats per second
      // gridInterval = snapValue / beatsPerSecond = 0.5 / 2 = 0.25s
      // time 0.13 -> round(0.13/0.25) = round(0.52) = 1 -> 0.25s
      final result = snapToGrid(0.13, 0.5, 120.0);
      expect(result, closeTo(0.25, 0.01));
    });

    test('snap at 60 BPM aligns to whole seconds', () {
      // 60 BPM = 1 beat per second
      // Quarter note = 1 beat = 1 second
      final result = snapToGrid(2.3, 1.0, 60.0);
      expect(result, closeTo(2.0, 0.001));
    });

    test('snap to bar at 120 BPM in 4/4', () {
      // 1 bar = 4 beats = 2 seconds at 120 BPM
      final result = snapToGrid(3.7, 4.0, 120.0);
      expect(result, closeTo(4.0, 0.001));
    });

    test('time 0.0 always snaps to 0.0', () {
      expect(snapToGrid(0.0, 1.0, 120.0), 0.0);
      expect(snapToGrid(0.0, 0.5, 90.0), 0.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BPM to Milliseconds Conversion
  // ═══════════════════════════════════════════════════════════════════════════

  group('BPM to milliseconds', () {
    double bpmToMsPerBeat(double bpm) {
      return 60000.0 / bpm;
    }

    test('60 BPM = 1000ms per beat', () {
      expect(bpmToMsPerBeat(60), 1000.0);
    });

    test('120 BPM = 500ms per beat', () {
      expect(bpmToMsPerBeat(120), 500.0);
    });

    test('140 BPM ~ 428.6ms per beat', () {
      expect(bpmToMsPerBeat(140), closeTo(428.57, 0.1));
    });

    test('180 BPM ~ 333.3ms per beat', () {
      expect(bpmToMsPerBeat(180), closeTo(333.33, 0.1));
    });

    test('bar duration in 4/4 time', () {
      double barDurationMs(double bpm, int beatsPerBar) {
        return bpmToMsPerBeat(bpm) * beatsPerBar;
      }
      expect(barDurationMs(120, 4), 2000.0);
      expect(barDurationMs(120, 3), 1500.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Time Signature Handling
  // ═══════════════════════════════════════════════════════════════════════════

  group('Time signature handling', () {
    test('4/4: 4 beats per bar', () {
      const numerator = 4;
      const denominator = 4;
      expect(numerator, 4);
      expect(denominator, 4);
    });

    test('3/4: 3 beats per bar (waltz)', () {
      const numerator = 3;
      final barDuration = 60.0 / 120.0 * numerator; // seconds at 120 BPM
      expect(barDuration, 1.5);
    });

    test('6/8: 6 eighth-note beats per bar', () {
      const numerator = 6;
      const denominator = 8;
      // Effective duration: 6 * (beat_duration / 2) because eighth notes
      final eighthNoteDuration = 60.0 / 120.0 / 2; // 0.25s at 120 BPM
      final barDuration = eighthNoteDuration * numerator;
      expect(barDuration, 1.5);
      expect(denominator, 8);
    });

    test('7/8: asymmetric meter', () {
      const numerator = 7;
      const denominator = 8;
      final eighthNoteDuration = 60.0 / 120.0 / 2;
      final barDuration = eighthNoteDuration * numerator;
      expect(barDuration, closeTo(1.75, 0.001));
      expect(denominator, 8);
    });

    test('formatBars produces correct bar.beat format', () {
      // At 120 BPM, 4/4: beat = 0.5s, bar = 2.0s
      expect(formatBars(0.0, 120, 4), '1.1');      // Start
      expect(formatBars(0.5, 120, 4), '1.2');      // Beat 2
      expect(formatBars(1.0, 120, 4), '1.3');      // Beat 3
      expect(formatBars(1.5, 120, 4), '1.4');      // Beat 4
      expect(formatBars(2.0, 120, 4), '2.1');      // Bar 2
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SMPTE Timecode Formatting
  // ═══════════════════════════════════════════════════════════════════════════

  group('SMPTE timecode formatting', () {
    test('0 seconds = 00:00:00', () {
      expect(formatTimecode(0.0), '00:00:00');
    });

    test('1 second at 30fps = 00:01:00', () {
      expect(formatTimecode(1.0, fps: 30), '00:01:00');
    });

    test('59.5 seconds at 30fps = 00:59:15', () {
      expect(formatTimecode(59.5, fps: 30), '00:59:15');
    });

    test('60 seconds = 01:00:00', () {
      expect(formatTimecode(60.0), '01:00:00');
    });

    test('90.5 seconds = 01:30:15', () {
      expect(formatTimecode(90.5, fps: 30), '01:30:15');
    });

    test('frame calculation at 24fps', () {
      // 0.5 seconds * 24 fps = 12 frames
      expect(formatTimecode(0.5, fps: 24), '00:00:12');
    });

    test('frame calculation at 25fps', () {
      // 0.5 seconds * 25 fps = 12 frames (floor)
      expect(formatTimecode(0.5, fps: 25), '00:00:12');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Clip Overlap Detection
  // ═══════════════════════════════════════════════════════════════════════════

  group('Clip overlap detection', () {
    bool clipsOverlap(double start1, double end1, double start2, double end2) {
      return start1 < end2 && start2 < end1;
    }

    test('overlapping clips detected', () {
      expect(clipsOverlap(0.0, 2.0, 1.0, 3.0), true);
    });

    test('non-overlapping clips (gap)', () {
      expect(clipsOverlap(0.0, 1.0, 2.0, 3.0), false);
    });

    test('adjacent clips (touching) do not overlap', () {
      expect(clipsOverlap(0.0, 1.0, 1.0, 2.0), false);
    });

    test('fully contained clip', () {
      expect(clipsOverlap(0.0, 5.0, 1.0, 3.0), true);
    });

    test('identical clips overlap', () {
      expect(clipsOverlap(1.0, 3.0, 1.0, 3.0), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Crossfade Duration Calculations
  // ═══════════════════════════════════════════════════════════════════════════

  group('Crossfade duration', () {
    test('overlap region defines crossfade duration', () {
      // Clip A: 0-3s, Clip B: 2-5s → overlap = 1s
      const startA = 0.0, endA = 3.0;
      const startB = 2.0, endB = 5.0;
      final overlapStart = math.max(startA, startB); // 2.0
      final overlapEnd = math.min(endA, endB);       // 3.0
      final crossfadeDuration = overlapEnd - overlapStart;
      expect(crossfadeDuration, 1.0);
    });

    test('no overlap means no crossfade', () {
      const startA = 0.0, endA = 1.0;
      const startB = 2.0, endB = 3.0;
      final overlapStart = math.max(startA, startB);
      final overlapEnd = math.min(endA, endB);
      final crossfadeDuration = math.max(0.0, overlapEnd - overlapStart);
      expect(crossfadeDuration, 0.0);
    });

    test('large overlap', () {
      const startA = 0.0, endA = 10.0;
      const startB = 1.0, endB = 8.0;
      final overlapStart = math.max(startA, startB); // 1.0
      final overlapEnd = math.min(endA, endB);       // 8.0
      final crossfadeDuration = overlapEnd - overlapStart;
      expect(crossfadeDuration, 7.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Time Display Mode
  // ═══════════════════════════════════════════════════════════════════════════

  group('Time display modes', () {
    test('formatTime in bars mode', () {
      final result = formatTime(2.5, TimeDisplayMode.bars, tempo: 120, timeSignatureNum: 4);
      // 2.5s at 120 BPM = 5 beats, 4/4 time = bar 2, beat 2
      expect(result, '2.2');
    });

    test('formatTime in timecode mode', () {
      final result = formatTime(65.5, TimeDisplayMode.timecode);
      expect(result, '01:05:15'); // 1 min, 5 sec, 15 frames
    });

    test('formatTime in samples mode', () {
      final result = formatTime(1.0, TimeDisplayMode.samples, sampleRate: 48000);
      expect(result, '48000');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Snap to Events
  // ═══════════════════════════════════════════════════════════════════════════

  group('Snap to events', () {
    test('snaps to nearest clip boundary within threshold', () {
      final clips = [
        TimelineClip(
          id: '1',
          trackId: '0',
          startTime: 2.0,
          duration: 3.0,
          name: 'Clip A',
        ),
      ];

      // Time 1.95 should snap to clip start at 2.0 (within 0.1 threshold)
      final result = snapToEvents(1.95, clips, threshold: 0.1);
      expect(result, 2.0);
    });

    test('snaps to clip end boundary', () {
      final clips = [
        TimelineClip(
          id: '1',
          trackId: '0',
          startTime: 0.0,
          duration: 3.0,
          name: 'Clip A',
        ),
      ];

      // Time 2.95 should snap to clip end at 3.0
      final result = snapToEvents(2.95, clips, threshold: 0.1);
      expect(result, 3.0);
    });

    test('no snap when outside threshold', () {
      final clips = [
        TimelineClip(
          id: '1',
          trackId: '0',
          startTime: 5.0,
          duration: 2.0,
          name: 'Clip A',
        ),
      ];

      // Time 1.0 is far from clip at 5.0
      final result = snapToEvents(1.0, clips, threshold: 0.1);
      expect(result, 1.0); // No snap
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LoopRegion Model
  // ═══════════════════════════════════════════════════════════════════════════

  group('LoopRegion', () {
    test('default values', () {
      const loop = LoopRegion(start: 0.0, end: 0.0);
      expect(loop.start, 0.0);
      expect(loop.end, 0.0);
    });

    test('copyWith preserves unchanged', () {
      const loop = LoopRegion(start: 1.0, end: 5.0);
      final modified = loop.copyWith(end: 10.0);
      expect(modified.start, 1.0);
      expect(modified.end, 10.0);
    });
  });
}
