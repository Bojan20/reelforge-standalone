/// Track Color Picker (P3.4) — Color customization for tracks/channels
///
/// Features:
/// - 16 preset colors for quick selection
/// - Custom color picker with hue/saturation/lightness
/// - Right-click popup menu for tracks
/// - Persists to MixerProvider.channelColors
///
/// Created: 2026-01-29
library;

import 'package:flutter/material.dart';
import '../../../../theme/fluxforge_theme.dart';

/// Preset track colors (DAW industry standard palette)
class TrackColorPresets {
  TrackColorPresets._();

  /// 16 preset colors matching DAW standards (Cubase, Pro Tools, Logic)
  static const List<Color> presets = [
    // Row 1: Primary colors
    Color(0xFFFF4040), // Red
    Color(0xFFFF9040), // Orange
    Color(0xFFFFD040), // Yellow
    Color(0xFF90FF40), // Lime

    // Row 2: Greens and Cyans
    Color(0xFF40FF40), // Green
    Color(0xFF40FF90), // Mint
    Color(0xFF40FFD0), // Teal
    Color(0xFF40D0FF), // Cyan

    // Row 3: Blues and Purples
    Color(0xFF4090FF), // Blue
    Color(0xFF4040FF), // Indigo
    Color(0xFF9040FF), // Violet
    Color(0xFFD040FF), // Magenta

    // Row 4: Pinks and Neutrals
    Color(0xFFFF40D0), // Pink
    Color(0xFFFF4090), // Rose
    Color(0xFFB0B0B0), // Gray
    Color(0xFFF0F0F0), // White
  ];

  /// Default color for new tracks
  static const Color defaultColor = Color(0xFF4A9EFF);

  /// Get next color in sequence (for auto-assignment)
  static Color getNextColor(int index) {
    return presets[index % presets.length];
  }
}

/// Compact color picker popup for track headers
class TrackColorPicker extends StatefulWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback? onClose;

  const TrackColorPicker({
    super.key,
    required this.currentColor,
    required this.onColorChanged,
    this.onClose,
  });

  /// Show as popup menu at position
  static Future<Color?> showAtPosition(
    BuildContext context, {
    required Offset position,
    required Color currentColor,
  }) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    return showMenu<Color>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      constraints: const BoxConstraints(maxWidth: 200),
      items: [
        PopupMenuItem<Color>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _ColorPickerContent(
            currentColor: currentColor,
            onColorChanged: (color) {
              Navigator.of(context).pop(color);
            },
          ),
        ),
      ],
    );
  }

  /// Show as dialog
  static Future<Color?> showAsDialog(
    BuildContext context, {
    required Color currentColor,
    String title = 'Track Color',
  }) async {
    return showDialog<Color>(
      context: context,
      builder: (context) => _ColorPickerDialog(
        title: title,
        currentColor: currentColor,
      ),
    );
  }

  @override
  State<TrackColorPicker> createState() => _TrackColorPickerState();
}

class _TrackColorPickerState extends State<TrackColorPicker> {
  @override
  Widget build(BuildContext context) {
    return _ColorPickerContent(
      currentColor: widget.currentColor,
      onColorChanged: widget.onColorChanged,
      onClose: widget.onClose,
    );
  }
}

/// Inner content widget for the color picker
class _ColorPickerContent extends StatefulWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback? onClose;

  const _ColorPickerContent({
    required this.currentColor,
    required this.onColorChanged,
    this.onClose,
  });

  @override
  State<_ColorPickerContent> createState() => _ColorPickerContentState();
}

class _ColorPickerContentState extends State<_ColorPickerContent> {
  late Color _selectedColor;
  bool _showCustomPicker = false;

  // HSL values for custom picker
  double _hue = 0.0;
  double _saturation = 1.0;
  double _lightness = 0.5;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.currentColor;

