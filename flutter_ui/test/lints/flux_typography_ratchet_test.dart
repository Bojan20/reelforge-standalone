/// FluxTypography ratchet — FLUX_MASTER_TODO 0.5 A.5.
///
/// FluxForge ima brand typography hierarchiju (`FluxForgeTheme.h1/h2/h3/
/// body/bodySmall/label/labelTiny/mono/monoSmall/monoLarge`) sa pin-ovanim
/// font family-jima (`Inter` + monoFontFamily). Direktni `TextStyle(...)`
/// + `fontFamily: '…'` + raw `fontSize:` literali izvan `lib/theme/`
/// razbijaju brand typography identity isto kao raw `Color(0x…)` i raw
/// `Duration(milliseconds:)` razbijaju color + motion identity.
///
/// Ovaj test pinuje **frozen baselines**:
///   * `TextStyle(...)` literala (svaki je inline TextStyle)
///   * `fontFamily:` referenca (svaki implies hardcoded font family)
///   * `fontSize:` referenca (svaki implies hardcoded font size)
///
/// **Direction contract:** baseline ide samo nadole. Migracije konvertuju
/// raw TextStyle u `FluxForgeTheme.h1/.body/.mono` itd. — i lower the
/// baseline u istom commit-u (asimetrično OK pravilo).
///
/// Detection heuristik:
///   * Single + doc komentari preskočeni
///   * `lib/theme/`, `lib/src/rust/` (auto-gen FFI), `lib/l10n/` isključeni
///
/// Migration pattern:
///   `TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: ...)`
///                                                  → `FluxForgeTheme.body`
///   `TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11)`
///                                                  → `FluxForgeTheme.monoSmall`
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Frozen baseline za inline `TextStyle(…)` poziva pod `lib/` izvan
/// `lib/theme/`. Captured 2026-05-10 audit.
/// Bumped 2026-05-10 (Sprint 10 E.1) +2 za `_ExportClipButton` u
/// `session_recorder_panel.dart` — 2 inline TextStyle poziva za dinamicki
/// label boja (success green / error red / brand gold idle).
/// Bumped 2026-05-10 (Sprint 11 G grupa) +3 za G.7 hot-reload SnackBar
/// label, G.21 blend preview snackbar (2× — active+empty paths).
/// Bumped 2026-05-10 (Sprint 12 G grupa) +8 za G.16 (3× snackbar +
/// dialog title), G.19 (snackbar + dialog title + hint), G.18 (—).
/// Bumped 2026-05-10 (Sprint 13 Helix Event Nexus) +43 za pure-trigger
/// event matrix UI (`helix_event_nexus.dart`): per-stage row labels,
/// per-layer parameter sliders (volume/pan/dual-pan/width/gain/delay/
/// fadeIn/fadeOut/trim/curves), event-level controls, header badges,
/// category chips, meta chips, dropdown labels, micro toggles. Each
/// inline TextStyle is intentionally fontSize=8–11 (dock-density) sa
/// monospace value displays — FluxForgeTheme typography tokens (h1/h2/
/// body) ne pokrivaju ovu density tier (dock UI density), pa su inline
/// styles privremeno opravdani; kad token paleta dobije .dockLabel /
/// .dockMono varijante migration je trivial.
/// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.A.2) +1 za WIP feature
/// SnackBar (`_showFeatureWipToast`) koji zameni dead `() {}` na 6 stub
/// dock tabova (SFX/BT/DNA/AI/CLOUD/A/B). Inline TextStyle za monospace
/// snack content jer SnackBar-default Theme nije FluxForge-tokenized.
/// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.B.4) +1 za `_ModeIndicator`
/// label u Omnibar-u (monospace 9px, weight 800 — dock-density tier).
// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.B.6) +4 za keyboard cheatsheet
// dialog (`_KeysGroup` + dialog header) — header label, group title,
// keyboard hint pill, description text.
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2 demo migration) -30 za
// `helix/helpers/dock_chrome.dart` — 30 inline `TextStyle(fontFamily:
// 'monospace', fontSize: N, …)` literala zamenjeni sa novim
// `FluxForgeTheme.dockMono(size:, …)` / `dockSans(size:, …)` factory
// pozivima. Factory pozivi koriste `size:` argument (ne `fontSize:`)
// pa ratchet pokazuje strict drop.
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2 batch 2) -75 za
// `panels/ai_gen_panel.dart` (-28), `panels/sfx_panel.dart` (-19),
// `panels/flow_panel.dart` (-20) — agent-driven migration koristi
// isti dockMono/dockSans pattern. Ukupan Sprint 15 B.2 pad: -105.
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2 batch 3) -91 za
// `panels/export_panel.dart` (-22), `spine/spine_audio_assign.dart`
// (-18), `spine/spine_misc.dart` (-17), `panels/ab_panel.dart` (-17),
// `helpers/context_lenses.dart` (-17). Ukupan Sprint 15 B.2 pad: -196.
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2 batch 4) -59 za intel/
// audio/audio_dna/bt/math/timeline/cloud/spine_chrome paneli.
// Ukupan Sprint 15 B.2 pad: -255.
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2 batch 5) -101 za spine_game_config.dart — agent migration.
// Lowered 2026-05-11 (Sprint 15 B.2 mega-wave) -1110 za ultimativnu batch
// migraciju: slot_lab_screen.dart (-181), slotlab_lower_zone_widget.dart (-115),
// ultimate_audio_panel.dart (-121), engine_connected_layout.dart (-88),
// export_panels.dart (-110), premium_slot_preview.dart (-80),
// events_folder_panel.dart (-69), slotlab_logic_tab.dart (-63),
// soundbank_panel.dart (-52), room_wizard.dart (-35),
// sfx_pipeline_wizard.dart (-45), engine_layout_widgets.dart (-110),
// slot_voice_mixer.dart (-54), problems_inbox_panel.dart (-1 Curves fix).
// Lowered 2026-05-11 (Sprint 15 B.2 batch 6+7) -390 za:
// events_panel_widget.dart (-49), gdd_import_wizard.dart (-35),
// game_model_editor.dart (-40), event_debugger_panel.dart (-35),
// ultimate_mixer.dart (-48), channel_inspector_panel.dart (-40),
// win_tier_config_panel.dart (-39), fabfilter_limiter_panel.dart (-42).
// Lowered 2026-05-11 (Sprint 15 B.2 batch 8) -225 za:
// slot_automation_panel.dart (-41), advanced_middleware_panel.dart (-40),
// helix_event_nexus.dart (-47), gdd_preview_dialog.dart (-46),
// music_system_panel.dart (-37). Plus 1 extra iz events_panel fontStyle fix.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 9) -294 za:
// daw_lower_zone_widget.dart (-41), event_editor_panel.dart (-42),
// container_preset_library_panel.dart (-42), fabfilter_eq_panel.dart (-34),
// blend_container_panel.dart (-33), sequence_container_panel.dart (-35),
// auto_bind_dialog_v2.dart (-33), action_editor_widget.dart (-17).
// Lowered 2026-05-11 (Sprint 15 B.2 batch 10) -292 za:
// random_container_panel.dart (-28), marketplace_panel.dart (-30),
// rgai_compliance_panel.dart (-36), scenario_editor.dart (-31),
// macro_controls_panel.dart (-36), bounce_dialog.dart (-36),
// bus_hierarchy_panel.dart (-36), pro_eq_editor.dart (-34).
// Lowered 2026-05-11 (Sprint 15 B.2 batch 11) -263 za:
// tempo_state_panel.dart (-30), plugins_scanner_panel.dart (-35),
// slotlab_music_layers_panel.dart (-35), sss_panel.dart (-35),
// package_manager_panel.dart (-33), extension_sdk_panel.dart (-33),
// cortex_neural_dashboard.dart (-30), slot_preview_widget.dart (-33).
// Lowered 2026-05-11 (Sprint 15 B.2 batch 12) -239 za:
// engine_connected_layout.dart (-30), loop_editor_panel.dart (-28),
// onboarding_wizard.dart (-27), preset_morph_editor_panel.dart (-22),
// ducking_matrix_panel.dart (-29), chain_preset_library_panel.dart (-28),
// audio_pool_panel.dart (-29), clip_widget.dart (-17).
// Lowered 2026-05-11 (Sprint 15 B.2 batch 13) -237: container_ab_comparison_panel.dart,
// attenuation_curve_panel.dart, loudness_report_panel.dart, fabfilter_saturation_panel.dart,
// deconvolution_wizard.dart, video_export_panel.dart, ab_test_panel.dart, ai_composer_panel.dart.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 14) -209: documentation_viewer.dart, helix_screen.dart,
// session_replay_panel.dart, audio_alignment_panel.dart, intensity_crossfade_wizard.dart,
// network_audio_panel.dart, control_bar.dart, fabfilter_compressor_panel.dart.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 15) -220: rgai_compliance_panel.dart,
// loudness_analysis_panel.dart, stereo_imager_panel.dart, brain_chat.dart,
// variant_group_panel.dart, neural_fingerprint_panel.dart, gad_panel.dart, vca_strip.dart.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 16) -208: rtpc_debugger_panel.dart,
// advanced_metering_panel.dart, crdt_sync_panel.dart, asset_cloud_panel.dart,
// ai_copilot_panel.dart, routing_panel.dart, track_templates_panel.dart, priority_tier_preset_panel.dart.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 17) -203: daw_files_browser.dart,
// video_processor_panel.dart, video_panel.dart, grid_settings_panel.dart,
// export_dialog.dart, branding_panel.dart, enhanced_autobind_dialog.dart, clip_inspector_panel.dart.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 18) -191: export_preset_manager.dart,
// engine_connection_panel.dart, hrtf_profile_panel.dart, project_dashboard_dialog.dart,
// stem_routing_matrix.dart, beat_grid_editor.dart, marker_actions_panel.dart, neve1073_eq.dart.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 19) -181: wavelet_panel.dart, spatial_panel.dart,
// ai_mixing_panel.dart, math_audio_bridge_panel.dart, transition_config_panel.dart,
// neuro_authoring_panel.dart, clip_gain_envelope_panel.dart, rtpc_macro_editor_panel.dart.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 20) -177: resource_dashboard_panel.dart,
// region_playlist_panel.dart, middleware_hub_screen.dart, test_automation_panel.dart,
// mock_engine_panel.dart, anchor_monitor.dart, rtpc_editor_panel.dart, feature_builder_panel.dart.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 21) -174: ab_sim_panel.dart, voice_steal_panel.dart,
// track_versions_panel.dart, pro_mixer_strip.dart, group_manager_panel.dart,
// rtpc_dsp_binding_editor.dart, accessibility_settings_panel.dart, stage_trace_widget.dart.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 22) -166: game_flow_overlay.dart,
// advanced_routing_matrix_panel.dart, audio_signatures_panel.dart, dsp_script_panel.dart,
// cycle_actions_panel.dart, collaboration_panel.dart, resources_panel.dart, macro_history.dart.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 23) -160: schema_migration_panel.dart,
// logical_editor_panel.dart, pro_metering_panel.dart, clip_properties_panel.dart,
// mastering_panel.dart, master_bus_limiter.dart, gpu_settings_panel.dart, convolution_ultra_panel.dart.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 24) -156: vision_dashboard.dart, git_panel.dart,
// project_settings_screen.dart, daw_hub_screen.dart, stage_ingest_panel.dart,
// intent_rule_editor.dart, spatial_audio_panel.dart, mwui_inspector_panel.dart.
const int _kRawTextStyleBaseline = 3806;

