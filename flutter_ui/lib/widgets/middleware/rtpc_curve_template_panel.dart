/// FluxForge Studio RTPC Curve Template Panel
///
/// P4.7: RTPC Curve Templates
/// - Reusable curve presets (linear, exponential, logarithmic, etc.)
/// - Visual curve editor with control points
/// - Apply templates to RTPC bindings
/// - Save custom curves as templates
library;

import 'package:flutter/material.dart';
import '../../models/middleware_models.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CURVE TEMPLATE DATA
// ═══════════════════════════════════════════════════════════════════════════════

/// Factory curve template
class CurveTemplate {
  final String id;
  final String name;
  final String category;
  final String description;
  final List<RtpcCurvePoint> points;
  final bool isFactory;

  const CurveTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.points,
    this.isFactory = true,
  });

  RtpcCurve toCurve() => RtpcCurve(points: points);
}

/// Factory templates
const List<CurveTemplate> _factoryTemplates = [
  // Linear
  CurveTemplate(
    id: 'linear',
    name: 'Linear',
    category: 'Basic',
    description: 'Straight line from min to max',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0),
      RtpcCurvePoint(x: 1.0, y: 1.0),
    ],
  ),
  CurveTemplate(
    id: 'linear_inverted',
    name: 'Linear Inverted',
    category: 'Basic',
    description: 'Straight line from max to min',
    points: [
      RtpcCurvePoint(x: 0.0, y: 1.0),
      RtpcCurvePoint(x: 1.0, y: 0.0),
    ],
  ),

  // Exponential
  CurveTemplate(
    id: 'exp_slow_start',
    name: 'Exponential (Slow Start)',
    category: 'Exponential',
    description: 'Starts slow, accelerates at the end',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 1.0, y: 1.0),
    ],
  ),
  CurveTemplate(
    id: 'exp_fast_start',
    name: 'Exponential (Fast Start)',
    category: 'Exponential',
    description: 'Starts fast, slows down at the end',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0, shape: RtpcCurveShape.sine),
      RtpcCurvePoint(x: 0.3, y: 0.6),
      RtpcCurvePoint(x: 1.0, y: 1.0),
    ],
  ),

  // S-Curves
  CurveTemplate(
    id: 's_curve',
    name: 'S-Curve',
    category: 'S-Curves',
    description: 'Smooth ease-in-ease-out transition',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0, shape: RtpcCurveShape.sCurve),
      RtpcCurvePoint(x: 1.0, y: 1.0),
    ],
  ),
  CurveTemplate(
    id: 's_curve_sharp',
    name: 'Sharp S-Curve',
    category: 'S-Curves',
    description: 'Aggressive S-curve with quick midpoint',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0),
      RtpcCurvePoint(x: 0.3, y: 0.1, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 0.5, y: 0.5, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 0.7, y: 0.9, shape: RtpcCurveShape.sine),
      RtpcCurvePoint(x: 1.0, y: 1.0),
    ],
  ),

  // Audio-Specific
  CurveTemplate(
    id: 'volume_log',
    name: 'Volume (Logarithmic)',
    category: 'Audio',
    description: 'Perceptually linear volume control',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0),
      RtpcCurvePoint(x: 0.25, y: 0.5, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 0.5, y: 0.75),
      RtpcCurvePoint(x: 1.0, y: 1.0),
    ],
  ),
  CurveTemplate(
    id: 'filter_sweep',
    name: 'Filter Sweep',
    category: 'Audio',
    description: 'Optimized for LPF/HPF cutoff',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0),
      RtpcCurvePoint(x: 0.5, y: 0.2, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 0.8, y: 0.5, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 1.0, y: 1.0),
    ],
  ),
  CurveTemplate(
    id: 'reverb_send',
    name: 'Reverb Send',
    category: 'Audio',
    description: 'Subtle low-end, fuller high-end',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0),
      RtpcCurvePoint(x: 0.5, y: 0.15),
      RtpcCurvePoint(x: 0.8, y: 0.4, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 1.0, y: 1.0),
    ],
  ),

  // Slot Game Specific
  CurveTemplate(
    id: 'win_intensity',
    name: 'Win Intensity',
    category: 'Slot',
    description: 'Maps win multiplier to audio intensity',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0),
      RtpcCurvePoint(x: 0.1, y: 0.3), // Small wins audible
      RtpcCurvePoint(x: 0.3, y: 0.5),
      RtpcCurvePoint(x: 0.6, y: 0.7, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 1.0, y: 1.0),
    ],
  ),
  CurveTemplate(
    id: 'cascade_escalation',
    name: 'Cascade Escalation',
    category: 'Slot',
    description: 'Builds intensity with cascade depth',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.3), // Base level
      RtpcCurvePoint(x: 0.2, y: 0.4),
      RtpcCurvePoint(x: 0.4, y: 0.55, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 0.7, y: 0.8, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 1.0, y: 1.0),
    ],
  ),
  CurveTemplate(
    id: 'tension_build',
    name: 'Tension Build',
    category: 'Slot',
    description: 'Gradual tension with late escalation',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0),
      RtpcCurvePoint(x: 0.4, y: 0.1),
      RtpcCurvePoint(x: 0.7, y: 0.3, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 0.9, y: 0.7, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 1.0, y: 1.0),
    ],
  ),
  CurveTemplate(
    id: 'anticipation',
    name: 'Anticipation',
    category: 'Slot',
    description: 'Quick rise, sustained peak',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0),
      RtpcCurvePoint(x: 0.2, y: 0.7, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 0.5, y: 0.85),
      RtpcCurvePoint(x: 1.0, y: 1.0),
    ],
  ),

  // Creative
  CurveTemplate(
    id: 'pulse',
    name: 'Pulse',
    category: 'Creative',
    description: 'Quick attack, quick release',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0),
      RtpcCurvePoint(x: 0.2, y: 1.0, shape: RtpcCurveShape.log3),
      RtpcCurvePoint(x: 0.5, y: 1.0),
      RtpcCurvePoint(x: 0.8, y: 0.0, shape: RtpcCurveShape.sine),
      RtpcCurvePoint(x: 1.0, y: 0.0),
    ],
  ),
  CurveTemplate(
    id: 'steps_3',
    name: '3 Steps',
    category: 'Creative',
    description: 'Three discrete levels',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0),
      RtpcCurvePoint(x: 0.33, y: 0.0),
      RtpcCurvePoint(x: 0.34, y: 0.5),
      RtpcCurvePoint(x: 0.66, y: 0.5),
      RtpcCurvePoint(x: 0.67, y: 1.0),
      RtpcCurvePoint(x: 1.0, y: 1.0),
    ],
  ),
  CurveTemplate(
    id: 'triangle',
    name: 'Triangle',
    category: 'Creative',
    description: 'Rise and fall symmetrically',
    points: [
      RtpcCurvePoint(x: 0.0, y: 0.0),
      RtpcCurvePoint(x: 0.5, y: 1.0),
      RtpcCurvePoint(x: 1.0, y: 0.0),
    ],
  ),
];

