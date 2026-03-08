/// Win Tier Config Panel — User-facing editor for P5 WinTierConfig
///
/// Allows editing of:
/// - Regular win tiers (WIN_1 through WIN_5): multiplier ranges, labels,
///   rollup durations, tick rates, particle counts
/// - Big win tiers (TIER 1 through TIER 5): multiplier ranges, labels,
///   visual/audio/particle intensities, celebration durations
/// - Big win threshold (when big win celebration starts)
/// - Preset selection (Standard, High Volatility, Jackpot Focus, Mobile)
/// - JSON import/export
///
/// All data-driven via SlotLabProjectProvider — zero hardcoded values.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/win_tier_config.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../theme/fluxforge_theme.dart';

class WinTierConfigPanel extends StatefulWidget {
  final SlotLabProjectProvider projectProvider;

  const WinTierConfigPanel({super.key, required this.projectProvider});

  @override
  State<WinTierConfigPanel> createState() => _WinTierConfigPanelState();
}

class _WinTierConfigPanelState extends State<WinTierConfigPanel> {
  final ValueNotifier<bool> _showRegular = ValueNotifier(false);
  final ValueNotifier<bool> _showBigWin = ValueNotifier(false);
  final ValueNotifier<bool> _showPresets = ValueNotifier(false);
  final ValueNotifier<double> _simBet = ValueNotifier(1.0);
  final ValueNotifier<double> _simWin = ValueNotifier(5.0);
  final ValueNotifier<String?> _editingField = ValueNotifier(null);

  // Inline editing state
  late TextEditingController _inlineController;
  late FocusNode _inlineFocus;

  SlotWinConfiguration get _config => widget.projectProvider.winConfiguration;
  RegularWinTierConfig get _regular => _config.regularWins;
  BigWinConfig get _bigWin => _config.bigWins;

  /// Manual refresh notifier — bumped after local edits to trigger rebuild
  /// without listening to the mega-provider's every notifyListeners.
  final ValueNotifier<int> _revision = ValueNotifier(0);
  void _bumpRevision() => _revision.value++;

  @override
  void initState() {
    super.initState();
    _inlineController = TextEditingController();
    _inlineFocus = FocusNode();
  }

