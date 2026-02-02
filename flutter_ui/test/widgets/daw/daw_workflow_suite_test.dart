/// DAW P2 Workflow Suite Tests
///
/// Tests for:
/// - P2-DAW-6: Marker System (5 tests)
/// - P2-DAW-7: Clip Gain Envelope (3 tests)
/// - P2-DAW-8: Track Icon Picker (3 tests)
/// - P2-DAW-9: Quick Commands Service (3 tests)
/// - P2-DAW-10: Session Template Service (3 tests)
/// - P2-DAW-11: Workspace Layouts (3 tests)
///
/// Created: 2026-02-02
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fluxforge_ui/widgets/daw/marker_system.dart';
import 'package:fluxforge_ui/widgets/daw/clip_gain_envelope.dart';
import 'package:fluxforge_ui/widgets/mixer/track_icon_picker.dart';
import 'package:fluxforge_ui/services/quick_commands_service.dart';
import 'package:fluxforge_ui/services/session_template_service.dart';
import 'package:fluxforge_ui/models/workspace_window_layout.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // P2-DAW-6: MARKER SYSTEM TESTS
  // ═══════════════════════════════════════════════════════════════════════════
  group('MarkerSystem', () {
    test('DawMarker creates with default category', () {
      final marker = DawMarker(
        id: 'test_1',
        time: 5.0,
        name: 'Verse 1',
      );

      expect(marker.id, 'test_1');
      expect(marker.time, 5.0);
      expect(marker.name, 'Verse 1');
      expect(marker.category, MarkerCategory.generic);
      expect(marker.color, MarkerCategory.generic.color);
    });

    test('DawMarker supports all categories', () {
      for (final category in MarkerCategory.values) {
        final marker = DawMarker(
          id: 'test_${category.name}',
          time: 1.0,
          name: 'Test',
          category: category,
        );

        expect(marker.category, category);
        expect(marker.color, category.color);
      }

      // Verify specific category colors
      expect(MarkerCategory.verse.color, const Color(0xFF4A9EFF));
      expect(MarkerCategory.chorus.color, const Color(0xFF40FF90));
      expect(MarkerCategory.drop.color, const Color(0xFFFF4081));
    });

    test('DawMarker serialization roundtrip', () {
      final original = DawMarker(
        id: 'marker_123',
        time: 42.5,
        name: 'Chorus',
        category: MarkerCategory.chorus,
        notes: 'Main chorus section',
      );

      final json = original.toJson();
      final restored = DawMarker.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.time, original.time);
      expect(restored.name, original.name);
      expect(restored.category, original.category);
      expect(restored.notes, original.notes);
    });

    test('DawMarker copyWith creates modified copy', () {
      final original = DawMarker(
        id: 'test_1',
        time: 10.0,
        name: 'Original',
        category: MarkerCategory.verse,
      );

      final modified = original.copyWith(
        time: 20.0,
        name: 'Modified',
        category: MarkerCategory.chorus,
      );

      expect(modified.id, 'test_1'); // Unchanged
      expect(modified.time, 20.0);
      expect(modified.name, 'Modified');
      expect(modified.category, MarkerCategory.chorus);
    });

    test('DawMarker converts to TimelineMarker', () {
      final dawMarker = DawMarker(
        id: 'test_1',
        time: 15.5,
        name: 'Bridge',
        category: MarkerCategory.bridge,
      );

      final timelineMarker = dawMarker.toTimelineMarker();

      expect(timelineMarker.id, dawMarker.id);
      expect(timelineMarker.time, dawMarker.time);
      expect(timelineMarker.name, dawMarker.name);
      expect(timelineMarker.color, MarkerCategory.bridge.color);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P2-DAW-7: CLIP GAIN ENVELOPE TESTS
  // ═══════════════════════════════════════════════════════════════════════════
  group('ClipGainEnvelope', () {
    test('GainEnvelopePoint dB conversion', () {
      // Unity gain
      final unity = GainEnvelopePoint(time: 0.5, gain: 1.0);
      expect(unity.dB, closeTo(0.0, 0.01));

      // +6dB (gain = 2.0)
      final boost = GainEnvelopePoint(time: 0.5, gain: 2.0);
      expect(boost.dB, closeTo(6.02, 0.1));

      // -6dB (gain = 0.5)
      final cut = GainEnvelopePoint(time: 0.5, gain: 0.5);
      expect(cut.dB, closeTo(-6.02, 0.1));

      // Near zero should return -60dB
      final silence = GainEnvelopePoint(time: 0.5, gain: 0.0001);
      expect(silence.dB, -60.0);
    });

    test('ClipGainEnvelope interpolation', () {
      final envelope = ClipGainEnvelope(points: [
        const GainEnvelopePoint(time: 0.0, gain: 1.0),
        const GainEnvelopePoint(time: 0.5, gain: 2.0),
        const GainEnvelopePoint(time: 1.0, gain: 0.5),
      ]);

      // At exact points
      expect(envelope.gainAt(0.0), 1.0);
      expect(envelope.gainAt(0.5), 2.0);
      expect(envelope.gainAt(1.0), 0.5);

      // Interpolated values
      expect(envelope.gainAt(0.25), closeTo(1.5, 0.01)); // Midpoint 1.0-2.0
      expect(envelope.gainAt(0.75), closeTo(1.25, 0.01)); // Midpoint 2.0-0.5

      // Before/after range
      expect(envelope.gainAt(-0.1), 1.0);
      expect(envelope.gainAt(1.1), 0.5);
    });

    test('ClipGainEnvelope serialization', () {
      final original = ClipGainEnvelope(points: [
        const GainEnvelopePoint(time: 0.0, gain: 1.0),
        const GainEnvelopePoint(time: 0.5, gain: 1.5),
      ]);

      final json = original.toJson();
      final restored = ClipGainEnvelope.fromJson(json);

      expect(restored.points.length, 2);
      expect(restored.points[0].time, 0.0);
      expect(restored.points[0].gain, 1.0);
      expect(restored.points[1].time, 0.5);
      expect(restored.points[1].gain, 1.5);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P2-DAW-8: TRACK ICON PICKER TESTS
  // ═══════════════════════════════════════════════════════════════════════════
  group('TrackIconPicker', () {
    test('TrackIconCategory has all required values', () {
      expect(TrackIconCategory.values.length, greaterThanOrEqualTo(10));

      // Check essential categories
      expect(TrackIconCategory.values.contains(TrackIconCategory.drums), true);
      expect(TrackIconCategory.values.contains(TrackIconCategory.bass), true);
      expect(TrackIconCategory.values.contains(TrackIconCategory.vocals), true);
      expect(TrackIconCategory.values.contains(TrackIconCategory.master), true);
    });

    test('TrackIcons has icons for all categories', () {
      for (final category in TrackIconCategory.values) {
        final icons = TrackIcons.byCategory[category];
        expect(icons, isNotNull, reason: 'Category ${category.name} should have icons');
        expect(icons!.isNotEmpty, true, reason: 'Category ${category.name} should have at least one icon');
      }
    });

    test('TrackIcons.all returns all icons', () {
      final allIcons = TrackIcons.all;
      expect(allIcons.length, greaterThan(40)); // Should have 50+ icons

      // Ensure no duplicates affect total count
      final uniqueIcons = allIcons.toSet();
      expect(uniqueIcons.length, allIcons.length);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P2-DAW-9: QUICK COMMANDS SERVICE TESTS
  // ═══════════════════════════════════════════════════════════════════════════
  group('QuickCommandsService', () {
    test('getDawCommands returns commands with callbacks', () {
      var undoCalled = false;
      var saveCalled = false;

      final commands = QuickCommandsService.getDawCommands(
        onUndo: () => undoCalled = true,
        onSaveProject: () => saveCalled = true,
      );

      // Should have multiple commands
      expect(commands.length, greaterThanOrEqualTo(2));

      // Find and execute undo command
      final undoCmd = commands.where((c) => c.label == 'Undo').first;
      undoCmd.onExecute();
      expect(undoCalled, true);

      // Find and execute save command
      final saveCmd = commands.where((c) => c.label == 'Save Project').first;
      saveCmd.onExecute();
      expect(saveCalled, true);
    });

    test('DawCommand has category', () {
      final commands = QuickCommandsService.getDawCommands(
        onUndo: () {},
        onZoomIn: () {},
        onAddAudioTrack: () {},
      );

      // Check that commands have expected categories
      final undoCmd = commands.whereType<DawCommand>().where((c) => c.label == 'Undo').first;
      expect(undoCmd.category, CommandCategory.edit);

      final zoomCmd = commands.whereType<DawCommand>().where((c) => c.label == 'Zoom In').first;
      expect(zoomCmd.category, CommandCategory.view);

      final trackCmd = commands.whereType<DawCommand>().where((c) => c.label == 'Add Audio Track').first;
      expect(trackCmd.category, CommandCategory.track);
    });

    test('getByCategory filters correctly', () {
      final commands = QuickCommandsService.getDawCommands(
        onUndo: () {},
        onRedo: () {},
        onZoomIn: () {},
        onZoomOut: () {},
      );

      final editCommands = QuickCommandsService.getByCategory(commands, CommandCategory.edit);
      final viewCommands = QuickCommandsService.getByCategory(commands, CommandCategory.view);

      expect(editCommands.length, 2); // Undo + Redo
      expect(viewCommands.length, 2); // Zoom In + Zoom Out
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P2-DAW-10: SESSION TEMPLATE SERVICE TESTS
  // ═══════════════════════════════════════════════════════════════════════════
  group('SessionTemplateService', () {
    test('BuiltInSessionTemplates has 5 templates', () {
      expect(BuiltInSessionTemplates.all.length, 5);

      // Verify each built-in template exists
      expect(BuiltInSessionTemplates.mixing.id, 'builtin_mixing');
      expect(BuiltInSessionTemplates.mastering.id, 'builtin_mastering');
      expect(BuiltInSessionTemplates.recording.id, 'builtin_recording');
      expect(BuiltInSessionTemplates.podcast.id, 'builtin_podcast');
      expect(BuiltInSessionTemplates.soundDesign.id, 'builtin_sound_design');
    });

    test('SessionTemplate serialization roundtrip', () {
      const original = SessionTemplate(
        id: 'test_template',
        name: 'Test Session',
        description: 'A test template',
        category: 'Custom',
        tempo: 128.0,
        timeSignatureNumerator: 3,
        timeSignatureDenominator: 4,
        tracks: [
          TrackTemplate(name: 'Track 1', volume: 0.8, pan: -0.5),
          TrackTemplate(name: 'Track 2', volume: 1.0, pan: 0.5),
        ],
      );

      final json = original.toJson();
      final restored = SessionTemplate.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.description, original.description);
      expect(restored.tempo, original.tempo);
      expect(restored.timeSignatureNumerator, original.timeSignatureNumerator);
      expect(restored.tracks.length, 2);
      expect(restored.tracks[0].name, 'Track 1');
      expect(restored.tracks[0].volume, 0.8);
      expect(restored.tracks[1].pan, 0.5);
    });

    test('TrackTemplate defaults are correct', () {
      const track = TrackTemplate(name: 'Default Track');

      expect(track.volume, 1.0);
      expect(track.pan, 0.0);
      expect(track.insertPlugins, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P2-DAW-11: WORKSPACE LAYOUTS TESTS
  // ═══════════════════════════════════════════════════════════════════════════
  group('WorkspaceWindowLayout', () {
    test('BuiltInWindowLayouts has 3 presets', () {
      expect(BuiltInWindowLayouts.all.length, 3);

      expect(BuiltInWindowLayouts.mix.id, 'builtin_mix');
      expect(BuiltInWindowLayouts.edit.id, 'builtin_edit');
      expect(BuiltInWindowLayouts.master.id, 'builtin_master');
    });

    test('WindowBounds serialization', () {
      const original = WindowBounds(x: 100, y: 200, width: 800, height: 600);

      final json = original.toJson();
      final restored = WindowBounds.fromJson(json);

      expect(restored.x, 100);
      expect(restored.y, 200);
      expect(restored.width, 800);
      expect(restored.height, 600);
    });

    test('PanelConfig defaults and serialization', () {
      const config = PanelConfig(visible: true, width: 300, expanded: true);

      final json = config.toJson();
      final restored = PanelConfig.fromJson(json);

      expect(restored.visible, true);
      expect(restored.width, 300);
      expect(restored.expanded, true);

      // Default values
      const defaultConfig = PanelConfig();
      expect(defaultConfig.visible, true);
      expect(defaultConfig.width, isNull);
    });
  });
}
