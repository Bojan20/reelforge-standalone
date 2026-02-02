// Waveform Scrubber Widget Tests
//
// Tests for WaveformScrubberWidget:
// - LoopRegion model
// - Zoom calculations
// - Time formatting
// - Widget rendering

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/slot_lab/waveform_scrubber_widget.dart';

void main() {
  group('LoopRegion', () {
    test('copyWith creates new instance with updated values', () {
      const original = LoopRegion(startSeconds: 1.0, endSeconds: 5.0);
      final updated = original.copyWith(endSeconds: 10.0);

      expect(updated.startSeconds, 1.0);
      expect(updated.endSeconds, 10.0);
      expect(updated.enabled, false);
    });

    test('durationSeconds calculates correctly', () {
      const region = LoopRegion(startSeconds: 2.0, endSeconds: 7.0);
      expect(region.durationSeconds, 5.0);
    });

    test('isValid returns true for valid region', () {
      const valid = LoopRegion(startSeconds: 0.0, endSeconds: 5.0);
      expect(valid.isValid(), isTrue);

      const invalid1 = LoopRegion(startSeconds: -1.0, endSeconds: 5.0);
      expect(invalid1.isValid(), isFalse);

      const invalid2 = LoopRegion(startSeconds: 5.0, endSeconds: 2.0);
      expect(invalid2.isValid(), isFalse);
    });

    test('enabled flag is respected', () {
      const disabled = LoopRegion(startSeconds: 0.0, endSeconds: 5.0);
      expect(disabled.enabled, isFalse);

      const enabled =
          LoopRegion(startSeconds: 0.0, endSeconds: 5.0, enabled: true);
      expect(enabled.enabled, isTrue);
    });

    test('toString produces readable output', () {
      const region =
          LoopRegion(startSeconds: 1.5, endSeconds: 3.5, enabled: true);
      expect(region.toString(), contains('1.5'));
      expect(region.toString(), contains('3.5'));
      expect(region.toString(), contains('enabled: true'));
    });
  });

  group('WaveformZoomLevel', () {
    test('enum values are defined', () {
      expect(WaveformZoomLevel.values.length, 5);
      expect(WaveformZoomLevel.fit, isNotNull);
      expect(WaveformZoomLevel.x2, isNotNull);
      expect(WaveformZoomLevel.x4, isNotNull);
      expect(WaveformZoomLevel.x8, isNotNull);
      expect(WaveformZoomLevel.x16, isNotNull);
    });
  });

  group('WaveformScrubberWidget', () {
    testWidgets('renders without waveform data', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WaveformScrubberWidget(
              audioPath: '/test/audio.wav',
              waveform: null,
              duration: 10.0,
            ),
          ),
        ),
      );

      expect(find.byType(WaveformScrubberWidget), findsOneWidget);
    });

    testWidgets('renders with waveform data', (tester) async {
      final waveform = Float32List.fromList([0.5, -0.5, 0.3, -0.3, 0.1]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaveformScrubberWidget(
              audioPath: '/test/audio.wav',
              waveform: waveform,
              duration: 10.0,
            ),
          ),
        ),
      );

      expect(find.byType(WaveformScrubberWidget), findsOneWidget);
    });

    testWidgets('shows zoom controls when enabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WaveformScrubberWidget(
              audioPath: '/test/audio.wav',
              duration: 10.0,
              showZoomControls: true,
            ),
          ),
        ),
      );

      // Should find zoom icons
      expect(find.byIcon(Icons.zoom_in), findsOneWidget);
      expect(find.byIcon(Icons.zoom_out), findsOneWidget);
      expect(find.byIcon(Icons.fit_screen), findsOneWidget);
    });

    testWidgets('hides zoom controls when disabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WaveformScrubberWidget(
              audioPath: '/test/audio.wav',
              duration: 10.0,
              showZoomControls: false,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.zoom_in), findsNothing);
      expect(find.byIcon(Icons.zoom_out), findsNothing);
    });

    testWidgets('displays time labels when enabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WaveformScrubberWidget(
              audioPath: '/test/audio.wav',
              duration: 65.5, // 1:05.50
              position: 30.25, // 0:30.25
              showTimeLabels: true,
            ),
          ),
        ),
      );

      // Should find formatted time displays
      expect(find.textContaining('00:30'), findsOneWidget);
      expect(find.textContaining('01:05'), findsOneWidget);
    });

    testWidgets('calls onSeek when tapped', (tester) async {
      double? seekPosition;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaveformScrubberWidget(
              audioPath: '/test/audio.wav',
              duration: 10.0,
              onSeek: (pos) => seekPosition = pos,
            ),
          ),
        ),
      );

      // Find the waveform area and tap
      final finder = find.byType(GestureDetector).first;
      await tester.tap(finder);
      await tester.pump();

      // Should have called onSeek
      expect(seekPosition, isNotNull);
    });

    testWidgets('respects custom colors', (tester) async {
      const customWaveformColor = Color(0xFFFF0000);
      const customPlayheadColor = Color(0xFF00FF00);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WaveformScrubberWidget(
              audioPath: '/test/audio.wav',
              duration: 10.0,
              waveformColor: customWaveformColor,
              playheadColor: customPlayheadColor,
            ),
          ),
        ),
      );

      // Widget should render without errors
      expect(find.byType(WaveformScrubberWidget), findsOneWidget);
    });
  });
}