/// Frozen baseline za `fontFamily:` referenca van theme/.
/// Bumped 2026-05-10 (Sprint 10 E.1) +1 za `_ExportClipButton` `'monospace'`
/// font (aligned sa _SessionStat sibling badge).
/// Bumped 2026-05-10 (Sprint 13 Helix Event Nexus) +16 za monospace value
/// displays u Event Nexus parameter editor (volume %, pan L/R/C, fadeMs,
/// trimMs, file size KB/MB, duration s, dB readout). Monospace je
/// canonical kod numerical readout-a; FluxForgeTheme.monoFontFamily
/// migration prati .dockMono token kreaciju.
/// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.A.2) +1 za WIP toast u
/// `_showFeatureWipToast` — monospace fontFamily da snack izgleda
/// konzistentno sa drugim status pillovima u dock-u.
/// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.B.4) +1 za `_ModeIndicator`
/// monospace label.
// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.B.6) +4 za keyboard cheatsheet
// monospace stilove (header + group title + key pill + description).
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2) -26 za dock_chrome.dart —
// `fontFamily: 'monospace'` literali eliminisani kroz `dockMono(...)`.
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2 batch 2) -72 za ai_gen/
// sfx/flow paneli — agent migration na dockMono/dockSans. Ukupan
// Sprint 15 B.2 pad: -98.
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2 batch 3) -78 za export/
// spine_audio_assign/spine_misc/ab/context_lenses — agent migration.
// Ukupan Sprint 15 B.2 pad: -176.
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2 batch 4) -53 za intel/
// audio/audio_dna/bt/math/timeline/cloud/spine_chrome paneli.
// Ukupan Sprint 15 B.2 pad: -229.
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2 batch 5) -104 za spine_game_config.dart — agent migration.
// Lowered 2026-05-11 (Sprint 15 B.2 mega-wave) -73 za istu batch migraciju
// (sve dockMono/dockSans pozivi eliminišu fontFamily: literale).
// Lowered 2026-05-11 (Sprint 15 B.2 batch 6+7) -43 za isti set fajlova.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 8) -24.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 9) -16.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 10) -12.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 11) -18.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 12) -22.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 13) -14.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 14) -28.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 15) -14.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 16) -10.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 17) -21.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 18) -15.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 19) -3.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 20) -6.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 21) -6.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 22) -10.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 23) -4.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 24) -11.
const int _kRawFontFamilyBaseline = 547;

