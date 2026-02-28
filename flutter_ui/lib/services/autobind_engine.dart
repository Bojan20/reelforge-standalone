/// AutoBind Engine — SlotLab Middleware §6
///
/// Parses audio filenames and automatically assigns them to behavior nodes.
/// Primary workflow: folder drop → parse → auto-bind → coverage update.
///
/// 7-step pipeline:
///   1. Parse filename
///   2. Identify phase (base, freespin, bonus, jackpot, gamble, ui)
///   3. Identify system (reel, cascade, win, feature, jackpot, ui, music, ambience)
///   4. Identify action (stop, land, start, step, end, evaluate, enter, exit, tick, press)
///   5. Identify modifiers (rX, cX, mX, jt_X)
///   6. Map to Behavior Node
///   7. Map to Engine Hook(s)
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §6

import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/behavior_tree_models.dart';

/// Result of auto-binding a single file
class AutoBindResult {
  /// Original file path
  final String filePath;

  /// Parsed filename (without extension)
  final String parsedName;

  /// Matched behavior node ID (null if no match)
  final String? matchedNodeId;

  /// Matched behavior node type (null if no match)
  final BehaviorNodeType? matchedNodeType;

  /// Detected variant index
  final int variantIndex;

  /// Detected phase/context
  final String? detectedPhase;

  /// Confidence score (0.0-1.0)
  final double confidence;

  /// Matching strategy used
  final MatchStrategy strategy;

  /// Category of result
  AutoBindCategory get category {
    if (confidence >= 0.9) return AutoBindCategory.autoBound;
    if (confidence >= 0.7) return AutoBindCategory.suggested;
    return AutoBindCategory.needsAttention;
  }

  const AutoBindResult({
    required this.filePath,
    required this.parsedName,
    this.matchedNodeId,
    this.matchedNodeType,
    this.variantIndex = 0,
    this.detectedPhase,
    this.confidence = 0.0,
    this.strategy = MatchStrategy.none,
  });
}

/// Category of auto-bind result
enum AutoBindCategory {
  /// >= 90% confidence, auto-bound immediately
  autoBound,
  /// 70-89% confidence, show for one-click confirm
  suggested,
  /// < 70% confidence, needs manual assignment
  needsAttention,
}

/// Strategy that produced the match
enum MatchStrategy {
  /// No match found
  none,
  /// Strict token matching (primary)
  strict,
  /// Token reorder
  tokenReorder,
  /// Abbreviation expansion
  abbreviation,
  /// CamelCase splitting
  camelCase,
  /// Substring matching
  substring,
  /// Folder context matching
  folderContext,
  /// Numeric suffix detection
  numericSuffix,
}

/// Result of processing an entire folder
class AutoBindBatchResult {
  /// All individual results
  final List<AutoBindResult> results;

  /// Timestamp
  final DateTime timestamp;

  /// Total files scanned
  int get totalFiles => results.length;

  /// Auto-bound count (>= 90%)
  int get autoBoundCount =>
      results.where((r) => r.category == AutoBindCategory.autoBound).length;

  /// Suggested count (70-89%)
  int get suggestedCount =>
      results.where((r) => r.category == AutoBindCategory.suggested).length;

  /// Needs attention count (< 70%)
  int get needsAttentionCount =>
      results.where((r) => r.category == AutoBindCategory.needsAttention).length;

  /// Overall coverage percentage
  double get coveragePercent =>
      totalFiles > 0 ? (autoBoundCount + suggestedCount) / totalFiles : 0.0;

  const AutoBindBatchResult({
    required this.results,
    required this.timestamp,
  });
}

/// The AutoBind Engine singleton
class AutoBindEngine {
  AutoBindEngine._();
  static final AutoBindEngine instance = AutoBindEngine._();

