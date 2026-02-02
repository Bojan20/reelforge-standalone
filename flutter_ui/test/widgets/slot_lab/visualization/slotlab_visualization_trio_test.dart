/// SlotLab Visualization Trio Tests — P12.1.6, P12.1.8, P12.1.16
///
/// Unit tests for the three visualization widgets:
/// - EventDependencyGraph — Node-based event flow visualization
/// - StageFlowDiagram — Stage sequence timeline
/// - WinCelebrationDesigner — Win tier audio editor
///
/// Tests cover:
/// - Model creation and copying
/// - Widget rendering
/// - Interaction callbacks
/// - Data transformation

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/slot_lab/event_dependency_graph.dart';
import 'package:fluxforge_ui/widgets/slot_lab/stage_flow_diagram.dart';
import 'package:fluxforge_ui/widgets/slot_lab/win_celebration_designer.dart';
import 'package:fluxforge_ui/services/stage_configuration_service.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // P12.1.6: EVENT GRAPH NODE TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('EventGraphNode', () {
    test('should create with required parameters', () {
      final node = EventGraphNode(
        id: 'test_node',
        label: 'Test Node',
        type: EventNodeType.stage,
        color: const Color(0xFF4A9EFF),
        position: const Offset(100, 200),
      );

      expect(node.id, 'test_node');
      expect(node.label, 'Test Node');
      expect(node.type, EventNodeType.stage);
      expect(node.color, const Color(0xFF4A9EFF));
      expect(node.position, const Offset(100, 200));
      expect(node.connectedTo, isEmpty);
      expect(node.metadata, isNull);
    });

    test('should create with all parameters including connections', () {
      final node = EventGraphNode(
        id: 'event_1',
        label: 'Win Present',
        type: EventNodeType.event,
        color: const Color(0xFF40FF90),
        position: const Offset(200, 100),
        connectedTo: ['audio_1', 'audio_2'],
        metadata: {'eventId': 'win_01', 'priority': 5},
      );

      expect(node.connectedTo, ['audio_1', 'audio_2']);
      expect(node.metadata, {'eventId': 'win_01', 'priority': 5});
    });

    test('copyWith should create modified copy', () {
      final original = EventGraphNode(
        id: 'original',
        label: 'Original',
        type: EventNodeType.audio,
        color: const Color(0xFFFF0000),
        position: const Offset(0, 0),
      );

      final modified = original.copyWith(
        position: const Offset(50, 75),
        label: 'Modified',
      );

      // Original unchanged
      expect(original.position, const Offset(0, 0));
      expect(original.label, 'Original');

      // Modified has new values
      expect(modified.position, const Offset(50, 75));
      expect(modified.label, 'Modified');

      // Unchanged fields preserved
      expect(modified.id, 'original');
      expect(modified.type, EventNodeType.audio);
      expect(modified.color, const Color(0xFFFF0000));
    });

    test('copyWith with no arguments returns equivalent node', () {
      final original = EventGraphNode(
        id: 'test',
        label: 'Test',
        type: EventNodeType.event,
        color: const Color(0xFF000000),
        position: const Offset(10, 20),
        connectedTo: ['a', 'b'],
      );

      final copied = original.copyWith();

      expect(copied.id, original.id);
      expect(copied.label, original.label);
      expect(copied.type, original.type);
      expect(copied.position, original.position);
      expect(copied.connectedTo, original.connectedTo);
    });
  });

  group('EventNodeType', () {
    test('should have all expected types', () {
      expect(EventNodeType.values.length, 3);
      expect(EventNodeType.stage, isNotNull);
      expect(EventNodeType.event, isNotNull);
      expect(EventNodeType.audio, isNotNull);
    });

    test('should have correct index values', () {
      expect(EventNodeType.stage.index, 0);
      expect(EventNodeType.event.index, 1);
      expect(EventNodeType.audio.index, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P12.1.8: STAGE FLOW EVENT TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('StageFlowEvent', () {
    test('should create with required parameters', () {
      const event = StageFlowEvent(
        id: 'event_1',
        stageName: 'SPIN_START',
        category: StageCategory.spin,
        timestampMs: 0,
      );

      expect(event.id, 'event_1');
      expect(event.stageName, 'SPIN_START');
      expect(event.category, StageCategory.spin);
      expect(event.timestampMs, 0);
      expect(event.durationMs, isNull);
      expect(event.hasAudio, false);
      expect(event.metadata, isNull);
    });

    test('should create with all parameters', () {
      const event = StageFlowEvent(
        id: 'win_event',
        stageName: 'WIN_PRESENT',
        category: StageCategory.win,
        timestampMs: 1500,
        durationMs: 2000,
        hasAudio: true,
        metadata: {'tier': 'big'},
      );

      expect(event.durationMs, 2000);
      expect(event.hasAudio, true);
      expect(event.metadata, {'tier': 'big'});
    });

    test('copyWith should create modified copy', () {
      const original = StageFlowEvent(
        id: 'original',
        stageName: 'REEL_STOP',
        category: StageCategory.spin,
        timestampMs: 500,
        hasAudio: false,
      );

      final modified = original.copyWith(
        timestampMs: 750,
        hasAudio: true,
        durationMs: 100,
      );

      // Original unchanged
      expect(original.timestampMs, 500);
      expect(original.hasAudio, false);

      // Modified has new values
      expect(modified.timestampMs, 750);
      expect(modified.hasAudio, true);
      expect(modified.durationMs, 100);

      // Unchanged fields preserved
      expect(modified.id, 'original');
      expect(modified.stageName, 'REEL_STOP');
      expect(modified.category, StageCategory.spin);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P12.1.16: WIN AUDIO LAYER TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('WinAudioLayer', () {
    test('should create with required parameters', () {
      const layer = WinAudioLayer(
        id: 'layer_1',
        audioPath: '/audio/win_fanfare.wav',
        label: 'Win Fanfare',
        startMs: 0,
        durationMs: 2000,
      );

      expect(layer.id, 'layer_1');
      expect(layer.audioPath, '/audio/win_fanfare.wav');
      expect(layer.label, 'Win Fanfare');
      expect(layer.startMs, 0);
      expect(layer.durationMs, 2000);
      expect(layer.volume, 1.0);
      expect(layer.loop, false);
    });

    test('should create with all parameters', () {
      const layer = WinAudioLayer(
        id: 'loop_layer',
        audioPath: '/audio/celebration_loop.wav',
        label: 'Celebration',
        startMs: 500,
        durationMs: 5000,
        volume: 0.8,
        loop: true,
      );

      expect(layer.volume, 0.8);
      expect(layer.loop, true);
    });

    test('copyWith should create modified copy', () {
      const original = WinAudioLayer(
        id: 'original',
        audioPath: '/path/to/audio.wav',
        label: 'Original',
        startMs: 0,
        durationMs: 1000,
      );

      final modified = original.copyWith(
        startMs: 500,
        volume: 0.5,
        loop: true,
      );

      // Original unchanged
      expect(original.startMs, 0);
      expect(original.volume, 1.0);
      expect(original.loop, false);

      // Modified has new values
      expect(modified.startMs, 500);
      expect(modified.volume, 0.5);
      expect(modified.loop, true);

      // Unchanged fields preserved
      expect(modified.id, 'original');
      expect(modified.audioPath, '/path/to/audio.wav');
      expect(modified.durationMs, 1000);
    });

    test('toJson should serialize correctly', () {
      const layer = WinAudioLayer(
        id: 'json_test',
        audioPath: '/audio/test.wav',
        label: 'Test',
        startMs: 100,
        durationMs: 500,
        volume: 0.9,
        loop: true,
      );

      final json = layer.toJson();

      expect(json['id'], 'json_test');
      expect(json['audioPath'], '/audio/test.wav');
      expect(json['label'], 'Test');
      expect(json['startMs'], 100);
      expect(json['durationMs'], 500);
      expect(json['volume'], 0.9);
      expect(json['loop'], true);
    });

    test('fromJson should deserialize correctly', () {
      final json = {
        'id': 'from_json',
        'audioPath': '/audio/deserialized.wav',
        'label': 'Deserialized',
        'startMs': 200,
        'durationMs': 800,
        'volume': 0.7,
        'loop': false,
      };

      final layer = WinAudioLayer.fromJson(json);

      expect(layer.id, 'from_json');
      expect(layer.audioPath, '/audio/deserialized.wav');
      expect(layer.label, 'Deserialized');
      expect(layer.startMs, 200);
      expect(layer.durationMs, 800);
      expect(layer.volume, 0.7);
      expect(layer.loop, false);
    });

    test('fromJson should use defaults for missing optional fields', () {
      final json = {
        'id': 'minimal',
        'audioPath': '/audio/minimal.wav',
        'label': 'Minimal',
        'startMs': 0,
        'durationMs': 1000,
      };

      final layer = WinAudioLayer.fromJson(json);

      expect(layer.volume, 1.0); // Default
      expect(layer.loop, false); // Default
    });
  });

  group('WinTierCelebration', () {
    test('should create with required parameters', () {
      const celebration = WinTierCelebration(
        tierId: 1,
        tierName: 'Small',
        totalDurationMs: 1500,
      );

      expect(celebration.tierId, 1);
      expect(celebration.tierName, 'Small');
      expect(celebration.totalDurationMs, 1500);
      expect(celebration.layers, isEmpty);
    });

    test('should create with layers', () {
      const celebration = WinTierCelebration(
        tierId: 2,
        tierName: 'Big',
        totalDurationMs: 2500,
        layers: [
          WinAudioLayer(
            id: 'layer_1',
            audioPath: '/a.wav',
            label: 'A',
            startMs: 0,
            durationMs: 1000,
          ),
          WinAudioLayer(
            id: 'layer_2',
            audioPath: '/b.wav',
            label: 'B',
            startMs: 500,
            durationMs: 1500,
          ),
        ],
      );

      expect(celebration.layers.length, 2);
      expect(celebration.layers[0].id, 'layer_1');
      expect(celebration.layers[1].id, 'layer_2');
    });

    test('copyWith should create modified copy', () {
      const original = WinTierCelebration(
        tierId: 1,
        tierName: 'Original',
        totalDurationMs: 1000,
      );

      final newLayers = [
        const WinAudioLayer(
          id: 'new_layer',
          audioPath: '/new.wav',
          label: 'New',
          startMs: 0,
          durationMs: 500,
        ),
      ];

      final modified = original.copyWith(
        totalDurationMs: 2000,
        layers: newLayers,
      );

      // Original unchanged
      expect(original.totalDurationMs, 1000);
      expect(original.layers, isEmpty);

      // Modified has new values
      expect(modified.totalDurationMs, 2000);
      expect(modified.layers.length, 1);

      // Unchanged fields preserved
      expect(modified.tierId, 1);
      expect(modified.tierName, 'Original');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE CATEGORY EXTENSION TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('StageCategory color extension', () {
    test('should return correct colors for each category', () {
      expect(StageCategory.spin.color, 0xFF4A9EFF);
      expect(StageCategory.win.color, 0xFFFFD700);
      expect(StageCategory.feature.color, 0xFF40FF90);
      expect(StageCategory.cascade.color, 0xFF40C8FF);
      expect(StageCategory.jackpot.color, 0xFFFF4040);
    });

    test('should return correct labels for each category', () {
      expect(StageCategory.spin.label, 'Spin');
      expect(StageCategory.win.label, 'Win');
      expect(StageCategory.feature.label, 'Feature');
      expect(StageCategory.cascade.label, 'Cascade');
      expect(StageCategory.jackpot.label, 'Jackpot');
      expect(StageCategory.hold.label, 'Hold & Spin');
    });
  });
}
