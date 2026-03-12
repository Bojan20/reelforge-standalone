// Lower Zone Types — Section-Specific Type Definitions
//
// Each section (DAW, Middleware, SlotLab) has its OWN Lower Zone
// with completely independent tabs, state, and content.
//
// Based on LOWER_ZONE_ARCHITECTURE.md

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Minimum height of the lower zone content area
const double kLowerZoneMinHeight = 150.0;

/// Maximum height of the lower zone content area
const double kLowerZoneMaxHeight = 600.0;

/// Default height of the lower zone content area
/// 350px gives slot preview enough room on 14" MacBook while keeping lower zone usable
const double kLowerZoneDefaultHeight = 350.0;

/// Height of the context bar when expanded (super-tabs + sub-tabs)
const double kContextBarHeight = 54.0;

/// Height of the context bar when collapsed (super-tabs only)
const double kContextBarCollapsedHeight = 30.0;

/// Height of the action strip
const double kActionStripHeight = 28.0;

/// Height of the resize handle
const double kResizeHandleHeight = 4.0;

/// Height of the spin control bar (SlotLab only)
const double kSpinControlBarHeight = 26.0;

/// Height of the slot context bar (Middleware only)
const double kSlotContextBarHeight = 28.0;

/// Animation duration for expand/collapse
const Duration kLowerZoneAnimationDuration = Duration(milliseconds: 200);

/// Minimum width/height ratio for split view panes (prevents pane from being too small)
const double kSplitViewMinRatio = 0.2;

/// Maximum width/height ratio for split view panes
const double kSplitViewMaxRatio = 0.8;

/// Default split ratio (50/50)
const double kSplitViewDefaultRatio = 0.5;

/// Width of the split view divider
const double kSplitDividerWidth = 6.0;

/// Minimum ratio for each pane in multi-panel mode (prevents pane from being too small)
const double kSplitViewMinPaneRatio = 0.15;

// ═══════════════════════════════════════════════════════════════════════════════
// SPLIT VIEW — Multi-panel mode (2, 3, or 4 panels simultaneously)
// ═══════════════════════════════════════════════════════════════════════════════

/// Direction of the split view divider
enum SplitDirection {
  horizontal, // Left | Right
  vertical,   // Top / Bottom
}

/// Default split ratios for each panel count
List<double> defaultSplitRatios(int panelCount) {
  return switch (panelCount) {
    2 => [0.5],
    3 => [0.33, 0.66],
    4 => [0.5, 0.5], // [horizontal ratio, vertical ratio] for 2x2 grid
    _ => [],
  };
}

/// Tab state for a single pane (used for panels 2, 3, 4)
class PaneTabState {
  DawSuperTab superTab;
  DawBrowseSubTab browseSubTab;
  DawEditSubTab editSubTab;
  DawMixSubTab mixSubTab;
  DawProcessSubTab processSubTab;
  DawDeliverSubTab deliverSubTab;

  PaneTabState({
    this.superTab = DawSuperTab.browse,
    this.browseSubTab = DawBrowseSubTab.files,
    this.editSubTab = DawEditSubTab.timeline,
    this.mixSubTab = DawMixSubTab.mixer,
    this.processSubTab = DawProcessSubTab.eq,
    this.deliverSubTab = DawDeliverSubTab.export,
  });

  int get currentSubTabIndex => switch (superTab) {
    DawSuperTab.browse => browseSubTab.index,
    DawSuperTab.edit => editSubTab.index,
    DawSuperTab.mix => mixSubTab.index,
    DawSuperTab.process => processSubTab.index,
    DawSuperTab.deliver => deliverSubTab.index,
  };

  void setSubTabIndex(int index) {
    switch (superTab) {
      case DawSuperTab.browse:
        browseSubTab = DawBrowseSubTab.values[index.clamp(0, 3)];
      case DawSuperTab.edit:
        editSubTab = DawEditSubTab.values[index.clamp(0, DawEditSubTab.values.length - 1)];
      case DawSuperTab.mix:
        mixSubTab = DawMixSubTab.values[index.clamp(0, 3)];
      case DawSuperTab.process:
        processSubTab = DawProcessSubTab.values[index.clamp(0, DawProcessSubTab.values.length - 1)];
      case DawSuperTab.deliver:
        deliverSubTab = DawDeliverSubTab.values[index.clamp(0, DawDeliverSubTab.values.length - 1)];
    }
  }

  List<String> get subTabLabels => switch (superTab) {
    DawSuperTab.browse => DawBrowseSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.edit => DawEditSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.mix => DawMixSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.process => DawProcessSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.deliver => DawDeliverSubTab.values.map((e) => e.label).toList(),
  };

  PaneTabState copy() => PaneTabState(
    superTab: superTab,
    browseSubTab: browseSubTab,
    editSubTab: editSubTab,
    mixSubTab: mixSubTab,
    processSubTab: processSubTab,
    deliverSubTab: deliverSubTab,
  );

  Map<String, dynamic> toJson() => {
    'superTab': superTab.index,
    'browseSubTab': browseSubTab.index,
    'editSubTab': editSubTab.index,
    'mixSubTab': mixSubTab.index,
    'processSubTab': processSubTab.index,
    'deliverSubTab': deliverSubTab.index,
  };

  factory PaneTabState.fromJson(Map<String, dynamic> json) => PaneTabState(
    superTab: DawSuperTab.values[(json['superTab'] as int? ?? 0).clamp(0, DawSuperTab.values.length - 1)],
    browseSubTab: DawBrowseSubTab.values[(json['browseSubTab'] as int? ?? 0).clamp(0, 3)],
    editSubTab: DawEditSubTab.values[(json['editSubTab'] as int? ?? 0).clamp(0, DawEditSubTab.values.length - 1)],
    mixSubTab: DawMixSubTab.values[(json['mixSubTab'] as int? ?? 0).clamp(0, DawMixSubTab.values.length - 1)],
    processSubTab: DawProcessSubTab.values[(json['processSubTab'] as int? ?? 0).clamp(0, DawProcessSubTab.values.length - 1)],
    deliverSubTab: DawDeliverSubTab.values[(json['deliverSubTab'] as int? ?? 0).clamp(0, DawDeliverSubTab.values.length - 1)],
  );

  /// Default tab states for each pane index (different tabs for usefulness)
  static PaneTabState defaultForIndex(int index) => switch (index) {
    0 => PaneTabState(superTab: DawSuperTab.mix),
    1 => PaneTabState(superTab: DawSuperTab.process),
    2 => PaneTabState(superTab: DawSuperTab.edit),
    _ => PaneTabState(),
  };
}

extension SplitDirectionX on SplitDirection {
  String get label => this == SplitDirection.horizontal ? 'Horizontal' : 'Vertical';
  IconData get icon => this == SplitDirection.horizontal ? Icons.view_column : Icons.view_agenda;
  String get tooltip => this == SplitDirection.horizontal
      ? 'Split panels side by side'
      : 'Split panels top and bottom';
}

// ═══════════════════════════════════════════════════════════════════════════════
// TYPOGRAPHY — P0.1 Font sizes (minimum 10px for accessibility)
// ═══════════════════════════════════════════════════════════════════════════════

class LowerZoneTypography {
  LowerZoneTypography._();

  /// Title/Header size (was 11-12px)
  static const double sizeTitle = 13.0;

  /// Label size (was 9-10px)
  static const double sizeLabel = 11.0;

  /// Value/content size (was 10px)
  static const double sizeValue = 11.0;

  /// Badge/chip size (was 8-9px)
  static const double sizeBadge = 10.0;

  /// Small/muted size (was 8px) — minimum accessible
  static const double sizeSmall = 10.0;

  /// Tiny size for shortcuts (minimum)
  static const double sizeTiny = 9.0;

  // Pre-built TextStyles for consistency
  static const TextStyle title = TextStyle(
    fontSize: sizeTitle,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );

