// Macro Controls Panel
//
// Serum/Vital/Ableton-style multi-parameter macro knobs:
// - Single knob controls multiple parameters
// - Per-target depth and curve
// - MIDI learn support
// - Macro pages for organization

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/macro_control_provider.dart';
import '../../theme/fluxforge_theme.dart';

class MacroControlsPanel extends StatelessWidget {
  const MacroControlsPanel({super.key});

  static const Color _accentColor = Color(0xFFAA40FF); // Purple

  @override
  Widget build(BuildContext context) {
    return Consumer<MacroControlProvider>(
      builder: (context, provider, _) {
        return Container(
          color: FluxForgeTheme.backgroundDeep,
          child: Column(
            children: [
              _buildHeader(provider),
              Expanded(
                child: Row(
                  children: [
                    // Left: Page tabs
                    _buildPageTabs(provider),
                    // Center: Macro grid
                    Expanded(child: _buildMacroGrid(context, provider)),
                    // Right: Target editor
                    _buildTargetEditor(context, provider),
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

  Widget _buildHeader(MacroControlProvider provider) {
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
            'MACRO CONTROLS',
            style: TextStyle(
              color: provider.enabled ? _accentColor : FluxForgeTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // MIDI Learn indicator
          if (provider.midiLearnMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.accentOrange),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.music_note, size: 14, color: FluxForgeTheme.accentOrange),
                  const SizedBox(width: 4),
                  Text(
                    'MIDI LEARN',
                    style: TextStyle(
                      color: FluxForgeTheme.accentOrange,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => provider.cancelMidiLearn(),
                    child: Icon(Icons.close, size: 14, color: FluxForgeTheme.accentOrange),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 16),
          // Macro count
          Text(
            '${provider.macros.length} Macros',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageTabs(MacroControlProvider provider) {
    return Container(
      width: 120,
      decoration: BoxDecoration(
        color: FluxForgeTheme.backgroundDeep,
        border: Border(
          right: BorderSide(color: FluxForgeTheme.backgroundMid, width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildSectionHeader('PAGES'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                // All macros
                _buildPageTab(
                  provider,
                  null,
                  'All',
                  Icons.grid_view,
                  provider.macros.length,
                ),
                const SizedBox(height: 4),
                // Custom pages
                ...provider.pages.map((page) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _buildPageTab(
                    provider,
                    page.id,
                    page.name,
                    Icons.folder,
                    page.macroIds.length,
                  ),
                )),
                const SizedBox(height: 8),
                // Add page button
                GestureDetector(
                  onTap: () => provider.addPage(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.backgroundMid,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 14, color: FluxForgeTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Add Page',
                          style: TextStyle(
                            color: FluxForgeTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageTab(
    MacroControlProvider provider,
    String? pageId,
    String name,
    IconData icon,
    int count,
  ) {
    final isActive = provider.activePageId == pageId;

    return GestureDetector(
      onTap: () => provider.setActivePage(pageId),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? _accentColor.withValues(alpha: 0.2) : FluxForgeTheme.backgroundMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? _accentColor : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isActive ? _accentColor : FluxForgeTheme.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: isActive ? _accentColor : FluxForgeTheme.textPrimary,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroGrid(BuildContext context, MacroControlProvider provider) {
    final macros = provider.activeMacros;

    if (macros.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune,
              size: 48,
              color: FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No Macros',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Click "Add Macro" to create one',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.0,
      ),
      itemCount: macros.length,
      itemBuilder: (context, index) {
        return _MacroKnob(
          macro: macros[index],
          isSelected: provider.selectedMacroId == macros[index].id,
          onTap: () => provider.selectMacro(macros[index].id),
          onValueChanged: (v) => provider.setMacroValue(macros[index].id, v),
          onMidiLearn: () => provider.startMidiLearn(macros[index].id),
          onReset: () => provider.resetMacro(macros[index].id),
        );
      },
    );
  }

  Widget _buildTargetEditor(BuildContext context, MacroControlProvider provider) {
    final selectedMacro = provider.selectedMacroId != null
        ? provider.getMacro(provider.selectedMacroId!)
        : null;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: FluxForgeTheme.backgroundDeep,
        border: Border(
          left: BorderSide(color: FluxForgeTheme.backgroundMid, width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildSectionHeader('TARGET MAPPING'),
          if (selectedMacro == null)
            Expanded(
              child: Center(
                child: Text(
                  'Select a macro to edit',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  // Macro info
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: FluxForgeTheme.backgroundMid,
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: selectedMacro.color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedMacro.name,
                                style: TextStyle(
                                  color: FluxForgeTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${selectedMacro.targets.length} targets',
                                style: TextStyle(
                                  color: FluxForgeTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // MIDI CC display
                        if (selectedMacro.midiCC != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.backgroundDeep,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'CC ${selectedMacro.midiCC}',
                              style: TextStyle(
                                color: FluxForgeTheme.accentCyan,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Target list
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(8),
                      children: [
                        ...selectedMacro.targets.map((target) => _buildTargetCard(
                          context,
                          provider,
                          selectedMacro,
                          target,
                        )),
                        const SizedBox(height: 8),
                        // Add target button
                        GestureDetector(
                          onTap: () => _showAddTargetDialog(context, provider, selectedMacro.id),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.backgroundMid,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _accentColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add, size: 16, color: _accentColor),
                                const SizedBox(width: 8),
                                Text(
                                  'Add Target',
                                  style: TextStyle(
                                    color: _accentColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTargetCard(
    BuildContext context,
    MacroControlProvider provider,
    MacroControl macro,
    MacroTarget target,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.backgroundMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: target.enabled ? macro.color.withValues(alpha: 0.5) : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // Enable toggle
                GestureDetector(
                  onTap: () => provider.toggleTargetEnabled(macro.id, target.id),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: target.enabled ? macro.color : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: target.enabled ? macro.color : FluxForgeTheme.textSecondary,
                      ),
                    ),
                    child: target.enabled
                        ? Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    target.displayName,
                    style: TextStyle(
                      color: target.enabled
                          ? FluxForgeTheme.textPrimary
                          : FluxForgeTheme.textSecondary,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Delete
                GestureDetector(
                  onTap: () => provider.removeTarget(macro.id, target.id),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Range
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text(
                  'Min: ${target.minValue.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                Text(
                  'Max: ${target.maxValue.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          // Curve selector
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Text(
                  'Curve:',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 8),
                ...MacroCurve.values.map((curve) {
                  final isSelected = target.curve == curve;
                  return GestureDetector(
                    onTap: () {
                      provider.updateTarget(
                        macro.id,
                        target.copyWith(curve: curve),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? macro.color.withValues(alpha: 0.3)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: isSelected ? macro.color : FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        _getCurveName(curve),
                        style: TextStyle(
                          color: isSelected ? macro.color : FluxForgeTheme.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // Bipolar toggle
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    provider.updateTarget(
                      macro.id,
                      target.copyWith(bipolar: !target.bipolar),
                    );
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: target.bipolar ? macro.color : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: target.bipolar ? macro.color : FluxForgeTheme.textSecondary,
                          ),
                        ),
                        child: target.bipolar
                            ? Icon(Icons.check, size: 10, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Bipolar',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getCurveName(MacroCurve curve) {
    switch (curve) {
      case MacroCurve.linear:
        return 'Lin';
      case MacroCurve.exponential:
        return 'Exp';
      case MacroCurve.logarithmic:
        return 'Log';
      case MacroCurve.sCurve:
        return 'S';
      case MacroCurve.step:
        return 'Step';
    }
  }

  void _showAddTargetDialog(BuildContext context, MacroControlProvider provider, String macroId) {
    showDialog(
      context: context,
      builder: (context) => _AddTargetDialog(
        macroId: macroId,
        provider: provider,
      ),
    );
  }

  Widget _buildFooter(BuildContext context, MacroControlProvider provider) {
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
          // Add Macro
          _buildFooterButton(
            'Add Macro',
            Icons.add,
            () => provider.addMacro(),
          ),
          const SizedBox(width: 8),
          // Reset All
          _buildFooterButton(
            'Reset All',
            Icons.refresh,
            () => provider.resetAllMacros(),
          ),
          const Spacer(),
          // Delete selected
          if (provider.selectedMacroId != null)
            _buildFooterButton(
              'Delete',
              Icons.delete_outline,
              () {
                provider.deleteMacro(provider.selectedMacroId!);
              },
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
// MACRO KNOB WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class _MacroKnob extends StatefulWidget {
  final MacroControl macro;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<double> onValueChanged;
  final VoidCallback onMidiLearn;
  final VoidCallback onReset;

  const _MacroKnob({
    required this.macro,
    required this.isSelected,
    required this.onTap,
    required this.onValueChanged,
    required this.onMidiLearn,
    required this.onReset,
  });

  @override
  State<_MacroKnob> createState() => _MacroKnobState();
}

class _MacroKnobState extends State<_MacroKnob> {
  double _dragStartValue = 0;
  double _dragStartY = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onReset,
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onLongPress: widget.onMidiLearn,
      child: Container(
        decoration: BoxDecoration(
          color: widget.isSelected
              ? widget.macro.color.withValues(alpha: 0.15)
              : FluxForgeTheme.backgroundMid,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.isSelected
                ? widget.macro.color
                : FluxForgeTheme.textSecondary.withValues(alpha: 0.2),
            width: widget.isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Knob
            CustomPaint(
              size: const Size(64, 64),
              painter: _KnobPainter(
                value: widget.macro.value,
                color: widget.macro.color,
              ),
            ),
            const SizedBox(height: 8),
            // Name
            Text(
              widget.macro.name,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            // Value
            Text(
              widget.macro.displayValue,
              style: TextStyle(
                color: widget.macro.color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            // MIDI CC indicator
            if (widget.macro.midiCC != null)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentCyan.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  'CC ${widget.macro.midiCC}',
                  style: TextStyle(
                    color: FluxForgeTheme.accentCyan,
                    fontSize: 8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartValue = widget.macro.value;
    _dragStartY = details.globalPosition.dy;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = (_dragStartY - details.globalPosition.dy) / 200.0;
    final newValue = (_dragStartValue + delta).clamp(0.0, 1.0);
    widget.onValueChanged(newValue);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// KNOB PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _KnobPainter extends CustomPainter {
  final double value;
  final Color color;

  _KnobPainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background arc
    final bgPaint = Paint()
      ..color = FluxForgeTheme.backgroundDeep
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    const startAngle = 0.75 * 3.14159; // 135 degrees
    const sweepAngle = 1.5 * 3.14159;  // 270 degrees

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * value,
      false,
      valuePaint,
    );

    // Center dot
    final centerPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius - 10, centerPaint);

    // Indicator dot
    final indicatorAngle = startAngle + sweepAngle * value;
    final indicatorPos = Offset(
      center.dx + (radius - 10) * 0.7 * cos(indicatorAngle),
      center.dy + (radius - 10) * 0.7 * sin(indicatorAngle),
    );

    final indicatorPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(indicatorPos, 3, indicatorPaint);
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.color != color;
  }
}

double cos(double x) => x.abs() < 0.0001 ? 1.0 : _cos(x);
double sin(double x) => x.abs() < 0.0001 ? 0.0 : _sin(x);

double _cos(double x) {
  double result = 1.0;
  double term = 1.0;
  for (int i = 1; i <= 10; i++) {
    term *= -x * x / (2 * i * (2 * i - 1));
    result += term;
  }
  return result;
}

double _sin(double x) {
  double result = x;
  double term = x;
  for (int i = 1; i <= 10; i++) {
    term *= -x * x / (2 * i * (2 * i + 1));
    result += term;
  }
  return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADD TARGET DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class _AddTargetDialog extends StatefulWidget {
  final String macroId;
  final MacroControlProvider provider;

  const _AddTargetDialog({
    required this.macroId,
    required this.provider,
  });

  @override
  State<_AddTargetDialog> createState() => _AddTargetDialogState();
}

class _AddTargetDialogState extends State<_AddTargetDialog> {
  int _trackId = 0;
  String _parameterName = 'Volume';
  String? _pluginId;
  double _minValue = 0.0;
  double _maxValue = 1.0;
  bool _bipolar = false;

  final _parameters = [
    'Volume',
    'Pan',
    'Mute',
    'Solo',
    'Send 1',
    'Send 2',
    'EQ Gain',
    'Compressor Threshold',
    'Filter Cutoff',
    'Filter Resonance',
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FluxForgeTheme.backgroundMid,
      title: Text(
        'Add Target',
        style: TextStyle(color: FluxForgeTheme.textPrimary),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Track ID
            Row(
              children: [
                Text('Track:', style: TextStyle(color: FluxForgeTheme.textSecondary)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<int>(
                    value: _trackId,
                    isExpanded: true,
                    dropdownColor: FluxForgeTheme.backgroundMid,
                    items: [
                      DropdownMenuItem(value: -1, child: Text('Master', style: TextStyle(color: FluxForgeTheme.textPrimary))),
                      for (int i = 0; i < 16; i++)
                        DropdownMenuItem(value: i, child: Text('Track ${i + 1}', style: TextStyle(color: FluxForgeTheme.textPrimary))),
                    ],
                    onChanged: (v) => setState(() => _trackId = v ?? 0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Parameter
            Row(
              children: [
                Text('Parameter:', style: TextStyle(color: FluxForgeTheme.textSecondary)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: _parameterName,
                    isExpanded: true,
                    dropdownColor: FluxForgeTheme.backgroundMid,
                    items: _parameters.map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(p, style: TextStyle(color: FluxForgeTheme.textPrimary)),
                    )).toList(),
                    onChanged: (v) => setState(() => _parameterName = v ?? 'Volume'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Range
            Row(
              children: [
                Text('Min:', style: TextStyle(color: FluxForgeTheme.textSecondary)),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _minValue,
                    onChanged: (v) => setState(() => _minValue = v),
                    activeColor: MacroControlsPanel._accentColor,
                  ),
                ),
                Text(_minValue.toStringAsFixed(2), style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11)),
              ],
            ),
            Row(
              children: [
                Text('Max:', style: TextStyle(color: FluxForgeTheme.textSecondary)),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _maxValue,
                    onChanged: (v) => setState(() => _maxValue = v),
                    activeColor: MacroControlsPanel._accentColor,
                  ),
                ),
                Text(_maxValue.toStringAsFixed(2), style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11)),
              ],
            ),
            // Bipolar
            Row(
              children: [
                Checkbox(
                  value: _bipolar,
                  onChanged: (v) => setState(() => _bipolar = v ?? false),
                  activeColor: MacroControlsPanel._accentColor,
                ),
                Text('Bipolar (center at 0.5)', style: TextStyle(color: FluxForgeTheme.textSecondary)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () {
            widget.provider.addTarget(
              widget.macroId,
              trackId: _trackId,
              parameterName: _parameterName,
              pluginId: _pluginId,
              minValue: _minValue,
              maxValue: _maxValue,
              bipolar: _bipolar,
            );
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: MacroControlsPanel._accentColor,
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
