/// AutoBindEngine — centralizovani engine za audio→stage binding.
///
/// Odvaja ANALIZU (čista funkcija, nema side-effecta) od PRIMENE (mutira state).
///
/// ## Arhitektura
///
///   1. `analyze(folder)` → `BindingAnalysis`  (pure, dry run)
///   2. `apply(analysis, provider)` → void     (transakcijsko, sa rollback-om)
///
/// ## Stage Resolution Pipeline
///
///   FFNC fast path → Exact alias → Prefix alias → Glued alias →
///   NofM pattern → Multiplier → WinTier → SymbolPay → Fuzzy token
///
/// Svaki metod daje score (0–100). Pobedi NAJVIŠI score, ne prvi match.
/// Ovo eliminiše order-dependentni bug iz starog 6-step sistema.
import 'dart:io';

import '../ffnc/ffnc_parser.dart';
import '../stage_configuration_service.dart';
import '../../providers/slot_lab_project_provider.dart';
import 'binding_result.dart';

// ──────────────────────────────────────────────────────────────────────────────
// ALIAS TABLE
// Centralizovana alias mapa — single source of truth.
// Key: normalized snake_case filename token(s)
// Value: stage identifier (uppercase)
// ──────────────────────────────────────────────────────────────────────────────

const Map<String, String> _kAliases = {
  // ── REELS ────────────────────────────────────────────────────────────────
  'spin_loop': 'REEL_SPIN_LOOP', 'spinloop': 'REEL_SPIN_LOOP',
  'spins_loop': 'REEL_SPIN_LOOP', 'reel_spin': 'REEL_SPIN_LOOP',
  'spinning': 'REEL_SPIN_LOOP',
  'spins_stop': 'REEL_STOP', 'reel_land': 'REEL_STOP',
  'reelstop': 'REEL_STOP', 'reelclick': 'REEL_STOP',
  'reel_clear': 'REEL_STOP',

  // ── ANTICIPATION ─────────────────────────────────────────────────────────
  'spins_susp_short': 'ANTICIPATION_TENSION_R2',
  'spins_susp_med':   'ANTICIPATION_TENSION_R3',
  'spins_susp_long':  'ANTICIPATION_TENSION_R4',
  'susp_short': 'ANTICIPATION_TENSION_R2',
  'susp_med':   'ANTICIPATION_TENSION_R3',
  'susp_long':  'ANTICIPATION_TENSION_R4',
  'reel_anticipation': 'ANTICIPATION_TENSION',
  'anticipation_miss': 'ANTICIPATION_MISS',
  'anticipation': 'ANTICIPATION_TENSION',
  'suspence': 'ANTICIPATION_TENSION', 'suspense': 'ANTICIPATION_TENSION',
  'tension': 'ANTICIPATION_TENSION',  'reel_suspense': 'ANTICIPATION_TENSION',
  'suspense_loop': 'ANTICIPATION_TENSION', 'suspence_loop': 'ANTICIPATION_TENSION',

  // ── WIN PRESENTATION ─────────────────────────────────────────────────────
  'hp_sym': 'HP_WIN', 'lp_sym': 'LP_WIN',
  'winlessthanequal': 'WIN_PRESENT_LOW',
  'win_low': 'WIN_PRESENT_LOW', 'winlow': 'WIN_PRESENT_LOW',
  'win_less': 'WIN_PRESENT_LOW', 'winless': 'WIN_PRESENT_LOW',
  'win_small': 'WIN_PRESENT_LOW', 'winsmall': 'WIN_PRESENT_LOW',
  'win_sub': 'WIN_PRESENT_LOW', 'win_present_low': 'WIN_PRESENT_LOW',
  'winpresentlow': 'WIN_PRESENT_LOW', 'low_win': 'WIN_PRESENT_LOW',
  'lowwin': 'WIN_PRESENT_LOW', 'small_win': 'WIN_PRESENT_LOW',
  'win_equal': 'WIN_PRESENT_EQUAL', 'winequal': 'WIN_PRESENT_EQUAL',
  'win_present_equal': 'WIN_PRESENT_EQUAL',
  'winpresentequal': 'WIN_PRESENT_EQUAL',
  'equal_win': 'WIN_PRESENT_EQUAL', 'equalwin': 'WIN_PRESENT_EQUAL',
  'total_win': 'WIN_PRESENT_END',

  // ── BIG WIN ───────────────────────────────────────────────────────────────
  'bw_alert': 'BIG_WIN_TRIGGER', 'big_win_alert': 'BIG_WIN_TRIGGER',
  'bigwinalert': 'BIG_WIN_TRIGGER',
  'bw_loop': 'BIG_WIN_START', 'bw_start': 'BIG_WIN_START',
  'bw_music': 'BIG_WIN_START', 'big_win_music': 'BIG_WIN_START',
  'big_win_loop': 'BIG_WIN_START', 'bigwinloop': 'BIG_WIN_START',
  'bigwinmusic': 'BIG_WIN_START', 'bw_mus': 'BIG_WIN_START',
  'bw_end': 'BIG_WIN_END', 'big_win_stinger': 'BIG_WIN_END',
  'bw_end_stinger': 'BIG_WIN_END', 'bigwinend': 'BIG_WIN_END',
  'bw_levelup': 'BIG_WIN_TIER_1', 'bw_level_up': 'BIG_WIN_TIER_1',
  'big_win_level_up': 'BIG_WIN_TIER_1', 'bigwinlevelup': 'BIG_WIN_TIER_1',
  'big_win_tier': 'BIG_WIN_TIER_1', 'bigwintier': 'BIG_WIN_TIER_1',
  'bw_tier': 'BIG_WIN_TIER_1', 'tier_up': 'BIG_WIN_TIER_1',
  'bw_outro': 'BIG_WIN_OUTRO', 'big_win_outro': 'BIG_WIN_OUTRO',
  'bw_end_outro': 'BIG_WIN_OUTRO', 'bigwinoutro': 'BIG_WIN_OUTRO',
  'big_win_fadeout': 'BIG_WIN_OUTRO', 'bw_fadeout': 'BIG_WIN_OUTRO',
  'bigwinfadeout': 'BIG_WIN_OUTRO',

  // ── PAYLINES ──────────────────────────────────────────────────────────────
  'reel_highlight': 'PAYLINE_HIGHLIGHT',
  'payline': 'PAYLINE_HIGHLIGHT', 'pay_line': 'PAYLINE_HIGHLIGHT',
  'linewin': 'PAYLINE_HIGHLIGHT', 'coin_highlight': 'PAYLINE_HIGHLIGHT',

  // ── ROLLUP ────────────────────────────────────────────────────────────────
  'ui_skip': 'SKIP', 'u_i_skip': 'SKIP',
  'coin_loop_end': 'ROLLUP_END',
  'coin_loop': 'ROLLUP_START',
  'coin_burst_fly': 'COIN_SHOWER_START',
  'coin_burst': 'BIG_WIN_TICK_START',
  'celebration_rollup': 'BIG_WIN_TICK_START',
  'rollup_loop': 'ROLLUP_START', 'rolluploop': 'ROLLUP_START',
  'rollup_low': 'WIN_PRESENT_LOW', 'rolluplow': 'WIN_PRESENT_LOW',
  'rollup_small': 'WIN_PRESENT_LOW', 'rollup_less': 'WIN_PRESENT_LOW',
  'rollup_sub': 'WIN_PRESENT_LOW',
  'rollup_equal': 'WIN_PRESENT_EQUAL', 'rollupequal': 'WIN_PRESENT_EQUAL',
  'rollup_terminator': 'ROLLUP_END', 'rollup_term': 'ROLLUP_END',
  'rollup': 'ROLLUP_TICK',
  'base_game_rollup': 'ROLLUP_TICK',
  'base_rollup_loop': 'ROLLUP_TICK',
  'bonus_level_rollup': 'ROLLUP_TICK',
  'bonus_rollup': 'ROLLUP_TICK',

  // ── MUSIC: BASE GAME ─────────────────────────────────────────────────────
  'mus_bg_lvl': 'MUSIC_BASE_L', 'base_game_music': 'MUSIC_BASE_L1',
  'mus_bw_end': 'BIG_WIN_END', 'mus_bw': 'BIG_WIN_START',

  // ── MUSIC: FREE SPINS ────────────────────────────────────────────────────
  'mus_fs_end': 'MUSIC_FS_END', 'mus_fs_outro': 'MUSIC_FS_END',
  'fs_end_music': 'MUSIC_FS_END', 'freespin_end_music': 'MUSIC_FS_END',
  'free_spin_end_music': 'MUSIC_FS_END', 'free_spin_end': 'MUSIC_FS_END',
  'freespin_end': 'MUSIC_FS_END', 'fs_outro_music': 'MUSIC_FS_END',
  'freespins_end': 'MUSIC_FS_END', 'freespins_end_music': 'MUSIC_FS_END',
  'free_spins_end': 'MUSIC_FS_END', 'free_spins_end_music': 'MUSIC_FS_END',
  'fs_end_loop': 'MUSIC_FS_END', 'fs_complete': 'MUSIC_FS_END',
  'freespin_complete': 'MUSIC_FS_END', 'freespins_complete': 'MUSIC_FS_END',
  'free_spins_complete': 'MUSIC_FS_END', 'free_spin_complete': 'MUSIC_FS_END',
  'freespinendmusic': 'MUSIC_FS_END', 'freespinsendmusic': 'MUSIC_FS_END',
  'freespinsmusicend': 'MUSIC_FS_END', 'freespinmusicend': 'MUSIC_FS_END',
  'mus_fs': 'MUSIC_FS_L1', 'free_spin_music': 'MUSIC_FS_L1',
  'freespin_music': 'MUSIC_FS_L1', 'fs_music': 'MUSIC_FS_L1',
  'free_spin_loop': 'MUSIC_FS_L1', 'freespin_loop': 'MUSIC_FS_L1',
  'fs_loop': 'MUSIC_FS_L1', 'fs_music_loop': 'MUSIC_FS_L1',
  'freespins_music': 'MUSIC_FS_L1', 'free_spins_music': 'MUSIC_FS_L1',
  'freespins_loop': 'MUSIC_FS_L1', 'free_spins_loop': 'MUSIC_FS_L1',
  'freespinsmusic': 'MUSIC_FS_L1', 'freespinmusicloop': 'MUSIC_FS_L1',
  'freespinloop': 'MUSIC_FS_L1', 'freespinsloop': 'MUSIC_FS_L1',
  'fs_bg': 'MUSIC_FS_L1', 'fs_background': 'MUSIC_FS_L1',
  'freespin_bg': 'MUSIC_FS_L1', 'freespins_bg': 'MUSIC_FS_L1',
  'free_spin_bg': 'MUSIC_FS_L1', 'free_spins_bg': 'MUSIC_FS_L1',
  'feature_music': 'MUSIC_FS_L1', 'feature_loop': 'MUSIC_FS_L1',

  // ── FREE SPINS ────────────────────────────────────────────────────────────
  'fs_start': 'FS_HOLD_INTRO', 'freespin_start': 'FS_HOLD_INTRO',
  'freespins_start': 'FS_HOLD_INTRO', 'free_spin_start': 'FS_HOLD_INTRO',
  'free_spins_start': 'FS_HOLD_INTRO', 'fs_intro': 'FS_HOLD_INTRO',
  'freespin_intro': 'FS_HOLD_INTRO', 'freespins_intro': 'FS_HOLD_INTRO',
  'freespinstart': 'FS_HOLD_INTRO', 'freespinsstart': 'FS_HOLD_INTRO',
  'freespinintro': 'FS_HOLD_INTRO', 'freespinsintro': 'FS_HOLD_INTRO',
  'fs_hold': 'FS_HOLD_INTRO', 'fs_holding': 'FS_HOLD_INTRO',
  'freespin_hold': 'FS_HOLD_INTRO', 'freespins_hold': 'FS_HOLD_INTRO',
  'freespinhold': 'FS_HOLD_INTRO', 'freespinshold': 'FS_HOLD_INTRO',
  'fs_hold_loop': 'FS_HOLD_INTRO', 'fs_holding_loop': 'FS_HOLD_INTRO',
  'panels_appear': 'FS_HOLD_INTRO',
  'bell_retrigger': 'FS_RETRIGGER',
  'bell_loop': 'FS_SPIN_START',
  'fs_active': 'FS_SPIN_START', 'fs_smart': 'FS_SPIN_START',
  'fs_coin_smart': 'FS_WIN',

  // ── TRANSITIONS ───────────────────────────────────────────────────────────
  'trn_fs_intro': 'CONTEXT_BASE_TO_FS',
  'trn_fs_outro_panel': 'FS_OUTRO_PLAQUE',
  'trn_fs_outro': 'FS_OUTRO_PLAQUE', 'fs_outro': 'FS_OUTRO_PLAQUE',
  'freespin_outro': 'FS_OUTRO_PLAQUE', 'freespins_outro': 'FS_OUTRO_PLAQUE',
  'free_spin_outro': 'FS_OUTRO_PLAQUE', 'free_spins_outro': 'FS_OUTRO_PLAQUE',
  'fs_exit_plaque': 'FS_OUTRO_PLAQUE', 'freespin_exit': 'FS_OUTRO_PLAQUE',
  'freespins_exit': 'FS_OUTRO_PLAQUE', 'fs_complete_plaque': 'FS_OUTRO_PLAQUE',
  'trn_return_to_base': 'CONTEXT_FS_TO_BASE',
  'trn_bonus_intro': 'CONTEXT_BASE_TO_BONUS',
  'trn_bonus_outro': 'CONTEXT_BONUS_TO_BASE',

  // ── GAME LIFECYCLE ────────────────────────────────────────────────────────
  'game_intro': 'GAME_INTRO', 'intro': 'GAME_INTRO',
  'game_intro_loop': 'GAME_INTRO', 'game_load': 'GAME_INTRO',
  'loading': 'GAME_INTRO', 'splash': 'GAME_INTRO',
  'logo_anim': 'GAME_INTRO', 'logo_animation': 'GAME_INTRO',
  'logo': 'GAME_INTRO', 'game_logo': 'GAME_INTRO',
  'game_continue': 'GAME_CONTINUE', 'continue': 'GAME_CONTINUE',
  'continue_button': 'GAME_CONTINUE', 'tap_to_continue': 'GAME_CONTINUE',
  'start_game': 'GAME_CONTINUE',

  // ── UI ────────────────────────────────────────────────────────────────────
  'ui_spin': 'UI_SPIN_PRESS', 'ui_spin_button': 'UI_SPIN_PRESS',
  'u_i_spin': 'UI_SPIN_PRESS', 'u_i_spin_press': 'UI_SPIN_PRESS',
  'spin_press': 'UI_SPIN_PRESS', 'spin_button': 'UI_SPIN_PRESS',
  'start_button': 'UI_SPIN_PRESS',
  'spin_stop': 'UI_STOP_PRESS', 'stop_button': 'UI_STOP_PRESS',
  'ui_stop': 'UI_STOP_PRESS', 'stop_press': 'UI_STOP_PRESS',
  'u_i_stop': 'UI_STOP_PRESS', 'u_i_stop_press': 'UI_STOP_PRESS',
  'reel_stop_all': 'UI_STOP_PRESS', 'stop_spin': 'UI_STOP_PRESS',
  'ui_open': 'UI_MENU_OPEN', 'ui_close': 'UI_MENU_CLOSE',
  'ui_interact': 'UI_BUTTON_PRESS', 'ui_click': 'UI_BUTTON_PRESS',
  'ui_tap': 'UI_BUTTON_PRESS', 'u_i_click': 'UI_BUTTON_PRESS',
  'interact': 'UI_BUTTON_PRESS', 'click': 'UI_BUTTON_PRESS',
  'select': 'UI_BUTTON_PRESS', 'ui_select': 'UI_BUTTON_PRESS',
  'u_i_select': 'UI_BUTTON_PRESS', 'button_click': 'UI_BUTTON_PRESS',
  'button_high_tech_press': 'UI_BUTTON_PRESS',
  'play_button_press': 'UI_BUTTON_PRESS',
  'menu_click': 'UI_MENU_SELECT', 'menu_hover': 'UI_MENU_HOVER',
  'menu_open': 'UI_MENU_OPEN', 'menu_close': 'UI_MENU_CLOSE',
  'volume_button': 'UI_VOLUME_CHANGE',
  'change_risk_amount': 'UI_BET_UP',
  'bet_up': 'UI_BET_UP', 'betup': 'UI_BET_UP',
  'bet_down': 'UI_BET_DOWN', 'betdown': 'UI_BET_DOWN',
  'bet_max': 'UI_BET_MAX', 'betmax': 'UI_BET_MAX',
  'bet_min': 'UI_BET_MIN', 'betmin': 'UI_BET_MIN',
  'bet_increase': 'UI_BET_UP', 'bet_decrease': 'UI_BET_DOWN',
  'u_i_bet_up': 'UI_BET_UP', 'u_i_bet_down': 'UI_BET_DOWN',

  // ── SYMBOLS ───────────────────────────────────────────────────────────────
  'icon_burst': 'SYMBOL_WIN',
  'level_up': 'FS_MULTIPLIER_UP', 'spin_count': 'FS_SPIN_START',
  'ignite': 'FS_START',
  'wild_win': 'WILD_WIN',
  'gem_land': 'SCATTER_LAND',
  'scatter_land': 'SCATTER_LAND', 'scatterland': 'SCATTER_LAND',
  'scatter_landing': 'SCATTER_LAND', 'scatterlanding': 'SCATTER_LAND',
  'scatter_symbol': 'SCATTER_LAND', 'scatter_sym': 'SCATTER_LAND',
  'scatter_stop': 'SCATTER_LAND',
  'wild_symbol': 'WILD_LAND', 'wild_sym': 'WILD_LAND',
  'wild_land': 'WILD_LAND', 'wildland': 'WILD_LAND',
  'wild_landing': 'WILD_LAND', 'wildlanding': 'WILD_LAND',
  'wild_stop': 'WILD_LAND',

  // ── JACKPOTS ─────────────────────────────────────────────────────────────
  'grand_jackpot': 'JACKPOT_GRAND', 'major_jackpot': 'JACKPOT_MAJOR',
  'mini_jackpot': 'JACKPOT_MINI',  'minor_jackpot': 'JACKPOT_MINOR',
  'maxi_jackpot': 'JACKPOT_GRAND', 'mega_jackpot': 'JACKPOT_GRAND',
  'jackpot_winner': 'JACKPOT_CELEBRATION', 'jackpot': 'JACKPOT_CELEBRATION',
  'progressive_reveal': 'JACKPOT_REVEAL',

  // ── BONUS / WHEEL / GAMBLE ───────────────────────────────────────────────
  'wheel_enters': 'WHEEL_ENTER', 'wheel_exits': 'WHEEL_EXIT',
  'double_up_loop': 'GAMBLE_START', 'double_up_win': 'GAMBLE_WIN',
  'double_up_lose': 'GAMBLE_LOSE', 'double_up_exit_take_win': 'GAMBLE_COLLECT',
  'credits_fly_up': 'WIN_COLLECT', 'credits_fly_down': 'WIN_COLLECT',
  'collect': 'WIN_COLLECT',
  'bonus_intro_loop': 'BONUS_ENTER', 'bonus_ending_short': 'BONUS_EXIT',
  'bonus_ending': 'BONUS_EXIT',   'bonus_complete': 'BONUS_EXIT',
  'bonus_level': 'BONUS_MUSIC',   'bonus': 'BONUS_MUSIC',
};