  static const TextStyle label = TextStyle(
    fontSize: sizeLabel,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle value = TextStyle(
    fontSize: sizeValue,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle badge = TextStyle(
    fontSize: sizeBadge,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle small = TextStyle(
    fontSize: sizeSmall,
    fontWeight: FontWeight.normal,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// COLORS — P0.3 Improved contrast for accessibility (WCAG AA)
// ═══════════════════════════════════════════════════════════════════════════════

class LowerZoneColors {
  LowerZoneColors._();

  // Backgrounds
  static const Color bgDeepest = Color(0xFF0A0A0C);
  static const Color bgDeep = Color(0xFF121216);
  static const Color bgMid = Color(0xFF1A1A20);
  static const Color bgSurface = Color(0xFF242430);

  // Text — P0.3: Improved contrast ratios
  // textPrimary on bgDeep = 15.5:1 ✓
  static const Color textPrimary = Color(0xFFFFFFFF);
  // textSecondary on bgDeep = 7.2:1 ✓ (was 0xFFA0A0B0)
  static const Color textSecondary = Color(0xFFB8B8C8);
  // textTertiary on bgDeep = 4.8:1 ✓ (was 0xFF606070)
  static const Color textTertiary = Color(0xFF808090);
  // textMuted on bgDeep = 4.5:1 ✓ (was 0xFF404050 = 2.4:1)
  static const Color textMuted = Color(0xFF909098);

  // Borders
  static const Color border = Color(0xFF303040);
  static const Color borderSubtle = Color(0xFF252530);

  // Focus indicator — P0.2: For keyboard navigation
  static const Color focusRing = Color(0xFF4A9EFF);
  static const double focusRingWidth = 2.0;

  // Section accents
  static const Color dawAccent = Color(0xFF4A9EFF);      // Blue
  static const Color middlewareAccent = Color(0xFFFF9040); // Orange
  static const Color slotLabAccent = Color(0xFF40C8FF);   // Cyan

  // Status
  static const Color success = Color(0xFF40FF90);
  static const Color warning = Color(0xFFFFD040);  // Slightly more orange for better contrast
  static const Color error = Color(0xFFFF4060);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════════
//
//  DAW LOWER ZONE — Timeline-based audio production
//
// ═══════════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════════

/// DAW Super-tabs: BROWSE, EDIT, MIX, PROCESS, DELIVER
enum DawSuperTab { browse, edit, mix, process, deliver }

extension DawSuperTabX on DawSuperTab {
  String get label => ['BROWSE', 'EDIT', 'MIX', 'PROCESS', 'DELIVER'][index];
  IconData get icon => [Icons.folder_open, Icons.content_cut, Icons.tune, Icons.equalizer, Icons.upload][index];
  String get shortcut => '${index + 1}';

  /// Category-based accent colors for DAW:
  /// BROWSE = blue, EDIT = cyan, MIX = green, PROCESS = orange, DELIVER = purple
  Color get color => switch (this) {
    DawSuperTab.browse  => const Color(0xFF4A9EFF), // Blue — file browsing
    DawSuperTab.edit    => const Color(0xFF40C8FF), // Cyan — editing
    DawSuperTab.mix     => const Color(0xFF50FF98), // Green — mixing
    DawSuperTab.process => const Color(0xFFFF9850), // Orange — processing
    DawSuperTab.deliver => const Color(0xFFB080FF), // Purple — delivery
  };

  String get category => switch (this) {
    DawSuperTab.browse  => 'FILES',
    DawSuperTab.edit    => 'EDIT',
    DawSuperTab.mix     => 'MIX',
    DawSuperTab.process => 'DSP',
    DawSuperTab.deliver => 'EXPORT',
  };

  String get tooltip => [
    'Browse audio files, presets, and plugins',
    'Edit timeline, MIDI, fades, and grid settings',
    'Mix with faders, sends, panning, and automation',
    'Process with EQ, dynamics, and FX chain',
    'Deliver: export, stems, bounce, and archive',
  ][index];
}

// --- DAW Sub-tabs ---

enum DawBrowseSubTab { files, presets, plugins, history }
enum DawEditSubTab { timeline, pianoRoll, fades, grid, punch, comping, warp, elastic, beatDetect, tempoDetect, stripSilence, dynamicSplit, ucsNaming, loopEditor, video, cycleActions, regionPlaylist, markerActions, granularSynth, networkAudio, dspScript, videoProcessor, packageManager, extensionSdk, razorEdit, mixSnapshots, metadataBrowser, screensets, projectTabs, subProjects }
enum DawMixSubTab { mixer, sends, pan, automation }
enum DawProcessSubTab { eq, comp, limiter, reverb, gate, delay, saturation, deEsser, fxChain, sidechain }
enum DawDeliverSubTab { export, stems, stemManager, loudnessReport, bounce, archive }

extension DawBrowseSubTabX on DawBrowseSubTab {
  String get label => ['Files', 'Presets', 'Plugins', 'History'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
  IconData get icon => [Icons.audio_file, Icons.save, Icons.extension, Icons.history][index];
  String get tooltip => [
    'Audio file browser with hover preview and drag-drop import',
    'Track preset library with factory presets (Vocals, Guitar, Drums)',
    'VST3/AU/CLAP plugin scanner with format filter',
    'Undo/redo history stack with 100-item limit',
  ][index];
}

extension DawEditSubTabX on DawEditSubTab {
  String get label => ['Timeline', 'Piano Roll', 'Fades', 'Grid', 'Punch', 'Comping', 'Warp', 'Elastic', 'Beat Det.', 'Tempo Det.', 'Strip Sil.', 'Dyn Split', 'UCS', 'Loop Ed.', 'Video', 'Cycles', 'Region PL', 'Markers', 'Granular', 'Network', 'DSP', 'Video FX', 'Packages', 'Ext SDK', 'Razor', 'Snapshots', 'Metadata', 'Screensets', 'Proj Tabs', 'Sub-Proj'][index];
  String get shortcut => ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'A', 'P', 'D', 'N', 'S', 'V', 'C', 'L', 'M', 'G', 'F', 'B', 'H', 'J', 'K', 'X', 'Z', '1', '2', '3', '4'][index];
  IconData get icon => [Icons.view_timeline, Icons.piano, Icons.gradient, Icons.grid_on, Icons.fiber_manual_record, Icons.layers, Icons.timer, Icons.waves, Icons.music_note, Icons.speed, Icons.content_cut, Icons.call_split, Icons.label, Icons.loop, Icons.videocam, Icons.replay, Icons.playlist_play, Icons.bolt, Icons.grain, Icons.wifi, Icons.code, Icons.movie_filter, Icons.inventory_2, Icons.extension, Icons.carpenter, Icons.camera, Icons.info_outline, Icons.window, Icons.tab, Icons.account_tree][index];
  String get tooltip => [
    'Track arrangement view with clip positions and routing',
    'MIDI editor with 128 notes, velocity, and CC automation',
    'Crossfade curve editor (Equal Power, Linear, S-Curve)',
    'Snap-to-grid settings, tempo (40-240 BPM), time signature',
    'Punch-in/out recording with pre-roll, count-in, and rehearsal',
    'Take lanes and comp regions (Pro Tools/Cubase style)',
    'Time-stretch and warp markers with algorithm selection',
    'Elastic Audio pitch correction and time manipulation',
    'Beat Detective transient detection and groove extraction',
    'SmartTempo auto-detect BPM from audio with confidence scoring',
    'Automatic silence detection and removal with threshold control',
    'Dynamic Split — transient/gate/silence detection with preview and batch split',
    'UCS Naming — Universal Category System for game audio asset naming',
    'Wwise-grade advanced loop system with regions, cues, and per-iteration gain',
    'Video timeline with playback, preview, and A/V sync controls',
    'Cycle Actions — sequential action cycling with conditionals',
    'Region Playlist — non-linear playback with independent region ordering',
    'Marker Actions — trigger actions when playhead crosses markers (!actionId)',
    'Granular Synthesis — ReaGranular-style 4-voice grain engine with freeze mode',
    'Network Audio — ReaStream-style host-to-host audio/MIDI streaming on LAN',
    'DSP Scripting — JSFX-style sample-level audio effect scripting',
    'Video Processor — text overlay, audio-reactive visuals, FFT spectrum, color correction',
    'Package Manager — marketplace for scripts, effects, themes with auto-update',
    'Extension SDK — open SDK for third-party plugin development with templates and docs',
    'Razor Edits — Alt+drag multi-track range selection with merged processing',
    'Mix Snapshots — save/recall mixer state with selective capture (volume, pan, mute, sends)',
    'Metadata Browser — BWF/iXML/ID3v2/RIFF metadata parsing with boolean search',
    'Screensets — 10 numbered UI state slots with save/recall (keys 1-0)',
    'Project Tabs — multi-project tab system with swap-in/swap-out state',
    'Sub-Projects — nested .rfproj references on timeline with proxy render',
  ][index];
}

extension DawMixSubTabX on DawMixSubTab {
  String get label => ['Mixer', 'Sends', 'Pan', 'Auto'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
  IconData get icon => [Icons.tune, Icons.call_split, Icons.swap_horiz, Icons.show_chart][index];
  String get tooltip => [
    'Full mixer console with faders, meters, sends, and inserts',
    'Track→Bus routing matrix with send level controls',
    'Stereo panning controls with pan law selection (0/-3/-4.5/-6dB)',
    'Automation curve editor with draw/erase tools',
  ][index];
}

extension DawProcessSubTabX on DawProcessSubTab {
  String get label => ['FF-Q', 'FF-C', 'FF-L', 'FF-R', 'FF-G', 'FF-D', 'FF-SAT', 'FF-E', 'FX Chain', 'Sidechain'][index];
  String get shortcut => ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'][index];
  IconData get icon => [Icons.equalizer, Icons.compress, Icons.volume_up, Icons.waves, Icons.door_front_door, Icons.timer, Icons.whatshot, Icons.mic_off, Icons.link, Icons.call_split][index];
  String get tooltip => [
    'FF-Q — 64-band parametric EQ with GPU spectrum analyzer (60fps)',
    'FF-C — Compressor with 14 styles and sidechain',
    'FF-L — Limiter with True Peak and LUFS metering',
    'FF-R — Reverb with decay display and space types',
    'FF-G — Gate with threshold visualization and sidechain',
    'FF-D — Stereo delay with ping-pong, ducking, and tempo sync',
    'FF-SAT — Saturn 2 multi-mode saturation (Tape, Tube, Transistor)',
    'FF-E — De-Esser with split-band mode and listen function',
    'Visual DSP chain with drag-drop reorder and bypass',
    'Sidechain routing with key input source selection',
  ][index];
}

extension DawDeliverSubTabX on DawDeliverSubTab {
  String get label => ['Export', 'Stems', 'Stem Mgr', 'Loudness', 'Bounce', 'Archive'][index];
  String get shortcut => ['Q', 'W', 'M', 'L', 'E', 'R'][index];
  IconData get icon => [Icons.upload_file, Icons.layers, Icons.library_music, Icons.assessment, Icons.album, Icons.archive][index];
  String get tooltip => [
    'Quick export with last settings (WAV/FLAC/MP3, LUFS normalize)',
    'Export individual tracks/buses as stems (batch export)',
    'Stem Manager — save/recall solo/mute configs, batch render with multi-format',
    'Loudness Report — LUFS analysis, True Peak, LRA, clipping detection, HTML export',
    'Master bounce with format/sample rate/normalize options',
    'ZIP project with audio/presets/plugins (optional compression)',
  ][index];
}

/// Complete DAW Lower Zone state
class DawLowerZoneState {
  DawSuperTab superTab;
  DawBrowseSubTab browseSubTab;
  DawEditSubTab editSubTab;
  DawMixSubTab mixSubTab;
  DawProcessSubTab processSubTab;
  DawDeliverSubTab deliverSubTab;
  bool isExpanded;
  double height;

  // ═══════════════════════════════════════════════════════════════════════════
  // Split View Mode — View 2, 3, or 4 panels simultaneously
  // ═══════════════════════════════════════════════════════════════════════════
  bool splitEnabled;
  SplitDirection splitDirection;
  double splitRatio; // 0.0-1.0, position of divider (legacy, used for 2-panel)
  bool syncScrollEnabled; // Linked scrolling between panes

  /// Number of panels (1=single, 2/3/4=multi-panel)
  int panelCount;

  /// Split ratios for dividers.
  /// 2 panels: [ratio] (1 divider)
  /// 3 panels: [ratio1, ratio2] (2 dividers, cumulative positions 0-1)
  /// 4 panels: [hRatio, vRatio] (horizontal split, vertical split for 2x2 grid)
  List<double> splitRatios;

  /// Tab state for extra panes (index 0 = pane 2, index 1 = pane 3, index 2 = pane 4)
  List<PaneTabState> extraPanes;

  // Legacy second pane tabs (kept for backward compatibility with existing JSON)
  DawSuperTab secondPaneSuperTab;
  DawBrowseSubTab secondPaneBrowseSubTab;
  DawEditSubTab secondPaneEditSubTab;
  DawMixSubTab secondPaneMixSubTab;
  DawProcessSubTab secondPaneProcessSubTab;
  DawDeliverSubTab secondPaneDeliverSubTab;

  DawLowerZoneState({
    this.superTab = DawSuperTab.browse,
    this.browseSubTab = DawBrowseSubTab.files,
    this.editSubTab = DawEditSubTab.timeline,
    this.mixSubTab = DawMixSubTab.mixer,
    this.processSubTab = DawProcessSubTab.eq,
    this.deliverSubTab = DawDeliverSubTab.export,
    this.isExpanded = true,
    this.height = kLowerZoneMaxHeight,
    // Split view defaults
    this.splitEnabled = false,
    this.splitDirection = SplitDirection.horizontal,
    this.splitRatio = kSplitViewDefaultRatio,
    this.syncScrollEnabled = false,
    this.panelCount = 1,
    List<double>? splitRatios,
    List<PaneTabState>? extraPanes,
    // Legacy second pane defaults (backward compat)
    this.secondPaneSuperTab = DawSuperTab.mix,
    this.secondPaneBrowseSubTab = DawBrowseSubTab.files,
    this.secondPaneEditSubTab = DawEditSubTab.timeline,
    this.secondPaneMixSubTab = DawMixSubTab.mixer,
    this.secondPaneProcessSubTab = DawProcessSubTab.eq,
    this.secondPaneDeliverSubTab = DawDeliverSubTab.export,
  }) : splitRatios = splitRatios ?? defaultSplitRatios(2),
       extraPanes = extraPanes ?? [
         PaneTabState.defaultForIndex(0),
         PaneTabState.defaultForIndex(1),
         PaneTabState.defaultForIndex(2),
       ];

  /// Get current sub-tab index for active super-tab
  int get currentSubTabIndex => switch (superTab) {
    DawSuperTab.browse => browseSubTab.index,
    DawSuperTab.edit => editSubTab.index,
    DawSuperTab.mix => mixSubTab.index,
    DawSuperTab.process => processSubTab.index,
    DawSuperTab.deliver => deliverSubTab.index,
  };

  /// Set sub-tab by index for active super-tab
  void setSubTabIndex(int index) {
    switch (superTab) {
      case DawSuperTab.browse:
        browseSubTab = DawBrowseSubTab.values[index.clamp(0, 3)];
      case DawSuperTab.edit:
        editSubTab = DawEditSubTab.values[index.clamp(0, DawEditSubTab.values.length - 1)];
      case DawSuperTab.mix:
        mixSubTab = DawMixSubTab.values[index.clamp(0, 3)];
      case DawSuperTab.process:
        processSubTab = DawProcessSubTab.values[index.clamp(0, DawProcessSubTab.values.length - 1)];
      case DawSuperTab.deliver:
        deliverSubTab = DawDeliverSubTab.values[index.clamp(0, DawDeliverSubTab.values.length - 1)];
    }
  }

  /// Get sub-tab labels for active super-tab
  List<String> get subTabLabels => switch (superTab) {
    DawSuperTab.browse => DawBrowseSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.edit => DawEditSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.mix => DawMixSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.process => DawProcessSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.deliver => DawDeliverSubTab.values.map((e) => e.label).toList(),
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // P2.1: Second Pane Tab Access (Split View Mode)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get current sub-tab index for second pane's active super-tab
  int get secondPaneCurrentSubTabIndex => switch (secondPaneSuperTab) {
    DawSuperTab.browse => secondPaneBrowseSubTab.index,
    DawSuperTab.edit => secondPaneEditSubTab.index,
    DawSuperTab.mix => secondPaneMixSubTab.index,
    DawSuperTab.process => secondPaneProcessSubTab.index,
    DawSuperTab.deliver => secondPaneDeliverSubTab.index,
  };

  /// Set sub-tab by index for second pane's active super-tab
  void setSecondPaneSubTabIndex(int index) {
    switch (secondPaneSuperTab) {
      case DawSuperTab.browse:
        secondPaneBrowseSubTab = DawBrowseSubTab.values[index.clamp(0, 3)];
      case DawSuperTab.edit:
        secondPaneEditSubTab = DawEditSubTab.values[index.clamp(0, DawEditSubTab.values.length - 1)];
      case DawSuperTab.mix:
        secondPaneMixSubTab = DawMixSubTab.values[index.clamp(0, 3)];
      case DawSuperTab.process:
        secondPaneProcessSubTab = DawProcessSubTab.values[index.clamp(0, DawProcessSubTab.values.length - 1)];
      case DawSuperTab.deliver:
        secondPaneDeliverSubTab = DawDeliverSubTab.values[index.clamp(0, DawDeliverSubTab.values.length - 1)];
    }
  }

  /// Get sub-tab labels for second pane's active super-tab
  List<String> get secondPaneSubTabLabels => switch (secondPaneSuperTab) {
    DawSuperTab.browse => DawBrowseSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.edit => DawEditSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.mix => DawMixSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.process => DawProcessSubTab.values.map((e) => e.label).toList(),
    DawSuperTab.deliver => DawDeliverSubTab.values.map((e) => e.label).toList(),
  };

  DawLowerZoneState copyWith({
    DawSuperTab? superTab,
    DawBrowseSubTab? browseSubTab,
    DawEditSubTab? editSubTab,
    DawMixSubTab? mixSubTab,
    DawProcessSubTab? processSubTab,
    DawDeliverSubTab? deliverSubTab,
    bool? isExpanded,
    double? height,
    // Split view fields
    bool? splitEnabled,
    SplitDirection? splitDirection,
    double? splitRatio,
    bool? syncScrollEnabled,
    int? panelCount,
    List<double>? splitRatios,
    List<PaneTabState>? extraPanes,
    DawSuperTab? secondPaneSuperTab,
    DawBrowseSubTab? secondPaneBrowseSubTab,
    DawEditSubTab? secondPaneEditSubTab,
    DawMixSubTab? secondPaneMixSubTab,
    DawProcessSubTab? secondPaneProcessSubTab,
    DawDeliverSubTab? secondPaneDeliverSubTab,
  }) {
    return DawLowerZoneState(
      superTab: superTab ?? this.superTab,
      browseSubTab: browseSubTab ?? this.browseSubTab,
      editSubTab: editSubTab ?? this.editSubTab,
      mixSubTab: mixSubTab ?? this.mixSubTab,
      processSubTab: processSubTab ?? this.processSubTab,
      deliverSubTab: deliverSubTab ?? this.deliverSubTab,
      isExpanded: isExpanded ?? this.isExpanded,
      height: height ?? this.height,
      // Split view
      splitEnabled: splitEnabled ?? this.splitEnabled,
      splitDirection: splitDirection ?? this.splitDirection,
      splitRatio: splitRatio ?? this.splitRatio,
      syncScrollEnabled: syncScrollEnabled ?? this.syncScrollEnabled,
      panelCount: panelCount ?? this.panelCount,
      splitRatios: splitRatios ?? List<double>.from(this.splitRatios),
      extraPanes: extraPanes ?? this.extraPanes.map((p) => p.copy()).toList(),
      secondPaneSuperTab: secondPaneSuperTab ?? this.secondPaneSuperTab,
      secondPaneBrowseSubTab: secondPaneBrowseSubTab ?? this.secondPaneBrowseSubTab,
      secondPaneEditSubTab: secondPaneEditSubTab ?? this.secondPaneEditSubTab,
      secondPaneMixSubTab: secondPaneMixSubTab ?? this.secondPaneMixSubTab,
      secondPaneProcessSubTab: secondPaneProcessSubTab ?? this.secondPaneProcessSubTab,
      secondPaneDeliverSubTab: secondPaneDeliverSubTab ?? this.secondPaneDeliverSubTab,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
    'superTab': superTab.index,
    'browseSubTab': browseSubTab.index,
    'editSubTab': editSubTab.index,
    'mixSubTab': mixSubTab.index,
    'processSubTab': processSubTab.index,
    'deliverSubTab': deliverSubTab.index,
    'isExpanded': isExpanded,
    'height': height,
    // Split view
    'splitEnabled': splitEnabled,
    'splitDirection': splitDirection.index,
    'splitRatio': splitRatio,
    'syncScrollEnabled': syncScrollEnabled,
    // Multi-pane
    'panelCount': panelCount,
    'splitRatios': splitRatios,
    'extraPanes': extraPanes.map((p) => p.toJson()).toList(),
    'secondPaneSuperTab': secondPaneSuperTab.index,
    'secondPaneBrowseSubTab': secondPaneBrowseSubTab.index,
    'secondPaneEditSubTab': secondPaneEditSubTab.index,
    'secondPaneMixSubTab': secondPaneMixSubTab.index,
    'secondPaneProcessSubTab': secondPaneProcessSubTab.index,
    'secondPaneDeliverSubTab': secondPaneDeliverSubTab.index,
  };

  /// Deserialize from JSON
  factory DawLowerZoneState.fromJson(Map<String, dynamic> json) {
    // Parse extraPanes (backward compatible — old JSON won't have this)
    final extraPanesJson = json['extraPanes'] as List<dynamic>?;
    final extraPanes = extraPanesJson
        ?.map((e) => PaneTabState.fromJson(e as Map<String, dynamic>))
        .toList();

    // Parse splitRatios (backward compatible)
    final splitRatiosJson = json['splitRatios'] as List<dynamic>?;
    final splitRatios = splitRatiosJson?.map((e) => (e as num).toDouble()).toList();

    return DawLowerZoneState(
      superTab: DawSuperTab.values[json['superTab'] as int? ?? 0],
      browseSubTab: DawBrowseSubTab.values[json['browseSubTab'] as int? ?? 0],
      editSubTab: DawEditSubTab.values[(json['editSubTab'] as int? ?? 0).clamp(0, DawEditSubTab.values.length - 1)],
      mixSubTab: DawMixSubTab.values[json['mixSubTab'] as int? ?? 0],
      processSubTab: DawProcessSubTab.values[(json['processSubTab'] as int? ?? 0).clamp(0, DawProcessSubTab.values.length - 1)],
      deliverSubTab: DawDeliverSubTab.values[(json['deliverSubTab'] as int? ?? 0).clamp(0, DawDeliverSubTab.values.length - 1)],
      isExpanded: json['isExpanded'] as bool? ?? true,
      height: (json['height'] as num?)?.toDouble() ?? kLowerZoneMaxHeight,
      // Split view
      splitEnabled: json['splitEnabled'] as bool? ?? false,
      splitDirection: SplitDirection.values[json['splitDirection'] as int? ?? 0],
      splitRatio: (json['splitRatio'] as num?)?.toDouble() ?? kSplitViewDefaultRatio,
      syncScrollEnabled: json['syncScrollEnabled'] as bool? ?? false,
      // Multi-pane (backward compatible — defaults if missing)
      panelCount: json['panelCount'] as int? ?? 1,
      splitRatios: splitRatios,
      extraPanes: extraPanes,
      secondPaneSuperTab: DawSuperTab.values[json['secondPaneSuperTab'] as int? ?? 2],
      secondPaneBrowseSubTab: DawBrowseSubTab.values[json['secondPaneBrowseSubTab'] as int? ?? 0],
      secondPaneEditSubTab: DawEditSubTab.values[(json['secondPaneEditSubTab'] as int? ?? 0).clamp(0, DawEditSubTab.values.length - 1)],
      secondPaneMixSubTab: DawMixSubTab.values[json['secondPaneMixSubTab'] as int? ?? 0],
      secondPaneProcessSubTab: DawProcessSubTab.values[(json['secondPaneProcessSubTab'] as int? ?? 0).clamp(0, DawProcessSubTab.values.length - 1)],
      secondPaneDeliverSubTab: DawDeliverSubTab.values[(json['secondPaneDeliverSubTab'] as int? ?? 0).clamp(0, DawDeliverSubTab.values.length - 1)],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════════
//
//  MIDDLEWARE LOWER ZONE — Wwise/FMOD-style event logic
//
// ═══════════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════════
//
//  SLOTLAB LOWER ZONE — Synthetic slot engine testing
//
// ═══════════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════════

/// SlotLab Super-tabs: STAGES, EVENTS, MIX, DSP, RTPC, CONTAINERS, MUSIC, LOGIC, INTEL, MONITOR, BAKE
enum SlotLabSuperTab { stages, events, mix, dsp, rtpc, containers, music, logic, intel, monitor, bake }

extension SlotLabSuperTabX on SlotLabSuperTab {
  String get label => switch (this) {
    SlotLabSuperTab.stages => 'STAGES',
    SlotLabSuperTab.events => 'EVENTS',
    SlotLabSuperTab.mix => 'MIX',
    SlotLabSuperTab.dsp => 'DSP',
    SlotLabSuperTab.rtpc => 'RTPC',
    SlotLabSuperTab.containers => 'CONTAINERS',
    SlotLabSuperTab.music => 'MUSIC',
    SlotLabSuperTab.logic => 'LOGIC',
    SlotLabSuperTab.intel => 'INTEL',
    SlotLabSuperTab.monitor => 'MONITOR',
    SlotLabSuperTab.bake => 'BAKE',
  };
  IconData get icon => switch (this) {
    SlotLabSuperTab.stages => Icons.theaters,
    SlotLabSuperTab.events => Icons.music_note,
    SlotLabSuperTab.mix => Icons.tune,
    SlotLabSuperTab.dsp => Icons.graphic_eq,
    SlotLabSuperTab.rtpc => Icons.speed,
    SlotLabSuperTab.containers => Icons.inventory_2,
    SlotLabSuperTab.music => Icons.queue_music,
    SlotLabSuperTab.logic => Icons.account_tree,
    SlotLabSuperTab.intel => Icons.psychology,
    SlotLabSuperTab.monitor => Icons.monitor_heart,
    SlotLabSuperTab.bake => Icons.local_fire_department,
  };
  String get shortcut => '${index + 1}';

  /// Category-based accent colors for visual hierarchy:
  /// STAGES (standalone) = cyan, AUDIO (events/mix/dsp/music) = green,
  /// DESIGN (rtpc/containers) = purple, DEBUG (logic/intel/monitor) = amber,
  /// PRODUCTION (bake) = orange
  Color get color => switch (this) {
    SlotLabSuperTab.stages     => const Color(0xFF40C8FF), // Cyan — game flow
    SlotLabSuperTab.events     => const Color(0xFF50FF98), // Green — audio
    SlotLabSuperTab.mix        => const Color(0xFF50FF98),
    SlotLabSuperTab.dsp        => const Color(0xFF50FF98),
    SlotLabSuperTab.music      => const Color(0xFF50FF98),
    SlotLabSuperTab.rtpc       => const Color(0xFFB080FF), // Purple — design
    SlotLabSuperTab.containers => const Color(0xFFB080FF),
    SlotLabSuperTab.logic      => const Color(0xFFFFD054), // Amber — debug/intel
    SlotLabSuperTab.intel      => const Color(0xFFFFD054),
    SlotLabSuperTab.monitor    => const Color(0xFFFFD054),
    SlotLabSuperTab.bake       => const Color(0xFFFF9850), // Orange — production
  };

  /// Category label for group identification
  String get category => switch (this) {
    SlotLabSuperTab.stages     => 'FLOW',
    SlotLabSuperTab.events     => 'AUDIO',
    SlotLabSuperTab.mix        => 'AUDIO',
    SlotLabSuperTab.dsp        => 'AUDIO',
    SlotLabSuperTab.music      => 'AUDIO',
    SlotLabSuperTab.rtpc       => 'DESIGN',
    SlotLabSuperTab.containers => 'DESIGN',
    SlotLabSuperTab.logic      => 'DEBUG',
    SlotLabSuperTab.intel      => 'DEBUG',
    SlotLabSuperTab.monitor    => 'DEBUG',
    SlotLabSuperTab.bake       => 'EXPORT',
  };

  String get tooltip => switch (this) {
    SlotLabSuperTab.stages     => 'Game states & stage flow — trace, timeline, symbols',
    SlotLabSuperTab.events     => 'Audio events — folders, layers, pool, templates',
    SlotLabSuperTab.mix        => 'Mix routing — buses, sends, pan, metering',
    SlotLabSuperTab.dsp        => 'DSP effects — EQ, comp, reverb, gate, spatial',
    SlotLabSuperTab.rtpc       => 'Real-time parameters — curves, macros, bindings',
    SlotLabSuperTab.containers => 'Sound containers — blend, random, sequence, crossfade',
    SlotLabSuperTab.music      => 'Interactive music — segments, stingers, transitions',
    SlotLabSuperTab.logic      => 'Game logic — behaviors, triggers, state machines',
    SlotLabSuperTab.intel      => 'Analysis & QA — build reports, flow, diagnostics',
    SlotLabSuperTab.monitor    => 'Live monitoring — voice, spectral, profiling',
    SlotLabSuperTab.bake       => 'Export & delivery — stems, packages, versioning',
  };
}

// --- SlotLab Sub-tabs ---

enum SlotLabStagesSubTab { trace, timeline, timing, layerTimeline }
enum SlotLabEventsSubTab { folder, editor, layers, pool, auto, templates, depGraph }
enum SlotLabMixSubTab { buses, sends, pan, meter, hierarchy, ducking }
enum SlotLabDspSubTab { chain, eq, comp, reverb, gate, limiter, attenuation, signatures, dspProfiler, layerDsp, presetMorph, spatial }
enum SlotLabRtpcSubTab { curves, macros, dspBinding, debugger }
enum SlotLabContainersSubTab { blend, random, sequence, abCompare, crossfade, groups, presets, metrics, timeline, wizard }
enum SlotLabMusicSubTab { layers, segments, stingers, transitions, looping, beatGrid, tempoStates }
enum SlotLabBakeSubTab { export, stems, variations, package, git, analytics, docs, macro, macroMon, macroReport, macroConfig, macroHistory }

/// LOGIC sub-tabs — Core middleware panels (behavior tree, triggers, state gate, etc.)
enum SlotLabLogicSubTab { behavior, triggers, gate, priority, orchestration, emotional, context, simulation, priorityPreset, stateMachine, stateHistory }

/// INTEL sub-tabs — MWUI intelligence views (build, flow, diagnostics, etc.)
enum SlotLabIntelSubTab { build, flow, sim, diagnostic, templates, export, coverage, inspector }

/// MONITOR sub-tabs — UCP monitoring zones (timeline, energy, spectral, etc.)
enum SlotLabMonitorSubTab { timeline, energy, voice, spectral, fatigue, ail, debug, export, profiler, profilerAdv, evtDebug, resource, voiceStats }

extension SlotLabStagesSubTabX on SlotLabStagesSubTab {
  String get label => ['Trace', 'Timeline', 'Timing', 'Layers'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
  String get tooltip => [
    'Stage event trace — chronological log of triggered stages',
    'Timeline — visual event-layer timeline with waveforms',
    'Timing — stage timing profiler and latency analysis',
    'Layers — per-layer timeline with crossfades',
  ][index];
}

extension SlotLabEventsSubTabX on SlotLabEventsSubTab {
  String get label => ['Folder', 'Editor', 'Layers', 'Pool', 'Auto', 'Templates', 'Dep Graph'][index];
  String get shortcut => ['Q', 'W', 'E', 'R', 'T', 'Y', 'U'][index];
  String get tooltip => [
    'Event folder — hierarchical event browser',
    'Composite editor — multi-layer event builder',
    'Event layers — layer list with properties',
    'Voice pool — active voice allocation and limits',
    'Automation — parameter automation curves',
    'Event templates — reusable event presets',
    'Dependency graph — event/stage relationship map',
  ][index];
}

extension SlotLabMixSubTabX on SlotLabMixSubTab {
  String get label => ['Buses', 'Sends', 'Pan', 'Meter', 'Hierarchy', 'Ducking'][index];
  String get shortcut => ['Q', 'W', 'E', 'R', 'T', 'Y'][index];
  String get tooltip => [
    'Bus mixer — per-bus faders, mute/solo',
    'Aux sends — effect send/return routing matrix',
    'Pan — stereo/surround panning controls',
    'Meters — real-time per-bus level meters',
    'Bus hierarchy — parent/child bus routing',
    'Ducking — inter-bus volume ducking matrix',
  ][index];
}

extension SlotLabDspSubTabX on SlotLabDspSubTab {
  String get label => ['Chain', 'FF-Q', 'FF-C', 'FF-R', 'FF-G', 'FF-L', 'Atten', 'Sigs', 'DSP Prof', 'Layer DSP', 'Morph', 'Spatial'][index];
  String get shortcut => ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', 'A', 'S'][index];
  String get tooltip => [
    'DSP chain — insert effect order and routing',
    'FabFilter EQ — parametric equalizer',
    'FabFilter Compressor — dynamics processing',
    'FabFilter Reverb — convolution/algorithmic reverb',
    'FabFilter Gate — noise gate / expander',
    'FabFilter Limiter — brick-wall limiter',
    'Attenuation — distance/priority attenuation curves',
    'Audio signatures — frequency fingerprint analysis',
    'DSP profiler — per-effect CPU usage monitoring',
    'Layer DSP — per-layer effect processing',
    'Preset morph — interpolate between DSP presets',
    'Spatial audio — 3D positioning and HRTF',
  ][index];
}

extension SlotLabBakeSubTabX on SlotLabBakeSubTab {
  String get label => ['Export', 'Stems', 'Variations', 'Package', 'Git', 'Analytics', 'Docs', 'Macro', 'Monitor', 'Reports', 'Config', 'History'][index];
  String get shortcut => ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', 'A', 'S'][index];
  String get tooltip => [
    'Batch export — render all events to audio files',
    'Stems — export individual layers as stems',
    'Variations — generate randomized audio variants',
    'Package — bundle project for deployment',
    'Git — version control for audio configs',
    'Analytics — project statistics dashboard',
    'Documentation — auto-generated project docs',
    'Macro — batch automation scripts',
    'Macro monitor — live macro execution status',
    'Macro reports — execution results and logs',
    'Macro config — automation settings',
    'Macro history — past execution timeline',
  ][index];
}

extension SlotLabLogicSubTabX on SlotLabLogicSubTab {
  String get label => ['Behavior', 'Triggers', 'Gate', 'Priority', 'Orch', 'Emotion', 'Context', 'Sim', 'Pri Preset', 'State Machine', 'State Hist'][index];
  String get shortcut => ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', 'A'][index];
  String get tooltip => [
    'Behavior tree — game audio behavior logic',
    'Triggers — stage trigger conditions and rules',
    'State gate — conditional playback gates',
    'Priority — voice priority assignment',
    'Orchestration — multi-event coordination rules',
    'Emotional arc — excitement/tension curve design',
    'Context — game state context awareness',
    'Simulation — logic simulation sandbox',
    'Priority presets — saved priority configurations',
    'State machine — FSM state editor',
    'State history — state transition log',
  ][index];
}

extension SlotLabIntelSubTabX on SlotLabIntelSubTab {
  String get label => ['Build', 'Flow', 'SimView', 'Diag', 'Templates', 'Export', 'Coverage', 'Inspector'][index];
  String get shortcut => ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I'][index];
  String get tooltip => [
    'Build — compile and validate event configurations',
    'Flow — event/stage flow visualization',
    'Simulation — spin outcome simulation view',
    'Diagnostics — system health checks',
    'Templates — event template gallery',
    'Export — configuration export tools',
    'Coverage — stage audio coverage map',
    'Inspector — live event object inspector',
  ][index];
}

extension SlotLabMonitorSubTabX on SlotLabMonitorSubTab {
  String get label => ['Timeline', 'Energy', 'Voice', 'Spectral', 'Fatigue', 'AIL', 'Debug', 'Export', 'Profiler', 'Prof Adv', 'Evt Debug', 'Resources', 'Voice Stats'][index];
  String get shortcut => ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', 'A', 'S', 'D'][index];
  String get tooltip => [
    'Event timeline — real-time event activity log',
    'Energy — emotional energy arc monitor',
    'Voice — active voice count per priority',
    'Spectral — frequency spectrum heatmap',
    'Fatigue — CPU/memory stability metrics',
    'AIL — adaptive audio intelligence learning',
    'Debug — raw debug output and FFI trace',
    'Export — monitoring data export',
    'Profiler — real-time performance metrics',
    'Advanced profiler — detailed CPU/latency breakdown',
    'Event debugger — event trigger/stop tracing',
    'Resources — audio asset memory usage',
    'Voice stats — voice pool statistics',
  ][index];
}

extension SlotLabRtpcSubTabX on SlotLabRtpcSubTab {
  String get label => ['Curves', 'Macros', 'DSP Bind', 'Debugger'][index];
  String get shortcut => ['Q', 'W', 'E', 'R'][index];
  String get tooltip => [
    'RTPC curves — real-time parameter control curves',
    'Macros — RTPC macro definitions',
    'DSP binding — bind RTPC to DSP parameters',
    'RTPC debugger — live parameter value inspector',
  ][index];
}

extension SlotLabContainersSubTabX on SlotLabContainersSubTab {
  String get label => ['Blend', 'Random', 'Sequence', 'A/B', 'Crossfade', 'Groups', 'Presets', 'Metrics', 'Timeline', 'Wizard'][index];
  String get shortcut => ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'][index];
  String get tooltip => [
    'Blend container — mix multiple audio sources',
    'Random container — weighted random selection',
    'Sequence container — ordered playback chain',
    'A/B compare — side-by-side audio comparison',
    'Crossfade — smooth transition between sources',
    'Groups — logical audio grouping',
    'Presets — saved container configurations',
    'Metrics — container usage statistics',
    'Timeline — container playback timeline',
    'Wizard — guided container setup',
  ][index];
}

extension SlotLabMusicSubTabX on SlotLabMusicSubTab {
  String get label => ['Layers', 'Segments', 'Stingers', 'Transitions', 'Looping', 'Beat Grid', 'Tempo States'][index];
  String get shortcut => ['Q', 'W', 'E', 'R', 'T', 'Y', 'U'][index];
  String get tooltip => [
    'Dynamic layers — win-driven music layer crossfade controller',
    'Music segments — interactive music section editor',
    'Stingers — one-shot musical transitions',
    'Transitions — segment-to-segment transition rules',
    'Looping — seamless loop point editor',
    'Beat grid — tempo/beat alignment grid',
    'Tempo states — Wwise-style tempo transitions with beat-synced crossfade',
  ][index];
}

/// Complete SlotLab Lower Zone state
class SlotLabLowerZoneState {
  SlotLabSuperTab superTab;
  SlotLabStagesSubTab stagesSubTab;
  SlotLabEventsSubTab eventsSubTab;
  SlotLabMixSubTab mixSubTab;
  SlotLabDspSubTab dspSubTab;
  SlotLabRtpcSubTab rtpcSubTab;
  SlotLabContainersSubTab containersSubTab;
  SlotLabMusicSubTab musicSubTab;
  SlotLabBakeSubTab bakeSubTab;
  SlotLabLogicSubTab logicSubTab;
  SlotLabIntelSubTab intelSubTab;
  SlotLabMonitorSubTab monitorSubTab;
  bool isExpanded;
  double height;

  SlotLabLowerZoneState({
    this.superTab = SlotLabSuperTab.stages,
    this.stagesSubTab = SlotLabStagesSubTab.trace,
    this.eventsSubTab = SlotLabEventsSubTab.folder,
    this.mixSubTab = SlotLabMixSubTab.buses,
    this.dspSubTab = SlotLabDspSubTab.chain,
    this.rtpcSubTab = SlotLabRtpcSubTab.curves,
    this.containersSubTab = SlotLabContainersSubTab.blend,
    this.musicSubTab = SlotLabMusicSubTab.segments,
    this.bakeSubTab = SlotLabBakeSubTab.export,
    this.logicSubTab = SlotLabLogicSubTab.behavior,
    this.intelSubTab = SlotLabIntelSubTab.build,
    this.monitorSubTab = SlotLabMonitorSubTab.timeline,
    this.isExpanded = false,
    this.height = kLowerZoneDefaultHeight,
  });

  int get currentSubTabIndex => switch (superTab) {
    SlotLabSuperTab.stages => stagesSubTab.index,
    SlotLabSuperTab.events => eventsSubTab.index,
    SlotLabSuperTab.mix => mixSubTab.index,
    SlotLabSuperTab.dsp => dspSubTab.index,
    SlotLabSuperTab.rtpc => rtpcSubTab.index,
    SlotLabSuperTab.containers => containersSubTab.index,
    SlotLabSuperTab.music => musicSubTab.index,
    SlotLabSuperTab.bake => bakeSubTab.index,
    SlotLabSuperTab.logic => logicSubTab.index,
    SlotLabSuperTab.intel => intelSubTab.index,
    SlotLabSuperTab.monitor => monitorSubTab.index,
  };

  void setSubTabIndex(int index) {
    switch (superTab) {
      case SlotLabSuperTab.stages:
        stagesSubTab = SlotLabStagesSubTab.values[index.clamp(0, SlotLabStagesSubTab.values.length - 1)];
      case SlotLabSuperTab.events:
        eventsSubTab = SlotLabEventsSubTab.values[index.clamp(0, SlotLabEventsSubTab.values.length - 1)];
      case SlotLabSuperTab.mix:
        mixSubTab = SlotLabMixSubTab.values[index.clamp(0, SlotLabMixSubTab.values.length - 1)];
      case SlotLabSuperTab.dsp:
        dspSubTab = SlotLabDspSubTab.values[index.clamp(0, SlotLabDspSubTab.values.length - 1)];
      case SlotLabSuperTab.rtpc:
        rtpcSubTab = SlotLabRtpcSubTab.values[index.clamp(0, SlotLabRtpcSubTab.values.length - 1)];
      case SlotLabSuperTab.containers:
        containersSubTab = SlotLabContainersSubTab.values[index.clamp(0, SlotLabContainersSubTab.values.length - 1)];
      case SlotLabSuperTab.music:
        musicSubTab = SlotLabMusicSubTab.values[index.clamp(0, SlotLabMusicSubTab.values.length - 1)];
      case SlotLabSuperTab.bake:
        bakeSubTab = SlotLabBakeSubTab.values[index.clamp(0, SlotLabBakeSubTab.values.length - 1)];
      case SlotLabSuperTab.logic:
        logicSubTab = SlotLabLogicSubTab.values[index.clamp(0, SlotLabLogicSubTab.values.length - 1)];
      case SlotLabSuperTab.intel:
        intelSubTab = SlotLabIntelSubTab.values[index.clamp(0, SlotLabIntelSubTab.values.length - 1)];
      case SlotLabSuperTab.monitor:
        monitorSubTab = SlotLabMonitorSubTab.values[index.clamp(0, SlotLabMonitorSubTab.values.length - 1)];
    }
  }

  List<String> get subTabLabels => switch (superTab) {
    SlotLabSuperTab.stages => SlotLabStagesSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.events => SlotLabEventsSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.mix => SlotLabMixSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.dsp => SlotLabDspSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.rtpc => SlotLabRtpcSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.containers => SlotLabContainersSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.music => SlotLabMusicSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.bake => SlotLabBakeSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.logic => SlotLabLogicSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.intel => SlotLabIntelSubTab.values.map((e) => e.label).toList(),
    SlotLabSuperTab.monitor => SlotLabMonitorSubTab.values.map((e) => e.label).toList(),
  };

  List<String> get subTabTooltips => switch (superTab) {
    SlotLabSuperTab.stages => SlotLabStagesSubTab.values.map((e) => e.tooltip).toList(),
    SlotLabSuperTab.events => SlotLabEventsSubTab.values.map((e) => e.tooltip).toList(),
    SlotLabSuperTab.mix => SlotLabMixSubTab.values.map((e) => e.tooltip).toList(),
    SlotLabSuperTab.dsp => SlotLabDspSubTab.values.map((e) => e.tooltip).toList(),
    SlotLabSuperTab.rtpc => SlotLabRtpcSubTab.values.map((e) => e.tooltip).toList(),
    SlotLabSuperTab.containers => SlotLabContainersSubTab.values.map((e) => e.tooltip).toList(),
    SlotLabSuperTab.music => SlotLabMusicSubTab.values.map((e) => e.tooltip).toList(),
    SlotLabSuperTab.bake => SlotLabBakeSubTab.values.map((e) => e.tooltip).toList(),
    SlotLabSuperTab.logic => SlotLabLogicSubTab.values.map((e) => e.tooltip).toList(),
    SlotLabSuperTab.intel => SlotLabIntelSubTab.values.map((e) => e.tooltip).toList(),
    SlotLabSuperTab.monitor => SlotLabMonitorSubTab.values.map((e) => e.tooltip).toList(),
  };

  SlotLabLowerZoneState copyWith({
    SlotLabSuperTab? superTab,
    SlotLabStagesSubTab? stagesSubTab,
    SlotLabEventsSubTab? eventsSubTab,
    SlotLabMixSubTab? mixSubTab,
    SlotLabDspSubTab? dspSubTab,
    SlotLabRtpcSubTab? rtpcSubTab,
    SlotLabContainersSubTab? containersSubTab,
    SlotLabMusicSubTab? musicSubTab,
    SlotLabBakeSubTab? bakeSubTab,
    SlotLabLogicSubTab? logicSubTab,
    SlotLabIntelSubTab? intelSubTab,
    SlotLabMonitorSubTab? monitorSubTab,
    bool? isExpanded,
    double? height,
  }) {
    return SlotLabLowerZoneState(
      superTab: superTab ?? this.superTab,
      stagesSubTab: stagesSubTab ?? this.stagesSubTab,
      eventsSubTab: eventsSubTab ?? this.eventsSubTab,
      mixSubTab: mixSubTab ?? this.mixSubTab,
      dspSubTab: dspSubTab ?? this.dspSubTab,
      rtpcSubTab: rtpcSubTab ?? this.rtpcSubTab,
      containersSubTab: containersSubTab ?? this.containersSubTab,
      musicSubTab: musicSubTab ?? this.musicSubTab,
      bakeSubTab: bakeSubTab ?? this.bakeSubTab,
      logicSubTab: logicSubTab ?? this.logicSubTab,
      intelSubTab: intelSubTab ?? this.intelSubTab,
      monitorSubTab: monitorSubTab ?? this.monitorSubTab,
      isExpanded: isExpanded ?? this.isExpanded,
      height: height ?? this.height,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
    'superTab': superTab.index,
    'stagesSubTab': stagesSubTab.index,
    'eventsSubTab': eventsSubTab.index,
    'mixSubTab': mixSubTab.index,
    'dspSubTab': dspSubTab.index,
    'rtpcSubTab': rtpcSubTab.index,
    'containersSubTab': containersSubTab.index,
    'musicSubTab': musicSubTab.index,
    'bakeSubTab': bakeSubTab.index,
    'logicSubTab': logicSubTab.index,
    'intelSubTab': intelSubTab.index,
    'monitorSubTab': monitorSubTab.index,
    'isExpanded': isExpanded,
    'height': height,
  };

  /// Deserialize from JSON (backward-compatible: old 'middlewareSubTab' maps to logicSubTab)
  factory SlotLabLowerZoneState.fromJson(Map<String, dynamic> json) {
    // Handle old superTab index: old middleware=5 → now logic=4
    var superIdx = (json['superTab'] as int? ?? 0).clamp(0, SlotLabSuperTab.values.length - 1);
    return SlotLabLowerZoneState(
      superTab: SlotLabSuperTab.values[superIdx],
      stagesSubTab: SlotLabStagesSubTab.values[(json['stagesSubTab'] as int? ?? 0).clamp(0, SlotLabStagesSubTab.values.length - 1)],
      eventsSubTab: SlotLabEventsSubTab.values[(json['eventsSubTab'] as int? ?? 0).clamp(0, SlotLabEventsSubTab.values.length - 1)],
      mixSubTab: SlotLabMixSubTab.values[(json['mixSubTab'] as int? ?? 0).clamp(0, SlotLabMixSubTab.values.length - 1)],
      dspSubTab: SlotLabDspSubTab.values[(json['dspSubTab'] as int? ?? 0).clamp(0, SlotLabDspSubTab.values.length - 1)],
      rtpcSubTab: SlotLabRtpcSubTab.values[(json['rtpcSubTab'] as int? ?? 0).clamp(0, SlotLabRtpcSubTab.values.length - 1)],
      containersSubTab: SlotLabContainersSubTab.values[(json['containersSubTab'] as int? ?? 0).clamp(0, SlotLabContainersSubTab.values.length - 1)],
      musicSubTab: SlotLabMusicSubTab.values[(json['musicSubTab'] as int? ?? 0).clamp(0, SlotLabMusicSubTab.values.length - 1)],
      bakeSubTab: SlotLabBakeSubTab.values[(json['bakeSubTab'] as int? ?? 0).clamp(0, SlotLabBakeSubTab.values.length - 1)],
      logicSubTab: SlotLabLogicSubTab.values[(json['logicSubTab'] as int? ?? json['middlewareSubTab'] as int? ?? 0).clamp(0, SlotLabLogicSubTab.values.length - 1)],
      intelSubTab: SlotLabIntelSubTab.values[(json['intelSubTab'] as int? ?? 0).clamp(0, SlotLabIntelSubTab.values.length - 1)],
      monitorSubTab: SlotLabMonitorSubTab.values[(json['monitorSubTab'] as int? ?? 0).clamp(0, SlotLabMonitorSubTab.values.length - 1)],
      isExpanded: json['isExpanded'] as bool? ?? false,
      height: (json['height'] as num?)?.toDouble() ?? kLowerZoneDefaultHeight,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P0.2: FOCUS INDICATOR WIDGET — Keyboard navigation support
// ═══════════════════════════════════════════════════════════════════════════════

/// Wrapper that adds focus ring when widget is focused via keyboard
class LowerZoneFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final Color? focusColor;
  final BorderRadius? borderRadius;

  const LowerZoneFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.focusColor,
    this.borderRadius,
  });

  @override
  State<LowerZoneFocusable> createState() => _LowerZoneFocusableState();
}

class _LowerZoneFocusableState extends State<LowerZoneFocusable> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        setState(() => _isFocused = hasFocus);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(4),
            border: _isFocused
                ? Border.all(
                    color: widget.focusColor ?? LowerZoneColors.focusRing,
                    width: LowerZoneColors.focusRingWidth,
                  )
                : null,
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: (widget.focusColor ?? LowerZoneColors.focusRing)
                          .withValues(alpha: 0.3),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P0.4: ERROR STATE WIDGETS — User feedback for failures
// ═══════════════════════════════════════════════════════════════════════════════

/// Error severity levels
enum LowerZoneErrorSeverity { info, warning, error }

/// Inline error banner for panels
class LowerZoneErrorBanner extends StatelessWidget {
  final String message;
  final LowerZoneErrorSeverity severity;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;

  const LowerZoneErrorBanner({
    super.key,
    required this.message,
    this.severity = LowerZoneErrorSeverity.error,
    this.onDismiss,
    this.onRetry,
  });

  Color get _color => switch (severity) {
        LowerZoneErrorSeverity.info => LowerZoneColors.dawAccent,
        LowerZoneErrorSeverity.warning => LowerZoneColors.warning,
        LowerZoneErrorSeverity.error => LowerZoneColors.error,
      };

  IconData get _icon => switch (severity) {
        LowerZoneErrorSeverity.info => Icons.info_outline,
        LowerZoneErrorSeverity.warning => Icons.warning_amber,
        LowerZoneErrorSeverity.error => Icons.error_outline,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 18, color: _color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeLabel,
                color: _color,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: LowerZoneTypography.sizeBadge,
                    fontWeight: FontWeight.bold,
                    color: _color,
                  ),
                ),
              ),
            ),
          ],
          if (onDismiss != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close, size: 16, color: _color),
            ),
          ],
        ],
      ),
    );
  }
}

/// Empty state placeholder with optional action
class LowerZoneEmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? accentColor;

  const LowerZoneEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.actionLabel,
    this.onAction,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? LowerZoneColors.textMuted;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: color.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: LowerZoneTypography.sizeTitle,
              fontWeight: FontWeight.w600,
              color: LowerZoneColors.textSecondary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeLabel,
                color: LowerZoneColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    fontSize: LowerZoneTypography.sizeLabel,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Loading state placeholder
class LowerZoneLoadingState extends StatelessWidget {
  final String? message;
  final Color? accentColor;

  const LowerZoneLoadingState({
    super.key,
    this.message,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? LowerZoneColors.dawAccent;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeLabel,
                color: LowerZoneColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P1.1: DRAG-AND-DROP WIDGETS — File/Audio drag support
// ═══════════════════════════════════════════════════════════════════════════════

/// Data transferred during drag operations
class LowerZoneDragData {
  final String type; // 'audio', 'preset', 'event', 'plugin'
  final String path;
  final String name;
  final Map<String, dynamic>? metadata;

  const LowerZoneDragData({
    required this.type,
    required this.path,
    required this.name,
    this.metadata,
  });
}

/// Draggable item wrapper for lists
class LowerZoneDraggable extends StatelessWidget {
  final Widget child;
  final LowerZoneDragData data;
  final Widget? feedback;
  final Color? accentColor;

  const LowerZoneDraggable({
    super.key,
    required this.child,
    required this.data,
    this.feedback,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable<LowerZoneDragData>(
      data: data,
      feedback: feedback ?? _buildDefaultFeedback(),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );
  }

  Widget _buildDefaultFeedback() {
    final color = accentColor ?? LowerZoneColors.dawAccent;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForType(data.type),
              size: 16,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(
              data.name,
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeLabel,
                fontWeight: FontWeight.bold,
                color: LowerZoneColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'audio' => Icons.audio_file,
      'preset' => Icons.tune,
      'event' => Icons.music_note,
      'plugin' => Icons.extension,
      _ => Icons.insert_drive_file,
    };
  }
}

/// Drop target wrapper
class LowerZoneDropTarget extends StatefulWidget {
  final Widget child;
  final List<String> acceptedTypes; // e.g., ['audio', 'preset']
  final void Function(LowerZoneDragData data)? onAccept;
  final Color? accentColor;
  final String? hintText;

  const LowerZoneDropTarget({
    super.key,
    required this.child,
    required this.acceptedTypes,
    this.onAccept,
    this.accentColor,
    this.hintText,
  });

  @override
  State<LowerZoneDropTarget> createState() => _LowerZoneDropTargetState();
}

class _LowerZoneDropTargetState extends State<LowerZoneDropTarget> {
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor ?? LowerZoneColors.dawAccent;

    return DragTarget<LowerZoneDragData>(
      onWillAcceptWithDetails: (details) {
        final willAccept = widget.acceptedTypes.contains(details.data.type);
        if (willAccept && !_isDragOver) {
          setState(() => _isDragOver = true);
        }
        return willAccept;
      },
      onLeave: (_) {
        setState(() => _isDragOver = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _isDragOver = false);
        widget.onAccept?.call(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: _isDragOver
                ? Border.all(color: color, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
            color: _isDragOver
                ? color.withValues(alpha: 0.1)
                : Colors.transparent,
          ),
          child: Stack(
            children: [
              widget.child,
              if (_isDragOver && widget.hintText != null)
                Positioned.fill(
                  child: Container(
                    color: LowerZoneColors.bgDeep.withValues(alpha: 0.8),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_circle_outline, size: 32, color: color),
                          const SizedBox(height: 8),
                          Text(
                            widget.hintText!,
                            style: TextStyle(
                              fontSize: LowerZoneTypography.sizeLabel,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P1.3: CONTEXT MENU WIDGET — Right-click menu support
// ═══════════════════════════════════════════════════════════════════════════════

/// Context menu action
class LowerZoneContextAction {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool isDividerBefore;

  const LowerZoneContextAction({
    required this.label,
    required this.icon,
    this.onTap,
    this.isDestructive = false,
    this.isDividerBefore = false,
  });
}

/// Wrapper that shows context menu on right-click
class LowerZoneContextMenu extends StatelessWidget {
  final Widget child;
  final List<LowerZoneContextAction> actions;
  final Color? accentColor;

  const LowerZoneContextMenu({
    super.key,
    required this.child,
    required this.actions,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition);
      },
      onLongPress: () {
        // For touch devices
        final box = context.findRenderObject() as RenderBox;
        final position = box.localToGlobal(Offset.zero);
        _showContextMenu(context, position + const Offset(20, 20));
      },
      child: child,
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final color = accentColor ?? LowerZoneColors.dawAccent;

    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: LowerZoneColors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: LowerZoneColors.border),
      ),
      items: actions.map((action) {
        return PopupMenuItem<void>(
          onTap: action.onTap,
          padding: EdgeInsets.zero,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: action.isDividerBefore
                ? const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: LowerZoneColors.border),
                    ),
                  )
                : null,
            child: Row(
              children: [
                Icon(
                  action.icon,
                  size: 16,
                  color: action.isDestructive
                      ? LowerZoneColors.error
                      : action.onTap != null
                          ? color
                          : LowerZoneColors.textMuted,
                ),
                const SizedBox(width: 10),
                Text(
                  action.label,
                  style: TextStyle(
                    fontSize: LowerZoneTypography.sizeLabel,
                    color: action.isDestructive
                        ? LowerZoneColors.error
                        : action.onTap != null
                            ? LowerZoneColors.textPrimary
                            : LowerZoneColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Pre-defined context menu actions
class LowerZoneContextActions {
  /// Audio file context menu
  static List<LowerZoneContextAction> forAudioFile({
    VoidCallback? onPlay,
    VoidCallback? onAddToTimeline,
    VoidCallback? onAddToEvent,
    VoidCallback? onShowInFinder,
    VoidCallback? onDelete,
  }) => [
    LowerZoneContextAction(label: 'Play', icon: Icons.play_arrow, onTap: onPlay),
    LowerZoneContextAction(label: 'Add to Timeline', icon: Icons.add_to_queue, onTap: onAddToTimeline),
    LowerZoneContextAction(label: 'Add to Event', icon: Icons.music_note, onTap: onAddToEvent),
    LowerZoneContextAction(label: 'Show in Finder', icon: Icons.folder_open, onTap: onShowInFinder, isDividerBefore: true),
    LowerZoneContextAction(label: 'Delete', icon: Icons.delete_outline, onTap: onDelete, isDestructive: true, isDividerBefore: true),
  ];

  /// Event context menu
  static List<LowerZoneContextAction> forEvent({
    VoidCallback? onPlay,
    VoidCallback? onEdit,
    VoidCallback? onDuplicate,
    VoidCallback? onDelete,
  }) => [
    LowerZoneContextAction(label: 'Play', icon: Icons.play_arrow, onTap: onPlay),
    LowerZoneContextAction(label: 'Edit', icon: Icons.edit, onTap: onEdit),
    LowerZoneContextAction(label: 'Duplicate', icon: Icons.copy, onTap: onDuplicate, isDividerBefore: true),
    LowerZoneContextAction(label: 'Delete', icon: Icons.delete_outline, onTap: onDelete, isDestructive: true, isDividerBefore: true),
  ];

  /// Container context menu
  static List<LowerZoneContextAction> forContainer({
    VoidCallback? onTest,
    VoidCallback? onEdit,
    VoidCallback? onDuplicate,
    VoidCallback? onExport,
    VoidCallback? onDelete,
  }) => [
    LowerZoneContextAction(label: 'Test', icon: Icons.play_arrow, onTap: onTest),
    LowerZoneContextAction(label: 'Edit', icon: Icons.edit, onTap: onEdit),
    LowerZoneContextAction(label: 'Duplicate', icon: Icons.copy, onTap: onDuplicate, isDividerBefore: true),
    LowerZoneContextAction(label: 'Export Preset', icon: Icons.upload, onTap: onExport),
    LowerZoneContextAction(label: 'Delete', icon: Icons.delete_outline, onTap: onDelete, isDestructive: true, isDividerBefore: true),
  ];
}
