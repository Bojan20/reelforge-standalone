import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/aurexis_retheme.dart';
import '../../services/aurexis_retheme_service.dart';
import 'aurexis_theme.dart';

/// AUREXIS™ Re-Theme Wizard — 3-step audio theme replacement.
///
/// Step 1: Source — Current project info and audio inventory
/// Step 2: Target — Select target theme audio folder
/// Step 3: Review — Review matches, resolve conflicts, apply
class ReThemeWizardWidget extends StatefulWidget {
  /// Callback when re-theme is applied.
  final ValueChanged<ReThemeMapping>? onApply;

  /// Callback when wizard is cancelled.
  final VoidCallback? onCancel;

  const ReThemeWizardWidget({
    super.key,
    this.onApply,
    this.onCancel,
  });

  @override
  State<ReThemeWizardWidget> createState() => _ReThemeWizardWidgetState();
}

class _ReThemeWizardWidgetState extends State<ReThemeWizardWidget> {
  ReThemeWizardStep _step = ReThemeWizardStep.source;
  ReThemeMatchStrategy _strategy = ReThemeMatchStrategy.namePattern;
  double _fuzzyThreshold = 0.7;

  // Source config
  String _sourceTheme = '';
  String _sourceDir = '';
  final List<String> _sourceFiles = [];

  // Target config
  String _targetTheme = '';
  String _targetDir = '';
  final List<String> _targetFiles = [];

  // Results
  ReThemeMapping? _mapping;

  // Review tab
  int _reviewTab = 0; // 0=matched, 1=unmatched, 2=conflicts

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AurexisColors.bgSection,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildWizardHeader(),
          _buildStepIndicator(),
          Padding(
            padding: const EdgeInsets.all(10),
            child: switch (_step) {
              ReThemeWizardStep.source => _buildSourceStep(),
              ReThemeWizardStep.target => _buildTargetStep(),
              ReThemeWizardStep.review => _buildReviewStep(),
            },
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildWizardHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AurexisColors.bgSectionHeader,
        border: Border(
          bottom: BorderSide(color: AurexisColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.swap_horiz, size: 14, color: AurexisColors.accent),
          const SizedBox(width: 4),
          Text(
            'RE-THEME WIZARD',
            style: AurexisTextStyles.sectionTitle.copyWith(
              color: AurexisColors.accent,
              fontSize: 9,
            ),
          ),
          const Spacer(),
          if (_mapping != null)
            Text(
              '${(_mapping!.matchPercent * 100).toStringAsFixed(0)}% matched',
              style: AurexisTextStyles.badge.copyWith(
                color: _mapping!.matchPercent > 0.8
                    ? AurexisColors.fatigueFresh
                    : AurexisColors.fatigueModerate,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          for (final step in ReThemeWizardStep.values) ...[
            if (step.stepIndex > 0)
              Expanded(
                child: Container(
                  height: 1,
                  color: step.stepIndex <= _step.stepIndex
                      ? AurexisColors.accent
                      : AurexisColors.borderSubtle,
                ),
              ),
            _buildStepDot(step),
          ],
        ],
      ),
    );
  }

