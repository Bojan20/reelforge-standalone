/// Fuzzy Search Engine
///
/// High-performance fuzzy matching algorithm for Command Palette.
/// Inspired by fzf/Sublime Text fuzzy finder scoring:
/// - Sequential character matching with gap penalties
/// - Bonus for consecutive matches, word boundaries, camelCase
/// - Case-insensitive with case-match bonus
/// - Returns match indices for highlighting
library;

/// Result of a fuzzy match operation
class FuzzyMatch {
  /// Overall match score (higher = better match)
  final int score;

  /// Indices of matched characters in the target string
  final List<int> matchedIndices;

  const FuzzyMatch({required this.score, required this.matchedIndices});

  static const noMatch = FuzzyMatch(score: -1, matchedIndices: []);

  bool get isMatch => score >= 0;
}

/// Fuzzy search scoring constants
class _Score {
  // Match bonuses
  static const int adjacentMatch = 15; // Consecutive chars
  static const int separatorBonus = 30; // Match after _ - / . space
  static const int camelBonus = 30; // Match on camelCase boundary
  static const int firstCharBonus = 15; // Match on first char
  static const int exactCaseBonus = 5; // Exact case match
  static const int prefixBonus = 50; // Query is prefix of target

  // Penalties
  static const int gapPenalty = -5; // Per-char gap
  static const int maxGapPenalty = -50; // Cap gap penalty
  static const int unmatchedLeadingPenalty = -3; // Before first match
  static const int maxUnmatchedLeading = -15; // Cap leading penalty
}

/// Perform fuzzy match of [query] against [target]
///
/// Returns [FuzzyMatch] with score and matched indices.
/// Returns [FuzzyMatch.noMatch] if no match found.
FuzzyMatch fuzzyMatch(String query, String target) {
  if (query.isEmpty) return const FuzzyMatch(score: 0, matchedIndices: []);
  if (target.isEmpty) return FuzzyMatch.noMatch;

  final queryLower = query.toLowerCase();
  final targetLower = target.toLowerCase();
  final queryLen = queryLower.length;
  final targetLen = targetLower.length;

  // Quick check: all query chars must exist in target
  {
    int qi = 0;
    for (int ti = 0; ti < targetLen && qi < queryLen; ti++) {
      if (queryLower.codeUnitAt(qi) == targetLower.codeUnitAt(ti)) {
        qi++;
      }
    }
    if (qi < queryLen) return FuzzyMatch.noMatch;
  }

  // Exact prefix match bonus
  if (targetLower.startsWith(queryLower)) {
    final indices = List<int>.generate(queryLen, (i) => i);
    int score = _Score.prefixBonus + queryLen * _Score.adjacentMatch;
    // Case bonus
    for (int i = 0; i < queryLen; i++) {
      if (query.codeUnitAt(i) == target.codeUnitAt(i)) {
        score += _Score.exactCaseBonus;
      }
    }
    return FuzzyMatch(score: score, matchedIndices: indices);
  }

  // Forward pass: find best matching positions using greedy with scoring
  final bestIndices = <int>[];
  final bestScoreRef = [-1]; // Mutable ref so recursive calls can prune

  // Try recursive matching with limited depth for quality
  _fuzzyMatchRecursive(
    queryLower,
    targetLower,
    query,
    target,
    0,
    0,
    [],
    0,
    bestIndices,
    bestScoreRef,
    0,
  );

  if (bestIndices.isEmpty) return FuzzyMatch.noMatch;

  return FuzzyMatch(score: bestScoreRef[0], matchedIndices: bestIndices);
}