  // Phase tokens → context ID
  static const Map<String, String> _phaseTokens = {
    'base': 'base',
    'main': 'base',
    'basegame': 'base',
    'base_game': 'base',
    'freespin': 'freeSpins',
    'freespins': 'freeSpins',
    'free_spin': 'freeSpins',
    'free_spins': 'freeSpins',
    'fs': 'freeSpins',
    'bonus': 'bonus',
    'bonusgame': 'bonus',
    'bonus_game': 'bonus',
    'jackpot': 'jackpot',
    'jp': 'jackpot',
    'gamble': 'gamble',
    'doubleup': 'gamble',
    'double_up': 'gamble',
    'ui': 'ui',
    'interface': 'ui',
  };

  // System tokens → BehaviorCategory
  static const Map<String, BehaviorCategory> _systemTokens = {
    'reel': BehaviorCategory.reels,
    'reels': BehaviorCategory.reels,
    'spin': BehaviorCategory.reels,
    'cascade': BehaviorCategory.cascade,
    'avalanche': BehaviorCategory.cascade,
    'tumble': BehaviorCategory.cascade,
    'win': BehaviorCategory.win,
    'payout': BehaviorCategory.win,
    'feature': BehaviorCategory.feature,
    'feat': BehaviorCategory.feature,
    'bonus': BehaviorCategory.feature,
    'jackpot': BehaviorCategory.jackpot,
    'jp': BehaviorCategory.jackpot,
    'progressive': BehaviorCategory.jackpot,
    'button': BehaviorCategory.ui,
    'ui': BehaviorCategory.ui,
    'click': BehaviorCategory.ui,
    'popup': BehaviorCategory.ui,
    'toggle': BehaviorCategory.ui,
    'session': BehaviorCategory.system,
    'system': BehaviorCategory.system,
  };

  // Action tokens → BehaviorNodeType
  static const Map<String, Map<BehaviorCategory, BehaviorNodeType>> _actionTokens = {
    'stop': {BehaviorCategory.reels: BehaviorNodeType.reelStop},
    'land': {BehaviorCategory.reels: BehaviorNodeType.reelLand},
    'anticipation': {BehaviorCategory.reels: BehaviorNodeType.reelAnticipation},
    'antic': {BehaviorCategory.reels: BehaviorNodeType.reelAnticipation},
    'nudge': {BehaviorCategory.reels: BehaviorNodeType.reelNudge},
    'start': {
      BehaviorCategory.cascade: BehaviorNodeType.cascadeStart,
      BehaviorCategory.system: BehaviorNodeType.systemSessionStart,
    },
    'step': {BehaviorCategory.cascade: BehaviorNodeType.cascadeStep},
    'end': {
      BehaviorCategory.cascade: BehaviorNodeType.cascadeEnd,
      BehaviorCategory.system: BehaviorNodeType.systemSessionEnd,
    },
    'small': {BehaviorCategory.win: BehaviorNodeType.winSmall},
    'big': {BehaviorCategory.win: BehaviorNodeType.winBig},
    'mega': {BehaviorCategory.win: BehaviorNodeType.winMega},
    'epic': {BehaviorCategory.win: BehaviorNodeType.winMega},
    'ultra': {BehaviorCategory.win: BehaviorNodeType.winMega},
    'countup': {BehaviorCategory.win: BehaviorNodeType.winCountup},
    'counter': {BehaviorCategory.win: BehaviorNodeType.winCountup},
    'tick': {BehaviorCategory.win: BehaviorNodeType.winCountup},
    'rollup': {BehaviorCategory.win: BehaviorNodeType.winCountup},
    'intro': {BehaviorCategory.feature: BehaviorNodeType.featureIntro},
    'enter': {BehaviorCategory.feature: BehaviorNodeType.featureIntro},
    'loop': {BehaviorCategory.feature: BehaviorNodeType.featureLoop},
    'outro': {BehaviorCategory.feature: BehaviorNodeType.featureOutro},
    'exit': {BehaviorCategory.feature: BehaviorNodeType.featureOutro},
    'mini': {BehaviorCategory.jackpot: BehaviorNodeType.jackpotMini},
    'minor': {BehaviorCategory.jackpot: BehaviorNodeType.jackpotMini},
    'major': {BehaviorCategory.jackpot: BehaviorNodeType.jackpotMajor},
    'grand': {BehaviorCategory.jackpot: BehaviorNodeType.jackpotGrand},
    'mega_jp': {BehaviorCategory.jackpot: BehaviorNodeType.jackpotGrand},
    'press': {BehaviorCategory.ui: BehaviorNodeType.uiButton},
    'click': {BehaviorCategory.ui: BehaviorNodeType.uiButton},
    'release': {BehaviorCategory.ui: BehaviorNodeType.uiButton},
    'show': {BehaviorCategory.ui: BehaviorNodeType.uiPopup},
    'dismiss': {BehaviorCategory.ui: BehaviorNodeType.uiPopup},
    'change': {BehaviorCategory.ui: BehaviorNodeType.uiToggle},
  };

