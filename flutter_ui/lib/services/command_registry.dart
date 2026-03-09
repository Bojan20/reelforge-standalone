/// Command Registry — Central Command Database
///
/// Singleton registry of ALL available commands in FluxForge Studio.
/// Commands are registered at app startup and context-dependently at runtime.
/// Provides the data source for the Command Palette.
///
/// Categories follow Reaper/Cubase action list organization:
/// - File, Edit, View, Track, Transport, Mix, Automation, Tools, Navigate
library;

import 'package:flutter/material.dart';

/// Command category with display properties
enum PaletteCategory {
  file('File', Icons.folder_outlined, Color(0xFF5AA8FF)),
  edit('Edit', Icons.edit_outlined, Color(0xFFB080FF)),
  view('View', Icons.visibility_outlined, Color(0xFF50D8FF)),
  track('Track', Icons.queue_music, Color(0xFF50FF98)),
  transport('Transport', Icons.play_arrow_outlined, Color(0xFFFFE050)),
  mix('Mix', Icons.tune, Color(0xFFFF9850)),
  automation('Automation', Icons.auto_graph, Color(0xFFB080FF)),
  tools('Tools', Icons.build_outlined, Color(0xFF808088)),
  navigate('Navigate', Icons.explore_outlined, Color(0xFF50D8FF));

  final String label;
  final IconData icon;
  final Color color;

  const PaletteCategory(this.label, this.icon, this.color);
}

/// A registered command in the palette
class PaletteCommand {
  /// Unique identifier (e.g., 'file.save', 'transport.play')
  final String id;

  /// Display label
  final String label;

  /// Optional description
  final String? description;

  /// Category for grouping
  final PaletteCategory category;

  /// Display icon
  final IconData? icon;

  /// Keyboard shortcut display string
  final String? shortcut;

  /// Search keywords (additional to label)
  final List<String> keywords;

  /// Callback when executed
  final VoidCallback? onExecute;

  /// Whether this command is currently available
  final bool enabled;

  const PaletteCommand({
    required this.id,
    required this.label,
    this.description,
    required this.category,
    this.icon,
    this.shortcut,
    this.keywords = const [],
    this.onExecute,
    this.enabled = true,
  });

  /// Create a copy with a different callback
  PaletteCommand withCallback(VoidCallback callback) => PaletteCommand(
        id: id,
        label: label,
        description: description,
        category: category,
        icon: icon,
        shortcut: shortcut,
        keywords: keywords,
        onExecute: callback,
        enabled: enabled,
      );
}

/// Central command registry — singleton
class CommandRegistry {
  CommandRegistry._();
  static final CommandRegistry instance = CommandRegistry._();

  final Map<String, PaletteCommand> _commands = {};
  final List<String> _recentIds = [];
  static const int _maxRecent = 20;

  /// All registered commands
  List<PaletteCommand> get commands => _commands.values.toList();

  /// Number of registered commands
  int get count => _commands.length;

  /// Recently executed command IDs (most recent first)
  List<String> get recentIds => List.unmodifiable(_recentIds);

  /// Recently executed commands (most recent first)
  List<PaletteCommand> get recentCommands {
    final result = <PaletteCommand>[];
    for (final id in _recentIds) {
      final cmd = _commands[id];
      if (cmd != null) result.add(cmd);
    }
    return result;
  }

  /// Register a command
  void register(PaletteCommand command) {
    _commands[command.id] = command;
  }

  /// Register multiple commands
  void registerAll(List<PaletteCommand> commands) {
    for (final cmd in commands) {
      _commands[cmd.id] = cmd;
    }
  }

  /// Unregister a command
  void unregister(String id) {
    _commands.remove(id);
  }

  /// Get command by ID
  PaletteCommand? get(String id) => _commands[id];

  /// Execute a command by ID and record in history
  void execute(String id) {
    final cmd = _commands[id];
    if (cmd == null || !cmd.enabled || cmd.onExecute == null) return;
    cmd.onExecute!();
    _recordRecent(id);
  }

  /// Execute a command directly and record in history
  void executeCommand(PaletteCommand cmd) {
    if (!cmd.enabled || cmd.onExecute == null) return;
    cmd.onExecute!();
    _recordRecent(cmd.id);
  }

  void _recordRecent(String id) {
    _recentIds.remove(id);
    _recentIds.insert(0, id);
    if (_recentIds.length > _maxRecent) {
      _recentIds.removeLast();
    }
  }

  /// Get commands by category
  List<PaletteCommand> byCategory(PaletteCategory category) {
    return _commands.values
        .where((cmd) => cmd.category == category)
        .toList();
  }

  /// Remove all commands whose ID starts with [prefix]
  void clearByPrefix(String prefix) {
    _commands.removeWhere((id, _) => id.startsWith(prefix));
  }

  /// Clear all commands (for testing or re-registration)
  void clear() {
    _commands.clear();
  }