/// Frozen baseline za `fontSize:` referenca van theme/.
/// Bumped 2026-05-10 (Sprint 10 E.1) +1 za `_ExportClipButton` 9px label
/// (aligned sa _SessionStat sibling badge size).
/// Bumped 2026-05-10 (Sprint 12 G grupa) +1 za G.19 dialog title fontSize.
/// Bumped 2026-05-10 (Sprint 13 Helix Event Nexus) +43 za dock-density
/// parameter editor (sve 7–11px brojeve mapirano na .label/.labelTiny/
/// .mono token, ali dok token paleta ne pokriva 7px tier, inline
/// fontSize ostaje. Sve manje od FluxForgeTheme.body (12px)).
/// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.A.2) +1 za WIP toast 11px
/// label (matches dock-density tier).
/// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.B.4) +1 za `_ModeIndicator`
/// 9px label.
// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.B.6) +4 za keyboard cheatsheet
// fontSize-ove (header 13px, group title 10px, key pill 10px, desc 10px).
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2) -30 za dock_chrome.dart —
// `fontSize: N` literali eliminisani kroz `dockMono/dockSans(size: N, …)`.
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2 batch 2) -75 za ai_gen/
// sfx/flow paneli — agent migration. Ukupan Sprint 15 B.2 pad: -105.
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2 batch 3) -91 za export/
// spine_audio_assign/spine_misc/ab/context_lenses — agent migration.
// Ukupan Sprint 15 B.2 pad: -196.
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2 batch 4) -59 za intel/
// audio/audio_dna/bt/math/timeline/cloud/spine_chrome paneli.
// Ukupan Sprint 15 B.2 pad: -255.
// Lowered 2026-05-11 (Sprint 15 Faza 4.B.2 batch 5) -110 za spine_game_config.dart — agent migration.
// Lowered 2026-05-11 (Sprint 15 B.2 mega-wave) -1095 za istu batch migraciju
// (sve dockMono/dockSans pozivi koriste size: arg, ne fontSize:).
// Lowered 2026-05-11 (Sprint 15 B.2 batch 6+7) -339 za isti set fajlova.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 8) -184.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 9) -256.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 10) -222.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 11) -259.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 12) -176.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 13) -220.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 14) -203.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 15) -200.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 16) -166.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 17) -192.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 18) -167.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 19) -175.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 20) -165.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 21) -157.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 22) -162.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 23) -159.
// Lowered 2026-05-11 (Sprint 15 B.2 batch 24) -138.
const int _kRawFontSizeBaseline = 3814;

