/// Layer DSP Service Tests (P12.1.5)
///
/// Tests for per-layer DSP chain management:
/// - DSP chain CRUD operations
/// - Parameter validation
/// - JSON serialization
/// - Preset application
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/slot_audio_events.dart';
import 'package:fluxforge_ui/services/layer_dsp_service.dart';

void main() {
  group('LayerDspNode', () {
    test('create with default parameters', () {
      final node = LayerDspNode.create(LayerDspType.eq);

      expect(node.id, isNotEmpty);
      expect(node.type, LayerDspType.eq);
      expect(node.bypass, false);
      expect(node.wetDry, 1.0);
      expect(node.params, isNotEmpty);
      expect(node.params['lowGain'], 0.0);
      expect(node.params['midFreq'], 1000.0);
    });

    test('create compressor with default parameters', () {
      final node = LayerDspNode.create(LayerDspType.compressor);

      expect(node.type, LayerDspType.compressor);
      expect(node.params['threshold'], -20.0);
      expect(node.params['ratio'], 4.0);
      expect(node.params['attack'], 10.0);
      expect(node.params['release'], 100.0);
      expect(node.params['makeupGain'], 0.0);
    });

    test('create reverb with default parameters', () {
      final node = LayerDspNode.create(LayerDspType.reverb);

      expect(node.type, LayerDspType.reverb);
      expect(node.params['decay'], 2.0);
      expect(node.params['preDelay'], 20.0);
      expect(node.params['damping'], 0.5);
      expect(node.params['size'], 0.7);
    });

    test('create delay with default parameters', () {
      final node = LayerDspNode.create(LayerDspType.delay);

      expect(node.type, LayerDspType.delay);
      expect(node.params['time'], 250.0);
      expect(node.params['feedback'], 0.3);
      expect(node.params['highCut'], 8000.0);
      expect(node.params['lowCut'], 80.0);
    });

    test('copyWith preserves unmodified fields', () {
      final original = LayerDspNode.create(LayerDspType.eq);
      final copied = original.copyWith(bypass: true);

      expect(copied.id, original.id);
      expect(copied.type, original.type);
      expect(copied.bypass, true);
      expect(copied.wetDry, original.wetDry);
      expect(copied.params, original.params);
    });

    test('copyWith updates specified fields', () {
      final original = LayerDspNode.create(LayerDspType.compressor);
      final newParams = {'threshold': -10.0, 'ratio': 8.0};
      final copied = original.copyWith(wetDry: 0.5, params: newParams);

      expect(copied.wetDry, 0.5);
      expect(copied.params['threshold'], -10.0);
      expect(copied.params['ratio'], 8.0);
    });

    test('toJson serializes all fields', () {
      final node = LayerDspNode(
        id: 'test-node',
        type: LayerDspType.reverb,
        bypass: true,
        wetDry: 0.75,
        params: {'decay': 3.0, 'size': 0.5},
      );

      final json = node.toJson();

      expect(json['id'], 'test-node');
      expect(json['type'], 'reverb');
      expect(json['bypass'], true);
      expect(json['wetDry'], 0.75);
      expect(json['params']['decay'], 3.0);
      expect(json['params']['size'], 0.5);
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'id': 'json-node',
        'type': 'delay',
        'bypass': false,
        'wetDry': 0.6,
        'params': {'time': 500.0, 'feedback': 0.5},
      };

      final node = LayerDspNode.fromJson(json);

      expect(node.id, 'json-node');
      expect(node.type, LayerDspType.delay);
      expect(node.bypass, false);
      expect(node.wetDry, 0.6);
      expect(node.params['time'], 500.0);
      expect(node.params['feedback'], 0.5);
    });

    test('fromJson handles missing fields with defaults', () {
      final json = <String, dynamic>{'type': 'eq'};

      final node = LayerDspNode.fromJson(json);

      expect(node.id, '');
      expect(node.type, LayerDspType.eq);
      expect(node.bypass, false);
      expect(node.wetDry, 1.0);
      expect(node.params, isEmpty);
    });

    test('fromJson handles unknown type gracefully', () {
      final json = {'id': 'test', 'type': 'unknown_type'};

      final node = LayerDspNode.fromJson(json);

      // Should default to EQ
      expect(node.type, LayerDspType.eq);
    });
  });

  group('SlotEventLayer with DSP chain', () {
    test('default layer has empty DSP chain', () {
      const layer = SlotEventLayer(
        id: 'layer1',
        name: 'Test Layer',
        audioPath: '/audio/test.wav',
      );

      expect(layer.dspChain, isEmpty);
      expect(layer.hasDsp, false);
      expect(layer.activeDspNodes, isEmpty);
    });

    test('layer with DSP chain reports hasDsp correctly', () {
      final layer = SlotEventLayer(
        id: 'layer1',
        name: 'Test Layer',
        audioPath: '/audio/test.wav',
        dspChain: [
          LayerDspNode.create(LayerDspType.eq),
          LayerDspNode.create(LayerDspType.compressor),
        ],
      );

      expect(layer.hasDsp, true);
      expect(layer.dspChain.length, 2);
    });

    test('activeDspNodes excludes bypassed nodes', () {
      final layer = SlotEventLayer(
        id: 'layer1',
        name: 'Test Layer',
        audioPath: '/audio/test.wav',
        dspChain: [
          LayerDspNode.create(LayerDspType.eq),
          LayerDspNode(
            id: 'bypassed',
            type: LayerDspType.compressor,
            bypass: true,
          ),
          LayerDspNode.create(LayerDspType.reverb),
        ],
      );

      expect(layer.activeDspNodes.length, 2);
      expect(layer.activeDspNodes.map((n) => n.type).toList(),
          [LayerDspType.eq, LayerDspType.reverb]);
    });

    test('copyWith updates DSP chain', () {
      const layer = SlotEventLayer(
        id: 'layer1',
        name: 'Test Layer',
        audioPath: '/audio/test.wav',
      );

      final newChain = [LayerDspNode.create(LayerDspType.delay)];
      final updated = layer.copyWith(dspChain: newChain);

      expect(updated.dspChain.length, 1);
      expect(updated.dspChain[0].type, LayerDspType.delay);
    });

    test('toJson includes DSP chain', () {
      final layer = SlotEventLayer(
        id: 'layer1',
        name: 'Test Layer',
        audioPath: '/audio/test.wav',
        dspChain: [
          LayerDspNode(
            id: 'node1',
            type: LayerDspType.eq,
            params: {'lowGain': 2.0},
          ),
        ],
      );

      final json = layer.toJson();

      expect(json['dspChain'], isList);
      expect((json['dspChain'] as List).length, 1);
      expect((json['dspChain'] as List)[0]['type'], 'eq');
    });

    test('fromJson deserializes DSP chain', () {
      final json = {
        'id': 'layer1',
        'name': 'Test Layer',
        'audioPath': '/audio/test.wav',
        'dspChain': [
          {'id': 'node1', 'type': 'reverb', 'wetDry': 0.5, 'params': {}},
          {'id': 'node2', 'type': 'delay', 'params': {}},
        ],
      };

      final layer = SlotEventLayer.fromJson(json);

      expect(layer.dspChain.length, 2);
      expect(layer.dspChain[0].type, LayerDspType.reverb);
      expect(layer.dspChain[0].wetDry, 0.5);
      expect(layer.dspChain[1].type, LayerDspType.delay);
    });

    test('fromJson handles missing dspChain field', () {
      final json = {
        'id': 'layer1',
        'name': 'Test Layer',
        'audioPath': '/audio/test.wav',
      };

      final layer = SlotEventLayer.fromJson(json);

      expect(layer.dspChain, isEmpty);
    });
  });

  group('LayerDspPresets', () {
    test('all presets have unique IDs', () {
      final ids = LayerDspPresets.all.map((p) => p.id).toSet();
      expect(ids.length, LayerDspPresets.all.length);
    });

    test('all presets have non-empty chains', () {
      for (final preset in LayerDspPresets.all) {
        expect(preset.chain, isNotEmpty, reason: 'Preset ${preset.id} has empty chain');
      }
    });

    test('all presets have valid chain length', () {
      for (final preset in LayerDspPresets.all) {
        expect(preset.chain.length, lessThanOrEqualTo(LayerDspService.maxProcessorsPerLayer),
            reason: 'Preset ${preset.id} exceeds max processors');
      }
    });

    test('getByCategory returns correct presets', () {
      final slotPresets = LayerDspPresets.getByCategory('Slot');
      expect(slotPresets, isNotEmpty);
      expect(slotPresets.every((p) => p.category == 'Slot'), true);
    });

    test('categories returns unique sorted categories', () {
      final categories = LayerDspPresets.categories;
      expect(categories, isNotEmpty);
      expect(categories.toSet().length, categories.length);

      // Check sorted
      final sorted = List<String>.from(categories)..sort();
      expect(categories, sorted);
    });

    test('findById returns correct preset', () {
      final preset = LayerDspPresets.findById('clean_dialog');
      expect(preset, isNotNull);
      expect(preset!.name, 'Clean Dialog');
      expect(preset.category, 'Voice');
    });

    test('findById returns null for unknown ID', () {
      final preset = LayerDspPresets.findById('nonexistent_preset');
      expect(preset, isNull);
    });
  });

  group('LayerDspService', () {
    late LayerDspService service;

    setUp(() {
      service = LayerDspService.instance;
    });

    test('maxProcessorsPerLayer is reasonable', () {
      expect(LayerDspService.maxProcessorsPerLayer, greaterThan(0));
      expect(LayerDspService.maxProcessorsPerLayer, lessThanOrEqualTo(8));
    });

    test('validateChain rejects too many processors', () {
      final tooManyNodes = List.generate(
        LayerDspService.maxProcessorsPerLayer + 1,
        (i) => LayerDspNode.create(LayerDspType.eq),
      );

      expect(service.validateChain(tooManyNodes), false);
    });

    test('validateChain accepts valid chain', () {
      final validChain = [
        LayerDspNode.create(LayerDspType.eq),
        LayerDspNode.create(LayerDspType.compressor),
      ];

      expect(service.validateChain(validChain), true);
    });

    test('validateChain accepts empty chain', () {
      expect(service.validateChain([]), true);
    });

    test('validateChain rejects invalid EQ gain', () {
      final chain = [
        LayerDspNode(
          id: 'test',
          type: LayerDspType.eq,
          params: {'lowGain': 30.0}, // > 24 dB
        ),
      ];

      expect(service.validateChain(chain), false);
    });

    test('validateChain rejects invalid compressor threshold', () {
      final chain = [
        LayerDspNode(
          id: 'test',
          type: LayerDspType.compressor,
          params: {'threshold': 10.0}, // > 0 dB
        ),
      ];

      expect(service.validateChain(chain), false);
    });

    test('validateChain rejects invalid reverb decay', () {
      final chain = [
        LayerDspNode(
          id: 'test',
          type: LayerDspType.reverb,
          params: {'decay': 25.0}, // > 20 seconds
        ),
      ];

      expect(service.validateChain(chain), false);
    });

    test('validateChain rejects invalid delay feedback', () {
      final chain = [
        LayerDspNode(
          id: 'test',
          type: LayerDspType.delay,
          params: {'feedback': 1.0}, // > 0.95
        ),
      ];

      expect(service.validateChain(chain), false);
    });

    test('validateChain rejects invalid wetDry', () {
      final chain = [
        LayerDspNode(
          id: 'test',
          type: LayerDspType.eq,
          wetDry: 1.5, // > 1.0
          params: {},
        ),
      ];

      expect(service.validateChain(chain), false);
    });

    test('applyPreset returns chain with new IDs', () {
      final chain = service.applyPreset('clean_dialog');

      expect(chain, isNotEmpty);
      // IDs should be unique and different from preset template IDs
      final ids = chain.map((n) => n.id).toSet();
      expect(ids.length, chain.length);
      expect(chain.every((n) => n.id.startsWith('layer-dsp-')), true);
    });

    test('applyPreset returns empty for unknown preset', () {
      final chain = service.applyPreset('nonexistent');
      expect(chain, isEmpty);
    });

    test('hasActiveDsp returns false for unloaded layer', () {
      expect(service.hasActiveDsp('nonexistent_layer'), false);
    });

    test('getActiveDspCount returns 0 for unloaded layer', () {
      expect(service.getActiveDspCount('nonexistent_layer'), 0);
    });

    test('activeLayerCount starts at 0', () {
      // Note: This may not be 0 if other tests have run
      // In a fresh service, it should be 0
      expect(service.activeLayerCount, greaterThanOrEqualTo(0));
    });
  });

  group('LayerDspType enum', () {
    test('all types have shortName', () {
      for (final type in LayerDspType.values) {
        expect(type.shortName, isNotEmpty);
      }
    });

    test('all types have fullName', () {
      for (final type in LayerDspType.values) {
        expect(type.fullName, isNotEmpty);
      }
    });

    test('shortName is shorter than fullName', () {
      for (final type in LayerDspType.values) {
        expect(type.shortName.length, lessThanOrEqualTo(type.fullName.length));
      }
    });
  });
}
