// SlotLab Models — Ultimate Unit Tests
//
// Tests for core SlotLab data models:
// - SymbolDefinition (creation, serialization, stage names, contexts)
// - SymbolAudioAssignment (stage name generation, serialization)
// - MusicLayerAssignment (serialization, copyWith)
// - ContextDefinition (factories, serialization)
// - SymbolPreset (built-in presets, symbol counts)
// - SymbolType (display names, colors, emojis)
// - SymbolAudioContext (parsing, stage suffix)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/slot_lab_models.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOL TYPE ENUM
  // ═══════════════════════════════════════════════════════════════════════════

  group('SymbolType', () {
    test('all types have display names', () {
      for (final type in SymbolType.values) {
        expect(type.displayName, isNotEmpty, reason: '$type has no displayName');
      }
    });

    test('all types have default colors', () {
      for (final type in SymbolType.values) {
        expect(type.defaultColor, isNotNull, reason: '$type has no color');
      }
    });

    test('all types have default emojis', () {
      for (final type in SymbolType.values) {
        expect(type.defaultEmoji, isNotEmpty, reason: '$type has no emoji');
      }
    });

    test('legacy aliases map correctly', () {
      expect(SymbolType.high.displayName, SymbolType.highPay.displayName);
      expect(SymbolType.low.displayName, SymbolType.lowPay.displayName);
    });

    test('wild has purple color', () {
      expect(SymbolType.wild.defaultColor, const Color(0xFF9C27B0));
    });

    test('scatter has gold color', () {
      expect(SymbolType.scatter.defaultColor, const Color(0xFFFFD700));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOL AUDIO CONTEXT ENUM
  // ═══════════════════════════════════════════════════════════════════════════

  group('SymbolAudioContext', () {
    test('all values produce correct stage suffix', () {
      expect(SymbolAudioContext.land.stageSuffix, 'LAND');
      expect(SymbolAudioContext.win.stageSuffix, 'WIN');
      expect(SymbolAudioContext.expand.stageSuffix, 'EXPAND');
      expect(SymbolAudioContext.lock.stageSuffix, 'LOCK');
      expect(SymbolAudioContext.transform.stageSuffix, 'TRANSFORM');
      expect(SymbolAudioContext.collect.stageSuffix, 'COLLECT');
      expect(SymbolAudioContext.stack.stageSuffix, 'STACK');
      expect(SymbolAudioContext.trigger.stageSuffix, 'TRIGGER');
      expect(SymbolAudioContext.anticipation.stageSuffix, 'ANTICIPATION');
    });

    test('fromString parses valid values', () {
      expect(SymbolAudioContext.fromString('land'), SymbolAudioContext.land);
      expect(SymbolAudioContext.fromString('LAND'), SymbolAudioContext.land);
      expect(SymbolAudioContext.fromString('Win'), SymbolAudioContext.win);
    });

    test('fromString returns null for invalid values', () {
      expect(SymbolAudioContext.fromString('invalid'), isNull);
      expect(SymbolAudioContext.fromString(''), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOL DEFINITION
  // ═══════════════════════════════════════════════════════════════════════════

  group('SymbolDefinition', () {
    const testSymbol = SymbolDefinition(
      id: 'hp1',
      name: 'High Pay 1',
      emoji: '💎',
      type: SymbolType.highPay,
      contexts: ['land', 'win', 'expand'],
      payMultiplier: 100,
      sortOrder: 1,
    );

    test('constructor sets all fields', () {
      expect(testSymbol.id, 'hp1');
      expect(testSymbol.name, 'High Pay 1');
      expect(testSymbol.emoji, '💎');
      expect(testSymbol.type, SymbolType.highPay);
      expect(testSymbol.contexts, ['land', 'win', 'expand']);
      expect(testSymbol.payMultiplier, 100);
      expect(testSymbol.sortOrder, 1);
      expect(testSymbol.customColor, isNull);
      expect(testSymbol.metadata, isNull);
    });

    test('default contexts are land and win', () {
      const symbol = SymbolDefinition(
        id: 'test',
        name: 'Test',
        emoji: '?',
        type: SymbolType.lowPay,
      );
      expect(symbol.contexts, ['land', 'win']);
    });

    test('displayColor uses custom color when set', () {
      final symbol = testSymbol.copyWith(
        customColor: const Color(0xFFFF0000),
      );
      expect(symbol.displayColor, const Color(0xFFFF0000));
    });

    test('displayColor uses type default when no custom', () {
      expect(testSymbol.displayColor, SymbolType.highPay.defaultColor);
    });

    // Stage name generation — CRITICAL for audio dispatch
    group('stage names', () {
      test('stageIdLand generates correct format', () {
        expect(testSymbol.stageIdLand, 'HP1_LAND');
      });

      test('stageIdWin generates SYMBOL_WIN format', () {
        // CRITICAL: Must match slot_preview_widget.dart trigger pattern
        expect(testSymbol.stageIdWin, 'HP1_WIN');
      });

      test('stageIdExpand generates correct format', () {
        expect(testSymbol.stageIdExpand, 'HP1_EXPAND');
      });

      test('stageIdLock generates correct format', () {
        expect(testSymbol.stageIdLock, 'HP1_LOCK');
      });

      test('stageIdTransform generates correct format', () {
        expect(testSymbol.stageIdTransform, 'HP1_TRANSFORM');
      });

      test('stageName dispatches to correct getter per context', () {
        expect(testSymbol.stageName('land'), 'HP1_LAND');
        expect(testSymbol.stageName('win'), 'HP1_WIN');
        expect(testSymbol.stageName('expand'), 'HP1_EXPAND');
        expect(testSymbol.stageName('lock'), 'HP1_LOCK');
        expect(testSymbol.stageName('transform'), 'HP1_TRANSFORM');
      });

      test('stageName fallback for unknown context', () {
        expect(testSymbol.stageName('custom_ctx'), 'HP1_CUSTOM_CTX');
      });

      test('allStageIds includes all contexts plus win', () {
        final stages = testSymbol.allStageIds;
        expect(stages, contains('HP1_LAND'));
        expect(stages, contains('HP1_WIN'));
        expect(stages, contains('HP1_EXPAND'));
      });

      test('allStageIds always includes win even if not in contexts', () {
        const symbolNoWin = SymbolDefinition(
          id: 'lp1',
          name: 'Low Pay 1',
          emoji: 'A',
          type: SymbolType.lowPay,
          contexts: ['land'],
        );
        final stages = symbolNoWin.allStageIds;
        expect(stages, contains('LP1_WIN'));
      });

      test('lowercase symbol id is uppercased in stages', () {
        const symbol = SymbolDefinition(
          id: 'wild',
          name: 'Wild',
          emoji: '🃏',
          type: SymbolType.wild,
        );
        expect(symbol.stageIdLand, 'WILD_LAND');
        expect(symbol.stageIdWin, 'WILD_WIN');
      });
    });

    // Typed contexts
    test('typedContexts converts string contexts to enum', () {
      final typed = testSymbol.typedContexts;
      expect(typed, contains(SymbolAudioContext.land));
      expect(typed, contains(SymbolAudioContext.win));
      expect(typed, contains(SymbolAudioContext.expand));
    });

    test('hasContext checks typed context presence', () {
      expect(testSymbol.hasContext(SymbolAudioContext.land), true);
      expect(testSymbol.hasContext(SymbolAudioContext.lock), false);
    });

    // Serialization round-trip
    test('toJson/fromJson round-trip preserves all fields', () {
      final json = testSymbol.toJson();
      final restored = SymbolDefinition.fromJson(json);

      expect(restored.id, testSymbol.id);
      expect(restored.name, testSymbol.name);
      expect(restored.emoji, testSymbol.emoji);
      expect(restored.type, testSymbol.type);
      expect(restored.contexts, testSymbol.contexts);
      expect(restored.payMultiplier, testSymbol.payMultiplier);
      expect(restored.sortOrder, testSymbol.sortOrder);
    });

    test('fromJson handles missing optional fields', () {
      final symbol = SymbolDefinition.fromJson({
        'id': 'x',
        'name': 'X',
        'emoji': '?',
        'type': 'lowPay',
      });
      expect(symbol.contexts, ['land', 'win']);
      expect(symbol.payMultiplier, isNull);
      expect(symbol.customColor, isNull);
      expect(symbol.sortOrder, 0);
    });

    test('fromJson handles unknown type gracefully', () {
      final symbol = SymbolDefinition.fromJson({
        'id': 'x',
        'name': 'X',
        'emoji': '?',
        'type': 'nonExistentType',
      });
      expect(symbol.type, SymbolType.lowPay); // Default fallback
    });

    // copyWith
    test('copyWith replaces specified fields only', () {
      final copy = testSymbol.copyWith(name: 'New Name', emoji: '🔥');
      expect(copy.name, 'New Name');
      expect(copy.emoji, '🔥');
      expect(copy.id, testSymbol.id); // Unchanged
      expect(copy.type, testSymbol.type); // Unchanged
    });

    // Equality
    test('equality is based on id only', () {
      const a = SymbolDefinition(
        id: 'hp1',
        name: 'Name A',
        emoji: '💎',
        type: SymbolType.highPay,
      );
      const b = SymbolDefinition(
        id: 'hp1',
        name: 'Name B',
        emoji: '🔶',
        type: SymbolType.lowPay,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different ids are not equal', () {
      const a = SymbolDefinition(
        id: 'hp1',
        name: 'HP1',
        emoji: '💎',
        type: SymbolType.highPay,
      );
      const b = SymbolDefinition(
        id: 'hp2',
        name: 'HP2',
        emoji: '💎',
        type: SymbolType.highPay,
      );
      expect(a, isNot(equals(b)));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOL AUDIO ASSIGNMENT
  // ═══════════════════════════════════════════════════════════════════════════

  group('SymbolAudioAssignment', () {
    const assignment = SymbolAudioAssignment(
      symbolId: 'hp1',
      context: 'win',
      audioPath: '/audio/hp1_win.wav',
      volume: 0.8,
      pan: -0.5,
    );

    test('constructor sets all fields', () {
      expect(assignment.symbolId, 'hp1');
      expect(assignment.context, 'win');
      expect(assignment.audioPath, '/audio/hp1_win.wav');
      expect(assignment.volume, 0.8);
      expect(assignment.pan, -0.5);
    });

    test('defaults for volume and pan', () {
      const a = SymbolAudioAssignment(
        symbolId: 'x',
        context: 'land',
        audioPath: '/x.wav',
      );
      expect(a.volume, 1.0);
      expect(a.pan, 0.0);
    });

    // Stage name generation — CRITICAL for event registry matching
    group('stageName', () {
      test('win context generates SYMBOL_WIN format', () {
        expect(assignment.stageName, 'HP1_WIN');
      });

      test('land context generates SYMBOL_LAND format', () {
        const a = SymbolAudioAssignment(
          symbolId: 'wild',
          context: 'land',
          audioPath: '/x.wav',
        );
        expect(a.stageName, 'WILD_LAND');
      });

      test('expand context generates SYMBOL_EXPAND format', () {
        const a = SymbolAudioAssignment(
          symbolId: 'scatter',
          context: 'expand',
          audioPath: '/x.wav',
        );
        expect(a.stageName, 'SCATTER_EXPAND');
      });

      test('lock context generates {SYMBOL}_LOCK format', () {
        const a = SymbolAudioAssignment(
          symbolId: 'coin',
          context: 'lock',
          audioPath: '/x.wav',
        );
        expect(a.stageName, 'COIN_LOCK');
      });

      test('transform context generates {SYMBOL}_TRANSFORM format', () {
        const a = SymbolAudioAssignment(
          symbolId: 'mystery',
          context: 'transform',
          audioPath: '/x.wav',
        );
        expect(a.stageName, 'MYSTERY_TRANSFORM');
      });

      test('collect context uses {SYMBOL}_COLLECT format', () {
        const a = SymbolAudioAssignment(
          symbolId: 'hp1',
          context: 'collect',
          audioPath: '/x.wav',
        );
        expect(a.stageName, 'HP1_COLLECT');
      });

      test('symbol id is uppercased', () {
        const a = SymbolAudioAssignment(
          symbolId: 'mySymbol',
          context: 'land',
          audioPath: '/x.wav',
        );
        expect(a.stageName, 'MYSYMBOL_LAND');
      });
    });

    // Serialization
    test('toJson/fromJson round-trip', () {
      final json = assignment.toJson();
      final restored = SymbolAudioAssignment.fromJson(json);

      expect(restored.symbolId, assignment.symbolId);
      expect(restored.context, assignment.context);
      expect(restored.audioPath, assignment.audioPath);
      expect(restored.volume, assignment.volume);
      expect(restored.pan, assignment.pan);
    });

    test('fromJson handles missing volume/pan with defaults', () {
      final a = SymbolAudioAssignment.fromJson({
        'symbolId': 'x',
        'context': 'land',
        'audioPath': '/x.wav',
      });
      expect(a.volume, 1.0);
      expect(a.pan, 0.0);
    });

    // copyWith
    test('copyWith replaces specified fields', () {
      final copy = assignment.copyWith(volume: 0.5, pan: 0.3);
      expect(copy.volume, 0.5);
      expect(copy.pan, 0.3);
      expect(copy.symbolId, assignment.symbolId);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MUSIC LAYER ASSIGNMENT
  // ═══════════════════════════════════════════════════════════════════════════

  group('MusicLayerAssignment', () {
    const layer = MusicLayerAssignment(
      contextId: 'base',
      layer: 1,
      audioPath: '/audio/base_l1.wav',
      volume: 0.9,
      loop: true,
    );

    test('constructor sets all fields', () {
      expect(layer.contextId, 'base');
      expect(layer.layer, 1);
      expect(layer.audioPath, '/audio/base_l1.wav');
      expect(layer.volume, 0.9);
      expect(layer.loop, true);
    });

    test('defaults for volume and loop', () {
      const l = MusicLayerAssignment(
        contextId: 'x',
        layer: 1,
        audioPath: '/x.wav',
      );
      expect(l.volume, 1.0);
      expect(l.loop, true);
    });

    test('toJson/fromJson round-trip', () {
      final json = layer.toJson();
      final restored = MusicLayerAssignment.fromJson(json);

      expect(restored.contextId, layer.contextId);
      expect(restored.layer, layer.layer);
      expect(restored.audioPath, layer.audioPath);
      expect(restored.volume, layer.volume);
      expect(restored.loop, layer.loop);
    });

    test('copyWith replaces specified fields', () {
      final copy = layer.copyWith(volume: 0.5, loop: false);
      expect(copy.volume, 0.5);
      expect(copy.loop, false);
      expect(copy.contextId, layer.contextId);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOL PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  group('SymbolPreset', () {
    test('builtInPresets has expected count', () {
      final presets = SymbolPreset.builtInPresets;
      expect(presets.length, greaterThanOrEqualTo(4));
    });

    test('standard5x3 preset has symbols with all required types', () {
      final preset = SymbolPreset.builtInPresets.firstWhere(
        (p) => p.type == SymbolPresetType.standard5x3,
      );
      final types = preset.symbols.map((s) => s.type).toSet();
      expect(types, contains(SymbolType.wild));
      expect(types, contains(SymbolType.scatter));
      expect(preset.symbols.length, greaterThanOrEqualTo(8));
    });

    test('each preset has unique symbol ids', () {
      for (final preset in SymbolPreset.builtInPresets) {
        final ids = preset.symbols.map((s) => s.id).toList();
        final uniqueIds = ids.toSet();
        expect(
          ids.length,
          uniqueIds.length,
          reason: '${preset.type.name} has duplicate symbol ids',
        );
      }
    });

    test('holdAndWin preset includes collector symbols', () {
      final preset = SymbolPreset.builtInPresets.firstWhere(
        (p) => p.type == SymbolPresetType.holdAndWin,
      );
      final types = preset.symbols.map((s) => s.type).toSet();
      expect(types, contains(SymbolType.collector));
    });

    test('megaways preset exists and has symbols', () {
      final preset = SymbolPreset.builtInPresets.firstWhere(
        (p) => p.type == SymbolPresetType.megaways,
      );
      expect(preset.symbols, isNotEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOL DEFINITION — getAllSymbolStageIds helper
  // ═══════════════════════════════════════════════════════════════════════════

  group('getAllSymbolStageIds', () {
    test('generates stages for each symbol and context', () {
      const symbols = [
        SymbolDefinition(
          id: 'wild',
          name: 'Wild',
          emoji: '🃏',
          type: SymbolType.wild,
          contexts: ['land', 'win', 'expand'],
        ),
        SymbolDefinition(
          id: 'scatter',
          name: 'Scatter',
          emoji: '⭐',
          type: SymbolType.scatter,
          contexts: ['land', 'win'],
        ),
      ];

      final stageIds = getAllSymbolStageIds(symbols);

      expect(stageIds, contains('WILD_LAND'));
      expect(stageIds, contains('WILD_WIN'));
      expect(stageIds, contains('WILD_EXPAND'));
      expect(stageIds, contains('SCATTER_LAND'));
      expect(stageIds, contains('SCATTER_WIN'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTEXT DEFINITION
  // ═══════════════════════════════════════════════════════════════════════════

  group('ContextDefinition', () {
    test('base factory creates correct context', () {
      final ctx = ContextDefinition.base();
      expect(ctx.id, 'base');
      expect(ctx.displayName, isNotEmpty);
      expect(ctx.layerCount, greaterThanOrEqualTo(3));
    });

    test('freeSpins factory creates correct context', () {
      final ctx = ContextDefinition.freeSpins();
      expect(ctx.id, 'freespins');
      expect(ctx.displayName, isNotEmpty);
    });

    test('holdWin factory creates correct context', () {
      final ctx = ContextDefinition.holdWin();
      expect(ctx.id, 'holdwin');
      expect(ctx.displayName, isNotEmpty);
    });

    test('toJson/fromJson round-trip', () {
      final ctx = ContextDefinition.base();
      final json = ctx.toJson();
      final restored = ContextDefinition.fromJson(json);

      expect(restored.id, ctx.id);
      expect(restored.displayName, ctx.displayName);
      expect(restored.layerCount, ctx.layerCount);
    });
  });
}