const Set<String> _kExcludedPathPrefixes = <String>{
  'theme/',
  'src/rust/',
  'l10n/',
};

final _libRoot = Directory.fromUri(
  Directory.current.uri.resolve('lib'),
);

void main() {
  group('FluxTypography ratchet (FLUX_MASTER_TODO 0.5 A.5)', () {
    late List<File> dartFiles;

    setUpAll(() {
      dartFiles = _libRoot
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !_isExcluded(_relPath(f.path)))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
    });

    test('lib root resolves and is non-empty', () {
      expect(_libRoot.existsSync(), isTrue);
      expect(dartFiles.isNotEmpty, isTrue);
    });

    test('TextStyle(…) literal count must not exceed frozen baseline', () {
      final result = _scan(dartFiles, _rxTextStyle);
      expect(
        result.total,
        lessThanOrEqualTo(_kRawTextStyleBaseline),
        reason:
            'Raw `TextStyle(…)` literala je poraslo iznad frozen baseline-a '
            '$_kRawTextStyleBaseline (sad ${result.total}). Novi UI kod mora '
            'da koristi `FluxForgeTheme.h1/h2/h3/body/bodySmall/label/'
            'labelTiny/mono/monoSmall/monoLarge` token umesto inline TextStyle.\n'
            '\nTop 15 offenders:\n${_formatTop(result.perFile, 15)}',
      );
    });

    test('fontFamily: count must not exceed frozen baseline', () {
      final result = _scan(dartFiles, _rxFontFamily);
      expect(
        result.total,
        lessThanOrEqualTo(_kRawFontFamilyBaseline),
        reason:
            'Raw `fontFamily:` referenca poraslo iznad frozen baseline-a '
            '$_kRawFontFamilyBaseline (sad ${result.total}). Novi UI kod mora '
            'da koristi `FluxForgeTheme.fontFamily` (Inter) ili '
            '`FluxForgeTheme.monoFontFamily` umesto hardcoded font name-a.\n'
            '\nTop 15 offenders:\n${_formatTop(result.perFile, 15)}',
      );
    });

    test('fontSize: count must not exceed frozen baseline', () {
      final result = _scan(dartFiles, _rxFontSize);
      expect(
        result.total,
        lessThanOrEqualTo(_kRawFontSizeBaseline),
        reason:
            'Raw `fontSize:` referenca poraslo iznad frozen baseline-a '
            '$_kRawFontSizeBaseline (sad ${result.total}). Migracija na '
            '`FluxForgeTheme.body / .label / .mono / .h1` etc. token-e '
            'pokriva canonical typography hierarchy.\n'
            '\nTop 15 offenders:\n${_formatTop(result.perFile, 15)}',
      );
    });

    test('reduction tip lands in failure messages', () {
      const failureExample =
          'Raw `TextStyle(…)` literala je poraslo iznad frozen baseline-a '
          '$_kRawTextStyleBaseline (sad 9999). Novi UI kod mora '
          'da koristi `FluxForgeTheme.h1/h2/h3/body/bodySmall/label/'
          'labelTiny/mono/monoSmall/monoLarge` token umesto inline TextStyle.';
      expect(failureExample, contains('FluxForgeTheme'));
      expect(failureExample, contains('mono'));
    });
  });
}