  // Abbreviation expansions
  static const Map<String, String> _abbreviations = {
    'rs': 'reel_stop',
    'rl': 'reel_land',
    'ra': 'reel_anticipation',
    'rn': 'reel_nudge',
    'cs': 'cascade_start',
    'cst': 'cascade_step',
    'ce': 'cascade_end',
    'ws': 'win_small',
    'wb': 'win_big',
    'wm': 'win_mega',
    'wc': 'win_countup',
    'fi': 'feature_intro',
    'fl': 'feature_loop',
    'fo': 'feature_outro',
    'jm': 'jackpot_mini',
    'jmaj': 'jackpot_major',
    'jg': 'jackpot_grand',
    'btn': 'button_press',
    'pop': 'popup_show',
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Process a single file
  AutoBindResult processFile(String filePath) {
    final basename = p.basenameWithoutExtension(filePath).toLowerCase();
    final dirContext = _extractFolderContext(filePath);

    // Step 1: Try strict token matching
    var result = _strictMatch(filePath, basename);
    if (result.confidence >= 0.9) return result;

    // Step 2: Try fuzzy strategies in order of reliability
    result = _tryTokenReorder(filePath, basename);
    if (result.confidence >= 0.7) return result;

    result = _tryAbbreviation(filePath, basename);
    if (result.confidence >= 0.7) return result;

    result = _tryCamelCase(filePath, basename);
    if (result.confidence >= 0.7) return result;

    result = _tryFolderContext(filePath, basename, dirContext);
    if (result.confidence >= 0.7) return result;

    result = _tryNumericSuffix(filePath, basename);
    if (result.confidence >= 0.7) return result;

    result = _trySubstring(filePath, basename);
    if (result.confidence >= 0.7) return result;

    // No match found
    return AutoBindResult(
      filePath: filePath,
      parsedName: basename,
      confidence: 0.0,
      strategy: MatchStrategy.none,
    );
  }

  /// Process an entire folder recursively
  AutoBindBatchResult processFolder(String folderPath) {
    final results = <AutoBindResult>[];
    final dir = Directory(folderPath);

    if (!dir.existsSync()) {
      return AutoBindBatchResult(results: [], timestamp: DateTime.now());
    }

    final audioExtensions = {'.wav', '.mp3', '.ogg', '.flac', '.aiff', '.aif'};

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (audioExtensions.contains(ext)) {
          results.add(processFile(entity.path));
        }
      }
    }

    // Sort: auto-bound first, then suggested, then needs attention
    results.sort((a, b) {
      final catCmp = a.category.index.compareTo(b.category.index);
      if (catCmp != 0) return catCmp;
      return b.confidence.compareTo(a.confidence);
    });

