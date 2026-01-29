/// Ultimate Audio Panel V8 — Game Flow Organization
///
/// Complete left panel for SlotLab audio assignment.
/// NO EDIT MODE REQUIRED — just drop audio directly.
///
/// V8 CHANGES (2026-01-25):
/// - 12 SECTIONS organized by GAME FLOW (not by type)
/// - TIER SYSTEM: Primary, Secondary, Feature, Premium, Background, Utility
/// - POOLED MARKERS: ⚡ for rapid-fire events (ROLLUP_TICK, CASCADE_STEP, etc.)
/// - PREMIUM SECTION: 🏆 Jackpots isolated for validation
///
/// SECTIONS (Game Flow Order):
/// 1. Base Game Loop [Primary] — Idle, Spin, Reel Animation, Stops, End
/// 2. Symbols & Lands [Primary] — High/Low Pay, Wild, Scatter, Bonus
/// 3. Win Presentation [Primary] — Eval, Lines, Tiers, Rollup, Celebration
/// 4. Cascading Mechanics [Secondary] — Cascade/Tumble/Avalanche unified
/// 5. Multipliers [Secondary] — Win, Progressive, Random multipliers
/// 6. Free Spins [Feature] — Trigger, Loop, Retrigger, Summary
/// 7. Bonus Games [Feature] — Pick, Wheel, Trail, Generic
/// 8. Hold & Win [Feature] — Trigger, Respin, Grid Fill, Summary
/// 9. Jackpots [Premium 🏆] — Trigger, Buildup, Reveal, Present, Celebration
/// 10. Gamble [Optional] — Entry, Flip, Result, Collect
/// 11. Music & Ambience [Background] — Base, Feature, Stingers, Tension, Ambient
/// 12. UI & System [Utility] — Buttons, Nav, Notifications, System
///
/// Auto-Distribution: Drop a folder on a GROUP, files are automatically
/// matched to their correct stages using fuzzy filename matching.

import 'package:flutter/material.dart';
import '../../models/auto_event_builder_models.dart';
import '../../models/slot_lab_models.dart';
import '../../services/stage_group_service.dart';
import '../../services/audio_playback_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Audio assignment callback with stage and path
typedef OnAudioAssign = void Function(String stage, String audioPath);

/// Callback for batch auto-distribution results
typedef OnBatchDistribute = void Function(List<StageMatch> matched, List<UnmatchedFile> unmatched);

/// Ultimate Audio Panel — all audio drops in one place
class UltimateAudioPanel extends StatefulWidget {
  /// Current audio assignments (stage → audioPath)
  final Map<String, String> audioAssignments;

  /// Called when single audio is dropped on a slot
  final OnAudioAssign? onAudioAssign;

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

  /// Symbol definitions for symbol section
  final List<SymbolDefinition> symbols;

  /// Context definitions for music section
  final List<ContextDefinition> contexts;

  /// Persisted expanded sections (optional - uses local state if null)
  final Set<String>? expandedSections;

  /// Persisted expanded groups (optional - uses local state if null)
  final Set<String>? expandedGroups;

