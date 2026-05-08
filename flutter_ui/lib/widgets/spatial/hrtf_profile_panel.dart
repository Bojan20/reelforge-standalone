/// HRTF Profile Panel — Anthropometric editor + database actions
///
/// Visualises and edits the eight anthropometric measurements that drive
/// the personalized HRTF generator (`rf_spatial::binaural::personalized`).
///
/// Layout:
///   ┌─ presets row ────────────── small / average / large / clamp ─┐
///   ├─ measurement sliders ────── 8 fields, hover tooltips ────────┤
///   ├─ database actions ───────── generate / save / load ──────────┤
///   └─ status footer ─────────── live metadata + error / sample rate┘
///
/// All numeric edits go through `HrtfProvider.updateField` so the Rust
/// clamp stays the single source of truth for valid ranges.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/hrtf_models.dart';
import '../../providers/hrtf_provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../common/flux_tooltip.dart';

class HrtfProfilePanel extends StatelessWidget {
  const HrtfProfilePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HrtfProvider>(
      builder: (context, p, _) => Container(
        color: FluxForgeTheme.bgDeep,
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(p),
              const SizedBox(height: 16),
              _buildPresets(context, p),
              const SizedBox(height: 16),
              _buildMeasurementSliders(p),
              const SizedBox(height: 16),
              _buildSampleRateRow(p),
              const SizedBox(height: 12),
              _buildActions(context, p),
              const SizedBox(height: 12),
              _buildStatus(p),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader(HrtfProvider p) {
    return Row(
      children: [
        Icon(
          Icons.spatial_audio_off_rounded,
          color: FluxForgeTheme.brandGoldBright.withValues(alpha: 0.85),
          size: 18,
        ),
        const SizedBox(width: 8),
        const Text(
          'PERSONALIZED HRTF',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: FluxForgeTheme.brandGoldBright,
            letterSpacing: 1.5,
          ),
        ),
        const Spacer(),
        if (p.metadata != null)
          Text(
            '${p.metadata!.measurementCount} dirs · '
            '${p.metadata!.filterLength} taps · '
            '${p.metadata!.sampleRate ~/ 1000}kHz',
            style: const TextStyle(
              fontSize: 9,
              color: FluxForgeTheme.textTertiary,
              fontFamily: 'JetBrainsMono',
              letterSpacing: 0.5,
            ),
          ),
      ],
    );
  }

  // ─── Presets ───────────────────────────────────────────────────────────

  Widget _buildPresets(BuildContext context, HrtfProvider p) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _presetChip(
          context, p, 'SMALL',
          AnthropometricProfile.small,
          tip: 'Smaller-than-average head & pinna (P5 female)',
        ),
        _presetChip(
          context, p, 'AVERAGE',
          AnthropometricProfile.cipicAverage,
          tip: 'CIPIC database average (European male)',
        ),
        _presetChip(
          context, p, 'LARGE',
          AnthropometricProfile.large,
          tip: 'Larger-than-average head & pinna (P95 male)',
        ),
        _actionChip(
          context,
          'CLAMP',
          icon: Icons.tune_rounded,
          tip: 'Pull all fields back into biologically plausible ranges',
          onTap: p.clampToValidRange,
        ),
      ],
    );
  }

  Widget _presetChip(
    BuildContext context,
    HrtfProvider p,
    String label,
    AnthropometricProfile profile, {
    required String tip,
  }) {
    final selected = p.profile == profile;
    return FluxTooltip(
      message: tip,
      child: GestureDetector(
        onTap: () => p.setProfile(profile),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? FluxForgeTheme.brandGold.withValues(alpha: 0.20)
                : const Color(0xFF14141C),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? FluxForgeTheme.brandGold
                  : FluxForgeTheme.brandGoldDark.withValues(alpha: 0.35),
              width: 0.6,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: selected
                  ? FluxForgeTheme.brandGoldBright
                  : FluxForgeTheme.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionChip(
    BuildContext context,
    String label, {
    required IconData icon,
    required String tip,
    required VoidCallback onTap,
  }) {
    return FluxTooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF14141C),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.35),
              width: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: FluxForgeTheme.accentCyan),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: FluxForgeTheme.accentCyan,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Measurement Sliders ───────────────────────────────────────────────

  Widget _buildMeasurementSliders(HrtfProvider p) {
    return Column(
      children: [
        _measurementSlider(
          'HEAD WIDTH', 'temple-to-temple distance',
          value: p.profile.headWidthMm,
          min: 120, max: 190, step: 1,
          unit: 'mm',
          onChanged: (v) => p.updateField(headWidthMm: v),
        ),
        _measurementSlider(
          'HEAD DEPTH', 'nasion-to-inion distance',
          value: p.profile.headDepthMm,
          min: 140, max: 250, step: 1,
          unit: 'mm',
          onChanged: (v) => p.updateField(headDepthMm: v),
        ),
        _measurementSlider(
          'PINNA HEIGHT', 'outer ear top-to-bottom',
          value: p.profile.pinnaHeightMm,
          min: 35, max: 95, step: 0.5,
          unit: 'mm',
          onChanged: (v) => p.updateField(pinnaHeightMm: v),
        ),
        _measurementSlider(
          'PINNA WIDTH', 'outer ear front-to-back',
          value: p.profile.pinnaWidthMm,
          min: 15, max: 45, step: 0.5,
          unit: 'mm',
          onChanged: (v) => p.updateField(pinnaWidthMm: v),
        ),
        _measurementSlider(
          'CAVUM CONCHA DEPTH', 'pinna bowl depth — primary elevation cue',
          value: p.profile.cavumConchaDepthMm,
          min: 4, max: 25, step: 0.25,
          unit: 'mm',
          onChanged: (v) => p.updateField(cavumConchaDepthMm: v),
        ),
        _measurementSlider(
          'HEAD CIRCUMFERENCE', 'supraorbital circumference',
          value: p.profile.headCircumferenceMm,
          min: 480, max: 680, step: 1,
          unit: 'mm',
          onChanged: (v) => p.updateField(headCircumferenceMm: v),
        ),
        _measurementSlider(
          'INTER-TRAGAL DISTANCE', 'tragus-to-tragus — drives ITD',
          value: p.profile.interTragalDistanceMm,
          min: 100, max: 180, step: 0.5,
          unit: 'mm',
          onChanged: (v) => p.updateField(interTragalDistanceMm: v),
        ),
        _measurementSlider(
          'NOSE BRIDGE PROMINENCE', 'glabella forward projection',
          value: p.profile.noseBridgeProminenceMm,
          min: 4, max: 28, step: 0.25,
          unit: 'mm',
          onChanged: (v) => p.updateField(noseBridgeProminenceMm: v),
        ),
      ],
    );
  }

  Widget _measurementSlider(
    String label,
    String tooltip, {
    required double value,
    required double min,
    required double max,
    required double step,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    final divisions = ((max - min) / step).round();
    return FluxTooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 180,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: FluxForgeTheme.textTertiary,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  activeTrackColor: FluxForgeTheme.brandGold,
                  inactiveTrackColor:
                      FluxForgeTheme.brandGoldDark.withValues(alpha: 0.25),
                  thumbColor: FluxForgeTheme.brandGoldBright,
                  overlayColor:
                      FluxForgeTheme.brandGold.withValues(alpha: 0.18),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              child: Text(
                '${value.toStringAsFixed(step >= 1 ? 0 : 1)} $unit',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: FluxForgeTheme.textPrimary,
                  fontFamily: 'JetBrainsMono',
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Sample Rate ───────────────────────────────────────────────────────

  Widget _buildSampleRateRow(HrtfProvider p) {
    const rates = [44100, 48000, 88200, 96000];
    return Row(
      children: [
        const SizedBox(
          width: 180,
          child: Text(
            'SAMPLE RATE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: FluxForgeTheme.textTertiary,
              letterSpacing: 1.1,
            ),
          ),
        ),
        for (final hz in rates) ...[
          GestureDetector(
            onTap: () => p.setSampleRate(hz),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: p.sampleRate == hz
                    ? FluxForgeTheme.brandGold.withValues(alpha: 0.18)
                    : const Color(0xFF14141C),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: p.sampleRate == hz
                      ? FluxForgeTheme.brandGold
                      : FluxForgeTheme.brandGoldDark.withValues(alpha: 0.30),
                  width: 0.5,
                ),
              ),
              child: Text(
                '${hz ~/ 1000}k',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: p.sampleRate == hz
                      ? FluxForgeTheme.brandGoldBright
                      : FluxForgeTheme.textSecondary,
                  fontFamily: 'JetBrainsMono',
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Actions ───────────────────────────────────────────────────────────

  Widget _buildActions(BuildContext context, HrtfProvider p) {
    return Row(
      children: [
        _bigButton(
          'GENERATE',
          icon: Icons.auto_awesome_rounded,
          color: FluxForgeTheme.accentCyan,
          tip: 'Materialise the personalized HRTF database '
              'into the spatial engine',
          onTap: () async {
            final ok = await p.generate();
            if (context.mounted) {
              _showSnack(context, ok
                  ? 'HRTF database generated'
                  : (p.errorMessage ?? 'Generate failed'));
            }
          },
        ),
        const SizedBox(width: 8),
        _bigButton(
          'SAVE',
          icon: Icons.save_alt_rounded,
          color: FluxForgeTheme.accentGreen,
          tip: 'Save the current database to a .ffhrtf bundle',
          onTap: p.hasGenerated
              ? () => _saveDialog(context, p)
              : null,
        ),
        const SizedBox(width: 8),
        _bigButton(
          'LOAD',
          icon: Icons.folder_open_rounded,
          color: FluxForgeTheme.accentOrange,
          tip: 'Load a .ffhrtf bundle from disk',
          onTap: () => _loadDialog(context, p),
        ),
      ],
    );
  }

  Widget _bigButton(
    String label, {
    required IconData icon,
    required Color color,
    required String tip,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Expanded(
      child: FluxTooltip(
        message: tip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              color: enabled
                  ? color.withValues(alpha: 0.10)
                  : const Color(0xFF14141C),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: enabled
                    ? color.withValues(alpha: 0.45)
                    : FluxForgeTheme.brandGoldDark.withValues(alpha: 0.20),
                width: 0.6,
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: enabled ? color : FluxForgeTheme.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: enabled ? color : FluxForgeTheme.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Status ────────────────────────────────────────────────────────────

  Widget _buildStatus(HrtfProvider p) {
    final color = switch (p.status) {
      HrtfStatus.none => FluxForgeTheme.textTertiary,
      HrtfStatus.ready => FluxForgeTheme.accentGreen,
      HrtfStatus.error => FluxForgeTheme.accentRed,
    };
    final text = switch (p.status) {
      HrtfStatus.none => 'No database generated yet — press GENERATE',
      HrtfStatus.ready =>
        p.lastSavedPath != null ? 'Saved → ${p.lastSavedPath}' : 'Ready',
      HrtfStatus.error => p.errorMessage ?? 'Unknown error',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF14141C),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color.withValues(alpha: 0.30),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontFamily: 'JetBrainsMono',
                letterSpacing: 0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Dialogs ───────────────────────────────────────────────────────────

  Future<void> _saveDialog(BuildContext context, HrtfProvider p) async {
    final pathCtl = TextEditingController(
      text: p.lastSavedPath ?? '~/Library/Application Support/FluxForge Studio/hrtf/custom',
    );
    final subjectCtl = TextEditingController(text: p.subjectId ?? 'custom');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        title: const Text('Save HRTF bundle',
            style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pathCtl,
              decoration: const InputDecoration(labelText: 'Directory path'),
            ),
            TextField(
              controller: subjectCtl,
              decoration: const InputDecoration(labelText: 'Subject ID'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (result == true) {
      final ok = await p.saveFfhrtf(
        _expandHome(pathCtl.text.trim()),
        subjectId: subjectCtl.text.trim().isEmpty
            ? 'custom'
            : subjectCtl.text.trim(),
      );
      if (context.mounted) {
        _showSnack(context, ok
            ? 'HRTF saved'
            : (p.errorMessage ?? 'Save failed'));
      }
    }
  }

  Future<void> _loadDialog(BuildContext context, HrtfProvider p) async {
    final pathCtl = TextEditingController(
      text: p.lastSavedPath ?? '~/Library/Application Support/FluxForge Studio/hrtf/custom',
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        title: const Text('Load HRTF bundle',
            style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: TextField(
          controller: pathCtl,
          decoration: const InputDecoration(labelText: 'Directory path'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Load')),
        ],
      ),
    );
    if (result == true) {
      final ok = await p.loadFfhrtf(_expandHome(pathCtl.text.trim()));
      if (context.mounted) {
        _showSnack(context, ok
            ? 'HRTF loaded'
            : (p.errorMessage ?? 'Load failed'));
      }
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  String _expandHome(String p) {
    if (!p.startsWith('~')) return p;
    final home = const String.fromEnvironment('HOME');
    if (home.isEmpty) {
      // Fallback for runtime: read from Platform.environment via dart:io
      // is not available in this widget context, so leave as-is and let
      // Rust's `~` expansion (none in core) fail loud.
      return p;
    }
    return p.replaceFirst('~', home);
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: FluxForgeTheme.bgDeep,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

