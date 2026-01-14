// Clip Gain Envelope Panel
//
// Per-clip gain automation (pre-fader):
// - Volume envelope drawn directly on clip
// - Non-destructive gain changes
// - Cubase "Volume Curve" / Pro Tools "Clip Gain Line"

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/clip_gain_envelope_provider.dart';
import '../../theme/fluxforge_theme.dart';

class ClipGainEnvelopePanel extends StatelessWidget {
  const ClipGainEnvelopePanel({super.key});

  static const Color _accentColor = Color(0xFFFFDD40); // Yellow/Gold

  @override
  Widget build(BuildContext context) {
    return Consumer<ClipGainEnvelopeProvider>(
      builder: (context, provider, _) {
        return Container(
          color: FluxForgeTheme.backgroundDeep,
          child: Column(
            children: [
              _buildHeader(provider),
              Expanded(
                child: Row(
                  children: [
                    // Left: Clip list
                    _buildClipList(provider),
                    // Center: Envelope editor
                    Expanded(child: _buildEnvelopeEditor(context, provider)),
                    // Right: Point inspector
                    _buildPointInspector(context, provider),
                  ],
                ),
              ),
              _buildFooter(context, provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(ClipGainEnvelopeProvider provider) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.backgroundMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.backgroundDeep, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Enable toggle
          Switch(
            value: provider.enabled,
            onChanged: (v) => provider.setEnabled(v),
            activeColor: _accentColor,
          ),
          const SizedBox(width: 8),
          Text(
            'CLIP GAIN ENVELOPE',
            style: TextStyle(
              color: provider.enabled ? _accentColor : FluxForgeTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Show envelopes toggle
          GestureDetector(
            onTap: () => provider.toggleShowEnvelopes(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: provider.showEnvelopes
                    ? _accentColor.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: provider.showEnvelopes
                      ? _accentColor
                      : FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    provider.showEnvelopes ? Icons.visibility : Icons.visibility_off,
                    size: 14,
                    color: provider.showEnvelopes ? _accentColor : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Show',
                    style: TextStyle(
                      color: provider.showEnvelopes ? _accentColor : FluxForgeTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Editing indicator
          if (provider.editingClipId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentGreen.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Editing',
                style: TextStyle(
                  color: FluxForgeTheme.accentGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClipList(ClipGainEnvelopeProvider provider) {
    // Mock clip list - in real app would come from project
    final clips = [
      _MockClip('clip_1', 'Vocal Take 1', true),
      _MockClip('clip_2', 'Vocal Take 2', true),
      _MockClip('clip_3', 'Guitar Riff', false),
      _MockClip('clip_4', 'Drums Loop', true),
      _MockClip('clip_5', 'Bass Line', false),
    ];

    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: FluxForgeTheme.backgroundDeep,
        border: Border(
          right: BorderSide(color: FluxForgeTheme.backgroundMid, width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildSectionHeader('CLIPS'),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: clips.length,
              itemBuilder: (context, index) {
                final clip = clips[index];
                final hasEnvelope = provider.hasEnvelope(clip.id);
                final isEditing = provider.editingClipId == clip.id;

                return GestureDetector(
                  onTap: () {
                    if (isEditing) {
                      provider.stopEditing();
                    } else {
                      provider.startEditing(clip.id);
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isEditing
                          ? _accentColor.withValues(alpha: 0.2)
                          : FluxForgeTheme.backgroundMid,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isEditing ? _accentColor : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Has envelope indicator
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: hasEnvelope ? _accentColor : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: hasEnvelope
                                  ? _accentColor
                                  : FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                clip.name,
                                style: TextStyle(
                                  color: isEditing
                                      ? _accentColor
                                      : FluxForgeTheme.textPrimary,
                                  fontSize: 11,
                                  fontWeight: isEditing ? FontWeight.bold : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (hasEnvelope)
                                Text(
                                  '${provider.getEnvelope(clip.id)?.pointCount ?? 0} points',
                                  style: TextStyle(
                                    color: FluxForgeTheme.textSecondary,
                                    fontSize: 9,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (clip.hasAudio)
                          Icon(
                            Icons.graphic_eq,
                            size: 12,
                            color: FluxForgeTheme.textSecondary,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvelopeEditor(BuildContext context, ClipGainEnvelopeProvider provider) {
    final clipId = provider.editingClipId;

    if (clipId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline,
              size: 48,
              color: FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Select a Clip',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Click on a clip to edit its gain envelope',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    final envelope = provider.getEnvelope(clipId);

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.backgroundMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.textSecondary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.backgroundDeep,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                // Tool buttons
                _buildToolButton(
                  'Draw',
                  Icons.edit,
                  true,
                  () {},
                ),
                const SizedBox(width: 4),
                _buildToolButton(
                  'Select',
                  Icons.select_all,
                  false,
                  () {},
                ),
                const SizedBox(width: 4),
                _buildToolButton(
                  'Erase',
                  Icons.auto_fix_off,
                  false,
                  () {},
                ),
                const Spacer(),
                // Curve type
                Text(
                  'Curve:',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 8),
                ...GainEnvelopeCurve.values.map((curve) => _buildCurveButton(
                  curve,
                  GainEnvelopeCurve.linear, // Current selected
                )),
              ],
            ),
          ),
          // Canvas
          Expanded(
            child: GestureDetector(
              onTapUp: (details) {
                final box = context.findRenderObject() as RenderBox;
                final localPos = box.globalToLocal(details.globalPosition);
                final size = box.size;

                // Calculate position (0-1)
                final position = (localPos.dx / size.width).clamp(0.0, 1.0);
                // Calculate gain (-60 to +12)
                final gain = 12.0 - (localPos.dy / size.height) * 72.0;

                provider.addPoint(
                  clipId,
                  position: position,
                  gain: gain.clamp(-60.0, 12.0),
                );
              },
              child: CustomPaint(
                size: Size.infinite,
                painter: _EnvelopePainter(
                  envelope: envelope,
                  selectedPointIds: provider.selectedPointIds,
                  accentColor: _accentColor,
                ),
              ),
            ),
          ),
          // dB scale
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.backgroundDeep,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('+12 dB', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 9)),
                Text('+6 dB', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 9)),
                Text('0 dB', style: TextStyle(color: _accentColor, fontSize: 9, fontWeight: FontWeight.bold)),
                Text('-6 dB', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 9)),
                Text('-12 dB', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 9)),
                Text('-∞', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton(String tooltip, IconData icon, bool isActive, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive ? _accentColor.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? _accentColor : Colors.transparent,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? _accentColor : FluxForgeTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildCurveButton(GainEnvelopeCurve curve, GainEnvelopeCurve selected) {
    final isSelected = curve == selected;
    final icon = _getCurveIcon(curve);

    return GestureDetector(
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? _accentColor.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? _accentColor : FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
          ),
        ),
        child: Icon(
          icon,
          size: 12,
          color: isSelected ? _accentColor : FluxForgeTheme.textSecondary,
        ),
      ),
    );
  }

  IconData _getCurveIcon(GainEnvelopeCurve curve) {
    switch (curve) {
      case GainEnvelopeCurve.linear:
        return Icons.show_chart;
      case GainEnvelopeCurve.exponential:
        return Icons.trending_up;
      case GainEnvelopeCurve.logarithmic:
        return Icons.trending_down;
      case GainEnvelopeCurve.sCurve:
        return Icons.waves;
    }
  }

  Widget _buildPointInspector(BuildContext context, ClipGainEnvelopeProvider provider) {
    final clipId = provider.editingClipId;
    final envelope = clipId != null ? provider.getEnvelope(clipId) : null;
    final selectedPoints = envelope?.selectedPoints ?? [];

    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: FluxForgeTheme.backgroundDeep,
        border: Border(
          left: BorderSide(color: FluxForgeTheme.backgroundMid, width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildSectionHeader('POINT INSPECTOR'),
          if (selectedPoints.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No points selected',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  // Point count
                  Text(
                    '${selectedPoints.length} point${selectedPoints.length > 1 ? 's' : ''} selected',
                    style: TextStyle(
                      color: _accentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Position
                  if (selectedPoints.length == 1) ...[
                    _buildInspectorRow(
                      'Position',
                      '${(selectedPoints.first.position * 100).toStringAsFixed(1)}%',
                    ),
                    const SizedBox(height: 8),
                    _buildInspectorRow(
                      'Gain',
                      selectedPoints.first.displayGain,
                    ),
                    const SizedBox(height: 8),
                    _buildInspectorRow(
                      'Curve',
                      _getCurveName(selectedPoints.first.curveToNext),
                    ),
                  ] else ...[
                    _buildInspectorRow(
                      'Avg Gain',
                      '${(selectedPoints.map((p) => p.gain).reduce((a, b) => a + b) / selectedPoints.length).toStringAsFixed(1)} dB',
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Actions
                  _buildInspectorButton(
                    'Delete Selected',
                    Icons.delete_outline,
                    () {
                      if (clipId != null) {
                        provider.deleteSelectedPoints(clipId);
                      }
                    },
                    color: FluxForgeTheme.errorRed,
                  ),
                ],
              ),
            ),
          // Presets section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.backgroundMid,
              border: Border(
                top: BorderSide(color: FluxForgeTheme.backgroundDeep, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PRESETS',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _buildPresetChip('Fade In', () {
                      if (clipId != null) {
                        provider.createFadeIn(clipId, 0.2);
                      }
                    }),
                    _buildPresetChip('Fade Out', () {
                      if (clipId != null) {
                        provider.createFadeOut(clipId, 0.2);
                      }
                    }),
                    _buildPresetChip('Clear', () {
                      if (clipId != null) {
                        provider.clearEnvelope(clipId);
                      }
                    }),
                    _buildPresetChip('Flatten', () {
                      if (clipId != null) {
                        provider.flattenEnvelope(clipId);
                      }
                    }),
                    _buildPresetChip('Invert', () {
                      if (clipId != null) {
                        provider.invertEnvelope(clipId);
                      }
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildInspectorButton(String label, IconData icon, VoidCallback onTap, {Color? color}) {
    final buttonColor = color ?? _accentColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: buttonColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: buttonColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: buttonColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: buttonColor,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.backgroundDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  String _getCurveName(GainEnvelopeCurve curve) {
    switch (curve) {
      case GainEnvelopeCurve.linear:
        return 'Linear';
      case GainEnvelopeCurve.exponential:
        return 'Exponential';
      case GainEnvelopeCurve.logarithmic:
        return 'Logarithmic';
      case GainEnvelopeCurve.sCurve:
        return 'S-Curve';
    }
  }

  Widget _buildFooter(BuildContext context, ClipGainEnvelopeProvider provider) {
    final clipId = provider.editingClipId;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.backgroundMid,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.backgroundDeep, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Copy/Paste
          _buildFooterButton('Copy', Icons.content_copy, () {
            if (clipId != null) provider.copyEnvelope(clipId);
          }),
          const SizedBox(width: 8),
          _buildFooterButton('Paste', Icons.content_paste, () {
            if (clipId != null) provider.pasteEnvelope(clipId);
          }),
          const Spacer(),
          // Offset gain
          _buildFooterButton('+3 dB', Icons.add, () {
            if (clipId != null) provider.offsetGain(clipId, 3.0);
          }),
          const SizedBox(width: 4),
          _buildFooterButton('-3 dB', Icons.remove, () {
            if (clipId != null) provider.offsetGain(clipId, -3.0);
          }),
          const SizedBox(width: 16),
          // Delete envelope
          if (clipId != null && provider.hasEnvelope(clipId))
            _buildFooterButton(
              'Delete Envelope',
              Icons.delete_outline,
              () => provider.deleteEnvelope(clipId),
              color: FluxForgeTheme.errorRed,
            ),
        ],
      ),
    );
  }

  Widget _buildFooterButton(String label, IconData icon, VoidCallback onTap, {Color? color}) {
    final buttonColor = color ?? _accentColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: buttonColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: buttonColor.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: buttonColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: buttonColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: FluxForgeTheme.backgroundMid,
      child: Text(
        title,
        style: TextStyle(
          color: FluxForgeTheme.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MOCK CLIP (for demo purposes)
// ═══════════════════════════════════════════════════════════════════════════════

class _MockClip {
  final String id;
  final String name;
  final bool hasAudio;

  _MockClip(this.id, this.name, this.hasAudio);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENVELOPE PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _EnvelopePainter extends CustomPainter {
  final ClipGainEnvelope? envelope;
  final Set<String> selectedPointIds;
  final Color accentColor;

  _EnvelopePainter({
    required this.envelope,
    required this.selectedPointIds,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background grid
    _drawGrid(canvas, size);

    // Draw 0 dB line
    _draw0dBLine(canvas, size);

    if (envelope == null || envelope!.points.isEmpty) return;

    // Draw envelope line
    _drawEnvelopeLine(canvas, size);

    // Draw points
    _drawPoints(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = FluxForgeTheme.textSecondary.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    // Vertical lines
    for (int i = 0; i <= 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Horizontal lines (every 6 dB)
    for (int i = 0; i <= 12; i++) {
      final y = size.height * i / 12;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _draw0dBLine(Canvas canvas, Size size) {
    final zeroPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    // 0 dB is at 1/6 from top (12 dB range at top, then 60 dB below)
    final zeroY = size.height * (12.0 / 72.0);
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);
  }

  void _drawEnvelopeLine(Canvas canvas, Size size) {
    if (envelope!.points.length < 2) return;

    final linePaint = Paint()
      ..color = accentColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final points = envelope!.points;

    // Start from left edge
    final startY = _gainToY(points.first.gain, size.height);
    path.moveTo(0, startY);
    path.lineTo(points.first.position * size.width, startY);

    // Draw through points
    for (int i = 0; i < points.length - 1; i++) {
      final from = points[i];
      final to = points[i + 1];

      final fromX = from.position * size.width;
      final fromY = _gainToY(from.gain, size.height);
      final toX = to.position * size.width;
      final toY = _gainToY(to.gain, size.height);

      switch (from.curveToNext) {
        case GainEnvelopeCurve.linear:
          path.lineTo(toX, toY);
          break;
        case GainEnvelopeCurve.exponential:
          final ctrl1X = fromX + (toX - fromX) * 0.8;
          final ctrl1Y = fromY;
          path.quadraticBezierTo(ctrl1X, ctrl1Y, toX, toY);
          break;
        case GainEnvelopeCurve.logarithmic:
          final ctrl1X = fromX + (toX - fromX) * 0.2;
          final ctrl1Y = toY;
          path.quadraticBezierTo(ctrl1X, ctrl1Y, toX, toY);
          break;
        case GainEnvelopeCurve.sCurve:
          final ctrl1X = fromX + (toX - fromX) * 0.5;
          final ctrl1Y = fromY;
          final ctrl2X = fromX + (toX - fromX) * 0.5;
          final ctrl2Y = toY;
          path.cubicTo(ctrl1X, ctrl1Y, ctrl2X, ctrl2Y, toX, toY);
          break;
      }
    }

    // End at right edge
    final lastY = _gainToY(points.last.gain, size.height);
    path.lineTo(size.width, lastY);

    canvas.drawPath(path, linePaint);

    // Fill under curve
    final fillPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
  }

  void _drawPoints(Canvas canvas, Size size) {
    for (final point in envelope!.points) {
      final x = point.position * size.width;
      final y = _gainToY(point.gain, size.height);
      final isSelected = selectedPointIds.contains(point.id);

      // Outer ring
      final outerPaint = Paint()
        ..color = isSelected ? Colors.white : accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(Offset(x, y), 6, outerPaint);

      // Inner fill
      final innerPaint = Paint()
        ..color = isSelected ? accentColor : accentColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), 4, innerPaint);
    }
  }

  double _gainToY(double gain, double height) {
    // Map +12 dB to 0, -60 dB to height
    // Total range: 72 dB
    return height * (12.0 - gain) / 72.0;
  }

  @override
  bool shouldRepaint(covariant _EnvelopePainter oldDelegate) {
    return oldDelegate.envelope != envelope ||
        oldDelegate.selectedPointIds != selectedPointIds;
  }
}