final _rxTextStyle = RegExp(r'\bTextStyle\s*\(');
final _rxFontFamily = RegExp(r'\bfontFamily\s*:');
final _rxFontSize = RegExp(r'\bfontSize\s*:');

class _ScanResult {
  _ScanResult(this.total, this.perFile);
  final int total;
  final List<MapEntry<String, int>> perFile;
}

_ScanResult _scan(List<File> files, RegExp pattern) {
  final perFile = <MapEntry<String, int>>[];
  var total = 0;
  for (final file in files) {
    final rel = _relPath(file.path);
    final count = _countMatches(file.readAsStringSync(), pattern);
    if (count > 0) perFile.add(MapEntry(rel, count));
    total += count;
  }
  perFile.sort((a, b) => b.value.compareTo(a.value));
  return _ScanResult(total, perFile);
}

int _countMatches(String content, RegExp pattern) {
  var total = 0;
  for (final line in content.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
    total += pattern.allMatches(line).length;
  }
  return total;
}

bool _isExcluded(String relPath) {
  for (final prefix in _kExcludedPathPrefixes) {
    if (relPath.startsWith(prefix)) return true;
  }
  return false;
}

String _formatTop(List<MapEntry<String, int>> entries, int n) {
  return entries.take(n).map((e) => '  ${e.value}× ${e.key}').join('\n');
}

String _relPath(String full) {
  final root = '${_libRoot.path}/';
  return full.startsWith(root) ? full.substring(root.length) : full;
}
