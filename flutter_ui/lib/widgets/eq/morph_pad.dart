// Morph XY Pad Widget
//
// Professional preset morphing controller:
// - 4-corner preset blending
// - Smooth animation between states
// - Automation recording support
// - Visual feedback with gradient interpolation
// - Touch and mouse support
//
// Unique feature not found in Pro-Q or most EQs

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

/// Morph preset slot
class MorphPreset {
  final String name;
  final Color color;
  final Map<String, double> parameters;
  final IconData? icon;

  const MorphPreset({
    required this.name,
    required this.color,
    required this.parameters,
    this.icon,
  });

  MorphPreset copyWith({
    String? name,
    Color? color,
    Map<String, double>? parameters,
    IconData? icon,
  }) {
    return MorphPreset(
      name: name ?? this.name,
      color: color ?? this.color,
      parameters: parameters ?? this.parameters,
      icon: icon ?? this.icon,
    );
  }
}

/// Morphing mode
enum MorphMode {
  bilinear,    // Standard 4-corner blend
  radial,      // Distance-based from center
  custom,      // User-defined blend curve
}

/// Morph pad configuration
class MorphPadConfig {
  final MorphMode mode;
  final double smoothing;        // Parameter smoothing 0-1
  final bool showGrid;
  final bool showLabels;
  final bool showGradient;
  final bool enableAutomation;
  final Duration animationDuration;

  const MorphPadConfig({
    this.mode = MorphMode.bilinear,
    this.smoothing = 0.15,
    this.showGrid = true,
    this.showLabels = true,
    this.showGradient = true,
    this.enableAutomation = true,
    this.animationDuration = const Duration(milliseconds: 100),
  });
}

/// Callback for morphed parameter values
typedef MorphCallback = void Function(Map<String, double> parameters);

/// Morph XY Pad Widget
class MorphPad extends StatefulWidget {
  /// Preset in top-left corner (A)
  final MorphPreset? presetA;

  /// Preset in top-right corner (B)
  final MorphPreset? presetB;

  /// Preset in bottom-left corner (C)
  final MorphPreset? presetC;

  /// Preset in bottom-right corner (D)
  final MorphPreset? presetD;

  /// Current X position (0-1)
  final double? x;

  /// Current Y position (0-1)
  final double? y;

  /// Configuration
  final MorphPadConfig config;

  /// Callback when position changes
  final ValueChanged<Offset>? onPositionChanged;

  /// Callback with interpolated parameters
  final MorphCallback? onParametersChanged;

  /// Callback when preset slot is tapped
  final ValueChanged<int>? onPresetSlotTapped;

  /// Widget size
  final double? size;

  const MorphPad({
    super.key,
    this.presetA,
    this.presetB,
    this.presetC,
    this.presetD,
    this.x,
    this.y,
    this.config = const MorphPadConfig(),
    this.onPositionChanged,
    this.onParametersChanged,
    this.onPresetSlotTapped,
    this.size,
  });

  @override
  State<MorphPad> createState() => _MorphPadState();
}

