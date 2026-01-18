/// Glass Control Bar
///
/// Liquid Glass styled top control bar:
/// - Logo with glass effect
/// - Menu bar with glass dropdowns
/// - Mode switcher with glass pills
/// - Transport controls with glass buttons
/// - Tempo/Time signature display
/// - Zone toggles
/// - System meters

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../models/layout_models.dart';
import '../../providers/edit_mode_pro_provider.dart';
import '../../providers/smart_tool_provider.dart';
import '../../providers/keyboard_focus_provider.dart';
import '../../providers/theme_mode_provider.dart';
import 'glass_widgets.dart';

// ==============================================================================
// GLASS CONTROL BAR
// ==============================================================================

class GlassControlBar extends StatelessWidget {
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

  const GlassControlBar({
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
  });

  String get _formattedTime {
    switch (timeDisplayMode) {
      case TimeDisplayMode.bars:
        return _formatBarsBeats();
      case TimeDisplayMode.timecode:
        return _formatTimecode();
      case TimeDisplayMode.samples:
        return _formatSamples();
    }
  }

  String _formatBarsBeats() {
    final beatsPerSecond = tempo / 60;
    final totalBeats = currentTime * beatsPerSecond;
    final beatsPerBar = timeSignature.numerator;
    final bars = (totalBeats / beatsPerBar).floor() + 1;
    final beats = (totalBeats % beatsPerBar).floor() + 1;
    final ticks = ((totalBeats % 1) * 480).floor();
    return '${bars.toString().padLeft(3, ' ')}.${beats}.${ticks.toString().padLeft(3, '0')}';
  }

  String _formatTimecode() {
    final hrs = (currentTime / 3600).floor();
    final mins = ((currentTime % 3600) / 60).floor();
    final secs = (currentTime % 60).floor();
    final frames = ((currentTime % 1) * 30).floor();
    return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
  }

