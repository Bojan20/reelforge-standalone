/// P-ICF: Intensity Crossfade Wizard UI
///
/// Interactive wizard for configuring RTPC-driven intensity crossfades.
/// Supersedes ReelToReel's x-fade-levels with full RTPC power.
///
/// Features:
/// - Variant list management (add/remove/reorder audio files)
/// - RTPC parameter configuration (name, range)
/// - Crossfade curve selection with visual preview
/// - Live preview slider showing active layers and volumes
/// - DSP auto-chain options (LPF sweep, pitch offset)
/// - Template save/load
/// - One-click event generation
library;

import 'package:flutter/material.dart';
import '../../models/middleware_models.dart';
import '../../services/intensity_crossfade_service.dart';
import '../../theme/fluxforge_theme.dart';

class IntensityCrossfadeWizard extends StatefulWidget {
  /// Callback when user generates an event from the wizard
  final void Function(MiddlewareEvent event, IntensityCrossfadeConfig config)? onGenerate;

  const IntensityCrossfadeWizard({super.key, this.onGenerate});

  @override
  State<IntensityCrossfadeWizard> createState() => _IntensityCrossfadeWizardState();
}

class _IntensityCrossfadeWizardState extends State<IntensityCrossfadeWizard> {
  final _service = IntensityCrossfadeService.instance;

  // Config state
  String _rtpcName = 'intensity';
  double _rtpcMin = 0.0;
  double _rtpcMax = 100.0;
  final List<String> _variants = [];
  double _overlapPercent = 0.2;
  CrossfadeCurveType _curveType = CrossfadeCurveType.equalPower;
  String _bus = 'Music';
  bool _loop = true;
  bool _enableLpf = false;
  bool _enablePitch = false;

  // Preview state
  double _previewValue = 50.0;

  // Text controllers
  late final TextEditingController _rtpcNameCtrl;
  late final TextEditingController _variantPathCtrl;

  @override
  void initState() {
    super.initState();
    _rtpcNameCtrl = TextEditingController(text: _rtpcName);
    _variantPathCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _rtpcNameCtrl.dispose();
    _variantPathCtrl.dispose();
    super.dispose();
  }

  IntensityCrossfadeConfig _buildConfig() {
    return IntensityCrossfadeConfig(
      rtpcName: _rtpcName,
      rtpcMin: _rtpcMin,
      rtpcMax: _rtpcMax,
      variants: _variants,
      overlapPercent: _overlapPercent,
      curveType: _curveType,
      bus: _bus,
      loop: _loop,
      dspConfig: (_enableLpf || _enablePitch)
          ? DspAutoChainConfig(
              enableLpfSweep: _enableLpf,
              enablePitchOffset: _enablePitch,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.bgElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildRtpcConfig(),
                  const SizedBox(height: 12),
                  _buildVariantList(),
                  const SizedBox(height: 12),
                  _buildCurveSelector(),
                  const SizedBox(height: 12),
                  _buildLivePreview(),
                  const SizedBox(height: 12),
                  _buildDspOptions(),
                  const SizedBox(height: 12),
                  _buildBusAndLoop(),
                  const SizedBox(height: 16),
                  _buildGenerateButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HEADER ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 16, color: Colors.cyan.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          Text(
            'Intensity Crossfade Wizard',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Template dropdown
          if (_service.templateNames.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Load template',
              icon: Icon(Icons.bookmark_outline, size: 16, color: FluxForgeTheme.textTertiary),
              onSelected: (name) {
                final tpl = _service.loadTemplate(name);
                if (tpl != null) _applyTemplate(tpl);
              },
              itemBuilder: (ctx) => _service.templateNames
                  .map((n) => PopupMenuItem(value: n, child: Text(n, style: const TextStyle(fontSize: 12))))
                  .toList(),
            ),
        ],
      ),
    );
  }

  // ─── RTPC CONFIG ────────────────────────────────────────────────────────────

