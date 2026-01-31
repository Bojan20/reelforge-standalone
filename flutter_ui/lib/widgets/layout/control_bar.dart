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
// P3 Cloud Services
import '../../services/cloud_sync_service.dart';
import '../../services/collaboration_service.dart';
import '../../services/crdt_sync_service.dart';

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

  // Navigation callbacks
  final VoidCallback? onBackToLauncher;
  final VoidCallback? onBackToMiddleware; // For Slot mode only

  // P3 Cloud callbacks
  final VoidCallback? onCloudSyncTap;
  final VoidCallback? onCollaborationTap;
  final VoidCallback? onCrdtSyncTap;

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
    this.onBackToLauncher,
    this.onBackToMiddleware,
    this.onCloudSyncTap,
    this.onCollaborationTap,
    this.onCrdtSyncTap,
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
    // Get feature flags for current mode
    final features = getModeLayoutConfig(widget.editorMode).features;

    return Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1e1e28),
              const Color(0xFF141418),
            ],
          ),
          border: Border(
            bottom: BorderSide(color: const Color(0xFF2a2a35), width: 1),
            top: BorderSide(color: const Color(0xFF3a3a45).withValues(alpha: 0.5), width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 1400;
            final isVeryCompact = constraints.maxWidth < 1100;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  // ═══════════════════════════════════════════════════════════
                  // LEFT SECTION - scrollable, same order as Glass
                  // ═══════════════════════════════════════════════════════════
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Logo
                          _Logo(),
                          const SizedBox(width: 8),

                          // Back button - context-aware navigation
                          if (widget.editorMode == EditorMode.slot && widget.onBackToMiddleware != null)
                            _BackButton(
                              label: 'Middleware',
                              accentColor: FluxForgeTheme.accentOrange,
                              onTap: widget.onBackToMiddleware!,
                            )
                          else if (widget.onBackToLauncher != null)
                            _BackButton(
                              label: 'Launcher',
                              accentColor: widget.editorMode == EditorMode.daw
                                  ? FluxForgeTheme.accentBlue
                                  : FluxForgeTheme.accentOrange,
                              onTap: widget.onBackToLauncher!,
                            ),

                          if (widget.onBackToLauncher != null || widget.onBackToMiddleware != null)
                            const SizedBox(width: 8),

                          // Note: Menu bar moved to native macOS menu bar
                          // See AppDelegate.swift for native menu implementation

                          // Mode Switcher
                          if (widget.onEditorModeChange != null)
                            _ModeSwitcher(
                              mode: widget.editorMode,
                              onChange: widget.onEditorModeChange!,
                              compact: isCompact,
                            ),

                          _Divider(),

                          // Transport Controls (just buttons, no loop/metro)
                          if (features.showTransport)
                            _TransportButtons(
                              isPlaying: widget.isPlaying,
                              isRecording: widget.isRecording,
                              transportDisabled: widget.transportDisabled,
                              onPlay: widget.onPlay,
                              onStop: widget.onStop,
                              onRecord: widget.onRecord,
                              onRewind: widget.onRewind,
                              onForward: widget.onForward,
                            ),

                          // Loop & Metronome (same as Glass)
                          if (!isVeryCompact && features.showTransport) ...[
                            _Divider(),
                            _IconBtn(
                              icon: Icons.repeat,
                              isActive: widget.loopEnabled,
                              activeColor: FluxForgeTheme.accentCyan,
                              onTap: widget.onLoopToggle,
                              tooltip: 'Loop',
                            ),
                            _IconBtn(
                              icon: Icons.timer,
                              isActive: widget.metronomeEnabled,
                              activeColor: FluxForgeTheme.accentOrange,
                              onTap: widget.onMetronomeToggle,
                              tooltip: 'Metronome',
                            ),
                          ],

                          _Divider(),

                          // Pro Edit Modes
                          if (!isVeryCompact && features.showTransport) _ProEditModes(),

                          // Smart Tool
                          if (!isVeryCompact && features.showTransport) _SmartToolButton(),

                          // Keyboard Focus
                          if (!isVeryCompact && features.showTransport) _KeyboardFocusButton(),

                          if (!isVeryCompact && features.showTransport) _Divider(),

                          // Tempo Display (same as Glass)
                          if (!isVeryCompact && features.showTransport)
                            _TempoDisplay(
                              tempo: widget.tempo,
                              onTempoChange: widget.onTempoChange,
                            ),

                          // Time Signature (same as Glass)
                          if (!isCompact && features.showTransport)
                            _TimeSignatureDisplay(timeSignature: widget.timeSignature),

                          // Time Display
                          if (features.showTimecode)
                            _TimeDisplay(
                              formattedTime: _formattedTime,
                              modeLabel: _timeModeLabel,
                              onTap: widget.onTimeDisplayModeChange,
                            ),

                          // Project Info (same as Glass)
                          if (!isCompact)
                            _ProjectInfo(
                              name: widget.projectName,
                              onSave: widget.onSave,
                            ),

                          // Middleware mode indicator
                          if (!features.showTransport)
                            _ModeStatusIndicator(mode: widget.editorMode),
                        ],
                      ),
                    ),
                  ),

                  // ═══════════════════════════════════════════════════════════
                  // RIGHT SECTION - fixed, same as Glass
                  // ═══════════════════════════════════════════════════════════
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Zone Toggles
                      if (!isVeryCompact)
                        _ZoneToggles(
                          onToggleLeft: widget.onToggleLeftZone,
                          onToggleLower: widget.onToggleLowerZone,
                          onToggleRight: widget.onToggleRightZone,
                        ),

                      // PDC Indicator (always show - 0ms when no plugins)
                      if (!isVeryCompact)
                        _PdcButton(
                          latencyMs: widget.pdcLatencyMs,
                          enabled: widget.pdcEnabled,
                          onTap: widget.onPdcTap,
                        ),

                      // P3 Cloud Status Badges
                      if (!isVeryCompact)
                        _CloudStatusBadges(
                          onCloudSyncTap: widget.onCloudSyncTap,
                          onCollaborationTap: widget.onCollaborationTap,
                          onCrdtSyncTap: widget.onCrdtSyncTap,
                        ),

                      // System Meters
                      if (!isVeryCompact)
                        _SystemMeters(
                          cpuUsage: widget.cpuUsage,
                          memoryUsage: widget.memoryUsage,
                          cpuColor: _cpuColor,
                        ),
                    ],
                  ),
                ],
              ),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [FluxForgeTheme.accentBlue, FluxForgeTheme.accentCyan],
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: FluxForgeTheme.accentBlue.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'F',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MENU BAR
// ════════════════════════════════════════════════════════════════════════════

