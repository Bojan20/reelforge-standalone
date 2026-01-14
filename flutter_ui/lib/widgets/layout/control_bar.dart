/// FluxForge Studio Control Bar
///
/// Top control bar matching React ControlBar.tsx 1:1:
/// - Logo
/// - Menu bar (File/Edit/View/Project)
/// - Mode switcher (DAW/Middleware/Slot)
/// - Transport controls
/// - Tempo/Time signature/Time display
/// - Project name + Save
/// - Zone toggles
/// - System meters

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../models/layout_models.dart';
import '../../models/editor_mode_config.dart';
import '../meters/pdc_display.dart';
import '../../providers/edit_mode_pro_provider.dart';
import '../../providers/smart_tool_provider.dart';
import '../../providers/keyboard_focus_provider.dart';
import '../../providers/razor_edit_provider.dart';
import '../../providers/modulator_provider.dart';
import '../../providers/arranger_track_provider.dart';
import '../../providers/chord_track_provider.dart';
import '../../providers/expression_map_provider.dart';
import '../../providers/macro_control_provider.dart';
import '../../providers/track_versions_provider.dart';
import '../../providers/groove_quantize_provider.dart';
import '../../providers/scale_assistant_provider.dart';

// ════════════════════════════════════════════════════════════════════════════
// TIME FORMATTING
// ════════════════════════════════════════════════════════════════════════════

class TimeFormatter {
  static String formatBarsBeats(double seconds, double tempo, TimeSignature ts) {
    final beatsPerSecond = tempo / 60;
    final totalBeats = seconds * beatsPerSecond;
    final beatsPerBar = ts.numerator;
    final bars = (totalBeats / beatsPerBar).floor() + 1;
    final beats = (totalBeats % beatsPerBar).floor() + 1;
    final ticks = ((totalBeats % 1) * 480).floor();
    return '${bars.toString().padLeft(3, ' ')}.${beats}.${ticks.toString().padLeft(3, '0')}';
  }

  static String formatTimecode(double seconds) {
    final hrs = (seconds / 3600).floor();
    final mins = ((seconds % 3600) / 60).floor();
    final secs = (seconds % 60).floor();
    final frames = ((seconds % 1) * 30).floor();
    return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
  }

