/// FFNC (FluxForge Audio Naming Convention) Parser
///
/// Parses FFNC-compliant filenames into structured stage data.
/// See /FFNC.md for the complete naming convention specification.

/// Audio category determined by filename prefix.
enum FFNCCategory {
  sfx, // sfx_ → gameplay sounds
  mus, // mus_ → music
  amb, // amb_ → ambience, attract, idle
  trn, // trn_ → transitions
  ui,  // ui_  → interface
  vo,  // vo_  → voice-over
}

/// Result of parsing an FFNC-compliant filename.
class FFNCResult {
  /// Internal stage name (e.g., "REEL_STOP_0", "MUSIC_BASE_L1")
  final String stage;

  /// Audio category from prefix
  final FFNCCategory category;

  /// Layer number (1 = default/only, 2+ = multi-layer)
  final int layer;

  /// Variant letter for round-robin pool (null = no variant)
  final String? variant;

  const FFNCResult({
    required this.stage,
    required this.category,
    this.layer = 1,
    this.variant,
  });

  @override
  String toString() =>
      'FFNCResult(stage: $stage, category: ${category.name}, layer: $layer, variant: $variant)';
}

class FFNCParser {
  const FFNCParser();

  static const _audioExtensions = {'.wav', '.mp3', '.ogg', '.flac', '.aiff', '.aif'};

  /// Check if a filename follows FFNC naming convention.
  bool isFFNC(String filename) {
    final lower = filename.toLowerCase();
    return lower.startsWith('sfx_') ||
        lower.startsWith('mus_') ||
        lower.startsWith('amb_') ||
        lower.startsWith('trn_') ||
        lower.startsWith('ui_') ||
        lower.startsWith('vo_');
  }