// Note: Menu bar has been moved to native macOS menu bar
// See AppDelegate.swift for File/Edit/View/Project/Studio menus

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

class _TransportBtn extends StatefulWidget {
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
  State<_TransportBtn> createState() => _TransportBtnState();
}

class _TransportBtnState extends State<_TransportBtn> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive
        ? (widget.activeColor ?? FluxForgeTheme.accentBlue)
        : (_isHovered ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Opacity(
          opacity: widget.disabled ? 0.4 : 1,
          child: GestureDetector(
            onTap: widget.disabled ? null : widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 30,
              height: 30,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                gradient: widget.isActive
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          color.withValues(alpha: 0.3),
                          color.withValues(alpha: 0.15),
                        ],
                      )
                    : (_isHovered
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              FluxForgeTheme.bgSurface.withValues(alpha: 0.8),
                              FluxForgeTheme.bgMid.withValues(alpha: 0.5),
                            ],
                          )
                        : null),
                color: (!widget.isActive && !_isHovered) ? Colors.transparent : null,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: widget.isActive
                      ? color.withValues(alpha: 0.5)
                      : (_isHovered
                          ? FluxForgeTheme.borderSubtle
                          : Colors.transparent),
                ),
                boxShadow: widget.isActive
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.3),
                          blurRadius: 6,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  widget.icon,
                  style: TextStyle(fontSize: 13, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PDC BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _PdcButton extends StatelessWidget {
  final double latencyMs;
  final bool enabled;
  final VoidCallback? onTap;

  const _PdcButton({
    required this.latencyMs,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasHighLatency = latencyMs > 10; // >10ms is noticeable
    final color = !enabled
        ? FluxForgeTheme.textTertiary
        : hasHighLatency
            ? FluxForgeTheme.warningOrange
            : FluxForgeTheme.accentGreen;

    return Tooltip(
      message: 'Plugin Delay Compensation\n'
          '${latencyMs.toStringAsFixed(2)}ms\n'
          '${enabled ? "Enabled" : "Disabled"} - Click to toggle',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PDC',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${latencyMs.toStringAsFixed(1)}ms',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ],
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
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            FluxForgeTheme.borderSubtle.withValues(alpha: 0.1),
            FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
            FluxForgeTheme.borderSubtle.withValues(alpha: 0.1),
          ],
        ),
      ),
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
// TRANSPORT BUTTONS (Ultimate UI - separate from loop/metro)
// ════════════════════════════════════════════════════════════════════════════

class _TransportButtons extends StatelessWidget {
  final bool isPlaying;
  final bool isRecording;
  final bool transportDisabled;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;
  final VoidCallback? onRewind;
  final VoidCallback? onForward;

  const _TransportButtons({
    required this.isPlaying,
    required this.isRecording,
    required this.transportDisabled,
    this.onPlay,
    this.onStop,
    this.onRecord,
    this.onRewind,
    this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF1a1a22),
            const Color(0xFF0f0f14),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF2a2a35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: const Color(0xFF3a3a45).withValues(alpha: 0.1),
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _UltimateTransportBtn(
            icon: Icons.skip_previous,
            onPressed: onRewind,
            tooltip: 'Rewind (,)',
          ),
          _UltimateTransportBtn(
            icon: Icons.stop,
            onPressed: onStop,
            tooltip: 'Stop (.)',
          ),
          _UltimateTransportBtn(
            icon: isPlaying ? Icons.pause : Icons.play_arrow,
            onPressed: transportDisabled ? null : onPlay,
            tooltip: transportDisabled ? 'Transport disabled' : 'Play/Pause (Space)',
            isActive: isPlaying,
            activeColor: FluxForgeTheme.accentGreen,
            disabled: transportDisabled,
            large: true,
          ),
          _UltimateTransportBtn(
            icon: Icons.fiber_manual_record,
            onPressed: onRecord,
            tooltip: 'Record (R)',
            isActive: isRecording,
            activeColor: FluxForgeTheme.errorRed,
          ),
          _UltimateTransportBtn(
            icon: Icons.skip_next,
            onPressed: onForward,
            tooltip: 'Forward (/)',
          ),
        ],
      ),
    );
  }
}