  static String formatSamples(double seconds, {int sampleRate = 48000}) {
    return (seconds * sampleRate).floor().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MODE CONFIG
// ════════════════════════════════════════════════════════════════════════════

class ModeConfigData {
  final EditorMode mode;
  final String name;
  final String description;
  final String icon;
  final String shortcut;
  final Color accentColor;

  const ModeConfigData({
    required this.mode,
    required this.name,
    required this.description,
    required this.icon,
    required this.shortcut,
    required this.accentColor,
  });
}

const Map<EditorMode, ModeConfigData> modeConfigs = {
  EditorMode.daw: ModeConfigData(
    mode: EditorMode.daw,
    name: 'DAW',
    description: 'Timeline editing',
    icon: '🎛',
    shortcut: '1',
    accentColor: FluxForgeTheme.accentBlue,
  ),
  EditorMode.middleware: ModeConfigData(
    mode: EditorMode.middleware,
    name: 'Middleware',
    description: 'Event routing',
    icon: '🔀',
    shortcut: '2',
    accentColor: FluxForgeTheme.accentOrange,
  ),
  EditorMode.slot: ModeConfigData(
    mode: EditorMode.slot,
    name: 'Slot',
    description: 'Slot audio',
    icon: '🎰',
    shortcut: '3',
    accentColor: FluxForgeTheme.accentGreen,
  ),
};

// ════════════════════════════════════════════════════════════════════════════
// CONTROL BAR
// ════════════════════════════════════════════════════════════════════════════

class ControlBar extends StatefulWidget {
  final EditorMode editorMode;
  final ValueChanged<EditorMode>? onEditorModeChange;
  final bool isPlaying;
  final bool isRecording;
  final bool transportDisabled;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;
  final VoidCallback? onRewind;
  final VoidCallback? onForward;
  final double tempo;
  final ValueChanged<double>? onTempoChange;
  final TimeSignature timeSignature;
  final double currentTime;
  final TimeDisplayMode timeDisplayMode;
  final VoidCallback? onTimeDisplayModeChange;
  final bool loopEnabled;
  final VoidCallback? onLoopToggle;
  final bool snapEnabled;
  final double snapValue;
  final VoidCallback? onSnapToggle;
  final ValueChanged<double>? onSnapValueChange;
  final bool metronomeEnabled;
  final VoidCallback? onMetronomeToggle;
  final double cpuUsage;
  final double memoryUsage;
  final String projectName;
  final VoidCallback? onSave;
  final VoidCallback? onToggleLeftZone;
  final VoidCallback? onToggleRightZone;
  final VoidCallback? onToggleLowerZone;
  final MenuCallbacks? menuCallbacks;

  // PDC (Plugin Delay Compensation)
  final int pdcLatencySamples;
  final double pdcLatencyMs;
  final bool pdcEnabled;
  final VoidCallback? onPdcTap;

  const ControlBar({
    super.key,
    this.editorMode = EditorMode.daw,
    this.onEditorModeChange,
    this.isPlaying = false,
    this.isRecording = false,
    this.transportDisabled = false,
    this.onPlay,
    this.onStop,
    this.onRecord,
    this.onRewind,
    this.onForward,
    this.tempo = 120,
    this.onTempoChange,
    this.timeSignature = const TimeSignature(4, 4),
    this.currentTime = 0,
    this.timeDisplayMode = TimeDisplayMode.bars,
    this.onTimeDisplayModeChange,
    this.loopEnabled = false,
    this.onLoopToggle,
    this.snapEnabled = true,
    this.snapValue = 1,
    this.onSnapToggle,
    this.onSnapValueChange,
    this.metronomeEnabled = false,
    this.onMetronomeToggle,
    this.cpuUsage = 0,
    this.memoryUsage = 0,
    this.projectName = 'Untitled',
    this.onSave,
    this.onToggleLeftZone,
    this.onToggleRightZone,
    this.onToggleLowerZone,
    this.menuCallbacks,
    this.pdcLatencySamples = 0,
    this.pdcLatencyMs = 0,
    this.pdcEnabled = true,
    this.onPdcTap,
  });

  @override
  State<ControlBar> createState() => _ControlBarState();
}

class _ControlBarState extends State<ControlBar> {
  String get _formattedTime {
    switch (widget.timeDisplayMode) {
      case TimeDisplayMode.bars:
        return TimeFormatter.formatBarsBeats(
            widget.currentTime, widget.tempo, widget.timeSignature);
      case TimeDisplayMode.timecode:
        return TimeFormatter.formatTimecode(widget.currentTime);
      case TimeDisplayMode.samples:
        return TimeFormatter.formatSamples(widget.currentTime);
    }
  }

  String get _timeModeLabel {
    switch (widget.timeDisplayMode) {
      case TimeDisplayMode.bars:
        return 'BAR';
      case TimeDisplayMode.timecode:
        return 'TC';
      case TimeDisplayMode.samples:
        return 'SMP';
    }
  }

  Color get _cpuColor {
    if (widget.cpuUsage > 80) return FluxForgeTheme.errorRed;
    if (widget.cpuUsage > 60) return FluxForgeTheme.warningOrange;
    return FluxForgeTheme.accentGreen;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        height: 48,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          border: Border(
              bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 1400;
            final isVeryCompact = constraints.maxWidth < 1100;
            final isUltraCompact = constraints.maxWidth <= 850;

            // Get feature flags for current mode
            final features = getModeLayoutConfig(widget.editorMode).features;

            return Row(
              children: [
                // Logo
                _Logo(),

                // Menu Bar (always visible)
                _MenuBar(
                  openMenu: null,
                  onMenuToggle: (_) {},
                  onMenuItemClick: (_) {},
                  menuCallbacks: widget.menuCallbacks,
                ),

                // Mode Switcher
                if (widget.onEditorModeChange != null)
                  _ModeSwitcher(
                    mode: widget.editorMode,
                    onChange: widget.onEditorModeChange!,
                    compact: isCompact,
                  ),

                // Transport Controls (only in DAW mode or when features.showTransport)
                if (features.showTransport)
                  _TransportControls(
                    isPlaying: widget.isPlaying,
                    isRecording: widget.isRecording,
                    transportDisabled: widget.transportDisabled,
                    loopEnabled: widget.loopEnabled,
                    metronomeEnabled: widget.metronomeEnabled,
                    snapEnabled: widget.snapEnabled,
                    snapValue: widget.snapValue,
                    onPlay: widget.onPlay,
                    onStop: widget.onStop,
                    onRecord: widget.onRecord,
                    onRewind: widget.onRewind,
                    onForward: widget.onForward,
                    onLoopToggle: widget.onLoopToggle,
                    onMetronomeToggle: widget.onMetronomeToggle,
                    onSnapToggle: widget.onSnapToggle,
                    onSnapValueChange: widget.onSnapValueChange,
                    compact: isCompact,
                  ),

                // Pro Tools Edit Modes (Shuffle/Slip/Spot/Grid) - only in DAW mode
                if (features.showTransport && !isVeryCompact)
                  _ProEditModes(),

                // Smart Tool indicator - only in DAW mode
                if (features.showTransport && !isVeryCompact)
                  _SmartToolButton(),

                // Keyboard Focus Mode indicator - only in DAW mode
                if (features.showTransport && !isUltraCompact)
                  _KeyboardFocusButton(),

                // Razor Edit indicator - only in DAW mode
                if (features.showTransport && !isVeryCompact)
                  _RazorEditButton(),

                // Arranger Track toggle
                if (features.showTransport && !isVeryCompact)
                  _ArrangerTrackButton(),

                // Chord Track toggle
                if (features.showTransport && !isVeryCompact)
                  _ChordTrackButton(),

                // Scale Assistant toggle
                if (features.showTransport && !isVeryCompact)
                  _ScaleAssistantButton(),

                // Groove Quantize toggle
                if (features.showTransport && !isUltraCompact)
                  _GrooveQuantizeButton(),

                // Track Versions toggle
                if (features.showTransport && !isUltraCompact)
                  _TrackVersionsButton(),

                // Macro Controls toggle
                if (features.showTransport && !isUltraCompact)
                  _MacroControlsButton(),

                // Tempo (only in DAW mode)
                if (features.showTempo && !isVeryCompact)
                  _TempoDisplay(tempo: widget.tempo, onTempoChange: widget.onTempoChange),

                // Time Signature (only in DAW mode)
                if (features.showTimecode && !isCompact)
                  _TimeSignatureDisplay(timeSignature: widget.timeSignature),

                // Time Display (only in DAW mode)
                if (features.showTimecode)
                  _TimeDisplay(
                    formattedTime: _formattedTime,
                    modeLabel: _timeModeLabel,
                    onTap: widget.onTimeDisplayModeChange,
                  ),

                // Middleware mode indicator (show in non-DAW modes, hide on ultra compact)
                if (!features.showTransport && !isUltraCompact)
                  _ModeStatusIndicator(mode: widget.editorMode),

                // Spacer
                const Expanded(child: SizedBox()),

                // Project Name & Save (hide on compact)
                if (!isCompact)
                  _ProjectInfo(name: widget.projectName, onSave: widget.onSave),

                // Zone Toggles (hide on ultra compact)
                if (!isUltraCompact)
                  _ZoneToggles(
                    onToggleLeft: widget.onToggleLeftZone,
                    onToggleLower: widget.onToggleLowerZone,
                    onToggleRight: widget.onToggleRightZone,
                  ),

                // PDC Indicator (only in DAW mode, auto-fetch from engine)
                if (features.showTransport && !isVeryCompact)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: widget.pdcLatencySamples > 0
                      ? PdcIndicator(
                          totalLatencySamples: widget.pdcLatencySamples,
                          totalLatencyMs: widget.pdcLatencyMs,
                          isEnabled: widget.pdcEnabled,
                          onTap: widget.onPdcTap,
                        )
                      : PdcIndicator.fromEngine(onTap: widget.onPdcTap),
                  ),

                // System Meters (hide on very compact)
                if (!isVeryCompact)
                  _SystemMeters(
                    cpuUsage: widget.cpuUsage,
                    memoryUsage: widget.memoryUsage,
                    cpuColor: _cpuColor,
                  ),

                const SizedBox(width: 8),
              ],
            );
          },
        ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// LOGO
// ════════════════════════════════════════════════════════════════════════════

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [FluxForgeTheme.accentBlue, FluxForgeTheme.accentCyan]),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(
              child: Text('R',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
          ),
          const SizedBox(width: 8),
          Text('FluxForge Studio',
              style: FluxForgeTheme.label
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MENU BAR
// ════════════════════════════════════════════════════════════════════════════

class _MenuBar extends StatelessWidget {
  final String? openMenu;
  final void Function(String) onMenuToggle;
  final void Function(VoidCallback?) onMenuItemClick;
  final MenuCallbacks? menuCallbacks;

  const _MenuBar({
    required this.openMenu,
    required this.onMenuToggle,
    required this.onMenuItemClick,
    this.menuCallbacks,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PopupMenuBtn(
          label: 'File',
          items: [
            _PopupItem('New Project', '⌘N', menuCallbacks?.onNewProject),
            _PopupItem('Open Project...', '⌘O', menuCallbacks?.onOpenProject),
            null, // Separator
            _PopupItem('Save', '⌘S', menuCallbacks?.onSaveProject),
            _PopupItem('Save As...', '⇧⌘S', menuCallbacks?.onSaveProjectAs),
            null,
            _PopupItem('Import Routes JSON...', '⌘I', menuCallbacks?.onImportJSON),
            _PopupItem('Export Routes JSON...', '⇧⌘E', menuCallbacks?.onExportJSON),
            null,
            _PopupItem('Import Audio Folder...', '', menuCallbacks?.onImportAudioFolder),
            _PopupItem('Import Audio Files...', '⇧⌘I', menuCallbacks?.onImportAudioFiles),
          ],
        ),
        _PopupMenuBtn(
          label: 'Edit',
          items: [
            _PopupItem('Undo', '⌘Z', menuCallbacks?.onUndo),
            _PopupItem('Redo', '⇧⌘Z', menuCallbacks?.onRedo),
            null,
            _PopupItem('Cut', '⌘X', menuCallbacks?.onCut),
            _PopupItem('Copy', '⌘C', menuCallbacks?.onCopy),
            _PopupItem('Paste', '⌘V', menuCallbacks?.onPaste),
            _PopupItem('Delete', '⌫', menuCallbacks?.onDelete),
            null,
            _PopupItem('Select All', '⌘A', menuCallbacks?.onSelectAll),
          ],
        ),
        _PopupMenuBtn(
          label: 'View',
          items: [
            _PopupItem('Toggle Left Panel', '⌘L', menuCallbacks?.onToggleLeftPanel),
            _PopupItem('Toggle Right Panel', '⌘R', menuCallbacks?.onToggleRightPanel),
            _PopupItem('Toggle Lower Panel', '⌘B', menuCallbacks?.onToggleLowerPanel),
            null,
            _PopupItem('Reset Layout', '', menuCallbacks?.onResetLayout),
          ],
        ),
        _PopupMenuBtn(
          label: 'Project',
          items: [
            _PopupItem('Project Settings...', '⌘,', menuCallbacks?.onProjectSettings),
            null,
            _PopupItem('Validate Project', '⇧⌘V', menuCallbacks?.onValidateProject),
            _PopupItem('Build Project', '⌘B', menuCallbacks?.onBuildProject),
          ],
        ),
      ],
    );
  }
}

class _PopupItem {
  final String label;
  final String shortcut;
  final VoidCallback? callback;
  const _PopupItem(this.label, this.shortcut, this.callback);
}

class _PopupMenuBtn extends StatefulWidget {
  final String label;
  final List<_PopupItem?> items; // null = separator

  const _PopupMenuBtn({
    required this.label,
    required this.items,
  });

  @override
  State<_PopupMenuBtn> createState() => _PopupMenuBtnState();
}

class _PopupMenuBtnState extends State<_PopupMenuBtn> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      offset: const Offset(0, 36),
      color: FluxForgeTheme.bgElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      elevation: 8,
      tooltip: '', // Disable default tooltip
      position: PopupMenuPosition.under,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _isHovered ? FluxForgeTheme.bgElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              color: _isHovered ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
            ),
          ),
        ),
      ),
      itemBuilder: (context) {
        final menuItems = <PopupMenuEntry<int>>[];
        for (var i = 0; i < widget.items.length; i++) {
          final item = widget.items[i];
          if (item == null) {
            menuItems.add(const PopupMenuDivider(height: 8));
          } else {
            menuItems.add(PopupMenuItem<int>(
              value: i,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: FluxForgeTheme.textPrimary,
                    ),
                  ),
                  if (item.shortcut.isNotEmpty)
                    Text(
                      item.shortcut,
                      style: TextStyle(
                        fontSize: 11,
                        color: FluxForgeTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ));
          }
        }
        return menuItems;
      },
      onSelected: (index) {
        final item = widget.items[index];
        if (item != null) {
          item.callback?.call();
        }
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MODE SWITCHER
// ════════════════════════════════════════════════════════════════════════════

class _ModeSwitcher extends StatelessWidget {
  final EditorMode mode;
  final ValueChanged<EditorMode> onChange;
  final bool compact;

  const _ModeSwitcher({
    required this.mode,
    required this.onChange,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: modeConfigs.values.map((config) {
          final isActive = mode == config.mode;
          return Tooltip(
            message: '${config.name} - ${config.description} (${config.shortcut})',
            child: GestureDetector(
              onTap: () => onChange(config.mode),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 6 : 10,
                  vertical: 6,
                ),
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? config.accentColor.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isActive ? config.accentColor : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Text(config.icon, style: const TextStyle(fontSize: 12)),
                    if (!compact) ...[
                      const SizedBox(width: 6),
                      Text(
                        config.name,
                        style: TextStyle(
                          color: isActive
                              ? config.accentColor
                              : FluxForgeTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MODE STATUS INDICATOR (for Middleware/Slot modes)
// ════════════════════════════════════════════════════════════════════════════

class _ModeStatusIndicator extends StatelessWidget {
  final EditorMode mode;

  const _ModeStatusIndicator({required this.mode});

  @override
  Widget build(BuildContext context) {
    final config = modeConfigs[mode]!;
    final layoutConfig = getModeLayoutConfig(mode);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: config.accentColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: config.accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(config.icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Text(
            layoutConfig.features.showSlotTools ? 'Slot Audio' : 'Events',
            style: TextStyle(
              color: config.accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TRANSPORT CONTROLS
// ════════════════════════════════════════════════════════════════════════════

class _TransportControls extends StatelessWidget {
  final bool isPlaying;
  final bool isRecording;
  final bool transportDisabled;
  final bool loopEnabled;
  final bool metronomeEnabled;
  final bool snapEnabled;
  final double snapValue;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;
  final VoidCallback? onRewind;
  final VoidCallback? onForward;
  final VoidCallback? onLoopToggle;
  final VoidCallback? onMetronomeToggle;
  final VoidCallback? onSnapToggle;
  final ValueChanged<double>? onSnapValueChange;
  final bool compact;

  const _TransportControls({
    required this.isPlaying,
    required this.isRecording,
    required this.transportDisabled,
    required this.loopEnabled,
    required this.metronomeEnabled,
    required this.snapEnabled,
    required this.snapValue,
    this.onPlay,
    this.onStop,
    this.onRecord,
    this.onRewind,
    this.onForward,
    this.onLoopToggle,
    this.onMetronomeToggle,
    this.onSnapToggle,
    this.onSnapValueChange,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Transport buttons
        _TransportBtn(icon: '⏮', onPressed: onRewind, tooltip: 'Rewind (,)'),
        _TransportBtn(icon: '⏹', onPressed: onStop, tooltip: 'Stop (.)'),
        _TransportBtn(
          icon: isPlaying ? '⏸' : '▶',
          onPressed: transportDisabled ? null : onPlay,
          tooltip: transportDisabled
              ? 'Timeline playback disabled'
              : 'Play/Pause (Space)',
          isActive: isPlaying,
          activeColor: FluxForgeTheme.accentGreen,
          disabled: transportDisabled,
        ),
        _TransportBtn(
          icon: '⏺',
          onPressed: onRecord,
          tooltip: 'Record (R)',
          isActive: isRecording,
          activeColor: FluxForgeTheme.errorRed,
        ),
        _TransportBtn(icon: '⏭', onPressed: onForward, tooltip: 'Forward (/)'),

        if (!compact) ...[
          _Divider(),

          // Loop & Metronome
          _TransportBtn(
            icon: '🔁',
            onPressed: onLoopToggle,
            tooltip: 'Loop (L)',
            isActive: loopEnabled,
          ),
          _TransportBtn(
            icon: '🎵',
            onPressed: onMetronomeToggle,
            tooltip: 'Metronome (K)',
            isActive: metronomeEnabled,
          ),

          _Divider(),

          // Snap
          _TransportBtn(
            icon: '⊞',
            onPressed: onSnapToggle,
            tooltip: 'Snap to Grid (G)',
            isActive: snapEnabled,
          ),
          if (snapEnabled && onSnapValueChange != null)
            _SnapDropdown(value: snapValue, onChange: onSnapValueChange!),
        ],
      ],
    );
  }
}

class _TransportBtn extends StatelessWidget {
  final String icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool isActive;
  final Color? activeColor;
  final bool disabled;

  const _TransportBtn({
    required this.icon,
    this.onPressed,
    required this.tooltip,
    this.isActive = false,
    this.activeColor,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? (activeColor ?? FluxForgeTheme.accentBlue)
        : FluxForgeTheme.textSecondary;

    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: disabled ? 0.4 : 1,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isActive ? color.withValues(alpha: 0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                icon,
                style: TextStyle(fontSize: 14, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: FluxForgeTheme.borderSubtle,
    );
  }
}

class _SnapDropdown extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChange;

  const _SnapDropdown({required this.value, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: DropdownButton<double>(
        value: value,
        isDense: true,
        underline: const SizedBox(),
        dropdownColor: FluxForgeTheme.bgElevated,
        style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textPrimary),
        items: const [
          DropdownMenuItem(value: 0.25, child: Text('1/16')),
          DropdownMenuItem(value: 0.5, child: Text('1/8')),
          DropdownMenuItem(value: 1.0, child: Text('1/4')),
          DropdownMenuItem(value: 2.0, child: Text('1/2')),
          DropdownMenuItem(value: 4.0, child: Text('Bar')),
        ],
        onChanged: (v) => onChange(v!),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TEMPO & TIME
// ════════════════════════════════════════════════════════════════════════════

class _TempoDisplay extends StatelessWidget {
  final double tempo;
  final ValueChanged<double>? onTempoChange;

  const _TempoDisplay({required this.tempo, this.onTempoChange});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        final delta = -d.delta.dy / 5;
        onTempoChange?.call((tempo + delta).clamp(20.0, 999.0));
      },
      child: Tooltip(
        message: 'Scroll to adjust tempo',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(tempo.toStringAsFixed(1),
                  style: FluxForgeTheme.monoSmall
                      .copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
              Text('BPM',
                  style:
                      TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeSignatureDisplay extends StatelessWidget {
  final TimeSignature timeSignature;
  const _TimeSignatureDisplay({required this.timeSignature});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(timeSignature.toString(),
          style: FluxForgeTheme.monoSmall.copyWith(fontSize: 13)),
    );
  }
}

class _TimeDisplay extends StatelessWidget {
  final String formattedTime;
  final String modeLabel;
  final VoidCallback? onTap;

  const _TimeDisplay(
      {required this.formattedTime, required this.modeLabel, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: 'Click to change display mode',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Row(
            children: [
              Text(formattedTime,
                  style: FluxForgeTheme.monoSmall.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(modeLabel,
                    style: TextStyle(
                        color: FluxForgeTheme.accentBlue,
                        fontSize: 9,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PROJECT INFO
// ════════════════════════════════════════════════════════════════════════════

class _ProjectInfo extends StatelessWidget {
  final String name;
  final VoidCallback? onSave;
  const _ProjectInfo({required this.name, this.onSave});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(name,
              style:
                  TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12)),
          if (onSave != null) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Save (Ctrl+S)',
              child: InkWell(
                onTap: onSave,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration:
                      BoxDecoration(borderRadius: BorderRadius.circular(4)),
                  child: const Center(
                    child: Text('💾', style: TextStyle(fontSize: 12)),
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

// ════════════════════════════════════════════════════════════════════════════
// ZONE TOGGLES
// ════════════════════════════════════════════════════════════════════════════

class _ZoneToggles extends StatelessWidget {
  final VoidCallback? onToggleLeft;
  final VoidCallback? onToggleLower;
  final VoidCallback? onToggleRight;

  const _ZoneToggles({this.onToggleLeft, this.onToggleLower, this.onToggleRight});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (onToggleLeft != null)
            _ZoneBtn(icon: '◀', onPressed: onToggleLeft!, tooltip: 'Toggle Left Zone (Ctrl+L)'),
          if (onToggleLower != null)
            _ZoneBtn(icon: '▼', onPressed: onToggleLower!, tooltip: 'Toggle Lower Zone (Ctrl+B)'),
          if (onToggleRight != null)
            _ZoneBtn(icon: '▶', onPressed: onToggleRight!, tooltip: 'Toggle Right Zone (Ctrl+R)'),
        ],
      ),
    );
  }
}

class _ZoneBtn extends StatelessWidget {
  final String icon;
  final VoidCallback onPressed;
  final String tooltip;
  const _ZoneBtn(
      {required this.icon, required this.onPressed, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Text(icon,
                style: TextStyle(
                    fontSize: 12, color: FluxForgeTheme.textSecondary)),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SYSTEM METERS
// ════════════════════════════════════════════════════════════════════════════

class _SystemMeters extends StatelessWidget {
  final double cpuUsage;
  final double memoryUsage;
  final Color cpuColor;
  const _SystemMeters(
      {required this.cpuUsage,
      required this.memoryUsage,
      required this.cpuColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MeterBar(label: 'CPU', value: cpuUsage, color: cpuColor),
        const SizedBox(width: 8),
        _MeterBar(label: 'MEM', value: memoryUsage, color: FluxForgeTheme.accentBlue),
      ],
    );
  }
}

class _MeterBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _MeterBar(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 9)),
        const SizedBox(height: 2),
        Container(
          width: 40,
          height: 6,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (value / 100).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PRO TOOLS EDIT MODES (Shuffle/Slip/Spot/Grid)
// ════════════════════════════════════════════════════════════════════════════

class _ProEditModes extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<EditModeProProvider>(
      builder: (context, provider, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: EditMode.values.map((mode) {
              final config = kEditModeConfigs[mode]!;
              final isSelected = provider.mode == mode;

              return Tooltip(
                message: '${config.name} (${config.shortcut})\n${config.description}',
                child: GestureDetector(
                  onTap: () => provider.setMode(mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? config.color.withValues(alpha: 0.2)
                          : FluxForgeTheme.bgMid,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? config.color : FluxForgeTheme.borderSubtle,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        config.icon,
                        size: 14,
                        color: isSelected ? config.color : FluxForgeTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SMART TOOL BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _SmartToolButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SmartToolProvider>(
      builder: (context, provider, _) {
        final isActive = provider.enabled;

        return Tooltip(
          message: isActive
              ? 'Smart Tool: ${provider.modeDisplayName}'
              : 'Smart Tool (Disabled)',
          child: GestureDetector(
            onTap: provider.toggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isActive
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.borderSubtle,
                  width: isActive ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    provider.modeIcon,
                    size: 14,
                    color: isActive
                        ? FluxForgeTheme.accentBlue
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Smart',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isActive
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// KEYBOARD FOCUS MODE BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _KeyboardFocusButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<KeyboardFocusProvider>(
      builder: (context, provider, _) {
        final isActive = provider.isCommandsMode;

        return Tooltip(
          message: isActive
              ? 'Commands Focus Mode (Cmd+Shift+A to exit)'
              : 'Normal Mode (Cmd+Shift+A for Commands)',
          child: GestureDetector(
            onTap: provider.toggleMode,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? FluxForgeTheme.accentOrange.withValues(alpha: 0.15)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isActive
                      ? FluxForgeTheme.accentOrange
                      : FluxForgeTheme.borderSubtle,
                  width: isActive ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    provider.modeIcon,
                    size: 14,
                    color: isActive
                        ? FluxForgeTheme.accentOrange
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isActive ? 'CMD' : 'A-Z',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isActive
                          ? FluxForgeTheme.accentOrange
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// RAZOR EDIT BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _RazorEditButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<RazorEditProvider>(
      builder: (context, provider, _) {
        final hasSelection = provider.hasSelection;

        return Tooltip(
          message: 'Razor Edit (Alt+Drag to select range)\n'
              '${hasSelection ? "Selection active - Del to delete" : "No selection"}',
          child: GestureDetector(
            onTap: hasSelection ? provider.clearSelection : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: hasSelection
                    ? FluxForgeTheme.accentOrange.withValues(alpha: 0.15)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: hasSelection
                      ? FluxForgeTheme.accentOrange
                      : FluxForgeTheme.borderSubtle,
                  width: hasSelection ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.carpenter,
                    size: 14,
                    color: hasSelection
                        ? FluxForgeTheme.accentOrange
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Razor',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: hasSelection
                          ? FluxForgeTheme.accentOrange
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ARRANGER TRACK BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _ArrangerTrackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ArrangerTrackProvider>(
      builder: (context, provider, _) {
        final isEnabled = provider.enabled;
        final sectionCount = provider.sections.length;

        return Tooltip(
          message: 'Arranger Track (Cubase-style)\n'
              '${isEnabled ? "Enabled" : "Disabled"} - $sectionCount sections',
          child: GestureDetector(
            onTap: provider.toggleEnabled,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isEnabled
                    ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isEnabled
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.borderSubtle,
                  width: isEnabled ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.view_week,
                    size: 14,
                    color: isEnabled
                        ? FluxForgeTheme.accentBlue
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Arr',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isEnabled
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CHORD TRACK BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _ChordTrackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ChordTrackProvider>(
      builder: (context, provider, _) {
        final isEnabled = provider.enabled;
        final chordCount = provider.events.length;
        final currentChord = provider.currentEvent?.displayName;

        return Tooltip(
          message: 'Chord Track (Cubase-style)\n'
              '${isEnabled ? "Enabled" : "Disabled"} - $chordCount chords\n'
              '${currentChord != null ? "Playing: $currentChord" : ""}',
          child: GestureDetector(
            onTap: provider.toggleEnabled,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isEnabled
                    ? const Color(0xFFAA40FF).withValues(alpha: 0.15)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isEnabled
                      ? const Color(0xFFAA40FF)
                      : FluxForgeTheme.borderSubtle,
                  width: isEnabled ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.music_note,
                    size: 14,
                    color: isEnabled
                        ? const Color(0xFFAA40FF)
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    currentChord ?? 'Chord',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isEnabled
                          ? const Color(0xFFAA40FF)
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MODULATOR BUTTON (for menu/toolbar access)
// ════════════════════════════════════════════════════════════════════════════

class ModulatorButton extends StatelessWidget {
  const ModulatorButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ModulatorProvider>(
      builder: (context, provider, _) {
        final isEnabled = provider.enabled;
        final lfoCount = provider.lfos.length;
        final envCount = provider.envelopes.length;

        return Tooltip(
          message: 'Parameter Modulators\n'
              '${isEnabled ? "Enabled" : "Disabled"}\n'
              '$lfoCount LFOs, $envCount Envelopes',
          child: GestureDetector(
            onTap: provider.toggleEnabled,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isEnabled
                    ? FluxForgeTheme.accentCyan.withValues(alpha: 0.15)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isEnabled
                      ? FluxForgeTheme.accentCyan
                      : FluxForgeTheme.borderSubtle,
                  width: isEnabled ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.waves,
                    size: 14,
                    color: isEnabled
                        ? FluxForgeTheme.accentCyan
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Mod',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isEnabled
                          ? FluxForgeTheme.accentCyan
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// EXPRESSION MAP BUTTON (for menu/toolbar access)
// ════════════════════════════════════════════════════════════════════════════

class ExpressionMapButton extends StatelessWidget {
  const ExpressionMapButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ExpressionMapProvider>(
      builder: (context, provider, _) {
        final isEnabled = provider.enabled;
        final mapCount = provider.maps.length;

        return Tooltip(
          message: 'Expression Maps (Cubase-style)\n'
              '${isEnabled ? "Enabled" : "Disabled"}\n'
              '$mapCount maps loaded',
          child: GestureDetector(
            onTap: provider.toggleEnabled,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isEnabled
                    ? FluxForgeTheme.accentGreen.withValues(alpha: 0.15)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isEnabled
                      ? FluxForgeTheme.accentGreen
                      : FluxForgeTheme.borderSubtle,
                  width: isEnabled ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.piano,
                    size: 14,
                    color: isEnabled
                        ? FluxForgeTheme.accentGreen
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Expr',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isEnabled
                          ? FluxForgeTheme.accentGreen
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SCALE ASSISTANT BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _ScaleAssistantButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ScaleAssistantProvider>(
      builder: (context, provider, _) {
        final isEnabled = provider.showScaleNotes;
        final key = provider.globalKey;

        return Tooltip(
          message: 'Scale Assistant\n'
              'Key: ${key.shortName}\n'
              'Mode: ${provider.constraintMode.name}',
          child: GestureDetector(
            onTap: () => provider.setShowScaleNotes(!isEnabled),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isEnabled
                    ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isEnabled
                      ? const Color(0xFFFFD700)
                      : FluxForgeTheme.borderSubtle,
                  width: isEnabled ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.music_note,
                    size: 14,
                    color: isEnabled
                        ? const Color(0xFFFFD700)
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    key.shortName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isEnabled
                          ? const Color(0xFFFFD700)
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// GROOVE QUANTIZE BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _GrooveQuantizeButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<GrooveQuantizeProvider>(
      builder: (context, provider, _) {
        final isEnabled = provider.enabled;
        final templateName = provider.activeTemplate?.name ?? 'None';

        return Tooltip(
          message: 'Groove Quantize\n'
              '${isEnabled ? "Enabled" : "Disabled"}\n'
              'Template: $templateName',
          child: GestureDetector(
            onTap: provider.toggleEnabled,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isEnabled
                    ? const Color(0xFFFF6B6B).withValues(alpha: 0.15)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isEnabled
                      ? const Color(0xFFFF6B6B)
                      : FluxForgeTheme.borderSubtle,
                  width: isEnabled ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.graphic_eq,
                    size: 14,
                    color: isEnabled
                        ? const Color(0xFFFF6B6B)
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Grv',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isEnabled
                          ? const Color(0xFFFF6B6B)
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TRACK VERSIONS BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _TrackVersionsButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<TrackVersionsProvider>(
      builder: (context, provider, _) {
        final isEnabled = provider.enabled;
        final trackCount = provider.tracksWithVersions.length;

        return Tooltip(
          message: 'Track Versions (Cubase-style)\n'
              '${isEnabled ? "Enabled" : "Disabled"}\n'
              '$trackCount tracks with versions',
          child: GestureDetector(
            onTap: provider.toggleEnabled,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isEnabled
                    ? const Color(0xFF9B59B6).withValues(alpha: 0.15)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isEnabled
                      ? const Color(0xFF9B59B6)
                      : FluxForgeTheme.borderSubtle,
                  width: isEnabled ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.layers,
                    size: 14,
                    color: isEnabled
                        ? const Color(0xFF9B59B6)
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Ver',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isEnabled
                          ? const Color(0xFF9B59B6)
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MACRO CONTROLS BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _MacroControlsButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<MacroControlProvider>(
      builder: (context, provider, _) {
        final isEnabled = provider.enabled;
        final macroCount = provider.macros.length;
        final pageCount = provider.pages.length;

        return Tooltip(
          message: 'Macro Controls\n'
              '${isEnabled ? "Enabled" : "Disabled"}\n'
              '$macroCount macros, $pageCount pages',
          child: GestureDetector(
            onTap: provider.toggleEnabled,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isEnabled
                    ? const Color(0xFF1ABC9C).withValues(alpha: 0.15)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isEnabled
                      ? const Color(0xFF1ABC9C)
                      : FluxForgeTheme.borderSubtle,
                  width: isEnabled ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune,
                    size: 14,
                    color: isEnabled
                        ? const Color(0xFF1ABC9C)
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Macro',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isEnabled
                          ? const Color(0xFF1ABC9C)
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
