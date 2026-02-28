import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/aurexis_retheme.dart';
import 'package:fluxforge_ui/services/aurexis_retheme_service.dart';

void main() {
  group('ReThemeFileMapping', () {
    test('isMatched returns true when target exists', () {
      const mapping = ReThemeFileMapping(
        sourcePath: 'zeus_spin.wav',
        targetPath: 'egyptian_spin.wav',
        confidenceScore: 0.95,
      );
      expect(mapping.isMatched, true);
      expect(mapping.confidence, MatchConfidence.high);
    });

    test('isMatched returns false when target is null', () {
      const mapping = ReThemeFileMapping(sourcePath: 'zeus_spin.wav');
      expect(mapping.isMatched, false);
      expect(mapping.confidence, MatchConfidence.none);
    });

    test('needsReview for low confidence matches', () {
      const mapping = ReThemeFileMapping(
        sourcePath: 'zeus_spin.wav',
        targetPath: 'pharaoh_start.wav',
        confidenceScore: 0.55,
      );
      expect(mapping.needsReview, true);
    });

    test('JSON round-trip', () {
      const mapping = ReThemeFileMapping(
        sourcePath: 'zeus_spin.wav',
        targetPath: 'egyptian_spin.wav',
        stageName: 'Spin Start',
        confidenceScore: 0.92,
        strategy: ReThemeMatchStrategy.namePattern,
        userConfirmed: true,
      );
      final json = mapping.toJson();
      final restored = ReThemeFileMapping.fromJson(json);
      expect(restored.sourcePath, mapping.sourcePath);
      expect(restored.targetPath, mapping.targetPath);
      expect(restored.stageName, mapping.stageName);
      expect(restored.confidenceScore, mapping.confidenceScore);
      expect(restored.strategy, mapping.strategy);
      expect(restored.userConfirmed, mapping.userConfirmed);
    });
  });

  group('ReThemeMapping', () {
    test('match statistics are correct', () {
      final mapping = ReThemeMapping(
        sourceTheme: 'Zeus',
        targetTheme: 'Egyptian',
        sourceDir: '/audio/zeus/',
        targetDir: '/audio/egyptian/',
        mappings: [
          const ReThemeFileMapping(
            sourcePath: 'spin.wav',
            targetPath: 'spin.wav',
            confidenceScore: 0.95,
          ),
          const ReThemeFileMapping(
            sourcePath: 'win.wav',
            targetPath: 'win.wav',
            confidenceScore: 0.55,
          ),
          const ReThemeFileMapping(sourcePath: 'bonus.wav'),
        ],
      );
      expect(mapping.totalCount, 3);
      expect(mapping.matchedCount, 2);
      expect(mapping.unmatchedCount, 1);
      expect(mapping.reviewCount, 1);
    });

    test('reversed mapping swaps source and target', () {
      final mapping = ReThemeMapping(
        sourceTheme: 'Zeus',
        targetTheme: 'Egyptian',
        sourceDir: '/zeus/',
        targetDir: '/egyptian/',
        mappings: [
          const ReThemeFileMapping(
            sourcePath: 'zeus_spin.wav',
            targetPath: 'egyptian_spin.wav',
            confidenceScore: 0.95,
          ),
        ],
      );
      final reversed = mapping.reversed();
      expect(reversed.sourceTheme, 'Egyptian');
      expect(reversed.targetTheme, 'Zeus');
      expect(reversed.mappings[0].sourcePath, 'egyptian_spin.wav');
      expect(reversed.mappings[0].targetPath, 'zeus_spin.wav');
    });

    test('JSON round-trip', () {
      final mapping = ReThemeMapping(
        sourceTheme: 'Zeus',
        targetTheme: 'Egyptian',
        sourceDir: '/zeus/',
        targetDir: '/egyptian/',
        mappings: [
          const ReThemeFileMapping(
            sourcePath: 'spin.wav',
            targetPath: 'spin.wav',
            confidenceScore: 0.95,
          ),
        ],
      );
      final jsonStr = mapping.toJsonString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restored = ReThemeMapping.fromJson(json);
      expect(restored.sourceTheme, mapping.sourceTheme);
      expect(restored.targetTheme, mapping.targetTheme);
      expect(restored.mappings.length, 1);
    });
  });

  group('AurexisReThemeService', () {
    test('name pattern matching finds exact stripped matches', () {
      final mapping = AurexisReThemeService.autoMatch(
        sourceTheme: 'Zeus',
        targetTheme: 'Egyptian',
        sourceFiles: [
          'zeus_spin_start.wav',
          'zeus_spin_stop.wav',
          'zeus_win_small.wav',
        ],
        targetFiles: [
          'egyptian_spin_start.wav',
          'egyptian_spin_stop.wav',
          'egyptian_win_small.wav',
        ],
        strategy: ReThemeMatchStrategy.namePattern,
        fuzzyThreshold: 0.7,
      );
      expect(mapping.matchedCount, 3);
      expect(mapping.unmatchedCount, 0);
    });

    test('unmatched files remain unmatched', () {
      final mapping = AurexisReThemeService.autoMatch(
        sourceTheme: 'Zeus',
        targetTheme: 'Egyptian',
        sourceFiles: ['zeus_unique.wav'],
        targetFiles: ['egyptian_different.wav'],
        strategy: ReThemeMatchStrategy.namePattern,
        fuzzyThreshold: 0.9,
      );
      expect(mapping.unmatchedCount, 1);
    });

    test('overrideMapping replaces target', () {
      final mapping = ReThemeMapping(
        sourceTheme: 'A',
        targetTheme: 'B',
        sourceDir: '/',
        targetDir: '/',
        mappings: [
          const ReThemeFileMapping(sourcePath: 'test.wav'),
        ],
      );
      final updated = AurexisReThemeService.overrideMapping(
        mapping: mapping,
        index: 0,
        newTarget: 'matched.wav',
      );
      expect(updated.mappings[0].targetPath, 'matched.wav');
      expect(updated.mappings[0].userConfirmed, true);
      expect(updated.mappings[0].confidenceScore, 1.0);
    });
  });

  group('MatchConfidence', () {
    test('fromScore returns correct levels', () {
      expect(MatchConfidence.fromScore(0.95), MatchConfidence.high);
      expect(MatchConfidence.fromScore(0.75), MatchConfidence.medium);
      expect(MatchConfidence.fromScore(0.55), MatchConfidence.low);
      expect(MatchConfidence.fromScore(0.35), MatchConfidence.veryLow);
      expect(MatchConfidence.fromScore(0.1), MatchConfidence.none);
    });
  });
}