    return AutoBindBatchResult(
      results: results,
      timestamp: DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STRICT MATCHING (Step 1-7)
  // ═══════════════════════════════════════════════════════════════════════════

  AutoBindResult _strictMatch(String filePath, String basename) {
    final tokens = _tokenize(basename);
    if (tokens.isEmpty) {
      return AutoBindResult(filePath: filePath, parsedName: basename);
    }

    String? phase;
    BehaviorCategory? system;
    BehaviorNodeType? nodeType;
    int variantIndex = 0;

    for (final token in tokens) {
      // Check phase
      if (phase == null && _phaseTokens.containsKey(token)) {
        phase = _phaseTokens[token];
        continue;
      }

      // Check system
      if (system == null && _systemTokens.containsKey(token)) {
        system = _systemTokens[token];
        continue;
      }

      // Check action (requires system context)
      if (system != null && nodeType == null && _actionTokens.containsKey(token)) {
        final actionMap = _actionTokens[token]!;
        if (actionMap.containsKey(system)) {
          nodeType = actionMap[system];
          continue;
        }
      }

      // Check variant (v1, v2, v3, etc.)
      final variantMatch = RegExp(r'^v(\d+)$').firstMatch(token);
      if (variantMatch != null) {
        variantIndex = int.parse(variantMatch.group(1)!) - 1;
        continue;
      }
    }

    if (nodeType != null) {
      return AutoBindResult(
        filePath: filePath,
        parsedName: basename,
        matchedNodeId: nodeType.nodeId,
        matchedNodeType: nodeType,
        variantIndex: variantIndex,
        detectedPhase: phase ?? 'base',
        confidence: 0.95,
        strategy: MatchStrategy.strict,
      );
    }

    // Partial match: have system but no action
    if (system != null) {
      return AutoBindResult(
        filePath: filePath,
        parsedName: basename,
        detectedPhase: phase,
        confidence: 0.4,
        strategy: MatchStrategy.strict,
      );
    }

    return AutoBindResult(filePath: filePath, parsedName: basename);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FUZZY MATCHING STRATEGIES
  // ═══════════════════════════════════════════════════════════════════════════

  AutoBindResult _tryTokenReorder(String filePath, String basename) {
    // Try all permutations of tokens
    final tokens = _tokenize(basename);
    if (tokens.length < 2 || tokens.length > 6) {
      return AutoBindResult(filePath: filePath, parsedName: basename);
    }

    // Try swapping adjacent tokens
    for (int i = 0; i < tokens.length - 1; i++) {
      final reordered = List<String>.from(tokens);
      final temp = reordered[i];
      reordered[i] = reordered[i + 1];
      reordered[i + 1] = temp;
      final reorderedName = reordered.join('_');
      final result = _strictMatch(filePath, reorderedName);
      if (result.matchedNodeId != null) {
        return AutoBindResult(
          filePath: filePath,
          parsedName: basename,
          matchedNodeId: result.matchedNodeId,
          matchedNodeType: result.matchedNodeType,
          variantIndex: result.variantIndex,
          detectedPhase: result.detectedPhase,
          confidence: 0.92,
          strategy: MatchStrategy.tokenReorder,
        );
      }
    }

    return AutoBindResult(filePath: filePath, parsedName: basename);
  }

  AutoBindResult _tryAbbreviation(String filePath, String basename) {
    final tokens = _tokenize(basename);
    for (final token in tokens) {
      if (_abbreviations.containsKey(token)) {
        final expanded = basename.replaceFirst(token, _abbreviations[token]!);
        final result = _strictMatch(filePath, expanded);
        if (result.matchedNodeId != null) {
          return AutoBindResult(
            filePath: filePath,
            parsedName: basename,
            matchedNodeId: result.matchedNodeId,
            matchedNodeType: result.matchedNodeType,
            variantIndex: result.variantIndex,
            detectedPhase: result.detectedPhase,
            confidence: 0.80,
            strategy: MatchStrategy.abbreviation,
          );
        }
      }
    }
    return AutoBindResult(filePath: filePath, parsedName: basename);
  }

  AutoBindResult _tryCamelCase(String filePath, String basename) {
    // Split CamelCase: "ReelStop3" → "reel_stop_3"
    final camelSplit = basename
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]}_${m[2]}')
        .replaceAllMapped(RegExp(r'([A-Za-z])(\d)'), (m) => '${m[1]}_${m[2]}')
        .toLowerCase();

    if (camelSplit != basename) {
      final result = _strictMatch(filePath, camelSplit);
      if (result.matchedNodeId != null) {
        return AutoBindResult(
          filePath: filePath,
          parsedName: basename,
          matchedNodeId: result.matchedNodeId,
          matchedNodeType: result.matchedNodeType,
          variantIndex: result.variantIndex,
          detectedPhase: result.detectedPhase,
          confidence: 0.85,
          strategy: MatchStrategy.camelCase,
        );
      }
    }
    return AutoBindResult(filePath: filePath, parsedName: basename);
  }