class _UltimateTransportBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool isActive;
  final Color? activeColor;
  final bool disabled;
  final bool large;

  const _UltimateTransportBtn({
    required this.icon,
    this.onPressed,
    required this.tooltip,
    this.isActive = false,
    this.activeColor,
    this.disabled = false,
    this.large = false,
  });

  @override
  State<_UltimateTransportBtn> createState() => _UltimateTransportBtnState();
}

class _UltimateTransportBtnState extends State<_UltimateTransportBtn>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _blinkAnimation = Tween<double>(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );
    _updateBlinking();
  }

  @override
  void didUpdateWidget(_UltimateTransportBtn oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateBlinking();
  }

  void _updateBlinking() {
    // Only blink for record button when active
    if (widget.isActive && widget.icon == Icons.fiber_manual_record) {
      _blinkController.repeat(reverse: true);
    } else {
      _blinkController.stop();
      _blinkController.value = 0;
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive
        ? (widget.activeColor ?? FluxForgeTheme.accentBlue)
        : (_isHovered ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary);

    final size = widget.large ? 36.0 : 30.0;
    final iconSize = widget.large ? 18.0 : 14.0;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.disabled ? null : widget.onPressed,
          child: Opacity(
            opacity: widget.disabled ? 0.4 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: size,
              height: size,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                gradient: widget.isActive
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          color.withValues(alpha: 0.4),
                          color.withValues(alpha: 0.2),
                        ],
                      )
                    : (_isHovered || _isPressed
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFF2a2a35),
                              const Color(0xFF1a1a22),
                            ],
                          )
                        : null),
                color: (!widget.isActive && !_isHovered && !_isPressed)
                    ? Colors.transparent
                    : null,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: widget.isActive
                      ? color.withValues(alpha: 0.6)
                      : (_isHovered
                          ? FluxForgeTheme.borderSubtle.withValues(alpha: 0.6)
                          : Colors.transparent),
                  width: widget.isActive ? 1.5 : 1,
                ),
                boxShadow: widget.isActive
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                        BoxShadow(
                          color: color.withValues(alpha: 0.3),
                          blurRadius: 2,
                          spreadRadius: 0,
                        ),
                      ]
                    : (_isPressed
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null),
              ),
              child: Center(
                child: AnimatedBuilder(
                  animation: _blinkAnimation,
                  builder: (context, child) {
                    final isBlinking = widget.isActive && widget.icon == Icons.fiber_manual_record;
                    return Opacity(
                      opacity: isBlinking ? _blinkAnimation.value : 1.0,
                      child: Icon(
                        widget.icon,
                        size: iconSize,
                        color: color,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ICON BUTTON (Ultimate UI - for loop/metronome)
// ════════════════════════════════════════════════════════════════════════════

class _IconBtn extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;
  final String tooltip;

  const _IconBtn({
    required this.icon,
    required this.isActive,
    required this.activeColor,
    this.onTap,
    required this.tooltip,
  });

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive
        ? widget.activeColor
        : (_isHovered ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              gradient: widget.isActive
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        widget.activeColor.withValues(alpha: 0.35),
                        widget.activeColor.withValues(alpha: 0.15),
                      ],
                    )
                  : (_isHovered
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF2a2a35),
                            const Color(0xFF1a1a22),
                          ],
                        )
                      : null),
              color: (!widget.isActive && !_isHovered) ? Colors.transparent : null,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.isActive
                    ? widget.activeColor.withValues(alpha: 0.6)
                    : (_isHovered
                        ? FluxForgeTheme.borderSubtle
                        : Colors.transparent),
                width: widget.isActive ? 1.5 : 1,
              ),
              boxShadow: widget.isActive
                  ? [
                      BoxShadow(
                        color: widget.activeColor.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: 16,
                color: color,
              ),
            ),
          ),
        ),
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

