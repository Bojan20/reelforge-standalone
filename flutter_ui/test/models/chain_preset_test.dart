/// Unit tests for chain preset domain models — Wave 2 Front 5.
///
/// These tests pin the wire format to the Rust definitions in
/// `crates/rf-ml/src/assistant/chain_preset.rs` /
/// `crates/rf-ml/src/assistant/chain_history.rs`. If the Rust struct
/// drifts (rename, type change), these tests should be the first to fail.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/chain_preset.dart';

void main() {
  group('SlotParamSnapshot', () {
    test('round-trips through JSON', () {
      const original = SlotParamSnapshot(
        index: 3,
        name: 'Threshold',
        value: -18.5,
      );
      final encoded = jsonEncode(original.toJson());
      final decoded = SlotParamSnapshot.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(decoded.index, 3);
      expect(decoded.name, 'Threshold');
      expect(decoded.value, -18.5);
    });

    test('handles integer JSON for value', () {
      // Rust sends f64; some serialisers emit ints when fractional == 0.
      final j = {'index': 0, 'name': 'Mix', 'value': 1};
      final p = SlotParamSnapshot.fromJson(j);
      expect(p.value, 1.0);
    });
  });

  group('FullSlotSnapshot', () {
    test('handles missing optional fields', () {
      final j = {
        'slot_index': 2,
        'processor_name': 'compressor',
        // bypassed missing → false
        // mix missing → 1.0
        // params missing → []
      };
      final s = FullSlotSnapshot.fromJson(j);
      expect(s.slotIndex, 2);
      expect(s.processorName, 'compressor');
      expect(s.bypassed, false);
      expect(s.mix, 1.0);
      expect(s.params, isEmpty);
    });

    test('toJson matches Rust snake_case keys', () {
      const s = FullSlotSnapshot(
        slotIndex: 0,
        processorName: 'eq',
        bypassed: false,
        mix: 1.0,
        params: [
          SlotParamSnapshot(index: 0, name: 'Frequency', value: 1000.0),
        ],
      );
      final j = s.toJson();
      expect(j.containsKey('slot_index'), true);
      expect(j.containsKey('processor_name'), true);
      expect(j.containsKey('bypassed'), true);
      expect(j.containsKey('mix'), true);
      expect(j.containsKey('params'), true);
      // No camelCase leaks
      expect(j.containsKey('slotIndex'), false);
      expect(j.containsKey('processorName'), false);
    });
  });

  group('FullChainSnapshot', () {
    test('round-trips with multiple slots', () {
      const snap = FullChainSnapshot(
        trackId: 7,
        slots: [
          FullSlotSnapshot(
            slotIndex: 0,
            processorName: 'compressor',
            bypassed: false,
            mix: 1.0,
            params: [
              SlotParamSnapshot(index: 0, name: 'Threshold', value: -20.0),
              SlotParamSnapshot(index: 1, name: 'Ratio', value: 4.0),
            ],
          ),
          FullSlotSnapshot(
            slotIndex: 1,
            processorName: 'pro-eq',
            bypassed: true,
            mix: 0.7,
            params: [],
          ),
        ],
        label: 'Apply Vocal Bright',
        timestampMs: 1714914000000,
      );
      final encoded = jsonEncode(snap.toJson());
      final decoded =
          FullChainSnapshot.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded.trackId, 7);
      expect(decoded.slots.length, 2);
      expect(decoded.slots[0].params.length, 2);
      expect(decoded.slots[0].params[1].name, 'Ratio');
      expect(decoded.slots[1].bypassed, true);
      expect(decoded.label, 'Apply Vocal Bright');
      expect(decoded.timestampMs, 1714914000000);
    });

    test('empty slots and missing label are tolerated', () {
      final j = {'track_id': 1};
      final s = FullChainSnapshot.fromJson(j);
      expect(s.trackId, 1);
      expect(s.slots, isEmpty);
      expect(s.label, '');
      expect(s.timestampMs, 0);
    });
  });

  group('ChainPreset', () {
    test('parses Rust-shaped JSON', () {
      final j = {
        'name': 'My Vocal Master',
        'description': 'Bright, transparent',
        'tags': ['vocal', 'modern'],
        'snapshot': {
          'track_id': 7,
          'slots': [
            {
              'slot_index': 0,
              'processor_name': 'compressor',
              'bypassed': false,
              'mix': 1.0,
              'params': [
                {'index': 0, 'name': 'Threshold', 'value': -18.0}
              ]
            }
          ],
          'label': 'Save',
          'timestamp_ms': 1714914000000,
        },
        'format_version': 1,
        'created_ms': 1714914000000,
        'updated_ms': 1714914999999,
      };
      final p = ChainPreset.fromJson(j);
      expect(p.name, 'My Vocal Master');
      expect(p.tags, ['vocal', 'modern']);
      expect(p.snapshot.trackId, 7);
      expect(p.snapshot.slots.first.processorName, 'compressor');
      expect(p.formatVersion, 1);
      expect(p.updatedMs, 1714914999999);
    });

    test('toSaveRequest strips audit fields', () {
      const p = ChainPreset(
        name: 'X',
        description: 'd',
        tags: ['a'],
        snapshot: FullChainSnapshot(
          trackId: 1, slots: [], label: '', timestampMs: 0),
        formatVersion: 1,
        createdMs: 100,
        updatedMs: 200,
      );
      final req = p.toSaveRequest();
      expect(req.containsKey('format_version'), false);
      expect(req.containsKey('created_ms'), false);
      expect(req.containsKey('updated_ms'), false);
      expect(req['name'], 'X');
      expect(req['description'], 'd');
      expect(req['tags'], ['a']);
      expect(req['snapshot'], isA<Map<String, dynamic>>());
    });
  });

  group('ChainPresetMeta', () {
    test('parses Rust-shaped list entry', () {
      final j = {
        'name': 'Listed',
        'description': '',
        'tags': <String>[],
        'created_ms': 100,
        'updated_ms': 200,
        'slot_count': 1,
        'filename': 'listed.json',
      };
      final m = ChainPresetMeta.fromJson(j);
      expect(m.name, 'Listed');
      expect(m.tags, isEmpty);
      expect(m.slotCount, 1);
      expect(m.filename, 'listed.json');
    });

    test('tolerates missing optional fields', () {
      final j = {'name': 'Minimal', 'filename': 'minimal.json'};
      final m = ChainPresetMeta.fromJson(j);
      expect(m.name, 'Minimal');
      expect(m.description, '');
      expect(m.tags, isEmpty);
      expect(m.createdMs, 0);
      expect(m.slotCount, 0);
    });
  });

  group('ChainPresetOpResult', () {
    test('parses success envelope', () {
      final r = ChainPresetOpResult.fromJson({
        'ok': true,
        'path': '/tmp/x.json',
        'name': 'X',
      });
      expect(r.ok, true);
      expect(r.path, '/tmp/x.json');
      expect(r.name, 'X');
      expect(r.error, isNull);
    });

    test('parses error envelope (presence of error field)', () {
      final r = ChainPresetOpResult.fromJson({
        'error': 'save: not found',
      });
      expect(r.ok, false);
      expect(r.error, 'save: not found');
      expect(r.path, '');
    });

    test('error factory builds error result', () {
      final r = ChainPresetOpResult.error('null pointer');
      expect(r.ok, false);
      expect(r.error, 'null pointer');
    });
  });
}