  /// Parse an FFNC filename into structured data.
  /// Returns null if the filename is not FFNC-compliant.
  FFNCResult? parse(String filename) {
    if (!isFFNC(filename)) return null;

    var name = _stripExtension(filename.toLowerCase());

    // 1. Extract _variant_x suffix
    String? variant;
    final variantMatch = RegExp(r'_variant_([a-z0-9]+)$').firstMatch(name);
    if (variantMatch != null) {
      variant = variantMatch.group(1);
      name = name.substring(0, variantMatch.start);
    }

    // 2. Extract _layerN suffix
    int layer = 1;
    final layerMatch = RegExp(r'_layer(\d+)$').firstMatch(name);
    if (layerMatch != null) {
      layer = int.parse(layerMatch.group(1)!);
      name = name.substring(0, layerMatch.start);
    }

    // 3. Identify prefix and transform to internal stage name
    if (name.startsWith('sfx_')) {
      final stage = _transformSfx(name.substring(4));
      return FFNCResult(stage: stage, category: FFNCCategory.sfx, layer: layer, variant: variant);
    }
    if (name.startsWith('mus_')) {
      final stage = _transformMus(name.substring(4));
      return FFNCResult(stage: stage, category: FFNCCategory.mus, layer: layer, variant: variant);
    }
    if (name.startsWith('amb_')) {
      final stage = _transformAmb(name.substring(4));
      return FFNCResult(stage: stage, category: FFNCCategory.amb, layer: layer, variant: variant);
    }
    if (name.startsWith('trn_')) {
      final stage = _transformTrn(name.substring(4));
      return FFNCResult(stage: stage, category: FFNCCategory.trn, layer: layer, variant: variant);
    }
    if (name.startsWith('ui_')) {
      return FFNCResult(stage: name.toUpperCase(), category: FFNCCategory.ui, layer: layer, variant: variant);
    }
    if (name.startsWith('vo_')) {
      return FFNCResult(stage: name.toUpperCase(), category: FFNCCategory.vo, layer: layer, variant: variant);
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════
  // SFX transformations
  // ═══════════════════════════════════════════════════════════════

  String _transformSfx(String name) {
    // win_tier_N → WIN_PRESENT_N
    final winTier = RegExp(r'^win_tier_(\d+)$').firstMatch(name);
    if (winTier != null) return 'WIN_PRESENT_${winTier.group(1)}';

    // win_low, win_equal, win_end
    if (name == 'win_low') return 'WIN_PRESENT_LOW';
    if (name == 'win_equal') return 'WIN_PRESENT_EQUAL';
    if (name == 'win_end') return 'WIN_PRESENT_END';

    // reel_stop_N → REEL_STOP_(N-1)  [FFNC 1-based → system 0-based]
    // Guard: if someone writes reel_stop_0, clamp to REEL_STOP_0
    final reelStop = RegExp(r'^reel_stop_(\d+)$').firstMatch(name);
    if (reelStop != null) {
      final n = int.parse(reelStop.group(1)!);
      final idx = n > 0 ? n - 1 : 0;
      return 'REEL_STOP_$idx';
    }

    // Everything else: direct uppercase
    return name.toUpperCase();
  }

  // ═══════════════════════════════════════════════════════════════
  // MUS transformations — mus_ prefix → MUSIC_ internal
  // ═══════════════════════════════════════════════════════════════

  String _transformMus(String name) {
    // Non-MUSIC_ prefixed stages that live on music bus
    if (name == 'big_win_loop') return 'BIG_WIN_START';
    if (name == 'big_win_end') return 'BIG_WIN_END';
    if (name == 'game_start') return 'GAME_START';
    if (name == 'fs_end') return 'FS_END';

    // base_game_* → BASE_*
    if (name.startsWith('base_game_')) {
      return 'MUSIC_BASE_${name.substring(10).toUpperCase()}';
    }
    if (name == 'base_game') return 'MUSIC_BASE';

    // freespin_* → FS_*
    if (name.startsWith('freespin_')) {
      return 'MUSIC_FS_${name.substring(9).toUpperCase()}';
    }
    if (name == 'freespin') return 'MUSIC_FS';

    // big_win → BIGWIN (no underscore in internal name)
    if (name == 'big_win') return 'MUSIC_BIGWIN';

    // Everything else: MUSIC_ + uppercase
    return 'MUSIC_${name.toUpperCase()}';
  }

  // ═══════════════════════════════════════════════════════════════
  // AMB transformations — amb_ prefix → AMBIENT_ or ATTRACT_/IDLE_
  // ═══════════════════════════════════════════════════════════════

  String _transformAmb(String name) {
    // base_game → AMBIENT_BASE
    if (name == 'base_game') return 'AMBIENT_BASE';

    // freespin → AMBIENT_FS
    if (name == 'freespin') return 'AMBIENT_FS';

    // big_win → AMBIENT_BIGWIN
    if (name == 'big_win') return 'AMBIENT_BIGWIN';

    // attract_* → ATTRACT_* (strip amb_ prefix, already stripped)
    if (name.startsWith('attract_')) return name.toUpperCase();

    // idle_* → IDLE_*
    if (name.startsWith('idle_')) return name.toUpperCase();

    // Everything else: AMBIENT_ + uppercase
    return 'AMBIENT_${name.toUpperCase()}';
  }

  // ═══════════════════════════════════════════════════════════════
  // TRN transformations — trn_ prefix → TRANSITION_
  // ═══════════════════════════════════════════════════════════════

  String _transformTrn(String name) {
    // CONTEXT_ stages keep their prefix (not TRANSITION_ internally)
    if (name.startsWith('context_')) return name.toUpperCase();

    // Stages that don't have TRANSITION_ prefix internally
    if (name == 'fs_outro_plaque' || name == 'fs_outro') return 'FS_OUTRO_PLAQUE';

    // Replace human-readable names with internal abbreviations
    var transformed = name;
    transformed = transformed.replaceAll('base_game', 'base');
    transformed = transformed.replaceAll('freespin', 'fs');

    return 'TRANSITION_${transformed.toUpperCase()}';
  }

  // ═══════════════════════════════════════════════════════════════
  // Utility
  // ═══════════════════════════════════════════════════════════════

  String _stripExtension(String filename) {
    final lower = filename.toLowerCase();
    for (final ext in _audioExtensions) {
      if (lower.endsWith(ext)) {
        return filename.substring(0, filename.length - ext.length);
      }
    }
    return filename;
  }
}