class _TimeDisplay extends StatefulWidget {
  final String formattedTime;
  final String modeLabel;
  final VoidCallback? onTap;

  const _TimeDisplay(
      {required this.formattedTime, required this.modeLabel, this.onTap});

  @override
  State<_TimeDisplay> createState() => _TimeDisplayState();
}

class _TimeDisplayState extends State<_TimeDisplay> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: 'Click to change display mode',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  FluxForgeTheme.bgDeepest,
                  FluxForgeTheme.bgDeepest.withValues(alpha: 0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isHovered
                    ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                    : FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
                if (_isHovered)
                  BoxShadow(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
              ],
            ),
            child: Row(
              children: [
                Text(
                  widget.formattedTime,
                  style: FluxForgeTheme.monoSmall.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: FluxForgeTheme.accentCyan,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    widget.modeLabel,
                    style: TextStyle(
                      color: FluxForgeTheme.accentBlue,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onToggleLeft != null)
          _ZoneBtn(icon: '◀', onPressed: onToggleLeft!, tooltip: 'Toggle Left Zone (Ctrl+L)'),
        if (onToggleLower != null)
          _ZoneBtn(icon: '▼', onPressed: onToggleLower!, tooltip: 'Toggle Lower Zone (Ctrl+B)'),
        if (onToggleRight != null)
          _ZoneBtn(icon: '▶', onPressed: onToggleRight!, tooltip: 'Toggle Right Zone (Ctrl+R)'),
      ],
    );
  }
}

class _ZoneBtn extends StatefulWidget {
  final String icon;
  final VoidCallback onPressed;
  final String tooltip;
  const _ZoneBtn(
      {required this.icon, required this.onPressed, required this.tooltip});

  @override
  State<_ZoneBtn> createState() => _ZoneBtnState();
}

