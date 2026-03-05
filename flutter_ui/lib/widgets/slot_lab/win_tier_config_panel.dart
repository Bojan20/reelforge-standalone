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
  bool _showBigWin = false;
  bool _showPresets = false;

  SlotWinConfiguration get _config => widget.projectProvider.winConfiguration;
  RegularWinTierConfig get _regular => _config.regularWins;
  BigWinConfig get _bigWin => _config.bigWins;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with presets/export
        _buildHeader(),
        // Content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(6),
            children: [
              if (_showPresets) ...[
                _buildPresetsSection(),
                const SizedBox(height: 8),
              ],
              // Regular win tiers
              _buildSectionHeader(
                'REGULAR WIN TIERS',
                icon: Icons.emoji_events_outlined,
                color: const Color(0xFF66BB6A),
                trailing: Text(
                  '${_regular.tiers.length} tiers',
                  style: const TextStyle(color: Color(0xFF606068), fontSize: 9),
                ),
              ),
              const SizedBox(height: 4),
              ..._regular.tiers.map(_buildRegularTierRow),
              const SizedBox(height: 12),
              // Big win threshold
              _buildBigWinThresholdRow(),
              const SizedBox(height: 8),
              // Big win tiers
              _buildSectionHeader(
                'BIG WIN TIERS',
                icon: Icons.stars,
                color: const Color(0xFFFFAA00),
                trailing: GestureDetector(
                  onTap: () => setState(() => _showBigWin = !_showBigWin),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _showBigWin ? 'COLLAPSE' : 'EXPAND',
                        style: const TextStyle(
                          color: Color(0xFF606068),
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        _showBigWin ? Icons.expand_less : Icons.expand_more,
                        size: 12,
                        color: const Color(0xFF606068),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              if (_showBigWin) ...[
                _buildBigWinTimingRow(),
                const SizedBox(height: 4),
                ..._bigWin.tiers.map(_buildBigWinTierRow),
              ] else ...[
                // Compact summary
                ..._bigWin.tiers.map(_buildBigWinTierCompact),
              ],
              const SizedBox(height: 12),
              // Validation
              _buildValidationSection(),
            ],
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
          _headerButton(
            icon: Icons.style,
            label: 'PRESETS',
            isActive: _showPresets,
            onTap: () => setState(() => _showPresets = !_showPresets),
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
                  setState(() {});
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
  // REGULAR WIN TIER ROW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRegularTierRow(WinTierDefinition tier) {
    final tierName = tier.stageName;
    final color = _tierColor(tier.tierId);

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF161620),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
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
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                tierName,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _editableField(
                  value: tier.displayLabel.isEmpty ? '(no label)' : tier.displayLabel,
                  hint: 'Label',
                  onSubmit: (val) => _updateRegularTier(tier, displayLabel: val),
                  dim: tier.displayLabel.isEmpty,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Row 2: Multiplier range
          Row(
            children: [
              _numericField(
                label: 'FROM',
                value: tier.fromMultiplier,
                suffix: 'x',
                onSubmit: (val) => _updateRegularTier(tier, fromMultiplier: val),
                width: 50,
              ),
              const SizedBox(width: 4),
              const Text('→', style: TextStyle(color: Color(0xFF404048), fontSize: 10)),
              const SizedBox(width: 4),
              _numericField(
                label: 'TO',
                value: tier.toMultiplier,
                suffix: 'x',
                onSubmit: (val) => _updateRegularTier(tier, toMultiplier: val),
                width: 50,
              ),
              const Spacer(),
              _numericField(
                label: 'ROLLUP',
                value: tier.rollupDurationMs.toDouble(),
                suffix: 'ms',
                onSubmit: (val) => _updateRegularTier(tier, rollupDurationMs: val.toInt()),
                width: 55,
                isInt: true,
              ),
              const SizedBox(width: 4),
              _numericField(
                label: 'TICK',
                value: tier.rollupTickRate.toDouble(),
                suffix: '/s',
                onSubmit: (val) => _updateRegularTier(tier, rollupTickRate: val.toInt()),
                width: 40,
                isInt: true,
              ),
            ],
          ),
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
          _numericField(
            label: '',
            value: _bigWin.threshold,
            suffix: 'x bet',
            onSubmit: (val) {
              widget.projectProvider.setBigWinThreshold(val);
              setState(() {});
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
          _numericField(
            label: 'INTRO',
            value: _bigWin.introDurationMs.toDouble(),
            suffix: 'ms',
            onSubmit: (val) => _updateBigWinTiming(introDurationMs: val.toInt()),
            width: 55,
            isInt: true,
          ),
          const SizedBox(width: 6),
          _numericField(
            label: 'END',
            value: _bigWin.endDurationMs.toDouble(),
            suffix: 'ms',
            onSubmit: (val) => _updateBigWinTiming(endDurationMs: val.toInt()),
            width: 55,
            isInt: true,
          ),
          const SizedBox(width: 6),
          _numericField(
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

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF161620),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
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
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(
                'TIER ${tier.tierId}',
                style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _editableField(
                  value: tier.displayLabel,
                  hint: 'Label',
                  onSubmit: (val) => _updateBigWinTier(tier, displayLabel: val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Row 2: Multiplier range + duration
          Row(
            children: [
              _numericField(
                label: 'FROM',
                value: tier.fromMultiplier,
                suffix: 'x',
                onSubmit: (val) => _updateBigWinTier(tier, fromMultiplier: val),
                width: 50,
              ),
              const SizedBox(width: 4),
              const Text('→', style: TextStyle(color: Color(0xFF404048), fontSize: 10)),
              const SizedBox(width: 4),
              _numericField(
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
              _numericField(
                label: 'DUR',
                value: tier.durationMs.toDouble(),
                suffix: 'ms',
                onSubmit: (val) => _updateBigWinTier(tier, durationMs: val.toInt()),
                width: 55,
                isInt: true,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Row 3: Intensities
          Row(
            children: [
              _intensitySlider('VIS', tier.visualIntensity, 1.0, 2.0, color,
                  (val) => _updateBigWinTier(tier, visualIntensity: val)),
              const SizedBox(width: 4),
              _intensitySlider('PART', tier.particleMultiplier, 0.5, 4.0, color,
                  (val) => _updateBigWinTier(tier, particleMultiplier: val)),
              const SizedBox(width: 4),
              _intensitySlider('AUD', tier.audioIntensity, 0.5, 2.0, color,
                  (val) => _updateBigWinTier(tier, audioIntensity: val)),
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
  // SHARED FIELD WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _editableField({
    required String value,
    required String hint,
    required ValueChanged<String> onSubmit,
    bool dim = false,
  }) {
    return GestureDetector(
      onDoubleTap: () => _showTextEditDialog(value, hint, onSubmit),
      child: Text(
        value,
        style: TextStyle(
          color: dim ? const Color(0xFF404048) : const Color(0xFF808088),
          fontSize: 9,
          fontStyle: dim ? FontStyle.italic : FontStyle.normal,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _numericField({
    required String label,
    required double value,
    required String suffix,
    required ValueChanged<double> onSubmit,
    required double width,
    bool isInt = false,
    Color accentColor = const Color(0xFF808088),
  }) {
    final displayValue = isInt
        ? value.toInt().toString()
        : (value == value.roundToDouble()
            ? value.toStringAsFixed(0)
            : value.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), ''));

    return GestureDetector(
      onDoubleTap: () => _showNumericEditDialog(value, label, suffix, onSubmit),
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
            Row(
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
          ],
        ),
      ),
    );
  }

  Widget _intensitySlider(
    String label,
    double value,
    double min,
    double max,
    Color color,
    ValueChanged<double> onChanged,
  ) {
    return Expanded(
      child: Column(
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
                value.toStringAsFixed(1),
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
                  onChanged(double.parse(v.toStringAsFixed(1)));
                  setState(() {});
                },
              ),
            ),
          ),
        ],
      ),
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
  }) {
    final updated = tier.copyWith(
      displayLabel: displayLabel,
      fromMultiplier: fromMultiplier,
      toMultiplier: toMultiplier,
      rollupDurationMs: rollupDurationMs,
      rollupTickRate: rollupTickRate,
    );
    widget.projectProvider.updateRegularWinTier(tier.tierId, updated);
    setState(() {});
  }

  void _updateBigWinTier(BigWinTierDefinition tier, {
    String? displayLabel,
    double? fromMultiplier,
    double? toMultiplier,
    int? durationMs,
    double? visualIntensity,
    double? particleMultiplier,
    double? audioIntensity,
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
    widget.projectProvider.updateBigWinTier(tier.tierId, updated);
    setState(() {});
  }

  void _updateBigWinTiming({int? introDurationMs, int? endDurationMs, int? fadeOutDurationMs}) {
    final updated = _bigWin.copyWith(
      introDurationMs: introDurationMs,
      endDurationMs: endDurationMs,
      fadeOutDurationMs: fadeOutDurationMs,
    );
    widget.projectProvider.setWinConfiguration(_config.copyWith(bigWins: updated));
    setState(() {});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DIALOGS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showTextEditDialog(String currentValue, String hint, ValueChanged<String> onSubmit) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: Text(hint, style: const TextStyle(color: Color(0xFFD0D0D8), fontSize: 13)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFD0D0D8), fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF404048)),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF2A2A32)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: FluxForgeTheme.accentCyan),
            ),
          ),
          onSubmitted: (val) {
            onSubmit(val);
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF808088))),
          ),
          TextButton(
            onPressed: () {
              onSubmit(controller.text);
              Navigator.of(ctx).pop();
            },
            child: Text('OK', style: TextStyle(color: FluxForgeTheme.accentCyan)),
          ),
        ],
      ),
    );
  }

  void _showNumericEditDialog(double currentValue, String label, String suffix, ValueChanged<double> onSubmit) {
    final controller = TextEditingController(text: currentValue.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: Text(
          '$label ($suffix)',
          style: const TextStyle(color: Color(0xFFD0D0D8), fontSize: 13),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.\-]'))],
          style: const TextStyle(color: Color(0xFFD0D0D8), fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'Enter value',
            hintStyle: const TextStyle(color: Color(0xFF404048)),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF2A2A32)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: FluxForgeTheme.accentCyan),
            ),
          ),
          onSubmitted: (val) {
            final parsed = double.tryParse(val);
            if (parsed != null) onSubmit(parsed);
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF808088))),
          ),
          TextButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text);
              if (parsed != null) onSubmit(parsed);
              Navigator.of(ctx).pop();
            },
            child: Text('OK', style: TextStyle(color: FluxForgeTheme.accentCyan)),
          ),
        ],
      ),
    );
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
              if (success) {
                setState(() {});
              } else {
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
              Navigator.of(ctx).pop();
              setState(() {});
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