  Widget _buildRtpcConfig() {
    return _section('RTPC Parameter', [
      Row(
        children: [
          Expanded(
            flex: 3,
            child: _textField('Name', _rtpcNameCtrl, (v) {
              setState(() => _rtpcName = v);
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _numberLabel('Min', _rtpcMin, (v) {
              setState(() => _rtpcMin = v);
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _numberLabel('Max', _rtpcMax, (v) {
              setState(() => _rtpcMax = v);
            }),
          ),
        ],
      ),
    ]);
  }

  // ─── VARIANT LIST ───────────────────────────────────────────────────────────

  Widget _buildVariantList() {
    return _section('Audio Variants (${_variants.length})', [
      // Add variant input
      Row(
        children: [
          Expanded(
            child: _textField('Audio path...', _variantPathCtrl, null),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            tooltip: 'Add variant',
            onPressed: () {
              final path = _variantPathCtrl.text.trim();
              if (path.isNotEmpty) {
                setState(() {
                  _variants.add(path);
                  _variantPathCtrl.clear();
                });
              }
            },
            style: IconButton.styleFrom(
              backgroundColor: Colors.cyan.withValues(alpha: 0.15),
              foregroundColor: Colors.cyan,
              minimumSize: const Size(28, 28),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      // Variant list
      if (_variants.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Add audio variants ordered from low to high intensity',
            style: TextStyle(
              color: FluxForgeTheme.textTertiary,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        )
      else
        ...List.generate(_variants.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Text(
                    '${i + 1}.',
                    style: TextStyle(
                      color: Colors.cyan.withValues(alpha: 0.6),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _variants[i].split('/').last,
                      style: TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Move up
                  if (i > 0)
                    InkWell(
                      onTap: () => setState(() {
                        final tmp = _variants[i];
                        _variants[i] = _variants[i - 1];
                        _variants[i - 1] = tmp;
                      }),
                      child: Icon(Icons.arrow_upward, size: 14, color: FluxForgeTheme.textTertiary),
                    ),
                  // Move down
                  if (i < _variants.length - 1)
                    InkWell(
                      onTap: () => setState(() {
                        final tmp = _variants[i];
                        _variants[i] = _variants[i + 1];
                        _variants[i + 1] = tmp;
                      }),
                      child: Icon(Icons.arrow_downward, size: 14, color: FluxForgeTheme.textTertiary),
                    ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => setState(() => _variants.removeAt(i)),
                    child: Icon(Icons.close, size: 14, color: Colors.red.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          );
        }),
      // Overlap slider
      const SizedBox(height: 8),
      Row(
        children: [
          Text(
            'Overlap: ${(_overlapPercent * 100).round()}%',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10),
          ),
          Expanded(
            child: Slider(
              value: _overlapPercent,
              min: 0.05,
              max: 0.5,
              divisions: 9,
              onChanged: (v) => setState(() => _overlapPercent = v),
              activeColor: Colors.cyan,
              inactiveColor: FluxForgeTheme.bgElevated,
            ),
          ),
        ],
      ),
    ]);
  }

  // ─── CURVE SELECTOR ─────────────────────────────────────────────────────────

  Widget _buildCurveSelector() {
    return _section('Crossfade Curve', [
      Row(
        children: CrossfadeCurveType.values.map((curve) {
          final selected = curve == _curveType;
          final label = switch (curve) {
            CrossfadeCurveType.equalPower => 'Equal Power',
            CrossfadeCurveType.linear => 'Linear',
            CrossfadeCurveType.sCurve => 'S-Curve',
          };
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                onTap: () => setState(() => _curveType = curve),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.cyan.withValues(alpha: 0.2)
                        : FluxForgeTheme.bgSurface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: selected ? Colors.cyan : FluxForgeTheme.bgElevated,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected ? Colors.cyan : FluxForgeTheme.textTertiary,
                        fontSize: 10,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ]);
  }

  // ─── P-ICF-5: LIVE PREVIEW ─────────────────────────────────────────────────

  Widget _buildLivePreview() {
    if (_variants.length < 2) {
      return _section('Live Preview', [
        Text(
          'Add at least 2 variants to see crossfade preview',
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 10,
            fontStyle: FontStyle.italic,
          ),
        ),
      ]);
    }

    final config = _buildConfig();
    final ranges = _service.calculateRanges(config);

    return _section('Live Preview', [
      // RTPC slider
      Row(
        children: [
          Text(
            _rtpcName,
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10),
          ),
          Expanded(
            child: Slider(
              value: _previewValue.clamp(_rtpcMin, _rtpcMax),
              min: _rtpcMin,
              max: _rtpcMax,
              onChanged: (v) => setState(() => _previewValue = v),
              activeColor: Colors.cyan,
              inactiveColor: FluxForgeTheme.bgElevated,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              _previewValue.toStringAsFixed(1),
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      // Volume bars per variant
      ...ranges.map((range) {
        final vol = range.volumeAt(_previewValue, _curveType);
        final fileName = range.audioPath.split('/').last;
        final isActive = vol > 0.01;

        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  '${range.index + 1}',
                  style: TextStyle(
                    color: isActive ? Colors.cyan : FluxForgeTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  fileName,
                  style: TextStyle(
                    color: isActive ? FluxForgeTheme.textSecondary : FluxForgeTheme.textTertiary,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgSurface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: vol,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.cyan.withValues(alpha: 0.3),
                            Colors.cyan.withValues(alpha: 0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 35,
                child: Text(
                  '${(vol * 100).round()}%',
                  style: TextStyle(
                    color: isActive ? Colors.cyan : FluxForgeTheme.textTertiary,
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }),
      const SizedBox(height: 6),
      // Crossfade curve visualization
      SizedBox(
        height: 60,
        child: CustomPaint(
          painter: _CrossfadeCurvePainter(
            ranges: ranges,
            curveType: _curveType,
            rtpcMin: _rtpcMin,
            rtpcMax: _rtpcMax,
            currentValue: _previewValue,
          ),
          size: Size.infinite,
        ),
      ),
    ]);
  }

  // ─── DSP OPTIONS ────────────────────────────────────────────────────────────

  Widget _buildDspOptions() {
    return _section('DSP Auto-Chain (optional)', [
      Row(
        children: [
          _toggleChip('LPF Sweep', _enableLpf, (v) => setState(() => _enableLpf = v)),
          const SizedBox(width: 8),
          _toggleChip('Pitch Offset', _enablePitch, (v) => setState(() => _enablePitch = v)),
        ],
      ),
    ]);
  }

  // ─── BUS & LOOP ─────────────────────────────────────────────────────────────

  Widget _buildBusAndLoop() {
    return _section('Output', [
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _bus,
              decoration: InputDecoration(
                labelText: 'Bus',
                labelStyle: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                isDense: true,
              ),
              dropdownColor: FluxForgeTheme.bgSurface,
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
              items: ['Master', 'Music', 'SFX', 'Ambience', 'Voice', 'UI']
                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                  .toList(),
              onChanged: (v) => setState(() => _bus = v ?? 'Music'),
            ),
          ),
          const SizedBox(width: 12),
          _toggleChip('Loop', _loop, (v) => setState(() => _loop = v)),
        ],
      ),
    ]);
  }

  // ─── GENERATE BUTTON ───────────────────────────────────────────────────────

  Widget _buildGenerateButton() {
    final canGenerate = _variants.length >= 2 && _rtpcName.isNotEmpty;

    return Row(
      children: [
        // Save as template
        TextButton.icon(
          onPressed: canGenerate
              ? () {
                  _showSaveTemplateDialog();
                }
              : null,
          icon: Icon(Icons.bookmark_add, size: 14, color: canGenerate ? Colors.cyan : FluxForgeTheme.textTertiary),
          label: Text(
            'Save Template',
            style: TextStyle(
              color: canGenerate ? Colors.cyan : FluxForgeTheme.textTertiary,
              fontSize: 11,
            ),
          ),
        ),
        const Spacer(),
        // Generate event
        ElevatedButton.icon(
          onPressed: canGenerate
              ? () {
                  final config = _buildConfig();
                  final event = _service.generateEvent(config);
                  widget.onGenerate?.call(event, config);
                }
              : null,
          icon: const Icon(Icons.auto_awesome, size: 14),
          label: const Text('Generate Event', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: canGenerate ? Colors.cyan : FluxForgeTheme.bgElevated,
            foregroundColor: canGenerate ? Colors.white : FluxForgeTheme.textTertiary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ],
    );
  }

  // ─── HELPERS ────────────────────────────────────────────────────────────────

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        ...children,
      ],
    );
  }

  Widget _textField(String hint, TextEditingController ctrl, void Function(String)? onChanged) {
    return TextField(
      controller: ctrl,
      onChanged: onChanged,
      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        isDense: true,
      ),
    );
  }

  Widget _numberLabel(String label, double value, void Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9)),
        Text(
          value.toStringAsFixed(0),
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _toggleChip(String label, bool value, void Function(bool) onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: value ? Colors.cyan.withValues(alpha: 0.15) : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: value ? Colors.cyan.withValues(alpha: 0.5) : FluxForgeTheme.bgElevated,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: value ? Colors.cyan : FluxForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: value ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  void _applyTemplate(IntensityCrossfadeConfig config) {
    setState(() {
      _rtpcName = config.rtpcName;
      _rtpcNameCtrl.text = config.rtpcName;
      _rtpcMin = config.rtpcMin;
      _rtpcMax = config.rtpcMax;
      _variants
        ..clear()
        ..addAll(config.variants);
      _overlapPercent = config.overlapPercent;
      _curveType = config.curveType;
      _bus = config.bus;
      _loop = config.loop;
      _enableLpf = config.dspConfig?.enableLpfSweep ?? false;
      _enablePitch = config.dspConfig?.enablePitchOffset ?? false;
    });
  }

  void _showSaveTemplateDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgSurface,
        title: Text('Save Template', style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Template name...',
            hintStyle: TextStyle(color: FluxForgeTheme.textTertiary),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textTertiary)),
          ),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                final config = _buildConfig();
                _service.saveTemplate(IntensityCrossfadeConfig(
                  rtpcName: config.rtpcName,
                  rtpcMin: config.rtpcMin,
                  rtpcMax: config.rtpcMax,
                  variants: config.variants,
                  overlapPercent: config.overlapPercent,
                  curveType: config.curveType,
                  bus: config.bus,
                  loop: config.loop,
                  dspConfig: config.dspConfig,
                  templateName: name,
                ));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.cyan)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CROSSFADE CURVE PAINTER — Visual curve preview
// =============================================================================

class _CrossfadeCurvePainter extends CustomPainter {
  final List<VariantRange> ranges;
  final CrossfadeCurveType curveType;
  final double rtpcMin;
  final double rtpcMax;
  final double currentValue;

  _CrossfadeCurvePainter({
    required this.ranges,
    required this.curveType,
    required this.rtpcMin,
    required this.rtpcMax,
    required this.currentValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (ranges.isEmpty || size.width <= 0 || size.height <= 0) return;

    final rtpcRange = rtpcMax - rtpcMin;
    if (rtpcRange <= 0) return;

    // Draw each variant's curve
    final colors = [
      Colors.cyan,
      Colors.lime,
      Colors.amber,
      Colors.pink,
      Colors.purple,
      Colors.teal,
      Colors.orange,
      Colors.indigo,
    ];

    for (final range in ranges) {
      final paint = Paint()
        ..color = colors[range.index % colors.length].withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      final fillPaint = Paint()
        ..color = colors[range.index % colors.length].withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;

      final path = Path();
      final fillPath = Path();
      bool started = false;

      for (double x = 0; x <= size.width; x += 1) {
        final rtpcVal = rtpcMin + (x / size.width) * rtpcRange;
        final vol = range.volumeAt(rtpcVal, curveType);
        final y = size.height - (vol * size.height);

        if (!started) {
          path.moveTo(x, y);
          fillPath.moveTo(x, size.height);
          fillPath.lineTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
          fillPath.lineTo(x, y);
        }
      }

      fillPath.lineTo(size.width, size.height);
      fillPath.close();

      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(path, paint);
    }

    // Draw current value line
    final lineX = ((currentValue - rtpcMin) / rtpcRange) * size.width;
    canvas.drawLine(
      Offset(lineX, 0),
      Offset(lineX, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _CrossfadeCurvePainter oldDelegate) {
    return oldDelegate.currentValue != currentValue ||
        oldDelegate.curveType != curveType ||
        oldDelegate.ranges.length != ranges.length;
  }
}
