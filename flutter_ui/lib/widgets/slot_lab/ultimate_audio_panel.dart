/// Ultimate Audio Panel V11 — Trostepeni Stage System
///
/// Complete left panel for SlotLab audio assignment.
/// NO EDIT MODE REQUIRED — just drop audio directly.
///
/// V11 CHANGES (2026-02-28):
/// - TWO MODES: STAGES (audio assignment) + PACING (math-driven orchestration)
/// - Dynamic mechanic filtering via FeatureComposerProvider
/// - Engine Core stages always visible (locked)
/// - Feature-derived stages appear/disappear based on enabled mechanics
/// - Pacing Engine: RTP, Volatility, Hit Freq → OrchestrationContext presets
///
/// V9/V10 LEGACY (preserved):
/// - 7 PHASES of game flow (grouped from 12 sections)
/// - Phase completion rings with per-phase progress
/// - BUS ROUTING badges on every slot (🎵Music 🔊SFX 🔔Reels 🎤VO 🖥UI)
/// - PRIORITY indicators (P0 Critical / P1 Important / P2 Optional)
/// - Collapsible phases with smart defaults
///
/// PHASES (Game Flow):
/// ┌─ PHASE 1: CORE LOOP ──────────────────────────────────┐
/// │  Base Game Loop + Symbols & Lands                      │
/// │  [P0] Spin, Stops, Symbols — must-have for any slot   │
/// ├─ PHASE 2: WINS ───────────────────────────────────────┤
/// │  Win Presentation + Cascading + Multipliers            │
/// │  [P0] Win eval, lines, rollup, cascade, multipliers   │
/// ├─ PHASE 3: FEATURES ──────────────────────────────────┤
/// │  Free Spins + Bonus Games + Hold & Win                 │
/// │  [P1] Feature-specific audio (game-dependent)          │
/// ├─ PHASE 4: JACKPOTS 🏆 ───────────────────────────────┤
/// │  Jackpots (isolated for regulatory validation)         │
/// │  [P1] Trigger, Reveal, Present, Celebrate              │
/// ├─ PHASE 5: GAMBLE ────────────────────────────────────┤
/// │  Gamble / Double-or-Nothing (optional)                 │
/// │  [P2] Only if game supports gamble feature             │
/// ├─ PHASE 6: MUSIC & AMBIENCE ──────────────────────────┤
/// │  Dynamic music layers + ambient + stingers             │
/// │  [P1] Background audio — always playing, ducked        │
/// ├─ PHASE 7: UI & SYSTEM ───────────────────────────────┤
/// │  Buttons, Navigation, Notifications, Feedback          │
/// │  [P2] Non-blocking, instant feedback utility sounds    │
/// └──────────────────────────────────────────────────────┘
///
/// Auto-Distribution: Drop a folder on a GROUP, files are automatically
/// matched to their correct stages using fuzzy filename matching.

import 'dart:io'; // V11: Folder import
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SL-LP-P1.3
import 'package:provider/provider.dart';
import '../../models/auto_event_builder_models.dart' show AudioAsset;
import '../../models/slot_lab_models.dart';
import '../../models/win_tier_config.dart'; // P5 Win Tier System
import '../../providers/middleware_provider.dart'; // SL-INT-P1.1
import '../../services/stage_group_service.dart';
import '../../services/stage_configuration_service.dart';
import '../../services/audio_playback_service.dart';
import '../../services/variant_manager.dart'; // SL-LP-P1.4
import '../../services/waveform_thumbnail_cache.dart'; // SL-LP-P1.1
import 'package:get_it/get_it.dart'; // V11: Feature Composer + Pacing
import 'ffnc_rename_dialog.dart'; // FFNC Rename Tool
import 'sfx_pipeline_wizard.dart'; // SFX Pipeline Wizard
import '../../providers/slot_lab/feature_composer_provider.dart'; // V11
import '../../providers/slot_lab/pacing_engine_provider.dart'; // V11
import '../../services/audio_mapping_import_service.dart'; // V11: Bulk Import
import '../../services/native_file_picker.dart'; // V11: Native folder picker
import '../../providers/slot_lab_project_provider.dart'; // Auto-Bind
import '../../screens/slot_lab_screen.dart'; // Static triggerAutoBindReload
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// V9: Bus Routing + Priority enums for slot metadata
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio bus routing — matches engine bus IDs
enum SlotBus {
  sfx('SFX', '🔊', Color(0xFFFF9040)),
  reels('Reels', '🔔', Color(0xFF40C8FF)),
  music('Music', '🎵', Color(0xFF9370DB)),
  voice('VO', '🎤', Color(0xFF40FF90)),
  ui('UI', '🖥', Color(0xFF9E9E9E)),
  ambience('Amb', '🌙', Color(0xFF607D8B));

  const SlotBus(this.label, this.icon, this.color);
  final String label;
  final String icon;
  final Color color;
}

/// Priority level — guides designers on which slots to fill first
enum SlotPriority {
  p0('P0', Color(0xFFFF4060)),   // Critical — must-have for any slot game
  p1('P1', Color(0xFFFF9040)),   // Important — expected by players
  p2('P2', Color(0xFF9E9E9E));   // Optional — nice-to-have polish

  const SlotPriority(this.label, this.color);
  final String label;
  final Color color;
}

/// Audio assignment callback with stage, path, and optional display label
typedef OnAudioAssign = void Function(String stage, String audioPath, [String? label]);

/// Callback for batch auto-distribution results
typedef OnBatchDistribute = void Function(List<StageMatch> matched, List<UnmatchedFile> unmatched);

/// Callback when slot is selected in Quick Assign mode
typedef OnQuickAssignSlotSelected = void Function(String stage);

/// Ultimate Audio Panel — all audio drops in one place
class UltimateAudioPanel extends StatefulWidget {
  /// Current audio assignments (stage → audioPath)
  final Map<String, String> audioAssignments;

  /// Called when single audio is dropped on a slot
  final OnAudioAssign? onAudioAssign;

  /// Called to add an additional layer to an existing event (multi-drop)
  final void Function(String stage, String audioPath)? onAudioLayerAdd;

  /// Called when audio is cleared from a slot
  final Function(String stage)? onAudioClear;

  /// Called after batch distribution (folder drop)
  final OnBatchDistribute? onBatchDistribute;

  /// Called to clear all audio in a section
  final Function(String sectionId)? onClearSection;

  /// Called when section is toggled (for state persistence)
  final Function(String sectionId)? onSectionToggle;

  /// Called when group is toggled (for state persistence)
  final Function(String groupId)? onGroupToggle;

  /// Quick Assign Mode: Called when slot is clicked in quick assign mode
  final OnQuickAssignSlotSelected? onQuickAssignSlotSelected;

  /// Quick Assign Mode: Currently selected slot (highlighted)
  final String? quickAssignSelectedSlot;

  /// Quick Assign Mode: Whether quick assign mode is active
  final bool quickAssignMode;

  /// Symbol definitions for symbol section
  final List<SymbolDefinition> symbols;

  /// Context definitions for music section
  final List<ContextDefinition> contexts;

  /// Persisted expanded sections (optional - uses local state if null)
  final Set<String>? expandedSections;

  /// Persisted expanded groups (optional - uses local state if null)
  final Set<String>? expandedGroups;

  /// P5: Win tier configuration for dynamic stage generation
  final SlotWinConfiguration? winConfiguration;

  // ==========================================================================
  // P3 RECOMMENDATIONS — Undo/Redo and Bulk Assign
  // ==========================================================================

  /// Called when undo is requested
  final VoidCallback? onUndo;

  /// Called when redo is requested
  final VoidCallback? onRedo;

  /// Whether undo is available
  final bool canUndo;

  /// Whether redo is available
  final bool canRedo;

  /// Undo description for tooltip
  final String? undoDescription;

  /// Redo description for tooltip
  final String? redoDescription;

  /// Called for bulk assign (e.g., REEL_STOP → REEL_STOP_0..4)
  final Function(String baseStage, String audioPath)? onBulkAssign;

  /// V11: Called when bulk import applies mappings (stage → audioPath)
  final Function(Map<String, String> mappings)? onBulkImport;

  /// V11: Called when slot machine is created via setup wizard
  /// Parameters: reelCount, rowCount
  final void Function(int reels, int rows)? onSlotMachineCreated;

  /// Called after auto-bind completes to sync assignments to EventRegistry
  /// Passes the folder path so parent can sync files into audio pool
  final void Function(String folderPath)? onAutoBindComplete;

  /// Called after user dismisses the auto-bind result dialog (presses OK)
  final VoidCallback? onAutoBindDialogDismissed;

  /// Called when POOL should be cleared (on reset with "clear pool" checked)
  final VoidCallback? onPoolClear;

  const UltimateAudioPanel({
    super.key,
    this.audioAssignments = const {},
    this.onAudioAssign,
    this.onAudioLayerAdd,
    this.onAudioClear,
    this.onBatchDistribute,
    this.onClearSection,
    this.onSectionToggle,
    this.onGroupToggle,
    this.onQuickAssignSlotSelected,
    this.quickAssignSelectedSlot,
    this.quickAssignMode = false,
    this.symbols = const [],
    this.contexts = const [],
    this.expandedSections,
    this.expandedGroups,
    this.winConfiguration,
    // P3 Recommendations
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.undoDescription,
    this.redoDescription,
    this.onBulkAssign,
    this.onBulkImport,
    this.onSlotMachineCreated,
    this.onAutoBindComplete,
    this.onAutoBindDialogDismissed,
    this.onPoolClear,
  });

  @override
  State<UltimateAudioPanel> createState() => _UltimateAudioPanelState();
}

class _UltimateAudioPanelState extends State<UltimateAudioPanel> {
  // Local expanded state (used when external state not provided)
  late Set<String> _localExpandedSections;
  late Set<String> _localExpandedGroups;

  // Audio preview state (SL-LP-P0.1)
  String? _playingStage;

  // Search state (SL-LP-P1.2)
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(); // SL-LP-P1.3

  // Unassigned filter state (P3-17)
  bool _showUnassignedOnly = false;

  // V10: Phase tab navigation — show one phase at a time
  int _activePhaseTab = 0; // 0=All, 1-7=individual phases
  bool _showAllPhases = false; // false=tab mode, true=scroll all

  // V11: Top-level mode switch (STAGES vs PACING)
  int _panelMode = 0; // 0=Stages, 1=Pacing

  // Inline event detail expand — shows composite event layers below slot

  // Keyboard navigation state (SL-LP-P1.3)
  final FocusNode _panelFocusNode = FocusNode();
  int _selectedSectionIndex = 0;
  int _selectedGroupIndex = 0;

  // Phase config cache — invalidated only when composer config actually changes
  List<_PhaseConfig>? _cachedPhases;
  int _cachedComposerHash = 0;

  void _invalidatePhaseCache() {
    setState(() => _cachedPhases = null);
  }

  @override
  void initState() {
    super.initState();
    // Initialize local state from external or defaults
    // V9: Phase IDs + Section IDs for two-level expand state
    // V10: Smart defaults — only P0 phases expanded, rest collapsed
    _localExpandedSections = Set.from(widget.expandedSections ?? <String>{});
    _localExpandedGroups = Set.from(widget.expandedGroups ?? <String>{});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _panelFocusNode.dispose(); // SL-LP-P1.3
    super.dispose();
  }

  /// Expanded sections — ALWAYS local for instant UI response.
  /// Synced to provider via callback for persistence.
  Set<String> get _expandedSections => _localExpandedSections;

  /// Expanded groups — ALWAYS local for instant UI response.
  Set<String> get _expandedGroups => _localExpandedGroups;

