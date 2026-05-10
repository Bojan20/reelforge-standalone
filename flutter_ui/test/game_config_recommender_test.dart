/// FLUX_MASTER_TODO 0.5 F.2 — Game Config Recommender heuristic tests.
///
/// Pin behavior za rule engine. Bez ovih testova bilo koja "small tweak"
/// na heuristics može razbiti business logic invariante (npr. UKGC RTP
/// floor, max-win cap, auto-spin zabrana).

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/game_config_recommender.dart';

void main() {
  final r = GameConfigRecommender.instance;

  group('Recommender invariants — RTP bounds', () {
    test('RTP nikad ispod jurisdikcijskog floor-a', () {
      for (final mkt in MarketSegment.values) {
        for (final p in PlayerProfile.values) {
          final rec = r.recommend(market: mkt, player: p);
          expect(rec.math.rtp, greaterThanOrEqualTo(mkt.minRtp),
              reason: '${mkt.name}/${p.name} pao ispod minRtp');
          expect(rec.math.rtp, lessThanOrEqualTo(mkt.maxRtp),
              reason: '${mkt.name}/${p.name} prešao maxRtp');
        }
      }
    });
  });

  group('Recommender invariants — Max win cap', () {
    test('user target preko cap-a se clamp-uje', () {
      final rec = r.recommend(
        market: MarketSegment.ukRetail,
        player: PlayerProfile.engaged,
        targetMaxWin: 99999,
      );
      expect(rec.math.maxWinMultiplier,
          equals(MarketSegment.ukRetail.maxWinCap));
    });

    test('user target ispod cap-a se prihvata', () {
      final rec = r.recommend(
        market: MarketSegment.ukRetail,
        player: PlayerProfile.engaged,
        targetMaxWin: 1000,
      );
      expect(rec.math.maxWinMultiplier, equals(1000));
    });
  });

  group('Recommender invariants — Volatility bounds', () {
    test('volatility u rasponu [1..10] uvek', () {
      for (final mkt in MarketSegment.values) {
        for (final p in PlayerProfile.values) {
          final rec = r.recommend(market: mkt, player: p);
          expect(rec.math.volatility, inInclusiveRange(1, 10));
        }
      }
    });

    test('UKGC clamp volatility na 7', () {
      final rec = r.recommend(
        market: MarketSegment.ukRetail,
        player: PlayerProfile.highStakes,
      );
      expect(rec.math.volatility, lessThanOrEqualTo(7),
          reason: 'UKGC clamp pravilo nije primenjeno');
    });
  });

  group('Recommender invariants — Compliance flags', () {
    test('UKGC ne dozvoljava auto-spin', () {
      final rec = r.recommend(
        market: MarketSegment.ukRetail,
        player: PlayerProfile.casual,
      );
      expect(rec.compliance.autoSpinAllowed, isFalse);
    });

    test('UKGC ima najstroziji near-miss cap (2%)', () {
      final rec = r.recommend(
        market: MarketSegment.ukRetail,
        player: PlayerProfile.casual,
      );
      expect(rec.compliance.nearMissQuotaCap, equals(0.02));
    });

    test('LDW guard required za sve regulisane jurisdikcije', () {
      for (final mkt in MarketSegment.values) {
        if (mkt == MarketSegment.generic) continue;
        final rec = r.recommend(market: mkt, player: PlayerProfile.engaged);
        expect(rec.compliance.requiresLdwGuard, isTrue,
            reason: '${mkt.name} mora zahtevati LDW guard');
      }
    });
  });

  group('Recommender invariants — Feature stack', () {
    test('Free Spins ON za sve player profile-e', () {
      for (final p in PlayerProfile.values) {
        final rec = r.recommend(market: MarketSegment.generic, player: p);
        expect(rec.features.freeSpins, isTrue,
            reason: '${p.name} mora imati FS (industry default)');
      }
    });

    test('UKGC ne dozvoljava Gamble feature', () {
      final rec = r.recommend(
        market: MarketSegment.ukRetail,
        player: PlayerProfile.engaged,
      );
      expect(rec.features.gamble, isFalse);
    });

    test('high-stakes dobija wild multiplier + expanding wilds', () {
      final rec = r.recommend(
        market: MarketSegment.mgaCrypto,
        player: PlayerProfile.highStakes,
      );
      expect(rec.features.wildMultiplier, isTrue);
      expect(rec.features.expandingWilds, isTrue);
    });
  });

  group('Recommender invariants — Rationale completeness', () {
    test('rationale ima entry za svaki kritičan field', () {
      final rec = r.recommend(
        market: MarketSegment.mgaCrypto,
        player: PlayerProfile.engaged,
      );
      final fields = rec.rationale.map((r) => r.field).toSet();
      // 5 must-have fields (math + compliance core)
      expect(fields, contains('rtp'));
      expect(fields, contains('volatility'));
      expect(fields, contains('hit_frequency'));
      expect(fields, contains('max_win_multiplier'));
      expect(fields.where((f) => f.startsWith('compliance.')).length,
          greaterThanOrEqualTo(4));
    });

    test('svaki rationale entry ima non-empty source rule ID', () {
      final rec = r.recommend(
        market: MarketSegment.generic,
        player: PlayerProfile.casual,
      );
      for (final r in rec.rationale) {
        expect(r.source, isNotEmpty);
        expect(r.reason, isNotEmpty);
      }
    });
  });

  group('Recommender invariants — Idempotency', () {
    test('isti input → isti output (no random / no time-dependent)', () {
      final a = r.recommend(
        market: MarketSegment.njBalanced,
        player: PlayerProfile.engaged,
        targetMaxWin: 5000,
      );
      final b = r.recommend(
        market: MarketSegment.njBalanced,
        player: PlayerProfile.engaged,
        targetMaxWin: 5000,
      );
      expect(a.math.toJson(), equals(b.math.toJson()));
      expect(a.features.toJson(), equals(b.features.toJson()));
      expect(a.compliance.toJson(), equals(b.compliance.toJson()));
    });
  });

  group('Recommender invariants — Audio palette', () {
    test('NV high-roller → classical (heritage override)', () {
      for (final p in PlayerProfile.values) {
        final rec =
            r.recommend(market: MarketSegment.nvHighRoller, player: p);
        expect(rec.audioPalette, equals(AudioPaletteStyle.classical));
      }
    });
  });
}
