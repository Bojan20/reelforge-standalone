/// ReelForge Control Bar
///
/// Top control bar combining logo, menu, transport, tempo, time display,
/// and system meters.

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/layout_models.dart';
import 'app_menu_bar.dart';
import 'transport_bar.dart';

/// Time formatting utilities
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

class ControlBar extends StatelessWidget {
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
  });

  String get _formattedTime {
    switch (timeDisplayMode) {
      case TimeDisplayMode.bars:
        return TimeFormatter.formatBarsBeats(currentTime, tempo, timeSignature);
      case TimeDisplayMode.timecode:
        return TimeFormatter.formatTimecode(currentTime);
      case TimeDisplayMode.samples:
        return TimeFormatter.formatSamples(currentTime);
    }
  }

  String get _timeModeLabel {
    switch (timeDisplayMode) {
      case TimeDisplayMode.bars: return 'BAR';
      case TimeDisplayMode.timecode: return 'TC';
      case TimeDisplayMode.samples: return 'SMP';
    }
  }

  Color _getCpuColor() {
    if (cpuUsage > 80) return ReelForgeTheme.errorRed;
    if (cpuUsage > 60) return ReelForgeTheme.warningOrange;
    return ReelForgeTheme.accentGreen;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: ReelForgeTheme.borderSubtle, width: 1)),
      ),
      child: Row(
        children: [
          _Logo(),
          AppMenuBar(callbacks: menuCallbacks),
          if (onEditorModeChange != null) _ModeSwitcher(mode: editorMode, onChange: onEditorModeChange!),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TransportBar(
              isPlaying: isPlaying,
              isRecording: isRecording,
              transportDisabled: transportDisabled,
              loopEnabled: loopEnabled,
              metronomeEnabled: metronomeEnabled,
              snapEnabled: snapEnabled,
              snapValue: snapValue,
              onPlay: onPlay,
              onStop: onStop,
              onRecord: onRecord,
              onRewind: onRewind,
              onForward: onForward,
              onLoopToggle: onLoopToggle,
              onMetronomeToggle: onMetronomeToggle,
              onSnapToggle: onSnapToggle,
              onSnapValueChange: onSnapValueChange,
            ),
          ),
          _TempoDisplay(tempo: tempo, onTempoChange: onTempoChange),
          _TimeSignatureDisplay(timeSignature: timeSignature),
          _TimeDisplay(
            formattedTime: _formattedTime,
            modeLabel: _timeModeLabel,
            onTap: onTimeDisplayModeChange,
          ),
          const Spacer(),
          _ProjectInfo(name: projectName, onSave: onSave),
          _ZoneToggles(
            onToggleLeft: onToggleLeftZone,
            onToggleLower: onToggleLowerZone,
            onToggleRight: onToggleRightZone,
          ),
          _SystemMeters(cpuUsage: cpuUsage, memoryUsage: memoryUsage, cpuColor: _getCpuColor()),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [ReelForgeTheme.accentBlue, ReelForgeTheme.accentCyan]),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(child: Text('R', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
          ),
          const SizedBox(width: 8),
          Text('ReelForge', style: ReelForgeTheme.label.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ModeSwitcher extends StatelessWidget {
  final EditorMode mode;
  final ValueChanged<EditorMode> onChange;

  const _ModeSwitcher({required this.mode, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: EditorMode.values.map((m) {
          final isActive = mode == m;
          final config = _getModeConfig(m);
          return GestureDetector(
            onTap: () => onChange(m),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: isActive ? config.accentColor.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: isActive ? config.accentColor : Colors.transparent),
              ),
              child: Row(
                children: [
                  Text(config.icon, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text(config.name, style: TextStyle(
                    color: isActive ? config.accentColor : ReelForgeTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  )),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  ModeConfig _getModeConfig(EditorMode m) {
    switch (m) {
      case EditorMode.daw:
        return const ModeConfig(mode: EditorMode.daw, name: 'DAW', description: 'Timeline editing', icon: '🎛', shortcut: '1', accentColor: ReelForgeTheme.accentBlue);
      case EditorMode.middleware:
        return const ModeConfig(mode: EditorMode.middleware, name: 'Middleware', description: 'Event routing', icon: '🔀', shortcut: '2', accentColor: ReelForgeTheme.accentOrange);
      case EditorMode.slot:
        return const ModeConfig(mode: EditorMode.slot, name: 'Slot', description: 'Slot audio', icon: '🎰', shortcut: '3', accentColor: ReelForgeTheme.accentGreen);
    }
  }
}

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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: ReelForgeTheme.bgMid, borderRadius: BorderRadius.circular(4)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(tempo.toStringAsFixed(1), style: ReelForgeTheme.monoSmall.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
            Text('BPM', style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 9)),
          ],
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
      decoration: BoxDecoration(color: ReelForgeTheme.bgMid, borderRadius: BorderRadius.circular(4)),
      child: Text(timeSignature.toString(), style: ReelForgeTheme.monoSmall.copyWith(fontSize: 13)),
    );
  }
}

class _TimeDisplay extends StatelessWidget {
  final String formattedTime;
  final String modeLabel;
  final VoidCallback? onTap;

  const _TimeDisplay({required this.formattedTime, required this.modeLabel, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Row(
          children: [
            Text(formattedTime, style: ReelForgeTheme.monoSmall.copyWith(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: ReelForgeTheme.accentBlue.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
              child: Text(modeLabel, style: TextStyle(color: ReelForgeTheme.accentBlue, fontSize: 9, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectInfo extends StatelessWidget {
  final String name;
  final VoidCallback? onSave;
  const _ProjectInfo({required this.name, this.onSave});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(name, style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 12)),
          if (onSave != null) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Save (Ctrl+S)',
              child: InkWell(
                onTap: onSave,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
                  child: const Icon(Icons.save, size: 16, color: ReelForgeTheme.textSecondary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
          if (onToggleLeft != null) _IconBtn(icon: Icons.chevron_left, onPressed: onToggleLeft!, tooltip: 'Toggle Left Zone'),
          if (onToggleLower != null) _IconBtn(icon: Icons.expand_more, onPressed: onToggleLower!, tooltip: 'Toggle Lower Zone'),
          if (onToggleRight != null) _IconBtn(icon: Icons.chevron_right, onPressed: onToggleRight!, tooltip: 'Toggle Right Zone'),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  const _IconBtn({required this.icon, required this.onPressed, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 16, color: ReelForgeTheme.textSecondary)),
      ),
    );
  }
}

class _SystemMeters extends StatelessWidget {
  final double cpuUsage;
  final double memoryUsage;
  final Color cpuColor;
  const _SystemMeters({required this.cpuUsage, required this.memoryUsage, required this.cpuColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MeterBar(label: 'CPU', value: cpuUsage, color: cpuColor),
        const SizedBox(width: 8),
        _MeterBar(label: 'MEM', value: memoryUsage, color: ReelForgeTheme.accentBlue),
      ],
    );
  }
}

class _MeterBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _MeterBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 9)),
        const SizedBox(height: 2),
        Container(
          width: 40, height: 6,
          decoration: BoxDecoration(color: ReelForgeTheme.bgDeepest, borderRadius: BorderRadius.circular(3)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (value / 100).clamp(0.0, 1.0),
            child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          ),
        ),
      ],
    );
  }
}
