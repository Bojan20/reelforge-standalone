/// Quick Commands Service (P2-DAW-9)
///
/// Extended command palette commands for DAW:
/// - 20+ DAW-specific commands
/// - Categorized by function
/// - Keyboard shortcuts
///
/// Created: 2026-02-02
library;

import 'package:flutter/material.dart';
import '../widgets/common/command_palette.dart';

/// Command category for organization
enum CommandCategory {
  file('File', Icons.folder),
  edit('Edit', Icons.edit),
  view('View', Icons.visibility),
  track('Track', Icons.queue_music),
  transport('Transport', Icons.play_arrow),
  mix('Mix', Icons.tune),
  automation('Automation', Icons.timeline),
  tools('Tools', Icons.build);

  final String label;
  final IconData icon;

  const CommandCategory(this.label, this.icon);
}

/// Extended command with category
class DawCommand extends Command {
  final CommandCategory category;

  const DawCommand({
    required super.label,
    super.description,
    super.icon,
    required super.onExecute,
    super.keywords = const [],
    super.shortcut,
    required this.category,
  });
}

/// Quick commands service for DAW
class QuickCommandsService {
  QuickCommandsService._();

  /// Generate all DAW commands
  static List<Command> getDawCommands({
    // File
    VoidCallback? onNewProject,
    VoidCallback? onOpenProject,
    VoidCallback? onSaveProject,
    VoidCallback? onSaveProjectAs,
    VoidCallback? onExportAudio,
    VoidCallback? onExportStems,
    VoidCallback? onImportAudio,

    // Edit
    VoidCallback? onUndo,
    VoidCallback? onRedo,
    VoidCallback? onCut,
    VoidCallback? onCopy,
    VoidCallback? onPaste,
    VoidCallback? onDuplicate,
    VoidCallback? onDelete,
    VoidCallback? onSelectAll,

    // View
    VoidCallback? onToggleMixer,
    VoidCallback? onToggleTimeline,
    VoidCallback? onToggleBrowser,
    VoidCallback? onToggleInspector,
    VoidCallback? onToggleMeters,
    VoidCallback? onZoomIn,
    VoidCallback? onZoomOut,
    VoidCallback? onZoomToFit,
    VoidCallback? onZoomToSelection,

    // Track
    VoidCallback? onAddAudioTrack,
    VoidCallback? onAddMidiTrack,
    VoidCallback? onAddBusTrack,
    VoidCallback? onDeleteTrack,
    VoidCallback? onDuplicateTrack,
    VoidCallback? onFreezeTrack,
    VoidCallback? onUnfreezeTrack,
    VoidCallback? onShowTrackInspector,

    // Transport
    VoidCallback? onPlay,
    VoidCallback? onStop,
    VoidCallback? onRecord,
    VoidCallback? onToggleLoop,
    VoidCallback? onToggleMetronome,
    VoidCallback? onGoToStart,
    VoidCallback? onGoToEnd,
    VoidCallback? onGoToMarker,
    VoidCallback? onSetLocatorLeft,
    VoidCallback? onSetLocatorRight,

    // Mix
    VoidCallback? onSoloSelected,
    VoidCallback? onMuteSelected,
    VoidCallback? onClearAllSolo,
    VoidCallback? onClearAllMute,
    VoidCallback? onResetFaders,
    VoidCallback? onBypassAllInserts,
    VoidCallback? onTogglePanLaw,

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
    VoidCallback? onRefreshPlugins,
  }) {
    return [
      // ─── FILE ───────────────────────────────────────────────────────────────────
      if (onNewProject != null)
        DawCommand(
          label: 'New Project',
          description: 'Create a new empty project',
          icon: Icons.add_box,
          onExecute: onNewProject,
          keywords: ['new', 'create', 'project'],
          shortcut: '⌘N',
          category: CommandCategory.file,
        ),
      if (onOpenProject != null)
        DawCommand(
          label: 'Open Project',
          description: 'Open an existing project',
          icon: Icons.folder_open,
          onExecute: onOpenProject,
          keywords: ['open', 'load', 'project'],
          shortcut: '⌘O',
          category: CommandCategory.file,
        ),
      if (onSaveProject != null)
        DawCommand(
          label: 'Save Project',
          description: 'Save current project',
          icon: Icons.save,
          onExecute: onSaveProject,
          keywords: ['save', 'project'],
          shortcut: '⌘S',
          category: CommandCategory.file,
        ),
      if (onSaveProjectAs != null)
        DawCommand(
          label: 'Save Project As...',
          description: 'Save project with new name',
          icon: Icons.save_as,
          onExecute: onSaveProjectAs,
          keywords: ['save', 'as', 'project', 'copy'],
          shortcut: '⌘⇧S',
          category: CommandCategory.file,
        ),
      if (onExportAudio != null)
        DawCommand(
          label: 'Export Audio',
          description: 'Bounce to audio file',
          icon: Icons.file_download,
          onExecute: onExportAudio,
          keywords: ['export', 'bounce', 'render', 'wav', 'mp3'],
          shortcut: '⌘⇧E',
          category: CommandCategory.file,
        ),
      if (onExportStems != null)
        DawCommand(
          label: 'Export Stems',
          description: 'Export individual track stems',
          icon: Icons.file_download_outlined,
          onExecute: onExportStems,
          keywords: ['export', 'stems', 'tracks', 'separate'],
          category: CommandCategory.file,
        ),
      if (onImportAudio != null)
        DawCommand(
          label: 'Import Audio',
          description: 'Import audio files',
          icon: Icons.file_upload,
          onExecute: onImportAudio,
          keywords: ['import', 'audio', 'file', 'add'],
          shortcut: '⌘I',
          category: CommandCategory.file,
        ),

      // ─── EDIT ───────────────────────────────────────────────────────────────────
      if (onUndo != null)
        DawCommand(
          label: 'Undo',
          description: 'Undo last action',
          icon: Icons.undo,
          onExecute: onUndo,
          keywords: ['undo', 'back'],
          shortcut: '⌘Z',
          category: CommandCategory.edit,
        ),
      if (onRedo != null)
        DawCommand(
          label: 'Redo',
          description: 'Redo last undone action',
          icon: Icons.redo,
          onExecute: onRedo,
          keywords: ['redo', 'forward'],
          shortcut: '⌘⇧Z',
          category: CommandCategory.edit,
        ),
      if (onCut != null)
        DawCommand(
          label: 'Cut',
          description: 'Cut selected items',
          icon: Icons.content_cut,
          onExecute: onCut,
          keywords: ['cut', 'remove'],
          shortcut: '⌘X',
          category: CommandCategory.edit,
        ),
      if (onCopy != null)
        DawCommand(
          label: 'Copy',
          description: 'Copy selected items',
          icon: Icons.content_copy,
          onExecute: onCopy,
          keywords: ['copy', 'duplicate'],
          shortcut: '⌘C',
          category: CommandCategory.edit,
        ),
      if (onPaste != null)
        DawCommand(
          label: 'Paste',
          description: 'Paste from clipboard',
          icon: Icons.content_paste,
          onExecute: onPaste,
          keywords: ['paste', 'insert'],
          shortcut: '⌘V',
          category: CommandCategory.edit,
        ),
      if (onDuplicate != null)
        DawCommand(
          label: 'Duplicate',
          description: 'Duplicate selected items',
          icon: Icons.copy_all,
          onExecute: onDuplicate,
          keywords: ['duplicate', 'copy', 'clone'],
          shortcut: '⌘D',
          category: CommandCategory.edit,
        ),
      if (onDelete != null)
        DawCommand(
          label: 'Delete',
          description: 'Delete selected items',
          icon: Icons.delete,
          onExecute: onDelete,
          keywords: ['delete', 'remove', 'clear'],
          shortcut: '⌫',
          category: CommandCategory.edit,
        ),
      if (onSelectAll != null)
        DawCommand(
          label: 'Select All',
          description: 'Select all items',
          icon: Icons.select_all,
          onExecute: onSelectAll,
          keywords: ['select', 'all'],
          shortcut: '⌘A',
          category: CommandCategory.edit,
        ),

      // ─── VIEW ───────────────────────────────────────────────────────────────────
      if (onToggleMixer != null)
        DawCommand(
          label: 'Toggle Mixer',
          description: 'Show/hide mixer panel',
          icon: Icons.tune,
          onExecute: onToggleMixer,
          keywords: ['mixer', 'fader', 'console'],
          shortcut: 'M',
          category: CommandCategory.view,
        ),
      if (onToggleTimeline != null)
        DawCommand(
          label: 'Toggle Timeline',
          description: 'Show/hide timeline panel',
          icon: Icons.view_timeline,
          onExecute: onToggleTimeline,
          keywords: ['timeline', 'arrangement'],
          shortcut: 'T',
          category: CommandCategory.view,
        ),
      if (onToggleBrowser != null)
        DawCommand(
          label: 'Toggle Browser',
          description: 'Show/hide file browser',
          icon: Icons.folder,
          onExecute: onToggleBrowser,
          keywords: ['browser', 'files', 'media'],
          shortcut: 'B',
          category: CommandCategory.view,
        ),
      if (onZoomIn != null)
        DawCommand(
          label: 'Zoom In',
          description: 'Zoom in on timeline',
          icon: Icons.zoom_in,
          onExecute: onZoomIn,
          keywords: ['zoom', 'in', 'magnify'],
          shortcut: '⌘+',
          category: CommandCategory.view,
        ),
      if (onZoomOut != null)
        DawCommand(
          label: 'Zoom Out',
          description: 'Zoom out on timeline',
          icon: Icons.zoom_out,
          onExecute: onZoomOut,
          keywords: ['zoom', 'out'],
          shortcut: '⌘-',
          category: CommandCategory.view,
        ),
      if (onZoomToFit != null)
        DawCommand(
          label: 'Zoom to Fit',
          description: 'Fit all content in view',
          icon: Icons.fit_screen,
          onExecute: onZoomToFit,
          keywords: ['zoom', 'fit', 'all'],
          shortcut: 'F',
          category: CommandCategory.view,
        ),

      // ─── TRACK ──────────────────────────────────────────────────────────────────
      if (onAddAudioTrack != null)
        DawCommand(
          label: 'Add Audio Track',
          description: 'Create new audio track',
          icon: Icons.add,
          onExecute: onAddAudioTrack,
          keywords: ['add', 'track', 'audio', 'new'],
          shortcut: '⌘⇧T',
          category: CommandCategory.track,
        ),
      if (onAddMidiTrack != null)
        DawCommand(
          label: 'Add MIDI Track',
          description: 'Create new MIDI track',
          icon: Icons.piano,
          onExecute: onAddMidiTrack,
          keywords: ['add', 'track', 'midi', 'new'],
          category: CommandCategory.track,
        ),
      if (onAddBusTrack != null)
        DawCommand(
          label: 'Add Bus Track',
          description: 'Create new bus track',
          icon: Icons.merge_type,
          onExecute: onAddBusTrack,
          keywords: ['add', 'track', 'bus', 'group', 'new'],
          category: CommandCategory.track,
        ),
      if (onFreezeTrack != null)
        DawCommand(
          label: 'Freeze Track',
          description: 'Freeze selected track',
          icon: Icons.ac_unit,
          onExecute: onFreezeTrack,
          keywords: ['freeze', 'render', 'bounce'],
          category: CommandCategory.track,
        ),

      // ─── TRANSPORT ──────────────────────────────────────────────────────────────
      if (onPlay != null)
        DawCommand(
          label: 'Play/Pause',
          description: 'Toggle playback',
          icon: Icons.play_arrow,
          onExecute: onPlay,
          keywords: ['play', 'pause', 'start', 'stop'],
          shortcut: 'Space',
          category: CommandCategory.transport,
        ),
      if (onRecord != null)
        DawCommand(
          label: 'Record',
          description: 'Start recording',
          icon: Icons.fiber_manual_record,
          onExecute: onRecord,
          keywords: ['record', 'rec'],
          shortcut: 'R',
          category: CommandCategory.transport,
        ),
      if (onToggleLoop != null)
        DawCommand(
          label: 'Toggle Loop',
          description: 'Enable/disable loop playback',
          icon: Icons.loop,
          onExecute: onToggleLoop,
          keywords: ['loop', 'cycle', 'repeat'],
          shortcut: 'L',
          category: CommandCategory.transport,
        ),
      if (onToggleMetronome != null)
        DawCommand(
          label: 'Toggle Metronome',
          description: 'Turn metronome on/off',
          icon: Icons.timer,
          onExecute: onToggleMetronome,
          keywords: ['metronome', 'click', 'tempo'],
          shortcut: 'C',
          category: CommandCategory.transport,
        ),
      if (onGoToStart != null)
        DawCommand(
          label: 'Go to Start',
          description: 'Jump to project start',
          icon: Icons.first_page,
          onExecute: onGoToStart,
          keywords: ['start', 'beginning', 'home'],
          shortcut: 'Home',
          category: CommandCategory.transport,
        ),
      if (onGoToEnd != null)
        DawCommand(
          label: 'Go to End',
          description: 'Jump to project end',
          icon: Icons.last_page,
          onExecute: onGoToEnd,
          keywords: ['end', 'finish'],
          shortcut: 'End',
          category: CommandCategory.transport,
        ),

      // ─── MIX ────────────────────────────────────────────────────────────────────
      if (onSoloSelected != null)
        DawCommand(
          label: 'Solo Selected',
          description: 'Solo selected tracks',
          icon: Icons.headphones,
          onExecute: onSoloSelected,
          keywords: ['solo', 'isolate'],
          shortcut: 'S',
          category: CommandCategory.mix,
        ),
      if (onMuteSelected != null)
        DawCommand(
          label: 'Mute Selected',
          description: 'Mute selected tracks',
          icon: Icons.volume_off,
          onExecute: onMuteSelected,
          keywords: ['mute', 'silence'],
          shortcut: 'M',
          category: CommandCategory.mix,
        ),
      if (onClearAllSolo != null)
        DawCommand(
          label: 'Clear All Solo',
          description: 'Clear all solo states',
          icon: Icons.hearing_disabled,
          onExecute: onClearAllSolo,
          keywords: ['clear', 'solo', 'all'],
          category: CommandCategory.mix,
        ),
      if (onResetFaders != null)
        DawCommand(
          label: 'Reset All Faders',
          description: 'Reset all faders to unity',
          icon: Icons.restart_alt,
          onExecute: onResetFaders,
          keywords: ['reset', 'faders', 'unity', 'default'],
          category: CommandCategory.mix,
        ),

      // ─── AUTOMATION ─────────────────────────────────────────────────────────────
      if (onToggleAutomationRead != null)
        DawCommand(
          label: 'Toggle Automation Read',
          description: 'Enable/disable reading automation',
          icon: Icons.auto_graph,
          onExecute: onToggleAutomationRead,
          keywords: ['automation', 'read', 'play'],
          shortcut: 'A',
          category: CommandCategory.automation,
        ),
      if (onToggleAutomationWrite != null)
        DawCommand(
          label: 'Toggle Automation Write',
          description: 'Enable/disable writing automation',
          icon: Icons.edit_note,
          onExecute: onToggleAutomationWrite,
          keywords: ['automation', 'write', 'record'],
          shortcut: '⌘A',
          category: CommandCategory.automation,
        ),

      // ─── TOOLS ──────────────────────────────────────────────────────────────────
      if (onOpenPreferences != null)
        DawCommand(
          label: 'Preferences',
          description: 'Open application preferences',
          icon: Icons.settings,
          onExecute: onOpenPreferences,
          keywords: ['preferences', 'settings', 'options'],
          shortcut: '⌘,',
          category: CommandCategory.tools,
        ),
      if (onOpenKeyboardShortcuts != null)
        DawCommand(
          label: 'Keyboard Shortcuts',
          description: 'View keyboard shortcuts',
          icon: Icons.keyboard,
          onExecute: onOpenKeyboardShortcuts,
          keywords: ['keyboard', 'shortcuts', 'keys', 'hotkeys'],
          category: CommandCategory.tools,
        ),
      if (onRefreshPlugins != null)
        DawCommand(
          label: 'Refresh Plugins',
          description: 'Rescan plugin folders',
          icon: Icons.refresh,
          onExecute: onRefreshPlugins,
          keywords: ['refresh', 'plugins', 'rescan', 'vst'],
          category: CommandCategory.tools,
        ),
    ];
  }

  /// Get commands filtered by category
  static List<Command> getByCategory(List<Command> commands, CommandCategory category) {
    return commands.where((cmd) {
      if (cmd is DawCommand) {
        return cmd.category == category;
      }
      return false;
    }).toList();
  }
}
