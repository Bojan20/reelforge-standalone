/// Glass Extras - Additional Theme-Aware Components
///
/// Theme-aware wrappers for:
/// - Browser panels (AudioPool, PluginBrowser)
/// - Editors (PianoRoll)
/// - Dialogs (ExportDialog)
/// - Recording panels
///
/// Note: Mixer components are in glass_mixer_ultimate.dart

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../providers/theme_mode_provider.dart';
import '../../providers/plugin_provider.dart';

// Browser imports
import '../browser/audio_pool_panel.dart';
import '../plugin/plugin_browser.dart';

// Editor imports
import '../editors/piano_roll.dart';

// Dialog imports
import '../dialogs/export_dialog.dart';

// Panel imports
import '../recording/recording_panel.dart';
import '../input_bus/input_bus_panel.dart';

// ==============================================================================
// GLASS PANEL WRAPPER (reusable)
// ==============================================================================

class GlassExtraPanelWrapper extends StatelessWidget {
  final Widget child;
  final double blurAmount;
  final double borderRadius;

  const GlassExtraPanelWrapper({
    super.key,
    required this.child,
    this.blurAmount = 12.0,
    this.borderRadius = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: blurAmount,
          sigmaY: blurAmount,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.08),
                Colors.white.withValues(alpha: 0.04),
                Colors.black.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.05),
                blurRadius: 30,
                spreadRadius: -5,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ==============================================================================
// THEME-AWARE AUDIO POOL PANEL
// ==============================================================================

class ThemeAwareAudioPoolPanel extends StatelessWidget {
  final void Function(AudioFileInfo file)? onFileSelected;
  final void Function(List<AudioFileInfo> files)? onFilesSelected;
  final void Function(AudioFileInfo file)? onFileDragStart;
  final void Function(List<AudioFileInfo> files)? onFilesDragStart;
  final void Function(AudioFileInfo file)? onFileDoubleClick;

  const ThemeAwareAudioPoolPanel({
    super.key,
    this.onFileSelected,
    this.onFilesSelected,
    this.onFileDragStart,
    this.onFilesDragStart,
    this.onFileDoubleClick,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = AudioPoolPanel(
      onFileSelected: onFileSelected,
      onFilesSelected: onFilesSelected,
      onFileDragStart: onFileDragStart,
      onFilesDragStart: onFilesDragStart,
      onFileDoubleClick: onFileDoubleClick,
    );

    if (isGlassMode) {
      return GlassExtraPanelWrapper(child: panel);
    }
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE PLUGIN BROWSER
// ==============================================================================

class ThemeAwarePluginBrowser extends StatelessWidget {
  final void Function(PluginInfo plugin)? onPluginSelected;
  final void Function(PluginInfo plugin)? onPluginLoad;

  const ThemeAwarePluginBrowser({
    super.key,
    this.onPluginSelected,
    this.onPluginLoad,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final browser = PluginBrowser(
      onPluginSelected: onPluginSelected,
      onPluginLoad: onPluginLoad,
    );

    if (isGlassMode) {
      return GlassExtraPanelWrapper(child: browser);
    }
    return browser;
  }
}

// ==============================================================================
// THEME-AWARE PIANO ROLL
// ==============================================================================

class ThemeAwarePianoRoll extends StatelessWidget {
  final List<MidiNote> notes;
  final List<MidiNote> ghostNotes;
  final ValueChanged<MidiNote>? onNoteAdd;

  const ThemeAwarePianoRoll({
    super.key,
    this.notes = const [],
    this.ghostNotes = const [],
    this.onNoteAdd,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final editor = PianoRoll(
      notes: notes,
      ghostNotes: ghostNotes,
      onNoteAdd: onNoteAdd,
    );

    if (isGlassMode) {
      return GlassExtraPanelWrapper(borderRadius: 8, child: editor);
    }
    return editor;
  }
}

// ==============================================================================
// THEME-AWARE EXPORT DIALOG
// ==============================================================================

class ThemeAwareExportDialog extends StatelessWidget {
  final double currentTime;
  final double totalDuration;
  final double? selectionStart;
  final double? selectionEnd;
  final double? loopStart;
  final double? loopEnd;

  const ThemeAwareExportDialog({
    super.key,
    required this.currentTime,
    required this.totalDuration,
    this.selectionStart,
    this.selectionEnd,
    this.loopStart,
    this.loopEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final dialog = ExportDialog(
      currentTime: currentTime,
      totalDuration: totalDuration,
      selectionStart: selectionStart,
      selectionEnd: selectionEnd,
      loopStart: loopStart,
      loopEnd: loopEnd,
    );

    if (isGlassMode) {
      return GlassExtraPanelWrapper(
        borderRadius: 16,
        blurAmount: 20,
        child: dialog,
      );
    }
    return dialog;
  }
}

// ==============================================================================
// THEME-AWARE RECORDING PANEL
// ==============================================================================

class ThemeAwareRecordingPanel extends StatelessWidget {
  const ThemeAwareRecordingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    const panel = RecordingPanel();

    if (isGlassMode) {
      return const GlassExtraPanelWrapper(child: panel);
    }
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE INPUT BUS PANEL
// ==============================================================================

class ThemeAwareInputBusPanel extends StatelessWidget {
  const ThemeAwareInputBusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    const panel = InputBusPanel();

    if (isGlassMode) {
      return const GlassExtraPanelWrapper(child: panel);
    }
    return panel;
  }
}
