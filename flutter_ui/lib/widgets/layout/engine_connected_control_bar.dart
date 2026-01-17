/// Engine Connected Control Bar
///
/// PERFORMANCE: Isolated control bar that directly listens to EngineProvider.
/// This prevents the entire MainLayout from rebuilding on every transport update.
/// Only the control bar rebuilds when transport state changes.
///
/// Theme-aware: Automatically switches between Glass and Classic control bars.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/engine_provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../models/layout_models.dart';
import '../../src/rust/native_ffi.dart';
import 'control_bar.dart';
import '../glass/glass_control_bar.dart';

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

  // Navigation callbacks
  final VoidCallback? onBackToLauncher;
  final VoidCallback? onBackToMiddleware;

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
    this.onBackToLauncher,
    this.onBackToMiddleware,
  });

  @override
  Widget build(BuildContext context) {
    // Watch theme mode for Glass/Classic switching
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    // PERFORMANCE: Use Selector to only rebuild on transport changes we care about
    return Selector<EngineProvider, _ControlBarData>(
      selector: (_, engine) {
        // Get PDC data from FFI
        final ffi = NativeFFI.instance;
        final pdcSamples = ffi.isLoaded ? ffi.pdcGetTotalLatencySamples() : 0;
        final pdcMs = ffi.isLoaded ? ffi.pdcGetTotalLatencyMs() : 0.0;
        final pdcEnabled = ffi.isLoaded ? ffi.pdcIsEnabled() : true;

        return _ControlBarData(
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
          pdcLatencySamples: pdcSamples,
          pdcLatencyMs: pdcMs,
          pdcEnabled: pdcEnabled,
        );
      },
      builder: (context, data, _) {
        final engine = context.read<EngineProvider>();

        // Shared callbacks
        void onPlay() {
          if (data.isPlaying) {
            engine.pause();
          } else {
            engine.play();
          }
        }

        void onStop() => engine.stop();
        void onRecord() => engine.toggleRecord();
        void onRewind() => engine.seek(0);
        void onForward() => engine.seek(data.positionSeconds + 10);
        void onTempoChanged(double t) => engine.setTempo(t);
        void onLoopToggle() => engine.toggleLoop();

        // Use Glass Control Bar when in Glass mode
        if (isGlassMode) {
          return GlassControlBar(
            editorMode: editorMode,
            onEditorModeChange: onEditorModeChange,
            isPlaying: data.isPlaying,
            isRecording: data.isRecording,
            onPlay: onPlay,
            onStop: onStop,
            onRecord: onRecord,
            onRewind: onRewind,
            onForward: onForward,
            tempo: data.tempo,
            onTempoChange: onTempoChanged,
            timeSignature: TimeSignature(data.timeSigNum, data.timeSigDenom),
            currentTime: data.positionSeconds,
            timeDisplayMode: timeDisplayMode,
            onTimeDisplayModeChange: onTimeDisplayModeChange,
            loopEnabled: data.loopEnabled,
            onLoopToggle: onLoopToggle,
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
        }

        // PDC toggle callback
        void onPdcToggle() {
          final ffi = NativeFFI.instance;
          if (ffi.isLoaded) {
            ffi.pdcSetEnabled(!data.pdcEnabled);
          }
        }

        // Classic Control Bar
        return ControlBar(
          editorMode: editorMode,
          onEditorModeChange: onEditorModeChange,
          isPlaying: data.isPlaying,
          isRecording: data.isRecording,
          onPlay: onPlay,
          onStop: onStop,
          onRecord: onRecord,
          onRewind: onRewind,
          onForward: onForward,
          tempo: data.tempo,
          onTempoChange: onTempoChanged,
          timeSignature: TimeSignature(data.timeSigNum, data.timeSigDenom),
          currentTime: data.positionSeconds,
          timeDisplayMode: timeDisplayMode,
          onTimeDisplayModeChange: onTimeDisplayModeChange,
          loopEnabled: data.loopEnabled,
          onLoopToggle: onLoopToggle,
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
          pdcLatencySamples: data.pdcLatencySamples,
          pdcLatencyMs: data.pdcLatencyMs,
          pdcEnabled: data.pdcEnabled,
          onPdcTap: onPdcToggle,
          onBackToLauncher: onBackToLauncher,
          onBackToMiddleware: onBackToMiddleware,
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
  // PDC
  final int pdcLatencySamples;
  final double pdcLatencyMs;
  final bool pdcEnabled;

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
    required this.pdcLatencySamples,
    required this.pdcLatencyMs,
    required this.pdcEnabled,
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
        other.canRedo == canRedo &&
        other.pdcLatencySamples == pdcLatencySamples &&
        other.pdcLatencyMs == pdcLatencyMs &&
        other.pdcEnabled == pdcEnabled;
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
        pdcLatencySamples,
        pdcLatencyMs,
        pdcEnabled,
      );
}
