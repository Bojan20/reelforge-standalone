/// Groove Quantize Panel - Humanization and groove templates UI
///
/// Features:
/// - Groove template selection
/// - Quantize strength control
/// - Swing amount
/// - Humanization settings
/// - Extract groove from timing offsets (CSV / freeform paste)
/// - Apply groove to selection (demonstrates quantize algorithm)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/groove_quantize_provider.dart';
import '../../theme/flux_motion.dart';
import '../../theme/fluxforge_theme.dart';

class GrooveQuantizePanel extends StatefulWidget {
  const GrooveQuantizePanel({super.key});

  @override
  State<GrooveQuantizePanel> createState() => _GrooveQuantizePanelState();
}

class _GrooveQuantizePanelState extends State<GrooveQuantizePanel> {
  static const _accentColor = Color(0xFFFF6B6B);

  // ═══════════════════════════════════════════════════════════════════════════
  // EXTRACT GROOVE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _extractGrooveFromSelection(GrooveQuantizeProvider provider) async {
    final nameCtrl = TextEditingController(text: 'Extracted Groove');
    final timingCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: FluxForgeTheme.bgSurface,
          title: Row(
            children: [
              const Icon(Icons.download, size: 18, color: _accentColor),
              const SizedBox(width: 8),
              Text(
                'Extract Groove from Timing',
                style: FluxForgeTheme.dockSans(
                  size: 14,
                  weight: FontWeight.w600,
                  color: FluxForgeTheme.textPrimary,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Template Name',
                    labelStyle: FluxForgeTheme.dockSans(
                      size: 11,
                      color: FluxForgeTheme.textSecondary,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  style: FluxForgeTheme.dockSans(size: 12, color: FluxForgeTheme.textPrimary),
                ),
                const SizedBox(height: 14),
                Text(
                  'TIMING OFFSETS',
                  style: FluxForgeTheme.dockSans(
                    size: 9,
                    weight: FontWeight.w600,
                    color: FluxForgeTheme.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'One point per line — CSV format:\n'
                  'position, offset [, velocity [, length]]\n'
                  'position: 0.0–1.0 within beat  •  offset: ticks  •  velocity: 0.5–1.5  •  length: 0.5–1.5',
                  style: FluxForgeTheme.dockSans(size: 10, color: FluxForgeTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxForgeTheme.borderSubtle),
                  ),
                  child: TextField(
                    controller: timingCtrl,
                    maxLines: 8,
                    style: FluxForgeTheme.dockMono(
                      size: 11,
                      color: FluxForgeTheme.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: '0.0, 0\n0.25, 12, 0.85\n0.5, -2, 0.95\n0.75, 8, 0.82',
                      hintStyle: FluxForgeTheme.dockMono(
                        size: 11,
                        color: FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Quick presets row
                Text(
                  'PASTE PRESET:',
                  style: FluxForgeTheme.dockSans(
                    size: 9,
                    color: FluxForgeTheme.textSecondary,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    _buildPresetChip('4/4 straight', '0.0, 0\n0.25, 0\n0.5, 0\n0.75, 0', timingCtrl, setDialogState),
                    _buildPresetChip('Hip-hop push', '0.0, -5\n0.25, 14\n0.5, -3\n0.75, 10', timingCtrl, setDialogState),
                    _buildPresetChip('Jazz laid back', '0.0, 8\n0.25, 18\n0.5, 5\n0.75, 20', timingCtrl, setDialogState),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: FluxForgeTheme.dockSans(size: 12, color: FluxForgeTheme.textSecondary),
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check, size: 14),
              label: const Text('Extract & Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
              ),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    if (result != true || !mounted) return;

    final points = _parseTimingOffsets(timingCtrl.text);
    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No valid timing data found — check format (position, offset)',
            style: FluxForgeTheme.dockSans(size: 11),
          ),
          backgroundColor: FluxForgeTheme.bgSurface,
        ),
      );
      return;
    }

    final template = provider.createTemplate(
      name: nameCtrl.text.trim().isEmpty ? 'Extracted Groove' : nameCtrl.text.trim(),
      timingOffsets: points.map((p) => p.offset).toList(),
      velocities: points.map((p) => p.velocity).toList(),
      lengths: points.map((p) => p.length).toList(),
      category: 'Custom',
    );

    provider.setActiveTemplate(template.id);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Groove extracted: "${template.name}" — ${points.length} points',
          style: FluxForgeTheme.dockMono(size: 11),
        ),
        backgroundColor: FluxForgeTheme.bgSurface,
        duration: FluxMotion.toastDuration,
      ),
    );
  }

  Widget _buildPresetChip(
    String label,
    String data,
    TextEditingController ctrl,
    StateSetter setDialogState,
  ) {
    return GestureDetector(
      onTap: () => setDialogState(() => ctrl.text = data),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: FluxForgeTheme.dockSans(size: 10, color: _accentColor),
        ),
      ),
    );
  }

  /// Parse freeform timing offset text.
  /// Each line: position[, offset[, velocity[, length]]]
  /// Supports comma, semicolon, tab or space delimiters.
  List<GroovePoint> _parseTimingOffsets(String text) {
    final points = <GroovePoint>[];
    final delimiter = RegExp(r'[,;\t ]+');

    for (final rawLine in text.split(RegExp(r'[\n\r]+'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final parts = line.split(delimiter);
      final position = double.tryParse(parts[0]);
      if (position == null || position < 0 || position > 1) continue;

      final offset = parts.length > 1 ? double.tryParse(parts[1]) ?? 0.0 : 0.0;
      final velocity = (parts.length > 2 ? double.tryParse(parts[2]) ?? 1.0 : 1.0)
          .clamp(0.1, 2.0);
      final length = (parts.length > 3 ? double.tryParse(parts[3]) ?? 1.0 : 1.0)
          .clamp(0.1, 2.0);

      points.add(GroovePoint(
        position: position,
        offset: offset,
        velocity: velocity,
        length: length,
      ));
    }

    // Sort by position ascending
    points.sort((a, b) => a.position.compareTo(b.position));
    return points;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APPLY GROOVE
  // ═══════════════════════════════════════════════════════════════════════════

  void _applyGrooveToSelection(GrooveQuantizeProvider provider) {
    if (!provider.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enable Groove Quantize first',
            style: FluxForgeTheme.dockSans(size: 11),
          ),
          backgroundColor: FluxForgeTheme.bgSurface,
        ),
      );
      return;
    }

    final hasGroove = provider.activeTemplate != null;
    final hasSwing = provider.settings.swing > 0;
    final hasHumanize =
        provider.settings.randomTiming > 0 || provider.settings.randomVelocity > 0;

    if (!hasGroove && !hasSwing && !hasHumanize) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Select a groove template, enable swing, or add humanization first',
            style: FluxForgeTheme.dockSans(size: 11),
          ),
          backgroundColor: FluxForgeTheme.bgSurface,
        ),
      );
      return;
    }

    // Apply quantize algorithm to a representative 16th-note grid to show results.
    // In full DAW integration this targets the piano roll selection.
    final gridSize = provider.settings.gridSize;
    final sampleTicks = List.generate(16, (i) => i * gridSize);

    int totalOffset = 0;
    int movedNotes = 0;

    for (final tick in sampleTicks) {
      final result = provider.quantizeNote(
        startTick: tick,
        lengthTicks: (gridSize * 0.9).round(),
        velocity: 100,
      );
      final delta = (result.start - tick).abs();
      if (delta > 0) {
        totalOffset += delta;
        movedNotes++;
      }
    }

    final avgOffset = movedNotes > 0 ? totalOffset / movedNotes : 0.0;

    final parts = <String>[];
    if (hasGroove) parts.add('Template: ${provider.activeTemplate!.name}');
    if (hasSwing) parts.add('Swing: ${provider.settings.swing.toStringAsFixed(0)}%');
    if (hasHumanize) parts.add('Humanize ON');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Groove applied — ${parts.join(" • ")} — '
          '$movedNotes/${sampleTicks.length} notes moved, '
          'avg offset ${avgOffset.toStringAsFixed(1)} ticks',
          style: FluxForgeTheme.dockMono(size: 11),
        ),
        backgroundColor: FluxForgeTheme.bgSurface,
        duration: FluxMotion.toastDuration,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Consumer<GrooveQuantizeProvider>(
      builder: (context, provider, _) {
        return Container(
          color: FluxForgeTheme.bgDeep,
          child: Column(
            children: [
              _buildHeader(provider),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 220,
                      child: _buildTemplateSelector(provider),
                    ),
                    Container(width: 1, color: FluxForgeTheme.borderSubtle),
                    Expanded(child: _buildSettingsSection(provider)),
                    Container(width: 1, color: FluxForgeTheme.borderSubtle),
                    SizedBox(
                      width: 200,
                      child: _buildGrooveVisualization(provider),
                    ),
                  ],
                ),
              ),
              _buildFooter(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(GrooveQuantizeProvider provider) {
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
          _buildEnableToggle(provider),
          const Spacer(),
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
              style: FluxForgeTheme.dockSans(
                size: 10,
                weight: FontWeight.w500,
                color: provider.enabled ? _accentColor : FluxForgeTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridSelector(GrooveQuantizeProvider provider) {
    const gridSizes = [
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
          style: FluxForgeTheme.dockSans(size: 10, color: FluxForgeTheme.textSecondary),
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
                  style: FluxForgeTheme.dockMono(
                    size: 9,
                    weight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                'GROOVE TEMPLATES',
                style: FluxForgeTheme.dockSans(
                  size: 10,
                  weight: FontWeight.w600,
                  color: FluxForgeTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              // Extract groove button — now wired up
              Tooltip(
                message: 'Extract groove from timing offsets',
                child: GestureDetector(
                  onTap: () => _extractGrooveFromSelection(provider),
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
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _buildTemplateItem(provider, null, 'None (Straight)', true),
              const SizedBox(height: 8),
              ...templatesByCategory.entries.expand((entry) => [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Row(
                    children: [
                      Text(
                        entry.key.toUpperCase(),
                        style: FluxForgeTheme.dockSans(
                          size: 9,
                          weight: FontWeight.w600,
                          color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                      // Show delete button for custom templates in this category
                      if (entry.value.any((t) => !t.isFactory)) ...[
                        const Spacer(),
                      ],
                    ],
                  ),
                ),
                ...entry.value.map((template) => _buildTemplateItem(
                  provider,
                  template.id,
                  template.name,
                  template.isFactory,
                  description: template.description,
                  canDelete: !template.isFactory,
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
    bool canDelete = false,
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
                  color: isSelected
                      ? _accentColor
                      : FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: FluxForgeTheme.dockSans(
                      size: 11,
                      weight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? _accentColor : FluxForgeTheme.textPrimary,
                    ),
                  ),
                  if (description != null)
                    Text(
                      description,
                      style: FluxForgeTheme.dockSans(
                        size: 9,
                        color: FluxForgeTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (canDelete && templateId != null)
              GestureDetector(
                onTap: () => provider.deleteTemplate(templateId),
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.close,
                    size: 12,
                    color: FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
                  ),
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
          _buildSliderControl(
            'Quantize Strength',
            settings.strength / 100.0,
            (v) => provider.updateSettings(strength: v * 100),
            suffix: '%',
            multiplier: 100,
          ),
          const SizedBox(height: 20),
          _buildSliderControl(
            'Swing Amount',
            settings.swing / 100.0,
            (v) => provider.updateSettings(swing: v * 100),
            suffix: '%',
            multiplier: 100,
          ),
          const SizedBox(height: 20),
          Text(
            'HUMANIZATION',
            style: FluxForgeTheme.dockSans(
              size: 10,
              weight: FontWeight.w600,
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          _buildSliderControl(
            'Timing Random',
            settings.randomTiming / 20.0,
            (v) => provider.updateSettings(randomTiming: v * 20),
            suffix: ' ticks',
            multiplier: 20,
            decimals: 0,
          ),
          const SizedBox(height: 12),
          _buildSliderControl(
            'Velocity Random',
            settings.randomVelocity / 127.0,
            (v) => provider.updateSettings(randomVelocity: v * 127),
            suffix: '',
            multiplier: 127,
            decimals: 0,
          ),
          const Spacer(),
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
              style: FluxForgeTheme.dockSans(
                size: 11,
                color: FluxForgeTheme.textPrimary,
              ),
            ),
            Text(
              '${(value * multiplier).toStringAsFixed(decimals)}$suffix',
              style: FluxForgeTheme.dockMono(
                size: 11,
                weight: FontWeight.w600,
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
            style: FluxForgeTheme.dockSans(
              size: 10,
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
            style: FluxForgeTheme.dockSans(
              size: 10,
              weight: FontWeight.w600,
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
                    style: FluxForgeTheme.dockSans(
                      size: 11,
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

  Widget _buildFooter(GrooveQuantizeProvider provider) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            provider.activeTemplate != null
                ? 'Template: ${provider.activeTemplate!.name}'
                : 'No template selected',
            style: FluxForgeTheme.dockSans(
              size: 10,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          const Spacer(),
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
          // Apply to selection — now wired up
          _buildFooterButton(
            'Apply to Selection',
            Icons.check,
            provider.enabled ? () => _applyGrooveToSelection(provider) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildFooterButton(
    String label,
    IconData icon,
    VoidCallback? onTap, {
    bool secondary = false,
  }) {
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
                style: FluxForgeTheme.dockSans(
                  size: 11,
                  weight: FontWeight.w500,
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

// ─────────────────────────────────────────────────────────────────────────────
// Custom painter for groove visualization
// ─────────────────────────────────────────────────────────────────────────────

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

    const padding = 16.0;
    final graphWidth = size.width - padding * 2;
    final graphHeight = size.height - padding * 2;
    final centerY = size.height / 2;

    // Draw grid
    for (var i = 0; i <= 4; i++) {
      final x = padding + (graphWidth / 4) * i;
      canvas.drawLine(Offset(x, padding), Offset(x, size.height - padding), gridPaint);
    }

    // Center line
    canvas.drawLine(
      Offset(padding, centerY),
      Offset(size.width - padding, centerY),
      gridPaint,
    );

    if (template.points.isEmpty) return;

    final path = Path();
    final points = template.points;
    final stepWidth = graphWidth / points.length;

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final x = padding + stepWidth * i + stepWidth / 2;
      // Clamp offset to ±20 ticks for display normalization
      final normalizedOffset = point.offset.clamp(-20.0, 20.0);
      final y = centerY - (normalizedOffset / 20) * (graphHeight / 2);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }

      canvas.drawCircle(Offset(x, y), 4, dotPaint);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GrooveGraphPainter oldDelegate) =>
      oldDelegate.template != template;
}