class _ZoneBtnState extends State<_ZoneBtn> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 26,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: _isHovered
                  ? FluxForgeTheme.bgSurface.withValues(alpha: 0.6)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _isHovered
                    ? FluxForgeTheme.borderSubtle
                    : Colors.transparent,
              ),
            ),
            child: Center(
              child: Text(
                widget.icon,
                style: TextStyle(
                  fontSize: 10,
                  color: _isHovered
                      ? FluxForgeTheme.textPrimary
                      : FluxForgeTheme.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// P3 CLOUD STATUS BADGES
// ════════════════════════════════════════════════════════════════════════════

class _CloudStatusBadges extends StatelessWidget {
  final VoidCallback? onCloudSyncTap;
  final VoidCallback? onCollaborationTap;
  final VoidCallback? onCrdtSyncTap;

  const _CloudStatusBadges({
    this.onCloudSyncTap,
    this.onCollaborationTap,
    this.onCrdtSyncTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cloud Sync Status
          ListenableBuilder(
            listenable: CloudSyncService.instance,
            builder: (context, _) {
              final service = CloudSyncService.instance;
              return _CloudBadge(
                icon: Icons.cloud,
                label: 'SYNC',
                isActive: service.isEnabled,
                isSyncing: service.isSyncing,
                color: service.lastSyncTime != null
                    ? FluxForgeTheme.accentGreen
                    : FluxForgeTheme.textTertiary,
                onTap: onCloudSyncTap,
                tooltip: service.isSyncing
                    ? 'Syncing...'
                    : service.lastSyncTime != null
                        ? 'Last sync: ${_formatTime(service.lastSyncTime!)}'
                        : 'Cloud sync disabled',
              );
            },
          ),
          const SizedBox(width: 4),
          // Collaboration Status
          ListenableBuilder(
            listenable: CollaborationService.instance,
            builder: (context, _) {
              final service = CollaborationService.instance;
              final peerCount = service.connectedPeers.length;
              return _CloudBadge(
                icon: Icons.people,
                label: peerCount > 0 ? '$peerCount' : 'COLLAB',
                isActive: service.isConnected,
                isSyncing: false,
                color: service.isConnected
                    ? FluxForgeTheme.accentCyan
                    : FluxForgeTheme.textTertiary,
                onTap: onCollaborationTap,
                tooltip: service.isConnected
                    ? '$peerCount peer${peerCount != 1 ? 's' : ''} connected'
                    : 'Collaboration offline',
              );
            },
          ),
          const SizedBox(width: 4),
          // CRDT Sync Status
          ListenableBuilder(
            listenable: CrdtSyncService.instance,
            builder: (context, _) {
              final service = CrdtSyncService.instance;
              final opCount = service.pendingOperations.length;
              return _CloudBadge(
                icon: Icons.sync_alt,
                label: opCount > 0 ? '$opCount' : 'CRDT',
                isActive: service.isConnected,
                isSyncing: service.isSyncing,
                color: service.hasConflicts
                    ? FluxForgeTheme.warningOrange
                    : service.isConnected
                        ? FluxForgeTheme.accentBlue
                        : FluxForgeTheme.textTertiary,
                onTap: onCrdtSyncTap,
                tooltip: service.hasConflicts
                    ? '${service.conflicts.length} conflict${service.conflicts.length != 1 ? 's' : ''}'
                    : service.isSyncing
                        ? 'Syncing operations...'
                        : service.isConnected
                            ? 'CRDT sync active'
                            : 'CRDT sync offline',
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _CloudBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isSyncing;
  final Color color;
  final VoidCallback? onTap;
  final String tooltip;

  const _CloudBadge({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isSyncing,
    required this.color,
    this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isActive
                ? color.withValues(alpha: 0.15)
                : FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive
                  ? color.withValues(alpha: 0.4)
                  : FluxForgeTheme.borderSubtle.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSyncing)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                )
              else
                Icon(
                  icon,
                  size: 10,
                  color: color,
                ),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MeterBar(label: 'CPU', value: cpuUsage, color: cpuColor),
          const SizedBox(width: 8),
          _MeterBar(label: 'MEM', value: memoryUsage, color: FluxForgeTheme.accentBlue),
        ],
      ),
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
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 40,
          height: 6,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (value / 100).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.7),
                      color,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 3,
                    ),
                  ],
                ),
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

// ════════════════════════════════════════════════════════════════════════════
// MORE TOOLS MENU (Dropdown for advanced tools)
// ════════════════════════════════════════════════════════════════════════════

class _MoreToolsMenu extends StatefulWidget {
  final bool isCompact;

  const _MoreToolsMenu({required this.isCompact});

  @override
  State<_MoreToolsMenu> createState() => _MoreToolsMenuState();
}

class _MoreToolsMenuState extends State<_MoreToolsMenu> {
  bool _isOpen = false;
  final _menuKey = GlobalKey();

  void _toggleMenu() {
    setState(() => _isOpen = !_isOpen);
    if (_isOpen) {
      _showMenu();
    }
  }

  void _showMenu() {
    final RenderBox button = _menuKey.currentContext!.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + button.size.height + 4,
        position.dx + button.size.width,
        position.dy + button.size.height + 300,
      ),
      color: FluxForgeTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      items: [
        // Edit tools section
        _buildMenuItem('razor', 'Razor Edit', Icons.content_cut, context.read<RazorEditProvider>().enabled),
        const PopupMenuDivider(),
        // Track features section
        _buildMenuItem('arranger', 'Arranger Track', Icons.view_week, context.read<ArrangerTrackProvider>().enabled),
        _buildMenuItem('chord', 'Chord Track', Icons.music_note, context.read<ChordTrackProvider>().enabled),
        _buildMenuItem('scale', 'Scale Assistant', Icons.piano, context.read<ScaleAssistantProvider>().showScaleNotes),
        _buildMenuItem('groove', 'Groove Quantize', Icons.grid_on, context.read<GrooveQuantizeProvider>().enabled),
        _buildMenuItem('versions', 'Track Versions', Icons.layers, context.read<TrackVersionsProvider>().showVersionLane),
        _buildMenuItem('macro', 'Macro Controls', Icons.tune, context.read<MacroControlProvider>().enabled),
      ],
    ).then((value) {
      setState(() => _isOpen = false);
      if (value != null) {
        _handleMenuAction(value);
      }
    });
  }

  PopupMenuItem<String> _buildMenuItem(String id, String label, IconData icon, bool isActive) {
    return PopupMenuItem<String>(
      value: id,
      height: 36,
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          if (isActive)
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'razor':
        final razor = context.read<RazorEditProvider>();
        razor.setEnabled(!razor.enabled);
        break;
      case 'arranger':
        context.read<ArrangerTrackProvider>().toggleEnabled();
        break;
      case 'chord':
        context.read<ChordTrackProvider>().toggleEnabled();
        break;
      case 'scale':
        context.read<ScaleAssistantProvider>().setShowScaleNotes(
            !context.read<ScaleAssistantProvider>().showScaleNotes);
        break;
      case 'groove':
        context.read<GrooveQuantizeProvider>().toggleEnabled();
        break;
      case 'versions':
        context.read<TrackVersionsProvider>().toggleShowVersionLane();
        break;
      case 'macro':
        context.read<MacroControlProvider>().toggleEnabled();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if any tool is active
    final hasActive = context.watch<RazorEditProvider>().enabled ||
        context.watch<ArrangerTrackProvider>().enabled ||
        context.watch<ChordTrackProvider>().enabled ||
        context.watch<ScaleAssistantProvider>().showScaleNotes ||
        context.watch<GrooveQuantizeProvider>().enabled ||
        context.watch<TrackVersionsProvider>().showVersionLane ||
        context.watch<MacroControlProvider>().enabled;

    return Tooltip(
      message: 'Advanced Tools',
      child: GestureDetector(
        key: _menuKey,
        onTap: _toggleMenu,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: _isOpen
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
                : hasActive
                    ? FluxForgeTheme.accentBlue.withValues(alpha: 0.1)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: hasActive
                  ? FluxForgeTheme.accentBlue.withValues(alpha: 0.4)
                  : FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.more_horiz,
                size: 16,
                color: hasActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
              ),
              if (hasActive) ...[
                const SizedBox(width: 4),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BACK BUTTON (Navigation to Launcher/Middleware)
// ════════════════════════════════════════════════════════════════════════════

class _BackButton extends StatefulWidget {
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  const _BackButton({
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: _isHovered ? 10 : 8,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.accentColor.withValues(alpha: 0.15)
                : FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isHovered
                  ? widget.accentColor.withValues(alpha: 0.5)
                  : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back_rounded,
                size: 12,
                color: _isHovered
                    ? widget.accentColor
                    : FluxForgeTheme.textSecondary,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 150),
                child: _isHovered
                    ? Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: widget.accentColor,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