  String _formatSamples() {
    final samples = (currentTime * 48000).floor();
    return samples.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  Color get _cpuColor {
    if (cpuUsage > 80) return LiquidGlassTheme.accentRed;
    if (cpuUsage > 60) return LiquidGlassTheme.accentOrange;
    return LiquidGlassTheme.accentGreen;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurAmount,
          sigmaY: LiquidGlassTheme.blurAmount,
        ),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.06),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          child: Stack(
            children: [
              // Specular highlight
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.4),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              // Content
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 1400;
                  final isVeryCompact = constraints.maxWidth < 1100;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        // Left section - scrollable if needed
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Logo
                                _GlassLogo(),
                                const SizedBox(width: 12),

                                // Menu Bar
                                _GlassMenuBar(callbacks: menuCallbacks),
                                const SizedBox(width: 8),

                                // Mode Switcher
                                if (onEditorModeChange != null)
                                  _GlassModeSwitcher(
                                    mode: editorMode,
                                    onChange: onEditorModeChange!,
                                    compact: isCompact,
                                  ),

                                _GlassDivider(),

                                // Transport Controls
                                _GlassTransportButtons(
                                  isPlaying: isPlaying,
                                  isRecording: isRecording,
                                  disabled: transportDisabled,
                                  onPlay: onPlay,
                                  onStop: onStop,
                                  onRecord: onRecord,
                                  onRewind: onRewind,
                                  onForward: onForward,
                                ),

                                if (!isVeryCompact) ...[
                                  _GlassDivider(),

                                  // Loop & Metronome
                                  GlassIconButton(
                                    icon: Icons.repeat,
                                    isActive: loopEnabled,
                                    activeColor: LiquidGlassTheme.accentCyan,
                                    onTap: onLoopToggle,
                                    tooltip: 'Loop',
                                    size: 28,
                                  ),
                                  GlassIconButton(
                                    icon: Icons.timer,
                                    isActive: metronomeEnabled,
                                    activeColor: LiquidGlassTheme.accentOrange,
                                    onTap: onMetronomeToggle,
                                    tooltip: 'Metronome',
                                    size: 28,
                                  ),
                                ],

                                _GlassDivider(),

                                // Pro Edit Modes
                                if (!isVeryCompact) _GlassProEditModes(),

                                // Smart Tool
                                if (!isVeryCompact) _GlassSmartToolButton(),

                                // Keyboard Focus
                                if (!isVeryCompact) _GlassKeyboardFocusButton(),

                                if (!isVeryCompact) _GlassDivider(),

                                // Tempo
                                if (!isVeryCompact)
                                  _GlassTempoDisplay(
                                    tempo: tempo,
                                    onTempoChange: onTempoChange,
                                  ),

                                // Time Signature
                                if (!isCompact)
                                  _GlassTimeSignature(timeSignature: timeSignature),

                                // Time Display
                                _GlassTimeDisplay(
                                  formattedTime: _formattedTime,
                                  isPlaying: isPlaying,
                                  onTap: onTimeDisplayModeChange,
                                ),

                                // Project Info
                                if (!isCompact)
                                  _GlassProjectInfo(
                                    name: projectName,
                                    onSave: onSave,
                                  ),
                              ],
                            ),
                          ),
                        ),

                        // Right section - fixed, never overflows
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Zone Toggles
                            if (!isVeryCompact)
                              _GlassZoneToggles(
                                onToggleLeft: onToggleLeftZone,
                                onToggleLower: onToggleLowerZone,
                                onToggleRight: onToggleRightZone,
                              ),

                            // Theme Mode Toggle
                            _GlassThemeModeToggle(compact: isCompact),

                            // System Meters
                            if (!isVeryCompact)
                              _GlassSystemMeters(
                                cpuUsage: cpuUsage,
                                memoryUsage: memoryUsage,
                                cpuColor: _cpuColor,
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS LOGO
// ==============================================================================

class _GlassLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                LiquidGlassTheme.accentBlue,
                LiquidGlassTheme.accentCyan,
              ],
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.4),
                blurRadius: 12,
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
        const SizedBox(width: 10),
        Text(
          'FluxForge',
          style: TextStyle(
            color: LiquidGlassTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ==============================================================================
// GLASS MENU BAR
// ==============================================================================

class _GlassMenuItem {
  final String label;
  final String shortcut;
  final VoidCallback? callback;
  const _GlassMenuItem(this.label, this.shortcut, this.callback);
}

class _GlassMenuBar extends StatelessWidget {
  final MenuCallbacks? callbacks;

  const _GlassMenuBar({this.callbacks});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassPopupMenuButton(
          label: 'File',
          items: [
            _GlassMenuItem('New Project', '⌘N', callbacks?.onNewProject),
            _GlassMenuItem('Open Project...', '⌘O', callbacks?.onOpenProject),
            null,
            _GlassMenuItem('Save', '⌘S', callbacks?.onSaveProject),
            _GlassMenuItem('Save As...', '⇧⌘S', callbacks?.onSaveProjectAs),
            null,
            _GlassMenuItem('Import Routes JSON...', '⌘I', callbacks?.onImportJSON),
            _GlassMenuItem('Export Routes JSON...', '⇧⌘E', callbacks?.onExportJSON),
            null,
            _GlassMenuItem('Import Audio Folder...', '', callbacks?.onImportAudioFolder),
            _GlassMenuItem('Import Audio Files...', '⇧⌘I', callbacks?.onImportAudioFiles),
            null,
            _GlassMenuItem('Export Audio...', '⌥⌘E', callbacks?.onExportAudio),
          ],
        ),
        _GlassPopupMenuButton(
          label: 'Edit',
          items: [
            _GlassMenuItem('Undo', '⌘Z', callbacks?.onUndo),
            _GlassMenuItem('Redo', '⇧⌘Z', callbacks?.onRedo),
            null,
            _GlassMenuItem('Cut', '⌘X', callbacks?.onCut),
            _GlassMenuItem('Copy', '⌘C', callbacks?.onCopy),
            _GlassMenuItem('Paste', '⌘V', callbacks?.onPaste),
            _GlassMenuItem('Delete', '⌫', callbacks?.onDelete),
            null,
            _GlassMenuItem('Select All', '⌘A', callbacks?.onSelectAll),
          ],
        ),
        _GlassPopupMenuButton(
          label: 'View',
          items: [
            _GlassMenuItem('Toggle Left Panel', '⌘L', callbacks?.onToggleLeftPanel),
            _GlassMenuItem('Toggle Right Panel', '⌘R', callbacks?.onToggleRightPanel),
            _GlassMenuItem('Toggle Lower Panel', '⌘B', callbacks?.onToggleLowerPanel),
            null,
            _GlassMenuItem('Reset Layout', '', callbacks?.onResetLayout),
          ],
        ),
        _GlassPopupMenuButton(
          label: 'Project',
          items: [
            _GlassMenuItem('Project Settings...', '⌘,', callbacks?.onProjectSettings),
            null,
            _GlassMenuItem('Validate Project', '⇧⌘V', callbacks?.onValidateProject),
            _GlassMenuItem('Build Project', '⌘B', callbacks?.onBuildProject),
          ],
        ),
      ],
    );
  }
}

