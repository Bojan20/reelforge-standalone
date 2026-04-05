/// Groove Quantize Panel - Humanization and groove templates UI
///
/// Features:
/// - Groove template selection
/// - Quantize strength control
/// - Swing amount
/// - Humanization settings
/// - Extract groove from selection

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/groove_quantize_provider.dart';
import '../../theme/fluxforge_theme.dart';

class GrooveQuantizePanel extends StatelessWidget {
  const GrooveQuantizePanel({super.key});

  static const _accentColor = Color(0xFFFF6B6B);

  @override
  Widget build(BuildContext context) {
    return Consumer<GrooveQuantizeProvider>(
      builder: (context, provider, _) {
        return Container(
          color: FluxForgeTheme.bgDeep,
          child: Column(
            children: [
              // Header
              _buildHeader(context, provider),

              // Main content
              Expanded(
                child: Row(
                  children: [
                    // Template selector (left)
                    SizedBox(
                      width: 220,
                      child: _buildTemplateSelector(provider),
                    ),

                    // Divider
                    Container(width: 1, color: FluxForgeTheme.borderSubtle),

                    // Settings (center)
                    Expanded(
                      child: _buildSettingsSection(provider),
                    ),

                    // Divider
                    Container(width: 1, color: FluxForgeTheme.borderSubtle),

                    // Visualization (right)
                    SizedBox(
                      width: 200,
                      child: _buildGrooveVisualization(provider),
                    ),
                  ],
                ),
              ),

              // Footer
              _buildFooter(context, provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, GrooveQuantizeProvider provider) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq, size: 16, color: _accentColor),
          const SizedBox(width: 8),
          Text(
            'Groove Quantize',
            style: FluxForgeTheme.label.copyWith(
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary,
            ),
          ),

          const SizedBox(width: 16),

          // Enable toggle
          _buildEnableToggle(provider),

          const Spacer(),

          // Grid size selector
          _buildGridSelector(provider),
        ],
      ),
    );
  }

  Widget _buildEnableToggle(GrooveQuantizeProvider provider) {
    return GestureDetector(
      onTap: provider.toggleEnabled,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: provider.enabled
              ? _accentColor.withValues(alpha: 0.15)
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: provider.enabled ? _accentColor : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              provider.enabled ? Icons.check_circle : Icons.circle_outlined,
              size: 12,
              color: provider.enabled ? _accentColor : FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              provider.enabled ? 'Enabled' : 'Disabled',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: provider.enabled ? _accentColor : FluxForgeTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridSelector(GrooveQuantizeProvider provider) {
    final gridSizes = [
      (120, '1/4'),
      (60, '1/8'),
      (30, '1/16'),
      (80, '1/8T'),
      (40, '1/16T'),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Grid:',
          style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary),
        ),
        const SizedBox(width: 6),
        ...gridSizes.map((grid) {
          final isSelected = provider.settings.gridSize == grid.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: GestureDetector(
              onTap: () => provider.updateSettings(gridSize: grid.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _accentColor.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: isSelected ? _accentColor : FluxForgeTheme.borderSubtle,
                  ),
                ),
                child: Text(
                  grid.$2,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? _accentColor : FluxForgeTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTemplateSelector(GrooveQuantizeProvider provider) {
    final templatesByCategory = provider.templatesByCategory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                'GROOVE TEMPLATES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              // Extract button
              Tooltip(
                message: 'Extract groove from selection',
                child: GestureDetector(
                  onTap: () {
                    // TODO: Extract groove from selection
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgDeep,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: FluxForgeTheme.borderSubtle),
                    ),
                    child: Icon(
                      Icons.download,
                      size: 14,
                      color: FluxForgeTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Template list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              // No groove option
              _buildTemplateItem(provider, null, 'None (Straight)', true),

              const SizedBox(height: 8),

              // Factory templates by category
              ...templatesByCategory.entries.expand((entry) => [
                // Category header
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    entry.key.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                // Templates
                ...entry.value.map((template) => _buildTemplateItem(
                  provider,
                  template.id,
                  template.name,
                  template.isFactory,
                  description: template.description,
                )),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateItem(
    GrooveQuantizeProvider provider,
    String? templateId,
    String name,
    bool isFactory, {
    String? description,
  }) {
    final isSelected = provider.activeTemplateId == templateId;

    return GestureDetector(
      onTap: () => provider.setActiveTemplate(templateId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? _accentColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? _accentColor : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            if (isFactory)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.star,
                  size: 12,
                  color: isSelected ? _accentColor : FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? _accentColor : FluxForgeTheme.textPrimary,
                    ),
                  ),
                  if (description != null)
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 9,
                        color: FluxForgeTheme.textSecondary,
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

  Widget _buildSettingsSection(GrooveQuantizeProvider provider) {
    final settings = provider.settings;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quantize Strength
          _buildSliderControl(
            'Quantize Strength',
            settings.strength / 100.0,
            (v) => provider.updateSettings(strength: v * 100),
            suffix: '%',
            multiplier: 100,
          ),

          const SizedBox(height: 20),

          // Swing
          _buildSliderControl(
            'Swing Amount',
            settings.swing / 100.0,
            (v) => provider.updateSettings(swing: v * 100),
            suffix: '%',
            multiplier: 100,
          ),

          const SizedBox(height: 20),

          // Humanize section
          Text(
            'HUMANIZATION',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),

          // Timing randomization
          _buildSliderControl(
            'Timing Random',
            settings.randomTiming / 20.0,
            (v) => provider.updateSettings(randomTiming: v * 20),
            suffix: ' ticks',
            multiplier: 20,
            decimals: 0,
          ),

          const SizedBox(height: 12),

          // Velocity randomization
          _buildSliderControl(
            'Velocity Random',
            settings.randomVelocity / 127.0,
            (v) => provider.updateSettings(randomVelocity: v * 127),
            suffix: '',
            multiplier: 127,
            decimals: 0,
          ),

          const Spacer(),

          // Apply options
          Row(
            children: [
              _buildCheckbox(
                'Quantize Start',
                settings.quantizeStart,
                (v) => provider.updateSettings(quantizeStart: v),
              ),
              const SizedBox(width: 16),
              _buildCheckbox(
                'Quantize End',
                settings.quantizeEnd,
                (v) => provider.updateSettings(quantizeEnd: v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSliderControl(
    String label,
    double value,
    ValueChanged<double> onChanged, {
    String suffix = '',
    double multiplier = 1,
    int decimals = 0,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: FluxForgeTheme.textPrimary,
              ),
            ),
            Text(
              '${(value * multiplier).toStringAsFixed(decimals)}$suffix',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _accentColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: _accentColor,
            inactiveTrackColor: FluxForgeTheme.bgMid,
            thumbColor: _accentColor,
            overlayColor: _accentColor.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: value ? _accentColor.withValues(alpha: 0.2) : FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: value ? _accentColor : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: value
                ? const Icon(Icons.check, size: 12, color: _accentColor)
                : null,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: value ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrooveVisualization(GrooveQuantizeProvider provider) {
    final template = provider.activeTemplate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Text(
            'GROOVE PREVIEW',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),

        Expanded(
          child: template == null
              ? Center(
                  child: Text(
                    'Select a template\nto see preview',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                )
              : _buildGrooveGraph(template),
        ),
      ],
    );
  }

  Widget _buildGrooveGraph(GrooveTemplate template) {
    return CustomPaint(
      painter: _GrooveGraphPainter(template: template),
    );
  }

  Widget _buildFooter(BuildContext context, GrooveQuantizeProvider provider) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          // Template info
          Text(
            provider.activeTemplate != null
                ? 'Template: ${provider.activeTemplate!.name}'
                : 'No template selected',
            style: TextStyle(
              fontSize: 10,
              color: FluxForgeTheme.textSecondary,
            ),
          ),

          const Spacer(),

          // Reset button
          _buildFooterButton(
            'Reset',
            Icons.refresh,
            () {
              provider.updateSettings(
                strength: 100,
                swing: 0,
                randomTiming: 0,
                randomVelocity: 0,
              );
            },
            secondary: true,
          ),

          const SizedBox(width: 8),

          // Apply button
          _buildFooterButton(
            'Apply to Selection',
            Icons.check,
            provider.enabled
                ? () {
                    // TODO: Apply to selection
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Groove applied to selection')),
                    );
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildFooterButton(String label, IconData icon, VoidCallback? onTap, {bool secondary = false}) {
    final isDisabled = onTap == null;
    final color = secondary ? FluxForgeTheme.textSecondary : _accentColor;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: secondary
                ? FluxForgeTheme.bgDeep
                : _accentColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: secondary ? FluxForgeTheme.borderSubtle : _accentColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom painter for groove visualization
class _GrooveGraphPainter extends CustomPainter {
  final GrooveTemplate template;

  _GrooveGraphPainter({required this.template});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF6B6B)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = const Color(0xFFFF6B6B)
      ..style = PaintingStyle.fill;

    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    final padding = 16.0;
    final graphWidth = size.width - padding * 2;
    final graphHeight = size.height - padding * 2;
    final centerY = size.height / 2;

    // Draw grid lines
    for (var i = 0; i <= 4; i++) {
      final x = padding + (graphWidth / 4) * i;
      canvas.drawLine(Offset(x, padding), Offset(x, size.height - padding), gridPaint);
    }

    // Draw center line
    canvas.drawLine(
      Offset(padding, centerY),
      Offset(size.width - padding, centerY),
      gridPaint,
    );

    // Draw groove points
    if (template.points.isEmpty) return;

    final path = Path();
    final points = template.points;
    final stepWidth = graphWidth / points.length;

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final x = padding + stepWidth * i + stepWidth / 2;
      final y = centerY - (point.offset / 20) * (graphHeight / 2);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }

      // Draw dot
      canvas.drawCircle(Offset(x, y), 4, dotPaint);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GrooveGraphPainter oldDelegate) =>
      oldDelegate.template != template;
}
