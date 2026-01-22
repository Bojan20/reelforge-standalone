// DAW Lower Zone Widget
//
// Complete Lower Zone for DAW section with:
// - Context bar (Super-tabs + Sub-tabs)
// - Content panel (switches based on current tab)
// - Action strip (context-aware actions)
// - Resizable height
// - Integrated FabFilter DSP panels (EQ, Comp, Limiter, Gate, Reverb)
// - Integrated Mixer, Timeline, Automation, Export panels

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'daw_lower_zone_controller.dart';
import 'lower_zone_types.dart';
import 'lower_zone_context_bar.dart';
import 'lower_zone_action_strip.dart';
import '../fabfilter/fabfilter_eq_panel.dart';
import '../fabfilter/fabfilter_compressor_panel.dart';
import '../fabfilter/fabfilter_limiter_panel.dart';
import '../mixer/ultimate_mixer.dart' as ultimate;
import '../mixer/knob.dart';
import '../editors/crossfade_editor.dart';
import '../../providers/mixer_provider.dart';
import '../../providers/undo_manager.dart';
// Gate and Reverb are accessible via FX Chain panel

class DawLowerZoneWidget extends StatefulWidget {
  final DawLowerZoneController controller;

  /// Currently selected track ID for DSP processing
  /// If null, DSP panels will show "No track selected"
  final int? selectedTrackId;

  /// Callback when a DSP panel action is triggered
  final void Function(String action, Map<String, dynamic>? params)? onDspAction;

  const DawLowerZoneWidget({
    super.key,
    required this.controller,
    this.selectedTrackId,
    this.onDspAction,
  });

  @override
  State<DawLowerZoneWidget> createState() => _DawLowerZoneWidgetState();
}

