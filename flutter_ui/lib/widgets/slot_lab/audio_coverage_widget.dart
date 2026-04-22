// AudioCoverageWidget — Compact badge + expandable breakdown dialog
//
// Dual-source coverage:
//   1. UI slot assignments (SlotLabProjectProvider.getCoverageBySection)
//   2. Rust canonical assets (SlotLabV2FFI.getAudioCoverage + getMissingAssets)
//
// Displays as a compact badge in ROW 2 context bar.
// Click → full breakdown dialog with per-section bars + missing assets list.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/slot_lab_project_provider.dart';
import '../../src/rust/native_ffi.dart';
import '../../src/rust/slot_lab_v2_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Compact audio coverage badge for status bars.
///
/// Shows overall coverage %, colored progress bar, and opens
/// detailed breakdown dialog on tap.
class AudioCoverageWidget extends StatelessWidget {
  const AudioCoverageWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SlotLabProjectProvider>(
      builder: (ctx, provider, _) {
        final sectionData = provider.getCoverageBySection();

        // Compute overall
        int totalAssigned = 0;
        int totalSlots = 0;
        for (final section in sectionData.values) {
          totalAssigned += section['assigned'] ?? 0;
          totalSlots += section['total'] ?? 0;
        }
        final percent =
            totalSlots > 0 ? (totalAssigned / totalSlots * 100).round() : 0;

        // Color by health
        final progressColor = _healthColor(percent);

        return Tooltip(
          message:
              'Audio Coverage: $totalAssigned / $totalSlots slots assigned\n'
              'Click for full breakdown + missing assets',
          waitDuration: const Duration(milliseconds: 300),
          child: GestureDetector(
            onTap: () => _showBreakdownDialog(context, provider),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: progressColor.withValues(alpha: 0.35),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Icon(
                    percent >= 100
                        ? Icons.check_circle_outline
                        : Icons.graphic_eq,
                    size: 11,
                    color: progressColor,
                  ),
                  const SizedBox(width: 5),
                  // Count
                  Text(
                    '$totalAssigned/$totalSlots',
                    style: TextStyle(
                      color: progressColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                  const SizedBox(width: 5),
                  // Mini arc progress
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CustomPaint(
                      painter: _MiniArcPainter(
                        progress: (percent / 100).clamp(0.0, 1.0),
                        color: progressColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Percent
                  Text(
                    '$percent%',
                    style: TextStyle(
                      color: progressColor.withValues(alpha: 0.7),
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'SpaceGrotesk',
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

  static Color _healthColor(int percent) {
    if (percent >= 80) return FluxForgeTheme.accentGreen;
    if (percent >= 50) return FluxForgeTheme.accentYellow;
    if (percent >= 25) return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentRed;
  }

  void _showBreakdownDialog(
      BuildContext context, SlotLabProjectProvider provider) {
    showDialog(
      context: context,
      builder: (_) => _AudioCoverageDialog(provider: provider),
    );
  }
}

/// Mini circular arc painter for the badge
class _MiniArcPainter extends CustomPainter {
  final double progress;
  final Color color;

  _MiniArcPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;

    // Track
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_MiniArcPainter old) =>
      old.progress != progress || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Full Breakdown Dialog
// ═══════════════════════════════════════════════════════════════════════════════

class _AudioCoverageDialog extends StatefulWidget {
  final SlotLabProjectProvider provider;

  const _AudioCoverageDialog({required this.provider});

  @override
  State<_AudioCoverageDialog> createState() => _AudioCoverageDialogState();
}

class _AudioCoverageDialogState extends State<_AudioCoverageDialog> {
  List<String> _missingAssets = [];
  double _canonicalCoverage = 0.0;
  bool _loadedCanonical = false;
  String? _expandedCategory;

  @override
  void initState() {
    super.initState();
    _loadCanonicalCoverage();
  }

  void _loadCanonicalCoverage() {
    try {
      final ffi = NativeFFI.instance;

      // Gather all assigned asset IDs from provider
      final assignedIds = <String>[];
      final assignments = widget.provider.getAudioAssignmentCounts();
      // The provider tracks by stage, we need the actual assigned asset filenames
      // For canonical check, we use the stage IDs as rough proxy
      for (final entry in assignments.entries) {
        if (!entry.key.endsWith('_total')) {
          assignedIds.add(entry.key);
        }
      }

      _canonicalCoverage = ffi.getAudioCoverage(assignedIds);
      _missingAssets = ffi.getMissingAssets(assignedIds);
      _loadedCanonical = true;
    } catch (_) {
      _loadedCanonical = false;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sectionData = widget.provider.getCoverageBySection();
    final sectionInfo = SlotLabProjectProvider.getSectionInfo();

    // Overall totals
    int totalAssigned = 0;
    int totalSlots = 0;
    for (final section in sectionData.values) {
      totalAssigned += section['assigned'] ?? 0;
      totalSlots += section['total'] ?? 0;
    }
    final percent =
        totalSlots > 0 ? (totalAssigned / totalSlots * 100).round() : 0;
    final progressColor = AudioCoverageWidget._healthColor(percent);

    // Group missing assets by prefix (category)
    final missingByCategory = <String, List<String>>{};
    for (final id in _missingAssets) {
      final prefix = id.contains('_') ? id.substring(0, id.indexOf('_')) : 'other';
      missingByCategory.putIfAbsent(prefix, () => []).add(id);
    }

    return Dialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgMid,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.graphic_eq, color: progressColor, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Audio Coverage',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
                  ),
                  // Overall badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: progressColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: progressColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '$percent%',
                      style: TextStyle(
                        color: progressColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Section Breakdown ──
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shrinkWrap: true,
                children: [
                  // Overall progress bar
                  _buildOverallBar(totalAssigned, totalSlots, progressColor),
                  const SizedBox(height: 12),

                  // Canonical coverage (Rust engine)
                  if (_loadedCanonical) ...[
                    _buildCanonicalRow(),
                    const SizedBox(height: 12),
                  ],

                  // Per-section bars
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      'BY SECTION',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
                  ),
                  for (final (id, name, _) in sectionInfo)
                    _buildSectionRow(
                      name,
                      sectionData[id]?['assigned'] ?? 0,
                      sectionData[id]?['total'] ?? 0,
                    ),

                  // Missing assets
                  if (_missingAssets.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Text(
                            'MISSING ASSETS',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                              fontFamily: 'SpaceGrotesk',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.accentRed
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_missingAssets.length}',
                              style: TextStyle(
                                color: FluxForgeTheme.accentRed,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'SpaceGrotesk',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final entry in missingByCategory.entries)
                      _buildMissingCategory(entry.key, entry.value),
                  ],
                ],
              ),
            ),

            // ── Footer ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Close',
                      style: TextStyle(fontFamily: 'SpaceGrotesk'),
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

  Widget _buildOverallBar(int assigned, int total, Color color) {
    final frac = total > 0 ? (assigned / total).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'UI Slots Assigned',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
                fontFamily: 'SpaceGrotesk',
              ),
            ),
            Text(
              '$assigned / $total',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'SpaceGrotesk',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: frac,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildCanonicalRow() {
    final pct = _canonicalCoverage.round();
    final color = AudioCoverageWidget._healthColor(pct);
    final frac = (_canonicalCoverage / 100).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Canonical Assets',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontFamily: 'SpaceGrotesk',
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message:
                      'Coverage against the engine\'s canonical asset list\n'
                      '(${_missingAssets.length} missing of ${_missingAssets.length + ((_canonicalCoverage / 100 * _missingAssets.length) / (1 - _canonicalCoverage / 100 + 0.001)).round()} total)',
                  child: Icon(
                    Icons.info_outline,
                    size: 11,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
            Text(
              '$pct%',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'SpaceGrotesk',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: frac,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionRow(String name, int assigned, int total) {
    final pct = total > 0 ? (assigned / total * 100).round() : 0;
    final color = AudioCoverageWidget._healthColor(pct);
    final frac = total > 0 ? (assigned / total).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              name,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 10,
                fontFamily: 'SpaceGrotesk',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: frac,
                backgroundColor: Colors.white.withValues(alpha: 0.04),
                valueColor: AlwaysStoppedAnimation(color.withValues(alpha: 0.6)),
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(
              '$assigned/$total',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.w500,
                fontFamily: 'SpaceGrotesk',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMissingCategory(String prefix, List<String> assets) {
    final isExpanded = _expandedCategory == prefix;
    final categoryLabel = _categoryLabel(prefix);
    final categoryColor = _categoryColor(prefix);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _expandedCategory = isExpanded ? null : prefix;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 14,
                  color: categoryColor.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  categoryLabel,
                  style: TextStyle(
                    color: categoryColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SpaceGrotesk',
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${assets.length}',
                  style: TextStyle(
                    color: categoryColor.withValues(alpha: 0.5),
                    fontSize: 9,
                    fontFamily: 'SpaceGrotesk',
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: assets.map((id) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgSurface,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: FluxForgeTheme.accentRed.withValues(alpha: 0.2),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    id,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 8,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  String _categoryLabel(String prefix) {
    return switch (prefix) {
      'sfx' => 'Sound Effects',
      'mus' => 'Music',
      'amb' => 'Ambience',
      'trn' => 'Transitions',
      'ui' => 'UI Sounds',
      _ => prefix.toUpperCase(),
    };
  }

  Color _categoryColor(String prefix) {
    return switch (prefix) {
      'sfx' => FluxForgeTheme.accentOrange,
      'mus' => FluxForgeTheme.accentBlue,
      'amb' => FluxForgeTheme.accentCyan,
      'trn' => FluxForgeTheme.accentPurple,
      'ui' => FluxForgeTheme.accentYellow,
      _ => FluxForgeTheme.accentGreen,
    };
  }
}