  AutoBindResult _tryFolderContext(String filePath, String basename, List<String> dirContext) {
    if (dirContext.isEmpty) {
      return AutoBindResult(filePath: filePath, parsedName: basename);
    }

    // Use folder names as additional context tokens
    final contextTokens = <String>[];
    for (final dir in dirContext) {
      contextTokens.addAll(_tokenize(dir.toLowerCase()));
    }

    // Try combining folder context with filename
    BehaviorCategory? system;
    for (final token in contextTokens) {
      if (_systemTokens.containsKey(token)) {
        system = _systemTokens[token];
        break;
      }
    }

    if (system != null) {
      // Try matching just the filename action against the folder's system
      final tokens = _tokenize(basename);
      for (final token in tokens) {
        if (_actionTokens.containsKey(token)) {
          final actionMap = _actionTokens[token]!;
          if (actionMap.containsKey(system)) {
            final nodeType = actionMap[system]!;
            return AutoBindResult(
              filePath: filePath,
              parsedName: basename,
              matchedNodeId: nodeType.nodeId,
              matchedNodeType: nodeType,
              confidence: 0.88,
              strategy: MatchStrategy.folderContext,
            );
          }
        }
      }
    }

    return AutoBindResult(filePath: filePath, parsedName: basename);
  }

  AutoBindResult _tryNumericSuffix(String filePath, String basename) {
    // "reel_stop_003" → strip suffix, try matching, use number as variant
    final match = RegExp(r'^(.+?)_?(\d{2,3})$').firstMatch(basename);
    if (match != null) {
      final nameWithoutNum = match.group(1)!;
      final numStr = match.group(2)!;
      final result = _strictMatch(filePath, nameWithoutNum);
      if (result.matchedNodeId != null) {
        return AutoBindResult(
          filePath: filePath,
          parsedName: basename,
          matchedNodeId: result.matchedNodeId,
          matchedNodeType: result.matchedNodeType,
          variantIndex: int.parse(numStr) - 1,
          detectedPhase: result.detectedPhase,
          confidence: 0.86,
          strategy: MatchStrategy.numericSuffix,
        );
      }
    }
    return AutoBindResult(filePath: filePath, parsedName: basename);
  }

  AutoBindResult _trySubstring(String filePath, String basename) {
    // Check if any node type's nodeId is a substring of the filename
    for (final type in BehaviorNodeType.values) {
      final id = type.nodeId.replaceAll('_', '');
      if (basename.replaceAll('_', '').contains(id)) {
        return AutoBindResult(
          filePath: filePath,
          parsedName: basename,
          matchedNodeId: type.nodeId,
          matchedNodeType: type,
          confidence: 0.70,
          strategy: MatchStrategy.substring,
        );
      }
    }
    return AutoBindResult(filePath: filePath, parsedName: basename);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Tokenize a filename: split by _, -, space, camelCase boundary
  List<String> _tokenize(String name) {
    return name
        .replaceAll(RegExp(r'[_\-\s\.]+'), '_')
        .split('_')
        .where((t) => t.isNotEmpty)
        .map((t) => t.toLowerCase())
        .toList();
  }

  /// Extract folder names from path for context matching
  List<String> _extractFolderContext(String filePath) {
    final parts = p.split(p.dirname(filePath));
    // Take last 3 directory components max
    return parts.length > 3 ? parts.sublist(parts.length - 3) : parts;
  }
}