// ──────────────────────────────────────────────────────────────────────────────
// AUTO BIND ENGINE
// ──────────────────────────────────────────────────────────────────────────────

/// Pure analysis + transactional apply engine for audio→stage binding.
class AutoBindEngine {
  AutoBindEngine._();

  static const _kAudioExtensions = {'wav', 'mp3', 'ogg', 'flac', 'aiff', 'aif'};
  static const _ffncParser = FFNCParser();

  // ── PUBLIC API ─────────────────────────────────────────────────────────────

  /// Analyze [folderPath] and return a [BindingAnalysis] without mutating state.
  ///
  /// Safe to call on any isolate (no provider access).
  static BindingAnalysis analyze(String folderPath) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) {
      return const BindingAnalysis(matched: [], unmatched: [], warnings: [], stageGroups: {});
    }

    final svc = StageConfigurationService.instance;
    final knownStages = svc.getAllStages().map((s) => s.name).toSet();

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => _kAudioExtensions.contains(f.path.split('.').last.toLowerCase()))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final matched = <BindingMatch>[];
    final unmatched = <UnmatchedFile>[];
    final warnings = <BindingWarning>[];
    final stageGroups = <String, List<BindingMatch>>{};
    final mappedPaths = <String>{};

    // Stage → primary file (for variant detection)
    final stagePrimary = <String, String>{};

    // Pending extra MUSIC_BASE_L1 files for layer distribution
    final pendingMusicBase = <String>[];

    // ── FFNC fast path ──────────────────────────────────────────────────────
    for (final file in files) {
      final filename = file.uri.pathSegments.last;
      if (!_ffncParser.isFFNC(filename)) continue;

      final result = _ffncParser.parse(filename);
      if (result == null) continue;

      final stage = result.stage.toUpperCase();
      if (svc.getStage(stage) == null) continue; // unknown stage → legacy path

      mappedPaths.add(file.path);
      final isVariant = result.variant != null;
      final layer = result.layer > 1 ? result.layer : null;
      final isPrimary = !stagePrimary.containsKey(stage);

      if (isPrimary) stagePrimary[stage] = file.path;

      final m = BindingMatch(
        filePath: file.path,
        fileName: filename,
        stage: stage,
        score: 100,
        method: MatchMethod.ffncPrefix,
        isVariant: isVariant || !isPrimary,
        layer: layer,
      );
      matched.add(m);
      stageGroups.putIfAbsent(stage, () => []);
      stageGroups[stage]!.add(m);
    }

    // ── Legacy path ─────────────────────────────────────────────────────────
    for (final file in files) {
      if (mappedPaths.contains(file.path)) continue;

      final filename = file.uri.pathSegments.last;
      final result = _scoreFilename(filename, knownStages, svc);

      if (result == null) {
        final suggestions = _suggest(filename, knownStages);
        unmatched.add(UnmatchedFile(
          filePath: file.path,
          fileName: filename,
          suggestions: suggestions,
        ));
        continue;
      }

      mappedPaths.add(file.path);
      final stage = result.stage;
      final isPrimary = !stagePrimary.containsKey(stage);

      // Handle MUSIC_BASE_L1 overflow → distribute to L2-L5
      if (!isPrimary && stage == 'MUSIC_BASE_L1') {
        pendingMusicBase.add(file.path);
        continue;
      }

      if (isPrimary) stagePrimary[stage] = file.path;

      final m = BindingMatch(
        filePath: file.path,
        fileName: filename,
        stage: stage,
        score: result.score,
        method: result.method,
        isVariant: !isPrimary,
      );
      matched.add(m);
      stageGroups.putIfAbsent(stage, () => []);
      stageGroups[stage]!.add(m);
    }

    // ── Distribute extra MUSIC_BASE files to L2-L5 ─────────────────────────
    const layerStages = ['MUSIC_BASE_L2', 'MUSIC_BASE_L3', 'MUSIC_BASE_L4', 'MUSIC_BASE_L5'];
    for (int i = 0; i < pendingMusicBase.length && i < layerStages.length; i++) {
      final ls = layerStages[i];
      if (stageGroups.containsKey(ls)) continue; // already bound
      final fn = pendingMusicBase[i].split('/').last;
      final m = BindingMatch(
        filePath: pendingMusicBase[i],
        fileName: fn,
        stage: ls,
        score: 75,
        method: MatchMethod.exactAlias,
        layer: i + 2,
      );
      matched.add(m);
      stageGroups[ls] = [m];
    }

    // ── Numbered-generic dedup ───────────────────────────────────────────────
    // If REEL_STOP_0 + REEL_STOP_1 exist, remove generic REEL_STOP.
    const genericPairs = [
      ('REEL_STOP', 'REEL_STOP_'),
      ('SCATTER_LAND', 'SCATTER_LAND_'),
      ('WILD_LAND', 'WILD_LAND_'),
      ('WIN_LINE_SHOW', 'WIN_LINE_SHOW_'),
      ('WIN_LINE_HIDE', 'WIN_LINE_HIDE_'),
      ('CASCADE_STEP', 'CASCADE_STEP_'),
      ('ROLLUP_TICK', 'ROLLUP_TICK_'),
    ];
    for (final (generic, prefix) in genericPairs) {
      if (stageGroups.containsKey(generic) &&
          stageGroups.keys.any((k) => k.startsWith(prefix))) {
        stageGroups.remove(generic);
        matched.removeWhere((m) => m.stage == generic);
      }
    }

    // ── Warnings ─────────────────────────────────────────────────────────────
    // Warn if any stage has 5+ variants (unusual)
    for (final entry in stageGroups.entries) {
      if (entry.value.length >= 5) {
        warnings.add(BindingWarning(
          message: '${entry.value.length} variants for ${entry.key} — only first will play unless variant pool is active',
          severity: WarningSeverity.info,
          stage: entry.key,
        ));
      }
    }

    return BindingAnalysis(
      matched: matched,
      unmatched: unmatched,
      warnings: warnings,
      stageGroups: stageGroups,
    );
  }

  /// Apply a [BindingAnalysis] to the provider — transactional.
  ///
  /// All bindings are collected first, then state is cleared and re-applied atomically.
  /// If any assignment throws, the previous state is restored via rollback.
  static void apply(BindingAnalysis analysis, SlotLabProjectProvider provider) {
    if (analysis.matched.isEmpty) return;

    // Build primary bindings map (one path per stage, no variants)
    final primaryBindings = <String, String>{};
    for (final entry in analysis.stageGroups.entries) {
      final primary = entry.value.firstWhere(
        (m) => !m.isVariant,
        orElse: () => entry.value.first,
      );
      primaryBindings[entry.key] = primary.filePath;
    }

    // Build variant pools map
    final variantPools = <String, List<String>>{};
    for (final entry in analysis.stageGroups.entries) {
      variantPools[entry.key] = entry.value.map((m) => m.filePath).toList();
    }

    // Build layer data map (for MUSIC_BASE multi-layer)
    final layerData = <String, List<({String path, int layer, String? variant})>>{};
    for (final m in analysis.matched) {
      if (m.layer != null) {
        layerData.putIfAbsent(m.stage, () => []);
        layerData[m.stage]!.add((path: m.filePath, layer: m.layer!, variant: null));
      }
    }

    // TRANSACTION: snapshot → clear → apply → commit (or rollback)
    final snapshot = provider.exportAudioAssignmentsSnapshot();
    try {
      provider.applyAutoBindTransaction(
        primaryBindings: primaryBindings,
        variantPools: variantPools,
        layerData: layerData,
      );
    } catch (e) {
      // Rollback to snapshot
      provider.restoreAudioAssignmentsSnapshot(snapshot);
      rethrow;
    }
  }

  // ── SCORING ENGINE ────────────────────────────────────────────────────────

  /// Score a filename against known stages. Returns the best candidate or null.
  static _ScoreResult? _scoreFilename(
    String filename,
    Set<String> knownStages,
    StageConfigurationService svc,
  ) {
    final rawName = filename.split('.').first;

    // Normalize: CamelCase → snake_case, trim whitespace/dashes, lowercase
    final snaked = rawName
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
        .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]}_${m[2]}')
        .replaceAllMapped(RegExp(r'([a-zA-Z])(\d)'), (m) => '${m[1]}_${m[2]}')
        .replaceAllMapped(RegExp(r'(\d)([a-zA-Z])'), (m) => '${m[1]}_${m[2]}');
    final base = snaked.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');

    // Strip numeric prefix (e.g. "004_" or "043_") — but NOT multiplier "2_x_"
    final stripped = RegExp(r'^\d+_x(_|$)').hasMatch(base)
        ? base
        : base.replaceFirst(RegExp(r'^\d+_'), '');

    // Strip trailing single-digit variant suffix
    final noVariant = stripped.replaceFirst(RegExp(r'_\d$'), '');

    // Strip level suffix
    final noLevel = noVariant.replaceFirst(RegExp(r'_?(?:level|lv)_?\d*$'), '');

    // Strip sfx_ prefix + numeric catalog number
    String _stripSfx(String s) {
      final after = s.startsWith('sfx_') ? s.substring(4) : s;
      return after.replaceFirst(RegExp(r'^\d+_'), '');
    }

    // All normalization candidates, de-duplicated
    final candidates = <String>[
      _stripSfx(stripped),
      if (stripped != _stripSfx(stripped)) stripped,
      _stripSfx(noVariant),
      _stripSfx(noLevel),
      if (noVariant != _stripSfx(noVariant)) noVariant,
      if (noLevel != _stripSfx(noVariant)) noLevel,
      base,
    ].toSet().toList();

    _ScoreResult? best;

    for (final candidate in candidates) {
      // Score degradation per candidate (earlier = better)
      final candPenalty = candidates.indexOf(candidate) * 3;

      // 1. Exact direct match
      final directUpper = candidate.toUpperCase();
      if (knownStages.contains(directUpper)) {
        final s = _ScoreResult(directUpper, 90 - candPenalty, MatchMethod.exactAlias);
        if (best == null || s.score > best.score) best = s;
        continue;
      }

      // 2. Exact alias match
      final aliasResult = _aliasLookup(candidate);
      if (aliasResult != null) {
        final resolvedUpper = aliasResult.toUpperCase();
        if (knownStages.contains(resolvedUpper)) {
          final s = _ScoreResult(resolvedUpper, 85 - candPenalty, MatchMethod.exactAlias);
          if (best == null || s.score > best.score) best = s;
          continue;
        }
        // Alias resolved to something — try to match it
        final expanded = aliasResult;
        if (svc.getStage(expanded.toUpperCase()) != null) {
          final s = _ScoreResult(expanded.toUpperCase(), 83 - candPenalty, MatchMethod.prefixAlias);
          if (best == null || s.score > best.score) best = s;
        }
      }

      // 3. Prefix alias match (longest wins)
      final prefixResult = _prefixAliasLookup(candidate);
      if (prefixResult != null && knownStages.contains(prefixResult.toUpperCase())) {
        final s = _ScoreResult(prefixResult.toUpperCase(), 80 - candPenalty, MatchMethod.prefixAlias);
        if (best == null || s.score > best.score) best = s;
        continue;
      }

      // 4. Glued alias (no underscores)
      final glued = candidate.replaceAll('_', '');
      final gluedResult = _gluedAliasLookup(glued);
      if (gluedResult != null && knownStages.contains(gluedResult.toUpperCase())) {
        final s = _ScoreResult(gluedResult.toUpperCase(), 75 - candPenalty, MatchMethod.gluedAlias);
        if (best == null || s.score > best.score) best = s;
        continue;
      }

      // 5. NofM pattern
      final nofm = _resolveNofM(candidate, svc, knownStages);
      if (nofm != null) {
        final s = _ScoreResult(nofm, 78 - candPenalty, MatchMethod.nofm);
        if (best == null || s.score > best.score) best = s;
        continue;
      }

      // 6. Multiplier pattern
      final mult = _resolveMultiplier(candidate, svc, knownStages);
      if (mult != null) {
        final s = _ScoreResult(mult, 77 - candPenalty, MatchMethod.multiplier);
        if (best == null || s.score > best.score) best = s;
        continue;
      }

      // 7. Win-tier pattern
      final winTier = _resolveWinTier(candidate, svc);
      if (winTier != null) {
        final s = _ScoreResult(winTier, 76 - candPenalty, MatchMethod.winTier);
        if (best == null || s.score > best.score) best = s;
        continue;
      }

      // 8. Symbol-pay pattern
      final symPay = _resolveSymbolPay(candidate, svc, knownStages);
      if (symPay != null) {
        final s = _ScoreResult(symPay, 74 - candPenalty, MatchMethod.symbolPay);
        if (best == null || s.score > best.score) best = s;
        continue;
      }
    }

    return best;
  }

  // ── ALIAS LOOKUPS ─────────────────────────────────────────────────────────

  static String? _aliasLookup(String key) => _kAliases[key];

  static String? _prefixAliasLookup(String candidate) {
    String? bestKey;
    String? bestValue;
    for (final entry in _kAliases.entries) {
      if (candidate == entry.key || candidate.startsWith('${entry.key}_')) {
        if (bestKey == null || entry.key.length > bestKey.length) {
          bestKey = entry.key;
          bestValue = entry.value;
        }
      }
    }
    if (bestKey == null) return null;
    // Replace matched prefix and keep remainder
    final remainder = candidate.substring(bestKey.length);
    return remainder.isEmpty ? bestValue! : '${bestValue!}$remainder';
  }

  static String? _gluedAliasLookup(String glued) {
    String? bestValue;
    int bestLen = 0;
    for (final entry in _kAliases.entries) {
      final gKey = entry.key.replaceAll('_', '');
      if ((glued == gKey || glued.startsWith(gKey)) && gKey.length > bestLen) {
        bestLen = gKey.length;
        final remainder = glued.substring(gKey.length);
        bestValue = remainder.isEmpty ? entry.value : '${entry.value}_$remainder';
      }
    }
    return bestValue;
  }

  // ── PATTERN RESOLVERS ─────────────────────────────────────────────────────

  static String? _resolveNofM(
    String candidate,
    StageConfigurationService svc,
    Set<String> knownStages,
  ) {
    final m = RegExp(r'_?(\d+)_?of_?(\d+)').firstMatch(candidate);
    if (m == null) return null;
    final idx = int.tryParse(m.group(1)!);
    final base = candidate.replaceFirst(m.group(0)!, '')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (idx == null || base.isEmpty) return null;
    final stageId = '${base.toUpperCase()}_$idx';
    return knownStages.contains(stageId) ? stageId : svc.ensureIndexedStage(stageId);
  }

  static String? _resolveMultiplier(
    String candidate,
    StageConfigurationService svc,
    Set<String> knownStages,
  ) {
    final m = RegExp(r'^win_(\d+)x$').firstMatch(candidate);
    if (m != null) {
      final tier = int.tryParse(m.group(1)!);
      if (tier != null && tier >= 2) {
        final id = 'WIN_PRESENT_${tier - 1}';
        return knownStages.contains(id) ? id : svc.ensureIndexedStage(id);
      }
    }
    if (candidate.startsWith('2x') || candidate.startsWith('2_x')) {
      return knownStages.contains('WIN_PRESENT_1') ? 'WIN_PRESENT_1' : null;
    }
    return null;
  }

  static String? _resolveWinTier(String candidate, StageConfigurationService svc) {
    final m = RegExp(r'^win_?x?(\d+)x?$').firstMatch(candidate);
    if (m == null) return null;
    final tier = int.tryParse(m.group(1)!);
    if (tier == null || tier < 1) return null;
    return svc.ensureIndexedStage('WIN_PRESENT_$tier');
  }

  static String? _resolveSymbolPay(
    String candidate,
    StageConfigurationService svc,
    Set<String> knownStages,
  ) {
    final tokens = candidate.split('_').where((t) => t.isNotEmpty).toList();
    String? symType;
    int? symNum;
    for (final t in tokens) {
      if (RegExp(r'^(hp|mp|lp)$').hasMatch(t)) symType = t;
      final glued = RegExp(r'^(hp|mp|lp)(\d+)$').firstMatch(t);
      if (glued != null) {
        symType = glued.group(1);
        symNum = int.tryParse(glued.group(2)!);
      }
      if (symType != null && symNum == null && RegExp(r'^\d+$').hasMatch(t)) {
        symNum = int.tryParse(t);
      }
    }
    if (symType == null || symNum == null) return null;
    final id = '${symType.toUpperCase()}_WIN_$symNum';
    return knownStages.contains(id) ? id : svc.ensureIndexedStage(id);
  }

  // ── SUGGESTIONS (for unmatched files) ────────────────────────────────────

  static List<StageSuggestion> _suggest(String filename, Set<String> knownStages) {
    final name = filename.split('.').first.toLowerCase().replaceAll(RegExp(r'[\s\-_]+'), '');
    final results = <StageSuggestion>[];
    for (final stage in knownStages) {
      final dist = _levenshtein(name, stage.toLowerCase().replaceAll('_', ''));
      if (dist <= 5) {
        results.add(StageSuggestion(stage: stage, score: (100 - dist * 15).clamp(0, 100)));
      }
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return List<StageSuggestion>.from(results.take(5));
  }

  static int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final d = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
    for (int i = 0; i <= a.length; i++) d[i][0] = i;
    for (int j = 0; j <= b.length; j++) d[0][j] = j;
    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        d[i][j] = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost]
            .reduce((a, b) => a < b ? a : b);
      }
    }
    return d[a.length][b.length];
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// INTERNAL SCORE RESULT
// ──────────────────────────────────────────────────────────────────────────────

class _ScoreResult {
  final String stage;
  final int score;
  final MatchMethod method;
  const _ScoreResult(this.stage, this.score, this.method);
}
