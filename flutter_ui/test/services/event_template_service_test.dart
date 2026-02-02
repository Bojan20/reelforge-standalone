import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ui/services/event_template_service.dart';

void main() {
  group('EventTemplateCategory', () {
    test('has correct display names', () {
      expect(EventTemplateCategory.spin.displayName, 'Spin Events');
      expect(EventTemplateCategory.win.displayName, 'Win Events');
      expect(EventTemplateCategory.feature.displayName, 'Feature Events');
      expect(EventTemplateCategory.cascade.displayName, 'Cascade Events');
      expect(EventTemplateCategory.ui.displayName, 'UI Events');
      expect(EventTemplateCategory.music.displayName, 'Music Events');
      expect(EventTemplateCategory.custom.displayName, 'Custom Templates');
    });

    test('has icons', () {
      for (final category in EventTemplateCategory.values) {
        expect(category.icon.isNotEmpty, true);
      }
    });
  });

  group('EventTemplateLayer', () {
    test('creates with default values', () {
      const layer = EventTemplateLayer();

      expect(layer.volume, 1.0);
      expect(layer.pan, 0.0);
      expect(layer.offsetMs, 0);
      expect(layer.busId, 2); // SFX bus
      expect(layer.hint, isNull);
    });

    test('serializes to JSON and back', () {
      const layer = EventTemplateLayer(
        volume: 0.8,
        pan: -0.5,
        offsetMs: 200,
        busId: 1,
        hint: 'Test hint',
      );

      final json = layer.toJson();
      final restored = EventTemplateLayer.fromJson(json);

      expect(restored.volume, layer.volume);
      expect(restored.pan, layer.pan);
      expect(restored.offsetMs, layer.offsetMs);
      expect(restored.busId, layer.busId);
      expect(restored.hint, layer.hint);
    });
  });

  group('EventTemplate', () {
    test('creates with required values', () {
      const template = EventTemplate(
        id: 'test_1',
        name: 'Test Template',
        description: 'A test template',
        category: EventTemplateCategory.spin,
        stage: 'SPIN_START',
      );

      expect(template.id, 'test_1');
      expect(template.name, 'Test Template');
      expect(template.description, 'A test template');
      expect(template.category, EventTemplateCategory.spin);
      expect(template.stage, 'SPIN_START');
      expect(template.layers, isEmpty);
      expect(template.isBuiltIn, false);
    });

    test('serializes to JSON and back', () {
      const template = EventTemplate(
        id: 'test_1',
        name: 'Test Template',
        description: 'A test template',
        category: EventTemplateCategory.win,
        stage: 'WIN_BIG',
        layers: [
          EventTemplateLayer(volume: 1.0, hint: 'Layer 1'),
          EventTemplateLayer(volume: 0.8, offsetMs: 100, hint: 'Layer 2'),
        ],
        isBuiltIn: true,
        icon: 'test_icon',
        metadata: {'key': 'value'},
      );

      final json = template.toJson();
      final restored = EventTemplate.fromJson(json);

      expect(restored.id, template.id);
      expect(restored.name, template.name);
      expect(restored.description, template.description);
      expect(restored.category, template.category);
      expect(restored.stage, template.stage);
      expect(restored.layers.length, 2);
      expect(restored.isBuiltIn, template.isBuiltIn);
      expect(restored.icon, template.icon);
      expect(restored.metadata, template.metadata);
    });

    test('copyWith creates modified copy', () {
      const original = EventTemplate(
        id: 'test_1',
        name: 'Original',
        description: 'Original description',
        category: EventTemplateCategory.spin,
        stage: 'SPIN_START',
      );

      final modified = original.copyWith(
        name: 'Modified',
        category: EventTemplateCategory.win,
      );

      expect(modified.id, original.id);
      expect(modified.name, 'Modified');
      expect(modified.description, original.description);
      expect(modified.category, EventTemplateCategory.win);
      expect(modified.stage, original.stage);
    });

    test('toEvent creates SlotCompositeEvent', () {
      const template = EventTemplate(
        id: 'test_1',
        name: 'Test Template',
        description: 'A test',
        category: EventTemplateCategory.spin,
        stage: 'SPIN_START',
        layers: [
          EventTemplateLayer(volume: 0.9, hint: 'Main'),
          EventTemplateLayer(volume: 0.7, offsetMs: 50, hint: 'Secondary'),
        ],
      );

      final event = template.toEvent(eventId: 'evt_123');

      expect(event.id, 'evt_123');
      expect(event.name, 'Test Template');
      expect(event.triggerStages, contains('SPIN_START'));
      expect(event.layers.length, 2);
      expect(event.layers[0].volume, 0.9);
      expect(event.layers[1].volume, 0.7);
    });

    test('toEvent respects custom parameters', () {
      const template = EventTemplate(
        id: 'test_1',
        name: 'Test Template',
        description: 'A test',
        category: EventTemplateCategory.spin,
        stage: 'SPIN_START',
      );

      final event = template.toEvent(
        eventId: 'evt_456',
        customName: 'Custom Name',
        customStage: 'CUSTOM_STAGE',
        customColor: Colors.red,
      );

      expect(event.id, 'evt_456');
      expect(event.name, 'Custom Name');
      expect(event.triggerStages, contains('CUSTOM_STAGE'));
      expect(event.color, Colors.red);
    });
  });

  group('BuiltInEventTemplates', () {
    test('has spin templates', () {
      final spinTemplates =
          BuiltInEventTemplates.byCategory(EventTemplateCategory.spin);

      expect(spinTemplates.length, greaterThanOrEqualTo(3));
      expect(spinTemplates.any((t) => t.id == 'tpl_spin_start'), true);
      expect(spinTemplates.any((t) => t.id == 'tpl_reel_stop'), true);
      expect(spinTemplates.any((t) => t.id == 'tpl_spin_loop'), true);
    });

    test('has win templates', () {
      final winTemplates =
          BuiltInEventTemplates.byCategory(EventTemplateCategory.win);

      expect(winTemplates.length, greaterThanOrEqualTo(4));
      expect(winTemplates.any((t) => t.id == 'tpl_win_small'), true);
      expect(winTemplates.any((t) => t.id == 'tpl_win_big'), true);
      expect(winTemplates.any((t) => t.id == 'tpl_win_mega'), true);
      expect(winTemplates.any((t) => t.id == 'tpl_win_epic'), true);
    });

    test('has feature templates', () {
      final featureTemplates =
          BuiltInEventTemplates.byCategory(EventTemplateCategory.feature);

      expect(featureTemplates.length, greaterThanOrEqualTo(5));
      expect(featureTemplates.any((t) => t.id == 'tpl_fs_trigger'), true);
      expect(featureTemplates.any((t) => t.id == 'tpl_bonus_enter'), true);
      expect(featureTemplates.any((t) => t.id == 'tpl_jackpot_trigger'), true);
    });

    test('has cascade templates', () {
      final cascadeTemplates =
          BuiltInEventTemplates.byCategory(EventTemplateCategory.cascade);

      expect(cascadeTemplates.length, greaterThanOrEqualTo(3));
      expect(cascadeTemplates.any((t) => t.id == 'tpl_cascade_start'), true);
      expect(cascadeTemplates.any((t) => t.id == 'tpl_cascade_step'), true);
      expect(cascadeTemplates.any((t) => t.id == 'tpl_cascade_end'), true);
    });

    test('has UI templates', () {
      final uiTemplates =
          BuiltInEventTemplates.byCategory(EventTemplateCategory.ui);

      expect(uiTemplates.length, greaterThanOrEqualTo(2));
      expect(uiTemplates.any((t) => t.id == 'tpl_button_press'), true);
      expect(uiTemplates.any((t) => t.id == 'tpl_menu_open'), true);
    });

    test('has music templates', () {
      final musicTemplates =
          BuiltInEventTemplates.byCategory(EventTemplateCategory.music);

      expect(musicTemplates.length, greaterThanOrEqualTo(3));
      expect(musicTemplates.any((t) => t.id == 'tpl_base_music'), true);
      expect(musicTemplates.any((t) => t.id == 'tpl_feature_music'), true);
      expect(musicTemplates.any((t) => t.id == 'tpl_big_win_music'), true);
    });

    test('all templates have required fields', () {
      for (final template in BuiltInEventTemplates.all) {
        expect(template.id.isNotEmpty, true, reason: 'ID should not be empty');
        expect(template.name.isNotEmpty, true,
            reason: 'Name should not be empty');
        expect(template.stage.isNotEmpty, true,
            reason: 'Stage should not be empty');
        expect(template.isBuiltIn, true, reason: 'Should be marked as built-in');
      }
    });

    test('all templates have at least 26 entries (original 16 + 10 new)', () {
      expect(BuiltInEventTemplates.all.length, greaterThanOrEqualTo(26));
    });
  });
}