  @override
  void dispose() {
    _inlineController.dispose();
    _inlineFocus.dispose();
    _showRegular.dispose();
    _showBigWin.dispose();
    _simBet.dispose();
    _simWin.dispose();
    _showPresets.dispose();
    _editingField.dispose();
    _revision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([_revision, _showRegular, _showBigWin, _showPresets, _editingField, _simBet, _simWin]),
            builder: (context, _) {
              return ListView(
                padding: const EdgeInsets.all(6),
                children: [
                  if (_showPresets.value) ...[
                    _buildPresetsSection(),
                    const SizedBox(height: 8),
                  ],
                  GestureDetector(
                    onTap: () => _showRegular.value = !_showRegular.value,
                    child: _buildSectionHeader(
                      'REGULAR WIN TIERS',
                      icon: Icons.emoji_events_outlined,
                      color: const Color(0xFF66BB6A),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_regular.tiers.length} tiers',
                            style: const TextStyle(color: Color(0xFF606068), fontSize: 9),
                          ),
                          const SizedBox(width: 6),
                          if (_showRegular.value) _addTierButton(),
                          const SizedBox(width: 4),
                          Icon(
                            _showRegular.value ? Icons.expand_less : Icons.expand_more,
                            size: 12,
                            color: const Color(0xFF606068),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_showRegular.value)
                    ..._regular.tiers.map(_buildRegularTierRow),
                  const SizedBox(height: 12),
                  _buildBigWinThresholdRow(),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _showBigWin.value = !_showBigWin.value,
                    child: _buildSectionHeader(
                      'BIG WIN TIERS',
                      icon: Icons.stars,
                      color: const Color(0xFFFFAA00),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_bigWin.tiers.length} tiers',
                            style: const TextStyle(color: Color(0xFF606068), fontSize: 9),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _showBigWin.value ? Icons.expand_less : Icons.expand_more,
                            size: 12,
                            color: const Color(0xFF606068),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_showBigWin.value) ...[
                    _buildBigWinTimingRow(),
                    const SizedBox(height: 4),
                    ..._bigWin.tiers.map(_buildBigWinTierRow),
                  ] else ...[
                    ..._bigWin.tiers.map(_buildBigWinTierCompact),
                  ],
                  const SizedBox(height: 12),
                  _buildValidationSection(),
                  const SizedBox(height: 8),
                  _buildSimulatorSection(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF111116),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2A2A32), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune, size: 12, color: Color(0xFFFFAA00)),
          const SizedBox(width: 4),
          const Text(
            'WIN TIERS',
            style: TextStyle(
              color: Color(0xFFD0D0D8),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          // Presets toggle
          ValueListenableBuilder<bool>(
            valueListenable: _showPresets,
            builder: (context, active, _) => _headerButton(
              icon: Icons.style,
              label: 'PRESETS',
              isActive: active,
              onTap: () => _showPresets.value = !_showPresets.value,
            ),
          ),
          const SizedBox(width: 4),
          // Export
          _headerButton(
            icon: Icons.upload,
            label: 'EXPORT',
            onTap: _exportConfig,
          ),
          const SizedBox(width: 4),
          // Import
          _headerButton(
            icon: Icons.download,
            label: 'IMPORT',
            onTap: _importConfig,
          ),
          const SizedBox(width: 4),
          // Reset
          _headerButton(
            icon: Icons.restart_alt,
            label: 'RESET',
            onTap: _resetConfig,
            color: const Color(0xFFFF6060),
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    Color? color,
  }) {
    final c = color ?? const Color(0xFF808088);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isActive ? c.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isActive ? c.withValues(alpha: 0.4) : const Color(0xFF2A2A32),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 9, color: c),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(color: c, fontSize: 7, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSectionHeader(String title, {
    required IconData icon,
    required Color color,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPresetsSection() {
    final presets = <String, SlotWinConfiguration>{
      'Standard': SlotWinConfigurationPresets.standard,
      'High Volatility': SlotWinConfigurationPresets.highVolatility,
      'Jackpot Focus': SlotWinConfigurationPresets.jackpotFocus,
      'Mobile': SlotWinConfigurationPresets.mobileOptimized,
    };

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF161620),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2A32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'APPLY PRESET',
            style: TextStyle(
              color: Color(0xFF808088),
              fontSize: 8,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: presets.entries.map((e) {
              final isActive = _regular.name == e.value.regularWins.name;
              return GestureDetector(
                onTap: () {
                  widget.projectProvider.applyWinTierPreset(e.value);
                  _bumpRevision();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? FluxForgeTheme.accentCyan.withValues(alpha: 0.15)
                        : const Color(0xFF1A1A24),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isActive
                          ? FluxForgeTheme.accentCyan.withValues(alpha: 0.5)
                          : const Color(0xFF2A2A32),
                    ),
                  ),
                  child: Text(
                    e.key,
                    style: TextStyle(
                      color: isActive
                          ? FluxForgeTheme.accentCyan
                          : const Color(0xFF808088),
                      fontSize: 9,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADD TIER BUTTON
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _addTierButton() {
    return GestureDetector(
      onTap: _addNewRegularTier,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFF66BB6A).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFF66BB6A).withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 10, color: Color(0xFF66BB6A)),
            SizedBox(width: 2),
            Text('ADD', style: TextStyle(
              color: Color(0xFF66BB6A), fontSize: 7, fontWeight: FontWeight.w600,
            )),
          ],
        ),
      ),
    );
  }

  void _addNewRegularTier() {
    // Find next available tier ID (1-based, skip -1 and 0)
    final existingIds = _regular.tiers.map((t) => t.tierId).toSet();
    int nextId = 1;
    while (existingIds.contains(nextId)) {
      nextId++;
    }

    // Find the last tier's toMultiplier as new tier's fromMultiplier
    final sortedTiers = List<WinTierDefinition>.from(_regular.tiers)
      ..sort((a, b) => a.tierId.compareTo(b.tierId));
    final lastPositive = sortedTiers.where((t) => t.tierId > 0).lastOrNull;
    final from = lastPositive?.toMultiplier ?? 1.0;

    final newTier = WinTierDefinition(
      tierId: nextId,
      fromMultiplier: from,
      toMultiplier: from + 5.0,
      displayLabel: 'WIN $nextId',
      rollupDurationMs: 1500,
      rollupTickRate: 15,
      particleBurstCount: nextId * 5,
    );

    widget.projectProvider.addRegularWinTier(newTier);
    _bumpRevision();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REGULAR WIN TIER ROW
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if a regular tier has validation issues
  String? _regularTierError(WinTierDefinition tier) {
    if (tier.fromMultiplier >= tier.toMultiplier) {
      return 'FROM >= TO';
    }
    final sorted = List<WinTierDefinition>.from(_regular.tiers)
      ..sort((a, b) => a.fromMultiplier.compareTo(b.fromMultiplier));
    final idx = sorted.indexWhere((t) => t.tierId == tier.tierId);
    if (idx > 0) {
      final prev = sorted[idx - 1];
      if ((prev.toMultiplier - tier.fromMultiplier).abs() > 0.001) {
        return 'GAP with ${prev.stageName}';
      }
    }
    if (idx < sorted.length - 1) {
      final next = sorted[idx + 1];
      if ((tier.toMultiplier - next.fromMultiplier).abs() > 0.001) {
        return 'GAP with ${next.stageName}';
      }
    }
    return null;
  }

  /// Check if a big win tier has validation issues
  String? _bigWinTierError(BigWinTierDefinition tier) {
    if (tier.toMultiplier != double.infinity && tier.fromMultiplier >= tier.toMultiplier) {
      return 'FROM >= TO';
    }
    final sorted = List<BigWinTierDefinition>.from(_bigWin.tiers)
      ..sort((a, b) => a.fromMultiplier.compareTo(b.fromMultiplier));
    final idx = sorted.indexWhere((t) => t.tierId == tier.tierId);
    if (idx == 0 && (tier.fromMultiplier - _bigWin.threshold).abs() > 0.001) {
      return 'Must start at ${_bigWin.threshold}x';
    }
    if (idx > 0) {
      final prev = sorted[idx - 1];
      if (prev.toMultiplier != double.infinity &&
          (prev.toMultiplier - tier.fromMultiplier).abs() > 0.001) {
        return 'GAP with TIER ${prev.tierId}';
      }
    }
    if (idx < sorted.length - 1) {
      final next = sorted[idx + 1];
      if (tier.toMultiplier != double.infinity &&
          (tier.toMultiplier - next.fromMultiplier).abs() > 0.001) {
        return 'GAP with TIER ${next.tierId}';
      }
    }
    return null;
  }

  Widget _buildRegularTierRow(WinTierDefinition tier) {
    final tierName = tier.stageName;
    final color = _tierColor(tier.tierId);
    final error = _regularTierError(tier);
    final hasError = error != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: hasError ? const Color(0xFF1A0A0A) : const Color(0xFF161620),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: hasError
              ? const Color(0xFFFF4040).withValues(alpha: 0.5)
              : color.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(
                color: hasError ? const Color(0xFFFF4040) : color, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(tierName, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
              if (hasError) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: error,
                  child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6060), size: 10),
                ),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: _inlineTextField(
                  fieldId: 'regular_${tier.tierId}_label',
                  value: tier.displayLabel.isEmpty ? '(no label)' : tier.displayLabel,
                  onSubmit: (val) => _updateRegularTier(tier, displayLabel: val),
                  dim: tier.displayLabel.isEmpty,
                  isText: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _inlineNumericField(
                fieldId: 'regular_${tier.tierId}_from',
                label: 'FROM',
                value: tier.fromMultiplier,
                suffix: 'x',
                onSubmit: (val) => _updateRegularTier(tier, fromMultiplier: val),
                width: 50,
              ),
              const SizedBox(width: 4),
              const Text('→', style: TextStyle(color: Color(0xFF404048), fontSize: 10)),
              const SizedBox(width: 4),
              _inlineNumericField(
                fieldId: 'regular_${tier.tierId}_to',
                label: 'TO',
                value: tier.toMultiplier,
                suffix: 'x',
                onSubmit: (val) => _updateRegularTier(tier, toMultiplier: val),
                width: 50,
              ),
              const Spacer(),
              _inlineNumericField(
                fieldId: 'regular_${tier.tierId}_rollup',
                label: 'ROLLUP',
                value: tier.rollupDurationMs.toDouble(),
                suffix: 'ms',
                onSubmit: (val) => _updateRegularTier(tier, rollupDurationMs: val.toInt()),
                width: 55,
                isInt: true,
              ),
              const SizedBox(width: 4),
              _inlineNumericField(
                fieldId: 'regular_${tier.tierId}_tick',
                label: 'TICK',
                value: tier.rollupTickRate.toDouble(),
                suffix: '/s',
                onSubmit: (val) => _updateRegularTier(tier, rollupTickRate: val.toInt()),
                width: 40,
                isInt: true,
              ),
            ],
          ),
          if (tier.tierId > 0) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 14,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 1.5,
                  rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 3),
                  activeTrackColor: color.withValues(alpha: 0.6),
                  inactiveTrackColor: const Color(0xFF2A2A32),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: RangeSlider(
                  values: () {
                    final s = tier.fromMultiplier.clamp(0.0, 25.0);
                    final e = tier.toMultiplier.clamp(0.0, 25.0);
                    return RangeValues(s, e < s ? s : e);
                  }(),
                  min: 0,
                  max: 25,
                  divisions: 250,
                  onChanged: (range) {
                    _updateRegularTier(tier,
                      fromMultiplier: double.parse(range.start.toStringAsFixed(1)),
                      toMultiplier: double.parse(range.end.toStringAsFixed(1)),
                      syncStages: false,
                    );
                  },
                  onChangeEnd: (range) {
                    widget.projectProvider.syncWinTierStages();
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BIG WIN THRESHOLD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBigWinThresholdRow() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1420),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFFAA00).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, size: 12, color: Color(0xFFFFAA00)),
          const SizedBox(width: 4),
          const Text(
            'BIG WIN THRESHOLD',
            style: TextStyle(
              color: Color(0xFFFFAA00),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          _inlineNumericField(
            fieldId: 'big_threshold',
            label: '',
            value: _bigWin.threshold,
            suffix: 'x bet',
            onSubmit: (val) {
              widget.projectProvider.setBigWinThreshold(val);
              _bumpRevision();
            },
            width: 70,
            accentColor: const Color(0xFFFFAA00),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BIG WIN TIMING
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBigWinTimingRow() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF161620),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2A32)),
      ),
      child: Row(
        children: [
          _inlineNumericField(
            fieldId: 'big_intro',
            label: 'INTRO',
            value: _bigWin.introDurationMs.toDouble(),
            suffix: 'ms',
            onSubmit: (val) => _updateBigWinTiming(introDurationMs: val.toInt()),
            width: 55,
            isInt: true,
          ),
          const SizedBox(width: 6),
          _inlineNumericField(
            fieldId: 'big_end',
            label: 'END',
            value: _bigWin.endDurationMs.toDouble(),
            suffix: 'ms',
            onSubmit: (val) => _updateBigWinTiming(endDurationMs: val.toInt()),
            width: 55,
            isInt: true,
          ),
          const SizedBox(width: 6),
          _inlineNumericField(
            fieldId: 'big_fade',
            label: 'FADE',
            value: _bigWin.fadeOutDurationMs.toDouble(),
            suffix: 'ms',
            onSubmit: (val) => _updateBigWinTiming(fadeOutDurationMs: val.toInt()),
            width: 55,
            isInt: true,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BIG WIN TIER ROW (EXPANDED)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBigWinTierRow(BigWinTierDefinition tier) {
    final color = _bigWinTierColor(tier.tierId);
    final error = _bigWinTierError(tier);
    final hasError = error != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: hasError ? const Color(0xFF1A0A0A) : const Color(0xFF161620),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: hasError
              ? const Color(0xFFFF4040).withValues(alpha: 0.5)
              : color.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Tier name + label
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: hasError ? const Color(0xFFFF4040) : color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'TIER ${tier.tierId}',
                style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
              ),
              if (hasError) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: error,
                  child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6060), size: 10),
                ),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: _inlineTextField(
                  fieldId: 'big_${tier.tierId}_label',
                  value: tier.displayLabel,
                  onSubmit: (val) => _updateBigWinTier(tier, displayLabel: val),
                  isText: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Row 2: Multiplier range + duration
          Row(
            children: [
              _inlineNumericField(
                fieldId: 'big_${tier.tierId}_from',
                label: 'FROM',
                value: tier.fromMultiplier,
                suffix: 'x',
                onSubmit: (val) => _updateBigWinTier(tier, fromMultiplier: val),
                width: 50,
              ),
              const SizedBox(width: 4),
              const Text('→', style: TextStyle(color: Color(0xFF404048), fontSize: 10)),
              const SizedBox(width: 4),
              _inlineNumericField(
                fieldId: 'big_${tier.tierId}_to',
                label: 'TO',
                value: tier.toMultiplier == double.infinity ? -1 : tier.toMultiplier,
                suffix: tier.toMultiplier == double.infinity ? '∞' : 'x',
                onSubmit: (val) => _updateBigWinTier(
                  tier,
                  toMultiplier: val < 0 ? double.infinity : val,
                ),
                width: 50,
              ),
              const Spacer(),
              _inlineNumericField(
                fieldId: 'big_${tier.tierId}_dur',
                label: 'DUR',
                value: tier.durationMs.toDouble(),
                suffix: 'ms',
                onSubmit: (val) => _updateBigWinTier(tier, durationMs: val.toInt()),
                width: 55,
                isInt: true,
              ),
            ],
          ),
          // RangeSlider for FROM/TO (skip if toMultiplier is infinity)
          if (tier.toMultiplier != double.infinity) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 14,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 1.5,
                  rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 3),
                  activeTrackColor: color.withValues(alpha: 0.6),
                  inactiveTrackColor: const Color(0xFF2A2A32),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: RangeSlider(
                  values: () {
                    final s = tier.fromMultiplier.clamp(0.0, 100.0);
                    final e = tier.toMultiplier.clamp(0.0, 100.0);
                    return RangeValues(s, e < s ? s : e);
                  }(),
                  min: 0,
                  max: 100,
                  divisions: 1000,
                  onChanged: (range) {
                    _updateBigWinTier(tier,
                      fromMultiplier: double.parse(range.start.toStringAsFixed(1)),
                      toMultiplier: double.parse(range.end.toStringAsFixed(1)),
                      syncStages: false,
                    );
                  },
                  onChangeEnd: (range) {
                    widget.projectProvider.syncWinTierStages();
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          // Row 3: Intensities
          Row(
            children: [
              Expanded(child: _intensitySlider('VIS', tier.visualIntensity, 1.0, 2.0, color,
                  (val) => _updateBigWinTier(tier, visualIntensity: val, syncStages: false),
                  onChangeEnd: widget.projectProvider.syncWinTierStages)),
              const SizedBox(width: 4),
              Expanded(child: _intensitySlider('PART', tier.particleMultiplier, 0.5, 4.0, color,
                  (val) => _updateBigWinTier(tier, particleMultiplier: val, syncStages: false),
                  onChangeEnd: widget.projectProvider.syncWinTierStages)),
              const SizedBox(width: 4),
              Expanded(child: _intensitySlider('AUD', tier.audioIntensity, 0.5, 2.0, color,
                  (val) => _updateBigWinTier(tier, audioIntensity: val, syncStages: false),
                  onChangeEnd: widget.projectProvider.syncWinTierStages)),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BIG WIN TIER COMPACT (COLLAPSED)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBigWinTierCompact(BigWinTierDefinition tier) {
    final color = _bigWinTierColor(tier.tierId);
    final toStr = tier.toMultiplier == double.infinity
        ? '∞'
        : '${tier.toMultiplier.toStringAsFixed(0)}x';

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF161620),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            'T${tier.tierId}',
            style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Text(
            '${tier.fromMultiplier.toStringAsFixed(0)}x → $toStr',
            style: const TextStyle(color: Color(0xFF808088), fontSize: 8),
          ),
          const Spacer(),
          Text(
            tier.displayLabel,
            style: const TextStyle(color: Color(0xFF606068), fontSize: 8),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SIMULATOR — Test which tier matches a given bet/win amount
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSimulatorSection() {
    final bet = _simBet.value;
    final win = _simWin.value;
    final multiplier = bet > 0 ? win / bet : 0.0;

    // Find matching regular tier
    final regularMatch = _regular.tiers.cast<WinTierDefinition?>().firstWhere(
      (t) => t!.matches(win, bet),
      orElse: () => null,
    );

    // Find matching big win tier
    final bigWinMatch = _bigWin.tiers.cast<BigWinTierDefinition?>().firstWhere(
      (t) => t!.matches(win, bet),
      orElse: () => null,
    );

    final isBigWin = multiplier >= _bigWin.threshold;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF12121C),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF4A9EFF).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.science, color: Color(0xFF4A9EFF), size: 11),
              SizedBox(width: 4),
              Text(
                'WIN TIER SIMULATOR',
                style: TextStyle(
                  color: Color(0xFF4A9EFF),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // BET + WIN input row
          Row(
            children: [
              _simField('BET', bet, (v) => _simBet.value = v),
              const SizedBox(width: 8),
              _simField('WIN', win, (v) => _simWin.value = v),
              const SizedBox(width: 8),
              // Multiplier display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isBigWin
                      ? const Color(0xFFFFAA00).withValues(alpha: 0.12)
                      : const Color(0xFF4A9EFF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '${multiplier.toStringAsFixed(1)}x',
                  style: TextStyle(
                    color: isBigWin ? const Color(0xFFFFAA00) : const Color(0xFF4A9EFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Result
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (regularMatch != null) ...[
                  Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: _tierColor(regularMatch.tierId),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        regularMatch.stageName,
                        style: TextStyle(
                          color: _tierColor(regularMatch.tierId),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (regularMatch.displayLabel.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          regularMatch.displayLabel,
                          style: const TextStyle(color: Color(0xFF808088), fontSize: 9),
                        ),
                      ],
                    ],
                  ),
                ] else
                  const Text(
                    'No regular tier match',
                    style: TextStyle(color: Color(0xFF606068), fontSize: 9),
                  ),
                if (isBigWin && bigWinMatch != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: _bigWinTierColor(bigWinMatch.tierId),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'BIG WIN TIER ${bigWinMatch.tierId}',
                        style: TextStyle(
                          color: _bigWinTierColor(bigWinMatch.tierId),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (bigWinMatch.displayLabel.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          bigWinMatch.displayLabel,
                          style: const TextStyle(color: Color(0xFF808088), fontSize: 9),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _simField(String label, double value, ValueChanged<double> onChanged) {
    return Expanded(
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF606068),
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: TextField(
                controller: TextEditingController(text: value.toStringAsFixed(2)),
                style: const TextStyle(color: Color(0xFFD0D0D8), fontSize: 10),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
                onSubmitted: (val) {
                  final parsed = double.tryParse(val);
                  if (parsed != null && parsed >= 0) onChanged(parsed);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildValidationSection() {
    final errors = _config.regularWins.getValidationErrors();
    final bigWinValid = _config.bigWins.validate();

    if (errors.isEmpty && bigWinValid) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1A0A),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF66BB6A).withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle, size: 12, color: Color(0xFF66BB6A)),
            SizedBox(width: 4),
            Text(
              'Configuration valid',
              style: TextStyle(color: Color(0xFF66BB6A), fontSize: 9),
            ),
          ],
        ),
      );
    }

    final allErrors = [...errors];
    if (!bigWinValid) {
      allErrors.add('Big win tier 1 must start at threshold (${_bigWin.threshold}x)');
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A0A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFF6060).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber, size: 12, color: Color(0xFFFF6060)),
              SizedBox(width: 4),
              Text(
                'VALIDATION ERRORS',
                style: TextStyle(
                  color: Color(0xFFFF6060),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...allErrors.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• $e',
                  style: const TextStyle(color: Color(0xFFFF8080), fontSize: 8),
                ),
              )),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INLINE EDITING FIELDS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Inline text field — single tap to start editing, Enter/blur to commit
  Widget _inlineTextField({
    required String fieldId,
    required String value,
    required ValueChanged<String> onSubmit,
    bool dim = false,
    bool isText = false,
  }) {
    final isEditing = _editingField.value == fieldId;

    if (isEditing) {
      return SizedBox(
        height: 16,
        child: TextField(
          controller: _inlineController,
          focusNode: _inlineFocus,
          style: const TextStyle(
            color: Color(0xFFD0D0D8),
            fontSize: 9,
            fontFamily: 'monospace',
          ),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF4488FF)),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF4488FF)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF4488FF), width: 1.5),
            ),
          ),
          onSubmitted: (val) {
            onSubmit(val);
            _editingField.value = null;
          },
          onTapOutside: (_) => _commitInlineEdit(),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _startInlineEdit(fieldId, value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: Colors.transparent),
        ),
        child: Text(
          value,
          style: TextStyle(
            color: dim ? const Color(0xFF404048) : const Color(0xFF808088),
            fontSize: 9,
            fontStyle: dim ? FontStyle.italic : FontStyle.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// Inline numeric field — single tap to start editing
  Widget _inlineNumericField({
    required String fieldId,
    required String label,
    required double value,
    required String suffix,
    required ValueChanged<double> onSubmit,
    required double width,
    bool isInt = false,
    Color accentColor = const Color(0xFF808088),
  }) {
    final isEditing = _editingField.value == fieldId;
    final displayValue = isInt
        ? value.toInt().toString()
        : (value == value.roundToDouble()
            ? value.toStringAsFixed(0)
            : value.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), ''));

    if (isEditing) {
      return SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label.isNotEmpty)
              Text(label, style: const TextStyle(
                color: Color(0xFF404048), fontSize: 7, fontWeight: FontWeight.w600,
              )),
            SizedBox(
              height: 18,
              child: TextField(
                controller: _inlineController,
                focusNode: _inlineFocus,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.\-]'))],
                style: TextStyle(
                  color: accentColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  border: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF4488FF)),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF4488FF)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF4488FF), width: 1.5),
                  ),
                  suffixText: suffix,
                  suffixStyle: TextStyle(
                    color: accentColor.withValues(alpha: 0.5),
                    fontSize: 7,
                  ),
                ),
                onSubmitted: (val) {
                  final parsed = double.tryParse(val);
                  if (parsed != null) onSubmit(parsed);
                  _editingField.value = null;
                },
                onTapOutside: (_) => _commitInlineEdit(),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => _startInlineEdit(fieldId, displayValue),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label.isNotEmpty)
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF404048),
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: accentColor.withValues(alpha: 0.05),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayValue,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 1),
                  Text(
                    suffix,
                    style: TextStyle(
                      color: accentColor.withValues(alpha: 0.5),
                      fontSize: 7,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startInlineEdit(String fieldId, String currentValue) {
    // Commit any previous edit first
    if (_editingField.value != null) {
      _commitInlineEdit();
    }
    _editingField.value = fieldId;
    _inlineController.text = currentValue;
    // Focus after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _inlineFocus.requestFocus();
        _inlineController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _inlineController.text.length,
        );
      }
    });
  }

  void _commitInlineEdit() {
    if (_editingField.value == null) return;
    _editingField.value = null;
  }

  Widget _intensitySlider(
    String label,
    double value,
    double min,
    double max,
    Color color,
    ValueChanged<double> onChanged, {
    bool isInt = false,
    VoidCallback? onChangeEnd,
  }) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF404048),
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                isInt ? value.toInt().toString() : value.toStringAsFixed(1),
                style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 8,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          SizedBox(
            height: 14,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                activeTrackColor: color.withValues(alpha: 0.6),
                inactiveTrackColor: const Color(0xFF2A2A32),
                thumbColor: color,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: (v) {
                  final rounded = isInt ? v.roundToDouble() : double.parse(v.toStringAsFixed(1));
                  onChanged(rounded);
                },
                onChangeEnd: onChangeEnd != null ? (_) => onChangeEnd() : null,
              ),
            ),
          ),
        ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UPDATE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void _updateRegularTier(WinTierDefinition tier, {
    String? displayLabel,
    double? fromMultiplier,
    double? toMultiplier,
    int? rollupDurationMs,
    int? rollupTickRate,
    int? particleBurstCount,
    bool syncStages = true,
  }) {
    final updated = tier.copyWith(
      displayLabel: displayLabel,
      fromMultiplier: fromMultiplier,
      toMultiplier: toMultiplier,
      rollupDurationMs: rollupDurationMs,
      rollupTickRate: rollupTickRate,
      particleBurstCount: particleBurstCount,
    );
    widget.projectProvider.updateRegularWinTier(tier.tierId, updated, syncStages: syncStages);

    // Chain ALL tiers: push values up/down so no gaps or overlaps
    if (fromMultiplier != null || toMultiplier != null) {
      final sorted = List<WinTierDefinition>.from(_regular.tiers)
        ..sort((a, b) => a.fromMultiplier.compareTo(b.fromMultiplier));
      final idx = sorted.indexWhere((t) => t.tierId == tier.tierId);
      if (idx >= 0) {
        final newFrom = fromMultiplier ?? tier.fromMultiplier;
        final newTo = toMultiplier ?? tier.toMultiplier;

        // Push all tiers BELOW: walk backwards, each tier's TO = next tier's FROM
        var boundary = newFrom;
        for (var i = idx - 1; i >= 0; i--) {
          final t = sorted[i];
          var tTo = boundary;
          var tFrom = t.fromMultiplier;
          if (tFrom > tTo) tFrom = tTo;
          widget.projectProvider.updateRegularWinTier(
            t.tierId, t.copyWith(fromMultiplier: tFrom, toMultiplier: tTo),
            syncStages: false,
          );
          boundary = tFrom;
        }

        // Push all tiers ABOVE: walk forwards, each tier's FROM = prev tier's TO
        boundary = newTo;
        for (var i = idx + 1; i < sorted.length; i++) {
          final t = sorted[i];
          var tFrom = boundary;
          var tTo = t.toMultiplier;
          if (tTo < tFrom) tTo = tFrom;
          widget.projectProvider.updateRegularWinTier(
            t.tierId, t.copyWith(fromMultiplier: tFrom, toMultiplier: tTo),
            syncStages: false,
          );
          boundary = tTo;
        }
      }
    }

    _bumpRevision();
  }

  void _updateBigWinTier(BigWinTierDefinition tier, {
    String? displayLabel,
    double? fromMultiplier,
    double? toMultiplier,
    int? durationMs,
    double? visualIntensity,
    double? particleMultiplier,
    double? audioIntensity,
    bool syncStages = true,
  }) {
    final updated = tier.copyWith(
      displayLabel: displayLabel,
      fromMultiplier: fromMultiplier,
      toMultiplier: toMultiplier,
      durationMs: durationMs,
      visualIntensity: visualIntensity,
      particleMultiplier: particleMultiplier,
      audioIntensity: audioIntensity,
    );
    widget.projectProvider.updateBigWinTier(tier.tierId, updated, syncStages: syncStages);

    // Chain ALL tiers: push values up/down so no gaps or overlaps
    if (fromMultiplier != null || toMultiplier != null) {
      final sorted = List<BigWinTierDefinition>.from(_bigWin.tiers)
        ..sort((a, b) => a.fromMultiplier.compareTo(b.fromMultiplier));
      final idx = sorted.indexWhere((t) => t.tierId == tier.tierId);
      if (idx >= 0) {
        final newFrom = fromMultiplier ?? tier.fromMultiplier;
        final newTo = toMultiplier ?? tier.toMultiplier;

        // Push all tiers BELOW
        var boundary = newFrom;
        for (var i = idx - 1; i >= 0; i--) {
          final t = sorted[i];
          var tTo = boundary;
          var tFrom = t.fromMultiplier;
          if (tFrom > tTo) tFrom = tTo;
          widget.projectProvider.updateBigWinTier(
            t.tierId, t.copyWith(fromMultiplier: tFrom, toMultiplier: tTo),
            syncStages: false,
          );
          boundary = tFrom;
        }

        // Push all tiers ABOVE (skip infinity toMultiplier)
        boundary = newTo;
        for (var i = idx + 1; i < sorted.length; i++) {
          final t = sorted[i];
          var tFrom = boundary;
          var tTo = t.toMultiplier;
          if (tTo != double.infinity && tTo < tFrom) tTo = tFrom;
          widget.projectProvider.updateBigWinTier(
            t.tierId, t.copyWith(fromMultiplier: tFrom, toMultiplier: tTo),
            syncStages: false,
          );
          if (tTo == double.infinity) break;
          boundary = tTo;
        }
      }
    }

    _bumpRevision();
  }

  void _updateBigWinTiming({int? introDurationMs, int? endDurationMs, int? fadeOutDurationMs}) {
    final updated = _bigWin.copyWith(
      introDurationMs: introDurationMs,
      endDurationMs: endDurationMs,
      fadeOutDurationMs: fadeOutDurationMs,
    );
    widget.projectProvider.setWinConfiguration(_config.copyWith(bigWins: updated));
    _bumpRevision();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _exportConfig() {
    final json = widget.projectProvider.exportWinConfigurationJson();
    Clipboard.setData(ClipboardData(text: json));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Win tier config copied to clipboard'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF1A1A24),
      ),
    );
  }

  void _importConfig() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text(
          'Import Win Tier Config',
          style: TextStyle(color: Color(0xFFD0D0D8), fontSize: 13),
        ),
        content: SizedBox(
          width: 400,
          height: 200,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            style: const TextStyle(
              color: Color(0xFFD0D0D8),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
            decoration: const InputDecoration(
              hintText: 'Paste JSON config here...',
              hintStyle: TextStyle(color: Color(0xFF404048)),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2A2A32)),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF808088))),
          ),
          TextButton(
            onPressed: () {
              final success = widget.projectProvider.importWinConfigurationJson(controller.text);
              Navigator.of(ctx).pop();
              if (success) _bumpRevision();
              if (!success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid JSON config'),
                    backgroundColor: Color(0xFF8B0000),
                  ),
                );
              }
            },
            child: Text('IMPORT', style: TextStyle(color: FluxForgeTheme.accentCyan)),
          ),
        ],
      ),
    );
  }

  void _resetConfig() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text(
          'Reset Win Tier Config?',
          style: TextStyle(color: Color(0xFFD0D0D8), fontSize: 13),
        ),
        content: const Text(
          'This will reset all win tier settings to factory defaults.',
          style: TextStyle(color: Color(0xFF808088), fontSize: 11),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF808088))),
          ),
          TextButton(
            onPressed: () {
              widget.projectProvider.resetWinConfiguration();
              _bumpRevision();
              Navigator.of(ctx).pop();
            },
            child: const Text('RESET', style: TextStyle(color: Color(0xFFFF6060))),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  Color _tierColor(int tierId) {
    return switch (tierId) {
      -1 => const Color(0xFF404048),
      0 => const Color(0xFF606068),
      1 => const Color(0xFF66BB6A),
      2 => const Color(0xFF42A5F5),
      3 => const Color(0xFFAB47BC),
      4 => const Color(0xFFFF7043),
      5 => const Color(0xFFFFCA28),
      _ => const Color(0xFF808088),
    };
  }

  Color _bigWinTierColor(int tierId) {
    return switch (tierId) {
      1 => const Color(0xFFFFAA00),
      2 => const Color(0xFFFF6600),
      3 => const Color(0xFFFF3366),
      4 => const Color(0xFFCC33FF),
      5 => const Color(0xFF00CCFF),
      _ => const Color(0xFFFFAA00),
    };
  }
}
