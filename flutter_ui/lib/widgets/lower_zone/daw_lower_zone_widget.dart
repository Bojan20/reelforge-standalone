// DAW Lower Zone Widget
//
// Complete Lower Zone for DAW section with:
// - Context bar (Super-tabs + Sub-tabs)
// - Content panel (switches based on current tab)
// - Action strip (context-aware actions)
// - Resizable height
// - Integrated FabFilter DSP panels (EQ, Comp, Limiter, Gate, Reverb)
// - Integrated Mixer, Timeline, Automation, Export panels

import 'dart:io' show Directory, Platform, Process;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'daw_lower_zone_controller.dart';
import 'lower_zone_types.dart';
import 'lower_zone_context_bar.dart';
import 'lower_zone_action_strip.dart';
import '../mixer/ultimate_mixer.dart' as ultimate;
import '../../providers/mixer_provider.dart';
import 'daw_files_browser.dart';
import '../../services/track_preset_service.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../providers/timeline_playback_provider.dart' show TimelineClipData;
import '../../utils/safe_file_picker.dart';
import '../../services/service_locator.dart';
import '../../services/audio_asset_manager.dart';
import '../../services/audio_playback_service.dart';
import '../../utils/input_validator.dart'; // ✅ P0.3: Input validation
import '../../utils/path_validator.dart' as pv;
import '../common/error_boundary.dart'; // ✅ P0.7: Error handling
import '../meters/lufs_meter_widget.dart'; // ✅ P0.2: LUFS metering
import 'workspace_preset_dropdown.dart'; // ✅ P1.1: Workspace presets
import '../../models/workspace_preset.dart'; // ✅ P1.1: WorkspaceSection enum
// ✅ P0.1: Extracted BROWSE panels
import 'daw/browse/track_presets_panel.dart';
import 'daw/browse/plugins_scanner_panel.dart';
import 'daw/browse/history_panel.dart';
// ✅ P0.1: Extracted EDIT panels
import 'daw/edit/timeline_overview_panel.dart';
import 'daw/edit/grid_settings_panel.dart';
import 'daw/edit/piano_roll_panel.dart';
import 'daw/edit/clip_properties_panel.dart';
// ✅ P2: Advanced EDIT panels
import 'daw/edit/punch_recording_panel.dart';
import 'daw/edit/comping_panel.dart';
import 'daw/edit/audio_warping_panel.dart';
import 'daw/edit/elastic_audio_panel.dart';
import 'daw/edit/beat_detective_panel.dart';
import 'daw/edit/strip_silence_panel.dart';
// ✅ P0.1: Extracted MIX panels
import 'daw/mix/sends_panel.dart';
import 'daw/mix/pan_panel.dart';
import 'daw/mix/automation_panel.dart';
// ✅ P0.1: Extracted PROCESS panels
import 'daw/process/eq_panel.dart';
import 'daw/process/comp_panel.dart';
import 'daw/process/limiter_panel.dart';
import 'daw/process/reverb_panel.dart';
import 'daw/process/gate_panel.dart';
import 'daw/process/fx_chain_panel.dart';
import 'daw/process/sidechain_panel.dart'; // ✅ P0.5: Sidechain UI
import 'daw/process/delay_panel.dart'; // ✅ FF-D Delay
import 'daw/process/saturation_panel_wrapper.dart'; // ✅ FF-SAT Saturator
import 'daw/process/deesser_panel.dart'; // ✅ FF-E DeEsser
// ✅ P0.1: Extracted DELIVER panels
import 'daw/deliver/export_panel.dart';
import 'daw/deliver/stems_panel.dart';
import 'daw/deliver/bounce_panel.dart';
import 'daw/deliver/archive_panel.dart';
// Gate and Reverb are accessible via FX Chain panel

class DawLowerZoneWidget extends StatefulWidget {
  final DawLowerZoneController controller;

  /// Currently selected track ID for DSP processing
  /// If null, DSP panels will show "No track selected"
  final int? selectedTrackId;

  /// Currently selected track name for display in context bar
  final String? selectedTrackName;

  /// Currently selected track color for display badge
  final Color? selectedTrackColor;

  /// Callback when a DSP panel action is triggered
  final void Function(String action, Map<String, dynamic>? params)? onDspAction;

  // ─── P0.2: Grid/Snap Settings ─────────────────────────────────────────────
  /// Whether snap to grid is enabled
  final bool snapEnabled;

  /// Current snap value in beats (0.25=1/16, 0.5=1/8, 1.0=1/4, 2.0=1/2, 4.0=bar)
  final double snapValue;

  /// Whether triplet grid is enabled
  final bool tripletGrid;

  /// Callback when snap enabled changes
  final ValueChanged<bool>? onSnapEnabledChanged;

  /// Callback when snap value changes
  final ValueChanged<double>? onSnapValueChanged;

  /// Callback when triplet grid changes
  final ValueChanged<bool>? onTripletGridChanged;

  // ─── P1.4: Timeline Settings (Tempo, Time Signature, Markers) ───────────────
  /// Current tempo in BPM
  final double tempo;

  /// Time signature numerator (beats per bar)
  final int timeSignatureNumerator;

  /// Time signature denominator (beat value: 2=half, 4=quarter, 8=eighth)
  final int timeSignatureDenominator;

  /// Callback when tempo changes
  final ValueChanged<double>? onTempoChanged;

  /// Callback when time signature changes (numerator, denominator)
  final void Function(int numerator, int denominator)? onTimeSignatureChanged;

  // ─── P1.3: Selected Clip for Clip Properties Panel ──────────────────────────
  /// Currently selected clip for editing in Clips panel
  /// If null, shows placeholder message
  final TimelineClipData? selectedClip;

  /// Callback when clip gain is changed (0-2, 1=unity)
  final void Function(String clipId, double gain)? onClipGainChanged;

  /// Callback when clip fade in is changed (seconds)
  final void Function(String clipId, double fadeIn)? onClipFadeInChanged;

  /// Callback when clip fade out is changed (seconds)
  final void Function(String clipId, double fadeOut)? onClipFadeOutChanged;