class _GlassPopupMenuButton extends StatefulWidget {
  final String label;
  final List<_GlassMenuItem?> items;

  const _GlassPopupMenuButton({
    required this.label,
    required this.items,
  });

  @override
  State<_GlassPopupMenuButton> createState() => _GlassPopupMenuButtonState();
}

class _GlassPopupMenuButtonState extends State<_GlassPopupMenuButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      offset: const Offset(0, 40),
      color: const Color(0xFF1a1a24),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      tooltip: '',
      position: PopupMenuPosition.under,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: LiquidGlassTheme.animFast,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _isHovered
                  ? LiquidGlassTheme.textPrimary
                  : LiquidGlassTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      itemBuilder: (context) {
        final menuItems = <PopupMenuEntry<int>>[];
        for (var i = 0; i < widget.items.length; i++) {
          final item = widget.items[i];
          if (item == null) {
            menuItems.add(PopupMenuDivider(
              height: 1,
            ));
          } else {
            menuItems.add(PopupMenuItem<int>(
              value: i,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: LiquidGlassTheme.textPrimary,
                    ),
                  ),
                  if (item.shortcut.isNotEmpty)
                    Text(
                      item.shortcut,
                      style: TextStyle(
                        fontSize: 11,
                        color: LiquidGlassTheme.textTertiary,
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

// ==============================================================================
// GLASS MODE SWITCHER
// ==============================================================================

class _GlassModeSwitcher extends StatelessWidget {
  final EditorMode mode;
  final ValueChanged<EditorMode> onChange;
  final bool compact;

  const _GlassModeSwitcher({
    required this.mode,
    required this.onChange,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GlassModeButton(
            label: 'DAW',
            icon: Icons.music_note,
            isActive: mode == EditorMode.daw,
            color: LiquidGlassTheme.accentBlue,
            onTap: () => onChange(EditorMode.daw),
            compact: compact,
          ),
          _GlassModeButton(
            label: 'MID',
            icon: Icons.route,
            isActive: mode == EditorMode.middleware,
            color: LiquidGlassTheme.accentOrange,
            onTap: () => onChange(EditorMode.middleware),
            compact: compact,
          ),
          _GlassSlotLabButton(
            isActive: mode == EditorMode.slot,
            onTap: () => onChange(EditorMode.slot),
            compact: compact,
          ),
        ],
      ),
    );
  }
}

class _GlassModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;
  final bool compact;

  const _GlassModeButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.color,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: LiquidGlassTheme.animFast,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: isActive
              ? Border.all(color: color.withValues(alpha: 0.5))
              : null,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? color : LiquidGlassTheme.textTertiary,
            ),
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? color : LiquidGlassTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// SLOT LAB BUTTON - Premium casino-style button
// ==============================================================================

class _GlassSlotLabButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool compact;

  const _GlassSlotLabButton({
    required this.isActive,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // Premium gold/amber gradient for slot lab
    const goldLight = Color(0xFFFFD700);
    const goldDark = Color(0xFFFF8C00);
    const amberGlow = Color(0xFFFFAA00);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: LiquidGlassTheme.animFast,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [goldDark, goldLight],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                )
              : null,
          color: isActive ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? goldLight.withValues(alpha: 0.8)
                : amberGlow.withValues(alpha: 0.3),
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: amberGlow.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: goldLight.withValues(alpha: 0.2),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Slot machine icon
            Icon(
              Icons.casino,
              size: compact ? 14 : 16,
              color: isActive ? Colors.black87 : amberGlow,
            ),
            const SizedBox(width: 6),
            // FLUXFORGE SLOT LAB text
            Text(
              compact ? 'SLOT LAB' : 'FLUXFORGE SLOT LAB',
              style: TextStyle(
                color: isActive ? Colors.black87 : amberGlow,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS TRANSPORT BUTTONS
// ==============================================================================

class _GlassTransportButtons extends StatelessWidget {
  final bool isPlaying;
  final bool isRecording;
  final bool disabled;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;
  final VoidCallback? onRewind;
  final VoidCallback? onForward;

  const _GlassTransportButtons({
    required this.isPlaying,
    required this.isRecording,
    required this.disabled,
    this.onPlay,
    this.onStop,
    this.onRecord,
    this.onRewind,
    this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassIconButton(
          icon: Icons.skip_previous,
          onTap: onRewind,
          tooltip: 'Rewind',
          size: 32,
        ),
        const SizedBox(width: 2),
        GlassIconButton(
          icon: Icons.stop,
          onTap: onStop,
          tooltip: 'Stop',
          size: 32,
        ),
        const SizedBox(width: 2),
        GlassIconButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          onTap: disabled ? null : onPlay,
          isActive: isPlaying,
          activeColor: LiquidGlassTheme.accentGreen,
          tooltip: isPlaying ? 'Pause' : 'Play',
          size: 40,
        ),
        const SizedBox(width: 2),
        GlassIconButton(
          icon: Icons.fiber_manual_record,
          onTap: onRecord,
          isActive: isRecording,
          activeColor: LiquidGlassTheme.accentRed,
          tooltip: 'Record',
          size: 32,
        ),
        const SizedBox(width: 2),
        GlassIconButton(
          icon: Icons.skip_next,
          onTap: onForward,
          tooltip: 'Forward',
          size: 32,
        ),
      ],
    );
  }
}

// ==============================================================================
// GLASS PRO EDIT MODES
// ==============================================================================

class _GlassProEditModes extends StatelessWidget {
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
                message: '${config.name}\n${config.description}',
                child: GestureDetector(
                  onTap: () => provider.setMode(mode),
                  child: AnimatedContainer(
                    duration: LiquidGlassTheme.animFast,
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? config.color.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? config.color.withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: config.color.withValues(alpha: 0.3),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      config.icon,
                      size: 14,
                      color: isSelected
                          ? config.color
                          : LiquidGlassTheme.textTertiary,
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

// ==============================================================================
// GLASS SMART TOOL BUTTON
// ==============================================================================

class _GlassSmartToolButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SmartToolProvider>(
      builder: (context, provider, _) {
        final isActive = provider.enabled;

        return Tooltip(
          message: 'Smart Tool',
          child: GestureDetector(
            onTap: provider.toggle,
            child: AnimatedContainer(
              duration: LiquidGlassTheme.animFast,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? LiquidGlassTheme.accentBlue.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isActive
                      ? LiquidGlassTheme.accentBlue.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    provider.modeIcon,
                    size: 12,
                    color: isActive
                        ? LiquidGlassTheme.accentBlue
                        : LiquidGlassTheme.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Smart',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isActive
                          ? LiquidGlassTheme.accentBlue
                          : LiquidGlassTheme.textTertiary,
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

// ==============================================================================
// GLASS KEYBOARD FOCUS BUTTON
// ==============================================================================

class _GlassKeyboardFocusButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<KeyboardFocusProvider>(
      builder: (context, provider, _) {
        final isActive = provider.isCommandsMode;

        return Tooltip(
          message: isActive ? 'Commands Mode' : 'Normal Mode',
          child: GestureDetector(
            onTap: provider.toggleMode,
            child: AnimatedContainer(
              duration: LiquidGlassTheme.animFast,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? LiquidGlassTheme.accentOrange.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isActive
                      ? LiquidGlassTheme.accentOrange.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    provider.modeIcon,
                    size: 12,
                    color: isActive
                        ? LiquidGlassTheme.accentOrange
                        : LiquidGlassTheme.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isActive ? 'CMD' : 'A-Z',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isActive
                          ? LiquidGlassTheme.accentOrange
                          : LiquidGlassTheme.textTertiary,
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

// ==============================================================================
// GLASS TEMPO DISPLAY
// ==============================================================================

class _GlassTempoDisplay extends StatelessWidget {
  final double tempo;
  final ValueChanged<double>? onTempoChange;

  const _GlassTempoDisplay({
    required this.tempo,
    this.onTempoChange,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (onTempoChange != null) {
          final delta = -details.delta.dy * 0.5;
          onTempoChange!((tempo + delta).clamp(20, 999));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              tempo.toStringAsFixed(1),
              style: const TextStyle(
                color: LiquidGlassTheme.textPrimary,
                fontSize: 14,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'BPM',
              style: TextStyle(
                color: LiquidGlassTheme.textTertiary,
                fontSize: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS TIME SIGNATURE
// ==============================================================================

class _GlassTimeSignature extends StatelessWidget {
  final TimeSignature timeSignature;

  const _GlassTimeSignature({required this.timeSignature});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${timeSignature.numerator}/${timeSignature.denominator}',
        style: const TextStyle(
          color: LiquidGlassTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS TIME DISPLAY
// ==============================================================================

class _GlassTimeDisplay extends StatelessWidget {
  final String formattedTime;
  final bool isPlaying;
  final VoidCallback? onTap;

  const _GlassTimeDisplay({
    required this.formattedTime,
    required this.isPlaying,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPlaying
                ? LiquidGlassTheme.accentGreen.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.1),
          ),
          boxShadow: isPlaying
              ? [
                  BoxShadow(
                    color: LiquidGlassTheme.accentGreen.withValues(alpha: 0.15),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Text(
          formattedTime,
          style: TextStyle(
            color: isPlaying
                ? LiquidGlassTheme.accentGreen
                : LiquidGlassTheme.textPrimary,
            fontSize: 18,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS PROJECT INFO
// ==============================================================================

class _GlassProjectInfo extends StatelessWidget {
  final String name;
  final VoidCallback? onSave;

  const _GlassProjectInfo({
    required this.name,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(
              color: LiquidGlassTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          if (onSave != null) ...[
            const SizedBox(width: 8),
            GlassIconButton(
              icon: Icons.save,
              onTap: onSave,
              tooltip: 'Save',
              size: 28,
            ),
          ],
        ],
      ),
    );
  }
}

// ==============================================================================
// GLASS ZONE TOGGLES
// ==============================================================================

class _GlassZoneToggles extends StatelessWidget {
  final VoidCallback? onToggleLeft;
  final VoidCallback? onToggleLower;
  final VoidCallback? onToggleRight;

  const _GlassZoneToggles({
    this.onToggleLeft,
    this.onToggleLower,
    this.onToggleRight,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggleLeft != null)
            GlassIconButton(
              icon: Icons.chevron_left,
              onTap: onToggleLeft,
              tooltip: 'Toggle Left',
              size: 28,
            ),
          if (onToggleLower != null)
            GlassIconButton(
              icon: Icons.expand_more,
              onTap: onToggleLower,
              tooltip: 'Toggle Lower',
              size: 28,
            ),
          if (onToggleRight != null)
            GlassIconButton(
              icon: Icons.chevron_right,
              onTap: onToggleRight,
              tooltip: 'Toggle Right',
              size: 28,
            ),
        ],
      ),
    );
  }
}

// ==============================================================================
// GLASS SYSTEM METERS
// ==============================================================================

class _GlassSystemMeters extends StatelessWidget {
  final double cpuUsage;
  final double memoryUsage;
  final Color cpuColor;

  const _GlassSystemMeters({
    required this.cpuUsage,
    required this.memoryUsage,
    required this.cpuColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GlassMeterBar(
            label: 'CPU',
            value: cpuUsage,
            color: cpuColor,
          ),
          const SizedBox(width: 8),
          _GlassMeterBar(
            label: 'MEM',
            value: memoryUsage,
            color: LiquidGlassTheme.accentBlue,
          ),
        ],
      ),
    );
  }
}

class _GlassMeterBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _GlassMeterBar({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: LiquidGlassTheme.textTertiary,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 40,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
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
                      color.withValues(alpha: 0.8),
                      color,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 4,
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

// ==============================================================================
// GLASS THEME MODE TOGGLE
// ==============================================================================

class _GlassThemeModeToggle extends StatelessWidget {
  final bool compact;

  const _GlassThemeModeToggle({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeModeProvider>(
      builder: (context, provider, _) {
        final isGlass = provider.isGlassMode;

        return Tooltip(
          message: isGlass ? 'Switch to Classic Theme' : 'Switch to Glass Theme',
          child: GestureDetector(
            onTap: provider.toggleMode,
            child: AnimatedContainer(
              duration: LiquidGlassTheme.animNormal,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 8,
                vertical: 4,
              ),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                gradient: isGlass
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          LiquidGlassTheme.accentBlue.withValues(alpha: 0.3),
                          LiquidGlassTheme.accentCyan.withValues(alpha: 0.2),
                        ],
                      )
                    : null,
                color: isGlass ? null : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isGlass
                      ? LiquidGlassTheme.accentBlue.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.1),
                ),
                boxShadow: isGlass
                    ? [
                        BoxShadow(
                          color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isGlass ? Icons.blur_on : Icons.blur_off,
                    size: 12,
                    color: isGlass
                        ? LiquidGlassTheme.accentBlue
                        : LiquidGlassTheme.textTertiary,
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 4),
                    Text(
                      isGlass ? 'Glass' : 'Classic',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isGlass
                            ? LiquidGlassTheme.accentBlue
                            : LiquidGlassTheme.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ==============================================================================
// GLASS DIVIDER
// ==============================================================================

class _GlassDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.2),
            Colors.white.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