class _MorphPadState extends State<MorphPad>
    with SingleTickerProviderStateMixin {

  // Position state
  double _x = 0.5;
  double _y = 0.5;
  double _targetX = 0.5;
  double _targetY = 0.5;

  // Animation
  late AnimationController _animController;

  // Interaction state
  bool _isDragging = false;
  int? _hoveredCorner;

  // Colors
  static const _bgDark = Color(0xFF0D0D12);
  static const _gridColor = Color(0xFF2A2A35);

  // Default corner colors
  static const _defaultColors = [
    Color(0xFF4A9EFF),  // A - Blue
    Color(0xFFFF9040),  // B - Orange
    Color(0xFF40FF90),  // C - Green
    Color(0xFFFF4090),  // D - Pink
  ];

  @override
  void initState() {
    super.initState();
    _x = widget.x ?? 0.5;
    _y = widget.y ?? 0.5;
    _targetX = _x;
    _targetY = _y;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updatePosition);
    _animController.repeat();
  }

  @override
  void didUpdateWidget(MorphPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.x != null && widget.x != _targetX) {
      _targetX = widget.x!;
    }
    if (widget.y != null && widget.y != _targetY) {
      _targetY = widget.y!;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _updatePosition() {
    if (!_isDragging) {
      // Smooth animation toward target
      final smoothing = widget.config.smoothing;
      _x = _x + (_targetX - _x) * (1 - smoothing);
      _y = _y + (_targetY - _y) * (1 - smoothing);
    }

    // Calculate and emit morphed parameters
    _emitMorphedParameters();

    setState(() {});
  }

  void _emitMorphedParameters() {
    final params = _interpolateParameters(_x, _y);
    widget.onParametersChanged?.call(params);
  }

  Map<String, double> _interpolateParameters(double x, double y) {
    final result = <String, double>{};

    // Collect all parameter keys
    final allKeys = <String>{};
    if (widget.presetA != null) allKeys.addAll(widget.presetA!.parameters.keys);
    if (widget.presetB != null) allKeys.addAll(widget.presetB!.parameters.keys);
    if (widget.presetC != null) allKeys.addAll(widget.presetC!.parameters.keys);
    if (widget.presetD != null) allKeys.addAll(widget.presetD!.parameters.keys);

    for (final key in allKeys) {
      final a = widget.presetA?.parameters[key] ?? 0;
      final b = widget.presetB?.parameters[key] ?? 0;
      final c = widget.presetC?.parameters[key] ?? 0;
      final d = widget.presetD?.parameters[key] ?? 0;

      // Bilinear interpolation
      final top = a + (b - a) * x;
      final bottom = c + (d - c) * x;
      result[key] = top + (bottom - top) * y;
    }

    return result;
  }

  Color _interpolateColor(double x, double y) {
    final a = widget.presetA?.color ?? _defaultColors[0];
    final b = widget.presetB?.color ?? _defaultColors[1];
    final c = widget.presetC?.color ?? _defaultColors[2];
    final d = widget.presetD?.color ?? _defaultColors[3];

    final top = Color.lerp(a, b, x)!;
    final bottom = Color.lerp(c, d, x)!;
    return Color.lerp(top, bottom, y)!;
  }

  void _onPanStart(DragStartDetails details) {
    setState(() => _isDragging = true);
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final padSize = size.width;
    final newX = (details.localPosition.dx / padSize).clamp(0.0, 1.0);
    final newY = (details.localPosition.dy / padSize).clamp(0.0, 1.0);

    setState(() {
      _x = newX;
      _y = newY;
      _targetX = newX;
      _targetY = newY;
    });

    widget.onPositionChanged?.call(Offset(newX, newY));
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
  }

  void _onTapUp(TapUpDetails details, Size size) {
    final padSize = size.width;
    final x = details.localPosition.dx / padSize;
    final y = details.localPosition.dy / padSize;

    // Check if tap is in corner zones
    const cornerSize = 0.15;

    if (x < cornerSize && y < cornerSize) {
      widget.onPresetSlotTapped?.call(0);  // A
    } else if (x > 1 - cornerSize && y < cornerSize) {
      widget.onPresetSlotTapped?.call(1);  // B
    } else if (x < cornerSize && y > 1 - cornerSize) {
      widget.onPresetSlotTapped?.call(2);  // C
    } else if (x > 1 - cornerSize && y > 1 - cornerSize) {
      widget.onPresetSlotTapped?.call(3);  // D
    } else {
      // Move to tapped position
      _targetX = x.clamp(0.0, 1.0);
      _targetY = y.clamp(0.0, 1.0);
      widget.onPositionChanged?.call(Offset(_targetX, _targetY));
    }
  }

  void _onHover(PointerHoverEvent event, Size size) {
    final padSize = size.width;
    final x = event.localPosition.dx / padSize;
    final y = event.localPosition.dy / padSize;

    int? hovered;
    const cornerSize = 0.15;

    if (x < cornerSize && y < cornerSize) {
      hovered = 0;
    } else if (x > 1 - cornerSize && y < cornerSize) {
      hovered = 1;
    } else if (x < cornerSize && y > 1 - cornerSize) {
      hovered = 2;
    } else if (x > 1 - cornerSize && y > 1 - cornerSize) {
      hovered = 3;
    }

    if (hovered != _hoveredCorner) {
      setState(() => _hoveredCorner = hovered);
    }
  }

  void _onExit(PointerExitEvent event) {
    setState(() => _hoveredCorner = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = widget.size ?? math.min(constraints.maxWidth, constraints.maxHeight);

        return MouseRegion(
          onHover: (e) => _onHover(e, Size(size, size)),
          onExit: _onExit,
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: (d) => _onPanUpdate(d, Size(size, size)),
            onPanEnd: _onPanEnd,
            onTapUp: (d) => _onTapUp(d, Size(size, size)),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _gridColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: ReelForgeTheme.bgVoid.withAlpha(77),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CustomPaint(
                  size: Size(size, size),
                  painter: _MorphPadPainter(
                    x: _x,
                    y: _y,
                    presetA: widget.presetA,
                    presetB: widget.presetB,
                    presetC: widget.presetC,
                    presetD: widget.presetD,
                    config: widget.config,
                    hoveredCorner: _hoveredCorner,
                    isDragging: _isDragging,
                    cursorColor: _interpolateColor(_x, _y),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MorphPadPainter extends CustomPainter {
  final double x;
  final double y;
  final MorphPreset? presetA;
  final MorphPreset? presetB;
  final MorphPreset? presetC;
  final MorphPreset? presetD;
  final MorphPadConfig config;
  final int? hoveredCorner;
  final bool isDragging;
  final Color cursorColor;

  static const _defaultColors = [
    Color(0xFF4A9EFF),
    Color(0xFFFF9040),
    Color(0xFF40FF90),
    Color(0xFFFF4090),
  ];

  _MorphPadPainter({
    required this.x,
    required this.y,
    this.presetA,
    this.presetB,
    this.presetC,
    this.presetD,
    required this.config,
    this.hoveredCorner,
    required this.isDragging,
    required this.cursorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw gradient background
    if (config.showGradient) {
      _drawGradientBackground(canvas, size);
    }

    // Draw grid
    if (config.showGrid) {
      _drawGrid(canvas, size);
    }

    // Draw corner indicators
    _drawCornerIndicators(canvas, size);

    // Draw cursor trail
    _drawCursorTrail(canvas, size);

    // Draw main cursor
    _drawCursor(canvas, size);

    // Draw labels
    if (config.showLabels) {
      _drawLabels(canvas, size);
    }
  }

  void _drawGradientBackground(Canvas canvas, Size size) {
    final a = presetA?.color ?? _defaultColors[0];
    final b = presetB?.color ?? _defaultColors[1];
    final c = presetC?.color ?? _defaultColors[2];
    final d = presetD?.color ?? _defaultColors[3];

    // Create mesh gradient effect using multiple overlapping gradients
    final paint = Paint();

    // Top-left to bottom-right diagonal
    paint.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(size.width, size.height),
      [
        a.withAlpha(77),
        d.withAlpha(77),
      ],
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Top-right to bottom-left diagonal
    paint.shader = ui.Gradient.linear(
      Offset(size.width, 0),
      Offset(0, size.height),
      [
        b.withAlpha(77),
        c.withAlpha(77),
      ],
    );
    paint.blendMode = BlendMode.plus;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Radial gradient at cursor position for local color emphasis
    paint.shader = ui.Gradient.radial(
      Offset(x * size.width, y * size.height),
      size.width * 0.4,
      [
        cursorColor.withAlpha(51),
        Colors.transparent,
      ],
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2A2A35)
      ..strokeWidth = 1;

    // Main grid lines
    const divisions = 4;
    for (int i = 1; i < divisions; i++) {
      final t = i / divisions;

      // Vertical
      canvas.drawLine(
        Offset(size.width * t, 0),
        Offset(size.width * t, size.height),
        paint,
      );

      // Horizontal
      canvas.drawLine(
        Offset(0, size.height * t),
        Offset(size.width, size.height * t),
        paint,
      );
    }

    // Center crosshair
    paint.color = const Color(0xFF3A3A45);
    paint.strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width / 2, size.height * 0.3),
      Offset(size.width / 2, size.height * 0.7),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.3, size.height / 2),
      Offset(size.width * 0.7, size.height / 2),
      paint,
    );
  }

  void _drawCornerIndicators(Canvas canvas, Size size) {
    final corners = [
      Offset(0, 0),
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];

    final colors = [
      presetA?.color ?? _defaultColors[0],
      presetB?.color ?? _defaultColors[1],
      presetC?.color ?? _defaultColors[2],
      presetD?.color ?? _defaultColors[3],
    ];

    final presets = [presetA, presetB, presetC, presetD];

    for (int i = 0; i < 4; i++) {
      final corner = corners[i];
      final color = colors[i];
      final preset = presets[i];
      final isHovered = hoveredCorner == i;

      // Corner glow
      final glowRadius = isHovered ? 60.0 : 40.0;
      final glowPaint = Paint()
        ..shader = ui.Gradient.radial(
          corner,
          glowRadius,
          [
            color.withAlpha(isHovered ? 102 : 51),
            Colors.transparent,
          ],
        );
      canvas.drawCircle(corner, glowRadius, glowPaint);

      // Corner marker
      final markerSize = isHovered ? 16.0 : 12.0;
      final markerOffset = Offset(
        corner.dx + (i % 2 == 0 ? markerSize : -markerSize),
        corner.dy + (i < 2 ? markerSize : -markerSize),
      );

      canvas.drawCircle(
        markerOffset,
        markerSize / 2,
        Paint()..color = color,
      );

      // Preset initial/icon
      if (preset != null) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: preset.icon != null ? '' : preset.name.substring(0, 1),
            style: TextStyle(
              color: ReelForgeTheme.textPrimary.withAlpha(isHovered ? 255 : 179),
              fontSize: isHovered ? 11 : 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        textPainter.paint(
          canvas,
          Offset(
            markerOffset.dx - textPainter.width / 2,
            markerOffset.dy - textPainter.height / 2,
          ),
        );
      }
    }
  }

  void _drawCursorTrail(Canvas canvas, Size size) {
    // Subtle trail effect
    final trailPaint = Paint()
      ..color = cursorColor.withAlpha(51)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Horizontal trail
    canvas.drawLine(
      Offset(0, y * size.height),
      Offset(x * size.width, y * size.height),
      trailPaint,
    );

    // Vertical trail
    canvas.drawLine(
      Offset(x * size.width, 0),
      Offset(x * size.width, y * size.height),
      trailPaint,
    );
  }

  void _drawCursor(Canvas canvas, Size size) {
    final center = Offset(x * size.width, y * size.height);
    final cursorSize = isDragging ? 20.0 : 16.0;

    // Outer glow
    final glowPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        cursorSize * 2,
        [
          cursorColor.withAlpha(77),
          Colors.transparent,
        ],
      );
    canvas.drawCircle(center, cursorSize * 2, glowPaint);

    // Outer ring
    canvas.drawCircle(
      center,
      cursorSize,
      Paint()
        ..color = ReelForgeTheme.textPrimary.withAlpha(77)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Inner fill
    canvas.drawCircle(
      center,
      cursorSize - 3,
      Paint()..color = cursorColor,
    );

    // Highlight
    canvas.drawCircle(
      Offset(center.dx - 3, center.dy - 3),
      4,
      Paint()..color = ReelForgeTheme.textPrimary.withAlpha(128),
    );

    // Center dot
    canvas.drawCircle(
      center,
      3,
      Paint()..color = ReelForgeTheme.textPrimary,
    );
  }

  void _drawLabels(Canvas canvas, Size size) {
    final presets = [
      (presetA, Offset(8, 8)),
      (presetB, Offset(size.width - 8, 8)),
      (presetC, Offset(8, size.height - 8)),
      (presetD, Offset(size.width - 8, size.height - 8)),
    ];

    final aligns = [
      TextAlign.left,
      TextAlign.right,
      TextAlign.left,
      TextAlign.right,
    ];

    for (int i = 0; i < 4; i++) {
      final preset = presets[i].$1;
      final pos = presets[i].$2;
      final align = aligns[i];

      if (preset != null) {
        final isHovered = hoveredCorner == i;

        final textPainter = TextPainter(
          text: TextSpan(
            text: preset.name,
            style: TextStyle(
              color: ReelForgeTheme.textPrimary.withAlpha(isHovered ? 230 : 128),
              fontSize: 10,
              fontWeight: isHovered ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: align,
        )..layout();

        double dx = pos.dx;
        double dy = pos.dy;

        // Adjust position based on corner
        if (i == 1 || i == 3) dx -= textPainter.width;
        if (i == 2 || i == 3) dy -= textPainter.height;

        textPainter.paint(canvas, Offset(dx, dy));
      }
    }

    // Draw current position indicator
    final posText = '${(x * 100).toInt()}%, ${(y * 100).toInt()}%';
    final posPainter = TextPainter(
      text: TextSpan(
        text: posText,
        style: TextStyle(
          color: cursorColor.withAlpha(179),
          fontSize: 9,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    posPainter.paint(
      canvas,
      Offset(
        (size.width - posPainter.width) / 2,
        size.height - posPainter.height - 8,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _MorphPadPainter oldDelegate) {
    return x != oldDelegate.x ||
        y != oldDelegate.y ||
        hoveredCorner != oldDelegate.hoveredCorner ||
        isDragging != oldDelegate.isDragging ||
        cursorColor != oldDelegate.cursorColor;
  }
}

/// Compact version for toolbar/strip usage
class MorphPadMini extends StatelessWidget {
  final MorphPreset? presetA;
  final MorphPreset? presetB;
  final MorphPreset? presetC;
  final MorphPreset? presetD;
  final double x;
  final double y;
  final ValueChanged<Offset>? onPositionChanged;
  final double size;

  const MorphPadMini({
    super.key,
    this.presetA,
    this.presetB,
    this.presetC,
    this.presetD,
    this.x = 0.5,
    this.y = 0.5,
    this.onPositionChanged,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return MorphPad(
      presetA: presetA,
      presetB: presetB,
      presetC: presetC,
      presetD: presetD,
      x: x,
      y: y,
      onPositionChanged: onPositionChanged,
      size: size,
      config: const MorphPadConfig(
        showGrid: false,
        showLabels: false,
        showGradient: true,
      ),
    );
  }
}

/// Morph Pad with preset selector
class MorphPadWithSelector extends StatefulWidget {
  final List<MorphPreset> availablePresets;
  final MorphPreset? initialA;
  final MorphPreset? initialB;
  final MorphPreset? initialC;
  final MorphPreset? initialD;
  final MorphCallback? onParametersChanged;

  const MorphPadWithSelector({
    super.key,
    required this.availablePresets,
    this.initialA,
    this.initialB,
    this.initialC,
    this.initialD,
    this.onParametersChanged,
  });

  @override
  State<MorphPadWithSelector> createState() => _MorphPadWithSelectorState();
}

class _MorphPadWithSelectorState extends State<MorphPadWithSelector> {
  late MorphPreset? _presetA;
  late MorphPreset? _presetB;
  late MorphPreset? _presetC;
  late MorphPreset? _presetD;
  double _x = 0.5;
  double _y = 0.5;

  @override
  void initState() {
    super.initState();
    _presetA = widget.initialA;
    _presetB = widget.initialB;
    _presetC = widget.initialC;
    _presetD = widget.initialD;
  }

  void _selectPresetForSlot(int slot) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A24),
      builder: (context) => _PresetSelectorSheet(
        presets: widget.availablePresets,
        onSelect: (preset) {
          setState(() {
            switch (slot) {
              case 0:
                _presetA = preset;
                break;
              case 1:
                _presetB = preset;
                break;
              case 2:
                _presetC = preset;
                break;
              case 3:
                _presetD = preset;
                break;
            }
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MorphPad(
          presetA: _presetA,
          presetB: _presetB,
          presetC: _presetC,
          presetD: _presetD,
          x: _x,
          y: _y,
          onPositionChanged: (pos) {
            setState(() {
              _x = pos.dx;
              _y = pos.dy;
            });
          },
          onParametersChanged: widget.onParametersChanged,
          onPresetSlotTapped: _selectPresetForSlot,
        ),
        const SizedBox(height: 8),
        Text(
          'Tap corners to assign presets',
          style: TextStyle(
            fontSize: 11,
            color: ReelForgeTheme.textPrimary.withAlpha(128),
          ),
        ),
      ],
    );
  }
}

class _PresetSelectorSheet extends StatelessWidget {
  final List<MorphPreset> presets;
  final ValueChanged<MorphPreset> onSelect;

  const _PresetSelectorSheet({
    required this.presets,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Preset',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: ReelForgeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presets.map((preset) {
              return GestureDetector(
                onTap: () => onSelect(preset),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: preset.color.withAlpha(51),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: preset.color),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: preset.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        preset.name,
                        style: const TextStyle(
                          fontSize: 13,
                          color: ReelForgeTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