  const UltimateAudioPanel({
    super.key,
    this.audioAssignments = const {},
    this.onAudioAssign,
    this.onAudioClear,
    this.onBatchDistribute,
    this.onClearSection,
    this.onSectionToggle,
    this.onGroupToggle,
    this.symbols = const [],
    this.contexts = const [],
    this.expandedSections,
    this.expandedGroups,
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

  @override
  void initState() {
    super.initState();
    // Initialize local state from external or defaults
    // V8: 12 sections organized by Game Flow
    _localExpandedSections = Set.from(widget.expandedSections ?? {
      'base_game_loop',     // 1. Primary — most used
      'symbols',            // 2. Primary
      'win_presentation',   // 3. Primary
    });
    _localExpandedGroups = Set.from(widget.expandedGroups ?? {
      // 1. Base Game Loop (Primary)
      'base_game_loop_idle', 'base_game_loop_spin_controls', 'base_game_loop_reel_stops',
      'base_game_loop_reel_animation', 'base_game_loop_anticipation',
      // 2. Symbols
      'symbols_special', 'symbols_highpay', 'symbols_mediumpay', 'symbols_lowpay',
      'symbols_wild_expanded', 'symbols_special_expanded',
      // 3. Win Presentation
      'win_presentation_eval', 'win_presentation_lines', 'win_presentation_tiers',
      'win_presentation_rollup', 'win_presentation_celebration', 'win_presentation_voice',
      // 4. Cascading
      'cascading_basic', 'cascading_chain', 'cascading_cluster',
      // 5. Multipliers
      'multipliers_win', 'multipliers_progressive', 'multipliers_random',
      // 6. Free Spins
      'free_spins_trigger', 'free_spins_loop', 'free_spins_summary',
      // 7. Bonus Games
      'bonus_pick', 'bonus_wheel', 'bonus_trail',
      // 8. Hold & Win
      'hold_win_trigger', 'hold_win_respins', 'hold_win_summary',
      // 9. Jackpots
      'jackpots_trigger', 'jackpots_reveal', 'jackpots_tiers',
      // 10. Gamble
      'gamble_entry', 'gamble_flip', 'gamble_result',
      // 11. Music
      'music_base', 'music_attract', 'music_tension', 'music_features',
      'music_stingers', 'music_ambient',
      // 12. UI & System
      'ui_system_menu', 'ui_system_notifications', 'ui_system_errors',
    });
  }

  /// Get effective expanded sections (external or local)
  Set<String> get _expandedSections => widget.expandedSections ?? _localExpandedSections;

  /// Get effective expanded groups (external or local)
  Set<String> get _expandedGroups => widget.expandedGroups ?? _localExpandedGroups;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0D10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // V8: 12 sections organized by Game Flow
                  // PRIMARY (80% workflow)
                  _buildSection(_BaseGameLoopSection(widget: widget)),     // 1. Base Game Loop
                  _buildSection(_SymbolsSection(widget: widget)),          // 2. Symbols & Lands
                  _buildSection(_WinPresentationSection(widget: widget)),  // 3. Win Presentation
                  // SECONDARY (15% workflow)
                  _buildSection(_CascadingSection(widget: widget)),        // 4. Cascading Mechanics
                  _buildSection(_MultipliersSection(widget: widget)),      // 5. Multipliers
                  // FEATURE (feature-specific)
                  _buildSection(_FreeSpinsSection(widget: widget)),        // 6. Free Spins
                  _buildSection(_BonusGamesSection(widget: widget)),       // 7. Bonus Games
                  _buildSection(_HoldAndWinSection(widget: widget)),       // 8. Hold & Win
                  // PREMIUM (regulatory)
                  _buildSection(_JackpotsSection(widget: widget)),         // 9. Jackpots 🏆
                  // OPTIONAL
                  _buildSection(_GambleSection(widget: widget)),           // 10. Gamble
                  // BACKGROUND
                  _buildSection(_MusicSection(widget: widget)),            // 11. Music & Ambience
                  // UTILITY
                  _buildSection(_UISystemSection(widget: widget)),         // 12. UI & System
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final totalAssigned = widget.audioAssignments.length;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A22),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.audiotrack, size: 16, color: Colors.white54),
          const SizedBox(width: 6),
          const Text(
            'Audio Panel',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const Spacer(),
          if (totalAssigned > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$totalAssigned assigned',
                style: TextStyle(
                  fontSize: 10,
                  color: FluxForgeTheme.accentBlue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSection(_SectionConfig config) {
    final isExpanded = _expandedSections.contains(config.id);
    final assignedCount = _countAssignedInSection(config);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header
        InkWell(
          onTap: () {
            // Use external callback if provided, otherwise update local state
            if (widget.onSectionToggle != null) {
              widget.onSectionToggle!(config.id);
            } else {
              setState(() {
                if (isExpanded) {
                  _localExpandedSections.remove(config.id);
                } else {
                  _localExpandedSections.add(config.id);
                }
              });
            }
          },
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: config.color.withOpacity(0.15),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: config.color,
                ),
                const SizedBox(width: 4),
                Text(
                  config.icon,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 6),
                Text(
                  config.title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: config.color,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                // Assigned count badge
                if (assignedCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: config.color.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '$assignedCount',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: config.color,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                // Completion percentage badge (SL-LP-P0.2)
                Builder(
                  builder: (context) {
                    final percentage = _getSectionPercentage(config);
                    final percentageColor = _getPercentageColor(percentage);
                    final isComplete = percentage == 100;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: percentageColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: percentageColor.withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$percentage%',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: percentageColor,
                              fontFamily: 'monospace',
                            ),
                          ),
                          if (isComplete) ...[
                            const SizedBox(width: 3),
                            Icon(Icons.check_circle, size: 10, color: percentageColor),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        // Progress bar (SL-LP-P0.2) — shown when expanded and not 100%
        if (isExpanded) Builder(
          builder: (context) {
            final percentage = _getSectionPercentage(config);
            if (percentage >= 100) return const SizedBox.shrink();

            return Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: LinearProgressIndicator(
                value: percentage / 100,
                backgroundColor: Colors.white.withOpacity(0.05),
                color: config.color.withOpacity(0.6),
                minHeight: 3,
              ),
            );
          },
        ),
        // Section content
        if (isExpanded)
          Container(
            color: const Color(0xFF0A0A0E),
            child: Column(
              children: config.groups.map((group) => _buildGroup(group, config)).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildGroup(_GroupConfig group, _SectionConfig section) {
    final groupKey = '${section.id}_${group.id}';
    final isExpanded = _expandedGroups.contains(groupKey);
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
            // Use external callback if provided, otherwise update local state
            if (widget.onGroupToggle != null) {
              widget.onGroupToggle!(groupKey);
            } else {
              setState(() {
                if (isExpanded) {
                  _localExpandedGroups.remove(groupKey);
                } else {
                  _localExpandedGroups.add(groupKey);
                }
              });
            }
          },
          onFolderDrop: (paths) => _handleFolderDrop(group, paths),
        ),
        // Individual slots
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 8, bottom: 8),
            child: Column(
              children: group.slots.map((slot) => _buildSlot(slot, section.color)).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildSlot(_SlotConfig slot, Color accentColor) {
    final audioPath = widget.audioAssignments[slot.stage];
    final hasAudio = audioPath != null;
    final fileName = hasAudio ? audioPath.split('/').last : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: DragTarget<Object>(
        onWillAcceptWithDetails: (details) {
          return details.data is AudioAsset ||
              details.data is List<AudioAsset> ||
              details.data is String;
        },
        onAcceptWithDetails: (details) {
          String? path;
          if (details.data is AudioAsset) {
            path = (details.data as AudioAsset).path;
          } else if (details.data is List<AudioAsset>) {
            final list = details.data as List<AudioAsset>;
            if (list.isNotEmpty) path = list.first.path;
          } else if (details.data is String) {
            path = details.data as String;
          }
          if (path != null) {
            widget.onAudioAssign?.call(slot.stage, path);
          }
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return Container(
            height: 26,
            decoration: BoxDecoration(
              color: isHovering
                  ? accentColor.withOpacity(0.2)
                  : const Color(0xFF16161C),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isHovering
                    ? accentColor
                    : hasAudio
                        ? accentColor.withOpacity(0.4)
                        : Colors.white.withOpacity(0.08),
              ),
            ),
            child: Row(
              children: [
                // Stage label
                Container(
                  width: 90,
                  height: 26,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(3)),
                  ),
                  child: Text(
                    slot.label,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: Colors.white60,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                // Audio path or hint
                Expanded(
                  child: Text(
                    hasAudio ? fileName! : 'Drop audio...',
                    style: TextStyle(
                      fontSize: 9,
                      color: hasAudio ? Colors.white70 : Colors.white24,
                      fontStyle: hasAudio ? FontStyle.normal : FontStyle.italic,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Play/Stop button (SL-LP-P0.1)
                if (hasAudio)
                  InkWell(
                    onTap: () => _togglePreview(slot.stage, audioPath),
                    child: Container(
                      width: 22,
                      height: 26,
                      alignment: Alignment.center,
                      child: Icon(
                        _playingStage == slot.stage ? Icons.stop : Icons.play_arrow,
                        size: 12,
                        color: _playingStage == slot.stage
                            ? FluxForgeTheme.accentGreen
                            : Colors.white54,
                      ),
                    ),
                  ),
                // Clear button
                if (hasAudio)
                  InkWell(
                    onTap: () => widget.onAudioClear?.call(slot.stage),
                    child: Container(
                      width: 22,
                      height: 26,
                      alignment: Alignment.center,
                      child: const Icon(Icons.close, size: 12, color: Colors.white38),
                    ),
                  ),
              ],
            ),
          );
        },
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

  /// Get color for completion percentage (SL-LP-P0.2)
  Color _getPercentageColor(int percentage) {
    if (percentage == 100) return FluxForgeTheme.accentGreen;
    if (percentage >= 75) return FluxForgeTheme.accentBlue;
    if (percentage >= 50) return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentRed;
  }

  int _countAssignedInGroup(_GroupConfig group) {
    int count = 0;
    for (final slot in group.slots) {
      if (widget.audioAssignments.containsKey(slot.stage)) {
        count++;
      }
    }
    return count;
  }

  /// Handle folder drop on a group — auto-distribute files
  void _handleFolderDrop(_GroupConfig group, List<String> audioPaths) {
    if (audioPaths.isEmpty) return;

    // Get all stages in this group
    final groupStages = group.slots.map((s) => s.stage).toSet();

    // Use StageGroupService to match files
    final matched = <StageMatch>[];
    final unmatched = <UnmatchedFile>[];

    for (final path in audioPaths) {
      final match = StageGroupService.instance.matchSingleFile(path);
      if (match != null && groupStages.contains(match.stage)) {
        matched.add(match);
      } else if (match != null) {
        // Matched but to wrong group — check if it should go elsewhere
        // For now, add as unmatched with suggestion
        unmatched.add(UnmatchedFile(
          audioFileName: path.split('/').last,
          audioPath: path,
          suggestions: [
            StageSuggestion(
              stage: match.stage,
              confidence: match.confidence,
              reason: 'Matched to different group',
            ),
          ],
        ));
      } else {
        // No match found
        unmatched.add(UnmatchedFile(
          audioFileName: path.split('/').last,
          audioPath: path,
          suggestions: const [],
        ));
      }
    }

    // Apply matched assignments
    for (final match in matched) {
      widget.onAudioAssign?.call(match.stage, match.audioPath);
    }

    // Show results dialog
    if (mounted) {
      _showDistributionResult(matched, unmatched);
    }

    // Notify callback
    widget.onBatchDistribute?.call(matched, unmatched);
  }

  void _showDistributionResult(List<StageMatch> matched, List<UnmatchedFile> unmatched) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: Row(
          children: [
            Icon(
              matched.isNotEmpty ? Icons.check_circle : Icons.warning,
              color: matched.isNotEmpty ? Colors.green : Colors.orange,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Auto-Distribution Result',
              style: const TextStyle(color: Colors.white, fontSize: 14),
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
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    _buildStatBadge('Matched', matched.length, Colors.green),
                    const SizedBox(width: 12),
                    _buildStatBadge('Unmatched', unmatched.length, Colors.orange),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Matched files
              if (matched.isNotEmpty) ...[
                const Text(
                  'MATCHED FILES:',
                  style: TextStyle(fontSize: 10, color: Colors.white38, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                ...matched.take(8).map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.check, size: 12, color: Colors.green),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          m.audioFileName,
                          style: const TextStyle(fontSize: 10, color: Colors.white70),
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
                    style: const TextStyle(fontSize: 10, color: Colors.white38),
                  ),
              ],
              // Unmatched files
              if (unmatched.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'UNMATCHED FILES:',
                  style: TextStyle(fontSize: 10, color: Colors.white38, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                ...unmatched.take(5).map((u) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.help_outline, size: 12, color: Colors.orange),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          u.audioFileName,
                          style: const TextStyle(fontSize: 10, color: Colors.white54),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (u.topSuggestion != null)
                        Text(
                          '? ${u.topSuggestion!.stage}',
                          style: const TextStyle(fontSize: 10, color: Colors.orange),
                        ),
                    ],
                  ),
                )),
                if (unmatched.length > 5)
                  Text(
                    '... and ${unmatched.length - 5} more',
                    style: const TextStyle(fontSize: 10, color: Colors.white38),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: Colors.white70)),
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
          style: const TextStyle(fontSize: 10, color: Colors.white54),
        ),
      ],
    );
  }
}

/// Group drop zone that accepts folders
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
  bool _isHovering = false;

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
        return InkWell(
          onTap: widget.onToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 26,
            margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: _isHovering
                  ? widget.section.color.withOpacity(0.3)
                  : const Color(0xFF14141A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _isHovering
                    ? widget.section.color
                    : Colors.white.withOpacity(0.08),
                width: _isHovering ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: Colors.white38,
                ),
                const SizedBox(width: 2),
                Text(
                  widget.group.icon,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.group.title,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.white60,
                    ),
                  ),
                ),
                // Drop hint when hovering
                if (_isHovering)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: widget.section.color.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Text(
                      'DROP TO AUTO-ASSIGN',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  )
                else if (widget.assignedCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: widget.section.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      '${widget.assignedCount}/${widget.group.slots.length}',
                      style: TextStyle(
                        fontSize: 8,
                        color: widget.section.color,
                      ),
                    ),
                  ),
              ],
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
  final String label;

  const _SlotConfig({required this.stage, required this.label});
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

  @override
  List<_GroupConfig> get groups => const [
    // ─── IDLE / ATTRACT ───
    _GroupConfig(
      id: 'idle',
      title: 'Idle / Attract',
      icon: '💤',
      slots: [
        _SlotConfig(stage: 'ATTRACT_LOOP', label: 'Attract Loop'),
        _SlotConfig(stage: 'IDLE_LOOP', label: 'Idle Loop'),
        _SlotConfig(stage: 'GAME_READY', label: 'Game Ready'),
        _SlotConfig(stage: 'GAME_START', label: 'Game Start'),
      ],
    ),
    // ─── SPIN CONTROLS ───
    _GroupConfig(
      id: 'spin_controls',
      title: 'Spin Controls',
      icon: '🔄',
      slots: [
        _SlotConfig(stage: 'SPIN_START', label: 'Spin Press'),
        _SlotConfig(stage: 'UI_STOP_PRESS', label: 'Stop Press'),
        _SlotConfig(stage: 'QUICK_STOP', label: 'Quick Stop'),
        _SlotConfig(stage: 'SLAM_STOP', label: 'Slam Stop'),
        _SlotConfig(stage: 'SLAM_STOP_IMPACT', label: 'Slam Impact'),
        _SlotConfig(stage: 'AUTOPLAY_START', label: 'AutoSpin On'),
        _SlotConfig(stage: 'AUTOPLAY_STOP', label: 'AutoSpin Off'),
        _SlotConfig(stage: 'AUTOPLAY_SPIN', label: 'AutoSpin Spin'),
        _SlotConfig(stage: 'UI_TURBO_ON', label: 'Turbo On'),
        _SlotConfig(stage: 'UI_TURBO_OFF', label: 'Turbo Off'),
      ],
    ),
    // ─── REEL ANIMATION ───
    _GroupConfig(
      id: 'reel_animation',
      title: 'Reel Animation',
      icon: '🔃',
      slots: [
        _SlotConfig(stage: 'REEL_SPIN', label: 'Spin Loop'),
        _SlotConfig(stage: 'REEL_SPINNING', label: 'Spinning'),
        _SlotConfig(stage: 'SPIN_ACCELERATION', label: 'Spin Accel'),
        _SlotConfig(stage: 'SPIN_DECELERATION', label: 'Spin Decel'),
        _SlotConfig(stage: 'TURBO_SPIN_LOOP', label: 'Turbo Loop'),
        _SlotConfig(stage: 'REEL_SLOW_STOP', label: 'Slow Stop'),
        _SlotConfig(stage: 'REEL_SHAKE', label: 'Reel Shake'),
        _SlotConfig(stage: 'REEL_WIGGLE', label: 'Reel Wiggle'),
      ],
    ),
    // ─── REEL STOPS ⚡ (pooled) ───
    _GroupConfig(
      id: 'reel_stops',
      title: 'Reel Stops ⚡',
      icon: '🛑',
      slots: [
        _SlotConfig(stage: 'REEL_STOP', label: 'Generic Stop'),
        _SlotConfig(stage: 'REEL_STOP_0', label: 'Reel 1 Stop'),
        _SlotConfig(stage: 'REEL_STOP_1', label: 'Reel 2 Stop'),
        _SlotConfig(stage: 'REEL_STOP_2', label: 'Reel 3 Stop'),
        _SlotConfig(stage: 'REEL_STOP_3', label: 'Reel 4 Stop'),
        _SlotConfig(stage: 'REEL_STOP_4', label: 'Reel 5 Stop'),
      ],
    ),
    // ─── ANTICIPATION ───
    _GroupConfig(
      id: 'anticipation',
      title: 'Anticipation',
      icon: '⏳',
      slots: [
        _SlotConfig(stage: 'ANTICIPATION_ON', label: 'Antic Start'),
        _SlotConfig(stage: 'ANTICIPATION_OFF', label: 'Antic End'),
        _SlotConfig(stage: 'ANTICIPATION_LOOP', label: 'Antic Loop'),
        _SlotConfig(stage: 'ANTICIPATION_REEL_0', label: 'Antic Reel 1'),
        _SlotConfig(stage: 'ANTICIPATION_REEL_1', label: 'Antic Reel 2'),
        _SlotConfig(stage: 'ANTICIPATION_REEL_2', label: 'Antic Reel 3'),
        _SlotConfig(stage: 'ANTICIPATION_REEL_3', label: 'Antic Reel 4'),
        _SlotConfig(stage: 'ANTICIPATION_REEL_4', label: 'Antic Reel 5'),
        _SlotConfig(stage: 'ANTICIPATION_LOW', label: 'Antic Low'),
        _SlotConfig(stage: 'ANTICIPATION_MEDIUM', label: 'Antic Medium'),
        _SlotConfig(stage: 'ANTICIPATION_HIGH', label: 'Antic High'),
        _SlotConfig(stage: 'ANTICIPATION_HEARTBEAT', label: 'Antic Heartbeat'),
        _SlotConfig(stage: 'ANTICIPATION_BUILDUP', label: 'Antic Buildup'),
        _SlotConfig(stage: 'ANTICIPATION_CLIMAX', label: 'Antic Climax'),
        _SlotConfig(stage: 'ANTICIPATION_RESOLVE', label: 'Antic Resolve'),
      ],
    ),
    // ─── SPIN END ───
    _GroupConfig(
      id: 'spin_end',
      title: 'Spin End',
      icon: '🏁',
      slots: [
        _SlotConfig(stage: 'SPIN_END', label: 'Spin End'),
        _SlotConfig(stage: 'NO_WIN', label: 'No Win'),
        _SlotConfig(stage: 'NEAR_MISS_SCATTER', label: 'Near Miss Scatter'),
        _SlotConfig(stage: 'NEAR_MISS_BONUS', label: 'Near Miss Bonus'),
        _SlotConfig(stage: 'NEAR_MISS_JACKPOT', label: 'Near Miss JP'),
        _SlotConfig(stage: 'NEAR_MISS_WILD', label: 'Near Miss Wild'),
        _SlotConfig(stage: 'NEAR_MISS_FEATURE', label: 'Near Miss Feature'),
      ],
    ),
  ];
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
        slots: special.expand((s) => [
          _SlotConfig(stage: 'SYMBOL_LAND_${s.id.toUpperCase()}', label: '${s.name} Land'),
          _SlotConfig(stage: 'WIN_SYMBOL_HIGHLIGHT_${s.id.toUpperCase()}', label: '${s.name} Win'),
        ]).toList(),
      ),
      _GroupConfig(
        id: 'highpay',
        title: 'High Pay',
        icon: '💎',
        slots: highPay.expand((s) => [
          _SlotConfig(stage: 'SYMBOL_LAND_${s.id.toUpperCase()}', label: '${s.name} Land'),
          _SlotConfig(stage: 'WIN_SYMBOL_HIGHLIGHT_${s.id.toUpperCase()}', label: '${s.name} Win'),
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
          _SlotConfig(stage: 'SYMBOL_LAND_MEDIUMPAY_1', label: 'Medium 1 Land'),
          _SlotConfig(stage: 'WIN_SYMBOL_HIGHLIGHT_MEDIUMPAY_1', label: 'Medium 1 Win'),
          _SlotConfig(stage: 'SYMBOL_LAND_MEDIUMPAY_2', label: 'Medium 2 Land'),
          _SlotConfig(stage: 'WIN_SYMBOL_HIGHLIGHT_MEDIUMPAY_2', label: 'Medium 2 Win'),
          _SlotConfig(stage: 'SYMBOL_LAND_MEDIUMPAY_3', label: 'Medium 3 Land'),
          _SlotConfig(stage: 'WIN_SYMBOL_HIGHLIGHT_MEDIUMPAY_3', label: 'Medium 3 Win'),
          _SlotConfig(stage: 'SYMBOL_LAND_MEDIUMPAY_4', label: 'Medium 4 Land'),
          _SlotConfig(stage: 'WIN_SYMBOL_HIGHLIGHT_MEDIUMPAY_4', label: 'Medium 4 Win'),
          _SlotConfig(stage: 'SYMBOL_LAND_MEDIUMPAY_5', label: 'Medium 5 Land'),
          _SlotConfig(stage: 'WIN_SYMBOL_HIGHLIGHT_MEDIUMPAY_5', label: 'Medium 5 Win'),
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
          _SlotConfig(stage: 'SYMBOL_LAND_LOWPAY_1', label: 'Low 1 Land'),
          _SlotConfig(stage: 'WIN_SYMBOL_HIGHLIGHT_LOWPAY_1', label: 'Low 1 Win'),
          _SlotConfig(stage: 'SYMBOL_LAND_LOWPAY_2', label: 'Low 2 Land'),
          _SlotConfig(stage: 'WIN_SYMBOL_HIGHLIGHT_LOWPAY_2', label: 'Low 2 Win'),
          _SlotConfig(stage: 'SYMBOL_LAND_LOWPAY_3', label: 'Low 3 Land'),
          _SlotConfig(stage: 'WIN_SYMBOL_HIGHLIGHT_LOWPAY_3', label: 'Low 3 Win'),
          _SlotConfig(stage: 'SYMBOL_LAND_LOWPAY_4', label: 'Low 4 Land'),
          _SlotConfig(stage: 'WIN_SYMBOL_HIGHLIGHT_LOWPAY_4', label: 'Low 4 Win'),
          _SlotConfig(stage: 'SYMBOL_LAND_LOWPAY_5', label: 'Low 5 Land'),
          _SlotConfig(stage: 'WIN_SYMBOL_HIGHLIGHT_LOWPAY_5', label: 'Low 5 Win'),
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
          _SlotConfig(stage: 'SCATTER_LAND_1', label: 'Scatter #1'),
          _SlotConfig(stage: 'SCATTER_LAND_2', label: 'Scatter #2'),
          _SlotConfig(stage: 'SCATTER_LAND_3', label: 'Scatter #3'),
          _SlotConfig(stage: 'SCATTER_LAND_4', label: 'Scatter #4'),
          _SlotConfig(stage: 'SCATTER_LAND_5', label: 'Scatter #5'),
          _SlotConfig(stage: 'SCATTER_COLLECT', label: 'Scatter Collect'),
        ],
      ),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3: WIN PRESENTATION [PRIMARY] — 50 slots
// Win detection → Line show → Tier display → Rollup → Celebration
// ═══════════════════════════════════════════════════════════════════════════════

class _WinPresentationSection extends _SectionConfig {
  final UltimateAudioPanel widget;
  _WinPresentationSection({required this.widget});

  @override String get id => 'win_presentation';
  @override String get title => 'WIN PRESENTATION';
  @override String get icon => '🏆';
  @override Color get color => const Color(0xFFFFD700);

  @override
  List<_GroupConfig> get groups => const [
    // ─── WIN EVALUATION ───
    _GroupConfig(
      id: 'eval',
      title: 'Win Evaluation',
      icon: '🔍',
      slots: [
        _SlotConfig(stage: 'WIN_EVAL', label: 'Win Evaluate'),
        _SlotConfig(stage: 'WIN_DETECTED', label: 'Win Detected'),
        _SlotConfig(stage: 'WIN_CALCULATE', label: 'Win Calculate'),
        _SlotConfig(stage: 'NO_WIN', label: 'No Win'),
      ],
    ),
    // ─── WIN LINES ⚡ (pooled) ───
    _GroupConfig(
      id: 'lines',
      title: 'Win Lines ⚡',
      icon: '📊',
      slots: [
        _SlotConfig(stage: 'WIN_LINE_SHOW', label: 'Line Show'),
        _SlotConfig(stage: 'WIN_LINE_HIDE', label: 'Line Hide'),
        _SlotConfig(stage: 'WIN_SYMBOL_HIGHLIGHT', label: 'Symbol Highlight'),
        _SlotConfig(stage: 'WIN_LINE_CYCLE', label: 'Line Cycle'),
      ],
    ),
    // ─── WIN TIERS ───
    _GroupConfig(
      id: 'tiers',
      title: 'Win Tiers',
      icon: '🎖️',
      slots: [
        _SlotConfig(stage: 'WIN_PRESENT_SMALL', label: 'Small Win (<5x)'),
        _SlotConfig(stage: 'WIN_PRESENT_BIG', label: 'Big Win (5-15x)'),
        _SlotConfig(stage: 'WIN_PRESENT_SUPER', label: 'Super Win (15-30x)'),
        _SlotConfig(stage: 'WIN_PRESENT_MEGA', label: 'Mega Win (30-60x)'),
        _SlotConfig(stage: 'WIN_PRESENT_EPIC', label: 'Epic Win (60-100x)'),
        _SlotConfig(stage: 'WIN_PRESENT_ULTRA', label: 'Ultra Win (100x+)'),
        _SlotConfig(stage: 'BIG_WIN_LOOP', label: 'Big Win Loop'),
        _SlotConfig(stage: 'BIG_WIN_COINS', label: 'Big Win Coins'),
        _SlotConfig(stage: 'BIG_WIN_INTRO', label: 'Big Win Intro'),
        _SlotConfig(stage: 'BIG_WIN_IMPACT', label: 'Big Win Impact'),
        _SlotConfig(stage: 'BIG_WIN_OUTRO', label: 'Big Win Outro'),
        _SlotConfig(stage: 'MEGA_WIN_UPGRADE', label: 'Mega Upgrade'),
        _SlotConfig(stage: 'SUPER_WIN_UPGRADE', label: 'Super Upgrade'),
        _SlotConfig(stage: 'EPIC_WIN_UPGRADE', label: 'Epic Upgrade'),
      ],
    ),
    // ─── ROLLUP / COUNTER ⚡ (pooled) ───
    _GroupConfig(
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
    _GroupConfig(
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
    // ─── VOICE OVERS ───
    _GroupConfig(
      id: 'voice',
      title: 'Voice Overs',
      icon: '🎙️',
      slots: [
        _SlotConfig(stage: 'VO_WIN_SMALL', label: 'VO Small Win'),
        _SlotConfig(stage: 'VO_WIN_MEDIUM', label: 'VO Medium Win'),
        _SlotConfig(stage: 'VO_WIN_BIG', label: 'VO Big Win'),
        _SlotConfig(stage: 'VO_WIN_MEGA', label: 'VO Mega Win'),
        _SlotConfig(stage: 'VO_WIN_EPIC', label: 'VO Epic Win'),
        _SlotConfig(stage: 'VO_WIN_ULTRA', label: 'VO Ultra Win'),
        _SlotConfig(stage: 'VO_CONGRATULATIONS', label: 'VO Congrats'),
        _SlotConfig(stage: 'VO_INCREDIBLE', label: 'VO Incredible'),
        _SlotConfig(stage: 'VO_SENSATIONAL', label: 'VO Sensational'),
      ],
    ),
  ];
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
    // ─── TRIGGER ───
    _GroupConfig(
      id: 'trigger',
      title: 'Trigger',
      icon: '🎯',
      slots: [
        _SlotConfig(stage: 'FREESPIN_TRIGGER', label: 'FS Trigger'),
        _SlotConfig(stage: 'FREESPIN_START', label: 'FS Start'),
        _SlotConfig(stage: 'FS_INTRO', label: 'FS Intro'),
        _SlotConfig(stage: 'FS_COUNTDOWN', label: 'FS Countdown'),
        _SlotConfig(stage: 'FS_BANNER_SHOW', label: 'FS Banner Show'),
        _SlotConfig(stage: 'FS_SCATTER_LAND_SEQUENCE', label: 'Scatter Sequence'),
      ],
    ),
    // ─── SPIN LOOP ───
    _GroupConfig(
      id: 'loop',
      title: 'Spin Loop',
      icon: '🔄',
      slots: [
        _SlotConfig(stage: 'FREESPIN_SPIN', label: 'FS Spin'),
        _SlotConfig(stage: 'FREESPIN_MUSIC', label: 'FS Music'),
        _SlotConfig(stage: 'FS_SPIN_1', label: 'FS Spin #1'),
        _SlotConfig(stage: 'FS_SPIN_LAST', label: 'FS Last Spin'),
        _SlotConfig(stage: 'FS_STICKY_WILD', label: 'FS Sticky Wild'),
        _SlotConfig(stage: 'FS_EXPANDING_WILD', label: 'FS Expand Wild'),
        _SlotConfig(stage: 'FS_MULTIPLIER_UP', label: 'FS Multi Up'),
        _SlotConfig(stage: 'FS_UPGRADE', label: 'FS Upgrade'),
      ],
    ),
    // ─── RETRIGGER ───
    _GroupConfig(
      id: 'retrigger',
      title: 'Retrigger',
      icon: '➕',
      slots: [
        _SlotConfig(stage: 'FREESPIN_RETRIGGER', label: 'FS Retrigger'),
        _SlotConfig(stage: 'FS_RETRIGGER_X3', label: 'FS +3'),
        _SlotConfig(stage: 'FS_RETRIGGER_X5', label: 'FS +5'),
        _SlotConfig(stage: 'FS_RETRIGGER_X10', label: 'FS +10'),
      ],
    ),
    // ─── SUMMARY ───
    _GroupConfig(
      id: 'summary',
      title: 'Summary',
      icon: '📋',
      slots: [
        _SlotConfig(stage: 'FREESPIN_END', label: 'FS End'),
        _SlotConfig(stage: 'FS_SUMMARY', label: 'FS Summary'),
        _SlotConfig(stage: 'FS_TOTAL_WIN', label: 'FS Total Win'),
        _SlotConfig(stage: 'FS_OUTRO', label: 'FS Outro'),
        _SlotConfig(stage: 'FS_BANNER_HIDE', label: 'FS Banner Hide'),
        _SlotConfig(stage: 'FS_CHOICE', label: 'FS Choice'),
        _SlotConfig(stage: 'FS_BUY_POPUP', label: 'FS Buy Popup'),
        _SlotConfig(stage: 'VO_FREE_SPINS', label: 'VO Free Spins'),
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
        _SlotConfig(stage: 'FEATURE_METER_INCREMENT', label: 'Meter +'),
        _SlotConfig(stage: 'FEATURE_METER_FULL', label: 'Meter Full'),
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
        _SlotConfig(stage: 'MULTIPLIER_LAND', label: 'Multi Land'),
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
        stage: 'MUSIC_${ctx.id.toUpperCase()}_L${i + 1}',
        label: 'Layer ${i + 1}',
      )),
    )).toList();

    // Add default music stages if no contexts
    if (contextGroups.isEmpty) {
      return const [
        _GroupConfig(
          id: 'base',
          title: 'Base Game',
          icon: '🎹',
          slots: [
            _SlotConfig(stage: 'MUSIC_BASE', label: 'Base Music'),
            _SlotConfig(stage: 'MUSIC_INTRO', label: 'Intro'),
            _SlotConfig(stage: 'MUSIC_LAYER_1', label: 'Layer 1'),
            _SlotConfig(stage: 'MUSIC_LAYER_2', label: 'Layer 2'),
            _SlotConfig(stage: 'MUSIC_LAYER_3', label: 'Layer 3'),
          ],
        ),
        _GroupConfig(
          id: 'attract',
          title: 'Attract / Idle',
          icon: '🔇',
          slots: [
            _SlotConfig(stage: 'ATTRACT_LOOP', label: 'Attract Loop'),
            _SlotConfig(stage: 'GAME_START', label: 'Game Start'),
          ],
        ),
        // ═══════════════════════════════════════════════════════════════════
        // TENSION MUSIC (P3 — 8 slots)
        // Dynamic tension escalation
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
        // FEATURE MUSIC (P3 — 10 slots)
        // Context-specific music
        // ═══════════════════════════════════════════════════════════════════
        _GroupConfig(
          id: 'features',
          title: 'Feature Music',
          icon: '🎼',
          slots: [
            _SlotConfig(stage: 'MUSIC_FREESPINS', label: 'FS Music'),
            _SlotConfig(stage: 'MUSIC_FREESPINS_LAYER', label: 'FS Layer'),
            _SlotConfig(stage: 'MUSIC_BONUS', label: 'Bonus Music'),
            _SlotConfig(stage: 'MUSIC_BONUS_LAYER', label: 'Bonus Layer'),
            _SlotConfig(stage: 'MUSIC_HOLD', label: 'Hold Music'),
            _SlotConfig(stage: 'MUSIC_HOLD_LAYER', label: 'Hold Layer'),
            _SlotConfig(stage: 'MUSIC_JACKPOT', label: 'Jackpot Music'),
            _SlotConfig(stage: 'MUSIC_BIG_WIN', label: 'Big Win Music'),
            _SlotConfig(stage: 'MUSIC_GAMBLE', label: 'Gamble Music'),
            _SlotConfig(stage: 'MUSIC_REVEAL', label: 'Reveal Music'),
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
        // AMBIENT (Industry Standard - Background atmosphere)
        // ═══════════════════════════════════════════════════════════════════
        _GroupConfig(
          id: 'ambient',
          title: 'Ambient',
          icon: '🌙',
          slots: [
            _SlotConfig(stage: 'AMBIENT_CASINO_LOOP', label: 'Casino Loop'),
            _SlotConfig(stage: 'AMBIENT_CROWD_MURMUR', label: 'Crowd Murmur'),
            _SlotConfig(stage: 'AMBIENT_SLOT_FLOOR', label: 'Slot Floor'),
            _SlotConfig(stage: 'AMBIENT_WIN_ROOM', label: 'Win Room'),
            _SlotConfig(stage: 'AMBIENT_VIP_LOUNGE', label: 'VIP Lounge'),
            _SlotConfig(stage: 'AMBIENT_NATURE', label: 'Nature'),
            _SlotConfig(stage: 'AMBIENT_UNDERWATER', label: 'Underwater'),
            _SlotConfig(stage: 'AMBIENT_SPACE', label: 'Space'),
            _SlotConfig(stage: 'AMBIENT_MYSTICAL', label: 'Mystical'),
            _SlotConfig(stage: 'AMBIENT_ADVENTURE', label: 'Adventure'),
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
        _SlotConfig(stage: 'UI_BUTTON_RELEASE', label: 'Button Release'),
        _SlotConfig(stage: 'UI_SPIN_PRESS', label: 'Spin Press'),
        _SlotConfig(stage: 'UI_SPIN_RELEASE', label: 'Spin Release'),
        _SlotConfig(stage: 'UI_BET_CHANGE', label: 'Bet Change'),
        _SlotConfig(stage: 'UI_LINES_CHANGE', label: 'Lines Change'),
        _SlotConfig(stage: 'UI_AUTOPLAY_ON', label: 'Autoplay On'),
        _SlotConfig(stage: 'UI_AUTOPLAY_OFF', label: 'Autoplay Off'),
        _SlotConfig(stage: 'UI_TURBO_ON', label: 'Turbo On'),
        _SlotConfig(stage: 'UI_TURBO_OFF', label: 'Turbo Off'),
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
        _SlotConfig(stage: 'UI_TAB_SELECT', label: 'Tab Select'),
        _SlotConfig(stage: 'UI_PANEL_SLIDE', label: 'Panel Slide'),
        _SlotConfig(stage: 'UI_PAYTABLE_OPEN', label: 'Paytable Open'),
        _SlotConfig(stage: 'UI_SETTINGS_OPEN', label: 'Settings Open'),
        _SlotConfig(stage: 'UI_HISTORY_OPEN', label: 'History Open'),
        _SlotConfig(stage: 'UI_INFO_OPEN', label: 'Info Open'),
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
        _SlotConfig(stage: 'UI_SUCCESS', label: 'Success'),
        _SlotConfig(stage: 'UI_WARNING', label: 'Warning'),
        _SlotConfig(stage: 'UI_POPUP_OPEN', label: 'Popup Open'),
        _SlotConfig(stage: 'UI_POPUP_CLOSE', label: 'Popup Close'),
        _SlotConfig(stage: 'UI_LOADING_START', label: 'Loading Start'),
        _SlotConfig(stage: 'UI_LOADING_END', label: 'Loading End'),
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
        _SlotConfig(stage: 'UI_CONFIRM', label: 'Confirm'),
        _SlotConfig(stage: 'UI_CANCEL', label: 'Cancel'),
        _SlotConfig(stage: 'UI_TOGGLE_ON', label: 'Toggle On'),
        _SlotConfig(stage: 'UI_TOGGLE_OFF', label: 'Toggle Off'),
        _SlotConfig(stage: 'UI_SLIDER_MOVE', label: 'Slider Move'),
        _SlotConfig(stage: 'UI_SLIDER_SNAP', label: 'Slider Snap'),
        _SlotConfig(stage: 'UI_COIN_INSERT', label: 'Coin Insert'),
        _SlotConfig(stage: 'UI_BALANCE_UPDATE', label: 'Balance Update'),
      ],
    ),
  ];
}