void _fuzzyMatchRecursive(
  String queryLower,
  String targetLower,
  String query,
  String target,
  int queryIdx,
  int targetIdx,
  List<int> currentIndices,
  int currentScore,
  List<int> bestIndices,
  List<int> bestScoreRef, // Mutable [bestScore] so branches can prune
  int depth,
) {
  // Limit recursion depth for performance
  if (depth > 10) return;

  final queryLen = queryLower.length;
  final targetLen = targetLower.length;

  if (queryIdx == queryLen) {
    // All query chars matched — compute final score
    int score = currentScore;

    // Leading gap penalty
    if (currentIndices.isNotEmpty) {
      final leading = currentIndices[0];
      score += (leading * _Score.unmatchedLeadingPenalty)
          .clamp(_Score.maxUnmatchedLeading, 0);
    }

    if (score > bestScoreRef[0]) {
      bestScoreRef[0] = score;
      bestIndices.clear();
      bestIndices.addAll(currentIndices);
    }
    return;
  }

  if (targetIdx >= targetLen) return;

  // Remaining chars in query vs remaining chars in target
  final queryRemaining = queryLen - queryIdx;
  final targetRemaining = targetLen - targetIdx;
  if (queryRemaining > targetRemaining) return;

  final qChar = queryLower.codeUnitAt(queryIdx);

  for (int ti = targetIdx; ti < targetLen; ti++) {
    if (targetLower.codeUnitAt(ti) != qChar) continue;

    int matchScore = 0;

    // Consecutive match bonus
    if (currentIndices.isNotEmpty && currentIndices.last == ti - 1) {
      matchScore += _Score.adjacentMatch;
    }

    // Gap penalty (non-consecutive)
    if (currentIndices.isNotEmpty && currentIndices.last < ti - 1) {
      final gap = ti - currentIndices.last - 1;
      matchScore += (gap * _Score.gapPenalty).clamp(_Score.maxGapPenalty, 0);
    }

    // First character bonus
    if (ti == 0) {
      matchScore += _Score.firstCharBonus;
    }

    // Word boundary bonus (after separator)
    if (ti > 0) {
      final prevChar = target.codeUnitAt(ti - 1);
      if (_isSeparator(prevChar)) {
        matchScore += _Score.separatorBonus;
      }
      // CamelCase boundary
      if (_isLower(target.codeUnitAt(ti - 1)) &&
          _isUpper(target.codeUnitAt(ti))) {
        matchScore += _Score.camelBonus;
      }
    }

    // Exact case bonus
    if (query.codeUnitAt(queryIdx) == target.codeUnitAt(ti)) {
      matchScore += _Score.exactCaseBonus;
    }

    currentIndices.add(ti);
    _fuzzyMatchRecursive(
      queryLower,
      targetLower,
      query,
      target,
      queryIdx + 1,
      ti + 1,
      currentIndices,
      currentScore + matchScore,
      bestIndices,
      bestScoreRef,
      depth + 1,
    );
    currentIndices.removeLast();

    // Only try first 3 positions for each query char to limit search space
    if (depth > 5) break;
  }
}

bool _isSeparator(int charCode) {
  return charCode == 0x20 || // space
      charCode == 0x5F || // _
      charCode == 0x2D || // -
      charCode == 0x2F || // /
      charCode == 0x2E || // .
      charCode == 0x5C; // backslash
}

bool _isUpper(int charCode) => charCode >= 0x41 && charCode <= 0x5A;
bool _isLower(int charCode) => charCode >= 0x61 && charCode <= 0x7A;

/// Search a list of items with fuzzy matching
///
/// Returns items sorted by score (best first), filtered to matches only.
List<FuzzySearchResult<T>> fuzzySearch<T>(
  String query,
  List<T> items,
  String Function(T item) getText, {
  List<String> Function(T item)? getKeywords,
}) {
  if (query.isEmpty) {
    return items
        .map((item) => FuzzySearchResult(
              item: item,
              match: const FuzzyMatch(score: 0, matchedIndices: []),
              matchField: MatchField.label,
            ))
        .toList();
  }

  final results = <FuzzySearchResult<T>>[];

  for (final item in items) {
    final text = getText(item);
    final match = fuzzyMatch(query, text);

    if (match.isMatch) {
      results.add(FuzzySearchResult(
        item: item,
        match: match,
        matchField: MatchField.label,
      ));
      continue;
    }

    // Try keywords
    if (getKeywords != null) {
      final keywords = getKeywords(item);
      bool found = false;
      for (final kw in keywords) {
        final kwMatch = fuzzyMatch(query, kw);
        if (kwMatch.isMatch) {
          results.add(FuzzySearchResult(
            item: item,
            match: kwMatch,
            matchField: MatchField.keyword,
          ));
          found = true;
          break;
        }
      }
      if (found) continue;
    }
  }

  results.sort((a, b) => b.match.score.compareTo(a.match.score));
  return results;
}

enum MatchField { label, keyword }

class FuzzySearchResult<T> {
  final T item;
  final FuzzyMatch match;
  final MatchField matchField;

  const FuzzySearchResult({
    required this.item,
    required this.match,
    required this.matchField,
  });
}