  /// Handle keyboard shortcuts (SL-LP-P1.3)
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus.context != null) {
      final editable = primaryFocus.context!.findAncestorWidgetOfExactType<EditableText>();
      if (editable != null) return KeyEventResult.ignored;
    }

    // When search field has focus, let TextField handle ALL key events
    // (typing, space, backspace, arrows, etc.) — only intercept Escape
    if (_searchFocusNode.hasFocus) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() {
          _searchQuery = '';
          _searchController.clear();
        });
        _searchFocusNode.unfocus();
        // Don't request _panelFocusNode — let focus return to slot machine
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // --- Below: search field does NOT have focus ---

    // Cmd/Ctrl+F: Focus search
    if (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyF) {
        _searchFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }

    // Escape: unfocus panel
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }

    // Arrow left/right: Navigate phase tabs
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      setState(() {
        if (_activePhaseTab > 0) _activePhaseTab--;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      setState(() {
        if (_activePhaseTab < 7) _activePhaseTab++;
      });
      return KeyEventResult.handled;
    }
    // Arrow up/down: Navigate sections within phase
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_selectedSectionIndex > 0) _selectedSectionIndex--;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        if (_selectedSectionIndex < 6) _selectedSectionIndex++;
      });
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final composer = GetIt.instance<FeatureComposerProvider>();

    return Focus(
      focusNode: _panelFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: ListenableBuilder(
        listenable: composer,
        builder: (context, _) {
          // Invalidate phase cache ONLY when composer config actually changes
          final composerHash = Object.hashAll([
            composer.isConfigured,
            ...composer.enabledMechanics,
            composer.config?.paylineType,
            composer.config?.winTierCount ?? 5,
            composer.config?.reelCount ?? 3,
            composer.config?.anticipationLevels ?? 4,
            composer.config?.anticipationReels?.length ?? -1,
            composer.config?.enabledBlockIds.length ?? 0,
            ...?(composer.config?.enabledBlockIds),
          ]);
          if (composerHash != _cachedComposerHash) {
            _cachedComposerHash = composerHash;
            _cachedPhases = null;
          }
          // V11: Show wizard if no slot machine config exists
          if (!composer.isConfigured) {
            return Container(
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(color: Color(0xFF0C0C10)),
              child: _buildSetupWizard(composer),
            );
          }

          return Container(
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(color: FluxForgeTheme.bgDeepest),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                if (_panelMode == 0) ...[
                  // STAGES mode — audio assignment
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: SizedBox(
                      height: 30,
                      child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: const TextStyle(fontSize: 12, color: FluxForgeTheme.textSecondary),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: FluxForgeTheme.bgDeep,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        hintText: 'Search slots...',
                        hintStyle: const TextStyle(color: FluxForgeTheme.textDisabled, fontSize: 11),
                        prefixIcon: const Icon(Icons.search, size: 15, color: FluxForgeTheme.textDisabled),
                        prefixIconConstraints: const BoxConstraints(minWidth: 32),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 15, color: FluxForgeTheme.textDisabled),
                                onPressed: () => setState(() {
                                  _searchQuery = '';
                                  _searchController.clear();
                                }),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value.toLowerCase());
                      },
                    ),
                  ),
                  ),
                  // V10: Phase tab bar — navigate between phases
                  _buildPhaseTabBar(),
                  Expanded(
                    child: _buildLazyPhaseList(),
                  ),
                ] else ...[
                  // PACING mode — math-driven orchestration
                  Expanded(
                    child: _buildPacingView(),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final stats = _getUnassignedStats();
    final totalSlots = stats.$1;
    final assignedCount = totalSlots - stats.$2;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 200;
          return Row(
            children: [
              _compactActionBtn(
                Icons.auto_fix_high, 'Auto-Bind',
                FluxForgeTheme.accentGreen,
                () => _showAutoBindDialog(context),
              ),
              const SizedBox(width: 2),
              _compactActionBtn(
                Icons.restart_alt, 'Reset',
                FluxForgeTheme.accentRed,
                () => _showResetConfirmDialog(context),
              ),
              const SizedBox(width: 2),
              _compactActionBtn(
                Icons.drive_file_rename_outline, 'FFNC Rename',
                FluxForgeTheme.accentCyan,
                () => _showFFNCRenameDialog(context),
              ),
              const SizedBox(width: 2),
              _compactActionBtn(
                Icons.auto_fix_high, 'SFX Pipeline',
                FluxForgeTheme.accentCyan,
                () => SfxPipelineWizard.show(context),
              ),
              const Expanded(child: SizedBox.shrink()),
              if (!isNarrow) ...[
                _buildInlineModeToggle(),
                const SizedBox(width: 2),
              ],
              Text(
                '$assignedCount/$totalSlots',
                style: const TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w500,
                  color: FluxForgeTheme.textTertiary, fontFamily: 'monospace',
                ),
              ),
              if (widget.onQuickAssignSlotSelected != null)
                GestureDetector(
                  onTap: () => widget.onQuickAssignSlotSelected?.call('__TOGGLE__'),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      widget.quickAssignMode ? Icons.touch_app : Icons.touch_app_outlined,
                      size: 13,
                      color: widget.quickAssignMode
                          ? FluxForgeTheme.accentOrange
                          : FluxForgeTheme.textTertiary,
                    ),
                  ),
                ),
              _compactIconBtn(
                _showUnassignedOnly ? Icons.filter_alt : Icons.filter_alt_outlined,
                () => setState(() => _showUnassignedOnly = !_showUnassignedOnly),
                _showUnassignedOnly ? 'Show all' : 'Show unassigned',
              ),
            ],
          );
        },
      ),
    );
  }

  /// Compact action button — icon only, tooltip shows label
  Widget _compactActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 300),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 20,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withOpacity(0.35), width: 1),
          ),
          child: Icon(icon, size: 12, color: color),
        ),
      ),
    );
  }

  Widget _compactIconBtn(IconData icon, VoidCallback? onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 22,
          height: 22,
          child: Icon(icon, size: 14,
            color: onTap != null ? FluxForgeTheme.textTertiary : FluxForgeTheme.textDisabled),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // V11: Reset Machine — confirm and clear config + assignments
  // ═══════════════════════════════════════════════════════════════════════════

  void _showResetConfirmDialog(BuildContext context) {
    bool clearPool = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: FluxForgeTheme.bgMid,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: FluxForgeTheme.accentRed, size: 20),
              SizedBox(width: 8),
              Text('Reset Slot Machine', style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 14)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will delete the current slot machine configuration, all audio assignments, and all events.\n\nYou will start from scratch with the setup wizard.',
                style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setDialogState(() => clearPool = !clearPool),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18, height: 18,
                      child: Checkbox(
                        value: clearPool,
                        onChanged: (v) => setDialogState(() => clearPool = v ?? true),
                        activeColor: FluxForgeTheme.accentRed,
                        side: const BorderSide(color: FluxForgeTheme.textTertiary),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Also clear audio POOL (uploaded sounds)',
                      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: FluxForgeTheme.textTertiary)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _performFullReset(clearPool: clearPool);
              },
              style: TextButton.styleFrom(
                backgroundColor: FluxForgeTheme.accentRed.withValues(alpha: 0.2),
              ),
              child: const Text('RESET', style: TextStyle(
                color: FluxForgeTheme.accentRed, fontWeight: FontWeight.w700,
              )),
            ),
          ],
        ),
      ),
    );
  }

  void _performFullReset({bool clearPool = true}) {
    // 1. Reset FeatureComposer config → triggers wizard
    final composer = GetIt.instance<FeatureComposerProvider>();
    composer.resetConfig();

    // 2. Clear all audio assignments
    for (final stage in widget.audioAssignments.keys.toList()) {
      widget.onAudioClear?.call(stage);
    }

    // 3. Clear audio POOL if requested
    if (clearPool) {
      widget.onPoolClear?.call();
    }

    // 4. Reset grid to default 3×3
    widget.onSlotMachineCreated?.call(3, 3);

    // 5. Reset wizard state to defaults
    _wizardReels = 5;
    _wizardRows = 3;
    _wizardName = '';
    _wizardWinTiers = 5;
    _wizardPaylineType = PaylineType.lines;
    _wizardMechanics.clear();
    _wizardAnticipationReels = null;
    _wizardAnticipationLevels = 4;

    // 6. Reset local UI state
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _activePhaseTab = 0;
      _panelMode = 0;
      _localExpandedSections.clear();
      _localExpandedGroups.clear();
    });
  }

  // Auto-Bind: Scan folder and auto-map by filename patterns
  // ═══════════════════════════════════════════════════════════════════════════

  void _showFFNCRenameDialog(BuildContext context) async {
    final count = await showDialog<int>(
      context: context,
      builder: (_) => FFNCRenameDialog(
        resolveStage: (normalized, full) =>
            SlotLabProjectProvider.resolveStageFromFilenamePublic(normalized, full),
      ),
    );
    if (count != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('FFNC Rename: $count files renamed'),
          backgroundColor: FluxForgeTheme.bgMid,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showAutoBindDialog(BuildContext context) async {
    final path = await NativeFilePicker.pickDirectory(
      title: 'Select Sound Folder for Auto-Bind',
    );
    if (path == null || !mounted) return;

    final projectProvider = GetIt.instance<SlotLabProjectProvider>();
    final result = projectProvider.autoBindFromFolder(path);
    final bindings = result.bindings;
    final unmapped = result.unmapped;

    if (!mounted) return;

    if (bindings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No matching sound files found in folder'),
          backgroundColor: Color(0xFF442222),
        ),
      );
      return;
    }

    // Show result dialog — pool sync + splash triggered via provider signal when OK pressed
    final totalFiles = bindings.length + unmapped.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.auto_fix_high, color: Color(0xFF66BB6A), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Auto-Bind: ${bindings.length}/$totalFiles files mapped',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          height: 350,
          child: ListView(
            children: [
              // Mapped stages
              for (final entry in bindings.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 10, color: Color(0xFF66BB6A)),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 180,
                        child: Text(entry.key, style: const TextStyle(
                          color: Color(0xFF66BB6A), fontSize: 10,
                          fontFamily: 'monospace', fontWeight: FontWeight.w600,
                        )),
                      ),
                      Expanded(
                        child: Text(entry.value.split('/').last, style: const TextStyle(
                          color: Colors.white54, fontSize: 9,
                          fontFamily: 'monospace',
                        ), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              // Unmapped files section
              if (unmapped.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 4),
                  child: Text('Unmapped files:', style: TextStyle(
                    color: Color(0xFFFF9040), fontSize: 10,
                    fontWeight: FontWeight.w600,
                  )),
                ),
                for (final file in unmapped)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        const Icon(Icons.remove_circle_outline, size: 10, color: Color(0xFF665533)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(file, style: const TextStyle(
                            color: Color(0xFF887755), fontSize: 9,
                            fontFamily: 'monospace',
                          ), overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Direct static call — no callbacks, no providers, no signals
              SlotLabScreen.triggerAutoBindReload(path);
            },
            child: const Text('OK', style: TextStyle(color: Color(0xFF66BB6A))),
          ),
        ],
      ),
    );
  }

  // V11: Bulk Import Dialog
  // ═══════════════════════════════════════════════════════════════════════════

  void _showBulkImportDialog(BuildContext context) {
    BulkImportResult? _lastResult;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            backgroundColor: const Color(0xFF16161C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1A1A28),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.file_download, size: 18, color: Color(0xFF40FF90)),
                        SizedBox(width: 8),
                        Text('BULK AUDIO IMPORT', style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: Color(0xFF40FF90), letterSpacing: 0.8,
                        )),
                      ],
                    ),
                  ),

                  // Import methods
                  if (_lastResult == null) ...[
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildImportMethodCard(
                            icon: Icons.folder_open,
                            title: 'Import Folder',
                            desc: 'Auto-match filenames to stages (fuzzy)',
                            color: const Color(0xFF4A9EFF),
                            onTap: () async {
                              final path = await NativeFilePicker.pickDirectory(
                                title: 'Select Audio Folder',
                              );
                              if (path == null) return;
                              // List audio files in folder
                              final dir = Directory(path);
                              if (!dir.existsSync()) return;
                              final audioPaths = dir.listSync()
                                  .whereType<File>()
                                  .where((f) {
                                    final ext = f.path.split('.').last.toLowerCase();
                                    return {'wav', 'mp3', 'ogg', 'flac', 'aif', 'aiff'}.contains(ext);
                                  })
                                  .map((f) => f.path)
                                  .toList();
                              if (audioPaths.isEmpty) return;
                              final result = AudioMappingImportService.instance.matchFolder(audioPaths);
                              setDialogState(() => _lastResult = result);
                            },
                          ),
                          const SizedBox(height: 8),
                          _buildImportMethodCard(
                            icon: Icons.table_chart,
                            title: 'Import CSV',
                            desc: 'stage,audio columns — precise mapping',
                            color: const Color(0xFFFFD700),
                            onTap: () async {
                              final result = await _pickAndImportFile(ctx, 'csv');
                              if (result != null) {
                                setDialogState(() => _lastResult = result);
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          _buildImportMethodCard(
                            icon: Icons.data_object,
                            title: 'Import JSON',
                            desc: '{"mappings": [...]} — structured mapping',
                            color: const Color(0xFF9370DB),
                            onTap: () async {
                              final result = await _pickAndImportFile(ctx, 'json');
                              if (result != null) {
                                setDialogState(() => _lastResult = result);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          // Export current
                          if (widget.audioAssignments.isNotEmpty)
                            GestureDetector(
                              onTap: () => _exportCurrentMappings(ctx),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.file_upload, size: 14, color: Colors.white38),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Export current mappings (${widget.audioAssignments.length} assignments)',
                                      style: const TextStyle(fontSize: 10, color: Colors.white38),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Import results view
                    _buildImportResultsView(ctx, _lastResult!, setDialogState),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImportMethodCard({
    required IconData icon,
    required String title,
    required String desc,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color,
                  )),
                  const SizedBox(height: 2),
                  Text(desc, style: const TextStyle(fontSize: 9, color: Colors.white38)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 12, color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildImportResultsView(
    BuildContext ctx,
    BulkImportResult result,
    void Function(void Function()) setDialogState,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary
          Row(
            children: [
              _buildResultStat('Matched', result.matchedCount, const Color(0xFF40FF90)),
              const SizedBox(width: 8),
              _buildResultStat('Unmatched', result.unmatchedCount, Colors.orange),
              const SizedBox(width: 8),
              _buildResultStat('Match Rate', null, const Color(0xFF4A9EFF),
                text: '${(result.matchRate * 100).toStringAsFixed(0)}%'),
            ],
          ),
          const SizedBox(height: 8),

          // Warnings
          if (result.warnings.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(maxHeight: 60),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: result.warnings.map((w) => Text(
                    w, style: const TextStyle(fontSize: 9, color: FluxForgeTheme.accentOrange),
                  )).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Matched list (scrollable, max 200px)
          if (result.mappings.isNotEmpty) ...[
            Text('MATCHED', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6), letterSpacing: 1.0,
            )),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Column(
                  children: result.mappings.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 3, height: 10,
                          decoration: BoxDecoration(
                            color: m.confidence >= 0.7
                                ? FluxForgeTheme.accentGreen
                                : m.confidence >= 0.4
                                    ? FluxForgeTheme.accentOrange
                                    : FluxForgeTheme.accentRed,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: Text(m.stageId, style: const TextStyle(
                            fontSize: 9, color: FluxForgeTheme.textSecondary,
                            fontFamily: 'JetBrainsMono',
                          )),
                        ),
                        const Icon(Icons.arrow_right, size: 10, color: FluxForgeTheme.textDisabled),
                        Expanded(
                          flex: 3,
                          child: Text(
                            m.audioPath.split('/').last,
                            style: const TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${(m.confidence * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 9,
                            fontFamily: 'JetBrainsMono',
                            color: m.confidence >= 0.7
                                ? FluxForgeTheme.accentGreen
                                : FluxForgeTheme.accentOrange,
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: Text('Cancel', style: TextStyle(fontSize: 10, color: Colors.white54)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () {
                    _applyImportResult(result);
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF40FF90), Color(0xFF20CC60)],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        'APPLY ${result.matchedCount} MAPPINGS',
                        style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: Color(0xFF0D0D10), letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultStat(String label, int? count, Color color, {String? text}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            Text(text ?? '$count', style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700,
              color: color, fontFamily: 'JetBrainsMono',
            )),
            Text(label, style: TextStyle(
              fontSize: 9, color: color.withValues(alpha: 0.7),
            )),
          ],
        ),
      ),
    );
  }

  /// Apply import result — assign all matched audio
  void _applyImportResult(BulkImportResult result) {
    if (result.mappings.isEmpty) return;

    // Use bulk import callback if available
    if (widget.onBulkImport != null) {
      final mappings = <String, String>{};
      for (final m in result.mappings) {
        mappings[m.stageId] = m.audioPath;
      }
      widget.onBulkImport!(mappings);
    } else {
      // Fallback: apply one by one via onAudioAssign
      for (final m in result.mappings) {
        widget.onAudioAssign?.call(m.stageId, m.audioPath);
      }
    }
  }

  /// Pick a file and import it
  Future<BulkImportResult?> _pickAndImportFile(BuildContext ctx, String type) async {
    // Use file picker dialog
    final path = await _showFilePickerDialog(ctx, type);
    if (path == null) return null;

    final service = AudioMappingImportService.instance;
    if (type == 'csv') {
      return await service.importCsvFile(path);
    } else {
      return await service.importJsonFile(path);
    }
  }

  /// Simple file picker via text input (macOS native picker would need platform channel)
  Future<String?> _showFilePickerDialog(BuildContext ctx, String type) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: ctx,
      builder: (dialogCtx) => Dialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter ${type.toUpperCase()} file path:', style: const TextStyle(
                fontSize: 11, color: Colors.white70,
              )),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamily: 'JetBrainsMono'),
                decoration: InputDecoration(
                  isDense: true, filled: true,
                  fillColor: const Color(0xFF0D0D10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  hintText: '/path/to/mappings.${type}',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 10),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(dialogCtx).pop(null),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Cancel', style: TextStyle(fontSize: 10, color: Colors.white38)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.of(dialogCtx).pop(controller.text.trim()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A9EFF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Import', style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white,
                      )),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    return result != null && result.isNotEmpty ? result : null;
  }

  /// Export current mappings to console (for now)
  void _exportCurrentMappings(BuildContext ctx) {
    final service = AudioMappingImportService.instance;
    final csv = service.exportCsv(widget.audioAssignments);

    // Show export preview
    showDialog(
      context: ctx,
      builder: (dialogCtx) => Dialog(
        backgroundColor: const Color(0xFF16161C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: 400,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('EXPORT — CSV Format', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: Color(0xFF4A9EFF), letterSpacing: 0.5,
                )),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      csv,
                      style: const TextStyle(
                        fontSize: 9, color: Colors.white54,
                        fontFamily: 'JetBrainsMono',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Copy this CSV and save to a .csv file for later import.',
                  style: TextStyle(fontSize: 9, color: Colors.white30),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(dialogCtx).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Close', style: TextStyle(fontSize: 10, color: Colors.white54)),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // V11: Mode Switch — STAGES vs PACING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Compact inline mode toggle — sits in header, saves 24px vertical
  Widget _buildInlineModeToggle() {
    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < 2; i++)
            GestureDetector(
              onTap: () => setState(() => _panelMode = i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: _panelMode == i ? FluxForgeTheme.bgSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      i == 0 ? Icons.audiotrack : Icons.functions,
                      size: 10,
                      color: _panelMode == i ? FluxForgeTheme.textSecondary : FluxForgeTheme.textDisabled,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      i == 0 ? 'STG' : 'PCG',
                      style: TextStyle(
                        fontSize: 8, fontWeight: FontWeight.w600,
                        color: _panelMode == i ? FluxForgeTheme.textSecondary : FluxForgeTheme.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // V11: Mechanic Composer — quick toggles for feature mechanics
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMechanicComposer() {
    final composer = GetIt.instance<FeatureComposerProvider>();
    return ListenableBuilder(
      listenable: composer,
      builder: (context, _) {
        final enabled = composer.enabledMechanics;
        final featureCount = composer.featureStageCount;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: const BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            border: Border(bottom: BorderSide(color: FluxForgeTheme.bgSurface)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'MECHANICS',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  if (featureCount > 0)
                    Text(
                      '+$featureCount',
                      style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textDisabled, fontFamily: 'monospace'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 3,
                children: SlotMechanic.values.map((mechanic) {
                  final isOn = enabled.contains(mechanic);
                  return GestureDetector(
                    onTap: () => composer.toggleMechanic(mechanic),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOn
                            ? FluxForgeTheme.bgSurface
                            : FluxForgeTheme.bgDeep,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isOn ? FluxForgeTheme.borderSubtle : FluxForgeTheme.bgSurface,
                        ),
                      ),
                      child: Text(
                        mechanic.displayName,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isOn ? FontWeight.w600 : FontWeight.w400,
                          color: isOn ? FluxForgeTheme.textSecondary : FluxForgeTheme.textDisabled,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              // Quick presets
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildPresetChip('Basic', () => composer.presetBasic()),
                  const SizedBox(width: 4),
                  _buildPresetChip('Standard', () => composer.presetStandard()),
                  const SizedBox(width: 4),
                  _buildPresetChip('Full', () => composer.presetFull()),
                  const Spacer(),
                  if (enabled.isNotEmpty)
                    GestureDetector(
                      onTap: () => composer.disableAll(),
                      child: const Text(
                        'Clear',
                        style: TextStyle(fontSize: 10, color: FluxForgeTheme.textDisabled),
                      ),
                    ),
                ],
              ),

              // ── Game Config ──
              if (composer.config != null) ...[
                const SizedBox(height: 3),
                const Divider(height: 1, color: FluxForgeTheme.bgSurface),
                const SizedBox(height: 4),
                // Win Tiers + Anticipation Levels — same row
                Row(
                  children: [
                    Expanded(
                      child: _buildConfigRow(
                        'WINS',
                        composer.config!.winTierCount, 1, 8,
                        (v) { composer.setWinTierCount(v); _invalidatePhaseCache(); },
                        FluxForgeTheme.accentYellow,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildConfigRow(
                        'TENSION',
                        composer.config!.anticipationLevels, 1, 4,
                        (v) { composer.setAnticipationLevels(v); _invalidatePhaseCache(); },
                        FluxForgeTheme.accentRed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                _buildAnticipationReelPicker(composer),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildConfigRow(String label, int value, int min, int max, ValueChanged<int> onChanged, Color color) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.6),
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: value > min ? () => onChanged(value - 1) : null,
          child: Container(
            width: 18, height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: value > min ? FluxForgeTheme.bgSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('−', style: TextStyle(fontSize: 11, color: value > min ? color : FluxForgeTheme.textDisabled)),
          ),
        ),
        Container(
          width: 24, height: 18,
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace'),
          ),
        ),
        GestureDetector(
          onTap: value < max ? () => onChanged(value + 1) : null,
          child: Container(
            width: 18, height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: value < max ? FluxForgeTheme.bgSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('+', style: TextStyle(fontSize: 11, color: value < max ? color : FluxForgeTheme.textDisabled)),
          ),
        ),
      ],
    );
  }

  Widget _buildAnticipationReelPicker(FeatureComposerProvider composer) {
    final config = composer.config!;
    final rc = config.reelCount;
    final activeReels = config.effectiveAnticipationReels;
    return Row(
      children: [
        Text(
          'ANTICIPATION REELS',
          style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w600,
            color: FluxForgeTheme.accentRed.withValues(alpha: 0.6),
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        for (int r = 0; r < rc; r++)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: GestureDetector(
              onTap: () {
                composer.toggleAnticipationReel(r);
                _invalidatePhaseCache();
              },
              child: Container(
                width: 20, height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: activeReels.contains(r)
                      ? FluxForgeTheme.accentRed.withValues(alpha: 0.15)
                      : FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: activeReels.contains(r)
                        ? FluxForgeTheme.accentRed.withValues(alpha: 0.5)
                        : FluxForgeTheme.bgSurface,
                  ),
                ),
                child: Text(
                  'R${r + 1}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: activeReels.contains(r) ? FontWeight.w700 : FontWeight.w400,
                    color: activeReels.contains(r)
                        ? FluxForgeTheme.accentRed
                        : FluxForgeTheme.textDisabled,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.bgSurface),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: FluxForgeTheme.textDisabled,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // V11: Pacing View — math-driven orchestration
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPacingView() {
    final pacing = GetIt.instance<PacingEngineProvider>();
    return ListenableBuilder(
      listenable: pacing,
      builder: (context, _) {
        final t = pacing.template;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Section: Math Inputs
              _buildPacingSectionHeader('GAME MATH INPUTS'),
              const SizedBox(height: 6),
              _buildPacingSlider(
                'RTP', '${(pacing.rtp * 100).toStringAsFixed(1)}%',
                pacing.rtp, 0.85, 0.995,
                (v) => pacing.setRtp(v),
                const Color(0xFF4A9EFF),
              ),
              _buildPacingSlider(
                'Volatility', pacing.volatilityProfile.displayName,
                pacing.volatility, 0.0, 1.0,
                (v) => pacing.setVolatility(v),
                const Color(0xFFFF6B6B),
              ),
              _buildPacingSlider(
                'Hit Frequency', '${(pacing.hitFrequency * 100).toStringAsFixed(0)}%',
                pacing.hitFrequency, 0.05, 0.80,
                (v) => pacing.setHitFrequency(v),
                const Color(0xFFFFD700),
              ),
              _buildPacingSlider(
                'Max Win', '${pacing.maxWin.toStringAsFixed(0)}x',
                pacing.maxWin, 100, 100000,
                (v) => pacing.setMaxWin(v),
                const Color(0xFF40FF90),
              ),
              _buildPacingSlider(
                'Feature Freq', '1 in ${pacing.featureFrequency.toStringAsFixed(0)}',
                pacing.featureFrequency, 10, 1000,
                (v) => pacing.setFeatureFrequency(v),
                const Color(0xFF9370DB),
              ),

              const SizedBox(height: 12),
              // Section: Computed Template
              _buildPacingSectionHeader('COMPUTED TEMPLATE'),
              const SizedBox(height: 6),
              _buildPacingResult('Base Tension', t.baseTension.toStringAsFixed(2), const Color(0xFFFF6B6B)),
              _buildPacingResult('Escalation Curve', '${t.escalationCurve.toStringAsFixed(1)}x', const Color(0xFFFFD700)),
              _buildPacingResult('Fatigue Rate', '${(t.sessionFatigueRate * 60).toStringAsFixed(2)}/min', const Color(0xFF808080)),
              _buildPacingResult('Anticipation Start', 'Reel ${t.anticipationStartReel + 1}', const Color(0xFF4A9EFF)),
              _buildPacingResult('Max Anticipation', 'L${t.maxAnticipationLevel}', const Color(0xFFFF9040)),
              _buildPacingResult('Gain Swing', '${t.maxGainSwingDb.toStringAsFixed(1)} dB', const Color(0xFF40FF90)),
              _buildPacingResult('Stereo Width', '${t.maxStereoWidth.toStringAsFixed(2)}x', const Color(0xFF9370DB)),

              const SizedBox(height: 8),
              // Win Thresholds
              _buildPacingSectionHeader('WIN THRESHOLDS'),
              const SizedBox(height: 4),
              for (int i = 0; i < t.winThresholds.length; i++)
                _buildPacingResult(
                  'Tier ${i + 1}',
                  '${t.winThresholds[i].toStringAsFixed(0)}x',
                  Color.lerp(const Color(0xFF4A9EFF), const Color(0xFFFFD700), i / 4) ?? Colors.white,
                ),

              const SizedBox(height: 12),
              // Presets
              _buildPacingSectionHeader('PRESETS'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildPacingPresetButton('Classic', 'Low vol, high freq', () => pacing.presetClassic()),
                  _buildPacingPresetButton('Modern', 'Medium balanced', () => pacing.presetModern()),
                  _buildPacingPresetButton('High Vol', 'Rare big wins', () => pacing.presetHighVol()),
                  _buildPacingPresetButton('Extreme', 'Jackpot chaser', () => pacing.presetExtreme()),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPacingSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildPacingSlider(
    String label, String valueText,
    double value, double min, double max,
    ValueChanged<double> onChanged,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54)),
              const Spacer(),
              Text(valueText, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.15),
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPacingResult(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.white38)),
          const Spacer(),
          Text(value, style: TextStyle(
            fontSize: 9,
            color: color,
            fontWeight: FontWeight.w600,
            fontFamily: 'JetBrainsMono',
          )),
        ],
      ),
    );
  }

  Widget _buildPacingPresetButton(String label, String desc, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 9, color: Colors.white60, fontWeight: FontWeight.w600)),
            Text(desc, style: const TextStyle(fontSize: 9, color: FluxForgeTheme.textDisabled)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // V11: Setup Wizard — shown when no slot machine config exists
  // ═══════════════════════════════════════════════════════════════════════════

  // Wizard state (local, not persisted — wizard is transient)
  String _wizardName = '';
  int _wizardReels = 5;
  int _wizardRows = 3;
  int _wizardWinTiers = 5;
  PaylineType _wizardPaylineType = PaylineType.lines;
  final Map<SlotMechanic, bool> _wizardMechanics = {};
  Set<int>? _wizardAnticipationReels; // null = default (last 2 reels)
  int _wizardAnticipationLevels = 4;

  Widget _buildSetupWizard(FeatureComposerProvider composer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header — clean
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF141418),
            border: Border(bottom: BorderSide(color: Color(0xFF2A2A32))),
          ),
          child: const Row(
            children: [
              Icon(Icons.casino, size: 14, color: Color(0xFF808088)),
              SizedBox(width: 6),
              Text(
                'NEW MACHINE',
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600,
                  color: Color(0xFFB0B0B8), letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Name
                _wizardLabel('SLOT NAME'),
                const SizedBox(height: 4),
                TextField(
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF16161C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    hintText: 'e.g. Book of Ra, Sweet Bonanza...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 10),
                  ),
                  onChanged: (v) => _wizardName = v,
                ),

                const SizedBox(height: 12),
                // Grid: Reels x Rows
                _wizardLabel('GRID'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _wizardStepper(
                        'Reels', _wizardReels, 3, 8,
                        (v) => setState(() => _wizardReels = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('x', style: TextStyle(color: Colors.white24, fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _wizardStepper(
                        'Rows', _wizardRows, 1, 6,
                        (v) => setState(() => _wizardRows = v),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                // Payline type
                _wizardLabel('PAYLINE TYPE'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: PaylineType.values.map((type) {
                    final isOn = _wizardPaylineType == type;
                    return GestureDetector(
                      onTap: () => setState(() => _wizardPaylineType = type),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isOn ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: isOn ? const Color(0xFF505058) : const Color(0xFF222228),
                          ),
                        ),
                        child: Text(
                          type.displayName,
                          style: TextStyle(
                            fontSize: 9,
                            color: isOn ? const Color(0xFFD0D0D8) : const Color(0xFF505058),
                            fontWeight: isOn ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 12),
                // Win tiers
                _wizardLabel('WIN TIERS'),
                const SizedBox(height: 4),
                _wizardStepper(
                  'Tiers', _wizardWinTiers, 1, 5,
                  (v) => setState(() => _wizardWinTiers = v),
                ),

                const SizedBox(height: 12),
                // Game Mechanics
                _wizardLabel('GAME MECHANICS'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: SlotMechanic.values.map((mechanic) {
                    final isOn = _wizardMechanics[mechanic] ?? false;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _wizardMechanics[mechanic] = !isOn;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: isOn
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: isOn ? const Color(0xFF505058) : const Color(0xFF222228),
                          ),
                        ),
                        child: Text(
                          mechanic.displayName,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: isOn ? FontWeight.w600 : FontWeight.w400,
                            color: isOn ? const Color(0xFFD0D0D8) : const Color(0xFF505058),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                // Anticipation config
                const SizedBox(height: 12),
                _wizardLabel('ANTICIPATION REELS'),
                const SizedBox(height: 4),
                _buildWizardAnticipationReels(),
                const SizedBox(height: 8),
                _wizardStepper(
                  'Tension Levels', _wizardAnticipationLevels, 1, 4,
                  (v) => setState(() => _wizardAnticipationLevels = v),
                ),

                // Quick presets
                const SizedBox(height: 8),
                Row(
                  children: [
                    _wizardPreset('Classic 5x3', () => setState(() {
                      _wizardReels = 5; _wizardRows = 3;
                      _wizardPaylineType = PaylineType.lines;
                      _wizardMechanics.clear();
                      _wizardAnticipationReels = null;
                      _wizardAnticipationLevels = 4;
                    })),
                    const SizedBox(width: 6),
                    _wizardPreset('Cascading', () => setState(() {
                      _wizardReels = 5; _wizardRows = 3;
                      _wizardPaylineType = PaylineType.cluster;
                      _wizardMechanics.clear();
                      _wizardMechanics[SlotMechanic.cascading] = true;
                      _wizardMechanics[SlotMechanic.multiplierTrail] = true;
                      _wizardAnticipationReels = null;
                      _wizardAnticipationLevels = 4;
                    })),
                    const SizedBox(width: 6),
                    _wizardPreset('Full Feature', () => setState(() {
                      _wizardReels = 5; _wizardRows = 3;
                      _wizardPaylineType = PaylineType.lines;
                      _wizardMechanics.clear();
                      for (final m in SlotMechanic.values) {
                        _wizardMechanics[m] = true;
                      }
                      _wizardAnticipationReels = null;
                      _wizardAnticipationLevels = 4;
                    })),
                  ],
                ),

                const SizedBox(height: 16),
                // Stage preview
                _wizardLabel('STAGE PREVIEW'),
                const SizedBox(height: 4),
                _buildWizardStagePreview(),

                const SizedBox(height: 16),
                // Create button
                GestureDetector(
                  onTap: () {
                    final name = _wizardName.trim().isEmpty ? 'Untitled Slot' : _wizardName.trim();
                    // Auto-enable anticipation block if reels are configured
                    final effectiveReels = _wizardAnticipationReels ??
                        {_wizardReels - 2, _wizardReels - 1}.where((r) => r >= 0).toSet();
                    final blockIds = <String>[
                      if (effectiveReels.isNotEmpty) 'anticipation',
                    ];
                    final config = SlotMachineConfig(
                      name: name,
                      reelCount: _wizardReels,
                      rowCount: _wizardRows,
                      paylineCount: _wizardPaylineType == PaylineType.ways ? 243 : 20,
                      paylineType: _wizardPaylineType,
                      winTierCount: _wizardWinTiers,
                      mechanics: Map.from(_wizardMechanics),
                      anticipationReels: _wizardAnticipationReels,
                      anticipationLevels: _wizardAnticipationLevels,
                      enabledBlockIds: blockIds,
                    );
                    composer.applyConfig(config);
                    // Notify parent to sync grid dimensions to engine + UI
                    widget.onSlotMachineCreated?.call(_wizardReels, _wizardRows);
                  },
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E28),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF404048)),
                    ),
                    child: const Center(
                      child: Text(
                        'CREATE',
                        style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w600,
                          color: Color(0xFFD0D0D8), letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _wizardLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _wizardStepper(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.white38)),
          const Spacer(),
          GestureDetector(
            onTap: value > min ? () => onChanged(value - 1) : null,
            child: Icon(Icons.remove_circle_outline, size: 14,
              color: value > min ? Colors.white54 : Colors.white12),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$value',
              style: const TextStyle(
                fontSize: 12, color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ),
          GestureDetector(
            onTap: value < max ? () => onChanged(value + 1) : null,
            child: Icon(Icons.add_circle_outline, size: 14,
              color: value < max ? Colors.white54 : Colors.white12),
          ),
        ],
      ),
    );
  }

  Widget _wizardPreset(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 9, color: FluxForgeTheme.textDisabled)),
      ),
    );
  }

  Widget _buildWizardAnticipationReels() {
    final rc = _wizardReels;
    final active = _wizardAnticipationReels ??
        {rc - 2, rc - 1}.where((r) => r >= 0).toSet();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (int r = 0; r < rc; r++)
          GestureDetector(
            onTap: () => setState(() {
              final current = Set<int>.from(active);
              if (current.contains(r)) {
                current.remove(r);
              } else {
                current.add(r);
              }
              _wizardAnticipationReels = current;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: active.contains(r)
                    ? const Color(0xFFFF5252).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: active.contains(r)
                      ? const Color(0xFFFF5252).withValues(alpha: 0.5)
                      : const Color(0xFF222228),
                ),
              ),
              child: Text(
                'R${r + 1}',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: active.contains(r) ? FontWeight.w700 : FontWeight.w400,
                  color: active.contains(r)
                      ? const Color(0xFFFF5252)
                      : const Color(0xFF505058),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWizardStagePreview() {
    // Count stages that would be generated
    final coreCount = 1 + _wizardReels + 1 + _wizardWinTiers + 2; // spin + reels + symbolLand + winTiers + countup
    int featureCount = 0;
    for (final entry in _wizardMechanics.entries) {
      if (entry.value) {
        featureCount += entry.key.generatedStages.length;
      }
    }
    const alwaysCount = 8; // Music (4) + UI (4) — matches _alwaysVisibleStages
    final total = coreCount + featureCount + alwaysCount;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF101018),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A9EFF),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text('Engine Core: $coreCount stages',
                style: const TextStyle(fontSize: 9, color: Colors.white54)),
            ],
          ),
          if (featureCount > 0) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFF40FF90),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text('Features: $featureCount stages',
                  style: const TextStyle(fontSize: 9, color: Colors.white54)),
              ],
            ),
          ],
          const SizedBox(height: 3),
          Row(
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF9370DB),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text('Music & UI: $alwaysCount stages',
                style: const TextStyle(fontSize: 9, color: Colors.white54)),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF4A9EFF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              'Total: $total audio slots',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF4A9EFF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // V10: Phase Tab Bar — Navigate between phases
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPhaseTabBar() {
    // Dynamic: build tabs from actual visible phases
    final phases = _buildPhases();
    final tabCount = phases.length + 1; // +1 for ALL tab
    // Clamp active tab if phases changed
    if (_activePhaseTab >= tabCount) _activePhaseTab = 0;

    return Container(
      height: 26,
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          // ALL tab
          _buildPhaseTab(0, 'ALL', FluxForgeTheme.textTertiary),
          // Dynamic phase tabs
          for (int i = 0; i < phases.length; i++)
            _buildPhaseTab(
              i + 1,
              _phaseShortLabel(phases[i].title),
              phases[i].color,
            ),
        ],
      ),
    );
  }

  Widget _buildPhaseTab(int index, String label, Color color) {
    final isActive = _activePhaseTab == index;
    final tabTint = Color.lerp(color, FluxForgeTheme.textTertiary, 0.55)!;
    return _HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: () => setState(() => _activePhaseTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isActive
                ? color.withOpacity(0.06)
                : hovered ? color.withOpacity(0.03) : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: isActive ? tabTint : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(label, style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600,
            color: isActive
                ? tabTint
                : hovered ? FluxForgeTheme.textTertiary : FluxForgeTheme.textDisabled,
            letterSpacing: 0.3,
          )),
        ),
      ),
    );
  }

  /// Shorten phase title for tab label (max ~5 chars)
  String _phaseShortLabel(String title) {
    const map = {
      'CORE LOOP': 'CORE',
      'WINS': 'WINS',
      'FEATURES': 'FEAT',
      'JACKPOTS': 'JACK',
      'GAMBLE': 'GAMB',
      'ANTICIPATION': 'ANTIC',
      'COLLECTOR': 'COLL',
      'MEGAWAYS': 'MEGA',
      'TRANSITIONS': 'TRANS',
      'MUSIC & AMBIENCE': 'MUSIC',
      'UI & SYSTEM': 'UI',
    };
    return map[title] ?? title.substring(0, title.length.clamp(0, 5));
  }

  /// Lazy phase list — uses ListView.builder to avoid building all phases/sections/slots
  /// at once. The mechanic composer is item 0, then phases follow.
  Widget _buildLazyPhaseList() {
    final phases = _getVisiblePhases();
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: phases.length + 1, // +1 for mechanic composer at top
      itemBuilder: (context, index) {
        if (index == 0) return _buildMechanicComposer();
        return _buildPhase(phases[index - 1]);
      },
    );
  }

  /// Get phases filtered by active tab
  List<_PhaseConfig> _getVisiblePhases() {
    final all = _buildPhases();
    if (_activePhaseTab == 0 || _isFiltering) return all; // ALL tab or search active
    final idx = _activePhaseTab - 1; // 1-indexed in tabs, 0-indexed in phases
    if (idx >= 0 && idx < all.length) {
      // Auto-expand the selected phase
      final phase = all[idx];
      if (!_expandedSections.contains(phase.id)) {
        _localExpandedSections.add(phase.id);
      }
      return [phase];
    }
    return all;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // V9: Phase header with completion ring, priority badge, and sections
  // ═══════════════════════════════════════════════════════════════════════════

  /// Build phases from widget data — filtered by enabled mechanics
  /// Only shows sections relevant to the current slot machine configuration
  List<_PhaseConfig> _buildPhases() {
    if (_cachedPhases != null) return _cachedPhases!;
    final composer = GetIt.instance<FeatureComposerProvider>();
    final enabled = composer.enabledMechanics;
    final hasCascading = enabled.contains(SlotMechanic.cascading);
    final hasMultiplier = enabled.contains(SlotMechanic.multiplierTrail);
    final hasFreeSpins = enabled.contains(SlotMechanic.freeSpins);
    final hasBonus = enabled.contains(SlotMechanic.pickBonus) ||
                     enabled.contains(SlotMechanic.wheelBonus);
    final hasHoldAndWin = enabled.contains(SlotMechanic.holdAndWin);
    final hasJackpot = enabled.contains(SlotMechanic.jackpot);
    final hasGamble = enabled.contains(SlotMechanic.gamble);
    final hasNudgeRespin = enabled.contains(SlotMechanic.nudgeRespin);
    final hasWilds = enabled.contains(SlotMechanic.expandingWilds) ||
                     enabled.contains(SlotMechanic.stickyWilds);
    final hasMegaways = enabled.contains(SlotMechanic.megaways) ||
                        (composer.config?.paylineType == PaylineType.megaways);

    final phases = <_PhaseConfig>[];

    // CORE LOOP — always visible
    phases.add(_PhaseConfig(
      id: 'core_loop',
      title: 'CORE LOOP',
      icon: '🎰',
      color: const Color(0xFF4A9EFF),
      priority: SlotPriority.p0,
      description: 'Spin → Stops → Symbols — must-have',
      sections: [
        _BaseGameLoopSection(widget: widget),
        _SymbolsSection(widget: widget),
      ],
    ));

    // WINS — always visible (win presentation is core), cascade/multiplier conditional
    final winSections = <_SectionConfig>[
      _WinPresentationSection(widget: widget),
    ];
    if (hasCascading) winSections.add(_CascadingSection(widget: widget));
    if (hasMultiplier) winSections.add(_MultipliersSection(widget: widget));
    phases.add(_PhaseConfig(
      id: 'wins',
      title: 'WINS',
      icon: '🏅',
      color: const Color(0xFFFFD700),
      priority: SlotPriority.p0,
      description: 'Lines, rollup, cascade, multipliers',
      sections: winSections,
    ));

    // FEATURES — only if any feature mechanic enabled
    if (hasFreeSpins || hasBonus || hasHoldAndWin || hasNudgeRespin || hasWilds) {
      final featureSections = <_SectionConfig>[];
      if (hasFreeSpins) featureSections.add(_FreeSpinsSection(widget: widget));
      if (hasBonus) featureSections.add(_BonusGamesSection(widget: widget));
      if (hasHoldAndWin) featureSections.add(_HoldAndWinSection(widget: widget));
      if (hasNudgeRespin) featureSections.add(_NudgeRespinSection(widget: widget));
      if (hasWilds) featureSections.add(_WildFeaturesSection(widget: widget));
      phases.add(_PhaseConfig(
        id: 'features',
        title: 'FEATURES',
        icon: '🎁',
        color: const Color(0xFF40FF90),
        priority: SlotPriority.p1,
        description: 'Free Spins, Bonus, Hold & Win, Wilds',
        sections: featureSections,
      ));
    }

    // JACKPOTS — only if jackpot mechanic enabled
    if (hasJackpot) {
      phases.add(_PhaseConfig(
        id: 'jackpots',
        title: 'JACKPOTS',
        icon: '🏆',
        color: const Color(0xFFFFD700),
        priority: SlotPriority.p1,
        description: 'Trigger → Reveal → Celebrate',
        sections: [_JackpotsSection(widget: widget)],
      ));
    }

    // GAMBLE — only if gamble mechanic enabled
    if (hasGamble) {
      phases.add(_PhaseConfig(
        id: 'gamble',
        title: 'GAMBLE',
        icon: '🎲',
        color: const Color(0xFFFF6B6B),
        priority: SlotPriority.p2,
        description: 'Double-or-nothing (optional)',
        sections: [_GambleSection(widget: widget)],
      ));
    }

    // ANTICIPATION — shown if block enabled OR any reels configured
    final hasAnticipation = composer.isBlockEnabled('anticipation') ||
        (composer.config?.effectiveAnticipationReels.isNotEmpty ?? false);
    if (hasAnticipation) {
      phases.add(_PhaseConfig(
        id: 'anticipation',
        title: 'ANTICIPATION',
        icon: '😱',
        color: const Color(0xFFFF5252),
        priority: SlotPriority.p1,
        description: 'Tension build, near-miss, heartbeat',
        sections: [_AnticipationSection(
          widget: widget,
          reelCount: composer.config?.reelCount ?? 3,
          activeReels: composer.config?.effectiveAnticipationReels ?? {1, 2},
          levelCount: composer.config?.anticipationLevels ?? 4,
        )],
      ));
    }

    // COLLECTOR — only if collector block enabled
    final hasCollector = composer.isBlockEnabled('collector');
    if (hasCollector) {
      phases.add(_PhaseConfig(
        id: 'collector',
        title: 'COLLECTOR',
        icon: '💰',
        color: const Color(0xFFFFC107),
        priority: SlotPriority.p1,
        description: 'Coin collect, meter fill, payout',
        sections: [_CollectorSection(widget: widget)],
      ));
    }

    // MEGAWAYS — only if megaways mechanic enabled
    if (hasMegaways) {
      phases.add(_PhaseConfig(
        id: 'megaways',
        title: 'MEGAWAYS',
        icon: '🔢',
        color: const Color(0xFFE040FB),
        priority: SlotPriority.p1,
        description: 'Ways reveal, expand, row shifts',
        sections: [_MegawaysSection(widget: widget)],
      ));
    }

    // TRANSITIONS — only if transitions block enabled
    final hasTransitions = composer.isBlockEnabled('transitions');
    if (hasTransitions) {
      phases.add(_PhaseConfig(
        id: 'transitions',
        title: 'TRANSITIONS',
        icon: '🔀',
        color: const Color(0xFF78909C),
        priority: SlotPriority.p2,
        description: 'Scene transitions, fade, swoosh',
        sections: [_TransitionsSection(widget: widget)],
      ));
    }

    // MUSIC & AMBIENCE — always visible
    phases.add(_PhaseConfig(
      id: 'music',
      title: 'MUSIC & AMBIENCE',
      icon: '🎵',
      color: const Color(0xFF9370DB),
      priority: SlotPriority.p1,
      description: 'Background loops, stingers, ambient',
      sections: [_MusicSection(widget: widget)],
    ));

    // UI & SYSTEM — always visible
    phases.add(_PhaseConfig(
      id: 'ui_system',
      title: 'UI & SYSTEM',
      icon: '🖥️',
      color: const Color(0xFF808080),
      priority: SlotPriority.p2,
      description: 'Buttons, menus, notifications',
      sections: [_UISystemSection(widget: widget)],
    ));

    _cachedPhases = phases;
    return phases;
  }

  Widget _buildPhase(_PhaseConfig phase) {
    // Hide entire phase when filtering and no slots match
    if (_isFiltering && !_phaseHasVisibleSlots(phase)) {
      return const SizedBox.shrink();
    }
    // Auto-expand when filtering
    final isExpanded = _isFiltering || _expandedSections.contains(phase.id);
    // Calculate totals across all sections in this phase
    int totalSlots = 0;
    int assignedSlots = 0;
    for (final section in phase.sections) {
      for (final group in section.groups) {
        totalSlots += group.slots.length;
        for (final slot in group.slots) {
          if (widget.audioAssignments.containsKey(slot.stage)) {
            assignedSlots++;
          }
        }
      }
    }
    final percentage = totalSlots > 0 ? (assignedSlots / totalSlots * 100).toInt() : 0;
    final isComplete = percentage == 100;

    // Apple-style: desaturated tint of phase color for subtle identity
    final tintColor = Color.lerp(phase.color, FluxForgeTheme.textTertiary, 0.55)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Phase header — subtle tinted
        _HoverBuilder(
          builder: (isHovered) => InkWell(
            onTap: () {
              // INSTANT: local setState for zero-delay UI
              setState(() {
                if (isExpanded) {
                  _localExpandedSections.remove(phase.id);
                } else {
                  _localExpandedSections.add(phase.id);
                }
              });
              // PERSIST: sync to provider in background
              widget.onSectionToggle?.call(phase.id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isHovered
                    ? phase.color.withOpacity(0.06)
                    : FluxForgeTheme.bgMid,
                border: Border(
                  bottom: BorderSide(color: phase.color.withOpacity(0.08)),
                  left: BorderSide(color: tintColor.withOpacity(0.7), width: 3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16, color: tintColor.withOpacity(0.6),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      phase.title,
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: tintColor, letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis, maxLines: 1,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$assignedSlots/$totalSlots',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w500,
                      color: tintColor.withOpacity(0.45), fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Phase content
        if (isExpanded)
          Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: phase.color.withOpacity(0.08), width: 2),
              ),
            ),
            child: Column(
              children: phase.sections.map((section) => _buildSection(section)).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildSection(_SectionConfig config) {
    if (_isFiltering && !_sectionHasVisibleSlots(config)) {
      return const SizedBox.shrink();
    }
    final isExpanded = _isFiltering || _expandedSections.contains(config.id);
    final sectionTint = Color.lerp(config.color, FluxForgeTheme.textTertiary, 0.6)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header — subtle hover tint
        _HoverBuilder(
          builder: (isHovered) => InkWell(
            onTap: () {
              // INSTANT: local setState for zero-delay UI
              setState(() {
                if (isExpanded) {
                  _localExpandedSections.remove(config.id);
                } else {
                  _localExpandedSections.add(config.id);
                }
              });
              // PERSIST: sync to provider in background
              widget.onSectionToggle?.call(config.id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: isHovered
                  ? config.color.withOpacity(0.04)
                  : FluxForgeTheme.bgDeep,
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14, color: sectionTint.withOpacity(0.5),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      config.title,
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: sectionTint.withOpacity(0.8), letterSpacing: 0.3,
                      ),
                      overflow: TextOverflow.ellipsis, maxLines: 1,
                    ),
                  ),
                  const Spacer(),
                  Builder(
                    builder: (context) {
                      final percentage = _getSectionPercentage(config);
                      return Text(
                        '$percentage%',
                        style: TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w500,
                          color: percentage == 100
                              ? sectionTint.withOpacity(0.6)
                              : FluxForgeTheme.textDisabled,
                          fontFamily: 'monospace',
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        // Section content
        if (isExpanded)
          Container(
            color: FluxForgeTheme.bgDeepest,
            child: Column(
              children: config.groups.map((group) => _buildGroup(group, config)).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildGroup(_GroupConfig group, _SectionConfig section) {
    if (_isFiltering && !_groupHasVisibleSlots(group)) {
      return const SizedBox.shrink();
    }
    final groupKey = '${section.id}_${group.id}';
    final isExpanded = _isFiltering || _expandedGroups.contains(groupKey);
    final assignedCount = _countAssignedInGroup(group);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Group header with FOLDER DROP ZONE
        _GroupDropZone(
          group: group,
          section: section,
          isExpanded: isExpanded,
          assignedCount: assignedCount,
          onToggle: () {
            // INSTANT: local setState for zero-delay UI
            setState(() {
              if (isExpanded) {
                _localExpandedGroups.remove(groupKey);
              } else {
                _localExpandedGroups.add(groupKey);
              }
            });
            // PERSIST: sync to provider in background
            widget.onGroupToggle?.call(groupKey);
          },
          onFolderDrop: (paths) => _handleFolderDrop(group, section, paths),
        ),
        // Individual slots — sized box constrains height for lazy rendering
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 18, right: 8, bottom: 10),
            child: Column(
              children: [
                for (final slot in group.slots)
                  _buildSlot(slot, section.color),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSlot(_SlotConfig slot, Color accentColor) {
    final audioPath = widget.audioAssignments[slot.stage];
    final hasAudio = audioPath != null;
    final fileName = hasAudio ? audioPath.split('/').last : null;

    // Variant info (SL-LP-P1.4)
    final variantCount = VariantManager.instance.getVariantCount(slot.stage);
    final hasVariants = variantCount > 1;

    // M2-8: Quick Assign Mode - is this slot selected?
    final isQuickAssignSelected = widget.quickAssignMode &&
        widget.quickAssignSelectedSlot == slot.stage;

    // P3-17: Filter by unassigned only
    if (_showUnassignedOnly && hasAudio) {
      return const SizedBox.shrink(); // Hide assigned slots when filter is active
    }

    // Filter by search query (SL-LP-P1.2)
    if (_searchQuery.isNotEmpty) {
      final matchesStage = slot.stage.toLowerCase().contains(_searchQuery);
      final matchesLabel = slot.label.toLowerCase().contains(_searchQuery);
      final matchesFileName = fileName?.toLowerCase().contains(_searchQuery) ?? false;
      if (!matchesStage && !matchesLabel && !matchesFileName) {
        return const SizedBox.shrink(); // Hide non-matching slots
      }
    }

    final slotTint = Color.lerp(accentColor, FluxForgeTheme.textTertiary, 0.6)!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _HoverBuilder(
        builder: (isSlotHovered) => GestureDetector(
        // M2-8: Quick Assign Mode - click to select/unselect slot
        onTap: widget.quickAssignMode
            ? () {
                // Toggle: if already selected, unselect
                if (widget.quickAssignSelectedSlot == slot.stage) {
                  widget.onQuickAssignSlotSelected?.call('__UNSELECT__');
                } else {
                  widget.onQuickAssignSlotSelected?.call(slot.stage);
                }
              }
            : null,
        onLongPress: hasAudio ? () => _showVariantEditor(context, slot.stage, accentColor) : null,
        child: DragTarget<Object>(
        onWillAcceptWithDetails: (details) {
          return details.data is AudioAsset ||
              details.data is List<AudioAsset> ||
              details.data is String;
        },
        onAcceptWithDetails: (details) {
          // Multi-drop support: first file = primary assign, rest = additional layers
          if (details.data is List<AudioAsset>) {
            final list = details.data as List<AudioAsset>;
            if (list.isNotEmpty) {
              // First file: primary audio assignment (creates composite event)
              widget.onAudioAssign?.call(slot.stage, list.first.path, slot.label);
              // Remaining files: add as extra layers to the composite event
              for (int i = 1; i < list.length; i++) {
                widget.onAudioLayerAdd?.call(slot.stage, list[i].path);
              }
            }
          } else {
            String? path;
            if (details.data is AudioAsset) {
              path = (details.data as AudioAsset).path;
            } else if (details.data is String) {
              path = details.data as String;
            }
            if (path != null) {
              widget.onAudioAssign?.call(slot.stage, path, slot.label);
            }
          }
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          // M2-8: Quick Assign visual feedback
          final showQuickAssignHighlight = isQuickAssignSelected ||
              (widget.quickAssignMode && isHovering);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 28,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: isQuickAssignSelected
                  ? FluxForgeTheme.bgElevated
                  : isHovering
                      ? FluxForgeTheme.bgSurface
                      : isSlotHovered
                          ? accentColor.withOpacity(0.03)
                          : FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isQuickAssignSelected
                    ? FluxForgeTheme.textTertiary
                    : isHovering
                        ? FluxForgeTheme.textDisabled
                        : isSlotHovered
                            ? slotTint.withOpacity(0.3)
                            : hasAudio
                                ? FluxForgeTheme.borderSubtle
                                : FluxForgeTheme.bgSurface,
              ),
            ),
            child: Row(
              children: [
                // Stage label — fixed width
                Container(
                  width: 80,
                  height: 28,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    slot.label,
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w500,
                      color: isSlotHovered
                          ? slotTint
                          : hasAudio ? FluxForgeTheme.textSecondary : FluxForgeTheme.textDisabled,
                    ),
                    overflow: TextOverflow.ellipsis, maxLines: 1,
                  ),
                ),
                // Separator
                Container(width: 1, height: 16, color: FluxForgeTheme.bgSurface),
                const SizedBox(width: 6),
                // Audio content or hint
                Expanded(
                  child: hasAudio
                      ? Row(
                          children: [
                            WaveformThumbnail(
                              filePath: audioPath,
                              width: 52, height: 18,
                              color: FluxForgeTheme.textDisabled,
                              backgroundColor: FluxForgeTheme.bgVoid,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                fileName!,
                                style: const TextStyle(
                                  fontSize: 10, color: FluxForgeTheme.textTertiary,
                                ),
                                overflow: TextOverflow.ellipsis, maxLines: 1,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          isQuickAssignSelected ? '← assign' : '—',
                          style: TextStyle(
                            fontSize: 10,
                            color: isQuickAssignSelected
                                ? FluxForgeTheme.textTertiary
                                : FluxForgeTheme.borderSubtle,
                          ),
                        ),
                ),
                // Variant count — minimal
                if (hasVariants && !isQuickAssignSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Text(
                      'x$variantCount',
                      style: const TextStyle(
                        fontSize: 9, color: FluxForgeTheme.textDisabled, fontFamily: 'monospace',
                      ),
                    ),
                  ),
                // Status icon + Event count badge (SL-INT-P1.1)
                // Status dot — minimal
                if (hasAudio)
                  Container(
                    width: 6, height: 6, margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: FluxForgeTheme.accentGreen.withOpacity(0.5),
                    ),
                  ),
                // Layer count badge
                if (hasAudio)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Builder(
                      builder: (_) {
                        final mw = Provider.of<MiddlewareProvider>(context, listen: false);
                        final eid = 'audio_${slot.stage}';
                        final evt = mw.compositeEvents.where((e) => e.id == eid).firstOrNull ??
                            mw.compositeEvents.where((e) => e.triggerStages.any((s) => s.toUpperCase() == slot.stage.toUpperCase())).firstOrNull;
                        final lc = evt?.layers.length ?? 0;
                        if (lc <= 1) return const SizedBox.shrink();
                        return Text(
                          '${lc}L',
                          style: TextStyle(
                            fontSize: 9,
                            color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5),
                            fontFamily: 'monospace',
                          ),
                        );
                      },
                    ),
                  ),
                // Play button — visible on hover or when playing
                if (hasAudio && (isSlotHovered || _playingStage == slot.stage))
                  GestureDetector(
                    onTap: () => _togglePreview(slot.stage, audioPath),
                    child: Icon(
                      _playingStage == slot.stage ? Icons.stop : Icons.play_arrow,
                      size: 14,
                      color: _playingStage == slot.stage
                          ? FluxForgeTheme.textSecondary
                          : FluxForgeTheme.textDisabled,
                    ),
                  ),
                // Clear button — visible on hover only
                if (hasAudio && isSlotHovered)
                  GestureDetector(
                    onTap: () => widget.onAudioClear?.call(slot.stage),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 3, right: 3),
                      child: Icon(Icons.close, size: 12, color: FluxForgeTheme.textDisabled),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      ),
      ),
    );
  }

  /// Toggle audio preview playback (SL-LP-P0.1)
  void _togglePreview(String stage, String audioPath) {
    if (_playingStage == stage) {
      // Stop if currently playing this stage
      AudioPlaybackService.instance.stopAll();
      setState(() => _playingStage = null);
    } else {
      // Stop previous and play new
      AudioPlaybackService.instance.stopAll();
      AudioPlaybackService.instance.previewFile(
        audioPath,
        source: PlaybackSource.browser, // Isolated engine
      );
      setState(() => _playingStage = stage);
    }
  }

  /// Show variant editor dialog (SL-LP-P1.4)
  void _showVariantEditor(BuildContext context, String stage, Color accentColor) {
    showDialog(
      context: context,
      builder: (context) => _VariantEditorDialog(
        stage: stage,
        accentColor: accentColor,
        onVariantsChanged: () => setState(() {}), // Refresh UI
      ),
    );
  }

  /// Count how many composite events use this stage (SL-INT-P1.1)
  int _countEventsForStage(MiddlewareProvider provider, String stage) {
    int count = 0;
    for (final event in provider.compositeEvents) {
      if (event.triggerStages.contains(stage)) {
        count++;
      }
    }
    return count;
  }

  int _countAssignedInSection(_SectionConfig section) {
    int count = 0;
    for (final group in section.groups) {
      count += _countAssignedInGroup(group);
    }
    return count;
  }

  /// Get total slot count in section (SL-LP-P0.2)
  int _getTotalSlotsInSection(_SectionConfig section) {
    int total = 0;
    for (final group in section.groups) {
      total += group.slots.length;
    }
    return total;
  }


  /// Get completion percentage for section (SL-LP-P0.2)
  int _getSectionPercentage(_SectionConfig section) {
    final total = _getTotalSlotsInSection(section);
    if (total == 0) return 0;
    final assigned = _countAssignedInSection(section);
    return ((assigned / total) * 100).toInt();
  }

  /// Check if a slot matches the current search/filter criteria
  bool _slotMatchesFilter(_SlotConfig slot) {
    final audioPath = widget.audioAssignments[slot.stage];
    final hasAudio = audioPath != null;
    if (_showUnassignedOnly && hasAudio) return false;
    if (_searchQuery.isNotEmpty) {
      final fileName = hasAudio ? audioPath.split('/').last.toLowerCase() : null;
      return slot.stage.toLowerCase().contains(_searchQuery) ||
             slot.label.toLowerCase().contains(_searchQuery) ||
             (fileName != null && fileName.contains(_searchQuery));
    }
    return true;
  }

  /// Check if any slot in a group matches filter
  bool _groupHasVisibleSlots(_GroupConfig group) {
    if (_searchQuery.isEmpty && !_showUnassignedOnly) return true;
    return group.slots.any(_slotMatchesFilter);
  }

  /// Check if any slot in a section matches filter
  bool _sectionHasVisibleSlots(_SectionConfig section) {
    if (_searchQuery.isEmpty && !_showUnassignedOnly) return true;
    return section.groups.any(_groupHasVisibleSlots);
  }

  /// Check if any slot in a phase matches filter
  bool _phaseHasVisibleSlots(_PhaseConfig phase) {
    if (_searchQuery.isEmpty && !_showUnassignedOnly) return true;
    return phase.sections.any(_sectionHasVisibleSlots);
  }

  /// Whether search/filter is active (auto-expand all)
  bool get _isFiltering => _searchQuery.isNotEmpty || _showUnassignedOnly;

  int _countAssignedInGroup(_GroupConfig group) {
    int count = 0;
    for (final slot in group.slots) {
      if (widget.audioAssignments.containsKey(slot.stage)) {
        count++;
      }
    }
    return count;
  }

  /// P3-17: Get total slot count and unassigned count for filter display
  /// V9: Uses phases to aggregate across all sections
  (int total, int unassigned) _getUnassignedStats() {
    int total = 0;
    int unassigned = 0;
    for (final phase in _buildPhases()) {
      for (final section in phase.sections) {
        for (final group in section.groups) {
          for (final slot in group.slots) {
            total++;
            if (!widget.audioAssignments.containsKey(slot.stage)) {
              unassigned++;
            }
          }
        }
      }
    }
    return (total, unassigned);
  }

  /// Handle folder drop on a group — auto-distribute files
  void _handleFolderDrop(_GroupConfig group, _SectionConfig section, List<String> audioPaths) {
    if (audioPaths.isEmpty) return;

    // Collect ALL stages from ALL groups in this section (not just the target group).
    // This ensures that dropping a mixed folder on any group still assigns files
    // to the correct stages across the entire section.
    final allSectionStages = <String>{};
    for (final g in section.groups) {
      for (final slot in g.slots) {
        allSectionStages.add(slot.stage);
      }
    }

    // Use BATCH matching with indexing convention detection.
    // This correctly handles 1-indexed filenames (reel_stop_3 → REEL_STOP_2)
    // unlike matchSingleFile() which has no batch context.
    final result = StageGroupService.instance.matchFilesToStages(
      audioPaths: audioPaths,
      allowedStages: allSectionStages,
    );

    // Apply matched assignments
    for (final match in result.matched) {
      widget.onAudioAssign?.call(match.stage, match.audioPath);
    }

    // Show results dialog
    if (mounted) {
      _showDistributionResult(result.matched, result.unmatched);
    }

    // Notify callback
    widget.onBatchDistribute?.call(result.matched, result.unmatched);
  }

  void _showDistributionResult(List<StageMatch> matched, List<UnmatchedFile> unmatched) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgMid,
        title: Row(
          children: [
            Icon(
              matched.isNotEmpty ? Icons.check_circle : Icons.warning,
              color: matched.isNotEmpty ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Auto-Distribution Result',
              style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 14),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgSurface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    _buildStatBadge('Matched', matched.length, FluxForgeTheme.accentGreen),
                    const SizedBox(width: 12),
                    _buildStatBadge('Unmatched', unmatched.length, FluxForgeTheme.accentOrange),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Matched files
              if (matched.isNotEmpty) ...[
                const Text(
                  'MATCHED FILES:',
                  style: TextStyle(fontSize: 10, color: FluxForgeTheme.textDisabled, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                ...matched.take(8).map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.check, size: 12, color: FluxForgeTheme.accentGreen),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          m.audioFileName,
                          style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '→ ${m.stage}',
                        style: TextStyle(fontSize: 10, color: FluxForgeTheme.accentBlue),
                      ),
                    ],
                  ),
                )),
                if (matched.length > 8)
                  Text(
                    '... and ${matched.length - 8} more',
                    style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textDisabled),
                  ),
              ],
              // Unmatched files
              if (unmatched.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'UNMATCHED FILES:',
                  style: TextStyle(fontSize: 10, color: FluxForgeTheme.textDisabled, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                ...unmatched.take(5).map((u) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.help_outline, size: 12, color: FluxForgeTheme.accentOrange),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          u.audioFileName,
                          style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (u.topSuggestion != null)
                        Text(
                          '? ${u.topSuggestion!.stage}',
                          style: const TextStyle(fontSize: 10, color: FluxForgeTheme.accentOrange),
                        ),
                    ],
                  ),
                )),
                if (unmatched.length > 5)
                  Text(
                    '... and ${unmatched.length - 5} more',
                    style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textDisabled),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: FluxForgeTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String label, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$count',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary),
        ),
      ],
    );
  }
}

/// Group drop zone that accepts folders
// ═══════════════════════════════════════════════════════════════════════════════
// Apple-style hover detection wrapper — lightweight StatefulWidget
// ═══════════════════════════════════════════════════════════════════════════════

class _HoverBuilder extends StatefulWidget {
  final Widget Function(bool isHovered) builder;
  const _HoverBuilder({required this.builder});

  @override
  State<_HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<_HoverBuilder> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: widget.builder(_isHovered),
    );
  }
}

class _GroupDropZone extends StatefulWidget {
  final _GroupConfig group;
  final _SectionConfig section;
  final bool isExpanded;
  final int assignedCount;
  final VoidCallback onToggle;
  final Function(List<String> paths) onFolderDrop;

  const _GroupDropZone({
    required this.group,
    required this.section,
    required this.isExpanded,
    required this.assignedCount,
    required this.onToggle,
    required this.onFolderDrop,
  });

  @override
  State<_GroupDropZone> createState() => _GroupDropZoneState();
}

class _GroupDropZoneState extends State<_GroupDropZone> {
  bool _isHovering = false; // drag hover
  bool _isMouseHover = false; // mouse hover

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        // Accept multiple files (folder drop simulation)
        final accepts = data is List<AudioAsset> ||
            data is AudioAsset ||
            data is String ||
            data is List<String>;
        if (accepts) {
          setState(() => _isHovering = true);
        }
        return accepts;
      },
      onLeave: (_) {
        setState(() => _isHovering = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _isHovering = false);
        final data = details.data;

        List<String> paths = [];
        if (data is List<AudioAsset>) {
          paths = data.map((a) => a.path).toList();
        } else if (data is AudioAsset) {
          paths = [data.path];
        } else if (data is List<String>) {
          paths = data;
        } else if (data is String) {
          paths = [data];
        }

        if (paths.isNotEmpty) {
          widget.onFolderDrop(paths);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final sectionColor = widget.section.color;
        final groupTint = Color.lerp(sectionColor, FluxForgeTheme.textTertiary, 0.65)!;

        return MouseRegion(
          onEnter: (_) => setState(() => _isMouseHover = true),
          onExit: (_) => setState(() => _isMouseHover = false),
          child: InkWell(
            onTap: widget.onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 26,
              margin: const EdgeInsets.only(left: 8, right: 8, top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _isHovering
                    ? FluxForgeTheme.bgElevated
                    : _isMouseHover
                        ? sectionColor.withOpacity(0.03)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: _isHovering
                    ? Border.all(color: FluxForgeTheme.textDisabled)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: _isMouseHover ? groupTint : FluxForgeTheme.textDisabled,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      widget.group.title,
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w500,
                        color: _isMouseHover ? groupTint : FluxForgeTheme.textTertiary,
                      ),
                    ),
                  ),
                  if (_isHovering)
                    const Text('DROP', style: TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w600,
                      color: FluxForgeTheme.textTertiary, letterSpacing: 0.5,
                    ))
                  else if (widget.assignedCount > 0)
                    Text(
                      '${widget.assignedCount}/${widget.group.slots.length}',
                      style: const TextStyle(
                        fontSize: 9, color: FluxForgeTheme.textDisabled, fontFamily: 'monospace',
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

// ═══════════════════════════════════════════════════════════════════════════════
// V8 SECTION CONFIGURATIONS — Game Flow Organization
// ═══════════════════════════════════════════════════════════════════════════════
//
// TIER SYSTEM:
// - PRIMARY (80% workflow): Base Game Loop, Symbols, Win Presentation
// - SECONDARY (15% workflow): Cascading, Multipliers
// - FEATURE: Free Spins, Bonus Games, Hold & Win
// - PREMIUM 🏆: Jackpots (regulatory validation)
// - OPTIONAL: Gamble
// - BACKGROUND: Music & Ambience
// - UTILITY: UI & System
//
// POOLED MARKERS: ⚡ = rapid-fire events (use voice pooling)
// ═══════════════════════════════════════════════════════════════════════════════

abstract class _SectionConfig {
  String get id;
  String get title;
  String get icon;
  Color get color;
  List<_GroupConfig> get groups;
}

class _GroupConfig {
  final String id;
  final String title;
  final String icon;
  final List<_SlotConfig> slots;

  const _GroupConfig({
    required this.id,
    required this.title,
    required this.icon,
    required this.slots,
  });
}

class _SlotConfig {
  final String stage;
  final String _explicitLabel;

  /// Label getter — centralized StageConfigurationService as SSoT.
  /// For stages with explicit labels in the service, uses service label.
  /// Falls back to explicit label provided at construction (dynamic stages like symbols).
  String get label {
    final serviceLabel = StageConfigurationService.instance.getDisplayLabel(stage);
    // If service returned Title Case fallback (no explicit entry), prefer explicit label
    final titleCaseFallback = stage.replaceAll('_', ' ').split(' ').map((w) =>
      w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}' : w
    ).join(' ');
    if (serviceLabel == titleCaseFallback) return _explicitLabel;
    return serviceLabel;
  }

  const _SlotConfig({required this.stage, required String label}) : _explicitLabel = label;

  /// V9: Resolve bus routing from stage name pattern
  SlotBus get bus => _resolveSlotBus(stage);

  /// V9: Resolve priority from stage name pattern
  SlotPriority get priority => _resolveSlotPriority(stage);
}

/// V9: Determine audio bus from stage name using pattern matching
SlotBus _resolveSlotBus(String stage) {
  final s = stage.toUpperCase();

  // Music bus — looping, background, ambient, stingers
  if (s.startsWith('MUSIC_') || s.startsWith('AMBIENT_') ||
      s.startsWith('ATTRACT_') || s.startsWith('IDLE_') ||
      s.contains('_MUSIC') || s.contains('_LOOP') && !s.contains('REEL') ||
      s.startsWith('MUSIC_STINGER')) {
    return SlotBus.music;
  }

  // Reels bus — reel mechanics
  if (s.startsWith('REEL_') || s.startsWith('SPIN_') ||
      s.startsWith('ANTICIPATION_') || s == 'QUICK_STOP' ||
      s == 'SLAM_STOP' || s == 'SLAM_STOP_IMPACT' ||
      s.startsWith('TURBO_SPIN')) {
    return SlotBus.reels;
  }

  // UI bus — interface sounds
  if (s.startsWith('UI_') || s.startsWith('AUTOPLAY_') ||
      s.startsWith('GAME_') || s.startsWith('BUY_') ||
      s.startsWith('ANTE_') || s.startsWith('SUPER_BET') ||
      s.startsWith('TURBO_MODE')) {
    return SlotBus.ui;
  }

  // Voice bus — voice-overs
  if (s.contains('_VOICE') || s.contains('_VO') ||
      s.startsWith('ANNOUNCE') || s.startsWith('NARRATOR')) {
    return SlotBus.voice;
  }

  // Ambience bus — ambient sounds
  if (s.startsWith('AMBIENT_')) {
    return SlotBus.ambience;
  }

  // Default: SFX bus (wins, symbols, features, jackpots, etc.)
  return SlotBus.sfx;
}

/// V9: Determine priority from stage name using pattern matching
SlotPriority _resolveSlotPriority(String stage) {
  final s = stage.toUpperCase();

  // P0: Critical — core loop that EVERY slot game needs
  if (s == 'UI_SPIN_PRESS' || s == 'SPIN_END' || s == 'NO_WIN' ||
      s.startsWith('REEL_STOP') || s == 'REEL_SPIN_LOOP' ||
      s == 'WIN_PRESENT' || s == 'ROLLUP_START' || s == 'ROLLUP_TICK' ||
      s == 'ROLLUP_END' || s.startsWith('WIN_LINE_') ||
      s == 'PAYLINE_HIGHLIGHT' ||
      s == 'SYMBOL_WIN' || s.endsWith('_WIN') ||
      s == 'EVALUATE_WINS' ||
      s.startsWith('ANTICIPATION_') ||
      s.startsWith('SYMBOL_LAND') || s.endsWith('_LAND')) {
    return SlotPriority.p0;
  }

  // P2: Optional — polish, edge cases, gamble, ambient variants
  if (s.startsWith('GAMBLE_') || s.startsWith('AMBIENT_') ||
      s.startsWith('UI_SLIDER') || s.startsWith('UI_TOGGLE') ||
      s.startsWith('UI_POPUP') || s.startsWith('UI_LOADING') ||
      s.startsWith('NEAR_MISS_REEL') || s.startsWith('BOSS_') ||
      s.startsWith('TRAIL_') || s.startsWith('DICE_') ||
      s.startsWith('BOARD_') || s.startsWith('LEVEL_') ||
      s.startsWith('MUST_HIT') || s.startsWith('HOT_DROP') ||
      s.startsWith('MUSIC_STING') || s.startsWith('MUSIC_DUCK') ||
      s.startsWith('MUSIC_CROSSFADE') || s.startsWith('MUSIC_TRANSITION')) {
    return SlotPriority.p2;
  }

  // Default: P1 — important but not critical
  return SlotPriority.p1;
}

// ═══════════════════════════════════════════════════════════════════════════════
// V9: Phase — groups related sections into game flow phases
// ═══════════════════════════════════════════════════════════════════════════════

class _PhaseConfig {
  final String id;
  final String title;
  final String icon;
  final Color color;
  final SlotPriority priority;
  final String description;
  final List<_SectionConfig> sections;

  const _PhaseConfig({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.priority,
    required this.description,
    required this.sections,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 1: BASE GAME LOOP [PRIMARY] — 41 slots
// The core spin cycle: Idle → Spin → Reel Animation → Stops → End
// ═══════════════════════════════════════════════════════════════════════════════

class _BaseGameLoopSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _BaseGameLoopSection({required this.widget});

  @override String get id => 'base_game_loop';
  @override String get title => 'BASE GAME LOOP';
  @override String get icon => '🎰';
  @override Color get color => const Color(0xFF4A9EFF);

  /// Reel count from current config (for filtering per-reel stages)
  int get _reelCount => GetIt.instance<FeatureComposerProvider>().config?.reelCount ?? 3;

  @override
  List<_GroupConfig> get groups {
    final rc = _reelCount;

    // Filter per-reel slots based on configured reel count
    final reelStops = <_SlotConfig>[
      const _SlotConfig(stage: 'REEL_STOP', label: 'Generic Stop'),
      for (int i = 0; i < rc; i++)
        _SlotConfig(stage: 'REEL_STOP_$i', label: 'Reel ${i + 1} Stop'),
    ];

    // Anticipation: basic always, per-reel for all reels in grid.
    // Any reel (R0-R7) can have anticipation depending on game logic config.
    // All L1-L4 levels registered per reel — runtime decides actual tension.
    final anticSlots = <_SlotConfig>[
      const _SlotConfig(stage: 'ANTICIPATION_TENSION', label: 'Anticipation (Global)'),
      const _SlotConfig(stage: 'ANTICIPATION_MISS', label: 'Anticipation Miss'),
      for (int r = 0; r < rc; r++)
        _SlotConfig(stage: 'ANTICIPATION_TENSION_R$r', label: 'Reel ${r + 1} Tension'),
      for (int r = 0; r < rc; r++)
        for (int l = 1; l <= 4; l++)
          _SlotConfig(stage: 'ANTICIPATION_TENSION_R${r}_L$l', label: 'Reel ${r + 1} Level $l'),
    ];

    // Near-miss: generic + per-reel filtered
    final nearMissSlots = <_SlotConfig>[
      const _SlotConfig(stage: 'SPIN_END', label: 'Spin End'),
      const _SlotConfig(stage: 'NO_WIN', label: 'No Win'),
      const _SlotConfig(stage: 'NEAR_MISS', label: 'Near Miss (Generic)'),
      for (int i = 0; i < rc; i++)
        _SlotConfig(stage: 'NEAR_MISS_REEL_$i', label: 'Near Miss R${i + 1}'),
      const _SlotConfig(stage: 'NEAR_MISS_SCATTER', label: 'Near Miss Scatter'),
      const _SlotConfig(stage: 'NEAR_MISS_BONUS', label: 'Near Miss Bonus'),
      const _SlotConfig(stage: 'NEAR_MISS_JACKPOT', label: 'Near Miss JP'),
      const _SlotConfig(stage: 'NEAR_MISS_WILD', label: 'Near Miss Wild'),
      const _SlotConfig(stage: 'NEAR_MISS_FEATURE', label: 'Near Miss Feature'),
    ];

    return [
      const _GroupConfig(
        id: 'idle',
        title: 'Idle / Attract',
        icon: '💤',
        slots: [
          _SlotConfig(stage: 'ATTRACT_LOOP', label: 'Attract Loop'),
          _SlotConfig(stage: 'ATTRACT_EXIT', label: 'Attract Exit'),
          _SlotConfig(stage: 'IDLE_LOOP', label: 'Idle Loop'),
          _SlotConfig(stage: 'IDLE_TO_ACTIVE', label: 'Idle → Active'),
          _SlotConfig(stage: 'GAME_READY', label: 'Game Ready'),
          _SlotConfig(stage: 'GAME_START', label: 'Base Game Start'),
        ],
      ),
      const _GroupConfig(
        id: 'spin_controls',
        title: 'Spin Controls',
        icon: '🔄',
        slots: [
          _SlotConfig(stage: 'UI_SPIN_PRESS', label: 'Spin Press'),
          _SlotConfig(stage: 'SPIN_CANCEL', label: 'Spin Cancel'),
          _SlotConfig(stage: 'UI_STOP_PRESS', label: 'Stop Press'),
          _SlotConfig(stage: 'QUICK_STOP', label: 'Quick Stop'),
          _SlotConfig(stage: 'SLAM_STOP', label: 'Slam Stop'),
          _SlotConfig(stage: 'SLAM_STOP_IMPACT', label: 'Slam Impact'),
          _SlotConfig(stage: 'SKIP', label: 'Skip'),
          _SlotConfig(stage: 'UI_AUTOPLAY_START', label: 'AutoSpin On'),
          _SlotConfig(stage: 'UI_AUTOPLAY_STOP', label: 'AutoSpin Off'),
          _SlotConfig(stage: 'UI_TURBO_ON', label: 'Turbo On'),
          _SlotConfig(stage: 'UI_TURBO_OFF', label: 'Turbo Off'),
        ],
      ),
      const _GroupConfig(
        id: 'reel_animation',
        title: 'Reel Animation',
        icon: '🔃',
        slots: [
          _SlotConfig(stage: 'REEL_SPIN_LOOP', label: 'Spin Loop'),
          _SlotConfig(stage: 'SPIN_ACCELERATION', label: 'Spin Accel'),
          _SlotConfig(stage: 'SPIN_DECELERATION', label: 'Spin Decel'),
          _SlotConfig(stage: 'TURBO_SPIN_LOOP', label: 'Turbo Loop'),
          _SlotConfig(stage: 'REEL_SLOW_STOP', label: 'Slow Stop'),
          _SlotConfig(stage: 'REEL_SHAKE', label: 'Reel Shake'),
          _SlotConfig(stage: 'REEL_WIGGLE', label: 'Reel Wiggle'),
        ],
      ),
      _GroupConfig(id: 'reel_stops', title: 'Reel Stops', icon: '🛑', slots: reelStops),
      _GroupConfig(id: 'anticipation', title: 'Anticipation', icon: '⏳', slots: anticSlots),
      _GroupConfig(id: 'spin_end', title: 'Spin End', icon: '🏁', slots: nearMissSlots),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 2: SYMBOLS & LANDS [PRIMARY] — 46 slots
// Symbol landing and special symbol mechanics
// ═══════════════════════════════════════════════════════════════════════════════

class _SymbolsSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _SymbolsSection({required this.widget});

  @override String get id => 'symbols';
  @override String get title => 'SYMBOLS';
  @override String get icon => '🎰';
  @override Color get color => const Color(0xFF9370DB);

  @override
  List<_GroupConfig> get groups {
    // Generate groups from widget.symbols
    final special = widget.symbols.where((s) =>
        s.type == SymbolType.wild ||
        s.type == SymbolType.scatter ||
        s.type == SymbolType.bonus ||
        s.type == SymbolType.multiplier).toList();
    final highPay = widget.symbols.where((s) =>
        s.type == SymbolType.high ||
        s.type == SymbolType.highPay).toList();
    // Note: Low Pay and Medium Pay are now static 1-5 slots (not dynamic)

    return [
      _GroupConfig(
        id: 'special',
        title: 'Special Symbols',
        icon: '✨',
        slots: special.expand((s) {
          final id = s.id.toUpperCase();
          return [
            // Indexed land slots #1-5 for per-reel audio
            _SlotConfig(stage: '${id}_LAND_1', label: '${s.name} #1'),
            _SlotConfig(stage: '${id}_LAND_2', label: '${s.name} #2'),
            _SlotConfig(stage: '${id}_LAND_3', label: '${s.name} #3'),
            _SlotConfig(stage: '${id}_LAND_4', label: '${s.name} #4'),
            _SlotConfig(stage: '${id}_LAND_5', label: '${s.name} #5'),
            // Win sound
            _SlotConfig(stage: '${id}_WIN', label: '${s.name} Win'),
          ];
        }).toList(),
      ),
      _GroupConfig(
        id: 'highpay',
        title: 'High Pay',
        icon: '💎',
        slots: highPay.expand((s) => [
          _SlotConfig(stage: '${s.id.toUpperCase()}_LAND', label: '${s.name} Land'),
          _SlotConfig(stage: '${s.id.toUpperCase()}_WIN', label: '${s.name} Win'),
        ]).toList(),
      ),
      // ═══════════════════════════════════════════════════════════════════════
      // MEDIUM PAY 1-5 (Static slots for generic medium value symbols)
      // ═══════════════════════════════════════════════════════════════════════
      const _GroupConfig(
        id: 'mediumpay',
        title: 'Medium Pay',
        icon: '♦️',
        slots: [
          _SlotConfig(stage: 'MP1_LAND', label: 'Medium 1 Land'),
          _SlotConfig(stage: 'MP1_WIN', label: 'Medium 1 Win'),
          _SlotConfig(stage: 'MP2_LAND', label: 'Medium 2 Land'),
          _SlotConfig(stage: 'MP2_WIN', label: 'Medium 2 Win'),
          _SlotConfig(stage: 'MP3_LAND', label: 'Medium 3 Land'),
          _SlotConfig(stage: 'MP3_WIN', label: 'Medium 3 Win'),
          _SlotConfig(stage: 'MP4_LAND', label: 'Medium 4 Land'),
          _SlotConfig(stage: 'MP4_WIN', label: 'Medium 4 Win'),
          _SlotConfig(stage: 'MP5_LAND', label: 'Medium 5 Land'),
          _SlotConfig(stage: 'MP5_WIN', label: 'Medium 5 Win'),
        ],
      ),
      // ═══════════════════════════════════════════════════════════════════════
      // LOW PAY 1-5 (Static slots for generic low value symbols)
      // ═══════════════════════════════════════════════════════════════════════
      const _GroupConfig(
        id: 'lowpay',
        title: 'Low Pay',
        icon: '♠️',
        slots: [
          _SlotConfig(stage: 'LP1_LAND', label: 'Low 1 Land'),
          _SlotConfig(stage: 'LP1_WIN', label: 'Low 1 Win'),
          _SlotConfig(stage: 'LP2_LAND', label: 'Low 2 Land'),
          _SlotConfig(stage: 'LP2_WIN', label: 'Low 2 Win'),
          _SlotConfig(stage: 'LP3_LAND', label: 'Low 3 Land'),
          _SlotConfig(stage: 'LP3_WIN', label: 'Low 3 Win'),
          _SlotConfig(stage: 'LP4_LAND', label: 'Low 4 Land'),
          _SlotConfig(stage: 'LP4_WIN', label: 'Low 4 Win'),
          _SlotConfig(stage: 'LP5_LAND', label: 'Low 5 Land'),
          _SlotConfig(stage: 'LP5_WIN', label: 'Low 5 Win'),
        ],
      ),
      // ═══════════════════════════════════════════════════════════════════════
      // WILD VARIATIONS (P0 — 15 slots)
      // Extended wild symbol mechanics
      // ═══════════════════════════════════════════════════════════════════════
      const _GroupConfig(
        id: 'wild_expanded',
        title: 'Wild Variations',
        icon: '🃏',
        slots: [
          _SlotConfig(stage: 'WILD_EXPAND_START', label: 'Wild Expand Start'),
          _SlotConfig(stage: 'WILD_EXPAND_STEP', label: 'Wild Expand Step'),
          _SlotConfig(stage: 'WILD_EXPAND_END', label: 'Wild Expand End'),
          _SlotConfig(stage: 'WILD_STICK', label: 'Wild Stick'),
          _SlotConfig(stage: 'WILD_WALK_LEFT', label: 'Wild Walk L'),
          _SlotConfig(stage: 'WILD_WALK_RIGHT', label: 'Wild Walk R'),
          _SlotConfig(stage: 'WILD_TRANSFORM', label: 'Wild Transform'),
          _SlotConfig(stage: 'WILD_MULTIPLY', label: 'Wild Multiply'),
          _SlotConfig(stage: 'WILD_SPREAD', label: 'Wild Spread'),
          _SlotConfig(stage: 'WILD_NUDGE', label: 'Wild Nudge'),
          _SlotConfig(stage: 'WILD_STACK', label: 'Wild Stack'),
          _SlotConfig(stage: 'WILD_COLOSSAL', label: 'Colossal Wild'),
          _SlotConfig(stage: 'WILD_REEL', label: 'Wild Reel'),
          _SlotConfig(stage: 'WILD_UPGRADE', label: 'Wild Upgrade'),
          _SlotConfig(stage: 'WILD_COLLECT', label: 'Wild Collect'),
        ],
      ),
      // ═══════════════════════════════════════════════════════════════════════
      // SPECIAL SYMBOLS EXPANDED (P0 — 15 slots)
      // Mystery, Collector, Coin symbols
      // ═══════════════════════════════════════════════════════════════════════
      const _GroupConfig(
        id: 'special_expanded',
        title: 'Special Expanded',
        icon: '🔮',
        slots: [
          _SlotConfig(stage: 'MYSTERY_LAND', label: 'Mystery Land'),
          _SlotConfig(stage: 'MYSTERY_REVEAL', label: 'Mystery Reveal'),
          _SlotConfig(stage: 'MYSTERY_TRANSFORM', label: 'Mystery Transform'),
          _SlotConfig(stage: 'COLLECTOR_LAND', label: 'Collector Land'),
          _SlotConfig(stage: 'COLLECTOR_COLLECT', label: 'Collector Collect'),
          _SlotConfig(stage: 'COLLECTOR_ACTIVATE', label: 'Collector Activate'),
          _SlotConfig(stage: 'COIN_LAND', label: 'Coin Land'),
          _SlotConfig(stage: 'COIN_VALUE_REVEAL', label: 'Coin Value Reveal'),
          _SlotConfig(stage: 'COIN_COLLECT', label: 'Coin Collect'),
        ],
      ),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3: WIN PRESENTATION [PRIMARY] — DYNAMIC from SlotWinConfiguration
// Win detection → Line show → Tier display → Rollup → Celebration
// P5: Uses SlotWinConfiguration for dynamic tier generation
// ═══════════════════════════════════════════════════════════════════════════════

class _WinPresentationSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _WinPresentationSection({required this.widget});

  @override String get id => 'win_presentation';
  @override String get title => 'WIN PRESENTATION';
  @override String get icon => '🏆';
  @override Color get color => const Color(0xFFFFD700);

  @override
  List<_GroupConfig> get groups {
    final config = widget.winConfiguration;

    // Build dynamic Win Tiers group from configuration
    final List<_SlotConfig> tierSlots = [];

    // P5: Regular win tiers (< bigWinThreshold)
    if (config != null) {
      for (final tier in config.regularWins.tiers) {
        // Format multiplier range for label
        final fromStr = tier.fromMultiplier.toStringAsFixed(tier.fromMultiplier.truncateToDouble() == tier.fromMultiplier ? 0 : 1);
        final toStr = tier.toMultiplier == double.infinity
            ? '∞'
            : tier.toMultiplier.toStringAsFixed(tier.toMultiplier.truncateToDouble() == tier.toMultiplier ? 0 : 1);

        // Primary stage (present stage)
        tierSlots.add(_SlotConfig(
          stage: tier.presentStageName,
          label: '${tier.displayLabel} (${fromStr}x-${toStr}x)',
        ));

        // Rollup stages for this tier (if not instant/WIN_LOW)
        if (tier.rollupStartStageName != null) {
          tierSlots.add(_SlotConfig(
            stage: tier.rollupStartStageName!,
            label: '${tier.displayLabel} Rollup Start',
          ));
          tierSlots.add(_SlotConfig(
            stage: tier.rollupTickStageName!,
            label: '${tier.displayLabel} Rollup Tick ⚡',
          ));
          tierSlots.add(_SlotConfig(
            stage: tier.rollupEndStageName!,
            label: '${tier.displayLabel} Rollup End',
          ));
        }
      }

      // P5: Big Win tier entry (threshold crossing)
      final threshold = config.bigWins.threshold;
      tierSlots.add(_SlotConfig(
        stage: 'BIG_WIN_TRIGGER',
        label: 'Big Win Trigger (≥${threshold.toStringAsFixed(0)}x)',
      ));

      // P5: Big Win internal tiers (escalation)
      for (final bigTier in config.bigWins.tiers) {
        final fromStr = bigTier.fromMultiplier.toStringAsFixed(bigTier.fromMultiplier.truncateToDouble() == bigTier.fromMultiplier ? 0 : 1);
        final toStr = bigTier.toMultiplier == double.infinity
            ? '∞'
            : bigTier.toMultiplier.toStringAsFixed(bigTier.toMultiplier.truncateToDouble() == bigTier.toMultiplier ? 0 : 1);

        // Use displayLabel if set, otherwise generate default
        final label = bigTier.displayLabel.isNotEmpty
            ? bigTier.displayLabel
            : 'Big Win Tier ${bigTier.tierId}';

        tierSlots.add(_SlotConfig(
          stage: bigTier.stageName,
          label: '$label (${fromStr}x-${toStr}x)',
        ));
      }

      // Big Win common stages
      tierSlots.addAll(const [
        _SlotConfig(stage: 'BIG_WIN_START', label: 'Big Win Intro'),
        _SlotConfig(stage: 'BIG_WIN_END', label: 'Big Win End'),
        _SlotConfig(stage: 'BIG_WIN_TICK_START', label: 'Big Win Tick Start'),
        _SlotConfig(stage: 'BIG_WIN_TICK_END', label: 'Big Win Tick End'),
        _SlotConfig(stage: 'COIN_SHOWER_START', label: 'Coin Shower Start'),
        _SlotConfig(stage: 'COIN_SHOWER_END', label: 'Coin Shower End'),
      ]);
    } else {
      // Fallback: Default slots when no config (legacy compatibility)
      tierSlots.addAll(const [
        _SlotConfig(stage: 'WIN_PRESENT_LOW', label: 'Low Win (< bet)'),
        _SlotConfig(stage: 'WIN_PRESENT_EQUAL', label: 'Equal Win (= bet)'),
        _SlotConfig(stage: 'WIN_PRESENT_1', label: 'Win Tier 1 (>1x, ≤2x)'),
        _SlotConfig(stage: 'WIN_PRESENT_2', label: 'Win Tier 2 (>2x, ≤4x)'),
        _SlotConfig(stage: 'WIN_PRESENT_3', label: 'Win Tier 3 (>4x, ≤8x)'),
        _SlotConfig(stage: 'WIN_PRESENT_4', label: 'Win Tier 4 (>8x, ≤13x)'),
        _SlotConfig(stage: 'WIN_PRESENT_5', label: 'Win Tier 5 (>13x, ≤16x)'),
        _SlotConfig(stage: 'WIN_PRESENT_6', label: 'Win Tier 6 (>16x, ≤18x)'),
        _SlotConfig(stage: 'WIN_PRESENT_7', label: 'Win Tier 7 (>18x, ≤19x)'),
        _SlotConfig(stage: 'WIN_PRESENT_8', label: 'Win Tier 8 (>19x)'),
        _SlotConfig(stage: 'BIG_WIN_TRIGGER', label: 'Big Win Trigger (≥20x)'),
        _SlotConfig(stage: 'BIG_WIN_TIER_1', label: 'Big Win Tier 1 (20x-50x)'),
        _SlotConfig(stage: 'BIG_WIN_TIER_2', label: 'Big Win Tier 2 (50x-100x)'),
        _SlotConfig(stage: 'BIG_WIN_TIER_3', label: 'Big Win Tier 3 (100x-250x)'),
        _SlotConfig(stage: 'BIG_WIN_TIER_4', label: 'Big Win Tier 4 (250x-500x)'),
        _SlotConfig(stage: 'BIG_WIN_TIER_5', label: 'Big Win Tier 5 (500x+)'),
      ]);
    }

    return [
      // ─── WIN EVALUATION ───
      const _GroupConfig(
        id: 'eval',
        title: 'Win Evaluation',
        icon: '🔍',
        slots: [
          _SlotConfig(stage: 'WIN_EVAL', label: 'Win Evaluate'),
          _SlotConfig(stage: 'WIN_DETECTED', label: 'Win Detected'),
          _SlotConfig(stage: 'WIN_CALCULATE', label: 'Win Calculate'),
        ],
      ),
      // ─── PAYLINES & WIN LINES ⚡ (pooled) ───
      const _GroupConfig(
        id: 'lines',
        title: 'Paylines & Win Lines ⚡',
        icon: '📊',
        slots: [
          _SlotConfig(stage: 'PAYLINE_HIGHLIGHT', label: 'Payline Highlight'),
          _SlotConfig(stage: 'WIN_LINE_SHOW', label: 'Line Show'),
          _SlotConfig(stage: 'WIN_LINE_HIDE', label: 'Line Hide'),
          _SlotConfig(stage: 'SYMBOL_WIN', label: 'Symbol Win (Generic)'),
          _SlotConfig(stage: 'WIN_LINE_CYCLE', label: 'Line Cycle'),
        ],
      ),
      // ─── PER-SYMBOL WIN AUDIO ⚡ (pooled) ───
      const _GroupConfig(
        id: 'symbol_wins',
        title: 'Per-Symbol Win ⚡',
        icon: '💎',
        slots: [
          _SlotConfig(stage: 'HP_WIN', label: 'HP (All) Win'),
          _SlotConfig(stage: 'HP1_WIN', label: 'HP1 Win'),
          _SlotConfig(stage: 'HP2_WIN', label: 'HP2 Win'),
          _SlotConfig(stage: 'HP3_WIN', label: 'HP3 Win'),
          _SlotConfig(stage: 'HP4_WIN', label: 'HP4 Win'),
          _SlotConfig(stage: 'MP_WIN', label: 'MP (All) Win'),
          _SlotConfig(stage: 'MP1_WIN', label: 'MP1 Win'),
          _SlotConfig(stage: 'MP2_WIN', label: 'MP2 Win'),
          _SlotConfig(stage: 'MP3_WIN', label: 'MP3 Win'),
          _SlotConfig(stage: 'MP4_WIN', label: 'MP4 Win'),
          _SlotConfig(stage: 'MP5_WIN', label: 'MP5 Win'),
          _SlotConfig(stage: 'LP_WIN', label: 'LP (All) Win'),
          _SlotConfig(stage: 'LP1_WIN', label: 'LP1 Win'),
          _SlotConfig(stage: 'LP2_WIN', label: 'LP2 Win'),
          _SlotConfig(stage: 'LP3_WIN', label: 'LP3 Win'),
          _SlotConfig(stage: 'LP4_WIN', label: 'LP4 Win'),
          _SlotConfig(stage: 'LP5_WIN', label: 'LP5 Win'),
          _SlotConfig(stage: 'LP6_WIN', label: 'LP6 Win'),
          _SlotConfig(stage: 'BONUS_WIN', label: 'Bonus Win'),
        ],
      ),
      // ─── WIN TIERS (P5 DYNAMIC) ───
      _GroupConfig(
        id: 'tiers',
        title: 'Win Tiers (P5)',
        icon: '🎖️',
        slots: tierSlots,
      ),
      // ─── ROLLUP / COUNTER ⚡ (pooled) ───
      const _GroupConfig(
        id: 'rollup',
        title: 'Rollup / Counter ⚡',
        icon: '🔢',
        slots: [
          _SlotConfig(stage: 'ROLLUP_START', label: 'Rollup Start'),
          _SlotConfig(stage: 'ROLLUP_TICK', label: 'Rollup Tick'),
          _SlotConfig(stage: 'ROLLUP_TICK_FAST', label: 'Rollup Fast'),
          _SlotConfig(stage: 'ROLLUP_TICK_SLOW', label: 'Rollup Slow'),
          _SlotConfig(stage: 'ROLLUP_ACCELERATION', label: 'Rollup Accel'),
          _SlotConfig(stage: 'ROLLUP_DECELERATION', label: 'Rollup Decel'),
          _SlotConfig(stage: 'ROLLUP_END', label: 'Rollup End'),
          _SlotConfig(stage: 'ROLLUP_SKIP', label: 'Rollup Skip'),
        ],
      ),
      // ─── WIN CELEBRATION ───
      const _GroupConfig(
        id: 'celebration',
        title: 'Win Celebration',
        icon: '🎊',
        slots: [
          _SlotConfig(stage: 'COIN_BURST', label: 'Coin Burst'),
          _SlotConfig(stage: 'COIN_DROP', label: 'Coin Drop'),
          _SlotConfig(stage: 'COIN_SHOWER', label: 'Coin Shower'),
          _SlotConfig(stage: 'COIN_RAIN', label: 'Coin Rain'),
          _SlotConfig(stage: 'SCREEN_SHAKE', label: 'Screen Shake'),
          _SlotConfig(stage: 'LIGHT_FLASH', label: 'Light Flash'),
          _SlotConfig(stage: 'CONFETTI_BURST', label: 'Confetti Burst'),
          _SlotConfig(stage: 'FIREWORKS_LAUNCH', label: 'Fireworks Launch'),
          _SlotConfig(stage: 'FIREWORKS_EXPLODE', label: 'Fireworks Explode'),
          _SlotConfig(stage: 'WIN_FANFARE', label: 'Win Fanfare'),
        ],
      ),
      // ─── VOICE OVERS (Dynamic) ───
      _GroupConfig(
        id: 'voice',
        title: 'Voice Overs',
        icon: '🎙️',
        slots: _buildVoiceOverSlots(config),
      ),
    ];
  }

  /// Build voice over slots dynamically based on win configuration
  List<_SlotConfig> _buildVoiceOverSlots(SlotWinConfiguration? config) {
    final slots = <_SlotConfig>[];

    if (config != null) {
      // Voice over for each regular tier
      for (final tier in config.regularWins.tiers) {
        slots.add(_SlotConfig(
          stage: 'VO_${tier.stageName}',
          label: 'VO ${tier.displayLabel}',
        ));
      }

      // Voice over for Big Win tiers
      for (final bigTier in config.bigWins.tiers) {
        final label = bigTier.displayLabel.isNotEmpty
            ? bigTier.displayLabel
            : 'Big Win Tier ${bigTier.tierId}';
        slots.add(_SlotConfig(
          stage: 'VO_${bigTier.stageName}',
          label: 'VO $label',
        ));
      }
    } else {
      // Fallback default voice overs (WIN_6 removed)
      slots.addAll(const [
        _SlotConfig(stage: 'VO_WIN_1', label: 'VO Win Tier 1'),
        _SlotConfig(stage: 'VO_WIN_2', label: 'VO Win Tier 2'),
        _SlotConfig(stage: 'VO_WIN_3', label: 'VO Win Tier 3'),
        _SlotConfig(stage: 'VO_WIN_4', label: 'VO Win Tier 4'),
        _SlotConfig(stage: 'VO_WIN_5', label: 'VO Win Tier 5'),
        _SlotConfig(stage: 'VO_BIG_WIN', label: 'VO Big Win'),
      ]);
    }

    // Common voice overs
    slots.addAll(const [
      _SlotConfig(stage: 'VO_CONGRATULATIONS', label: 'VO Congrats'),
      _SlotConfig(stage: 'VO_INCREDIBLE', label: 'VO Incredible'),
      _SlotConfig(stage: 'VO_SENSATIONAL', label: 'VO Sensational'),
    ]);

    return slots;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 4: CASCADING MECHANICS [SECONDARY] — 30 slots
// Cascade/Tumble/Avalanche unified (same concept, different names)
// ═══════════════════════════════════════════════════════════════════════════════

class _CascadingSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _CascadingSection({required this.widget});

  @override String get id => 'cascading';
  @override String get title => 'CASCADING';
  @override String get icon => '💧';
  @override Color get color => const Color(0xFF40C8FF);

  @override
  List<_GroupConfig> get groups => const [
    // ─── BASIC CASCADE ───
    _GroupConfig(
      id: 'basic',
      title: 'Basic Cascade',
      icon: '💧',
      slots: [
        _SlotConfig(stage: 'CASCADE_START', label: 'Cascade Start'),
        _SlotConfig(stage: 'CASCADE_STEP', label: 'Cascade Step'),
        _SlotConfig(stage: 'CASCADE_POP', label: 'Cascade Pop'),
        _SlotConfig(stage: 'CASCADE_END', label: 'Cascade End'),
      ],
    ),
    // ─── CASCADE CHAIN ⚡ (pooled) ───
    _GroupConfig(
      id: 'chain',
      title: 'Cascade Chain ⚡',
      icon: '🔗',
      slots: [
        _SlotConfig(stage: 'CASCADE_STEP_1', label: 'Cascade 1'),
        _SlotConfig(stage: 'CASCADE_STEP_2', label: 'Cascade 2'),
        _SlotConfig(stage: 'CASCADE_STEP_3', label: 'Cascade 3'),
        _SlotConfig(stage: 'CASCADE_STEP_4', label: 'Cascade 4'),
        _SlotConfig(stage: 'CASCADE_STEP_5', label: 'Cascade 5'),
        _SlotConfig(stage: 'CASCADE_STEP_6PLUS', label: 'Cascade 6+'),
        _SlotConfig(stage: 'CASCADE_SYMBOL_POP', label: 'Symbol Pop'),
        _SlotConfig(stage: 'CASCADE_SYMBOL_DROP', label: 'Symbol Drop'),
        _SlotConfig(stage: 'CASCADE_SYMBOL_LAND', label: 'Symbol Land'),
      ],
    ),
    // ─── CASCADE EFFECTS ───
    _GroupConfig(
      id: 'effects',
      title: 'Cascade Effects',
      icon: '✨',
      slots: [
        _SlotConfig(stage: 'CASCADE_CHAIN_START', label: 'Chain Start'),
        _SlotConfig(stage: 'CASCADE_CHAIN_CONTINUE', label: 'Chain Continue'),
        _SlotConfig(stage: 'CASCADE_CHAIN_END', label: 'Chain End'),
        _SlotConfig(stage: 'CASCADE_ANTICIPATION', label: 'Cascade Antic'),
        _SlotConfig(stage: 'CASCADE_MEGA', label: 'Cascade Mega'),
      ],
    ),
    // ─── TUMBLE / AVALANCHE ───
    _GroupConfig(
      id: 'tumble',
      title: 'Tumble / Avalanche',
      icon: '🌊',
      slots: [
        _SlotConfig(stage: 'TUMBLE_DROP', label: 'Tumble Drop'),
        _SlotConfig(stage: 'TUMBLE_IMPACT', label: 'Tumble Impact'),
        _SlotConfig(stage: 'AVALANCHE_TRIGGER', label: 'Avalanche Trigger'),
        _SlotConfig(stage: 'REACTION_WIN', label: 'Reaction Win'),
        _SlotConfig(stage: 'GRAVITY_SHIFT', label: 'Gravity Shift'),
        _SlotConfig(stage: 'REPLACEMENT_FALL', label: 'Replacement Fall'),
      ],
    ),
    // ─── CLUSTER ───
    _GroupConfig(
      id: 'cluster',
      title: 'Cluster',
      icon: '🔮',
      slots: [
        _SlotConfig(stage: 'CLUSTER_FORM', label: 'Cluster Form'),
        _SlotConfig(stage: 'CLUSTER_EXPLODE', label: 'Cluster Explode'),
        _SlotConfig(stage: 'CLUSTER_WIN', label: 'Cluster Win'),
      ],
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 5: MULTIPLIERS [SECONDARY] — 22 slots
// Win multipliers, progressive multipliers, random multipliers
// ═══════════════════════════════════════════════════════════════════════════════

class _MultipliersSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _MultipliersSection({required this.widget});

  @override String get id => 'multipliers';
  @override String get title => 'MULTIPLIERS';
  @override String get icon => '✖️';
  @override Color get color => const Color(0xFFFF6B6B);

  @override
  List<_GroupConfig> get groups => const [
    // ─── WIN MULTIPLIERS ───
    _GroupConfig(
      id: 'win',
      title: 'Win Multipliers',
      icon: '✖️',
      slots: [
        _SlotConfig(stage: 'MULTIPLIER_INCREASE', label: 'Multi Increase'),
        _SlotConfig(stage: 'MULTIPLIER_APPLY', label: 'Multi Apply'),
        _SlotConfig(stage: 'MULTIPLIER_X2', label: 'Multi x2'),
        _SlotConfig(stage: 'MULTIPLIER_X3', label: 'Multi x3'),
        _SlotConfig(stage: 'MULTIPLIER_X5', label: 'Multi x5'),
        _SlotConfig(stage: 'MULTIPLIER_X10', label: 'Multi x10'),
        _SlotConfig(stage: 'MULTIPLIER_X25', label: 'Multi x25'),
        _SlotConfig(stage: 'MULTIPLIER_X50', label: 'Multi x50'),
        _SlotConfig(stage: 'MULTIPLIER_X100', label: 'Multi x100'),
        _SlotConfig(stage: 'MULTIPLIER_MAX', label: 'Multi Max'),
      ],
    ),
    // ─── PROGRESSIVE MULTIPLIERS ───
    _GroupConfig(
      id: 'progressive',
      title: 'Progressive',
      icon: '📈',
      slots: [
        _SlotConfig(stage: 'MULTIPLIER_RESET', label: 'Multi Reset'),
        _SlotConfig(stage: 'PROGRESSIVE_MULTIPLIER', label: 'Prog Multi'),
        _SlotConfig(stage: 'GLOBAL_MULTIPLIER', label: 'Global Multi'),
        _SlotConfig(stage: 'MULTIPLIER_TRAIL', label: 'Trail Multi'),
        _SlotConfig(stage: 'MULTIPLIER_STACK', label: 'Stack Multi'),
      ],
    ),
    // ─── RANDOM / SPECIAL MULTIPLIERS ───
    _GroupConfig(
      id: 'random',
      title: 'Random / Special',
      icon: '🎲',
      slots: [
        _SlotConfig(stage: 'RANDOM_MULTIPLIER', label: 'Random Multi'),
        _SlotConfig(stage: 'MULTIPLIER_WILD', label: 'Wild Multi'),
        _SlotConfig(stage: 'MULTIPLIER_REEL', label: 'Reel Multi'),
        _SlotConfig(stage: 'MULTIPLIER_SYMBOL', label: 'Symbol Multi'),
        _SlotConfig(stage: 'MULTIPLIER_LAND', label: 'Multi Land'),
      ],
    ),
    // ─── MODIFIER FEATURES ───
    _GroupConfig(
      id: 'modifiers',
      title: 'Modifier Features',
      icon: '⚡',
      slots: [
        _SlotConfig(stage: 'MODIFIER_TRIGGER', label: 'Modifier Trigger'),
        _SlotConfig(stage: 'RANDOM_FEATURE', label: 'Random Feature'),
        _SlotConfig(stage: 'RANDOM_WILD', label: 'Random Wild'),
        _SlotConfig(stage: 'RANDOM_NUDGE', label: 'Random Nudge'),
        _SlotConfig(stage: 'RANDOM_RESPIN', label: 'Random Respin'),
        _SlotConfig(stage: 'RANDOM_UPGRADE', label: 'Random Upgrade'),
        _SlotConfig(stage: 'LIGHTNING_STRIKE', label: 'Lightning Strike'),
        _SlotConfig(stage: 'MAGIC_TOUCH', label: 'Magic Touch'),
      ],
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 6: FREE SPINS [FEATURE] — 28 slots
// Trigger → Loop → Retrigger → Summary
// ═══════════════════════════════════════════════════════════════════════════════

class _FreeSpinsSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _FreeSpinsSection({required this.widget});

  @override String get id => 'free_spins';
  @override String get title => 'FREE SPINS';
  @override String get icon => '🎁';
  @override Color get color => const Color(0xFF40FF90);

  @override
  List<_GroupConfig> get groups => const [
    // ─── HOLD (Base → FS Transition) ───
    _GroupConfig(
      id: 'hold',
      title: 'Hold',
      icon: '🎯',
      slots: [
        _SlotConfig(stage: 'FS_HOLD_INTRO', label: 'Hold Intro'),
        _SlotConfig(stage: 'FS_HOLD_OUTRO', label: 'Hold Outro'),
      ],
    ),
    // ─── GAMEPLAY ───
    _GroupConfig(
      id: 'gameplay',
      title: 'Gameplay',
      icon: '🔄',
      slots: [
        _SlotConfig(stage: 'FS_START', label: 'FS Start'),
        _SlotConfig(stage: 'FS_SPIN_START', label: 'Spin Start'),
        _SlotConfig(stage: 'FS_SPIN_END', label: 'Spin End'),
        _SlotConfig(stage: 'FS_WIN', label: 'FS Win'),
        _SlotConfig(stage: 'FS_STICKY_WILD', label: 'Sticky Wild'),
        _SlotConfig(stage: 'FS_EXPANDING_WILD', label: 'Expand Wild'),
        _SlotConfig(stage: 'FS_MULTIPLIER_UP', label: 'Multi Up'),
      ],
    ),
    // ─── SCATTER ───
    _GroupConfig(
      id: 'scatter',
      title: 'Scatter Land',
      icon: '⭐',
      slots: [
        _SlotConfig(stage: 'FS_SCATTER_LAND', label: 'Scatter Land'),
        _SlotConfig(stage: 'FS_SCATTER_LAND_R1', label: 'Reel 1'),
        _SlotConfig(stage: 'FS_SCATTER_LAND_R2', label: 'Reel 2'),
        _SlotConfig(stage: 'FS_SCATTER_LAND_R3', label: 'Reel 3'),
        _SlotConfig(stage: 'FS_SCATTER_LAND_R4', label: 'Reel 4'),
        _SlotConfig(stage: 'FS_SCATTER_LAND_R5', label: 'Reel 5'),
      ],
    ),
    // ─── RETRIGGER ───
    _GroupConfig(
      id: 'retrigger',
      title: 'Retrigger',
      icon: '➕',
      slots: [
        _SlotConfig(stage: 'FS_RETRIGGER', label: 'Retrigger'),
        _SlotConfig(stage: 'FS_RETRIGGER_3', label: '+3'),
        _SlotConfig(stage: 'FS_RETRIGGER_5', label: '+5'),
        _SlotConfig(stage: 'FS_RETRIGGER_10', label: '+10'),
      ],
    ),
    // ─── END ───
    _GroupConfig(
      id: 'end',
      title: 'End',
      icon: '🏁',
      slots: [
        _SlotConfig(stage: 'FS_END', label: 'FS End'),
        _SlotConfig(stage: 'FS_OUTRO_PLAQUE', label: 'FS Outro Plaque'),
      ],
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 7: BONUS GAMES [FEATURE] — 62 slots
// Pick, Wheel, Trail, Generic bonus mechanics
// ═══════════════════════════════════════════════════════════════════════════════

class _BonusGamesSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _BonusGamesSection({required this.widget});

  @override String get id => 'bonus_games';
  @override String get title => 'BONUS GAMES';
  @override String get icon => '🎲';
  @override Color get color => const Color(0xFF9370DB);

  @override
  List<_GroupConfig> get groups => const [
    // ─── GENERIC BONUS ───
    _GroupConfig(
      id: 'generic',
      title: 'Generic Bonus',
      icon: '⭐',
      slots: [
        _SlotConfig(stage: 'BONUS_TRIGGER', label: 'Bonus Trigger'),
        _SlotConfig(stage: 'BONUS_ENTER', label: 'Bonus Enter'),
        _SlotConfig(stage: 'BONUS_STEP', label: 'Bonus Step'),
        _SlotConfig(stage: 'BONUS_EXIT', label: 'Bonus Exit'),
        _SlotConfig(stage: 'BONUS_MUSIC', label: 'Bonus Music'),
        _SlotConfig(stage: 'BONUS_SUMMARY', label: 'Bonus Summary'),
        _SlotConfig(stage: 'BONUS_TOTAL', label: 'Bonus Total'),
        _SlotConfig(stage: 'VO_BONUS', label: 'VO Bonus'),
      ],
    ),
    // ─── PICK GAME ───
    _GroupConfig(
      id: 'pick',
      title: 'Pick Game',
      icon: '👆',
      slots: [
        _SlotConfig(stage: 'PICK_REVEAL', label: 'Pick Reveal'),
        _SlotConfig(stage: 'PICK_GOOD', label: 'Pick Good'),
        _SlotConfig(stage: 'PICK_BAD', label: 'Pick Bad'),
        _SlotConfig(stage: 'PICK_BONUS', label: 'Pick Bonus'),
        _SlotConfig(stage: 'PICK_MULTIPLIER', label: 'Pick Multi'),
        _SlotConfig(stage: 'PICK_UPGRADE', label: 'Pick Upgrade'),
        _SlotConfig(stage: 'PICK_COLLECT', label: 'Pick Collect'),
        _SlotConfig(stage: 'PICK_HOVER', label: 'Pick Hover'),
        _SlotConfig(stage: 'PICK_CHEST_OPEN', label: 'Chest Open'),
        _SlotConfig(stage: 'PICK_ALL_REVEALED', label: 'All Revealed'),
        _SlotConfig(stage: 'PICK_MEGA_PRIZE', label: 'Mega Prize'),
      ],
    ),
    // ─── WHEEL BONUS ⚡ (pooled ticks) ───
    _GroupConfig(
      id: 'wheel',
      title: 'Wheel Bonus ⚡',
      icon: '🎡',
      slots: [
        _SlotConfig(stage: 'WHEEL_START', label: 'Wheel Start'),
        _SlotConfig(stage: 'WHEEL_SPIN', label: 'Wheel Spin'),
        _SlotConfig(stage: 'WHEEL_TICK', label: 'Wheel Tick'),
        _SlotConfig(stage: 'WHEEL_POINTER_TICK', label: 'Pointer Tick'),
        _SlotConfig(stage: 'WHEEL_SLOW', label: 'Wheel Slow'),
        _SlotConfig(stage: 'WHEEL_ACCELERATION', label: 'Wheel Accel'),
        _SlotConfig(stage: 'WHEEL_LAND', label: 'Wheel Land'),
        _SlotConfig(stage: 'WHEEL_ANTICIPATION', label: 'Wheel Antic'),
        _SlotConfig(stage: 'WHEEL_NEAR_MISS', label: 'Wheel Near Miss'),
        _SlotConfig(stage: 'WHEEL_CELEBRATION', label: 'Wheel Celeb'),
        _SlotConfig(stage: 'WHEEL_PRIZE', label: 'Wheel Prize'),
        _SlotConfig(stage: 'WHEEL_BONUS', label: 'Wheel Bonus'),
        _SlotConfig(stage: 'WHEEL_MULTIPLIER', label: 'Wheel Multi'),
        _SlotConfig(stage: 'WHEEL_JACKPOT_LAND', label: 'Wheel JP Land'),
      ],
    ),
    // ─── TRAIL / BOARD ───
    _GroupConfig(
      id: 'trail',
      title: 'Trail / Board',
      icon: '🎲',
      slots: [
        _SlotConfig(stage: 'TRAIL_MOVE', label: 'Trail Move'),
        _SlotConfig(stage: 'TRAIL_LAND', label: 'Trail Land'),
        _SlotConfig(stage: 'TRAIL_PRIZE', label: 'Trail Prize'),
        _SlotConfig(stage: 'TRAIL_BONUS', label: 'Trail Bonus'),
        _SlotConfig(stage: 'DICE_ROLL', label: 'Dice Roll'),
        _SlotConfig(stage: 'DICE_LAND', label: 'Dice Land'),
        _SlotConfig(stage: 'BOARD_ADVANCE', label: 'Board Advance'),
        _SlotConfig(stage: 'BOARD_LADDER', label: 'Board Ladder'),
        _SlotConfig(stage: 'BOARD_SNAKE', label: 'Board Snake'),
      ],
    ),
    // ─── LEVELS / BOSS ───
    _GroupConfig(
      id: 'levels',
      title: 'Levels / Boss',
      icon: '👾',
      slots: [
        _SlotConfig(stage: 'LEVEL_COMPLETE', label: 'Level Complete'),
        _SlotConfig(stage: 'LEVEL_ADVANCE', label: 'Level Advance'),
        _SlotConfig(stage: 'LEVEL_BOSS', label: 'Level Boss'),
        _SlotConfig(stage: 'BOSS_HIT', label: 'Boss Hit'),
        _SlotConfig(stage: 'BOSS_DEFEAT', label: 'Boss Defeat'),
      ],
    ),
    // ─── METERS / COLLECTION ───
    _GroupConfig(
      id: 'meters',
      title: 'Meters / Collection',
      icon: '📊',
      slots: [
        _SlotConfig(stage: 'METER_INCREMENT', label: 'Meter +'),
        _SlotConfig(stage: 'METER_FILL', label: 'Meter Full'),
        _SlotConfig(stage: 'COLLECTION_ADD', label: 'Collection Add'),
        _SlotConfig(stage: 'COLLECTION_COMPLETE', label: 'Collection Done'),
        _SlotConfig(stage: 'REWARD_AWARD', label: 'Reward Award'),
        _SlotConfig(stage: 'FEATURE_METER_INCREMENT', label: 'Feature Meter +'),
        _SlotConfig(stage: 'FEATURE_METER_FULL', label: 'Feature Meter Full'),
      ],
    ),
    // ─── BUY FEATURE ───
    _GroupConfig(
      id: 'buy',
      title: 'Buy Feature',
      icon: '💳',
      slots: [
        _SlotConfig(stage: 'BUY_FEATURE_CONFIRM', label: 'Buy Confirm'),
        _SlotConfig(stage: 'BUY_FEATURE_ANIMATION', label: 'Buy Animation'),
        _SlotConfig(stage: 'BUY_FEATURE_CANCEL', label: 'Buy Cancel'),
        _SlotConfig(stage: 'ANTE_BET_ACTIVATE', label: 'Ante Bet On'),
        _SlotConfig(stage: 'ANTE_BET_DEACTIVATE', label: 'Ante Bet Off'),
        _SlotConfig(stage: 'SUPER_BET_ACTIVATE', label: 'Super Bet On'),
        _SlotConfig(stage: 'SUPER_BET_DEACTIVATE', label: 'Super Bet Off'),
        _SlotConfig(stage: 'TURBO_MODE_ACTIVATE', label: 'Turbo Activate'),
        _SlotConfig(stage: 'TURBO_MODE_DEACTIVATE', label: 'Turbo Deactivate'),
      ],
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 8: HOLD & WIN (Feature Tier)
// Hold & Win / Respins mechanics — 32 slots
// ═══════════════════════════════════════════════════════════════════════════════

class _HoldAndWinSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _HoldAndWinSection({required this.widget});

  @override String get id => 'hold_win';
  @override String get title => 'HOLD & WIN';
  @override String get icon => '🔒';
  @override Color get color => const Color(0xFFFF6B35);  // Orange

  @override
  List<_GroupConfig> get groups => const [
    // ─── TRIGGER ───
    _GroupConfig(
      id: 'trigger',
      title: 'Trigger',
      icon: '🎯',
      slots: [
        _SlotConfig(stage: 'HOLD_TRIGGER', label: 'Hold Trigger'),
        _SlotConfig(stage: 'HOLD_START', label: 'Hold Start'),
        _SlotConfig(stage: 'HOLD_INTRO', label: 'Hold Intro'),
        _SlotConfig(stage: 'HOLD_MUSIC', label: 'Hold Music'),
      ],
    ),
    // ─── RESPINS ───
    _GroupConfig(
      id: 'respins',
      title: 'Respins',
      icon: '🔄',
      slots: [
        _SlotConfig(stage: 'RESPIN_START', label: 'Respin Start'),
        _SlotConfig(stage: 'RESPIN_SPIN', label: 'Respin Spin'),
        _SlotConfig(stage: 'RESPIN_STOP', label: 'Respin Stop'),
        _SlotConfig(stage: 'RESPIN_RESET', label: 'Respin Reset'),
        _SlotConfig(stage: 'RESPIN_COUNT_3', label: 'Respins = 3'),
        _SlotConfig(stage: 'RESPIN_COUNT_2', label: 'Respins = 2'),
        _SlotConfig(stage: 'RESPIN_COUNT_1', label: 'Respins = 1'),
        _SlotConfig(stage: 'RESPIN_LAST', label: 'Last Respin'),
        _SlotConfig(stage: 'BLANK_RESPIN', label: 'Blank Respin'),
      ],
    ),
    // ─── COIN MECHANICS ───
    _GroupConfig(
      id: 'coins',
      title: 'Coin Mechanics',
      icon: '🪙',
      slots: [
        _SlotConfig(stage: 'COIN_LOCK', label: 'Coin Lock'),
        _SlotConfig(stage: 'COIN_UPGRADE', label: 'Coin Upgrade'),
        _SlotConfig(stage: 'COIN_COLLECT_ALL', label: 'Collect All'),
        _SlotConfig(stage: 'STICKY_ADD', label: 'Sticky Add'),
        _SlotConfig(stage: 'STICKY_REMOVE', label: 'Sticky Remove'),
        // NOTE: MULTIPLIER_LAND → Use Section 5 (Multipliers)
        _SlotConfig(stage: 'SPECIAL_SYMBOL_LAND', label: 'Special Land'),
      ],
    ),
    // ─── GRID FILL ───
    _GroupConfig(
      id: 'grid',
      title: 'Grid Fill',
      icon: '📐',
      slots: [
        _SlotConfig(stage: 'GRID_FILL', label: 'Grid Fill'),
        _SlotConfig(stage: 'GRID_COMPLETE', label: 'Grid Complete'),
        _SlotConfig(stage: 'COLUMN_FILL', label: 'Column Fill'),
        _SlotConfig(stage: 'ROW_FILL', label: 'Row Fill'),
        _SlotConfig(stage: 'POSITION_FILL', label: 'Position Fill'),
        _SlotConfig(stage: 'FULL_SCREEN_TRIGGER', label: 'Full Screen'),
        _SlotConfig(stage: 'PROGRESSIVE_FILL', label: 'Prog Fill'),
      ],
    ),
    // ─── SUMMARY ───
    _GroupConfig(
      id: 'summary',
      title: 'Summary',
      icon: '🏁',
      slots: [
        _SlotConfig(stage: 'HOLD_END', label: 'Hold End'),
        _SlotConfig(stage: 'HOLD_WIN_TOTAL', label: 'Total Win'),
        _SlotConfig(stage: 'PRIZE_REVEAL', label: 'Prize Reveal'),
        _SlotConfig(stage: 'PRIZE_UPGRADE', label: 'Prize Upgrade'),
        _SlotConfig(stage: 'GRAND_TRIGGER', label: 'Grand Trigger'),
      ],
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 9: JACKPOTS (Premium Tier 🏆)
// Isolated for regulatory validation — 38 slots
// ═══════════════════════════════════════════════════════════════════════════════

class _JackpotsSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _JackpotsSection({required this.widget});

  @override String get id => 'jackpots';
  @override String get title => '🏆 JACKPOTS';
  @override String get icon => '💎';
  @override Color get color => const Color(0xFFFFD700);  // Gold

  @override
  List<_GroupConfig> get groups => const [
    // ─── TRIGGER ───
    _GroupConfig(
      id: 'trigger',
      title: 'Trigger',
      icon: '🎯',
      slots: [
        _SlotConfig(stage: 'JACKPOT_TRIGGER', label: 'JP Trigger'),
        _SlotConfig(stage: 'JACKPOT_ELIGIBLE', label: 'JP Eligible'),
        _SlotConfig(stage: 'JACKPOT_PROGRESS', label: 'JP Progress'),
      ],
    ),
    // ─── BUILDUP ───
    _GroupConfig(
      id: 'buildup',
      title: 'Buildup',
      icon: '📈',
      slots: [
        _SlotConfig(stage: 'JACKPOT_BUILDUP', label: 'JP Buildup'),
        _SlotConfig(stage: 'JACKPOT_ANIMATION_START', label: 'JP Anim Start'),
        _SlotConfig(stage: 'JACKPOT_METER_FILL', label: 'JP Meter Fill'),
      ],
    ),
    // ─── REVEAL ───
    _GroupConfig(
      id: 'reveal',
      title: 'Reveal',
      icon: '✨',
      slots: [
        _SlotConfig(stage: 'JACKPOT_REVEAL', label: 'JP Reveal'),
        _SlotConfig(stage: 'JACKPOT_WHEEL_SPIN', label: 'JP Wheel Spin'),
        _SlotConfig(stage: 'JACKPOT_WHEEL_TICK', label: 'JP Wheel Tick'),
        _SlotConfig(stage: 'JACKPOT_WHEEL_LAND', label: 'JP Wheel Land'),
      ],
    ),
    // ─── TIERS ───
    _GroupConfig(
      id: 'tiers',
      title: 'Tiers',
      icon: '🏆',
      slots: [
        _SlotConfig(stage: 'JACKPOT_MINI', label: 'JP Mini'),
        _SlotConfig(stage: 'JACKPOT_MINOR', label: 'JP Minor'),
        _SlotConfig(stage: 'JACKPOT_MAJOR', label: 'JP Major'),
        _SlotConfig(stage: 'JACKPOT_GRAND', label: 'JP Grand'),
        _SlotConfig(stage: 'JACKPOT_MEGA', label: 'JP Mega'),
        _SlotConfig(stage: 'JACKPOT_ULTRA', label: 'JP Ultra'),
      ],
    ),
    // ─── PRESENT ───
    _GroupConfig(
      id: 'present',
      title: 'Present',
      icon: '🎉',
      slots: [
        _SlotConfig(stage: 'JACKPOT_PRESENT', label: 'JP Present'),
        _SlotConfig(stage: 'JACKPOT_AWARD', label: 'JP Award'),
        _SlotConfig(stage: 'JACKPOT_ROLLUP', label: 'JP Rollup'),
        _SlotConfig(stage: 'JACKPOT_BELLS', label: 'JP Bells'),
        _SlotConfig(stage: 'JACKPOT_SIRENS', label: 'JP Sirens'),
      ],
    ),
    // ─── CELEBRATION ───
    _GroupConfig(
      id: 'celebration',
      title: 'Celebration',
      icon: '🎊',
      slots: [
        _SlotConfig(stage: 'JACKPOT_CELEBRATION', label: 'JP Celebration'),
        _SlotConfig(stage: 'JACKPOT_MACHINE_WIN', label: 'JP Machine Win'),
        _SlotConfig(stage: 'JACKPOT_COLLECT', label: 'JP Collect'),
        _SlotConfig(stage: 'JACKPOT_END', label: 'JP End'),
      ],
    ),
    // ─── PROGRESSIVE ───
    _GroupConfig(
      id: 'progressive',
      title: 'Progressive',
      icon: '📊',
      slots: [
        _SlotConfig(stage: 'PROGRESSIVE_INCREMENT', label: 'Prog Increment'),
        _SlotConfig(stage: 'PROGRESSIVE_FLASH', label: 'Prog Flash'),
        _SlotConfig(stage: 'PROGRESSIVE_HIT', label: 'Prog Hit'),
        _SlotConfig(stage: 'JACKPOT_TICKER_INCREMENT', label: 'JP Ticker Inc'),
      ],
    ),
    // ─── SPECIAL ───
    _GroupConfig(
      id: 'special',
      title: 'Special',
      icon: '⚡',
      slots: [
        _SlotConfig(stage: 'MUST_HIT_BY_WARNING', label: 'Must Hit Warning'),
        _SlotConfig(stage: 'MUST_HIT_BY_IMMINENT', label: 'Must Hit Imminent'),
        _SlotConfig(stage: 'HOT_DROP_WARNING', label: 'Hot Drop Warn'),
        _SlotConfig(stage: 'HOT_DROP_HIT', label: 'Hot Drop Hit'),
        _SlotConfig(stage: 'HOT_DROP_NEAR', label: 'Hot Drop Near'),
        _SlotConfig(stage: 'LINK_WIN', label: 'Link Win'),
        _SlotConfig(stage: 'NETWORK_JACKPOT', label: 'Network JP'),
        _SlotConfig(stage: 'LOCAL_JACKPOT', label: 'Local JP'),
      ],
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 10: GAMBLE (Optional Tier)
// Risk/reward feature — 15 slots
// ═══════════════════════════════════════════════════════════════════════════════

class _GambleSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _GambleSection({required this.widget});

  @override String get id => 'gamble';
  @override String get title => 'GAMBLE';
  @override String get icon => '🃏';
  @override Color get color => const Color(0xFFE040FB);  // Purple

  @override
  List<_GroupConfig> get groups => const [
    // ─── ENTRY ───
    _GroupConfig(
      id: 'entry',
      title: 'Entry',
      icon: '🚪',
      slots: [
        _SlotConfig(stage: 'GAMBLE_ENTER', label: 'Gamble Enter'),
        _SlotConfig(stage: 'GAMBLE_OFFER', label: 'Gamble Offer'),
      ],
    ),
    // ─── FLIP ───
    _GroupConfig(
      id: 'flip',
      title: 'Flip',
      icon: '🔄',
      slots: [
        _SlotConfig(stage: 'GAMBLE_CARD_FLIP', label: 'Card Flip'),
        _SlotConfig(stage: 'GAMBLE_COLOR_PICK', label: 'Color Pick'),
        _SlotConfig(stage: 'GAMBLE_SUIT_PICK', label: 'Suit Pick'),
        _SlotConfig(stage: 'GAMBLE_LADDER_STEP', label: 'Ladder Step'),
      ],
    ),
    // ─── RESULT ───
    _GroupConfig(
      id: 'result',
      title: 'Result',
      icon: '🎯',
      slots: [
        _SlotConfig(stage: 'GAMBLE_WIN', label: 'Gamble Win'),
        _SlotConfig(stage: 'GAMBLE_LOSE', label: 'Gamble Lose'),
        _SlotConfig(stage: 'GAMBLE_DOUBLE', label: 'Gamble Double'),
        _SlotConfig(stage: 'GAMBLE_HALF', label: 'Gamble Half'),
        _SlotConfig(stage: 'GAMBLE_LADDER_FALL', label: 'Ladder Fall'),
      ],
    ),
    // ─── EXIT ───
    _GroupConfig(
      id: 'exit',
      title: 'Exit',
      icon: '🏁',
      slots: [
        _SlotConfig(stage: 'GAMBLE_COLLECT', label: 'Gamble Collect'),
        _SlotConfig(stage: 'GAMBLE_EXIT', label: 'Gamble Exit'),
        _SlotConfig(stage: 'GAMBLE_LIMIT', label: 'Gamble Limit'),
        _SlotConfig(stage: 'GAMBLE_TIMEOUT', label: 'Gamble Timeout'),
      ],
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 11: MUSIC (Background)
// Background layer — ambient and dynamic music system
// Tier: Background | Priority: Low (always playing, ducked by everything)
// ═══════════════════════════════════════════════════════════════════════════════

class _MusicSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _MusicSection({required this.widget});

  @override String get id => 'music';
  @override String get title => 'MUSIC';
  @override String get icon => '🎵';
  @override Color get color => const Color(0xFF40C8FF);

  @override
  List<_GroupConfig> get groups {
    // Generate music groups from contexts
    final contextGroups = widget.contexts.map((ctx) => _GroupConfig(
      id: ctx.id,
      title: ctx.displayName,
      icon: ctx.icon,
      slots: List.generate(ctx.layerCount, (i) => _SlotConfig(
        stage: 'MUSIC_${ctx.stagePrefix}_L${i + 1}',
        label: 'Layer ${i + 1}',
      )),
    )).toList();

    // Add default music stages if no contexts
    if (contextGroups.isEmpty) {
      return const [
        // ═══════════════════════════════════════════════════════════════════
        // BASE GAME MUSIC — Full arrangement architecture
        // Layer = complete arrangement (gradatively stronger)
        // Extension = additional layer mixed ON TOP of active layer
        // ═══════════════════════════════════════════════════════════════════
        _GroupConfig(
          id: 'base',
          title: 'Base Game',
          icon: '🎹',
          slots: [
            _SlotConfig(stage: 'MUSIC_BASE_INTRO', label: 'Intro'),
            _SlotConfig(stage: 'MUSIC_BASE_OUTRO', label: 'Outro'),
            _SlotConfig(stage: 'MUSIC_BASE_L1', label: 'Layer 1'),
            _SlotConfig(stage: 'MUSIC_BASE_L2', label: 'Layer 2'),
            _SlotConfig(stage: 'MUSIC_BASE_L3', label: 'Layer 3'),
            _SlotConfig(stage: 'MUSIC_BASE_L4', label: 'Layer 4'),
            _SlotConfig(stage: 'MUSIC_BASE_L5', label: 'Layer 5'),
          ],
        ),
        _GroupConfig(
          id: 'freespins',
          title: 'Free Spins',
          icon: '🌀',
          slots: [
            _SlotConfig(stage: 'MUSIC_FS_INTRO', label: 'Intro'),
            _SlotConfig(stage: 'MUSIC_FS_OUTRO', label: 'Outro'),
            _SlotConfig(stage: 'MUSIC_FS_L1', label: 'Layer 1'),
            _SlotConfig(stage: 'MUSIC_FS_L2', label: 'Layer 2'),
            _SlotConfig(stage: 'MUSIC_FS_L3', label: 'Layer 3'),
            _SlotConfig(stage: 'MUSIC_FS_L4', label: 'Layer 4'),
            _SlotConfig(stage: 'MUSIC_FS_L5', label: 'Layer 5'),
          ],
        ),
        _GroupConfig(
          id: 'bonus',
          title: 'Bonus',
          icon: '🎁',
          slots: [
            _SlotConfig(stage: 'MUSIC_BONUS_INTRO', label: 'Intro'),
            _SlotConfig(stage: 'MUSIC_BONUS_OUTRO', label: 'Outro'),
            _SlotConfig(stage: 'MUSIC_BONUS_L1', label: 'Layer 1'),
            _SlotConfig(stage: 'MUSIC_BONUS_L2', label: 'Layer 2'),
            _SlotConfig(stage: 'MUSIC_BONUS_L3', label: 'Layer 3'),
            _SlotConfig(stage: 'MUSIC_BONUS_L4', label: 'Layer 4'),
            _SlotConfig(stage: 'MUSIC_BONUS_L5', label: 'Layer 5'),
          ],
        ),
        _GroupConfig(
          id: 'hold',
          title: 'Hold & Spin',
          icon: '🔒',
          slots: [
            _SlotConfig(stage: 'MUSIC_HOLD_INTRO', label: 'Intro'),
            _SlotConfig(stage: 'MUSIC_HOLD_OUTRO', label: 'Outro'),
            _SlotConfig(stage: 'MUSIC_HOLD_L1', label: 'Layer 1'),
            _SlotConfig(stage: 'MUSIC_HOLD_L2', label: 'Layer 2'),
            _SlotConfig(stage: 'MUSIC_HOLD_L3', label: 'Layer 3'),
            _SlotConfig(stage: 'MUSIC_HOLD_L4', label: 'Layer 4'),
            _SlotConfig(stage: 'MUSIC_HOLD_L5', label: 'Layer 5'),
          ],
        ),
        // BIG_WIN_START/END are in WIN PRESENTATION section
        _GroupConfig(
          id: 'jackpot',
          title: 'Jackpot',
          icon: '💎',
          slots: [
            _SlotConfig(stage: 'MUSIC_JACKPOT_INTRO', label: 'Intro'),
            _SlotConfig(stage: 'MUSIC_JACKPOT_OUTRO', label: 'Outro'),
            _SlotConfig(stage: 'MUSIC_JACKPOT_L1', label: 'Layer 1'),
            _SlotConfig(stage: 'MUSIC_JACKPOT_L2', label: 'Layer 2'),
            _SlotConfig(stage: 'MUSIC_JACKPOT_L3', label: 'Layer 3'),
            _SlotConfig(stage: 'MUSIC_JACKPOT_L4', label: 'Layer 4'),
            _SlotConfig(stage: 'MUSIC_JACKPOT_L5', label: 'Layer 5'),
          ],
        ),
        _GroupConfig(
          id: 'gamble',
          title: 'Gamble',
          icon: '🎲',
          slots: [
            _SlotConfig(stage: 'MUSIC_GAMBLE_INTRO', label: 'Intro'),
            _SlotConfig(stage: 'MUSIC_GAMBLE_OUTRO', label: 'Outro'),
            _SlotConfig(stage: 'MUSIC_GAMBLE_L1', label: 'Layer 1'),
            _SlotConfig(stage: 'MUSIC_GAMBLE_L2', label: 'Layer 2'),
            _SlotConfig(stage: 'MUSIC_GAMBLE_L3', label: 'Layer 3'),
            _SlotConfig(stage: 'MUSIC_GAMBLE_L4', label: 'Layer 4'),
            _SlotConfig(stage: 'MUSIC_GAMBLE_L5', label: 'Layer 5'),
          ],
        ),
        _GroupConfig(
          id: 'reveal',
          title: 'Reveal / Pick',
          icon: '🃏',
          slots: [
            _SlotConfig(stage: 'MUSIC_REVEAL_INTRO', label: 'Intro'),
            _SlotConfig(stage: 'MUSIC_REVEAL_OUTRO', label: 'Outro'),
            _SlotConfig(stage: 'MUSIC_REVEAL_L1', label: 'Layer 1'),
            _SlotConfig(stage: 'MUSIC_REVEAL_L2', label: 'Layer 2'),
            _SlotConfig(stage: 'MUSIC_REVEAL_L3', label: 'Layer 3'),
            _SlotConfig(stage: 'MUSIC_REVEAL_L4', label: 'Layer 4'),
            _SlotConfig(stage: 'MUSIC_REVEAL_L5', label: 'Layer 5'),
          ],
        ),
        // ═══════════════════════════════════════════════════════════════════
        // TENSION MUSIC — Dynamic tension escalation
        // ═══════════════════════════════════════════════════════════════════
        _GroupConfig(
          id: 'tension',
          title: 'Tension',
          icon: '⚡',
          slots: [
            _SlotConfig(stage: 'MUSIC_TENSION_LOW', label: 'Tension Low'),
            _SlotConfig(stage: 'MUSIC_TENSION_MED', label: 'Tension Med'),
            _SlotConfig(stage: 'MUSIC_TENSION_HIGH', label: 'Tension High'),
            _SlotConfig(stage: 'MUSIC_TENSION_MAX', label: 'Tension Max'),
            _SlotConfig(stage: 'MUSIC_BUILDUP', label: 'Buildup'),
            _SlotConfig(stage: 'MUSIC_CLIMAX', label: 'Climax'),
            _SlotConfig(stage: 'MUSIC_RESOLVE', label: 'Resolve'),
            _SlotConfig(stage: 'MUSIC_WIND_DOWN', label: 'Wind Down'),
          ],
        ),
        // ═══════════════════════════════════════════════════════════════════
        // MUSIC STINGERS (Industry Standard - Short musical hits)
        // ═══════════════════════════════════════════════════════════════════
        _GroupConfig(
          id: 'stingers',
          title: 'Music Stingers',
          icon: '⚡',
          slots: [
            _SlotConfig(stage: 'MUSIC_STINGER_WIN', label: 'Stinger Win'),
            _SlotConfig(stage: 'MUSIC_STINGER_FEATURE', label: 'Stinger Feature'),
            _SlotConfig(stage: 'MUSIC_STINGER_JACKPOT', label: 'Stinger JP'),
            _SlotConfig(stage: 'MUSIC_STINGER_BONUS', label: 'Stinger Bonus'),
            _SlotConfig(stage: 'MUSIC_STINGER_ALERT', label: 'Stinger Alert'),
            _SlotConfig(stage: 'MUSIC_CROSSFADE', label: 'Crossfade'),
            _SlotConfig(stage: 'MUSIC_DUCK_START', label: 'Duck Start'),
            _SlotConfig(stage: 'MUSIC_DUCK_END', label: 'Duck End'),
            _SlotConfig(stage: 'MUSIC_TRANSITION', label: 'Transition'),
            _SlotConfig(stage: 'MUSIC_STING_UP', label: 'Sting Up'),
            _SlotConfig(stage: 'MUSIC_STING_DOWN', label: 'Sting Down'),
          ],
        ),
        // ═══════════════════════════════════════════════════════════════════
        // AMBIENT — One per scene (background atmosphere per feature)
        // ═══════════════════════════════════════════════════════════════════
        _GroupConfig(
          id: 'ambient',
          title: 'Ambient',
          icon: '🌙',
          slots: [
            _SlotConfig(stage: 'AMBIENT_BASE', label: 'Base Game'),
            _SlotConfig(stage: 'AMBIENT_FS', label: 'Free Spins'),
            _SlotConfig(stage: 'AMBIENT_BONUS', label: 'Bonus'),
            _SlotConfig(stage: 'AMBIENT_HOLD', label: 'Hold & Spin'),
            _SlotConfig(stage: 'AMBIENT_BIGWIN', label: 'Big Win'),
            _SlotConfig(stage: 'AMBIENT_JACKPOT', label: 'Jackpot'),
            _SlotConfig(stage: 'AMBIENT_GAMBLE', label: 'Gamble'),
            _SlotConfig(stage: 'AMBIENT_REVEAL', label: 'Reveal'),
          ],
        ),
      ];
    }

    return contextGroups;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 12: UI SYSTEM (Utility)
// Utility tier — system sounds and UI feedback
// Tier: Utility | Priority: Lowest (non-blocking, instant feedback)
// ═══════════════════════════════════════════════════════════════════════════════

class _UISystemSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _UISystemSection({required this.widget});

  @override String get id => 'ui_system';
  @override String get title => 'UI SYSTEM';
  @override String get icon => '🖥️';
  @override Color get color => const Color(0xFF9E9E9E);  // Gray (utility)

  @override
  List<_GroupConfig> get groups => const [
    // ═══════════════════════════════════════════════════════════════════════
    // BUTTONS (Primary UI interactions)
    // ═══════════════════════════════════════════════════════════════════════
    _GroupConfig(
      id: 'buttons',
      title: 'Buttons',
      icon: '🔘',
      slots: [
        _SlotConfig(stage: 'UI_BUTTON_PRESS', label: 'Button Press'),
        _SlotConfig(stage: 'UI_BUTTON_HOVER', label: 'Button Hover'),
        // UI_SPIN_PRESS is in BASE GAME LOOP > Spin Controls
        _SlotConfig(stage: 'UI_SPIN_HOVER', label: 'Spin Hover'),
        _SlotConfig(stage: 'UI_SPIN_RELEASE', label: 'Spin Release'),
        _SlotConfig(stage: 'UI_BET_UP', label: 'Bet Up'),
        _SlotConfig(stage: 'UI_BET_DOWN', label: 'Bet Down'),
        _SlotConfig(stage: 'UI_BET_MAX', label: 'Bet Max'),
        _SlotConfig(stage: 'UI_BET_MIN', label: 'Bet Min'),
      ],
    ),
    // ═══════════════════════════════════════════════════════════════════════
    // NAVIGATION (Menu and panel sounds)
    // ═══════════════════════════════════════════════════════════════════════
    _GroupConfig(
      id: 'navigation',
      title: 'Navigation',
      icon: '📑',
      slots: [
        _SlotConfig(stage: 'UI_MENU_OPEN', label: 'Menu Open'),
        _SlotConfig(stage: 'UI_MENU_CLOSE', label: 'Menu Close'),
        _SlotConfig(stage: 'UI_MENU_HOVER', label: 'Menu Hover'),
        _SlotConfig(stage: 'UI_MENU_SELECT', label: 'Menu Select'),
        _SlotConfig(stage: 'UI_TAB_SWITCH', label: 'Tab Switch'),
        _SlotConfig(stage: 'UI_PAGE_FLIP', label: 'Page Flip'),
        _SlotConfig(stage: 'UI_SCROLL', label: 'Scroll'),
        _SlotConfig(stage: 'UI_PAYTABLE_OPEN', label: 'Paytable Open'),
        _SlotConfig(stage: 'UI_PAYTABLE_CLOSE', label: 'Paytable Close'),
        _SlotConfig(stage: 'UI_RULES_OPEN', label: 'Rules Open'),
        _SlotConfig(stage: 'UI_HELP_OPEN', label: 'Help Open'),
        _SlotConfig(stage: 'UI_INFO_PRESS', label: 'Info Press'),
        _SlotConfig(stage: 'UI_SETTINGS_OPEN', label: 'Settings Open'),
        _SlotConfig(stage: 'UI_SETTINGS_CLOSE', label: 'Settings Close'),
      ],
    ),
    // ═══════════════════════════════════════════════════════════════════════
    // SYSTEM (Notifications and alerts)
    // ═══════════════════════════════════════════════════════════════════════
    _GroupConfig(
      id: 'system',
      title: 'System',
      icon: '⚙️',
      slots: [
        _SlotConfig(stage: 'UI_NOTIFICATION', label: 'Notification'),
        _SlotConfig(stage: 'UI_ALERT', label: 'Alert'),
        _SlotConfig(stage: 'UI_ERROR', label: 'Error'),
        _SlotConfig(stage: 'UI_WARNING', label: 'Warning'),
        _SlotConfig(stage: 'UI_POPUP_OPEN', label: 'Popup Open'),
        _SlotConfig(stage: 'UI_POPUP_CLOSE', label: 'Popup Close'),
        _SlotConfig(stage: 'UI_TOOLTIP_SHOW', label: 'Tooltip Show'),
        _SlotConfig(stage: 'UI_TOOLTIP_HIDE', label: 'Tooltip Hide'),
      ],
    ),
    // ═══════════════════════════════════════════════════════════════════════
    // FEEDBACK (Interaction confirmations)
    // ═══════════════════════════════════════════════════════════════════════
    _GroupConfig(
      id: 'feedback',
      title: 'Feedback',
      icon: '✅',
      slots: [
        _SlotConfig(stage: 'UI_CHECKBOX_ON', label: 'Checkbox On'),
        _SlotConfig(stage: 'UI_CHECKBOX_OFF', label: 'Checkbox Off'),
        _SlotConfig(stage: 'UI_SLIDER_DRAG', label: 'Slider Drag'),
        _SlotConfig(stage: 'UI_SLIDER_RELEASE', label: 'Slider Release'),
        _SlotConfig(stage: 'UI_SOUND_ON', label: 'Sound On'),
        _SlotConfig(stage: 'UI_SOUND_OFF', label: 'Sound Off'),
        _SlotConfig(stage: 'UI_VOLUME_CHANGE', label: 'Volume Change'),
        _SlotConfig(stage: 'UI_FULLSCREEN_ENTER', label: 'Fullscreen Enter'),
        _SlotConfig(stage: 'UI_FULLSCREEN_EXIT', label: 'Fullscreen Exit'),
      ],
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION: NUDGE / RESPIN — conditional on nudgeRespin mechanic
// ═══════════════════════════════════════════════════════════════════════════════

class _NudgeRespinSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _NudgeRespinSection({required this.widget});

  @override String get id => 'nudge_respin';
  @override String get title => 'NUDGE / RESPIN';
  @override String get icon => '🔁';
  @override Color get color => const Color(0xFFFF9800);

  @override
  List<_GroupConfig> get groups => const [
    _GroupConfig(
      id: 'nudge',
      title: 'Nudge',
      icon: '👆',
      slots: [
        _SlotConfig(stage: 'REEL_NUDGE', label: 'Reel Nudge'),
        _SlotConfig(stage: 'NUDGE_UP', label: 'Nudge Up'),
        _SlotConfig(stage: 'NUDGE_DOWN', label: 'Nudge Down'),
        _SlotConfig(stage: 'NUDGE_TRIGGER', label: 'Nudge Trigger'),
        _SlotConfig(stage: 'NUDGE_COMPLETE', label: 'Nudge Complete'),
      ],
    ),
    _GroupConfig(
      id: 'respin',
      title: 'Respin',
      icon: '🔄',
      slots: [
        _SlotConfig(stage: 'RESPIN_TRIGGER', label: 'Respin Trigger'),
        // RESPIN_START/SPIN/STOP are in HOLD & WIN section
        _SlotConfig(stage: 'RESPIN_END', label: 'Respin End'),
        _SlotConfig(stage: 'RESPIN_RETRIGGER', label: 'Respin Retrigger'),
      ],
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION: WILD FEATURES — conditional on expandingWilds / stickyWilds
// ═══════════════════════════════════════════════════════════════════════════════

class _WildFeaturesSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _WildFeaturesSection({required this.widget});

  @override String get id => 'wild_features';
  @override String get title => 'WILD FEATURES';
  @override String get icon => '🃏';
  @override Color get color => const Color(0xFF00E676);

  @override
  List<_GroupConfig> get groups => const [
    _GroupConfig(
      id: 'expanding',
      title: 'Expanding Wilds',
      icon: '📐',
      slots: [
        _SlotConfig(stage: 'WILD_EXPAND', label: 'Wild Expand'),
        _SlotConfig(stage: 'WILD_EXPAND_FILL', label: 'Expand Fill'),
        _SlotConfig(stage: 'WILD_EXPAND_COMPLETE', label: 'Expand Complete'),
        _SlotConfig(stage: 'WILD_COLUMN_FILL', label: 'Column Fill'),
      ],
    ),
    _GroupConfig(
      id: 'sticky',
      title: 'Sticky Wilds',
      icon: '📌',
      slots: [
        _SlotConfig(stage: 'WILD_STICKY', label: 'Wild Sticky'),
        _SlotConfig(stage: 'WILD_STICKY_LAND', label: 'Sticky Land'),
        _SlotConfig(stage: 'WILD_STICKY_HOLD', label: 'Sticky Hold'),
        _SlotConfig(stage: 'WILD_STICKY_RELEASE', label: 'Sticky Release'),
        _SlotConfig(stage: 'WILD_STICKY_UPGRADE', label: 'Sticky Upgrade'),
      ],
    ),
    _GroupConfig(
      id: 'wild_general',
      title: 'General Wild',
      icon: '🌟',
      slots: [
        // WILD_LAND is in SYMBOLS > Wild Variations
        _SlotConfig(stage: 'WILD_WALKING', label: 'Walking Wild'),
        _SlotConfig(stage: 'WILD_RANDOM', label: 'Random Wild'),
        _SlotConfig(stage: 'WILD_STACKED', label: 'Stacked Wild'),
      ],
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION: MEGAWAYS — conditional on megaways mechanic
// ═══════════════════════════════════════════════════════════════════════════════

class _MegawaysSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _MegawaysSection({required this.widget});

  @override String get id => 'megaways';
  @override String get title => 'MEGAWAYS';
  @override String get icon => '🔢';
  @override Color get color => const Color(0xFFE040FB);

  @override
  List<_GroupConfig> get groups => const [
    _GroupConfig(
      id: 'megaways_core',
      title: 'Megaways Core',
      icon: '🔢',
      slots: [
        _SlotConfig(stage: 'MEGAWAYS_REVEAL', label: 'Ways Reveal'),
        _SlotConfig(stage: 'MEGAWAYS_EXPAND', label: 'Ways Expand'),
        _SlotConfig(stage: 'MEGAWAYS_SHIFT', label: 'Ways Shift'),
        _SlotConfig(stage: 'MEGAWAYS_MAX', label: 'Max Ways Hit'),
      ],
    ),
    _GroupConfig(
      id: 'megaways_effects',
      title: 'Megaways Effects',
      icon: '✨',
      slots: [
        _SlotConfig(stage: 'MEGAWAYS_ROW_ADD', label: 'Row Add'),
        _SlotConfig(stage: 'MEGAWAYS_ROW_REMOVE', label: 'Row Remove'),
        _SlotConfig(stage: 'MEGAWAYS_TOP_REEL', label: 'Top Reel Spin'),
        _SlotConfig(stage: 'MEGAWAYS_MYSTERY', label: 'Mystery Transform'),
      ],
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION: TRANSITIONS — conditional via transitions block
// ═══════════════════════════════════════════════════════════════════════════════

class _TransitionsSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _TransitionsSection({required this.widget});

  @override String get id => 'transitions';
  @override String get title => 'TRANSITIONS';
  @override String get icon => '🔀';
  @override Color get color => const Color(0xFF78909C);

  @override
  List<_GroupConfig> get groups => const [
    _GroupConfig(
      id: 'scene_transitions',
      title: 'Scene Transitions',
      icon: '🎬',
      slots: [
        _SlotConfig(stage: 'TRANSITION_TO_BASE', label: 'To Base Game'),
        _SlotConfig(stage: 'TRANSITION_TO_FEATURE', label: 'To Feature'),
        _SlotConfig(stage: 'TRANSITION_TO_BONUS', label: 'To Bonus'),
        _SlotConfig(stage: 'TRANSITION_TO_FREESPINS', label: 'To Free Spins'),
        _SlotConfig(stage: 'TRANSITION_TO_JACKPOT', label: 'To Jackpot'),
        _SlotConfig(stage: 'TRANSITION_TO_GAMBLE', label: 'To Gamble'),
      ],
    ),
    _GroupConfig(
      id: 'effects',
      title: 'Transition Effects',
      icon: '💫',
      slots: [
        _SlotConfig(stage: 'TRANSITION_FADE_IN', label: 'Fade In'),
        _SlotConfig(stage: 'TRANSITION_FADE_OUT', label: 'Fade Out'),
        _SlotConfig(stage: 'TRANSITION_SWOOSH', label: 'Swoosh'),
        _SlotConfig(stage: 'TRANSITION_REVEAL', label: 'Reveal'),
        _SlotConfig(stage: 'TRANSITION_IMPACT', label: 'Impact'),
        _SlotConfig(stage: 'TRANSITION_STINGER', label: 'Stinger'),
      ],
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION: ANTICIPATION — conditional via anticipation block
// ═══════════════════════════════════════════════════════════════════════════════

class _AnticipationSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  final int reelCount;
  final Set<int> activeReels;
  final int levelCount;
  _AnticipationSection({
    required this.widget,
    required this.reelCount,
    required this.activeReels,
    this.levelCount = 4,
  });

  @override String get id => 'anticipation';
  @override String get title => 'ANTICIPATION';
  @override String get icon => '😱';
  @override Color get color => const Color(0xFFFF5252);

  @override
  List<_GroupConfig> get groups {
    // Only generate slots for reels that have anticipation enabled
    final sortedReels = activeReels.toList()..sort();
    if (sortedReels.isEmpty) return [];
    return [
      // ANTICIPATION_TENSION + ANTICIPATION_MISS are in BASE GAME LOOP section
      _GroupConfig(
        id: 'tension_per_reel',
        title: 'Tension Per-Reel',
        icon: '📈',
        slots: [
          for (final r in sortedReels)
            _SlotConfig(stage: 'ANTICIPATION_TENSION_R$r', label: 'Tension Reel ${r + 1}'),
        ],
      ),
      _GroupConfig(
        id: 'tension_levels',
        title: 'Tension Levels',
        icon: '🎚️',
        slots: [
          for (final r in sortedReels)
            for (int l = 1; l <= levelCount; l++)
              _SlotConfig(stage: 'ANTICIPATION_TENSION_R${r}_L$l', label: 'Reel ${r + 1} Level $l'),
        ],
      ),
      // NEAR_MISS is in BASE GAME LOOP section
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION: COLLECTOR — conditional via collector block
// ═══════════════════════════════════════════════════════════════════════════════

class _CollectorSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _CollectorSection({required this.widget});

  @override String get id => 'collector';
  @override String get title => 'COLLECTOR';
  @override String get icon => '💰';
  @override Color get color => const Color(0xFFFFC107);

  @override
  List<_GroupConfig> get groups => const [
    _GroupConfig(
      id: 'collect',
      title: 'Collection',
      icon: '🏦',
      slots: [
        _SlotConfig(stage: 'COLLECT_TRIGGER', label: 'Collect Trigger'),
        _SlotConfig(stage: 'COLLECT_COIN', label: 'Coin Collect'),
        _SlotConfig(stage: 'COLLECT_SYMBOL', label: 'Symbol Collect'),
        _SlotConfig(stage: 'COLLECT_METER_FILL', label: 'Meter Fill'),
        _SlotConfig(stage: 'COLLECT_METER_FULL', label: 'Meter Full'),
        _SlotConfig(stage: 'COLLECT_PAYOUT', label: 'Payout'),
      ],
    ),
    _GroupConfig(
      id: 'collect_effects',
      title: 'Collector Effects',
      icon: '✨',
      slots: [
        _SlotConfig(stage: 'COLLECT_FLY_TO', label: 'Fly-to-Meter'),
        _SlotConfig(stage: 'COLLECT_IMPACT', label: 'Impact'),
        _SlotConfig(stage: 'COLLECT_UPGRADE', label: 'Upgrade'),
        _SlotConfig(stage: 'COLLECT_COMPLETE', label: 'Collection Complete'),
      ],
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// Variant Editor Dialog (SL-LP-P1.4)
// ═══════════════════════════════════════════════════════════════════════════════

class _VariantEditorDialog extends StatefulWidget {
  final String stage;
  final Color accentColor;
  final VoidCallback onVariantsChanged;

  const _VariantEditorDialog({
    required this.stage,
    required this.accentColor,
    required this.onVariantsChanged,
  });

  @override
  State<_VariantEditorDialog> createState() => _VariantEditorDialogState();
}

class _VariantEditorDialogState extends State<_VariantEditorDialog> {
  late VariantSelectionMode _mode;
  late List<AudioVariant> _variants;

  @override
  void initState() {
    super.initState();
    _variants = List.from(VariantManager.instance.getVariants(widget.stage));
    // Default mode is random (VariantManager doesn't expose mode getter yet)
    _mode = VariantSelectionMode.random;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF16161C),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.library_music, color: widget.accentColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Variants: ${widget.stage}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Mode selector
            Row(
              children: [
                const Text(
                  'Selection Mode:',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<VariantSelectionMode>(
                    segments: const [
                      ButtonSegment(
                        value: VariantSelectionMode.random,
                        label: Text('Random', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.shuffle, size: 14),
                      ),
                      ButtonSegment(
                        value: VariantSelectionMode.sequence,
                        label: Text('Sequence', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.format_list_numbered, size: 14),
                      ),
                      ButtonSegment(
                        value: VariantSelectionMode.manual,
                        label: Text('Manual', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.touch_app, size: 14),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (Set<VariantSelectionMode> newSelection) {
                      setState(() => _mode = newSelection.first);
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return widget.accentColor.withOpacity(0.3);
                        }
                        return const Color(0xFF0D0D10);
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return widget.accentColor;
                        }
                        return Colors.white54;
                      }),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Variants list
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: _variants.isEmpty
                  ? const Center(
                      child: Text(
                        'No variants yet. Drop audio files to add.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : ListView.builder(
                      cacheExtent: 300, // Pre-render for smooth scroll
                      itemCount: _variants.length,
                      itemBuilder: (context, index) => _buildVariantItem(index),
                    ),
            ),
            const SizedBox(height: 16),
            // Add variant button (via drag-drop)
            DragTarget<Object>(
              onWillAcceptWithDetails: (details) =>
                  details.data is AudioAsset ||
                  details.data is List<AudioAsset> ||
                  details.data is String,
              onAcceptWithDetails: (details) {
                List<String> paths = [];
                if (details.data is AudioAsset) {
                  paths = [(details.data as AudioAsset).path];
                } else if (details.data is List<AudioAsset>) {
                  paths = (details.data as List<AudioAsset>).map((a) => a.path).toList();
                } else if (details.data is String) {
                  paths = [details.data as String];
                }
                for (final path in paths) {
                  _addVariant(path);
                }
              },
              builder: (context, candidateData, rejectedData) {
                final isHovering = candidateData.isNotEmpty;
                return Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: isHovering
                        ? widget.accentColor.withOpacity(0.2)
                        : const Color(0xFF0D0D10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isHovering
                          ? widget.accentColor
                          : Colors.white.withOpacity(0.1),
                      style: BorderStyle.solid,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Drop audio to add variant',
                    style: TextStyle(
                      fontSize: 12,
                      color: isHovering ? widget.accentColor : Colors.white38,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveVariants,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantItem(int index) {
    final variant = _variants[index];
    final fileName = variant.path.split('/').last;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          // Index
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.accentColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: widget.accentColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // File name
          Expanded(
            child: Text(
              fileName,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Weight slider (for random mode)
          if (_mode == VariantSelectionMode.random) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: Slider(
                value: variant.weight,
                min: 0.1,
                max: 3.0,
                divisions: 29,
                label: '${variant.weight.toStringAsFixed(1)}x',
                activeColor: widget.accentColor,
                onChanged: (value) {
                  setState(() {
                    _variants[index] = AudioVariant(
                      path: variant.path,
                      name: variant.name,
                      weight: value,
                    );
                  });
                },
              ),
            ),
          ],
          // Remove button
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.white38),
            onPressed: () => _removeVariant(index),
          ),
        ],
      ),
    );
  }

  void _addVariant(String path) {
    setState(() {
      _variants.add(AudioVariant(
        path: path,
        name: path.split('/').last,
        weight: 1.0,
      ));
    });
  }

  void _removeVariant(int index) {
    setState(() {
      _variants.removeAt(index);
    });
  }

  void _saveVariants() {
    // Clear existing variants for this stage
    VariantManager.instance.clearStage(widget.stage);

    // Add all variants
    for (final variant in _variants) {
      VariantManager.instance.addVariant(widget.stage, variant);
    }

    // Set mode
    VariantManager.instance.setMode(widget.stage, _mode);

    // Notify parent
    widget.onVariantsChanged();

    // Close dialog
    Navigator.pop(context);
  }
}