class _DawLowerZoneWidgetState extends State<DawLowerZoneWidget> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: kLowerZoneAnimationDuration,
      height: widget.controller.totalHeight,
      decoration: const BoxDecoration(
        color: LowerZoneColors.bgDeep,
        border: Border(
          top: BorderSide(color: LowerZoneColors.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Resize handle
          _buildResizeHandle(),
          // Context bar
          LowerZoneContextBar(
            superTabLabels: DawSuperTab.values.map((t) => t.label).toList(),
            superTabIcons: DawSuperTab.values.map((t) => t.icon).toList(),
            selectedSuperTab: widget.controller.superTab.index,
            subTabLabels: widget.controller.subTabLabels,
            selectedSubTab: widget.controller.currentSubTabIndex,
            accentColor: widget.controller.accentColor,
            isExpanded: widget.controller.isExpanded,
            onSuperTabSelected: widget.controller.setSuperTabIndex,
            onSubTabSelected: widget.controller.setSubTabIndex,
            onToggle: widget.controller.toggle,
          ),
          // Content panel (only when expanded)
          if (widget.controller.isExpanded) ...[
            Expanded(child: _buildContentPanel()),
            // Action strip
            _buildActionStrip(),
          ],
        ],
      ),
    );
  }

  Widget _buildResizeHandle() {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        widget.controller.adjustHeight(-details.delta.dy);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: Container(
          height: 4,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 40,
              height: 3,
              decoration: BoxDecoration(
                color: LowerZoneColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentPanel() {
    return Container(
      color: LowerZoneColors.bgDeep,
      child: _getContentForCurrentTab(),
    );
  }

  Widget _getContentForCurrentTab() {
    switch (widget.controller.superTab) {
      case DawSuperTab.browse:
        return _buildBrowseContent();
      case DawSuperTab.edit:
        return _buildEditContent();
      case DawSuperTab.mix:
        return _buildMixContent();
      case DawSuperTab.process:
        return _buildProcessContent();
      case DawSuperTab.deliver:
        return _buildDeliverContent();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BROWSE CONTENT — Functional panels
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBrowseContent() {
    final subTab = widget.controller.state.browseSubTab;
    return switch (subTab) {
      DawBrowseSubTab.files => _buildFilesPanel(),
      DawBrowseSubTab.presets => _buildPresetsPanel(),
      DawBrowseSubTab.plugins => _buildPluginsPanel(),
      DawBrowseSubTab.history => _buildHistoryPanel(),
    };
  }

  Widget _buildFilesPanel() => _buildCompactFilesBrowser();
  Widget _buildPresetsPanel() => _buildCompactPresetsBrowser();
  Widget _buildPluginsPanel() => _buildCompactPluginsScanner();
  Widget _buildHistoryPanel() => _buildCompactHistoryPanel();

  /// Compact files browser
  Widget _buildCompactFilesBrowser() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBrowserHeader('FILES', Icons.folder_open),
          const SizedBox(height: 12),
          _buildBrowserSearchBar(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                // Folder tree
                SizedBox(
                  width: 180,
                  child: _buildFolderTree(),
                ),
                const SizedBox(width: 12),
                // File list
                Expanded(child: _buildFileList()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowserHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: LowerZoneColors.dawAccent),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.dawAccent,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildBrowserSearchBar() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.search, size: 14, color: LowerZoneColors.textMuted),
          SizedBox(width: 8),
          Expanded(
            child: TextField(
              style: TextStyle(fontSize: 11, color: LowerZoneColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(fontSize: 11, color: LowerZoneColors.textMuted),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTree() {
    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _buildFolderItem('Project', Icons.folder, isExpanded: true),
          _buildFolderItem('  Audio', Icons.folder_open, indent: 1),
          _buildFolderItem('  SFX', Icons.folder_open, indent: 1),
          _buildFolderItem('  Music', Icons.folder_open, indent: 1),
          _buildFolderItem('Samples', Icons.folder, isExpanded: false),
          _buildFolderItem('Presets', Icons.folder, isExpanded: false),
        ],
      ),
    );
  }

  Widget _buildFolderItem(String name, IconData icon, {bool isExpanded = false, int indent = 0}) {
    return Padding(
      padding: EdgeInsets.only(left: indent * 12.0, top: 2, bottom: 2),
      child: Row(
        children: [
          Icon(
            isExpanded ? Icons.expand_more : Icons.chevron_right,
            size: 12,
            color: LowerZoneColors.textMuted,
          ),
          Icon(icon, size: 14, color: LowerZoneColors.dawAccent),
          const SizedBox(width: 4),
          Text(
            name.trim(),
            style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: ListView(
        padding: const EdgeInsets.all(4),
        children: [
          _buildFileItem('drums_loop.wav', '2.4 MB', Icons.audio_file),
          _buildFileItem('bass_hit.wav', '156 KB', Icons.audio_file),
          _buildFileItem('synth_pad.wav', '3.1 MB', Icons.audio_file),
          _buildFileItem('vocal_take1.wav', '8.2 MB', Icons.audio_file),
          _buildFileItem('fx_whoosh.wav', '412 KB', Icons.audio_file),
        ],
      ),
    );
  }

  Widget _buildFileItem(String name, String size, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: LowerZoneColors.border.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: LowerZoneColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
            ),
          ),
          Text(
            size,
            style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
          ),
        ],
      ),
    );
  }

  /// Compact presets browser
  Widget _buildCompactPresetsBrowser() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBrowserHeader('PRESETS', Icons.tune),
          const SizedBox(height: 12),
          _buildBrowserSearchBar(),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 2.5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                final presets = ['Clean', 'Warm', 'Punch', 'Air', 'Vintage', 'Modern',
                                 'Soft', 'Bright', 'Dark', 'Natural', 'Tight', 'Wide'];
                return _buildPresetCard(presets[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetCard(String name) {
    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Center(
        child: Text(
          name,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: LowerZoneColors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// Compact plugins scanner
  Widget _buildCompactPluginsScanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildBrowserHeader('PLUGINS', Icons.extension),
              const Spacer(),
              _buildActionChip(Icons.refresh, 'Rescan'),
            ],
          ),
          const SizedBox(height: 12),
          _buildBrowserSearchBar(),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _buildPluginCategory('VST3', [
                  ('FabFilter Pro-Q 3', true),
                  ('FabFilter Pro-C 2', true),
                  ('FabFilter Pro-L 2', true),
                  ('Waves SSL Channel', false),
                ]),
                _buildPluginCategory('AU', [
                  ('Apple AUGraphicEQ', true),
                  ('Apple AUPitch', true),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: LowerZoneColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: LowerZoneColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginCategory(String category, List<(String, bool)> plugins) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Row(
              children: [
                Text(
                  category,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: LowerZoneColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${plugins.length} plugins',
                  style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
                ),
              ],
            ),
          ),
          ...plugins.map((p) => _buildPluginItem(p.$1, p.$2)),
        ],
      ),
    );
  }

  Widget _buildPluginItem(String name, bool isValid) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.error,
            size: 12,
            color: isValid ? LowerZoneColors.success : LowerZoneColors.error,
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: TextStyle(
              fontSize: 10,
              color: isValid ? LowerZoneColors.textPrimary : LowerZoneColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// Compact undo history panel — Connected to UiUndoManager
  Widget _buildCompactHistoryPanel() {
    return ListenableBuilder(
      listenable: UiUndoManager.instance,
      builder: (context, _) {
        final undoManager = UiUndoManager.instance;
        final history = undoManager.undoHistory;
        final canUndo = undoManager.canUndo;
        final canRedo = undoManager.canRedo;

        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildBrowserHeader('UNDO HISTORY', Icons.history),
                  const SizedBox(width: 8),
                  Text(
                    '${undoManager.undoStackSize} actions',
                    style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
                  ),
                  const Spacer(),
                  // Undo button
                  GestureDetector(
                    onTap: canUndo ? () => undoManager.undo() : null,
                    child: _buildUndoRedoChip(Icons.undo, 'Undo', canUndo),
                  ),
                  const SizedBox(width: 4),
                  // Redo button
                  GestureDetector(
                    onTap: canRedo ? () => undoManager.redo() : null,
                    child: _buildUndoRedoChip(Icons.redo, 'Redo', canRedo),
                  ),
                  const SizedBox(width: 8),
                  // Clear button
                  GestureDetector(
                    onTap: history.isNotEmpty ? () => undoManager.clear() : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: history.isNotEmpty
                            ? Colors.red.withValues(alpha: 0.1)
                            : LowerZoneColors.bgSurface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: history.isNotEmpty ? Colors.red.withValues(alpha: 0.3) : LowerZoneColors.border,
                        ),
                      ),
                      child: Text(
                        'Clear',
                        style: TextStyle(
                          fontSize: 9,
                          color: history.isNotEmpty ? Colors.red : LowerZoneColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: LowerZoneColors.bgDeepest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.border),
                  ),
                  child: history.isEmpty
                      ? const Center(
                          child: Text(
                            'No undo history',
                            style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(4),
                          itemCount: history.length,
                          itemBuilder: (context, index) {
                            final action = history[index];
                            return GestureDetector(
                              onTap: () => undoManager.undoTo(index),
                              child: _buildHistoryItem(
                                action.description,
                                index == 0, // Most recent is current
                                index,
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUndoRedoChip(IconData icon, String label, bool isEnabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isEnabled
            ? LowerZoneColors.dawAccent.withValues(alpha: 0.1)
            : LowerZoneColors.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isEnabled ? LowerZoneColors.dawAccent.withValues(alpha: 0.3) : LowerZoneColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isEnabled ? LowerZoneColors.dawAccent : LowerZoneColors.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: isEnabled ? LowerZoneColors.dawAccent : LowerZoneColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(String action, bool isCurrent, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isCurrent ? LowerZoneColors.dawAccent.withValues(alpha: 0.1) : null,
        border: Border(
          left: BorderSide(
            color: isCurrent ? LowerZoneColors.dawAccent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isCurrent ? Icons.arrow_right : Icons.circle,
            size: isCurrent ? 16 : 6,
            color: isCurrent ? LowerZoneColors.dawAccent : LowerZoneColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              action,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                color: isCurrent ? LowerZoneColors.dawAccent : LowerZoneColors.textPrimary,
              ),
            ),
          ),
          // Index indicator (for undo-to-this-point)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              '#${index + 1}',
              style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EDIT CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEditContent() {
    final subTab = widget.controller.state.editSubTab;
    return switch (subTab) {
      DawEditSubTab.timeline => _buildTimelinePanel(),
      DawEditSubTab.clips => _buildClipsPanel(),
      DawEditSubTab.fades => _buildFadesPanel(),
      DawEditSubTab.grid => _buildGridPanel(),
    };
  }

  Widget _buildTimelinePanel() => _buildCompactTimelineOverview();
  Widget _buildClipsPanel() => _buildCompactClipProperties();
  Widget _buildFadesPanel() => _buildCompactFadeEditor();
  Widget _buildGridPanel() => _buildCompactGridSettings();

  /// Compact Timeline Overview
  Widget _buildCompactTimelineOverview() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('TIMELINE OVERVIEW', Icons.timeline),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                // Track list
                SizedBox(
                  width: 120,
                  child: _buildTrackList(),
                ),
                const SizedBox(width: 8),
                // Timeline visualization
                Expanded(child: _buildTimelineVisualization()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackList() {
    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: ListView(
        padding: const EdgeInsets.all(4),
        children: [
          _buildTrackListItem('Master', Icons.speaker, true),
          _buildTrackListItem('Track 1', Icons.audiotrack, false),
          _buildTrackListItem('Track 2', Icons.audiotrack, false),
          _buildTrackListItem('Track 3', Icons.audiotrack, false),
        ],
      ),
    );
  }

  Widget _buildTrackListItem(String name, IconData icon, bool isMaster) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isMaster ? LowerZoneColors.dawAccent.withValues(alpha: 0.1) : null,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: isMaster ? LowerZoneColors.dawAccent : LowerZoneColors.textMuted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 9,
                color: isMaster ? LowerZoneColors.dawAccent : LowerZoneColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineVisualization() {
    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: CustomPaint(
        painter: _TimelineOverviewPainter(color: LowerZoneColors.dawAccent),
        size: Size.infinite,
      ),
    );
  }

  /// Compact Clip Properties — Editable version
  /// Displays and allows editing of selected clip properties
  Widget _buildCompactClipProperties() {
    // For now we show editable controls with default values
    // TODO: Connect to actual TimelineClip from selection provider
    return _EditableClipPanel(
      clipName: 'audio_clip_01.wav',
      startTime: 0.0,
      duration: 5.234,
      gain: 1.0, // Unity gain
      fadeIn: 0.01, // 10ms
      fadeOut: 0.05, // 50ms
      onGainChanged: (value) {
        widget.onDspAction?.call('clip_gain', {'gain': value});
      },
      onFadeInChanged: (value) {
        widget.onDspAction?.call('clip_fade_in', {'duration': value});
      },
      onFadeOutChanged: (value) {
        widget.onDspAction?.call('clip_fade_out', {'duration': value});
      },
    );
  }

  Widget _buildPropertyRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Integrated Crossfade Editor from editors/crossfade_editor.dart
  Widget _buildCompactFadeEditor() {
    return const CrossfadeEditor(
      initialConfig: CrossfadeConfig(
        fadeOut: FadeCurveConfig(preset: CrossfadePreset.equalPower),
        fadeIn: FadeCurveConfig(preset: CrossfadePreset.equalPower),
        duration: 0.5,
        linked: true,
      ),
    );
  }

  /// Compact Grid Settings
  Widget _buildCompactGridSettings() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('GRID SETTINGS', Icons.grid_on),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildGridOption('Grid Type', 'Bars+Beats', Icons.music_note),
                  _buildGridOption('Grid Resolution', '1/16', Icons.straighten),
                  _buildGridOption('Snap Mode', 'Magnetic', Icons.adjust),
                  _buildGridOption('Triplet Grid', 'Off', Icons.grid_3x3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridOption(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: LowerZoneColors.dawAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(value, style: TextStyle(fontSize: 10, color: LowerZoneColors.dawAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: LowerZoneColors.dawAccent),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.dawAccent,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIX CONTENT — Integrated panels
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMixContent() {
    final subTab = widget.controller.state.mixSubTab;
    return switch (subTab) {
      DawMixSubTab.mixer => _buildMixerPanel(),
      DawMixSubTab.sends => _buildSendsPanel(),
      DawMixSubTab.pan => _buildPanPanel(),
      DawMixSubTab.automation => _buildAutomationPanel(),
    };
  }

  Widget _buildMixerPanel() {
    // UltimateMixer requires MixerProvider
    final MixerProvider mixerProvider;
    try {
      mixerProvider = context.watch<MixerProvider>();
    } catch (_) {
      return _buildNoProviderPanel('Mixer', Icons.tune, 'MixerProvider');
    }

    // Convert MixerProvider channels to UltimateMixerChannel format
    final channels = mixerProvider.channels.map((ch) {
      return ultimate.UltimateMixerChannel(
        id: ch.id,
        name: ch.name,
        type: ultimate.ChannelType.audio,
        color: ch.color,
        volume: ch.volume,
        pan: ch.pan,
        panRight: ch.panRight,
        isStereo: ch.isStereo,
        muted: ch.muted,
        soloed: ch.soloed,
        armed: ch.armed,
        peakL: ch.peakL,
        peakR: ch.peakR,
        rmsL: ch.rmsL,
        rmsR: ch.rmsR,
      );
    }).toList();

    final buses = mixerProvider.buses.map((bus) {
      return ultimate.UltimateMixerChannel(
        id: bus.id,
        name: bus.name,
        type: ultimate.ChannelType.bus,
        color: bus.color,
        volume: bus.volume,
        pan: bus.pan,
        muted: bus.muted,
        soloed: bus.soloed,
        peakL: bus.peakL,
        peakR: bus.peakR,
      );
    }).toList();

    final auxes = mixerProvider.auxes.map((aux) {
      return ultimate.UltimateMixerChannel(
        id: aux.id,
        name: aux.name,
        type: ultimate.ChannelType.aux,
        color: aux.color,
        volume: aux.volume,
        pan: aux.pan,
        muted: aux.muted,
        soloed: aux.soloed,
        peakL: aux.peakL,
        peakR: aux.peakR,
      );
    }).toList();

    // Convert VCAs
    final vcas = mixerProvider.vcas.map((vca) {
      return ultimate.UltimateMixerChannel(
        id: vca.id,
        name: vca.name,
        type: ultimate.ChannelType.vca,
        color: vca.color,
        volume: vca.level,
        muted: vca.muted,
        soloed: vca.soloed,
      );
    }).toList();

    final master = ultimate.UltimateMixerChannel(
      id: mixerProvider.master.id,
      name: 'Master',
      type: ultimate.ChannelType.master,
      color: const Color(0xFFFF9040),
      volume: mixerProvider.master.volume,
      peakL: mixerProvider.master.peakL,
      peakR: mixerProvider.master.peakR,
    );

    return ultimate.UltimateMixer(
      channels: channels,
      buses: buses,
      auxes: auxes,
      vcas: vcas,
      master: master,
      compact: true,
      showInserts: true,
      showSends: true,
      // === VOLUME / PAN / MUTE / SOLO / ARM ===
      onVolumeChange: (id, volume) {
        // Check if it's a VCA
        if (mixerProvider.vcas.any((v) => v.id == id)) {
          mixerProvider.setVcaLevel(id, volume);
        } else if (id == mixerProvider.master.id) {
          mixerProvider.setMasterVolume(volume);
        } else {
          mixerProvider.setChannelVolume(id, volume);
        }
      },
      onPanChange: (id, pan) => mixerProvider.setChannelPan(id, pan),
      onPanRightChange: (id, pan) => mixerProvider.setChannelPanRight(id, pan),
      onMuteToggle: (id) {
        if (mixerProvider.vcas.any((v) => v.id == id)) {
          mixerProvider.toggleVcaMute(id);
        } else {
          mixerProvider.toggleChannelMute(id);
        }
      },
      onSoloToggle: (id) => mixerProvider.toggleChannelSolo(id),
      onArmToggle: (id) => mixerProvider.toggleChannelArm(id),
      // === SENDS ===
      onSendLevelChange: (channelId, sendIndex, level) {
        final ch = mixerProvider.channels.firstWhere(
          (c) => c.id == channelId,
          orElse: () => mixerProvider.channels.first,
        );
        if (sendIndex < ch.sends.length) {
          final auxId = ch.sends[sendIndex].auxId;
          mixerProvider.setAuxSendLevel(channelId, auxId, level);
        }
      },
      onSendMuteToggle: (channelId, sendIndex, muted) {
        final ch = mixerProvider.channels.firstWhere(
          (c) => c.id == channelId,
          orElse: () => mixerProvider.channels.first,
        );
        if (sendIndex < ch.sends.length) {
          final auxId = ch.sends[sendIndex].auxId;
          mixerProvider.toggleAuxSendEnabled(channelId, auxId);
        }
      },
      onSendPreFaderToggle: (channelId, sendIndex, preFader) {
        final ch = mixerProvider.channels.firstWhere(
          (c) => c.id == channelId,
          orElse: () => mixerProvider.channels.first,
        );
        if (sendIndex < ch.sends.length) {
          final auxId = ch.sends[sendIndex].auxId;
          mixerProvider.toggleAuxSendPreFader(channelId, auxId);
        }
      },
      onSendDestChange: (channelId, sendIndex, newDestination) {
        if (newDestination != null) {
          mixerProvider.setAuxSendDestination(channelId, sendIndex, newDestination);
        }
      },
      // === ROUTING ===
      onOutputChange: (channelId, busId) {
        mixerProvider.setChannelOutput(channelId, busId);
      },
      // === INPUT SECTION ===
      onPhaseToggle: (channelId) {
        mixerProvider.togglePhaseInvert(channelId);
      },
      onGainChange: (channelId, gain) {
        mixerProvider.setInputGain(channelId, gain);
      },
      // === STRUCTURE ===
      onAddBus: () {
        mixerProvider.createBus(name: 'Bus ${mixerProvider.buses.length + 1}');
      },
    );
  }

  Widget _buildSendsPanel() => _buildCompactSendsPanel();
  Widget _buildPanPanel() => _buildCompactPannerPanel();
  Widget _buildAutomationPanel() => _buildCompactAutomationPanel();

  /// Compact sends panel with MiniKnobs connected to MixerProvider
  Widget _buildCompactSendsPanel() {
    // Try to get MixerProvider
    MixerProvider? mixerProvider;
    try {
      mixerProvider = context.watch<MixerProvider>();
    } catch (_) {
      // Provider not available
    }

    // Get selected channel's sends
    final selectedChannel = _getSelectedChannel(mixerProvider);
    final sends = selectedChannel?.sends ?? [];

    // Default aux definitions
    const auxDefs = [
      ('Reverb A', 'aux_reverb_a', Color(0xFF40C8FF)),
      ('Reverb B', 'aux_reverb_b', Color(0xFF40C8FF)),
      ('Delay', 'aux_delay', Color(0xFFFF9040)),
      ('Chorus', 'aux_chorus', Color(0xFF40FF90)),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.call_split, size: 16, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 8),
              Text(
                'AUX SENDS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              if (selectedChannel != null)
                Text(
                  selectedChannel.name,
                  style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary),
                )
              else
                const Text(
                  'No track selected',
                  style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: auxDefs.map((def) {
                final (name, auxId, color) = def;
                // Find send level for this aux
                final send = sends.where((s) => s.auxId == auxId).firstOrNull;
                final level = send?.level ?? 0.0;
                final enabled = send?.enabled ?? true;

                return _buildSendChannelWithKnob(
                  name,
                  level,
                  color,
                  enabled: enabled,
                  onChanged: mixerProvider != null && selectedChannel != null
                      ? (newLevel) {
                          mixerProvider!.setAuxSendLevel(
                            selectedChannel.id,
                            auxId,
                            newLevel,
                          );
                        }
                      : null,
                  onMuteToggle: mixerProvider != null && selectedChannel != null
                      ? () {
                          mixerProvider!.toggleAuxSendEnabled(
                            selectedChannel.id,
                            auxId,
                          );
                        }
                      : null,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Get selected channel from MixerProvider based on selectedTrackId
  MixerChannel? _getSelectedChannel(MixerProvider? provider) {
    if (provider == null || widget.selectedTrackId == null) return null;
    // Find channel by track index
    return provider.channels
        .where((c) => c.trackIndex == widget.selectedTrackId)
        .firstOrNull;
  }

  Widget _buildSendChannelWithKnob(
    String name,
    double level,
    Color color, {
    bool enabled = true,
    ValueChanged<double>? onChanged,
    VoidCallback? onMuteToggle,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        LargeKnob(
          label: '',
          value: level,
          size: 52,
          accentColor: enabled ? color : LowerZoneColors.textMuted,
          onChanged: onChanged,
        ),
        const SizedBox(height: 4),
        // Mute button
        GestureDetector(
          onTap: onMuteToggle,
          child: Container(
            width: 28,
            height: 18,
            decoration: BoxDecoration(
              color: !enabled
                  ? LowerZoneColors.warning.withValues(alpha: 0.3)
                  : LowerZoneColors.bgDeepest,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: !enabled ? LowerZoneColors.warning : LowerZoneColors.border,
              ),
            ),
            child: Center(
              child: Text(
                'M',
                style: TextStyle(
                  fontSize: 9,
                  color: !enabled ? LowerZoneColors.warning : LowerZoneColors.textMuted,
                  fontWeight: !enabled ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Compact surround panner connected to MixerProvider
  Widget _buildCompactPannerPanel() {
    // Try to get MixerProvider
    MixerProvider? mixerProvider;
    try {
      mixerProvider = context.watch<MixerProvider>();
    } catch (_) {
      // Provider not available
    }

    final selectedChannel = _getSelectedChannel(mixerProvider);
    final pan = selectedChannel?.pan ?? 0.0;
    final panRight = selectedChannel?.panRight ?? 0.0;
    final isStereo = selectedChannel?.isStereo ?? true;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.surround_sound, size: 16, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 8),
              Text(
                isStereo ? 'STEREO PANNER' : 'MONO PANNER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              if (selectedChannel != null)
                Text(
                  selectedChannel.name,
                  style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary),
                )
              else
                const Text(
                  'No track selected',
                  style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: _buildPannerWidget(
                pan: pan,
                panRight: panRight,
                isStereo: isStereo,
                onPanChanged: mixerProvider != null && selectedChannel != null
                    ? (newPan) {
                        mixerProvider!.setChannelPan(selectedChannel.id, newPan);
                      }
                    : null,
                onPanRightChanged: mixerProvider != null && selectedChannel != null && isStereo
                    ? (newPan) {
                        mixerProvider!.setChannelPanRight(selectedChannel.id, newPan);
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPannerWidget({
    required double pan,
    required double panRight,
    required bool isStereo,
    ValueChanged<double>? onPanChanged,
    ValueChanged<double>? onPanRightChanged,
  }) {
    // Pan display text
    String panText(double p) {
      if (p.abs() < 0.01) return 'C';
      final percent = (p.abs() * 100).round();
      return p < 0 ? 'L$percent' : 'R$percent';
    }

    if (!isStereo) {
      // Mono: single pan knob
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('PAN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: LowerZoneColors.textPrimary)),
          const SizedBox(height: 8),
          LargeKnob(
            label: '',
            value: pan,
            bipolar: true,
            size: 72,
            accentColor: LowerZoneColors.dawAccent,
            onChanged: onPanChanged,
          ),
          const SizedBox(height: 4),
          Text(panText(pan), style: const TextStyle(fontSize: 11, color: LowerZoneColors.textSecondary)),
        ],
      );
    }

    // Stereo: dual pan knobs (Pro Tools style)
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Left channel pan
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('L', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: LowerZoneColors.textMuted)),
            const SizedBox(height: 8),
            LargeKnob(
              label: '',
              value: pan,
              bipolar: true,
              size: 56,
              accentColor: LowerZoneColors.dawAccent,
              onChanged: onPanChanged,
            ),
            const SizedBox(height: 4),
            Text(panText(pan), style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary)),
          ],
        ),
        const SizedBox(width: 32),
        // Width indicator
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('WIDTH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: LowerZoneColors.textMuted)),
            const SizedBox(height: 8),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: LowerZoneColors.bgDeepest,
                shape: BoxShape.circle,
                border: Border.all(color: LowerZoneColors.border),
              ),
              child: CustomPaint(
                painter: _StereoWidthPainter(
                  panL: pan,
                  panR: panRight,
                  color: LowerZoneColors.dawAccent,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${((panRight - pan).abs() * 50 + 50).round()}%',
              style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(width: 32),
        // Right channel pan
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('R', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: LowerZoneColors.textMuted)),
            const SizedBox(height: 8),
            LargeKnob(
              label: '',
              value: panRight,
              bipolar: true,
              size: 56,
              accentColor: LowerZoneColors.dawAccent,
              onChanged: onPanRightChanged,
            ),
            const SizedBox(height: 4),
            Text(panText(panRight), style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary)),
          ],
        ),
      ],
    );
  }

  /// Compact automation panel for Lower Zone
  Widget _buildCompactAutomationPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_graph, size: 16, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 8),
              Text(
                'AUTOMATION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              _buildAutomationModeChip('Read', true),
              _buildAutomationModeChip('Write', false),
              _buildAutomationModeChip('Touch', false),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: LowerZoneColors.bgDeepest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: CustomPaint(
                painter: _AutomationCurvePainter(
                  color: LowerZoneColors.dawAccent,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomationModeChip(String label, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? LowerZoneColors.dawAccent.withValues(alpha: 0.2)
            : LowerZoneColors.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? LowerZoneColors.dawAccent : LowerZoneColors.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          color: isActive ? LowerZoneColors.dawAccent : LowerZoneColors.textMuted,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROCESS CONTENT — FabFilter DSP Panels
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProcessContent() {
    final subTab = widget.controller.state.processSubTab;
    return switch (subTab) {
      DawProcessSubTab.eq => _buildEqPanel(),
      DawProcessSubTab.comp => _buildCompPanel(),
      DawProcessSubTab.limiter => _buildLimiterPanel(),
      DawProcessSubTab.fxChain => _buildFxChainPanel(),
    };
  }

  /// FabFilter Pro-Q Style 64-band Parametric EQ
  Widget _buildEqPanel() {
    final trackId = widget.selectedTrackId;
    if (trackId == null) {
      return _buildNoTrackSelectedPanel('EQ', Icons.equalizer);
    }
    return FabFilterEqPanel(trackId: trackId);
  }

  /// FabFilter Pro-C Style Compressor
  Widget _buildCompPanel() {
    final trackId = widget.selectedTrackId;
    if (trackId == null) {
      return _buildNoTrackSelectedPanel('Compressor', Icons.compress);
    }
    return FabFilterCompressorPanel(trackId: trackId);
  }

  /// FabFilter Pro-L Style Limiter
  Widget _buildLimiterPanel() {
    final trackId = widget.selectedTrackId;
    if (trackId == null) {
      return _buildNoTrackSelectedPanel('Limiter', Icons.volume_up);
    }
    return FabFilterLimiterPanel(trackId: trackId);
  }

  /// FX Chain — Shows all processors in chain
  Widget _buildFxChainPanel() {
    final trackId = widget.selectedTrackId;
    if (trackId == null) {
      return _buildNoTrackSelectedPanel('FX Chain', Icons.link);
    }
    // FX Chain view showing all active processors
    return _buildFxChainView(trackId);
  }

  /// FX Chain View — Horizontal chain of active processors
  Widget _buildFxChainView(int trackId) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.link, size: 16, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 8),
              Text(
                'FX CHAIN — Track $trackId',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              _buildChainActionButton(Icons.add, 'Add', () {
                widget.onDspAction?.call('addProcessor', {'trackId': trackId});
              }),
              const SizedBox(width: 8),
              _buildChainActionButton(Icons.clear_all, 'Clear', () {
                widget.onDspAction?.call('clearChain', {'trackId': trackId});
              }),
            ],
          ),
          const SizedBox(height: 16),
          // Chain visualization
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Input
                  _buildChainNode('INPUT', Icons.input, isEndpoint: true),
                  _buildChainConnector(),
                  // Processors
                  _buildChainProcessor('EQ', Icons.equalizer, true, () {
                    widget.controller.setProcessSubTab(DawProcessSubTab.eq);
                  }),
                  _buildChainConnector(),
                  _buildChainProcessor('COMP', Icons.compress, true, () {
                    widget.controller.setProcessSubTab(DawProcessSubTab.comp);
                  }),
                  _buildChainConnector(),
                  _buildChainProcessor('LIMIT', Icons.volume_up, false, () {
                    widget.controller.setProcessSubTab(DawProcessSubTab.limiter);
                  }),
                  _buildChainConnector(),
                  // Output
                  _buildChainNode('OUTPUT', Icons.output, isEndpoint: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChainActionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: LowerZoneColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: LowerZoneColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChainNode(String label, IconData icon, {bool isEndpoint = false}) {
    return Container(
      width: 80,
      height: 60,
      decoration: BoxDecoration(
        color: isEndpoint ? LowerZoneColors.bgDeepest : LowerZoneColors.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEndpoint ? LowerZoneColors.border : LowerZoneColors.dawAccent.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: isEndpoint ? LowerZoneColors.textMuted : LowerZoneColors.dawAccent),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: isEndpoint ? LowerZoneColors.textMuted : LowerZoneColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChainProcessor(String label, IconData icon, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 70,
        decoration: BoxDecoration(
          color: isActive
              ? LowerZoneColors.dawAccent.withValues(alpha: 0.15)
              : LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? LowerZoneColors.dawAccent
                : LowerZoneColors.border,
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive ? [
            BoxShadow(
              color: LowerZoneColors.dawAccent.withValues(alpha: 0.2),
              blurRadius: 8,
            ),
          ] : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: isActive ? LowerZoneColors.dawAccent : LowerZoneColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isActive ? LowerZoneColors.dawAccent : LowerZoneColors.textSecondary,
              ),
            ),
            if (isActive) ...[
              const SizedBox(height: 2),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: LowerZoneColors.success,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChainConnector() {
    return Container(
      width: 30,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            LowerZoneColors.dawAccent.withValues(alpha: 0.3),
            LowerZoneColors.dawAccent.withValues(alpha: 0.6),
            LowerZoneColors.dawAccent.withValues(alpha: 0.3),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DELIVER CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDeliverContent() {
    final subTab = widget.controller.state.deliverSubTab;
    return switch (subTab) {
      DawDeliverSubTab.export => _buildExportPanel(),
      DawDeliverSubTab.stems => _buildStemsPanel(),
      DawDeliverSubTab.bounce => _buildBouncePanel(),
      DawDeliverSubTab.archive => _buildArchivePanel(),
    };
  }

  Widget _buildExportPanel() => _buildCompactExportSettings();
  Widget _buildStemsPanel() => _buildCompactStemExport();
  Widget _buildBouncePanel() => _buildCompactBounce();
  Widget _buildArchivePanel() => _buildCompactArchive();

  /// Compact Export Settings
  Widget _buildCompactExportSettings() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('EXPORT SETTINGS', Icons.upload),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildExportOption('Format', 'WAV 48kHz/24bit'),
                        _buildExportOption('Channels', 'Stereo'),
                        _buildExportOption('Normalize', 'Peak -1dB'),
                        _buildExportOption('Dither', 'None'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildExportButton('EXPORT', Icons.upload, LowerZoneColors.dawAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportOption(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textMuted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: LowerZoneColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildExportButton(String label, IconData icon, Color color) {
    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  /// Compact Stem Export
  Widget _buildCompactStemExport() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('STEM EXPORT', Icons.account_tree),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      _buildStemItem('Master Mix', true),
                      _buildStemItem('Track 1', true),
                      _buildStemItem('Track 2', true),
                      _buildStemItem('Track 3', false),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildExportButton('STEMS', Icons.account_tree, LowerZoneColors.dawAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStemItem(String name, bool selected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: selected ? LowerZoneColors.dawAccent.withValues(alpha: 0.1) : LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: selected ? LowerZoneColors.dawAccent : LowerZoneColors.border),
      ),
      child: Row(
        children: [
          Icon(
            selected ? Icons.check_box : Icons.check_box_outline_blank,
            size: 14,
            color: selected ? LowerZoneColors.dawAccent : LowerZoneColors.textMuted,
          ),
          const SizedBox(width: 6),
          Text(name, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary)),
        ],
      ),
    );
  }

  /// Compact Bounce
  Widget _buildCompactBounce() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('REALTIME BOUNCE', Icons.speed),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _buildBounceOption('Source', 'Master Output'),
                      _buildBounceOption('Length', '3:24.567'),
                      _buildBounceOption('Tail', '2 sec'),
                      const Spacer(),
                      _buildBounceProgress(0.0),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildExportButton('BOUNCE', Icons.play_circle, LowerZoneColors.success),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBounceOption(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textMuted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildBounceProgress(double progress) {
    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          FractionallySizedBox(
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: LowerZoneColors.success,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Center(
            child: Text(
              progress > 0 ? '${(progress * 100).toInt()}%' : 'Ready',
              style: const TextStyle(fontSize: 9, color: LowerZoneColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact Archive
  Widget _buildCompactArchive() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('PROJECT ARCHIVE', Icons.inventory_2),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _buildArchiveOption('Include Audio', true),
                      _buildArchiveOption('Include Presets', true),
                      _buildArchiveOption('Include Plugins', false),
                      _buildArchiveOption('Compress', true),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildExportButton('ARCHIVE', Icons.archive, LowerZoneColors.dawAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveOption(String label, bool enabled) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle : Icons.cancel,
            size: 14,
            color: enabled ? LowerZoneColors.success : LowerZoneColors.textMuted,
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER PANELS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPlaceholderPanel(String title, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: LowerZoneColors.textMuted),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: LowerZoneColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Coming soon...',
            style: TextStyle(
              fontSize: 11,
              color: LowerZoneColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTrackSelectedPanel(String processorName, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: LowerZoneColors.textMuted),
          const SizedBox(height: 12),
          Text(
            processorName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: LowerZoneColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: LowerZoneColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: LowerZoneColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 14, color: LowerZoneColors.warning),
                const SizedBox(width: 8),
                Text(
                  'Select a track to edit $processorName',
                  style: TextStyle(
                    fontSize: 11,
                    color: LowerZoneColors.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoProviderPanel(String title, IconData icon, String providerName) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: LowerZoneColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: LowerZoneColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Requires $providerName',
            style: const TextStyle(
              fontSize: 11,
              color: LowerZoneColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION STRIP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActionStrip() {
    final actions = switch (widget.controller.superTab) {
      DawSuperTab.browse => DawActions.forBrowse(),
      DawSuperTab.edit => DawActions.forEdit(),
      DawSuperTab.mix => DawActions.forMix(),
      DawSuperTab.process => DawActions.forProcess(),
      DawSuperTab.deliver => DawActions.forDeliver(),
    };

    // Add track info to status when in PROCESS tab
    String statusText = 'DAW Ready';
    if (widget.controller.superTab == DawSuperTab.process) {
      final trackId = widget.selectedTrackId;
      statusText = trackId != null ? 'Track $trackId' : 'No track selected';
    }

    return LowerZoneActionStrip(
      actions: actions,
      accentColor: widget.controller.accentColor,
      statusText: statusText,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION CURVE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _AutomationCurvePainter extends CustomPainter {
  final Color color;

  _AutomationCurvePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    // Draw a sample automation curve
    final path = Path();
    final fillPath = Path();

    final points = [
      Offset(0, size.height * 0.6),
      Offset(size.width * 0.15, size.height * 0.4),
      Offset(size.width * 0.3, size.height * 0.35),
      Offset(size.width * 0.45, size.height * 0.7),
      Offset(size.width * 0.6, size.height * 0.5),
      Offset(size.width * 0.75, size.height * 0.25),
      Offset(size.width * 0.9, size.height * 0.45),
      Offset(size.width, size.height * 0.4),
    ];

    path.moveTo(points[0].dx, points[0].dy);
    fillPath.moveTo(points[0].dx, size.height);
    fillPath.lineTo(points[0].dx, points[0].dy);

    for (int i = 1; i < points.length; i++) {
      final cp1x = points[i - 1].dx + (points[i].dx - points[i - 1].dx) / 2;
      final cp1y = points[i - 1].dy;
      final cp2x = points[i - 1].dx + (points[i].dx - points[i - 1].dx) / 2;
      final cp2y = points[i].dy;
      path.cubicTo(cp1x, cp1y, cp2x, cp2y, points[i].dx, points[i].dy);
      fillPath.cubicTo(cp1x, cp1y, cp2x, cp2y, points[i].dx, points[i].dy);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw points
    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final point in points) {
      canvas.drawCircle(point, 4, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// TIMELINE OVERVIEW PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _TimelineOverviewPainter extends CustomPainter {
  final Color color;

  _TimelineOverviewPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = LowerZoneColors.border
      ..strokeWidth = 1;

    // Draw timeline grid
    for (int i = 0; i < 8; i++) {
      final x = (i / 8) * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        linePaint,
      );
    }

    // Draw track lanes
    final trackHeight = size.height / 4;
    for (int i = 0; i < 4; i++) {
      final y = i * trackHeight;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        linePaint,
      );
    }

    // Draw sample clips
    final clips = [
      (0, 0.1, 0.4),
      (0, 0.5, 0.8),
      (1, 0.2, 0.6),
      (2, 0.0, 0.3),
      (2, 0.4, 0.9),
      (3, 0.3, 0.7),
    ];

    for (final (track, start, end) in clips) {
      final rect = Rect.fromLTRB(
        start * size.width + 2,
        track * trackHeight + 4,
        end * size.width - 2,
        (track + 1) * trackHeight - 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );

      // Clip border
      final borderPaint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        borderPaint,
      );
    }

    // Draw playhead
    final playheadPaint = Paint()
      ..color = LowerZoneColors.error
      ..strokeWidth = 2;
    final playheadX = size.width * 0.35;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// FADE CURVE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _FadeCurvePainter extends CustomPainter {
  final Color color;
  final bool isLinear;

  _FadeCurvePainter({required this.color, this.isLinear = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final gridPaint = Paint()
      ..color = LowerZoneColors.border.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Draw grid
    for (int i = 1; i < 4; i++) {
      final x = (i / 4) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (int i = 1; i < 4; i++) {
      final y = (i / 4) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path();
    final fillPath = Path();

    if (isLinear) {
      // Linear fade
      path.moveTo(0, size.height);
      path.lineTo(size.width, 0);

      fillPath.moveTo(0, size.height);
      fillPath.lineTo(size.width, 0);
      fillPath.lineTo(size.width, size.height);
      fillPath.close();
    } else {
      // S-curve fade
      path.moveTo(0, size.height);
      path.cubicTo(
        size.width * 0.3, size.height,
        size.width * 0.7, 0,
        size.width, 0,
      );

      fillPath.moveTo(0, size.height);
      fillPath.cubicTo(
        size.width * 0.3, size.height,
        size.width * 0.7, 0,
        size.width, 0,
      );
      fillPath.lineTo(size.width, size.height);
      fillPath.close();
    }

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO WIDTH PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _StereoWidthPainter extends CustomPainter {
  final double panL;
  final double panR;
  final Color color;

  _StereoWidthPainter({
    required this.panL,
    required this.panR,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background arc
    final bgPaint = Paint()
      ..color = LowerZoneColors.bgSurface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius - 8, bgPaint);

    // Width indicator (pie slice showing stereo image)
    // Map -1..1 to left..right on a semicircle (top half)
    final startAngle = -3.14159 + (panL + 1) * 3.14159 / 2;
    final endAngle = -3.14159 + (panR + 1) * 3.14159 / 2;
    final sweepAngle = endAngle - startAngle;

    if (sweepAngle.abs() > 0.01) {
      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;

      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius - 8),
          startAngle,
          sweepAngle,
          false,
        )
        ..close();

      canvas.drawPath(path, fillPaint);

      // Edge lines
      final edgePaint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      final lX = center.dx + (radius - 8) * math.cos(startAngle);
      final lY = center.dy + (radius - 8) * math.sin(startAngle);
      final rX = center.dx + (radius - 8) * math.cos(endAngle);
      final rY = center.dy + (radius - 8) * math.sin(endAngle);

      canvas.drawLine(center, Offset(lX, lY), edgePaint);
      canvas.drawLine(center, Offset(rX, rY), edgePaint);
    }

    // Center marker
    final centerPaint = Paint()
      ..color = LowerZoneColors.textMuted
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx, center.dy - radius + 4),
      Offset(center.dx, center.dy - 8),
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(_StereoWidthPainter oldDelegate) =>
      panL != oldDelegate.panL || panR != oldDelegate.panR;
}

// ═══════════════════════════════════════════════════════════════════════════════
// EDITABLE CLIP PANEL — Gain, Fade In, Fade Out controls
// ═══════════════════════════════════════════════════════════════════════════════

class _EditableClipPanel extends StatefulWidget {
  final String clipName;
  final double startTime;
  final double duration;
  final double gain; // 0-2, 1 = unity (0 dB)
  final double fadeIn; // seconds
  final double fadeOut; // seconds
  final ValueChanged<double>? onGainChanged;
  final ValueChanged<double>? onFadeInChanged;
  final ValueChanged<double>? onFadeOutChanged;

  const _EditableClipPanel({
    required this.clipName,
    required this.startTime,
    required this.duration,
    required this.gain,
    required this.fadeIn,
    required this.fadeOut,
    this.onGainChanged,
    this.onFadeInChanged,
    this.onFadeOutChanged,
  });

  @override
  State<_EditableClipPanel> createState() => _EditableClipPanelState();
}

class _EditableClipPanelState extends State<_EditableClipPanel> {
  late double _gain;
  late double _fadeIn;
  late double _fadeOut;

  @override
  void initState() {
    super.initState();
    _gain = widget.gain;
    _fadeIn = widget.fadeIn;
    _fadeOut = widget.fadeOut;
  }

  @override
  void didUpdateWidget(_EditableClipPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gain != widget.gain) _gain = widget.gain;
    if (oldWidget.fadeIn != widget.fadeIn) _fadeIn = widget.fadeIn;
    if (oldWidget.fadeOut != widget.fadeOut) _fadeOut = widget.fadeOut;
  }

  // Convert gain (0-2) to dB (-inf to +6)
  String _gainToDb(double gain) {
    if (gain <= 0) return '-∞ dB';
    final db = 20 * (math.log(gain) / math.ln10);
    return '${db.toStringAsFixed(1)} dB';
  }

  // Format time (seconds) to display
  String _formatTime(double seconds) {
    if (seconds < 0.001) return '0 ms';
    if (seconds < 1) return '${(seconds * 1000).round()} ms';
    return '${seconds.toStringAsFixed(2)} s';
  }

  // Format timecode HH:MM:SS.mmm
  String _formatTimecode(double seconds) {
    final h = (seconds / 3600).floor();
    final m = ((seconds % 3600) / 60).floor();
    final s = (seconds % 60).floor();
    final ms = ((seconds * 1000) % 1000).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Read-only info
                  _buildInfoRow('Name', widget.clipName, Icons.audio_file),
                  _buildInfoRow('Start', _formatTimecode(widget.startTime), Icons.start),
                  _buildInfoRow('Duration', _formatTime(widget.duration), Icons.timer),

                  const SizedBox(height: 12),
                  const Divider(color: LowerZoneColors.border, height: 1),
                  const SizedBox(height: 12),

                  // Editable: Gain
                  _buildGainControl(),
                  const SizedBox(height: 12),

                  // Editable: Fade In
                  _buildFadeControl(
                    label: 'Fade In',
                    value: _fadeIn,
                    maxValue: widget.duration / 2,
                    icon: Icons.trending_up,
                    onChanged: (v) {
                      setState(() => _fadeIn = v);
                      widget.onFadeInChanged?.call(v);
                    },
                  ),
                  const SizedBox(height: 8),

                  // Editable: Fade Out
                  _buildFadeControl(
                    label: 'Fade Out',
                    value: _fadeOut,
                    maxValue: widget.duration / 2,
                    icon: Icons.trending_down,
                    onChanged: (v) {
                      setState(() => _fadeOut = v);
                      widget.onFadeOutChanged?.call(v);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.content_cut, size: 14, color: LowerZoneColors.dawAccent),
        const SizedBox(width: 6),
        Text(
          'CLIP PROPERTIES',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.dawAccent,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        // Reset button
        GestureDetector(
          onTap: () {
            setState(() {
              _gain = 1.0;
              _fadeIn = 0.0;
              _fadeOut = 0.0;
            });
            widget.onGainChanged?.call(1.0);
            widget.onFadeInChanged?.call(0.0);
            widget.onFadeOutChanged?.call(0.0);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgSurface,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: LowerZoneColors.border),
            ),
            child: const Text(
              'RESET',
              style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: LowerZoneColors.textMuted),
          const SizedBox(width: 6),
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGainControl() {
    // Gain slider: -inf to +6 dB (mapped from 0 to 2)
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.volume_up, size: 12, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              const Text(
                'Gain',
                style: TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary),
              ),
              const Spacer(),
              // Value display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: LowerZoneColors.bgMid,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _gainToDb(_gain),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _gain > 1.0 ? Colors.orange : LowerZoneColors.dawAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: _gain > 1.0 ? Colors.orange : LowerZoneColors.dawAccent,
              inactiveTrackColor: LowerZoneColors.bgMid,
              thumbColor: _gain > 1.0 ? Colors.orange : LowerZoneColors.dawAccent,
            ),
            child: Slider(
              value: _gain.clamp(0.0, 2.0),
              min: 0.0,
              max: 2.0,
              onChanged: (v) {
                setState(() => _gain = v);
                widget.onGainChanged?.call(v);
              },
            ),
          ),
          // dB scale markers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('-∞', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
              const Text('-12', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
              const Text('0', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
              const Text('+6', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFadeControl({
    required String label,
    required double value,
    required double maxValue,
    required IconData icon,
    required ValueChanged<double> onChanged,
  }) {
    final maxMs = (maxValue * 1000).clamp(10.0, 10000.0);
    final valueMs = value * 1000;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: LowerZoneColors.bgMid,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _formatTime(value),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: LowerZoneColors.dawAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: LowerZoneColors.dawAccent,
              inactiveTrackColor: LowerZoneColors.bgMid,
              thumbColor: LowerZoneColors.dawAccent,
            ),
            child: Slider(
              value: valueMs.clamp(0.0, maxMs),
              min: 0.0,
              max: maxMs,
              onChanged: (ms) => onChanged(ms / 1000),
            ),
          ),
        ],
      ),
    );
  }
}
