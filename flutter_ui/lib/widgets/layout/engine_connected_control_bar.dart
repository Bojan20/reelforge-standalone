/// Engine Connected Control Bar
///
/// PERFORMANCE: Isolated control bar that directly listens to EngineProvider.
/// This prevents the entire MainLayout from rebuilding on every transport update.
/// Only the control bar rebuilds when transport state changes.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/engine_provider.dart';
import '../../models/layout_models.dart';
import 'control_bar.dart';

class EngineConnectedControlBar extends StatelessWidget {
  final EditorMode editorMode;
  final ValueChanged<EditorMode>? onEditorModeChange;
  final TimeDisplayMode timeDisplayMode;
  final VoidCallback? onTimeDisplayModeChange;
  final bool snapEnabled;
  final double snapValue;
  final VoidCallback? onSnapToggle;
  final ValueChanged<double>? onSnapValueChange;
  final bool metronomeEnabled;
  final VoidCallback? onMetronomeToggle;
  final double memoryUsage;
  final MenuCallbacks? menuCallbacks;
  final VoidCallback? onSave;
  // Zone toggle callbacks
  final VoidCallback? onToggleLeftZone;
  final VoidCallback? onToggleRightZone;
  final VoidCallback? onToggleLowerZone;

  const EngineConnectedControlBar({
    super.key,
    required this.editorMode,
    this.onEditorModeChange,
    required this.timeDisplayMode,
    this.onTimeDisplayModeChange,
    required this.snapEnabled,
    required this.snapValue,
    this.onSnapToggle,
    this.onSnapValueChange,
    required this.metronomeEnabled,
    this.onMetronomeToggle,
    required this.memoryUsage,
    this.menuCallbacks,
    this.onSave,
    this.onToggleLeftZone,
    this.onToggleRightZone,
    this.onToggleLowerZone,
  });

  @override
  Widget build(BuildContext context) {
    // PERFORMANCE: Use Selector to only rebuild on transport changes we care about
    return Selector<EngineProvider, _ControlBarData>(
      selector: (_, engine) => _ControlBarData(
        isPlaying: engine.transport.isPlaying,
        isRecording: engine.transport.isRecording,
        tempo: engine.transport.tempo,
        positionSeconds: engine.transport.positionSeconds,
        timeSigNum: engine.transport.timeSigNum,
        timeSigDenom: engine.transport.timeSigDenom,
        loopEnabled: engine.transport.loopEnabled,
        cpuUsage: engine.metering.cpuUsage,
        projectName: engine.project.name,
        canUndo: engine.canUndo,
        canRedo: engine.canRedo,
      ),
      builder: (context, data, _) {
        final engine = context.read<EngineProvider>();

        return ControlBar(
          editorMode: editorMode,
          onEditorModeChange: onEditorModeChange,
          isPlaying: data.isPlaying,
          isRecording: data.isRecording,
          onPlay: () {
            if (data.isPlaying) {
              engine.pause();
            } else {
              engine.play();
            }
          },
          onStop: () => engine.stop(),
          onRecord: () => engine.toggleRecord(),
          onRewind: () => engine.seek(0),
          onForward: () => engine.seek(data.positionSeconds + 10),
          tempo: data.tempo,
          onTempoChange: (t) => engine.setTempo(t),
          timeSignature: TimeSignature(data.timeSigNum, data.timeSigDenom),
          currentTime: data.positionSeconds,
          timeDisplayMode: timeDisplayMode,
          onTimeDisplayModeChange: onTimeDisplayModeChange,
          loopEnabled: data.loopEnabled,
          onLoopToggle: () => engine.toggleLoop(),
          snapEnabled: snapEnabled,
          snapValue: snapValue,
          onSnapToggle: onSnapToggle,
          onSnapValueChange: onSnapValueChange,
          metronomeEnabled: metronomeEnabled,
          onMetronomeToggle: onMetronomeToggle,
          cpuUsage: data.cpuUsage,
          memoryUsage: memoryUsage,
          projectName: data.projectName,
          onSave: onSave,
          onToggleLeftZone: onToggleLeftZone,
          onToggleRightZone: onToggleRightZone,
          onToggleLowerZone: onToggleLowerZone,
          menuCallbacks: menuCallbacks,
        );
      },
    );
  }
}

/// Data class for Selector - only rebuilds when these values change
class _ControlBarData {
  final bool isPlaying;
  final bool isRecording;
  final double tempo;
  final double positionSeconds;
  final int timeSigNum;
  final int timeSigDenom;
  final bool loopEnabled;
  final double cpuUsage;
  final String projectName;
  final bool canUndo;
  final bool canRedo;

  const _ControlBarData({
    required this.isPlaying,
    required this.isRecording,
    required this.tempo,
    required this.positionSeconds,
    required this.timeSigNum,
    required this.timeSigDenom,
    required this.loopEnabled,
    required this.cpuUsage,
    required this.projectName,
    required this.canUndo,
    required this.canRedo,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ControlBarData &&
        other.isPlaying == isPlaying &&
        other.isRecording == isRecording &&
        other.tempo == tempo &&
        other.positionSeconds == positionSeconds &&
        other.timeSigNum == timeSigNum &&
        other.timeSigDenom == timeSigDenom &&
        other.loopEnabled == loopEnabled &&
        other.cpuUsage == cpuUsage &&
        other.projectName == projectName &&
        other.canUndo == canUndo &&
        other.canRedo == canRedo;
  }

  @override
  int get hashCode => Object.hash(
        isPlaying,
        isRecording,
        tempo,
        positionSeconds,
        timeSigNum,
        timeSigDenom,
        loopEnabled,
        cpuUsage,
        projectName,
        canUndo,
        canRedo,
      );
}