  Widget _buildStepDot(ReThemeWizardStep step) {
    final isActive = step == _step;
    final isDone = step.stepIndex < _step.stepIndex;
    final color = isDone
        ? AurexisColors.fatigueFresh
        : isActive
            ? AurexisColors.accent
            : AurexisColors.borderSubtle;

    return GestureDetector(
      onTap: step.stepIndex <= _step.stepIndex ? () => setState(() => _step = step) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone || isActive
                  ? color.withValues(alpha: 0.15)
                  : Colors.transparent,
              border: Border.all(color: color, width: 1.5),
            ),
            child: Center(
              child: isDone
                  ? Icon(Icons.check, size: 10, color: color)
                  : Text(
                      '${step.stepIndex + 1}',
                      style: AurexisTextStyles.badge.copyWith(
                        color: color,
                        fontSize: 8,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            step.label,
            style: AurexisTextStyles.badge.copyWith(
              color: isActive ? AurexisColors.textPrimary : AurexisColors.textLabel,
              fontSize: 7,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1: SOURCE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSourceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Source Theme',
          style: AurexisTextStyles.sectionTitle.copyWith(fontSize: 10),
        ),
        const SizedBox(height: 6),
        // Theme name input
        _buildInputField(
          label: 'Theme Name',
          hint: 'e.g., Zeus Thunder',
          value: _sourceTheme,
          onChanged: (v) => setState(() => _sourceTheme = v),
        ),
        const SizedBox(height: 6),
        // Source directory
        _buildInputField(
          label: 'Audio Directory',
          hint: '/audio/zeus_theme/',
          value: _sourceDir,
          onChanged: (v) => setState(() => _sourceDir = v),
        ),
        const SizedBox(height: 8),
        // File count info
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AurexisColors.bgInput,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              Icon(Icons.audio_file, size: 14, color: AurexisColors.spatial),
              const SizedBox(width: 6),
              Text(
                '${_sourceFiles.length} audio files found',
                style: AurexisTextStyles.paramLabel,
              ),
              const Spacer(),
              GestureDetector(
                onTap: _scanSourceFiles,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AurexisColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: AurexisColors.accent.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    'SCAN',
                    style: AurexisTextStyles.badge.copyWith(color: AurexisColors.accent),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Match strategy
        Text(
          'Match Strategy',
          style: AurexisTextStyles.paramLabel.copyWith(fontSize: 9),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: ReThemeMatchStrategy.values.map((s) {
            final isSelected = s == _strategy;
            return GestureDetector(
              onTap: () => setState(() => _strategy = s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AurexisColors.accent.withValues(alpha: 0.15)
                      : AurexisColors.bgInput,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: isSelected
                        ? AurexisColors.accent
                        : AurexisColors.borderSubtle,
                    width: 0.5,
                  ),
                ),
                child: Text(
                  s.label,
                  style: AurexisTextStyles.badge.copyWith(
                    color: isSelected
                        ? AurexisColors.accent
                        : AurexisColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _scanSourceFiles() {
    // In real implementation, this would scan the directory
    // For now, populate with demo data
    setState(() {
      _sourceFiles.clear();
      _sourceFiles.addAll([
        '${_sourceTheme.toLowerCase().replaceAll(' ', '_')}_spin_start.wav',
        '${_sourceTheme.toLowerCase().replaceAll(' ', '_')}_spin_stop.wav',
        '${_sourceTheme.toLowerCase().replaceAll(' ', '_')}_win_small.wav',
        '${_sourceTheme.toLowerCase().replaceAll(' ', '_')}_win_medium.wav',
        '${_sourceTheme.toLowerCase().replaceAll(' ', '_')}_win_large.wav',
        '${_sourceTheme.toLowerCase().replaceAll(' ', '_')}_bonus_trigger.wav',
        '${_sourceTheme.toLowerCase().replaceAll(' ', '_')}_freespin_intro.wav',
        '${_sourceTheme.toLowerCase().replaceAll(' ', '_')}_music_base.wav',
        '${_sourceTheme.toLowerCase().replaceAll(' ', '_')}_music_freespin.wav',
        '${_sourceTheme.toLowerCase().replaceAll(' ', '_')}_ambient_loop.wav',
      ]);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2: TARGET
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTargetStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Target Theme',
          style: AurexisTextStyles.sectionTitle.copyWith(fontSize: 10),
        ),
        const SizedBox(height: 6),
        _buildInputField(
          label: 'Theme Name',
          hint: 'e.g., Egyptian Gold',
          value: _targetTheme,
          onChanged: (v) => setState(() => _targetTheme = v),
        ),
        const SizedBox(height: 6),
        _buildInputField(
          label: 'Audio Directory',
          hint: '/audio/egyptian_theme/',
          value: _targetDir,
          onChanged: (v) => setState(() => _targetDir = v),
        ),
        const SizedBox(height: 8),
        // Scan + match
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AurexisColors.bgInput,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.audio_file, size: 14, color: AurexisColors.variation),
                  const SizedBox(width: 6),
                  Text(
                    '${_targetFiles.length} target files',
                    style: AurexisTextStyles.paramLabel,
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _scanTargetFiles,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AurexisColors.variation.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: AurexisColors.variation.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        'SCAN',
                        style: AurexisTextStyles.badge.copyWith(color: AurexisColors.variation),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Fuzzy threshold slider
              Row(
                children: [
                  Text(
                    'Fuzzy Threshold:',
                    style: AurexisTextStyles.badge.copyWith(color: AurexisColors.textLabel),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                        activeTrackColor: AurexisColors.accent,
                        inactiveTrackColor: AurexisColors.bgSlider,
                        thumbColor: AurexisColors.accent,
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: _fuzzyThreshold,
                        min: 0.3,
                        max: 1.0,
                        onChanged: (v) => setState(() => _fuzzyThreshold = v),
                      ),
                    ),
                  ),
                  Text(
                    '${(_fuzzyThreshold * 100).toStringAsFixed(0)}%',
                    style: AurexisTextStyles.paramValue.copyWith(
                      color: AurexisColors.accent,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_mapping != null) ...[
          const SizedBox(height: 8),
          // Match summary
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AurexisColors.accent.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: AurexisColors.accent.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'AUTO-MATCH RESULTS',
                      style: AurexisTextStyles.sectionTitle.copyWith(fontSize: 8),
                    ),
                    const Spacer(),
                    Text(
                      '${(_mapping!.matchPercent * 100).toStringAsFixed(0)}%',
                      style: AurexisTextStyles.paramValue.copyWith(
                        color: AurexisColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMatchStat('Matched', _mapping!.matchedCount,
                        AurexisColors.fatigueFresh),
                    _buildMatchStat('Unmatched', _mapping!.unmatchedCount,
                        AurexisColors.fatigueCritical),
                    _buildMatchStat('Review', _mapping!.reviewCount,
                        AurexisColors.fatigueModerate),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _scanTargetFiles() {
    // Demo data for target theme
    setState(() {
      _targetFiles.clear();
      _targetFiles.addAll([
        '${_targetTheme.toLowerCase().replaceAll(' ', '_')}_spin_start.wav',
        '${_targetTheme.toLowerCase().replaceAll(' ', '_')}_spin_stop.wav',
        '${_targetTheme.toLowerCase().replaceAll(' ', '_')}_win_small.wav',
        '${_targetTheme.toLowerCase().replaceAll(' ', '_')}_win_medium.wav',
        '${_targetTheme.toLowerCase().replaceAll(' ', '_')}_win_big.wav',
        '${_targetTheme.toLowerCase().replaceAll(' ', '_')}_bonus_start.wav',
        '${_targetTheme.toLowerCase().replaceAll(' ', '_')}_freespin_intro.wav',
        '${_targetTheme.toLowerCase().replaceAll(' ', '_')}_music_base.wav',
        '${_targetTheme.toLowerCase().replaceAll(' ', '_')}_music_bonus.wav',
        '${_targetTheme.toLowerCase().replaceAll(' ', '_')}_ambient.wav',
        '${_targetTheme.toLowerCase().replaceAll(' ', '_')}_jackpot.wav',
      ]);

      // Run auto-matching
      _mapping = AurexisReThemeService.autoMatch(
        sourceTheme: _sourceTheme,
        targetTheme: _targetTheme,
        sourceFiles: _sourceFiles,
        targetFiles: _targetFiles,
        strategy: _strategy,
        fuzzyThreshold: _fuzzyThreshold,
      );
    });
  }

  Widget _buildMatchStat(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: AurexisTextStyles.paramValue.copyWith(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: AurexisTextStyles.badge.copyWith(color: AurexisColors.textLabel),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 3: REVIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildReviewStep() {
    if (_mapping == null) {
      return Center(
        child: Text(
          'No mapping data. Go back and run auto-match.',
          style: AurexisTextStyles.paramLabel.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }

    final mapping = _mapping!;
    final displayList = switch (_reviewTab) {
      0 => mapping.matchedMappings,
      1 => mapping.unmatchedMappings,
      2 => mapping.conflictMappings,
      _ => mapping.mappings,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tab bar
        Row(
          children: [
            _buildReviewTab('Matched', mapping.matchedCount, 0),
            const SizedBox(width: 4),
            _buildReviewTab('Unmatched', mapping.unmatchedCount, 1),
            const SizedBox(width: 4),
            _buildReviewTab('Conflicts', mapping.reviewCount, 2),
          ],
        ),
        const SizedBox(height: 6),
        // File list
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: displayList.length,
            itemBuilder: (context, index) {
              return _buildMappingRow(displayList[index]);
            },
          ),
        ),
        if (displayList.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Text(
                'No items in this category',
                style: AurexisTextStyles.paramLabel.copyWith(
                  color: AurexisColors.textLabel,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReviewTab(String label, int count, int tabIndex) {
    final isSelected = _reviewTab == tabIndex;
    return GestureDetector(
      onTap: () => setState(() => _reviewTab = tabIndex),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AurexisColors.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected ? AurexisColors.accent : AurexisColors.borderSubtle,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AurexisTextStyles.badge.copyWith(
                color: isSelected ? AurexisColors.accent : AurexisColors.textSecondary,
              ),
            ),
            const SizedBox(width: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: AurexisColors.bgInput,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                '$count',
                style: AurexisTextStyles.badge.copyWith(
                  color: AurexisColors.textLabel,
                  fontSize: 7,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMappingRow(ReThemeFileMapping mapping) {
    final confidence = mapping.confidence;
    final confColor = switch (confidence) {
      MatchConfidence.high => AurexisColors.fatigueFresh,
      MatchConfidence.medium => AurexisColors.fatigueMild,
      MatchConfidence.low => AurexisColors.fatigueModerate,
      MatchConfidence.veryLow => AurexisColors.fatigueHigh,
      MatchConfidence.none => AurexisColors.fatigueCritical,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AurexisColors.bgInput,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          // Confirmation indicator
          Icon(
            mapping.userConfirmed ? Icons.check_circle : Icons.circle_outlined,
            size: 10,
            color: mapping.userConfirmed
                ? AurexisColors.fatigueFresh
                : AurexisColors.textLabel,
          ),
          const SizedBox(width: 4),
          // Source file
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _truncatePath(mapping.sourcePath),
                  style: AurexisTextStyles.badge.copyWith(
                    color: AurexisColors.textPrimary,
                    fontSize: 8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (mapping.targetPath != null)
                  Text(
                    '→ ${_truncatePath(mapping.targetPath!)}',
                    style: AurexisTextStyles.badge.copyWith(
                      color: AurexisColors.spatial,
                      fontSize: 7,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Confidence badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: confColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              '${(mapping.confidenceScore * 100).toStringAsFixed(0)}%',
              style: AurexisTextStyles.badge.copyWith(
                color: confColor,
                fontSize: 7,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _truncatePath(String path) {
    if (path.length <= 35) return path;
    return '...${path.substring(path.length - 32)}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInputField({
    required String label,
    required String hint,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: AurexisTextStyles.paramLabel.copyWith(fontSize: 9),
          ),
        ),
        Expanded(
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: AurexisColors.bgInput,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
            ),
            child: TextField(
              style: AurexisTextStyles.paramLabel.copyWith(fontSize: 9),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AurexisTextStyles.paramLabel.copyWith(
                  fontSize: 9,
                  color: AurexisColors.textLabel,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AurexisColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Cancel
          GestureDetector(
            onTap: widget.onCancel,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
              ),
              child: Text('Cancel', style: AurexisTextStyles.badge),
            ),
          ),
          const Spacer(),
          // Back (if not on first step)
          if (_step != ReThemeWizardStep.source) ...[
            GestureDetector(
              onTap: () => setState(() {
                _step = ReThemeWizardStep.values[_step.stepIndex - 1];
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
                ),
                child: Text('Back', style: AurexisTextStyles.badge),
              ),
            ),
            const SizedBox(width: 4),
          ],
          // Next / Apply
          GestureDetector(
            onTap: _onNextOrApply,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AurexisColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AurexisColors.accent, width: 0.5),
              ),
              child: Text(
                _step == ReThemeWizardStep.review ? 'Apply' : 'Next',
                style: AurexisTextStyles.badge.copyWith(color: AurexisColors.accent),
              ),
            ),
          ),
          if (_step == ReThemeWizardStep.review && _mapping != null) ...[
            const SizedBox(width: 4),
            // Export JSON
            GestureDetector(
              onTap: () {
                final json = _mapping!.toJsonString();
                Clipboard.setData(ClipboardData(text: json));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Mapping JSON copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download, size: 10, color: AurexisColors.textSecondary),
                    const SizedBox(width: 2),
                    Text('JSON', style: AurexisTextStyles.badge),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _onNextOrApply() {
    if (_step == ReThemeWizardStep.review) {
      if (_mapping != null) {
        widget.onApply?.call(_mapping!);
      }
    } else {
      setState(() {
        _step = ReThemeWizardStep.values[_step.stepIndex + 1];
      });
    }
  }
}