    // Initialize HSL from current color
    final hsl = HSLColor.fromColor(widget.currentColor);
    _hue = hsl.hue;
    _saturation = hsl.saturation;
    _lightness = hsl.lightness;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Track Color',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (widget.onClose != null)
                InkWell(
                  onTap: widget.onClose,
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Preset colors grid
          if (!_showCustomPicker) _buildPresetGrid(),

          // Custom picker
          if (_showCustomPicker) _buildCustomPicker(),

          const SizedBox(height: 8),

          // Toggle custom picker / Reset buttons
          Row(
            children: [
              InkWell(
                onTap: () => setState(() => _showCustomPicker = !_showCustomPicker),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgMid,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    _showCustomPicker ? 'Presets' : 'Custom',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
              const Spacer(),

              // Current color preview
              Container(
                width: 24,
                height: 16,
                decoration: BoxDecoration(
                  color: _selectedColor,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.white24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: TrackColorPresets.presets.length,
      itemBuilder: (context, index) {
        final color = TrackColorPresets.presets[index];
        final isSelected = color.value == _selectedColor.value;

        return InkWell(
          onTap: () {
            setState(() => _selectedColor = color);
            widget.onColorChanged(color);
          },
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.white24,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withAlpha(100),
                        blurRadius: 4,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: isSelected
                ? const Center(
                    child: Icon(Icons.check, color: Colors.white, size: 14),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildCustomPicker() {
    return Column(
      children: [
        // Hue slider
        _buildSliderRow('H', _hue, 360, (v) {
          setState(() {
            _hue = v;
            _updateColorFromHsl();
          });
        }),

        const SizedBox(height: 4),

        // Saturation slider
        _buildSliderRow('S', _saturation * 100, 100, (v) {
          setState(() {
            _saturation = v / 100;
            _updateColorFromHsl();
          });
        }),

        const SizedBox(height: 4),

        // Lightness slider
        _buildSliderRow('L', _lightness * 100, 100, (v) {
          setState(() {
            _lightness = v / 100;
            _updateColorFromHsl();
          });
        }),

        const SizedBox(height: 8),

        // Color preview bar
        Container(
          height: 24,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: List.generate(
                12,
                (i) => HSLColor.fromAHSL(1, i * 30.0, _saturation, _lightness).toColor(),
              ),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderRow(String label, double value, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(
            label,
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: FluxForgeTheme.accentBlue,
              inactiveTrackColor: FluxForgeTheme.bgMid,
              thumbColor: FluxForgeTheme.accentBlue,
            ),
            child: Slider(
              value: value,
              min: 0,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            value.toInt().toString(),
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  void _updateColorFromHsl() {
    final color = HSLColor.fromAHSL(1, _hue, _saturation, _lightness).toColor();
    setState(() => _selectedColor = color);
    widget.onColorChanged(color);
  }
}

/// Dialog wrapper for color picker
class _ColorPickerDialog extends StatefulWidget {
  final String title;
  final Color currentColor;

  const _ColorPickerDialog({
    required this.title,
    required this.currentColor,
  });

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.currentColor;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      title: Text(
        widget.title,
        style: TextStyle(
          color: FluxForgeTheme.textPrimary,
          fontSize: 14,
        ),
      ),
      contentPadding: const EdgeInsets.all(16),
      content: TrackColorPicker(
        currentColor: _selectedColor,
        onColorChanged: (color) {
          setState(() => _selectedColor = color);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: FluxForgeTheme.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_selectedColor),
          child: Text(
            'Apply',
            style: TextStyle(color: FluxForgeTheme.accentBlue),
          ),
        ),
      ],
    );
  }
}

/// Extension for easy color picker integration in track headers
extension TrackColorPickerExtension on Widget {
  /// Wrap with right-click color picker gesture
  Widget withTrackColorPicker({
    required BuildContext context,
    required Color currentColor,
    required ValueChanged<Color> onColorChanged,
  }) {
    return GestureDetector(
      onSecondaryTapUp: (details) async {
        final color = await TrackColorPicker.showAtPosition(
          context,
          position: details.globalPosition,
          currentColor: currentColor,
        );
        if (color != null) {
          onColorChanged(color);
        }
      },
      child: this,
    );
  }
}

/// Small color indicator widget for track headers
class TrackColorIndicator extends StatelessWidget {
  final Color color;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const TrackColorIndicator({
    super.key,
    required this.color,
    this.width = 4,
    this.height = double.infinity,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(width / 2),
          ),
        ),
      ),
    );
  }
}