// ═══════════════════════════════════════════════════════════════════════════════
// CURVE TEMPLATE PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class RtpcCurveTemplatePanel extends StatefulWidget {
  final RtpcCurve? currentCurve;
  final ValueChanged<RtpcCurve>? onCurveSelected;
  final double height;

  const RtpcCurveTemplatePanel({
    super.key,
    this.currentCurve,
    this.onCurveSelected,
    this.height = 350,
  });

  /// Show as a dialog and return selected curve
  static Future<RtpcCurve?> show(BuildContext context, {RtpcCurve? currentCurve}) {
    return showDialog<RtpcCurve>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: FluxForgeTheme.surface,
        child: Container(
          width: 700,
          height: 500,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  Text(
                    'Curve Templates',
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Panel
              Expanded(
                child: RtpcCurveTemplatePanel(
                  currentCurve: currentCurve,
                  onCurveSelected: (curve) => Navigator.pop(context, curve),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  State<RtpcCurveTemplatePanel> createState() => _RtpcCurveTemplatePanelState();
}

class _RtpcCurveTemplatePanelState extends State<RtpcCurveTemplatePanel> {
  String _selectedCategory = 'All';
  String? _selectedTemplateId;
  String _searchQuery = '';

  List<String> get _categories {
    final cats = <String>{'All'};
    for (final t in _factoryTemplates) {
      cats.add(t.category);
    }
    return cats.toList();
  }

  List<CurveTemplate> get _filteredTemplates {
    return _factoryTemplates.where((t) {
      if (_selectedCategory != 'All' && t.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return t.name.toLowerCase().contains(query) ||
            t.description.toLowerCase().contains(query);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          // Categories (left)
          Container(
            width: 140,
            decoration: BoxDecoration(
              color: FluxForgeTheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = cat == _selectedCategory;
                final count = cat == 'All'
                    ? _factoryTemplates.length
                    : _factoryTemplates.where((t) => t.category == cat).length;

                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: FluxForgeTheme.accent.withValues(alpha: 0.1),
                  title: Text(
                    cat,
                    style: TextStyle(
                      color: isSelected ? FluxForgeTheme.accent : FluxForgeTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: Text(
                    '$count',
                    style: TextStyle(
                      color: FluxForgeTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  onTap: () => setState(() => _selectedCategory = cat),
                );
              },
            ),
          ),
          // Divider
          Container(
            width: 1,
            color: FluxForgeTheme.borderSubtle,
          ),
          // Templates list (middle)
          Expanded(
            flex: 2,
            child: Column(
              children: [
                // Search
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search templates...',
                      hintStyle: TextStyle(color: FluxForgeTheme.textMuted),
                      prefixIcon: Icon(Icons.search, color: FluxForgeTheme.textMuted, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                // List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _filteredTemplates.length,
                    itemBuilder: (context, index) {
                      final template = _filteredTemplates[index];
                      final isSelected = template.id == _selectedTemplateId;

                      return _TemplateListTile(
                        template: template,
                        isSelected: isSelected,
                        onTap: () => setState(() => _selectedTemplateId = template.id),
                        onApply: () {
                          widget.onCurveSelected?.call(template.toCurve());
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Divider
          Container(
            width: 1,
            color: FluxForgeTheme.borderSubtle,
          ),
          // Preview (right)
          Expanded(
            flex: 2,
            child: _buildPreview(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final template = _selectedTemplateId != null
        ? _factoryTemplates.firstWhere((t) => t.id == _selectedTemplateId)
        : null;

    if (template == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline, size: 48, color: FluxForgeTheme.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'Select a template',
              style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name
          Text(
            template.name,
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          // Category badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              template.category,
              style: TextStyle(
                color: FluxForgeTheme.accent,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Description
          Text(
            template.description,
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          // Curve preview
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: CustomPaint(
                size: Size.infinite,
                painter: _CurvePreviewPainter(
                  curve: template.toCurve(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Apply button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                widget.onCurveSelected?.call(template.toCurve());
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Apply Template'),
              style: ElevatedButton.styleFrom(
                backgroundColor: FluxForgeTheme.accent,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TEMPLATE LIST TILE
// ═══════════════════════════════════════════════════════════════════════════════

class _TemplateListTile extends StatelessWidget {
  final CurveTemplate template;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onApply;

  const _TemplateListTile({
    required this.template,
    required this.isSelected,
    required this.onTap,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onApply,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? FluxForgeTheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(color: FluxForgeTheme.accent.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          children: [
            // Mini curve preview
            Container(
              width: 40,
              height: 24,
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
              ),
              child: CustomPaint(
                painter: _MiniCurveTemplatePainter(curve: template.toCurve()),
              ),
            ),
            const SizedBox(width: 8),
            // Name
            Expanded(
              child: Text(
                template.name,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Apply button (when selected)
            if (isSelected)
              IconButton(
                icon: Icon(Icons.check_circle, size: 18, color: FluxForgeTheme.accent),
                onPressed: onApply,
                tooltip: 'Apply',
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _CurvePreviewPainter extends CustomPainter {
  final RtpcCurve curve;

  _CurvePreviewPainter({required this.curve});

  @override
  void paint(Canvas canvas, Size size) {
    final padding = 16.0;
    final chartRect = Rect.fromLTWH(
      padding,
      padding,
      size.width - padding * 2,
      size.height - padding * 2,
    );

    // Grid
    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final x = chartRect.left + chartRect.width * (i / 4);
      final y = chartRect.top + chartRect.height * (i / 4);

      canvas.drawLine(
        Offset(x, chartRect.top),
        Offset(x, chartRect.bottom),
        gridPaint,
      );
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    // Curve
    final path = Path();
    for (int i = 0; i <= 100; i++) {
      final x = i / 100.0;
      final y = curve.evaluate(x);

      final px = chartRect.left + x * chartRect.width;
      final py = chartRect.bottom - y * chartRect.height;

      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    final curvePaint = Paint()
      ..color = FluxForgeTheme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, curvePaint);

    // Control points
    final pointPaint = Paint()
      ..color = FluxForgeTheme.accent
      ..style = PaintingStyle.fill;

    final pointOutlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final point in curve.points) {
      final px = chartRect.left + point.x * chartRect.width;
      final py = chartRect.bottom - point.y * chartRect.height;

      canvas.drawCircle(Offset(px, py), 6, pointPaint);
      canvas.drawCircle(Offset(px, py), 6, pointOutlinePaint);
    }

    // Labels
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // X-axis labels
    for (int i = 0; i <= 4; i++) {
      textPainter.text = TextSpan(
        text: '${(i * 25)}%',
        style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          chartRect.left + chartRect.width * (i / 4) - textPainter.width / 2,
          chartRect.bottom + 4,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_CurvePreviewPainter oldDelegate) => curve != oldDelegate.curve;
}

class _MiniCurveTemplatePainter extends CustomPainter {
  final RtpcCurve curve;

  _MiniCurveTemplatePainter({required this.curve});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();

    for (int i = 0; i <= 20; i++) {
      final x = i / 20.0;
      final y = curve.evaluate(x);

      final px = x * size.width;
      final py = size.height - y * size.height;

      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    final paint = Paint()
      ..color = FluxForgeTheme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MiniCurveTemplatePainter oldDelegate) => curve != oldDelegate.curve;
}