  /// Clear history
  void clearHistory() {
    _recentIds.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DEFAULT COMMAND REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register all standard DAW commands with provided callbacks
  void registerDawCommands({
    // File
    VoidCallback? onNewProject,
    VoidCallback? onOpenProject,
    VoidCallback? onSaveProject,
    VoidCallback? onSaveProjectAs,
    VoidCallback? onExportAudio,
    VoidCallback? onExportStems,
    VoidCallback? onImportAudio,
    VoidCallback? onImportJSON,
    VoidCallback? onExportJSON,
    VoidCallback? onBatchExport,
    VoidCallback? onBounceToFile,
    VoidCallback? onRenderInPlace,
    // Edit
    VoidCallback? onUndo,
    VoidCallback? onRedo,
    VoidCallback? onCut,
    VoidCallback? onCopy,
    VoidCallback? onPaste,
    VoidCallback? onDuplicate,
    VoidCallback? onDelete,
    VoidCallback? onSelectAll,
    VoidCallback? onDeselect,
    VoidCallback? onSplit,
    VoidCallback? onTrim,
    VoidCallback? onQuantize,
    VoidCallback? onNormalize,
    VoidCallback? onReverse,
    // View
    VoidCallback? onToggleMixer,
    VoidCallback? onToggleTimeline,
    VoidCallback? onToggleBrowser,
    VoidCallback? onToggleInspector,
    VoidCallback? onToggleLeftPanel,
    VoidCallback? onToggleRightPanel,
    VoidCallback? onToggleLowerPanel,
    VoidCallback? onZoomIn,
    VoidCallback? onZoomOut,
    VoidCallback? onZoomToFit,
    VoidCallback? onZoomToSelection,
    VoidCallback? onShowAudioPool,
    VoidCallback? onShowMarkers,
    VoidCallback? onShowMidiEditor,
    VoidCallback? onResetLayout,
    VoidCallback? onFullscreen,
    // Track
    VoidCallback? onAddAudioTrack,
    VoidCallback? onAddMidiTrack,
    VoidCallback? onAddBusTrack,
    VoidCallback? onDeleteTrack,
    VoidCallback? onDuplicateTrack,
    VoidCallback? onFreezeTrack,
    VoidCallback? onUnfreezeTrack,
    VoidCallback? onAddTrack,
    VoidCallback? onRemoveTrack,
    // Transport
    VoidCallback? onPlay,
    VoidCallback? onStop,
    VoidCallback? onRecord,
    VoidCallback? onToggleLoop,
    VoidCallback? onToggleMetronome,
    VoidCallback? onGoToStart,
    VoidCallback? onGoToEnd,
    VoidCallback? onGoToLeftLocator,
    VoidCallback? onGoToRightLocator,
    VoidCallback? onNudgeLeft,
    VoidCallback? onNudgeRight,
    VoidCallback? onToggleSnap,
    VoidCallback? onSetLoopFromSelection,
    // Mix
    VoidCallback? onSoloSelected,
    VoidCallback? onMuteSelected,
    VoidCallback? onClearAllSolo,
    VoidCallback? onClearAllMute,
    VoidCallback? onResetFaders,
    VoidCallback? onBypassAllInserts,
    // Automation
    VoidCallback? onToggleAutomationRead,
    VoidCallback? onToggleAutomationWrite,
    VoidCallback? onShowAllAutomation,
    VoidCallback? onHideAllAutomation,
    VoidCallback? onClearAutomation,
    // Tools
    VoidCallback? onOpenPreferences,
    VoidCallback? onOpenKeyboardShortcuts,
    VoidCallback? onOpenAudioSettings,
    VoidCallback? onOpenMidiSettings,
    VoidCallback? onPluginManager,
    VoidCallback? onRefreshPlugins,
    VoidCallback? onProjectSettings,
    VoidCallback? onValidateProject,
    VoidCallback? onBuildProject,
    // Navigate
    VoidCallback? onCommandPalette,
    VoidCallback? onShowKeyboardShortcutsOverlay,
    // Advanced
    VoidCallback? onFadeIn,
    VoidCallback? onFadeOut,
    VoidCallback? onCrossfade,
    VoidCallback? onShowLogicalEditor,
    VoidCallback? onShowScaleAssistant,
    VoidCallback? onShowGrooveQuantize,
    VoidCallback? onShowAudioAlignment,
    VoidCallback? onShowTrackVersions,
    VoidCallback? onShowAutoColorRules,
    VoidCallback? onShowDynamicSplit,
    VoidCallback? onShowUcsNaming,
    VoidCallback? onShowStemManager,
    VoidCallback? onShowLoudnessReport,
    VoidCallback? onShowCycleActions,
    VoidCallback? onShowRegionPlaylist,
    VoidCallback? onShowMarkerActions,
    VoidCallback? onShowMacroControls,
    VoidCallback? onShowClipGainEnvelope,
  }) {
    registerAll([
      // ─── FILE ─────────────────────────────────────────────────────────────
      PaletteCommand(
        id: 'file.new',
        label: 'New Project',
        description: 'Create a new empty project',
        category: PaletteCategory.file,
        icon: Icons.add_box_outlined,
        shortcut: '⌘N',
        keywords: ['new', 'create', 'project', 'file'],
        onExecute: onNewProject,
      ),
      PaletteCommand(
        id: 'file.open',
        label: 'Open Project',
        description: 'Open an existing project',
        category: PaletteCategory.file,
        icon: Icons.folder_open_outlined,
        shortcut: '⌘O',
        keywords: ['open', 'load', 'project', 'file', 'browse'],
        onExecute: onOpenProject,
      ),
      PaletteCommand(
        id: 'file.save',
        label: 'Save Project',
        description: 'Save current project',
        category: PaletteCategory.file,
        icon: Icons.save_outlined,
        shortcut: '⌘S',
        keywords: ['save', 'project', 'file', 'write'],
        onExecute: onSaveProject,
      ),
      PaletteCommand(
        id: 'file.save_as',
        label: 'Save Project As...',
        description: 'Save project with new name',
        category: PaletteCategory.file,
        icon: Icons.save_as_outlined,
        shortcut: '⌘⇧S',
        keywords: ['save', 'as', 'project', 'copy', 'rename'],
        onExecute: onSaveProjectAs,
      ),
      PaletteCommand(
        id: 'file.export_audio',
        label: 'Export Audio',
        description: 'Bounce to audio file (WAV/MP3/FLAC)',
        category: PaletteCategory.file,
        icon: Icons.file_download_outlined,
        shortcut: '⌘⇧E',
        keywords: ['export', 'bounce', 'render', 'wav', 'mp3', 'flac', 'mixdown'],
        onExecute: onExportAudio,
      ),
      PaletteCommand(
        id: 'file.export_stems',
        label: 'Export Stems',
        description: 'Export individual track stems',
        category: PaletteCategory.file,
        icon: Icons.file_download_outlined,
        keywords: ['export', 'stems', 'tracks', 'separate', 'multi'],
        onExecute: onExportStems,
      ),
      PaletteCommand(
        id: 'file.import_audio',
        label: 'Import Audio',
        description: 'Import audio files into project',
        category: PaletteCategory.file,
        icon: Icons.file_upload_outlined,
        shortcut: '⌘⇧I',
        keywords: ['import', 'audio', 'file', 'add', 'wav', 'mp3'],
        onExecute: onImportAudio,
      ),
      PaletteCommand(
        id: 'file.import_json',
        label: 'Import JSON',
        description: 'Import project data from JSON',
        category: PaletteCategory.file,
        icon: Icons.data_object,
        shortcut: '⌘I',
        keywords: ['import', 'json', 'data', 'config'],
        onExecute: onImportJSON,
      ),
      PaletteCommand(
        id: 'file.export_json',
        label: 'Export JSON',
        description: 'Export project data to JSON',
        category: PaletteCategory.file,
        icon: Icons.data_object,
        keywords: ['export', 'json', 'data', 'backup'],
        onExecute: onExportJSON,
      ),
      PaletteCommand(
        id: 'file.batch_export',
        label: 'Batch Export',
        description: 'Export multiple regions/stems at once',
        category: PaletteCategory.file,
        icon: Icons.dynamic_feed,
        shortcut: '⇧⌥E',
        keywords: ['batch', 'export', 'multiple', 'regions', 'bulk'],
        onExecute: onBatchExport,
      ),
      PaletteCommand(
        id: 'file.bounce_to_file',
        label: 'Bounce to File',
        description: 'Bounce selection to audio file',
        category: PaletteCategory.file,
        icon: Icons.compress,
        shortcut: '⌥B',
        keywords: ['bounce', 'file', 'render', 'offline'],
        onExecute: onBounceToFile,
      ),
      PaletteCommand(
        id: 'file.render_in_place',
        label: 'Render in Place',
        description: 'Render track with effects in place',
        category: PaletteCategory.file,
        icon: Icons.layers,
        shortcut: '⌥R',
        keywords: ['render', 'place', 'freeze', 'commit', 'print'],
        onExecute: onRenderInPlace,
      ),

      // ─── EDIT ─────────────────────────────────────────────────────────────
      PaletteCommand(
        id: 'edit.undo',
        label: 'Undo',
        description: 'Undo last action',
        category: PaletteCategory.edit,
        icon: Icons.undo,
        shortcut: '⌘Z',
        keywords: ['undo', 'back', 'revert'],
        onExecute: onUndo,
      ),
      PaletteCommand(
        id: 'edit.redo',
        label: 'Redo',
        description: 'Redo last undone action',
        category: PaletteCategory.edit,
        icon: Icons.redo,
        shortcut: '⌘⇧Z',
        keywords: ['redo', 'forward'],
        onExecute: onRedo,
      ),
      PaletteCommand(
        id: 'edit.cut',
        label: 'Cut',
        description: 'Cut selected items',
        category: PaletteCategory.edit,
        icon: Icons.content_cut,
        shortcut: '⌘X',
        keywords: ['cut', 'remove', 'move'],
        onExecute: onCut,
      ),
      PaletteCommand(
        id: 'edit.copy',
        label: 'Copy',
        description: 'Copy selected items',
        category: PaletteCategory.edit,
        icon: Icons.content_copy,
        shortcut: '⌘C',
        keywords: ['copy', 'clipboard'],
        onExecute: onCopy,
      ),
      PaletteCommand(
        id: 'edit.paste',
        label: 'Paste',
        description: 'Paste from clipboard',
        category: PaletteCategory.edit,
        icon: Icons.content_paste,
        shortcut: '⌘V',
        keywords: ['paste', 'insert', 'clipboard'],
        onExecute: onPaste,
      ),
      PaletteCommand(
        id: 'edit.duplicate',
        label: 'Duplicate',
        description: 'Duplicate selected items',
        category: PaletteCategory.edit,
        icon: Icons.copy_all,
        shortcut: '⌘D',
        keywords: ['duplicate', 'copy', 'clone', 'repeat'],
        onExecute: onDuplicate,
      ),
      PaletteCommand(
        id: 'edit.delete',
        label: 'Delete',
        description: 'Delete selected items',
        category: PaletteCategory.edit,
        icon: Icons.delete_outline,
        shortcut: '⌫',
        keywords: ['delete', 'remove', 'clear', 'erase'],
        onExecute: onDelete,
      ),
      PaletteCommand(
        id: 'edit.select_all',
        label: 'Select All',
        description: 'Select all items',
        category: PaletteCategory.edit,
        icon: Icons.select_all,
        shortcut: '⌘A',
        keywords: ['select', 'all', 'everything'],
        onExecute: onSelectAll,
      ),
      PaletteCommand(
        id: 'edit.deselect',
        label: 'Deselect All',
        description: 'Clear selection',
        category: PaletteCategory.edit,
        icon: Icons.deselect,
        shortcut: 'Esc',
        keywords: ['deselect', 'clear', 'none'],
        onExecute: onDeselect,
      ),
      PaletteCommand(
        id: 'edit.split',
        label: 'Split at Cursor',
        description: 'Split clip at cursor position',
        category: PaletteCategory.edit,
        icon: Icons.vertical_split,
        shortcut: 'S',
        keywords: ['split', 'cut', 'divide', 'slice', 'razor'],
        onExecute: onSplit,
      ),
      PaletteCommand(
        id: 'edit.trim',
        label: 'Trim',
        description: 'Trim clip edges',
        category: PaletteCategory.edit,
        icon: Icons.content_cut_outlined,
        shortcut: 'T',
        keywords: ['trim', 'crop', 'edge', 'resize'],
        onExecute: onTrim,
      ),
      PaletteCommand(
        id: 'edit.quantize',
        label: 'Quantize',
        description: 'Snap to grid',
        category: PaletteCategory.edit,
        icon: Icons.grid_3x3,
        shortcut: 'Q',
        keywords: ['quantize', 'snap', 'grid', 'align'],
        onExecute: onQuantize,
      ),
      PaletteCommand(
        id: 'edit.normalize',
        label: 'Normalize',
        description: 'Normalize audio to peak level',
        category: PaletteCategory.edit,
        icon: Icons.equalizer,
        shortcut: '⌘⇧N',
        keywords: ['normalize', 'level', 'peak', 'gain', 'loudness'],
        onExecute: onNormalize,
      ),
      PaletteCommand(
        id: 'edit.reverse',
        label: 'Reverse',
        description: 'Reverse audio selection',
        category: PaletteCategory.edit,
        icon: Icons.swap_horiz,
        shortcut: '⌘⇧R',
        keywords: ['reverse', 'backwards', 'flip'],
        onExecute: onReverse,
      ),
      PaletteCommand(
        id: 'edit.fade_in',
        label: 'Fade In',
        description: 'Apply fade in to selection',
        category: PaletteCategory.edit,
        icon: Icons.trending_up,
        shortcut: 'F',
        keywords: ['fade', 'in', 'volume', 'ramp'],
        onExecute: onFadeIn,
      ),
      PaletteCommand(
        id: 'edit.fade_out',
        label: 'Fade Out',
        description: 'Apply fade out to selection',
        category: PaletteCategory.edit,
        icon: Icons.trending_down,
        shortcut: '⇧F',
        keywords: ['fade', 'out', 'volume', 'ramp'],
        onExecute: onFadeOut,
      ),
      PaletteCommand(
        id: 'edit.crossfade',
        label: 'Crossfade',
        description: 'Create crossfade between clips',
        category: PaletteCategory.edit,
        icon: Icons.compare_arrows,
        shortcut: 'X',
        keywords: ['crossfade', 'transition', 'blend', 'overlap'],
        onExecute: onCrossfade,
      ),

      // ─── VIEW ─────────────────────────────────────────────────────────────
      PaletteCommand(
        id: 'view.toggle_mixer',
        label: 'Toggle Mixer',
        description: 'Show/hide mixer panel',
        category: PaletteCategory.view,
        icon: Icons.tune,
        shortcut: 'F3',
        keywords: ['mixer', 'fader', 'console', 'mix'],
        onExecute: onToggleMixer,
      ),
      PaletteCommand(
        id: 'view.toggle_timeline',
        label: 'Toggle Timeline',
        description: 'Show/hide timeline panel',
        category: PaletteCategory.view,
        icon: Icons.view_timeline,
        keywords: ['timeline', 'arrangement', 'sequencer'],
        onExecute: onToggleTimeline,
      ),
      PaletteCommand(
        id: 'view.toggle_browser',
        label: 'Toggle Browser',
        description: 'Show/hide file browser',
        category: PaletteCategory.view,
        icon: Icons.folder_outlined,
        shortcut: 'B',
        keywords: ['browser', 'files', 'media', 'finder'],
        onExecute: onToggleBrowser,
      ),
      PaletteCommand(
        id: 'view.toggle_inspector',
        label: 'Toggle Inspector',
        description: 'Show/hide inspector panel',
        category: PaletteCategory.view,
        icon: Icons.info_outline,
        shortcut: 'I',
        keywords: ['inspector', 'properties', 'details', 'info'],
        onExecute: onToggleInspector,
      ),
      PaletteCommand(
        id: 'view.toggle_left',
        label: 'Toggle Left Panel',
        description: 'Show/hide left panel',
        category: PaletteCategory.view,
        icon: Icons.vertical_split,
        shortcut: '⌘L',
        keywords: ['left', 'panel', 'sidebar'],
        onExecute: onToggleLeftPanel,
      ),
      PaletteCommand(
        id: 'view.toggle_right',
        label: 'Toggle Right Panel',
        description: 'Show/hide right panel',
        category: PaletteCategory.view,
        icon: Icons.vertical_split,
        shortcut: '⌘R',
        keywords: ['right', 'panel', 'sidebar'],
        onExecute: onToggleRightPanel,
      ),
      PaletteCommand(
        id: 'view.toggle_lower',
        label: 'Toggle Lower Zone',
        description: 'Show/hide lower zone',
        category: PaletteCategory.view,
        icon: Icons.horizontal_split,
        shortcut: '⌘B',
        keywords: ['lower', 'zone', 'bottom', 'panel'],
        onExecute: onToggleLowerPanel,
      ),
      PaletteCommand(
        id: 'view.zoom_in',
        label: 'Zoom In',
        description: 'Zoom in on timeline',
        category: PaletteCategory.view,
        icon: Icons.zoom_in,
        shortcut: 'H',
        keywords: ['zoom', 'in', 'magnify', 'bigger'],
        onExecute: onZoomIn,
      ),
      PaletteCommand(
        id: 'view.zoom_out',
        label: 'Zoom Out',
        description: 'Zoom out on timeline',
        category: PaletteCategory.view,
        icon: Icons.zoom_out,
        shortcut: 'G',
        keywords: ['zoom', 'out', 'smaller'],
        onExecute: onZoomOut,
      ),
      PaletteCommand(
        id: 'view.zoom_to_fit',
        label: 'Zoom to Fit',
        description: 'Fit all content in view',
        category: PaletteCategory.view,
        icon: Icons.fit_screen,
        shortcut: '⌘0',
        keywords: ['zoom', 'fit', 'all', 'overview'],
        onExecute: onZoomToFit,
      ),
      PaletteCommand(
        id: 'view.zoom_to_selection',
        label: 'Zoom to Selection',
        description: 'Zoom to selected region',
        category: PaletteCategory.view,
        icon: Icons.crop_free,
        shortcut: 'Z',
        keywords: ['zoom', 'selection', 'focus'],
        onExecute: onZoomToSelection,
      ),
      PaletteCommand(
        id: 'view.audio_pool',
        label: 'Show Audio Pool',
        description: 'Open audio pool browser',
        category: PaletteCategory.view,
        icon: Icons.library_music,
        shortcut: '⌥P',
        keywords: ['audio', 'pool', 'media', 'library'],
        onExecute: onShowAudioPool,
      ),
      PaletteCommand(
        id: 'view.markers',
        label: 'Show Markers',
        description: 'Open marker list',
        category: PaletteCategory.view,
        icon: Icons.bookmark_border,
        shortcut: '⌥M',
        keywords: ['markers', 'regions', 'bookmarks'],
        onExecute: onShowMarkers,
      ),
      PaletteCommand(
        id: 'view.midi_editor',
        label: 'Show MIDI Editor',
        description: 'Open MIDI/Piano Roll editor',
        category: PaletteCategory.view,
        icon: Icons.piano,
        shortcut: '⌥E',
        keywords: ['midi', 'editor', 'piano', 'roll', 'notes'],
        onExecute: onShowMidiEditor,
      ),
      PaletteCommand(
        id: 'view.reset_layout',
        label: 'Reset Layout',
        description: 'Reset all panels to default positions',
        category: PaletteCategory.view,
        icon: Icons.dashboard_customize,
        keywords: ['reset', 'layout', 'default', 'restore'],
        onExecute: onResetLayout,
      ),
      PaletteCommand(
        id: 'view.fullscreen',
        label: 'Toggle Fullscreen',
        description: 'Enter/exit fullscreen mode',
        category: PaletteCategory.view,
        icon: Icons.fullscreen,
        shortcut: 'F11',
        keywords: ['fullscreen', 'maximize', 'full'],
        onExecute: onFullscreen,
      ),

      // ─── TRACK ────────────────────────────────────────────────────────────
      PaletteCommand(
        id: 'track.add_audio',
        label: 'Add Audio Track',
        description: 'Create new audio track',
        category: PaletteCategory.track,
        icon: Icons.graphic_eq,
        shortcut: '⌘T',
        keywords: ['add', 'track', 'audio', 'new', 'create'],
        onExecute: onAddAudioTrack ?? onAddTrack,
      ),
      PaletteCommand(
        id: 'track.add_midi',
        label: 'Add MIDI Track',
        description: 'Create new MIDI/instrument track',
        category: PaletteCategory.track,
        icon: Icons.piano,
        keywords: ['add', 'track', 'midi', 'instrument', 'new'],
        onExecute: onAddMidiTrack,
      ),
      PaletteCommand(
        id: 'track.add_bus',
        label: 'Add Bus Track',
        description: 'Create new bus/group track',
        category: PaletteCategory.track,
        icon: Icons.call_split,
        keywords: ['add', 'track', 'bus', 'group', 'submix', 'aux'],
        onExecute: onAddBusTrack,
      ),
      PaletteCommand(
        id: 'track.delete',
        label: 'Delete Track',
        description: 'Delete selected track',
        category: PaletteCategory.track,
        icon: Icons.delete_outline,
        shortcut: '⌘⇧T',
        keywords: ['delete', 'remove', 'track'],
        onExecute: onDeleteTrack ?? onRemoveTrack,
      ),
      PaletteCommand(
        id: 'track.duplicate',
        label: 'Duplicate Track',
        description: 'Duplicate selected track with content',
        category: PaletteCategory.track,
        icon: Icons.copy_all,
        keywords: ['duplicate', 'copy', 'track', 'clone'],
        onExecute: onDuplicateTrack,
      ),
      PaletteCommand(
        id: 'track.freeze',
        label: 'Freeze Track',
        description: 'Freeze selected track (render to audio)',
        category: PaletteCategory.track,
        icon: Icons.ac_unit,
        shortcut: '⌥F',
        keywords: ['freeze', 'render', 'bounce', 'offline'],
        onExecute: onFreezeTrack,
      ),
      PaletteCommand(
        id: 'track.unfreeze',
        label: 'Unfreeze Track',
        description: 'Unfreeze selected track',
        category: PaletteCategory.track,
        icon: Icons.whatshot_outlined,
        keywords: ['unfreeze', 'thaw', 'restore'],
        onExecute: onUnfreezeTrack,
      ),

      // ─── TRANSPORT ────────────────────────────────────────────────────────
      PaletteCommand(
        id: 'transport.play',
        label: 'Play / Pause',
        description: 'Toggle playback',
        category: PaletteCategory.transport,
        icon: Icons.play_arrow,
        shortcut: 'Space',
        keywords: ['play', 'pause', 'start', 'playback'],
        onExecute: onPlay,
      ),
      PaletteCommand(
        id: 'transport.stop',
        label: 'Stop',
        description: 'Stop playback and return to start',
        category: PaletteCategory.transport,
        icon: Icons.stop,
        shortcut: '.',
        keywords: ['stop', 'halt'],
        onExecute: onStop,
      ),
      PaletteCommand(
        id: 'transport.record',
        label: 'Record',
        description: 'Start/stop recording',
        category: PaletteCategory.transport,
        icon: Icons.fiber_manual_record,
        shortcut: 'R',
        keywords: ['record', 'rec', 'arm'],
        onExecute: onRecord,
      ),
      PaletteCommand(
        id: 'transport.toggle_loop',
        label: 'Toggle Loop',
        description: 'Enable/disable loop playback',
        category: PaletteCategory.transport,
        icon: Icons.loop,
        shortcut: 'L',
        keywords: ['loop', 'cycle', 'repeat'],
        onExecute: onToggleLoop,
      ),
      PaletteCommand(
        id: 'transport.toggle_metronome',
        label: 'Toggle Metronome',
        description: 'Turn metronome click on/off',
        category: PaletteCategory.transport,
        icon: Icons.timer,
        shortcut: 'K',
        keywords: ['metronome', 'click', 'tempo', 'beat'],
        onExecute: onToggleMetronome,
      ),
      PaletteCommand(
        id: 'transport.toggle_snap',
        label: 'Toggle Snap',
        description: 'Turn grid snap on/off',
        category: PaletteCategory.transport,
        icon: Icons.grid_on,
        shortcut: 'N',
        keywords: ['snap', 'grid', 'quantize', 'magnetic'],
        onExecute: onToggleSnap,
      ),

      // ─── NAVIGATE ─────────────────────────────────────────────────────────
      PaletteCommand(
        id: 'navigate.go_to_start',
        label: 'Go to Start',
        description: 'Jump to project start',
        category: PaletteCategory.navigate,
        icon: Icons.first_page,
        shortcut: 'Home',
        keywords: ['start', 'beginning', 'home', 'rewind'],
        onExecute: onGoToStart,
      ),
      PaletteCommand(
        id: 'navigate.go_to_end',
        label: 'Go to End',
        description: 'Jump to project end',
        category: PaletteCategory.navigate,
        icon: Icons.last_page,
        shortcut: 'End',
        keywords: ['end', 'finish', 'last'],
        onExecute: onGoToEnd,
      ),
      PaletteCommand(
        id: 'navigate.left_locator',
        label: 'Go to Left Locator',
        description: 'Jump to left locator position',
        category: PaletteCategory.navigate,
        icon: Icons.skip_previous,
        shortcut: '1',
        keywords: ['left', 'locator', 'start', 'punch'],
        onExecute: onGoToLeftLocator,
      ),
      PaletteCommand(
        id: 'navigate.right_locator',
        label: 'Go to Right Locator',
        description: 'Jump to right locator position',
        category: PaletteCategory.navigate,
        icon: Icons.skip_next,
        shortcut: '2',
        keywords: ['right', 'locator', 'end', 'punch'],
        onExecute: onGoToRightLocator,
      ),
      PaletteCommand(
        id: 'navigate.nudge_left',
        label: 'Nudge Left',
        description: 'Move selection left by nudge amount',
        category: PaletteCategory.navigate,
        icon: Icons.arrow_back,
        shortcut: '←',
        keywords: ['nudge', 'left', 'move', 'shift'],
        onExecute: onNudgeLeft,
      ),
      PaletteCommand(
        id: 'navigate.nudge_right',
        label: 'Nudge Right',
        description: 'Move selection right by nudge amount',
        category: PaletteCategory.navigate,
        icon: Icons.arrow_forward,
        shortcut: '→',
        keywords: ['nudge', 'right', 'move', 'shift'],
        onExecute: onNudgeRight,
      ),
      PaletteCommand(
        id: 'navigate.set_loop_from_selection',
        label: 'Set Loop from Selection',
        description: 'Set loop region to match selection',
        category: PaletteCategory.navigate,
        icon: Icons.loop,
        shortcut: '⇧L',
        keywords: ['loop', 'selection', 'region', 'locators'],
        onExecute: onSetLoopFromSelection,
      ),
      PaletteCommand(
        id: 'navigate.command_palette',
        label: 'Command Palette',
        description: 'Open command palette',
        category: PaletteCategory.navigate,
        icon: Icons.terminal,
        shortcut: '⌘K',
        keywords: ['command', 'palette', 'search', 'action', 'quick'],
        onExecute: onCommandPalette,
      ),
      PaletteCommand(
        id: 'navigate.keyboard_shortcuts',
        label: 'Show Keyboard Shortcuts',
        description: 'Display keyboard shortcut overlay',
        category: PaletteCategory.navigate,
        icon: Icons.keyboard,
        shortcut: '?',
        keywords: ['keyboard', 'shortcuts', 'keys', 'hotkeys', 'help'],
        onExecute: onShowKeyboardShortcutsOverlay,
      ),

      // ─── MIX ──────────────────────────────────────────────────────────────
      PaletteCommand(
        id: 'mix.solo_selected',
        label: 'Solo Selected',
        description: 'Solo selected tracks',
        category: PaletteCategory.mix,
        icon: Icons.headphones,
        shortcut: '⌥S',
        keywords: ['solo', 'isolate', 'listen'],
        onExecute: onSoloSelected,
      ),
      PaletteCommand(
        id: 'mix.mute_selected',
        label: 'Mute Selected',
        description: 'Mute selected tracks',
        category: PaletteCategory.mix,
        icon: Icons.volume_off,
        shortcut: 'M',
        keywords: ['mute', 'silence', 'quiet'],
        onExecute: onMuteSelected,
      ),
      PaletteCommand(
        id: 'mix.clear_all_solo',
        label: 'Clear All Solo',
        description: 'Clear all solo states',
        category: PaletteCategory.mix,
        icon: Icons.hearing_disabled,
        keywords: ['clear', 'solo', 'all', 'unsolo'],
        onExecute: onClearAllSolo,
      ),
      PaletteCommand(
        id: 'mix.clear_all_mute',
        label: 'Clear All Mute',
        description: 'Clear all mute states',
        category: PaletteCategory.mix,
        icon: Icons.volume_up,
        keywords: ['clear', 'mute', 'all', 'unmute'],
        onExecute: onClearAllMute,
      ),
      PaletteCommand(
        id: 'mix.reset_faders',
        label: 'Reset All Faders',
        description: 'Reset all faders to 0 dB',
        category: PaletteCategory.mix,
        icon: Icons.restart_alt,
        keywords: ['reset', 'faders', 'unity', 'default', '0db'],
        onExecute: onResetFaders,
      ),
      PaletteCommand(
        id: 'mix.bypass_all_inserts',
        label: 'Bypass All Inserts',
        description: 'Bypass all insert effects',
        category: PaletteCategory.mix,
        icon: Icons.not_interested,
        keywords: ['bypass', 'inserts', 'effects', 'disable', 'all'],
        onExecute: onBypassAllInserts,
      ),

      // ─── AUTOMATION ───────────────────────────────────────────────────────
      PaletteCommand(
        id: 'automation.toggle_read',
        label: 'Toggle Automation Read',
        description: 'Enable/disable reading automation',
        category: PaletteCategory.automation,
        icon: Icons.auto_graph,
        shortcut: 'A',
        keywords: ['automation', 'read', 'play', 'follow'],
        onExecute: onToggleAutomationRead,
      ),
      PaletteCommand(
        id: 'automation.toggle_write',
        label: 'Toggle Automation Write',
        description: 'Enable/disable writing automation',
        category: PaletteCategory.automation,
        icon: Icons.edit_note,
        shortcut: '⌘A',
        keywords: ['automation', 'write', 'record', 'draw'],
        onExecute: onToggleAutomationWrite,
      ),
      PaletteCommand(
        id: 'automation.show_all',
        label: 'Show All Automation',
        description: 'Show automation on all tracks',
        category: PaletteCategory.automation,
        icon: Icons.visibility,
        keywords: ['automation', 'show', 'all', 'reveal'],
        onExecute: onShowAllAutomation,
      ),
      PaletteCommand(
        id: 'automation.hide_all',
        label: 'Hide All Automation',
        description: 'Hide automation on all tracks',
        category: PaletteCategory.automation,
        icon: Icons.visibility_off,
        keywords: ['automation', 'hide', 'all', 'collapse'],
        onExecute: onHideAllAutomation,
      ),
      PaletteCommand(
        id: 'automation.clear',
        label: 'Clear Automation',
        description: 'Clear automation data for selection',
        category: PaletteCategory.automation,
        icon: Icons.delete_sweep,
        keywords: ['automation', 'clear', 'delete', 'remove'],
        onExecute: onClearAutomation,
      ),

      // ─── TOOLS ────────────────────────────────────────────────────────────
      PaletteCommand(
        id: 'tools.preferences',
        label: 'Preferences',
        description: 'Open application preferences',
        category: PaletteCategory.tools,
        icon: Icons.settings,
        shortcut: '⌘,',
        keywords: ['preferences', 'settings', 'options', 'config'],
        onExecute: onOpenPreferences,
      ),
      PaletteCommand(
        id: 'tools.keyboard_shortcuts',
        label: 'Keyboard Shortcuts Settings',
        description: 'Customize keyboard shortcuts',
        category: PaletteCategory.tools,
        icon: Icons.keyboard,
        shortcut: '⌥⌘K',
        keywords: ['keyboard', 'shortcuts', 'keys', 'customize', 'remap'],
        onExecute: onOpenKeyboardShortcuts,
      ),
      PaletteCommand(
        id: 'tools.audio_settings',
        label: 'Audio Settings',
        description: 'Configure audio interface and buffer',
        category: PaletteCategory.tools,
        icon: Icons.speaker,
        shortcut: '⌥⌘A',
        keywords: ['audio', 'settings', 'interface', 'buffer', 'asio', 'driver'],
        onExecute: onOpenAudioSettings,
      ),
      PaletteCommand(
        id: 'tools.midi_settings',
        label: 'MIDI Settings',
        description: 'Configure MIDI devices',
        category: PaletteCategory.tools,
        icon: Icons.piano,
        shortcut: '⌥⌘M',
        keywords: ['midi', 'settings', 'controller', 'device'],
        onExecute: onOpenMidiSettings,
      ),
      PaletteCommand(
        id: 'tools.plugin_manager',
        label: 'Plugin Manager',
        description: 'Manage VST/AU plugins',
        category: PaletteCategory.tools,
        icon: Icons.extension,
        shortcut: '⌥⌘P',
        keywords: ['plugin', 'manager', 'vst', 'au', 'scan'],
        onExecute: onPluginManager,
      ),
      PaletteCommand(
        id: 'tools.refresh_plugins',
        label: 'Refresh Plugins',
        description: 'Rescan plugin folders',
        category: PaletteCategory.tools,
        icon: Icons.refresh,
        keywords: ['refresh', 'plugins', 'rescan', 'reload'],
        onExecute: onRefreshPlugins,
      ),
      PaletteCommand(
        id: 'tools.project_settings',
        label: 'Project Settings',
        description: 'Sample rate, bit depth, tempo',
        category: PaletteCategory.tools,
        icon: Icons.settings_applications,
        keywords: ['project', 'settings', 'sample', 'rate', 'tempo', 'bpm'],
        onExecute: onProjectSettings,
      ),
      PaletteCommand(
        id: 'tools.validate_project',
        label: 'Validate Project',
        description: 'Check project for issues',
        category: PaletteCategory.tools,
        icon: Icons.verified,
        keywords: ['validate', 'check', 'verify', 'health'],
        onExecute: onValidateProject,
      ),
      PaletteCommand(
        id: 'tools.build_project',
        label: 'Build Project',
        description: 'Build and compile project',
        category: PaletteCategory.tools,
        icon: Icons.build,
        keywords: ['build', 'compile', 'make'],
        onExecute: onBuildProject,
      ),

      PaletteCommand(
        id: 'tools.auto_color_rules',
        label: 'Auto-Color Rules',
        description: 'Manage track auto-color rules (regex → color/icon)',
        category: PaletteCategory.tools,
        icon: Icons.palette,
        keywords: ['auto', 'color', 'rules', 'regex', 'pattern', 'track', 'palette'],
        onExecute: onShowAutoColorRules,
      ),
      PaletteCommand(
        id: 'tools.dynamic_split',
        label: 'Dynamic Split',
        description: 'Split clips by transients, gate threshold, or silence detection',
        category: PaletteCategory.tools,
        icon: Icons.call_split,
        keywords: ['dynamic', 'split', 'transient', 'gate', 'silence', 'detect', 'cut'],
        onExecute: onShowDynamicSplit,
      ),
      PaletteCommand(
        id: 'tools.ucs_naming',
        label: 'UCS Naming',
        description: 'Universal Category System naming for game audio assets',
        category: PaletteCategory.tools,
        icon: Icons.label,
        keywords: ['ucs', 'naming', 'category', 'rename', 'universal', 'game', 'audio', 'asset'],
        onExecute: onShowUcsNaming,
      ),
      PaletteCommand(
        id: 'tools.stem_manager',
        label: 'Stem Manager',
        description: 'Save/recall solo/mute configs for stem rendering',
        category: PaletteCategory.tools,
        icon: Icons.library_music,
        keywords: ['stem', 'manager', 'solo', 'mute', 'render', 'batch', 'export', 'config'],
        onExecute: onShowStemManager,
      ),
      PaletteCommand(
        id: 'tools.loudness_report',
        label: 'Loudness Report',
        description: 'LUFS analysis, True Peak, LRA, clipping detection, HTML report',
        category: PaletteCategory.tools,
        icon: Icons.assessment,
        keywords: ['loudness', 'report', 'lufs', 'peak', 'lra', 'clipping', 'analysis', 'html'],
        onExecute: onShowLoudnessReport,
      ),
      PaletteCommand(
        id: 'tools.cycle_actions',
        label: 'Cycle Actions',
        description: 'Sequential action cycling — each invocation executes the next step',
        category: PaletteCategory.tools,
        icon: Icons.replay,
        keywords: ['cycle', 'actions', 'sequential', 'step', 'macro', 'repeat'],
        onExecute: onShowCycleActions,
      ),
      PaletteCommand(
        id: 'tools.region_playlist',
        label: 'Region Playlist',
        description: 'Non-linear playback — define region order independently of timeline',
        category: PaletteCategory.tools,
        icon: Icons.playlist_play,
        keywords: ['region', 'playlist', 'non-linear', 'playback', 'order', 'sequence'],
        onExecute: onShowRegionPlaylist,
      ),
      PaletteCommand(
        id: 'tools.marker_actions',
        label: 'Marker Actions',
        description: 'Trigger actions when playhead crosses markers (!actionId in name)',
        category: PaletteCategory.tools,
        icon: Icons.bolt,
        keywords: ['marker', 'actions', 'trigger', 'playhead', 'crossing', 'timeline'],
        onExecute: onShowMarkerActions,
      ),

      // ─── ADVANCED PANELS ──────────────────────────────────────────────────
      PaletteCommand(
        id: 'tools.logical_editor',
        label: 'Logical Editor',
        description: 'Open logical editor for batch operations',
        category: PaletteCategory.tools,
        icon: Icons.rule,
        shortcut: '⇧⌘L',
        keywords: ['logical', 'editor', 'batch', 'filter', 'transform'],
        onExecute: onShowLogicalEditor,
      ),
      PaletteCommand(
        id: 'tools.scale_assistant',
        label: 'Scale Assistant',
        description: 'Show scale and chord helper',
        category: PaletteCategory.tools,
        icon: Icons.music_note,
        shortcut: '⇧⌘K',
        keywords: ['scale', 'assistant', 'chord', 'key', 'theory'],
        onExecute: onShowScaleAssistant,
      ),
      PaletteCommand(
        id: 'tools.groove_quantize',
        label: 'Groove Quantize',
        description: 'Apply groove quantize templates',
        category: PaletteCategory.tools,
        icon: Icons.waves,
        shortcut: '⇧⌘Q',
        keywords: ['groove', 'quantize', 'swing', 'feel', 'template'],
        onExecute: onShowGrooveQuantize,
      ),
      PaletteCommand(
        id: 'tools.audio_alignment',
        label: 'Audio Alignment',
        description: 'Align audio to reference',
        category: PaletteCategory.tools,
        icon: Icons.align_horizontal_left,
        shortcut: '⇧⌘A',
        keywords: ['audio', 'alignment', 'phase', 'sync', 'warp'],
        onExecute: onShowAudioAlignment,
      ),
      PaletteCommand(
        id: 'tools.track_versions',
        label: 'Track Versions',
        description: 'Manage track version history',
        category: PaletteCategory.tools,
        icon: Icons.history,
        shortcut: '⇧⌘V',
        keywords: ['track', 'versions', 'history', 'comping', 'takes'],
        onExecute: onShowTrackVersions,
      ),
      PaletteCommand(
        id: 'tools.macro_controls',
        label: 'Macro Controls',
        description: 'Open macro parameter controls',
        category: PaletteCategory.tools,
        icon: Icons.tune,
        shortcut: '⇧⌘M',
        keywords: ['macro', 'controls', 'parameters', 'knobs'],
        onExecute: onShowMacroControls,
      ),
      PaletteCommand(
        id: 'tools.clip_gain_envelope',
        label: 'Clip Gain Envelope',
        description: 'Edit clip gain envelope',
        category: PaletteCategory.tools,
        icon: Icons.timeline,
        shortcut: '⇧⌘G',
        keywords: ['clip', 'gain', 'envelope', 'volume', 'automation'],
        onExecute: onShowClipGainEnvelope,
      ),
    ]);
  }
}
