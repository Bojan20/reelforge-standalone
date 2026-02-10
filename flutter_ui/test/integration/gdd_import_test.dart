// GDD Import Integration Tests
//
// Tests: Parse complete GDD JSON, symbol tier detection, toRustJson()
// conversion, grid config extraction, auto-stage generation,
// feature convenience properties, edge cases.
//
// Pure Dart logic — NO FFI, NO Flutter widgets.
@Tags(['integration'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/gdd_import_service.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // GRID CONFIG
  // ═══════════════════════════════════════════════════════════════════════

  group('GddGridConfig', () {
    test('fromJson with standard fields', () {
      final grid = GddGridConfig.fromJson({
        'rows': 3,
        'reels': 5,
        'mechanic': 'lines',
        'paylines': 20,
      });
      expect(grid.rows, 3);
      expect(grid.columns, 5);
      expect(grid.mechanic, 'lines');
      expect(grid.paylines, 20);
    });

    test('fromJson accepts columns alias for reels', () {
      final grid = GddGridConfig.fromJson({
        'rows': 4,
        'columns': 6,
        'mechanic': 'megaways',
      });
      expect(grid.columns, 6);
    });

    test('fromJson prefers reels over columns', () {
      final grid = GddGridConfig.fromJson({
        'rows': 3,
        'reels': 5,
        'columns': 6, // Should be ignored when reels is present
        'mechanic': 'lines',
      });
      expect(grid.columns, 5);
    });

    test('fromJson with defaults for missing fields', () {
      final grid = GddGridConfig.fromJson({});
      expect(grid.rows, 3);
      expect(grid.columns, 5);
      expect(grid.mechanic, 'lines');
      expect(grid.paylines, isNull);
      expect(grid.ways, isNull);
    });

    test('toJson uses reels key (Rust format)', () {
      const grid = GddGridConfig(
        rows: 3, columns: 5, mechanic: 'lines', paylines: 20,
      );
      final json = grid.toJson();
      expect(json['reels'], 5);
      expect(json.containsKey('columns'), false);
    });

    test('JSON roundtrip', () {
      const grid = GddGridConfig(
        rows: 4, columns: 6, mechanic: 'ways', ways: 4096,
      );
      final json = grid.toJson();
      final restored = GddGridConfig.fromJson(json);
      expect(restored.rows, 4);
      expect(restored.columns, 6);
      expect(restored.mechanic, 'ways');
      expect(restored.ways, 4096);
    });

    test('ways grid config', () {
      const grid = GddGridConfig(
        rows: 3, columns: 5, mechanic: 'ways', ways: 243,
      );
      expect(grid.ways, 243);
      expect(grid.paylines, isNull);
    });

    test('cluster grid config', () {
      const grid = GddGridConfig(
        rows: 7, columns: 7, mechanic: 'cluster',
      );
      expect(grid.mechanic, 'cluster');
      expect(grid.rows, 7);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // SYMBOL TIERS
  // ═══════════════════════════════════════════════════════════════════════

  group('SymbolTier', () {
    test('enum has 8 values', () {
      expect(SymbolTier.values.length, 8);
    });

    test('fromString is case insensitive', () {
      expect(SymbolTierExtension.fromString('low'), SymbolTier.low);
      expect(SymbolTierExtension.fromString('LOW'), SymbolTier.low);
      expect(SymbolTierExtension.fromString('Low'), SymbolTier.low);
      expect(SymbolTierExtension.fromString('WILD'), SymbolTier.wild);
      expect(SymbolTierExtension.fromString('scatter'), SymbolTier.scatter);
    });

    test('fromString defaults to low for unknown', () {
      expect(SymbolTierExtension.fromString('unknown'), SymbolTier.low);
      expect(SymbolTierExtension.fromString(''), SymbolTier.low);
    });

    test('label is capitalized', () {
      expect(SymbolTier.low.label, 'Low');
      expect(SymbolTier.wild.label, 'Wild');
      expect(SymbolTier.premium.label, 'Premium');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // GDD SYMBOL
  // ═══════════════════════════════════════════════════════════════════════

  group('GddSymbol', () {
    test('fromJson parses payouts correctly', () {
      final symbol = GddSymbol.fromJson({
        'id': 'zeus',
        'name': 'Zeus',
        'tier': 'premium',
        'payouts': {'3': 5.0, '4': 10.0, '5': 50.0},
        'isWild': false,
        'isScatter': false,
        'isBonus': false,
      });
      expect(symbol.id, 'zeus');
      expect(symbol.name, 'Zeus');
      expect(symbol.tier, SymbolTier.premium);
      expect(symbol.payouts[3], 5.0);
      expect(symbol.payouts[4], 10.0);
      expect(symbol.payouts[5], 50.0);
    });

    test('wild symbol flags', () {
      const symbol = GddSymbol(
        id: 'wild', name: 'Wild', tier: SymbolTier.wild,
        payouts: {3: 10, 4: 25, 5: 100},
        isWild: true, isScatter: false, isBonus: false,
      );
      expect(symbol.isWild, true);
      expect(symbol.isScatter, false);
      expect(symbol.isBonus, false);
    });

    test('JSON roundtrip', () {
      const symbol = GddSymbol(
        id: 'scatter', name: 'Scatter', tier: SymbolTier.scatter,
        payouts: {3: 2.0, 4: 5.0, 5: 20.0},
        isWild: false, isScatter: true, isBonus: false,
      );
      final json = symbol.toJson();
      final restored = GddSymbol.fromJson(json);
      expect(restored.id, 'scatter');
      expect(restored.tier, SymbolTier.scatter);
      expect(restored.isScatter, true);
      expect(restored.payouts[5], 20.0);
    });

    test('empty payouts', () {
      const symbol = GddSymbol(
        id: 'low1', name: 'Low 1', tier: SymbolTier.low,
        payouts: {},
      );
      expect(symbol.payouts, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // GDD FEATURE
  // ═══════════════════════════════════════════════════════════════════════

  group('GddFeature', () {
    test('GddFeatureType has 10 values', () {
      expect(GddFeatureType.values.length, 10);
    });

    test('fromString parses known types', () {
      expect(GddFeatureTypeExtension.fromString('freeSpins'),
          GddFeatureType.freeSpins);
      expect(GddFeatureTypeExtension.fromString('holdAndSpin'),
          GddFeatureType.holdAndSpin);
      expect(GddFeatureTypeExtension.fromString('cascade'),
          GddFeatureType.cascade);
    });

    test('fromString defaults to bonus for unknown', () {
      expect(GddFeatureTypeExtension.fromString('unknown'),
          GddFeatureType.bonus);
    });

    test('feature JSON roundtrip', () {
      const feature = GddFeature(
        id: 'fs',
        name: 'Free Spins',
        type: GddFeatureType.freeSpins,
        triggerCondition: '3+ scatter',
        initialSpins: 10,
        retriggerable: 1,
        stages: ['FS_TRIGGER', 'FS_ENTER', 'FS_EXIT'],
      );
      final json = feature.toJson();
      final restored = GddFeature.fromJson(json);
      expect(restored.id, 'fs');
      expect(restored.type, GddFeatureType.freeSpins);
      expect(restored.triggerCondition, '3+ scatter');
      expect(restored.initialSpins, 10);
      expect(restored.stages.length, 3);
    });

    test('feature labels are human readable', () {
      expect(GddFeatureType.freeSpins.label, 'Free Spins');
      expect(GddFeatureType.holdAndSpin.label, 'Hold & Spin');
      expect(GddFeatureType.cascade.label, 'Cascade/Tumble');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // GDD MATH MODEL
  // ═══════════════════════════════════════════════════════════════════════

  group('GddMathModel', () {
    test('fromJson with all fields', () {
      final math = GddMathModel.fromJson({
        'rtp': 0.96,
        'volatility': 'high',
        'hitFrequency': 0.28,
        'winTiers': [
          {'id': 't1', 'name': 'Small', 'minMultiplier': 1.0, 'maxMultiplier': 5.0},
        ],
      });
      expect(math.rtp, 0.96);
      expect(math.volatility, 'high');
      expect(math.hitFrequency, 0.28);
      expect(math.winTiers.length, 1);
    });

    test('fromJson with defaults', () {
      final math = GddMathModel.fromJson({});
      expect(math.rtp, 0.96);
      expect(math.volatility, 'medium');
      expect(math.hitFrequency, 0.25);
      expect(math.winTiers, isEmpty);
    });

    test('JSON roundtrip', () {
      const math = GddMathModel(
        rtp: 0.945,
        volatility: 'very_high',
        hitFrequency: 0.22,
        winTiers: [
          GddWinTier(id: 'big', name: 'Big Win', minMultiplier: 10, maxMultiplier: 50),
        ],
      );
      final json = math.toJson();
      final restored = GddMathModel.fromJson(json);
      expect(restored.rtp, 0.945);
      expect(restored.volatility, 'very_high');
      expect(restored.winTiers.length, 1);
      expect(restored.winTiers[0].name, 'Big Win');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // GAME DESIGN DOCUMENT
  // ═══════════════════════════════════════════════════════════════════════

  group('GameDesignDocument', () {
    late GameDesignDocument gdd;

    setUp(() {
      gdd = GameDesignDocument(
        name: 'Zeus Unleashed',
        version: '2.0',
        description: 'Greek mythology themed slot',
        grid: const GddGridConfig(
          rows: 3, columns: 5, mechanic: 'lines', paylines: 20,
        ),
        math: const GddMathModel(
          rtp: 0.96,
          volatility: 'high',
          hitFrequency: 0.28,
          winTiers: [
            GddWinTier(id: 'small', name: 'Small', minMultiplier: 1, maxMultiplier: 5),
            GddWinTier(id: 'big', name: 'Big', minMultiplier: 5, maxMultiplier: 20),
          ],
        ),
        symbols: const [
          GddSymbol(id: 'zeus', name: 'Zeus', tier: SymbolTier.premium,
              payouts: {3: 5, 4: 15, 5: 50}),
          GddSymbol(id: 'athena', name: 'Athena', tier: SymbolTier.high,
              payouts: {3: 3, 4: 10, 5: 30}),
          GddSymbol(id: 'wild', name: 'Wild', tier: SymbolTier.wild,
              payouts: {3: 10, 4: 25, 5: 100}, isWild: true),
          GddSymbol(id: 'scatter', name: 'Scatter', tier: SymbolTier.scatter,
              payouts: {3: 2, 4: 5, 5: 20}, isScatter: true),
          GddSymbol(id: 'bonus', name: 'Bonus', tier: SymbolTier.bonus,
              payouts: {}, isBonus: true),
          GddSymbol(id: 'ten', name: 'Ten', tier: SymbolTier.low,
              payouts: {3: 0.5, 4: 1, 5: 3}),
          GddSymbol(id: 'jack', name: 'Jack', tier: SymbolTier.low,
              payouts: {3: 0.5, 4: 1.5, 5: 4}),
          GddSymbol(id: 'queen', name: 'Queen', tier: SymbolTier.mid,
              payouts: {3: 1, 4: 2, 5: 6}),
        ],
        features: const [
          GddFeature(id: 'fs', name: 'Free Spins', type: GddFeatureType.freeSpins,
              triggerCondition: '3+ scatter', initialSpins: 10),
          GddFeature(id: 'bonus', name: 'Bonus Game', type: GddFeatureType.bonus),
          GddFeature(id: 'cascade', name: 'Cascade', type: GddFeatureType.cascade),
          GddFeature(id: 'jackpot', name: 'Jackpot Wheel', type: GddFeatureType.jackpot),
        ],
        customStages: ['CUSTOM_INTRO', 'CUSTOM_OUTRO'],
      );
    });

    test('stores all fields', () {
      expect(gdd.name, 'Zeus Unleashed');
      expect(gdd.version, '2.0');
      expect(gdd.description, 'Greek mythology themed slot');
      expect(gdd.grid.rows, 3);
      expect(gdd.grid.columns, 5);
      expect(gdd.symbols.length, 8);
      expect(gdd.features.length, 4);
      expect(gdd.customStages.length, 2);
    });

    test('symbolsByTier filters correctly', () {
      final lows = gdd.symbolsByTier(SymbolTier.low);
      expect(lows.length, 2); // ten, jack

      final premiums = gdd.symbolsByTier(SymbolTier.premium);
      expect(premiums.length, 1); // zeus
      expect(premiums[0].id, 'zeus');

      final wilds = gdd.symbolsByTier(SymbolTier.wild);
      expect(wilds.length, 1);
      expect(wilds[0].isWild, true);
    });

    test('feature convenience properties', () {
      expect(gdd.hasFreeSpins, true);
      expect(gdd.hasHoldAndSpin, false);
      expect(gdd.hasCascade, true);
      expect(gdd.hasJackpot, true);
    });

    test('JSON roundtrip preserves all data', () {
      final json = gdd.toJson();
      final jsonStr = jsonEncode(json);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restored = GameDesignDocument.fromJson(decoded);

      expect(restored.name, gdd.name);
      expect(restored.version, gdd.version);
      expect(restored.description, gdd.description);
      expect(restored.grid.rows, gdd.grid.rows);
      expect(restored.grid.columns, gdd.grid.columns);
      expect(restored.grid.mechanic, gdd.grid.mechanic);
      expect(restored.math.rtp, gdd.math.rtp);
      expect(restored.math.volatility, gdd.math.volatility);
      expect(restored.symbols.length, gdd.symbols.length);
      expect(restored.features.length, gdd.features.length);
      expect(restored.customStages, gdd.customStages);

      // Verify symbol data roundtrip
      expect(restored.symbols[0].name, 'Zeus');
      expect(restored.symbols[0].tier, SymbolTier.premium);
      expect(restored.symbols[0].payouts[5], 50);
    });

    test('fromJson with minimal data', () {
      final minimal = GameDesignDocument.fromJson({});
      expect(minimal.name, 'Untitled');
      expect(minimal.version, '1.0');
      expect(minimal.description, isNull);
      expect(minimal.grid.rows, 3);
      expect(minimal.grid.columns, 5);
      expect(minimal.symbols, isEmpty);
      expect(minimal.features, isEmpty);
    });

    // ═══════════════════════════════════════════════════════════════════
    // toRustJson() CONVERSION
    // ═══════════════════════════════════════════════════════════════════

    group('toRustJson()', () {
      test('generates game section', () {
        final rust = gdd.toRustJson();
        final game = rust['game'] as Map<String, dynamic>;
        expect(game['name'], 'Zeus Unleashed');
        expect(game['volatility'], 'high');
        expect(game['target_rtp'], 0.96);
        expect(game['provider'], 'FluxForge');
        expect(game['id'], isNotEmpty);
      });

      test('generates grid section with reels', () {
        final rust = gdd.toRustJson();
        final grid = rust['grid'] as Map<String, dynamic>;
        expect(grid['reels'], 5);
        expect(grid['rows'], 3);
        expect(grid['paylines'], 20);
      });

      test('generates win_mechanism', () {
        final rust = gdd.toRustJson();
        expect(rust['win_mechanism'], 'paylines');
      });

      test('win_mechanism for ways games', () {
        const waysGdd = GameDesignDocument(
          name: 'Ways Game', version: '1.0',
          grid: GddGridConfig(
            rows: 3, columns: 5, mechanic: 'ways', ways: 243,
          ),
          math: GddMathModel(rtp: 0.96, volatility: 'medium', hitFrequency: 0.25),
          symbols: [], features: [],
        );
        final rust = waysGdd.toRustJson();
        expect(rust['win_mechanism'], 'ways_243');
      });

      test('win_mechanism for cluster games', () {
        const clusterGdd = GameDesignDocument(
          name: 'Cluster', version: '1.0',
          grid: GddGridConfig(
            rows: 7, columns: 7, mechanic: 'cluster',
          ),
          math: GddMathModel(rtp: 0.96, volatility: 'medium', hitFrequency: 0.25),
          symbols: [], features: [],
        );
        expect(clusterGdd.toRustJson()['win_mechanism'], 'cluster');
      });

      test('win_mechanism for megaways', () {
        const megawaysGdd = GameDesignDocument(
          name: 'Megaways', version: '1.0',
          grid: GddGridConfig(
            rows: 6, columns: 6, mechanic: 'megaways',
          ),
          math: GddMathModel(rtp: 0.96, volatility: 'high', hitFrequency: 0.25),
          symbols: [], features: [],
        );
        expect(megawaysGdd.toRustJson()['win_mechanism'], 'megaways');
      });

      test('symbols have correct Rust format', () {
        final rust = gdd.toRustJson();
        final symbols = rust['symbols'] as List<dynamic>;
        expect(symbols.length, 8);

        // First symbol (zeus - premium)
        final zeus = symbols[0] as Map<String, dynamic>;
        expect(zeus['id'], 0); // Numeric ID
        expect(zeus['name'], 'Zeus');
        expect(zeus['type'], 'high_pay'); // premium -> high_pay
        expect(zeus['tier'], 4); // premium = 4

        // Wild
        final wild = symbols[2] as Map<String, dynamic>;
        expect(wild['type'], 'wild');
        expect(wild['tier'], 6); // wild = 6

        // Scatter
        final scatter = symbols[3] as Map<String, dynamic>;
        expect(scatter['type'], 'scatter');
        expect(scatter['tier'], 7); // scatter = 7
      });

      test('symbol pays are arrays', () {
        final rust = gdd.toRustJson();
        final symbols = rust['symbols'] as List<dynamic>;
        final zeus = symbols[0] as Map<String, dynamic>;
        final pays = zeus['pays'] as List<dynamic>;
        // payouts: {3: 5, 4: 15, 5: 50} -> [0, 0, 0, 5, 15, 50]
        expect(pays.length, 6);
        expect(pays[0], 0);
        expect(pays[3], 5);
        expect(pays[4], 15);
        expect(pays[5], 50);
      });

      test('symbol weights follow tier distribution', () {
        final rust = gdd.toRustJson();
        final mathSection = rust['math'] as Map<String, dynamic>;
        final weights = mathSection['symbol_weights'] as Map<String, dynamic>;

        // Wild should have lowest weight (2 per reel)
        final wildWeights = weights['Wild'] as List<dynamic>;
        expect(wildWeights.length, 5); // 5 reels
        expect(wildWeights[0], 2);

        // Low symbols should have highest weight (18 per reel)
        final tenWeights = weights['Ten'] as List<dynamic>;
        expect(tenWeights[0], 18);

        // Mid symbols (12 per reel)
        final queenWeights = weights['Queen'] as List<dynamic>;
        expect(queenWeights[0], 12);

        // High symbols (8 per reel)
        final athenaWeights = weights['Athena'] as List<dynamic>;
        expect(athenaWeights[0], 8);

        // Premium (5 per reel)
        final zeusWeights = weights['Zeus'] as List<dynamic>;
        expect(zeusWeights[0], 5);

        // Scatter (3 per reel)
        final scatterWeights = weights['Scatter'] as List<dynamic>;
        expect(scatterWeights[0], 3);
      });

      test('features have Rust format', () {
        final rust = gdd.toRustJson();
        final features = rust['features'] as List<dynamic>;
        expect(features.length, 4);

        final fs = features[0] as Map<String, dynamic>;
        expect(fs['type'], 'free_spins');
        expect(fs['trigger'], '3+ scatter');
        expect(fs['spins'], 10);
      });

      test('game ID is normalized', () {
        final rust = gdd.toRustJson();
        final game = rust['game'] as Map<String, dynamic>;
        final id = game['id'] as String;
        // Should be lowercase with underscores
        expect(id, matches(RegExp(r'^[a-z0-9_]+$')));
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // GDD WIN TIER
  // ═══════════════════════════════════════════════════════════════════════

  group('GddWinTier', () {
    test('JSON roundtrip', () {
      const tier = GddWinTier(
        id: 'mega', name: 'Mega Win',
        minMultiplier: 30.0, maxMultiplier: 60.0,
      );
      final json = tier.toJson();
      final restored = GddWinTier.fromJson(json);
      expect(restored.id, 'mega');
      expect(restored.name, 'Mega Win');
      expect(restored.minMultiplier, 30.0);
      expect(restored.maxMultiplier, 60.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // GDD IMPORT RESULT
  // ═══════════════════════════════════════════════════════════════════════

  group('GddImportResult', () {
    test('hasErrors and hasWarnings', () {
      const withErrors = GddImportResult(
        gdd: GameDesignDocument(
          name: 'Test', version: '1.0',
          grid: GddGridConfig(rows: 3, columns: 5, mechanic: 'lines'),
          math: GddMathModel(rtp: 0.96, volatility: 'medium', hitFrequency: 0.25),
          symbols: [], features: [],
        ),
        generatedStages: [],
        generatedSymbols: [],
        errors: ['Missing symbols'],
        warnings: ['Low RTP'],
      );
      expect(withErrors.hasErrors, true);
      expect(withErrors.hasWarnings, true);
    });

    test('clean result has no errors', () {
      const clean = GddImportResult(
        gdd: GameDesignDocument(
          name: 'Test', version: '1.0',
          grid: GddGridConfig(rows: 3, columns: 5, mechanic: 'lines'),
          math: GddMathModel(rtp: 0.96, volatility: 'medium', hitFrequency: 0.25),
          symbols: [], features: [],
        ),
        generatedStages: ['SPIN_START', 'SPIN_END'],
        generatedSymbols: [],
      );
      expect(clean.hasErrors, false);
      expect(clean.hasWarnings, false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // EDGE CASES
  // ═══════════════════════════════════════════════════════════════════════

  group('Edge cases', () {
    test('GDD with no symbols', () {
      const gdd = GameDesignDocument(
        name: 'Empty', version: '1.0',
        grid: GddGridConfig(rows: 3, columns: 5, mechanic: 'lines'),
        math: GddMathModel(rtp: 0.96, volatility: 'medium', hitFrequency: 0.25),
        symbols: [],
        features: [],
      );
      final rust = gdd.toRustJson();
      expect((rust['symbols'] as List).isEmpty, true);
    });

    test('GDD with single symbol', () {
      const gdd = GameDesignDocument(
        name: 'Single', version: '1.0',
        grid: GddGridConfig(rows: 3, columns: 5, mechanic: 'lines'),
        math: GddMathModel(rtp: 0.96, volatility: 'medium', hitFrequency: 0.25),
        symbols: [
          GddSymbol(id: 'only', name: 'Only', tier: SymbolTier.mid, payouts: {3: 1}),
        ],
        features: [],
      );
      expect(gdd.symbols.length, 1);
      expect(gdd.hasFreeSpins, false);
      expect(gdd.hasHoldAndSpin, false);
    });

    test('toRustJson with empty payouts generates zero array', () {
      const gdd = GameDesignDocument(
        name: 'Test', version: '1.0',
        grid: GddGridConfig(rows: 3, columns: 5, mechanic: 'lines'),
        math: GddMathModel(rtp: 0.96, volatility: 'medium', hitFrequency: 0.25),
        symbols: [
          GddSymbol(id: 'bonus', name: 'Bonus', tier: SymbolTier.bonus,
              payouts: {}, isBonus: true),
        ],
        features: [],
      );
      final rust = gdd.toRustJson();
      final symbols = rust['symbols'] as List;
      final bonus = symbols[0] as Map<String, dynamic>;
      final pays = bonus['pays'] as List;
      expect(pays, [0, 0, 0, 0, 0]);
    });

    test('complete JSON parse from raw string', () {
      const jsonStr = '''
      {
        "name": "Egyptian Gold",
        "version": "1.0",
        "grid": {
          "rows": 3,
          "reels": 5,
          "mechanic": "lines",
          "paylines": 10
        },
        "math": {
          "rtp": 0.95,
          "volatility": "high",
          "hitFrequency": 0.30
        },
        "symbols": [
          {"id": "ra", "name": "Ra", "tier": "premium", "payouts": {"3": 8, "4": 20, "5": 80}},
          {"id": "scarab", "name": "Scarab", "tier": "low", "payouts": {"3": 0.5, "4": 1, "5": 2}}
        ],
        "features": [
          {"id": "fs", "name": "Tomb Spins", "type": "freeSpins", "initialSpins": 12}
        ]
      }
      ''';
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final gdd = GameDesignDocument.fromJson(json);

      expect(gdd.name, 'Egyptian Gold');
      expect(gdd.grid.columns, 5);
      expect(gdd.grid.paylines, 10);
      expect(gdd.math.rtp, 0.95);
      expect(gdd.symbols.length, 2);
      expect(gdd.symbols[0].name, 'Ra');
      expect(gdd.symbols[0].tier, SymbolTier.premium);
      expect(gdd.features.length, 1);
      expect(gdd.features[0].type, GddFeatureType.freeSpins);
      expect(gdd.hasFreeSpins, true);

      // Verify Rust conversion works
      final rust = gdd.toRustJson();
      expect(rust['game']['name'], 'Egyptian Gold');
      expect(rust['grid']['reels'], 5);
    });
  });
}
