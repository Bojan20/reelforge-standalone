/// Timeline Layer Reorder Tests (P12.1.14)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/slot_lab/timeline_layer_reorder.dart';

void main() {
  group('ReorderableLayer', () {
    test('creates with required fields', () {
      const layer = ReorderableLayer(
        id: 'layer_1',
        name: 'Test Layer',
      );

      expect(layer.id, 'layer_1');
      expect(layer.name, 'Test Layer');
      expect(layer.offsetMs, 0);
      expect(layer.durationMs, 1000);
      expect(layer.isMuted, false);
    });

    test('copyWith preserves unmodified fields', () {
      const original = ReorderableLayer(
        id: 'layer_1',
        name: 'Original',
        offsetMs: 100,
        durationMs: 2000,
      );
      final copied = original.copyWith(name: 'Copied', isMuted: true);

      expect(copied.id, original.id);
      expect(copied.offsetMs, original.offsetMs);
      expect(copied.durationMs, original.durationMs);
      expect(copied.name, 'Copied');
      expect(copied.isMuted, true);
    });

    test('copyWith updates all specified fields', () {
      const original = ReorderableLayer(
        id: 'layer_1',
        name: 'Original',
      );
      final copied = original.copyWith(
        name: 'New Name',
        audioPath: '/new/path.wav',
        offsetMs: 500,
        durationMs: 3000,
        color: Colors.red,
        isMuted: true,
      );

      expect(copied.name, 'New Name');
      expect(copied.audioPath, '/new/path.wav');
      expect(copied.offsetMs, 500);
      expect(copied.durationMs, 3000);
      expect(copied.color, Colors.red);
      expect(copied.isMuted, true);
    });
  });
}