  const DawLowerZoneWidget({
    super.key,
    required this.controller,
    this.selectedTrackId,
    this.selectedTrackName,
    this.selectedTrackColor,
    this.onDspAction,
    this.snapEnabled = true,
    this.snapValue = 0.25,
    this.tripletGrid = false,
    this.onSnapEnabledChanged,
    this.onSnapValueChanged,
    this.onTripletGridChanged,
    this.tempo = 120.0,
    this.timeSignatureNumerator = 4,
    this.timeSignatureDenominator = 4,
    this.onTempoChanged,
    this.onTimeSignatureChanged,
    this.selectedClip,
    this.onClipGainChanged,
    this.onClipFadeInChanged,
    this.onClipFadeOutChanged,
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

  /// P1.4: Returns tooltips for current sub-tabs based on active super-tab
  List<String> _getCurrentSubTabTooltips() {
    switch (widget.controller.superTab) {
      case DawSuperTab.browse:
        return DawBrowseSubTab.values.map((t) => t.tooltip).toList();
      case DawSuperTab.edit:
        return DawEditSubTab.values.map((t) => t.tooltip).toList();
      case DawSuperTab.mix:
        return DawMixSubTab.values.map((t) => t.tooltip).toList();
      case DawSuperTab.process:
        return DawProcessSubTab.values.map((t) => t.tooltip).toList();
      case DawSuperTab.deliver:
        return DawDeliverSubTab.values.map((t) => t.tooltip).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: kLowerZoneAnimationDuration,
      height: widget.controller.totalHeight,
      clipBehavior: Clip.hardEdge,
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
            superTabTooltips: DawSuperTab.values.map((t) => t.tooltip).toList(),
            selectedSuperTab: widget.controller.superTab.index,
            subTabLabels: widget.controller.subTabLabels,
            subTabTooltips: _getCurrentSubTabTooltips(),
            selectedSubTab: widget.controller.currentSubTabIndex,
            accentColor: widget.controller.accentColor,
            isExpanded: widget.controller.isExpanded,
            onSuperTabSelected: widget.controller.setSuperTabIndex,
            onSubTabSelected: widget.controller.setSubTabIndex,
            onToggle: widget.controller.toggle,
            trackIndicator: _buildTrackIndicator(),
            // P1.5: Recent tabs quick access
            recentTabs: widget.controller.recentTabs,
            onRecentTabSelected: widget.controller.goToRecentTab,
            // ✅ P1.1: Workspace presets dropdown
            presetDropdown: WorkspacePresetDropdown(
              section: WorkspaceSection.daw,
              accentColor: widget.controller.accentColor,
              onPresetApplied: _applyWorkspacePreset,
              getCurrentState: _getCurrentWorkspaceState,
            ),
            // ✅ P2.1: Split view controls
            splitEnabled: widget.controller.splitEnabled,
            splitDirection: widget.controller.splitDirection,
            onSplitToggle: widget.controller.toggleSplitView,
            onSplitDirectionToggle: widget.controller.toggleSplitDirection,
            onSwapPanes: widget.controller.swapPanes,
            // Multi-pane panel count
            panelCount: widget.controller.panelCount,
            onPanelCountChanged: widget.controller.setPanelCount,
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

  /// Build track name indicator badge for the context bar
  Widget? _buildTrackIndicator() {
    final name = widget.selectedTrackName;
    if (name == null || name.isEmpty) return null;

    final color = widget.selectedTrackColor ?? widget.controller.accentColor;

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(
              fontSize: LowerZoneTypography.sizeLabel,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
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
    // Multi-pane mode (2, 3, or 4 panels)
    if (widget.controller.panelCount > 1) {
      return _buildMultiPaneContent();
    }

    return Container(
      color: LowerZoneColors.bgDeep,
      child: ErrorBoundary( // ✅ P0.7: Wrap content in error boundary
        errorTitle: '${widget.controller.superTab.label} Panel Error',
        child: _getContentForCurrentTab(),
        fallbackBuilder: (error, stack) {
          return ErrorPanel(
            title: 'Failed to load ${widget.controller.superTab.label} panel',
            message: 'The panel encountered an error and cannot be displayed.',
            error: error,
            onRetry: () {
              // Retry by triggering rebuild
              setState(() {});
            },
          );
        },
        onError: (error, stack) {
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P2.1: SPLIT VIEW MODE — View 2 panels simultaneously
  // ═══════════════════════════════════════════════════════════════════════════

  /// Build multi-pane content for 2, 3, or 4 panels
  Widget _buildMultiPaneContent() {
    final panelCount = widget.controller.panelCount;
    final ratios = widget.controller.splitRatios;

    if (panelCount == 4) {
      return _build4PaneGrid(ratios);
    }

    // 2 or 3 panels: linear layout (horizontal or vertical)
    final isHorizontal = widget.controller.splitDirection == SplitDirection.horizontal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalSize = isHorizontal ? constraints.maxWidth : constraints.maxHeight;
        final dividerCount = panelCount - 1;
        final availableSize = totalSize - (dividerCount * kSplitDividerWidth);

        // Calculate pane sizes from cumulative ratios
        final paneSizes = <double>[];
        double prevRatio = 0.0;
        for (int i = 0; i < panelCount; i++) {
          final nextRatio = i < ratios.length ? ratios[i] : 1.0;
          paneSizes.add(availableSize * (nextRatio - prevRatio));
          prevRatio = nextRatio;
        }
        // Last pane gets remaining space
        if (paneSizes.length == panelCount) {
          paneSizes[panelCount - 1] = availableSize * (1.0 - (ratios.isNotEmpty ? ratios.last : 0.0));
        }

        final children = <Widget>[];
        for (int i = 0; i < panelCount; i++) {
          if (i > 0) {
            children.add(_buildSplitDividerIndexed(
              isHorizontal: isHorizontal,
              dividerIndex: i - 1,
              constraints: constraints,
            ));
          }
          children.add(SizedBox(
            width: isHorizontal ? paneSizes[i] : null,
            height: isHorizontal ? null : paneSizes[i],
            child: _buildPaneForIndex(i),
          ));
        }

        return isHorizontal
            ? Row(children: children)
            : Column(children: children);
      },
    );
  }

  /// Build 2x2 grid layout for 4 panels
  Widget _build4PaneGrid(List<double> ratios) {
    final hRatio = ratios.isNotEmpty ? ratios[0] : 0.5;
    final vRatio = ratios.length > 1 ? ratios[1] : 0.5;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalW = constraints.maxWidth;
        final totalH = constraints.maxHeight;
        final availW = totalW - kSplitDividerWidth;
        final availH = totalH - kSplitDividerWidth;
        final leftW = availW * hRatio;
        final rightW = availW * (1 - hRatio);
        final topH = availH * vRatio;
        final bottomH = availH * (1 - vRatio);

        return Column(
          children: [
            // Top row: Pane 0 | Pane 1
            SizedBox(
              height: topH,
              child: Row(
                children: [
                  SizedBox(width: leftW, child: _buildPaneForIndex(0)),
                  _buildSplitDividerIndexed(
                    isHorizontal: true,
                    dividerIndex: 0,
                    constraints: constraints,
                  ),
                  SizedBox(width: rightW, child: _buildPaneForIndex(1)),
                ],
              ),
            ),
            // Horizontal divider between rows
            _buildSplitDividerIndexed(
              isHorizontal: false,
              dividerIndex: 1,
              constraints: constraints,
            ),
            // Bottom row: Pane 2 | Pane 3
            SizedBox(
              height: bottomH,
              child: Row(
                children: [
                  SizedBox(width: leftW, child: _buildPaneForIndex(2)),
                  _buildSplitDividerIndexed(
                    isHorizontal: true,
                    dividerIndex: 0,
                    constraints: constraints,
                  ),
                  SizedBox(width: rightW, child: _buildPaneForIndex(3)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Build a pane widget for a given index using controller's per-pane state
  Widget _buildPaneForIndex(int paneIndex) {
    return _buildPaneWithHeader(
      superTab: widget.controller.getPaneSuperTab(paneIndex),
      subTabIndex: widget.controller.getPaneSubTabIndex(paneIndex),
      onSuperTabChanged: (tab) => widget.controller.setPaneSuperTab(paneIndex, tab),
      onSubTabChanged: (idx) => widget.controller.setPaneSubTabIndex(paneIndex, idx),
      paneIndex: paneIndex,
    );
  }

  /// Build a draggable divider at a specific index
  Widget _buildSplitDividerIndexed({
    required bool isHorizontal,
    required int dividerIndex,
    required BoxConstraints constraints,
  }) {
    return GestureDetector(
      onPanUpdate: (details) {
        final totalSize = isHorizontal ? constraints.maxWidth : constraints.maxHeight;
        final delta = isHorizontal ? details.delta.dx : details.delta.dy;
        final currentRatios = widget.controller.splitRatios;
        if (dividerIndex < currentRatios.length) {
          final newRatio = currentRatios[dividerIndex] + (delta / totalSize);
          widget.controller.setSplitRatioAtIndex(dividerIndex, newRatio);
        }
      },
      child: MouseRegion(
        cursor: isHorizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
        child: Container(
          width: isHorizontal ? kSplitDividerWidth : null,
          height: isHorizontal ? null : kSplitDividerWidth,
          color: LowerZoneColors.bgMid,
          child: Center(
            child: Container(
              width: isHorizontal ? 2 : 24,
              height: isHorizontal ? 24 : 2,
              decoration: BoxDecoration(
                color: LowerZoneColors.border,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaneWithHeader({
    required DawSuperTab superTab,
    required int subTabIndex,
    required void Function(DawSuperTab) onSuperTabChanged,
    required void Function(int) onSubTabChanged,
    required int paneIndex,
  }) {
    return Container(
      color: LowerZoneColors.bgDeep,
      child: Column(
        children: [
          // Mini tab bar for this pane
          _buildPaneTabBar(
            superTab: superTab,
            subTabIndex: subTabIndex,
            onSuperTabChanged: onSuperTabChanged,
            onSubTabChanged: onSubTabChanged,
            paneIndex: paneIndex,
          ),
          // Content
          Expanded(
            child: ErrorBoundary(
              errorTitle: '${superTab.label} Panel Error',
              child: _getContentForSuperTab(superTab, subTabIndex),
              fallbackBuilder: (error, stack) {
                return ErrorPanel(
                  title: 'Failed to load ${superTab.label} panel',
                  message: 'The panel encountered an error.',
                  error: error,
                  onRetry: () => setState(() {}),
                );
              },
              onError: (error, stack) {
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaneTabBar({
    required DawSuperTab superTab,
    required int subTabIndex,
    required void Function(DawSuperTab) onSuperTabChanged,
    required void Function(int) onSubTabChanged,
    required int paneIndex,
  }) {
    final subTabLabels = _getSubTabLabelsForSuperTab(superTab);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        border: Border(
          bottom: BorderSide(color: LowerZoneColors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // Super-tab dropdown
          PopupMenuButton<DawSuperTab>(
            initialValue: superTab,
            tooltip: 'Change panel type',
            onSelected: onSuperTabChanged,
            itemBuilder: (context) => DawSuperTab.values.map((tab) {
              return PopupMenuItem(
                value: tab,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tab.icon, size: 14, color: tab == superTab ? LowerZoneColors.dawAccent : LowerZoneColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(tab.label, style: TextStyle(
                      fontSize: 11,
                      color: tab == superTab ? LowerZoneColors.dawAccent : LowerZoneColors.textSecondary,
                    )),
                  ],
                ),
              );
            }).toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: LowerZoneColors.dawAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(superTab.icon, size: 12, color: LowerZoneColors.dawAccent),
                  const SizedBox(width: 4),
                  Text(superTab.label, style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: LowerZoneColors.dawAccent,
                  )),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_drop_down, size: 14, color: LowerZoneColors.dawAccent),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Sub-tabs
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(subTabLabels.length, (index) {
                  final isSelected = index == subTabIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      onTap: () => onSubTabChanged(index),
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? LowerZoneColors.dawAccent.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          subTabLabels[index],
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.textTertiary,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // NOTE: _buildSplitDivider replaced by _buildSplitDividerIndexed above

  List<String> _getSubTabLabelsForSuperTab(DawSuperTab superTab) {
    return switch (superTab) {
      DawSuperTab.browse => DawBrowseSubTab.values.map((e) => e.label).toList(),
      DawSuperTab.edit => DawEditSubTab.values.map((e) => e.label).toList(),
      DawSuperTab.mix => DawMixSubTab.values.map((e) => e.label).toList(),
      DawSuperTab.process => DawProcessSubTab.values.map((e) => e.label).toList(),
      DawSuperTab.deliver => DawDeliverSubTab.values.map((e) => e.label).toList(),
    };
  }

  /// Get content widget for a specific super-tab and sub-tab index
  Widget _getContentForSuperTab(DawSuperTab superTab, int subTabIndex) {
    return switch (superTab) {
      DawSuperTab.browse => _getBrowseContentForIndex(subTabIndex),
      DawSuperTab.edit => _getEditContentForIndex(subTabIndex),
      DawSuperTab.mix => _getMixContentForIndex(subTabIndex),
      DawSuperTab.process => _getProcessContentForIndex(subTabIndex),
      DawSuperTab.deliver => _getDeliverContentForIndex(subTabIndex),
    };
  }

  Widget _getBrowseContentForIndex(int index) {
    return switch (DawBrowseSubTab.values[index.clamp(0, 3)]) {
      DawBrowseSubTab.files => _buildFilesPanel(),
      DawBrowseSubTab.presets => _buildPresetsPanel(),
      DawBrowseSubTab.plugins => _buildPluginsPanel(),
      DawBrowseSubTab.history => _buildHistoryPanel(),
    };
  }

  Widget _getEditContentForIndex(int index) {
    return switch (DawEditSubTab.values[index.clamp(0, DawEditSubTab.values.length - 1)]) {
      DawEditSubTab.timeline => _buildTimelinePanel(),
      DawEditSubTab.pianoRoll => _buildPianoRollPanel(),
      DawEditSubTab.fades => _buildFadesPanel(),
      DawEditSubTab.grid => _buildGridPanel(),
      DawEditSubTab.punch => _buildPunchRecordingPanel(),
      DawEditSubTab.comping => _buildCompingPanel(),
      DawEditSubTab.warp => _buildAudioWarpingPanel(),
      DawEditSubTab.elastic => _buildElasticAudioPanel(),
      DawEditSubTab.beatDetect => _buildBeatDetectivePanel(),
      DawEditSubTab.stripSilence => _buildStripSilencePanel(),
    };
  }

  Widget _getMixContentForIndex(int index) {
    return switch (DawMixSubTab.values[index.clamp(0, 3)]) {
      DawMixSubTab.mixer => _buildMixerPanel(),
      DawMixSubTab.sends => _buildSendsPanel(),
      DawMixSubTab.pan => _buildPanPanel(),
      DawMixSubTab.automation => _buildAutomationPanel(),
    };
  }

  Widget _getProcessContentForIndex(int index) {
    return switch (DawProcessSubTab.values[index.clamp(0, 9)]) {
      DawProcessSubTab.eq => _buildEqPanel(),
      DawProcessSubTab.comp => _buildCompPanel(),
      DawProcessSubTab.limiter => _buildLimiterPanel(),
      DawProcessSubTab.reverb => _buildReverbPanel(),
      DawProcessSubTab.gate => _buildGatePanel(),
      DawProcessSubTab.delay => _buildDelayPanel(),
      DawProcessSubTab.saturation => _buildSaturationPanel(),
      DawProcessSubTab.deEsser => _buildDeEsserPanel(),
      DawProcessSubTab.fxChain => _buildFxChainPanel(),
      DawProcessSubTab.sidechain => _buildSidechainPanel(),
    };
  }

  Widget _getDeliverContentForIndex(int index) {
    return switch (DawDeliverSubTab.values[index.clamp(0, 3)]) {
      DawDeliverSubTab.export => _buildExportPanel(),
      DawDeliverSubTab.stems => _buildStemsPanel(),
      DawDeliverSubTab.bounce => _buildBouncePanel(),
      DawDeliverSubTab.archive => _buildArchivePanel(),
    };
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

  /// P3.1: Files browser with hover preview
  Widget _buildFilesPanel() => const DawFilesBrowserPanel();

  /// ✅ P0.1: Extracted panels (replace inline builders with panel widgets)
  Widget _buildPresetsPanel() => TrackPresetsPanel(onPresetAction: widget.onDspAction);
  Widget _buildPluginsPanel() => const PluginsScannerPanel();
  Widget _buildHistoryPanel() => const HistoryPanel();

  /// Compact files browser


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

  /// P0.1: Track Presets Browser with real service integration
  // ✅ P0.1: BROWSE panels extracted to daw/browse/*.dart
  // Old code removed: Presets (459-827), Plugins (829-1236), History (1238-1420)
  // Total removed: ~962 LOC

  Widget _buildEditContent() {
    final subTab = widget.controller.state.editSubTab;
    return switch (subTab) {
      DawEditSubTab.timeline => _buildTimelinePanel(),
      DawEditSubTab.pianoRoll => _buildPianoRollPanel(),
      DawEditSubTab.fades => _buildFadesPanel(),
      DawEditSubTab.grid => _buildGridPanel(),
      DawEditSubTab.punch => _buildPunchRecordingPanel(),
      DawEditSubTab.comping => _buildCompingPanel(),
      DawEditSubTab.warp => _buildAudioWarpingPanel(),
      DawEditSubTab.elastic => _buildElasticAudioPanel(),
      DawEditSubTab.beatDetect => _buildBeatDetectivePanel(),
      DawEditSubTab.stripSilence => _buildStripSilencePanel(),
    };
  }

  /// ✅ P0.1: Extracted EDIT panels (replaced inline builders)
  Widget _buildTimelinePanel() => const TimelineOverviewPanel();

  Widget _buildPianoRollPanel() => PianoRollPanel(
    selectedTrackId: widget.selectedTrackId,
    tempo: widget.tempo,
    onAction: widget.onDspAction,
  );

  Widget _buildFadesPanel() => const FadesPanel(); // Wrapper for CrossfadeEditor

  Widget _buildGridPanel() => GridSettingsPanel(
    tempo: widget.tempo,
    timeSignatureNumerator: widget.timeSignatureNumerator,
    timeSignatureDenominator: widget.timeSignatureDenominator,
    snapEnabled: widget.snapEnabled,
    tripletGrid: widget.tripletGrid,
    snapValue: widget.snapValue,
    onTempoChanged: widget.onTempoChanged,
    onTimeSignatureChanged: widget.onTimeSignatureChanged,
    onSnapEnabledChanged: widget.onSnapEnabledChanged,
    onTripletGridChanged: widget.onTripletGridChanged,
    onSnapValueChanged: widget.onSnapValueChanged,
  );

  // ✅ P2: Advanced EDIT panels
  Widget _buildPunchRecordingPanel() => PunchRecordingPanel(
    selectedTrackId: widget.selectedTrackId,
    onAction: widget.onDspAction,
  );

  Widget _buildCompingPanel() => CompingPanel(
    selectedTrackId: widget.selectedTrackId,
    onAction: widget.onDspAction,
  );

  Widget _buildAudioWarpingPanel() => AudioWarpingPanel(
    selectedTrackId: widget.selectedTrackId,
  );

  Widget _buildElasticAudioPanel() => ElasticAudioPanel(
    selectedTrackId: widget.selectedTrackId,
    onAction: widget.onDspAction,
  );

  Widget _buildBeatDetectivePanel() => BeatDetectivePanel(
    selectedTrackId: widget.selectedTrackId,
    tempo: widget.tempo,
    onAction: widget.onDspAction,
  );

  Widget _buildStripSilencePanel() => StripSilencePanel(
    selectedTrackId: widget.selectedTrackId,
    onAction: widget.onDspAction,
  );

  /// Compact Timeline Overview
  // ✅ P0.1: Timeline Overview extracted to daw/edit/timeline_overview_panel.dart
  // Old code removed (was lines 1459-1642, ~184 LOC)

  // ✅ P0.1: Piano Roll extracted to daw/edit/piano_roll_panel.dart
  // Old code removed (was lines 1462-1559, ~98 LOC)

  /// P1.3: Compact Clip Properties — Connected to selectedClip
  /// Displays and allows editing of selected clip properties
  // ✅ P0.1: Clip Properties + Fades extracted to daw/edit/clip_properties_panel.dart
  // Old code removed (was lines 1467-1597, ~131 LOC)

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

    // ✅ P0.2: Wrap mixer with LUFS meter header
    return Column(
      children: [
        // LUFS Meter Header (master bus loudness)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A20),
            border: Border(
              bottom: BorderSide(color: const Color(0xFF242430), width: 1),
            ),
          ),
          child: Row(
            children: [
              const Text(
                'MASTER LOUDNESS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF909090),
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              LufsBadge(fontSize: 10, showIcon: true),
            ],
          ),
        ),
        // Mixer console
        Expanded(
          child: ultimate.UltimateMixer(
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
          mixerProvider.setVcaLevelWithUndo(id, volume);
        } else if (id == mixerProvider.master.id) {
          mixerProvider.setMasterVolumeWithUndo(volume);
        } else {
          mixerProvider.setChannelVolumeWithUndo(id, volume);
        }
      },
      onPanChange: (id, pan) => mixerProvider.setChannelPanWithUndo(id, pan),
      onPanRightChange: (id, pan) => mixerProvider.setChannelPanRightWithUndo(id, pan),
      onMuteToggle: (id) {
        if (mixerProvider.vcas.any((v) => v.id == id)) {
          mixerProvider.toggleVcaMute(id);
        } else {
          mixerProvider.toggleChannelMuteWithUndo(id);
        }
      },
      onSoloToggle: (id) => mixerProvider.toggleChannelSoloWithUndo(id),
      onArmToggle: (id) => mixerProvider.toggleChannelArm(id),
      // === SENDS ===
      onSendLevelChange: (channelId, sendIndex, level) {
        final ch = mixerProvider.channels.firstWhere(
          (c) => c.id == channelId,
          orElse: () => mixerProvider.channels.first,
        );
        if (sendIndex < ch.sends.length) {
          final auxId = ch.sends[sendIndex].auxId;
          mixerProvider.setAuxSendLevelWithUndo(channelId, auxId, level);
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
          ), // End UltimateMixer
        ), // End Expanded
      ], // End Column children
    ); // End Column
  }

  /// ✅ P0.1: Extracted MIX panels
  Widget _buildSendsPanel() => const SendsPanel();
  Widget _buildPanPanel() => PanPanel(selectedTrackId: widget.selectedTrackId);
  Widget _buildAutomationPanel() => AutomationPanel(selectedTrackId: widget.selectedTrackId);

  // ═══════════════════════════════════════════════════════════════════════════
  // PROCESS CONTENT — FabFilter DSP Panels
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProcessContent() {
    final subTab = widget.controller.state.processSubTab;
    return switch (subTab) {
      DawProcessSubTab.eq => _buildEqPanel(),
      DawProcessSubTab.comp => _buildCompPanel(),
      DawProcessSubTab.limiter => _buildLimiterPanel(),
      DawProcessSubTab.reverb => _buildReverbPanel(),
      DawProcessSubTab.gate => _buildGatePanel(),
      DawProcessSubTab.delay => _buildDelayPanel(),
      DawProcessSubTab.saturation => _buildSaturationPanel(),
      DawProcessSubTab.deEsser => _buildDeEsserPanel(),
      DawProcessSubTab.fxChain => _buildFxChainPanel(),
      DawProcessSubTab.sidechain => _buildSidechainPanel(),
    };
  }

  /// FF-Q 64-band Parametric EQ
  /// ✅ P0.1: Extracted PROCESS panels
  Widget _buildEqPanel() => EqPanel(selectedTrackId: widget.selectedTrackId);

  /// FF-C Compressor
  Widget _buildCompPanel() => CompPanel(selectedTrackId: widget.selectedTrackId);

  /// FF-L Limiter
  Widget _buildLimiterPanel() => LimiterPanel(selectedTrackId: widget.selectedTrackId);

  /// FF-R Reverb
  Widget _buildReverbPanel() => ReverbPanel(selectedTrackId: widget.selectedTrackId);

  /// FF-G Gate
  Widget _buildGatePanel() => GatePanel(selectedTrackId: widget.selectedTrackId);

  /// FF-D Delay (Timeless 3 Style)
  Widget _buildDelayPanel() => DelayPanel(selectedTrackId: widget.selectedTrackId);

  /// FF-SAT Saturator (Saturn 2)
  Widget _buildSaturationPanel() => SaturationPanelWrapper(selectedTrackId: widget.selectedTrackId);

  /// FF-E De-Esser
  Widget _buildDeEsserPanel() => DeEsserPanel(selectedTrackId: widget.selectedTrackId);

  /// P0.4: FX Chain — Shows all processors in chain with reorder support
  Widget _buildFxChainPanel() => FxChainPanel(
    selectedTrackId: widget.selectedTrackId,
    onNavigateToSubTab: (subTab) => widget.controller.setProcessSubTab(subTab),
  );

  /// P0.5: Sidechain — External/internal sidechain routing configuration
  Widget _buildSidechainPanel() => SidechainPanel(
    selectedTrackId: widget.selectedTrackId,
  );


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

  /// P2.1: Functional export panel with FFI integration
  /// ✅ P0.1: Extracted DELIVER panels
  Widget _buildExportPanel() => const ExportPanel();

  /// P2.1: Functional stems panel with track/bus selection
  Widget _buildStemsPanel() => const StemsPanel();

  /// P2.1: Functional realtime bounce with progress
  Widget _buildBouncePanel() => const BouncePanel();

  /// Archive panel (project packaging)
  Widget _buildArchivePanel() => const ArchivePanel();

  // Note: _buildCompactExportSettings, _buildCompactStemExport, _buildCompactBounce
  // removed — replaced by DawExportPanel, DawStemsPanel, DawBouncePanel (P2.1)


  // ═══════════════════════════════════════════════════════════════════════════
  // EMPTY STATE PANELS
  // ═══════════════════════════════════════════════════════════════════════════

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
  // WORKSPACE PRESETS (P1.1)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Apply a workspace preset to the current layout
  void _applyWorkspacePreset(WorkspacePreset preset) {
    // Apply super tab from first activeTabs entry
    if (preset.activeTabs.isNotEmpty) {
      final tabIndex = DawSuperTab.values.indexWhere(
        (t) => t.name == preset.activeTabs.first,
      );
      if (tabIndex >= 0) {
        widget.controller.setSuperTabIndex(tabIndex);
      }
    }

    // Apply height
    widget.controller.setHeight(preset.lowerZoneHeight);

    // Apply expanded state
    if (!preset.lowerZoneExpanded && widget.controller.isExpanded) {
      widget.controller.toggle();
    } else if (preset.lowerZoneExpanded && !widget.controller.isExpanded) {
      widget.controller.toggle();
    }
  }

  /// Get current workspace state for saving as preset
  WorkspacePreset _getCurrentWorkspaceState() {
    final now = DateTime.now();
    return WorkspacePreset(
      id: 'custom_${now.millisecondsSinceEpoch}',
      name: 'Custom Preset',
      section: WorkspaceSection.daw,
      activeTabs: [widget.controller.superTab.name],
      lowerZoneHeight: widget.controller.height,
      lowerZoneExpanded: widget.controller.isExpanded,
      createdAt: now,
      modifiedAt: now,
      isBuiltIn: false,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION STRIP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Map PROCESS subtab to DspNodeType for insert chain operations
  DspNodeType? _nodeTypeForCurrentSubTab() {
    return switch (widget.controller.state.processSubTab) {
      DawProcessSubTab.eq => DspNodeType.eq,
      DawProcessSubTab.comp => DspNodeType.compressor,
      DawProcessSubTab.limiter => DspNodeType.limiter,
      DawProcessSubTab.reverb => DspNodeType.reverb,
      DawProcessSubTab.gate => DspNodeType.gate,
      DawProcessSubTab.delay => DspNodeType.delay,
      DawProcessSubTab.saturation => DspNodeType.multibandSaturation,
      DawProcessSubTab.deEsser => DspNodeType.deEsser,
      DawProcessSubTab.fxChain => null,
      DawProcessSubTab.sidechain => null,
    };
  }

  /// Dynamic label for the Add button based on current PROCESS subtab
  String _addLabelForCurrentSubTab() {
    return switch (widget.controller.state.processSubTab) {
      DawProcessSubTab.eq => 'Add EQ',
      DawProcessSubTab.comp => 'Add Comp',
      DawProcessSubTab.limiter => 'Add Limiter',
      DawProcessSubTab.reverb => 'Add Reverb',
      DawProcessSubTab.gate => 'Add Gate',
      DawProcessSubTab.delay => 'Add Delay',
      DawProcessSubTab.saturation => 'Add Saturn',
      DawProcessSubTab.deEsser => 'Add DeEss',
      DawProcessSubTab.fxChain => 'Add Insert',
      DawProcessSubTab.sidechain => 'Sidechain',
    };
  }

  /// Build PROCESS tab actions — subtab-aware
  List<LowerZoneAction> _buildProcessActions() {
    final trackId = widget.selectedTrackId;
    final nodeType = _nodeTypeForCurrentSubTab();
    final dspChain = DspChainProvider.instance;

    return DawActions.forProcess(
      addLabel: _addLabelForCurrentSubTab(),
      onAdd: trackId != null && nodeType != null ? () {
        dspChain.addNode(trackId, nodeType);
      } : null,
      onRemove: trackId != null ? () {
        final chain = dspChain.getChain(trackId);
        // Remove the processor matching current subtab, or last if none found
        if (chain.nodes.isNotEmpty) {
          final matching = chain.nodes.where((n) => n.type == nodeType).toList();
          if (matching.isNotEmpty) {
            dspChain.removeNode(trackId, matching.last.id);
          } else {
            dspChain.removeNode(trackId, chain.nodes.last.id);
          }
        }
      } : null,
      onCopy: trackId != null ? () {
        // Copy current processor settings to clipboard
        final chain = dspChain.getChain(trackId);
        final matching = chain.nodes.where((n) => n.type == nodeType).toList();
        if (matching.isNotEmpty) {
          widget.onDspAction?.call('copyDspSettings', {
            'trackId': trackId,
            'nodeType': nodeType?.name,
          });
        }
      } : null,
      onBypass: trackId != null ? () {
        final chain = dspChain.getChain(trackId);
        // Toggle bypass only on matching processor type, not all
        final matching = chain.nodes.where((n) => n.type == nodeType).toList();
        if (matching.isNotEmpty) {
          for (final node in matching) {
            dspChain.toggleNodeBypass(trackId, node.id);
          }
        } else {
          // Fallback: toggle all if no matching type
          for (final node in chain.nodes) {
            dspChain.toggleNodeBypass(trackId, node.id);
          }
        }
      } : null,
    );
  }

  Widget _buildActionStrip() {
    final actions = switch (widget.controller.superTab) {
      DawSuperTab.browse => DawActions.forBrowse(
        onImport: () async {
          // Import audio files via FilePicker
          final result = await SafeFilePicker.pickFiles(context,
            type: FileType.custom,
            allowedExtensions: pv.PathValidator.allowedExtensions,
            allowMultiple: true,
          );
          if (result != null && result.files.isNotEmpty) {
            final assetManager = sl<AudioAssetManager>();
            final paths = result.files
                .where((f) => f.path != null)
                .map((f) => f.path!)
                .toList();

            // ✅ P0.3: Validate all paths before import
            final validPaths = <String>[];
            final invalidPaths = <String>[];
            for (final path in paths) {
              final error = PathValidator.validate(path, checkExists: true);
              if (error == null) {
                validPaths.add(path);
              } else {
                invalidPaths.add(path);
              }
            }

            // Import only valid paths
            if (validPaths.isNotEmpty) {
              await assetManager.importFiles(validPaths, folder: 'Imported');
            }

            // Show warning if some paths were invalid
            if (invalidPaths.isNotEmpty && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${invalidPaths.length} file(s) skipped (invalid path or type)'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        },
        onDelete: () {
          // Delete selected asset from AudioAssetManager
          final assetManager = sl<AudioAssetManager>();
          final selectedPath = assetManager.selectedAssetPath;
          if (selectedPath != null) {
            assetManager.removeByPath(selectedPath);
          }
        },
        onPreview: () {
          // Preview selected audio file
          final assetManager = sl<AudioAssetManager>();
          final selectedPath = assetManager.selectedAssetPath;
          if (selectedPath != null) {
            AudioPlaybackService.instance.previewFile(selectedPath);
          }
        },
        onAddToProject: () {
          // Add selected asset to timeline via callback
          widget.onDspAction?.call('addToProject', {
            'path': sl<AudioAssetManager>().selectedAssetPath,
          });
        },
      ),
      DawSuperTab.edit => DawActions.forEdit(
        onAddTrack: () {
          // Create new audio track in mixer
          final mixer = context.read<MixerProvider>();
          final channel = mixer.createChannel(
            name: 'Audio ${mixer.channelCount + 1}',
          );
          widget.onDspAction?.call('trackCreated', {'id': channel.id});
        },
        onSplit: () {
          // Split clip at playhead via callback
          widget.onDspAction?.call('splitClip', null);
        },
        onDuplicate: () {
          // Duplicate selected clip via callback
          widget.onDspAction?.call('duplicateSelection', null);
        },
        onDelete: () {
          // Delete selected clip/track via callback
          widget.onDspAction?.call('deleteSelection', null);
        },
      ),
      DawSuperTab.mix => DawActions.forMix(
        onAddBus: () {
          // Create new bus in mixer
          final mixer = context.read<MixerProvider>();
          final bus = mixer.createBus(
            name: 'Bus ${mixer.busCount + 1}',
          );
        },
        onMuteAll: () {
          // Mute all channels
          final mixer = context.read<MixerProvider>();
          for (final channel in mixer.channels) {
            mixer.setMuted(channel.id, true);
          }
        },
        onSolo: () {
          // Clear all solos (toggle solo mode)
          final mixer = context.read<MixerProvider>();
          mixer.clearAllSolo();
        },
        onReset: () {
          // Reset mixer to defaults
          final mixer = context.read<MixerProvider>();
          for (final channel in mixer.channels) {
            mixer.setVolume(channel.id, 1.0);  // Unity gain
            mixer.setPan(channel.id, 0.0);     // Center
            mixer.setMuted(channel.id, false);
            mixer.setSoloed(channel.id, false);
          }
        },
      ),
      DawSuperTab.process => _buildProcessActions(),
      DawSuperTab.deliver => DawActions.forDeliver(
        onQuickExport: () {
          // Quick export with last used settings
          widget.onDspAction?.call('quickExport', null);
        },
        onBrowse: () async {
          // Open export folder in system file browser
          final exportPath = '/Users/${Platform.environment['USER']}/Music/FluxForge Exports';
          // Create directory if it doesn't exist and open in Finder
          final dir = Directory(exportPath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          await Process.run('open', [exportPath]);
        },
        onExport: () {
          // Open export dialog
          widget.onDspAction?.call('showExportDialog', null);
        },
      ),
    };

    // Add track info to status when in PROCESS tab
    String statusText = 'DAW Ready';
    if (widget.controller.superTab == DawSuperTab.process) {
      statusText = widget.selectedTrackName ?? 'No track selected';
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
// P2.3: INTERACTIVE AUTOMATION CURVE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _InteractiveAutomationCurvePainter extends CustomPainter {
  final Color color;
  final List<Offset> points;
  final int? selectedIndex;
  final bool isEditable;

  _InteractiveAutomationCurvePainter({
    required this.color,
    required this.points,
    this.selectedIndex,
    this.isEditable = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid
    _drawGrid(canvas, size);

    // Draw value labels
    _drawValueLabels(canvas, size);

    if (points.isEmpty) {
      // Draw placeholder text
      final textPainter = TextPainter(
        text: TextSpan(
          text: isEditable
              ? 'Click to add automation points\nDouble-click to delete last point'
              : 'Switch to Write or Touch mode to edit',
          style: TextStyle(
            color: LowerZoneColors.textMuted.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
      return;
    }

    final curvePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    // Draw curve with fill
    if (points.length >= 2) {
      final path = Path();
      final fillPath = Path();

      path.moveTo(points[0].dx, points[0].dy);
      fillPath.moveTo(points[0].dx, size.height);
      fillPath.lineTo(points[0].dx, points[0].dy);

      for (int i = 1; i < points.length; i++) {
        // Cubic bezier for smooth curve
        final cp1x = points[i - 1].dx + (points[i].dx - points[i - 1].dx) / 2;
        final cp1y = points[i - 1].dy;
        final cp2x = points[i - 1].dx + (points[i].dx - points[i - 1].dx) / 2;
        final cp2y = points[i].dy;
        path.cubicTo(cp1x, cp1y, cp2x, cp2y, points[i].dx, points[i].dy);
        fillPath.cubicTo(cp1x, cp1y, cp2x, cp2y, points[i].dx, points[i].dy);
      }

      fillPath.lineTo(points.last.dx, size.height);
      fillPath.close();

      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(path, curvePaint);
    }

    // Draw points
    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final selectedPointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final pointOutlinePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final isSelected = i == selectedIndex;

      if (isSelected) {
        canvas.drawCircle(point, 8, selectedPointPaint);
        canvas.drawCircle(point, 8, pointOutlinePaint);
      } else {
        canvas.drawCircle(point, 5, pointPaint);
      }
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = LowerZoneColors.border.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Horizontal lines (value grid)
    for (int i = 0; i <= 4; i++) {
      final y = i * size.height / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical lines (time grid)
    for (int i = 0; i <= 8; i++) {
      final x = i * size.width / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  void _drawValueLabels(Canvas canvas, Size size) {
    final labels = ['100%', '75%', '50%', '25%', '0%'];
    for (int i = 0; i < labels.length; i++) {
      final y = i * size.height / 4;
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: LowerZoneColors.textMuted.withValues(alpha: 0.5),
            fontSize: 8,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(4, y + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _InteractiveAutomationCurvePainter oldDelegate) {
    return points != oldDelegate.points ||
        selectedIndex != oldDelegate.selectedIndex ||
        isEditable != oldDelegate.isEditable;
  }
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

// ═══════════════════════════════════════════════════════════════════════════
// P0.2: GRID PREVIEW PAINTER
// ═══════════════════════════════════════════════════════════════════════════

/// Custom painter for grid preview visualization
class _GridPreviewPainter extends CustomPainter {
  final double snapValue;
  final bool isActive;
  final Color accentColor;

  _GridPreviewPainter({
    required this.snapValue,
    required this.isActive,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isActive
          ? accentColor.withOpacity(0.6)
          : LowerZoneColors.textTertiary.withOpacity(0.3)
      ..strokeWidth = 1;

    // Calculate number of grid lines based on snap value
    // Assume 4 beats visible in preview
    final beatsVisible = 4.0;
    final gridLines = (beatsVisible / snapValue).round().clamp(2, 16);
    final spacing = size.width / gridLines;

    // Draw vertical grid lines
    for (int i = 0; i <= gridLines; i++) {
      final x = i * spacing;
      final isMajor = i % 4 == 0;
      paint.strokeWidth = isMajor ? 1.5 : 0.5;
      paint.color = isActive
          ? accentColor.withOpacity(isMajor ? 0.8 : 0.4)
          : LowerZoneColors.textTertiary.withOpacity(isMajor ? 0.5 : 0.2);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw a sample "clip" to show snap behavior
    if (isActive) {
      final clipPaint = Paint()
        ..color = accentColor.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      final clipRect = Rect.fromLTWH(
        spacing * 1.5,
        size.height * 0.2,
        spacing * 2,
        size.height * 0.6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(clipRect, const Radius.circular(2)),
        clipPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPreviewPainter oldDelegate) {
    return oldDelegate.snapValue != snapValue ||
        oldDelegate.isActive != isActive ||
        oldDelegate.accentColor != accentColor;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// P0.1: TRACK PRESET SAVE DIALOG
// ═══════════════════════════════════════════════════════════════════════════

class _TrackPresetSaveDialog extends StatefulWidget {
  final void Function(String name, String? category) onSave;

  const _TrackPresetSaveDialog({required this.onSave});

  @override
  State<_TrackPresetSaveDialog> createState() => _TrackPresetSaveDialogState();
}

class _TrackPresetSaveDialogState extends State<_TrackPresetSaveDialog> {
  final _nameController = TextEditingController();
  String? _selectedCategory;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LowerZoneColors.bgDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: LowerZoneColors.border),
      ),
      title: Row(
        children: [
          Icon(Icons.save_outlined, size: 20, color: LowerZoneColors.dawAccent),
          const SizedBox(width: 8),
          const Text(
            'Save Track Preset',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: LowerZoneColors.textPrimary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name field
            const Text(
              'Preset Name',
              style: TextStyle(
                fontSize: 11,
                color: LowerZoneColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(
                fontSize: 12,
                color: LowerZoneColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'My Track Preset',
                hintStyle: const TextStyle(color: LowerZoneColors.textTertiary),
                filled: true,
                fillColor: LowerZoneColors.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: LowerZoneColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: LowerZoneColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: LowerZoneColors.dawAccent),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
            const SizedBox(height: 16),
            // Category selector
            const Text(
              'Category',
              style: TextStyle(
                fontSize: 11,
                color: LowerZoneColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: TrackPresetService.categories.map((category) {
                final isSelected = _selectedCategory == category;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedCategory = isSelected ? null : category;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? LowerZoneColors.dawAccent
                          : LowerZoneColors.bgSurface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected
                            ? LowerZoneColors.dawAccent
                            : LowerZoneColors.border,
                      ),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? Colors.white : LowerZoneColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: LowerZoneColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            widget.onSave(name, _selectedCategory);
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: LowerZoneColors.dawAccent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
