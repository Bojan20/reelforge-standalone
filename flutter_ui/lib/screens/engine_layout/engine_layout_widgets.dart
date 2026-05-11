// Engine Connected Layout — Atomic Widget Helpers
//
// Extracted from engine_connected_layout.dart via `part of` to reduce monolith
// LOC. All `_` private classes remain library-private and accessible within
// the engine_connected_layout library scope.
//
// Classes: _MeterRow, _StatusIndicator, _InspectorField, _InspectorEditableField,
//   _InspectorDropdown, _InspectorSlider, _InspectorCheckbox,
//   _InspectorDropdownInteractive, _InspectorSliderInteractive,
//   _InspectorCheckboxInteractive, _InspectorTextFieldInteractive,
//   _ToolbarButton, _ToolbarIconButton, _ToolbarDropdown,
//   _MiniDropdown, _MiniInput, _MiniSlider, _MiniToggle,
//   _CommandGroup, _CommandChip, _CommandIconBtn, _CommandToggle,
//   _ParamBox, _LayerToggle, _CellDropdown, _CellTextField,
//   _CellNumberField, _CellSlider, _SettingsRow, _InsertMenuOption,
//   _AudioEditorDialog, _ImportAudioIntent, _DialogDropdownRow,
//   _MiddlewareTimeRulerPainter, _MiddlewareTimelineGridPainter,
//   _SendDialogResult + remaining helper classes
//
// Part of: ../engine_connected_layout.dart

part of '../engine_connected_layout.dart';

// ignore: unused_element
class _MeterRow extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _MeterRow({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: FluxForgeTheme.dockSans(size: 11),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: FluxForgeTheme.dockMono(size: 11, color: FluxForgeTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            unit,
            style: FluxForgeTheme.dockSans(size: 10, color: FluxForgeTheme.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _StatusIndicator extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;

  const _StatusIndicator({
    required this.label,
    required this.active,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : FluxForgeTheme.textTertiary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: FluxForgeTheme.dockSans(size: 12, color: active ? color : FluxForgeTheme.textTertiary),
        ),
      ],
    );
  }
}

// ============ Inspector Field Widgets ============

class _InspectorField extends StatelessWidget {
  final String label;
  final String value;

  const _InspectorField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: FluxForgeTheme.dockSans(size: 11),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: Text(
                value,
                style: FluxForgeTheme.dockSans(size: 11, color: FluxForgeTheme.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorEditableField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _InspectorEditableField({required this.label, required this.value, required this.onChanged});

  @override
  State<_InspectorEditableField> createState() => _InspectorEditableFieldState();
}

class _InspectorEditableFieldState extends State<_InspectorEditableField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _InspectorEditableField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(widget.label, style: FluxForgeTheme.dockSans(size: 11)),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              style: FluxForgeTheme.dockSans(size: 11, color: FluxForgeTheme.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                filled: true,
                fillColor: FluxForgeTheme.bgDeepest,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: FluxForgeTheme.accentBlue)),
              ),
              onSubmitted: (v) => widget.onChanged(v),
              onTapOutside: (_) {
                if (_controller.text != widget.value) {
                  widget.onChanged(_controller.text);
                }
                FocusScope.of(context).unfocus();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;

  const _InspectorDropdown({
    required this.label,
    required this.value,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: FluxForgeTheme.dockSans(size: 11),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    value,
                    style: FluxForgeTheme.dockSans(size: 11, color: FluxForgeTheme.textPrimary),
                  ),
                  Icon(Icons.arrow_drop_down, size: 14, color: FluxForgeTheme.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorSlider extends StatelessWidget {
  final String label;
  final double value;
  final String suffix;

  const _InspectorSlider({
    required this.label,
    required this.value,
    required this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: FluxForgeTheme.dockSans(size: 11),
            ),
          ),
          Expanded(
            child: Container(
              height: 20,
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      suffix,
                      style: FluxForgeTheme.dockSans(size: 10, color: FluxForgeTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorCheckbox extends StatelessWidget {
  final String label;
  final bool checked;

  const _InspectorCheckbox({required this.label, required this.checked});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: FluxForgeTheme.dockSans(size: 11),
            ),
          ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: checked ? FluxForgeTheme.accentBlue : FluxForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: checked ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: checked
                ? Icon(Icons.check, size: 12, color: FluxForgeTheme.textPrimary)
                : null,
          ),
        ],
      ),
    );
  }
}

// ============ Interactive Inspector Widgets ============

/// Interactive dropdown for Inspector - connected to real data
class _InspectorDropdownInteractive extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _InspectorDropdownInteractive({
    required this.label,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: FluxForgeTheme.dockSans(size: 11, color: enabled ? FluxForgeTheme.textSecondary : FluxForgeTheme.textTertiary),
            ),
          ),
          Expanded(
            child: PopupMenuButton<String>(
              enabled: enabled,
              onSelected: onChanged,
              offset: const Offset(0, 24),
              color: FluxForgeTheme.bgElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
              itemBuilder: (context) => options.map((option) {
                final isSelected = option == value;
                return PopupMenuItem<String>(
                  value: option,
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      if (isSelected)
                        Icon(Icons.check, size: 12, color: FluxForgeTheme.accentOrange)
                      else
                        const SizedBox(width: 12),
                      const SizedBox(width: 8),
                      Text(
                        option,
                        style: FluxForgeTheme.dockSans(
                          size: 11,
                          color: isSelected ? FluxForgeTheme.accentOrange : FluxForgeTheme.textPrimary,
                          weight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: enabled ? FluxForgeTheme.bgDeepest : FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: enabled ? FluxForgeTheme.borderSubtle : FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: FluxForgeTheme.dockSans(
                          size: 11,
                          color: enabled ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary,
                          weight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: enabled ? FluxForgeTheme.textSecondary : FluxForgeTheme.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive slider for Inspector - uses local state during drag to prevent rebuild interruption
class _InspectorSliderInteractive extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final String Function(double) formatValue;
  final ValueChanged<double> onChanged;
  final double defaultValue;

  const _InspectorSliderInteractive({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.formatValue,
    required this.onChanged,
    this.defaultValue = 0.0,
  });

  @override
  State<_InspectorSliderInteractive> createState() => _InspectorSliderInteractiveState();
}

class _InspectorSliderInteractiveState extends State<_InspectorSliderInteractive> {
  bool _isDragging = false;
  double _localValue = 0.0;

  double get _displayValue => _isDragging ? _localValue : widget.value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              widget.label,
              style: FluxForgeTheme.dockSans(size: 11, color: widget.enabled ? FluxForgeTheme.textSecondary : FluxForgeTheme.textTertiary),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: widget.enabled ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary,
                inactiveTrackColor: FluxForgeTheme.bgDeepest,
                thumbColor: widget.enabled ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary,
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: GestureDetector(
                onDoubleTap: widget.enabled ? () {
                  setState(() {
                    _isDragging = false;
                    _localValue = widget.defaultValue;
                  });
                  widget.onChanged(widget.defaultValue);
                } : null,
                child: Slider(
                  value: _displayValue.clamp(widget.min, widget.max),
                  min: widget.min,
                  max: widget.max,
                  onChanged: widget.enabled ? (v) {
                    setState(() {
                      _isDragging = true;
                      _localValue = v;
                    });
                    widget.onChanged(v);
                  } : null,
                  onChangeEnd: widget.enabled ? (v) {
                    setState(() {
                      _isDragging = false;
                    });
                    widget.onChanged(v);
                  } : null,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              widget.formatValue(_displayValue),
              style: FluxForgeTheme.dockSans(
                size: 10,
                color: widget.enabled ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary,
                weight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive checkbox for Inspector - connected to real data
class _InspectorCheckboxInteractive extends StatelessWidget {
  final String label;
  final bool checked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _InspectorCheckboxInteractive({
    required this.label,
    required this.checked,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: FluxForgeTheme.dockSans(size: 11, color: enabled ? FluxForgeTheme.textSecondary : FluxForgeTheme.textTertiary),
            ),
          ),
          GestureDetector(
            onTap: enabled ? () => onChanged(!checked) : null,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: checked
                    ? (enabled ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary)
                    : FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: checked
                      ? (enabled ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary)
                      : (enabled ? FluxForgeTheme.borderSubtle : FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
                ),
              ),
              child: checked
                  ? Icon(Icons.check, size: 12, color: FluxForgeTheme.textPrimary)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive text field for Inspector - connected to real data
class _InspectorTextFieldInteractive extends StatefulWidget {
  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _InspectorTextFieldInteractive({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_InspectorTextFieldInteractive> createState() => _InspectorTextFieldInteractiveState();
}

class _InspectorTextFieldInteractiveState extends State<_InspectorTextFieldInteractive> {
  late TextEditingController _controller;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_InspectorTextFieldInteractive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_isFocused) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              widget.label,
              style: FluxForgeTheme.dockSans(size: 11, color: widget.enabled ? FluxForgeTheme.textSecondary : FluxForgeTheme.textTertiary),
            ),
          ),
          Expanded(
            child: Focus(
              onFocusChange: (focused) {
                setState(() => _isFocused = focused);
                if (!focused) {
                  widget.onChanged(_controller.text);
                }
              },
              child: TextField(
                controller: _controller,
                enabled: widget.enabled,
                style: FluxForgeTheme.dockSans(size: 11, color: widget.enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  filled: true,
                  fillColor: FluxForgeTheme.bgDeepest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
                  ),
                ),
                onSubmitted: widget.onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============ Middleware Widgets ============

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isActive ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 6 : 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: FluxForgeTheme.textPrimary),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(label, style: FluxForgeTheme.dockSans(size: 10, color: FluxForgeTheme.textPrimary, weight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarIconButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 16, color: FluxForgeTheme.textSecondary),
        ),
      ),
    );
  }
}

class _ToolbarDropdown extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final Color accentColor;

  const _ToolbarDropdown({
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      offset: const Offset(0, 32),
      color: FluxForgeTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      itemBuilder: (context) => options.map((option) {
        final isSelected = option == value;
        return PopupMenuItem<String>(
          value: option,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (isSelected)
                Icon(Icons.check, size: 14, color: accentColor)
              else
                const SizedBox(width: 14),
              const SizedBox(width: 8),
              Text(
                option,
                style: FluxForgeTheme.dockSans(
                  size: 11,
                  color: isSelected ? accentColor : FluxForgeTheme.textPrimary,
                  weight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: accentColor),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(label, style: FluxForgeTheme.dockSans(size: 10)),
              const SizedBox(width: 4),
            ],
            Text(value, style: FluxForgeTheme.dockSans(size: 10, color: accentColor, weight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 14, color: accentColor),
          ],
        ),
      ),
    );
  }
}

class _MiniDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _MiniDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      offset: const Offset(0, 28),
      color: FluxForgeTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      itemBuilder: (context) => options.map((option) {
        final isSelected = option == value;
        return PopupMenuItem<String>(
          value: option,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            option,
            style: FluxForgeTheme.dockSans(
              size: 11,
              color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.textPrimary,
              weight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: FluxForgeTheme.dockSans(size: 9, color: FluxForgeTheme.textTertiary)),
            const SizedBox(width: 6),
            Text(value, style: FluxForgeTheme.dockSans(size: 10, color: FluxForgeTheme.textPrimary)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 12, color: FluxForgeTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _MiniInput extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _MiniInput({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: FluxForgeTheme.dockSans(size: 9, color: FluxForgeTheme.textTertiary)),
            const SizedBox(width: 6),
            Text(value, style: FluxForgeTheme.dockMono(size: 10, color: FluxForgeTheme.accentCyan)),
          ],
        ),
      ),
    );
  }
}

class _MiniSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) formatValue;
  final ValueChanged<double> onChanged;

  const _MiniSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.formatValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Text(label, style: FluxForgeTheme.dockSans(size: 9, color: FluxForgeTheme.textTertiary)),
          const SizedBox(width: 4),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: FluxForgeTheme.accentCyan,
                inactiveTrackColor: FluxForgeTheme.borderSubtle,
                thumbColor: FluxForgeTheme.accentCyan,
                overlayColor: FluxForgeTheme.accentCyan.withAlpha(40),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              formatValue(value),
              style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.accentCyan),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _MiniToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: value ? FluxForgeTheme.accentGreen.withValues(alpha: 0.2) : FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: value ? FluxForgeTheme.accentGreen : FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.loop : Icons.trending_flat,
              size: 12,
              color: value ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(label, style: FluxForgeTheme.dockSans(size: 10, color: value ? FluxForgeTheme.accentGreen : FluxForgeTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Visually groups command bar controls with a subtle background
class _CommandGroup extends StatelessWidget {
  final List<Widget> children;
  const _CommandGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest.withAlpha(120),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Compact info chip (non-interactive)
class _CommandChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  const _CommandChip({required this.label, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? FluxForgeTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 3),
          ],
          Text(label, style: FluxForgeTheme.dockSans(size: 10, color: c)),
        ],
      ),
    );
  }
}

/// Compact icon button for command bar
class _CommandIconBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  const _CommandIconBtn({required this.icon, required this.tooltip, this.onTap, this.color});

  @override
  State<_CommandIconBtn> createState() => _CommandIconBtnState();
}

class _CommandIconBtnState extends State<_CommandIconBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.onTap != null ? (widget.color ?? FluxForgeTheme.textSecondary) : FluxForgeTheme.textTertiary;
    final c = _hovered && widget.onTap != null ? (widget.color ?? FluxForgeTheme.accentBlue) : baseColor;
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: _hovered && widget.onTap != null ? c.withAlpha(20) : Colors.transparent,
            ),
            child: Icon(widget.icon, size: 14, color: c),
          ),
        ),
      ),
    );
  }
}

/// Compact toggle for M/S/L buttons
class _CommandToggle extends StatefulWidget {
  final String label;
  final bool value;
  final Color activeColor;
  final VoidCallback onTap;
  const _CommandToggle({required this.label, required this.value, required this.activeColor, required this.onTap});

  @override
  State<_CommandToggle> createState() => _CommandToggleState();
}

class _CommandToggleState extends State<_CommandToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.value ? widget.activeColor.withAlpha(50) : (_hovered ? widget.activeColor.withAlpha(20) : Colors.transparent),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: widget.value ? widget.activeColor : (_hovered ? widget.activeColor.withAlpha(120) : FluxForgeTheme.borderSubtle), width: widget.value ? 1.5 : 1),
          ),
          child: Text(
            widget.label,
            style: FluxForgeTheme.dockSans(
              size: 10,
              weight: FontWeight.w700,
              color: widget.value ? widget.activeColor : (_hovered ? widget.activeColor : FluxForgeTheme.textTertiary),
            ),
          ),
        ),
      ),
    );
  }
}


/// Compact parameter box: label above, clickable value tile, popup slider on tap.
/// Designed for single-row layer parameter display.
class _ParamBox extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final Color color;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final double width;
  final double defaultValue;
  final VoidCallback? onInteract;

  const _ParamBox({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.format,
    required this.onChanged,
    this.width = 38,
    this.defaultValue = 0,
    this.onInteract,
  });

  @override
  State<_ParamBox> createState() => _ParamBoxState();
}

class _ParamBoxState extends State<_ParamBox> {
  bool _editing = false;
  bool _hovered = false;
  late TextEditingController _textController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _editing) {
        _commitEdit();
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _editing = true;
      _textController.text = widget.format(widget.value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _textController.selection = TextSelection(baseOffset: 0, extentOffset: _textController.text.length);
    });
  }

  void _commitEdit() {
    final text = _textController.text.replaceAll(RegExp(r'[^0-9.\-]'), '');
    final parsed = double.tryParse(text);
    if (parsed != null) {
      final isPan = widget.label == 'Pan' && widget.min == -1 && widget.max == 1;
      final value = isPan ? (parsed / 100.0) : parsed;
      widget.onChanged(value.clamp(widget.min, widget.max));
    }
    setState(() => _editing = false);
  }

  void _showSliderPopup(RenderBox box) {
    final overlay = Overlay.of(context);
    final pos = box.localToGlobal(Offset.zero);
    late OverlayEntry entry;
    double current = widget.value.clamp(widget.min, widget.max);
    final bool isVolume = widget.label == 'Vol' && widget.min == 0 && widget.max == 1;
    // Volume fader curve: slider position (0-1 linear) ↔ volume (0-1 logarithmic)
    // x² gives standard audio fader feel (more resolution at top)
    double volToSlider(double v) => math.sqrt(v.clamp(0.0, 1.0));
    double sliderToVol(double s) => s * s;

    entry = OverlayEntry(builder: (ctx) {
      return StatefulBuilder(builder: (ctx2, setPopup) {
        final double sliderVal = isVolume ? volToSlider(current) : current;
        return Stack(
          children: [
            Positioned.fill(child: GestureDetector(onTap: () => entry.remove(), behavior: HitTestBehavior.opaque, child: const SizedBox.expand())),
            Positioned(
              left: (pos.dx - 50).clamp(0, MediaQuery.of(ctx2).size.width - 200),
              top: pos.dy + box.size.height + 6,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 190,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A24),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.color.withAlpha(120), width: 1.2),
                    boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(widget.label, style: FluxForgeTheme.dockSans(size: 11, color: widget.color, weight: FontWeight.w700)),
                          Text(widget.format(current), style: FluxForgeTheme.dockMono(size: 12, color: widget.color, weight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 24,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3.5,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: widget.color,
                            inactiveTrackColor: FluxForgeTheme.borderSubtle,
                            thumbColor: widget.color,
                            overlayColor: widget.color.withAlpha(30),
                          ),
                          child: GestureDetector(
                            onDoubleTap: () {
                              setPopup(() => current = widget.defaultValue);
                              widget.onChanged(widget.defaultValue);
                            },
                            child: Slider(
                              value: sliderVal,
                              min: isVolume ? 0.0 : widget.min,
                              max: isVolume ? 1.0 : widget.max,
                              onChanged: (v) {
                                final actual = isVolume ? sliderToVol(v) : v;
                                setPopup(() => current = actual);
                                widget.onChanged(actual);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      });
    });
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(widget.label, textAlign: TextAlign.center, style: FluxForgeTheme.dockSans(size: 9, color: _hovered ? widget.color : FluxForgeTheme.textTertiary, weight: FontWeight.w600, height: 1)),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () {
              widget.onInteract?.call();
              if (_editing) return;
              final box = context.findRenderObject() as RenderBox?;
              if (box != null) _showSliderPopup(box);
            },
            onDoubleTap: () {
              widget.onInteract?.call();
              if (!_editing) _startEditing();
            },
            child: Container(
              constraints: BoxConstraints(minWidth: widget.width),
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _hovered ? widget.color.withAlpha(15) : FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _hovered ? widget.color.withAlpha(140) : widget.color.withAlpha(70), width: 0.8),
              ),
              child: _editing
                ? EditableText(
                    controller: _textController,
                    focusNode: _focusNode,
                    style: FluxForgeTheme.dockMono(size: 10, color: widget.color, weight: FontWeight.w600),
                    textAlign: TextAlign.center,
                    cursorColor: widget.color,
                    backgroundCursorColor: Colors.transparent,
                    selectionColor: widget.color.withAlpha(80),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    onSubmitted: (_) => _commitEdit(),
                  )
                : Text(
                    widget.format(widget.value),
                    style: FluxForgeTheme.dockMono(size: 10, color: widget.color, weight: FontWeight.w600),
                    overflow: TextOverflow.clip,
                    maxLines: 1,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerToggle extends StatefulWidget {
  final String label;
  final bool value;
  final Color activeColor;
  final VoidCallback onTap;
  final VoidCallback? onInteract;
  const _LayerToggle({required this.label, required this.value, required this.activeColor, required this.onTap, this.onInteract});

  @override
  State<_LayerToggle> createState() => _LayerToggleState();
}

class _LayerToggleState extends State<_LayerToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.value ? widget.activeColor : widget.activeColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () { widget.onInteract?.call(); widget.onTap(); },
        child: Container(
          width: 22,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.value ? widget.activeColor.withAlpha(50) : (_hovered ? hoverColor.withAlpha(20) : Colors.transparent),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: widget.value ? widget.activeColor : (_hovered ? hoverColor.withAlpha(120) : FluxForgeTheme.borderSubtle), width: widget.value ? 1.5 : 1),
          ),
          child: Text(
            widget.label,
            style: FluxForgeTheme.dockSans(
              size: 9,
              weight: FontWeight.w700,
              color: widget.value ? widget.activeColor : (_hovered ? hoverColor : FluxForgeTheme.textTertiary),
            ),
          ),
        ),
      ),
    );
  }
}

class _CellDropdown extends StatefulWidget {
  final String value;
  final List<String> options;
  final Color? color;
  final ValueChanged<String> onChanged;
  final VoidCallback? onInteract;

  const _CellDropdown({
    required this.value,
    required this.options,
    this.color,
    required this.onChanged,
    this.onInteract,
  });

  @override
  State<_CellDropdown> createState() => _CellDropdownState();
}

class _CellDropdownState extends State<_CellDropdown> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.color ?? FluxForgeTheme.accentBlue;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PopupMenuButton<String>(
        onOpened: () => widget.onInteract?.call(),
        onSelected: widget.onChanged,
        offset: const Offset(0, 24),
        color: FluxForgeTheme.bgElevated,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
        itemBuilder: (context) {
          // Normalize for matching: strip path and compare case-insensitive
          String _norm(String s) => s.split('/').last.toLowerCase();
          final normValue = _norm(widget.value);
          return widget.options.map((option) {
            final isSelected = option == widget.value || (option.isNotEmpty && widget.value.isNotEmpty && _norm(option) == normValue);
            final displayText = option.isEmpty ? '(none)' : option;
            return PopupMenuItem<String>(
              value: option,
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected)
                    Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.check, size: 12, color: accentColor))
                  else
                    const SizedBox(width: 18),
                  Flexible(child: Text(
                    displayText,
                    style: FluxForgeTheme.dockSans(
                      size: 11,
                      color: isSelected
                          ? accentColor
                          : (option.isEmpty ? FluxForgeTheme.textTertiary : FluxForgeTheme.textPrimary),
                      weight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ).copyWith(fontStyle: option.isEmpty ? FontStyle.italic : FontStyle.normal),
                    overflow: TextOverflow.ellipsis,
                  )),
                ],
              ),
            );
          }).toList();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: _hovered ? accentColor.withAlpha(15) : FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: _hovered ? accentColor.withAlpha(120) : FluxForgeTheme.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.value.isEmpty ? '(select)' : widget.value,
                  style: FluxForgeTheme.dockSans(
                    size: 10,
                    color: widget.value.isEmpty
                        ? FluxForgeTheme.textTertiary
                        : (_hovered ? accentColor : (widget.color ?? FluxForgeTheme.textPrimary)),
                  ).copyWith(fontStyle: widget.value.isEmpty ? FontStyle.italic : FontStyle.normal),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 12, color: _hovered ? accentColor : FluxForgeTheme.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// NOTE: _ActionsTable, _TableHeader, _TableCell, _TableCellDropdown removed - unused legacy widgets

/// Compact inline text field for table cells
class _CellTextField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;

  const _CellTextField({
    required this.value,
    required this.onChanged,
    this.hint,
  });

  @override
  State<_CellTextField> createState() => _CellTextFieldState();
}

class _CellTextFieldState extends State<_CellTextField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() => _hasFocus = _focusNode.hasFocus);
      if (!_focusNode.hasFocus && _controller.text != widget.value) {
        widget.onChanged(_controller.text);
      }
    });
  }

  @override
  void didUpdateWidget(_CellTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasFocus && oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: _hasFocus ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: FluxForgeTheme.dockSans(size: 11, color: FluxForgeTheme.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          hintText: widget.hint,
          hintStyle: FluxForgeTheme.dockSans(size: 11, color: FluxForgeTheme.textSecondary.withValues(alpha: 0.5)),
        ),
        onSubmitted: (val) => widget.onChanged(val),
      ),
    );
  }
}

/// Compact inline number field for table cells
class _CellNumberField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final String? suffix;
  final double min;
  final double max;
  final int decimals;

  const _CellNumberField({
    required this.value,
    required this.onChanged,
    this.suffix,
    this.min = 0,
    this.max = 9999,
    this.decimals = 0,
  });

  @override
  State<_CellNumberField> createState() => _CellNumberFieldState();
}

class _CellNumberFieldState extends State<_CellNumberField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatValue(widget.value));
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() => _hasFocus = _focusNode.hasFocus);
      if (!_focusNode.hasFocus) {
        _commitValue();
      }
    });
  }

  String _formatValue(double val) {
    if (widget.decimals == 0) {
      return val.round().toString();
    }
    return val.toStringAsFixed(widget.decimals);
  }

  void _commitValue() {
    final parsed = double.tryParse(_controller.text);
    if (parsed != null) {
      final clamped = parsed.clamp(widget.min, widget.max);
      if (clamped != widget.value) {
        widget.onChanged(clamped);
      }
    }
    _controller.text = _formatValue(widget.value);
  }

  @override
  void didUpdateWidget(_CellNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasFocus && oldWidget.value != widget.value) {
      _controller.text = _formatValue(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: _hasFocus ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: FluxForgeTheme.dockSans(size: 11, color: FluxForgeTheme.textPrimary),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _commitValue(),
            ),
          ),
          if (widget.suffix != null)
            Text(
              widget.suffix!,
              style: FluxForgeTheme.dockSans(size: 9, color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7)),
            ),
        ],
      ),
    );
  }
}

/// Compact inline slider for table cells
class _CellSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final String Function(double) formatValue;
  final ValueChanged<double> onChanged;
  final Color? color;

  const _CellSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.formatValue,
    required this.onChanged,
    this.color,
  });

  @override
  State<_CellSlider> createState() => _CellSliderState();
}

class _CellSliderState extends State<_CellSlider> {
  late double _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
  }

  @override
  void didUpdateWidget(_CellSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _currentValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.color ?? FluxForgeTheme.accentOrange;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Show popup slider for precise control — avoids horizontal drag conflicts
        _showSliderPopup(context, effectiveColor);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mini progress bar
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: ((_currentValue - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: effectiveColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Value text
            Text(
              widget.formatValue(_currentValue),
              style: FluxForgeTheme.dockMono(size: 9, color: effectiveColor, weight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  void _showSliderPopup(BuildContext context, Color color) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset position = box.localToGlobal(Offset.zero);

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          Positioned(
            left: position.dx - 20,
            top: position.dy - 40,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 140,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: StatefulBuilder(
                  builder: (context, setPopupState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.formatValue(_currentValue),
                          style: FluxForgeTheme.dockMono(size: 12, color: color, weight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: color,
                            inactiveTrackColor: FluxForgeTheme.bgDeepest,
                            thumbColor: color,
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          ),
                          child: Slider(
                            value: _currentValue.clamp(widget.min, widget.max),
                            min: widget.min,
                            max: widget.max,
                            onChanged: (v) {
                              setState(() => _currentValue = v);
                              setPopupState(() {});
                            },
                            onChangeEnd: (v) {
                              widget.onChanged(v);
                              Navigator.of(ctx).pop();
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings row for project settings dialog
class _SettingsRow extends StatelessWidget {
  final String label;
  final String value;

  const _SettingsRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: FluxForgeTheme.dockSans(size: 13)),
          Text(value, style: FluxForgeTheme.dockSans(size: 13, color: FluxForgeTheme.textPrimary, weight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Insert menu option for existing plugin context menu
class _InsertMenuOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _InsertMenuOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color ?? FluxForgeTheme.textSecondary),
            const SizedBox(width: 10),
            Text(
              label,
              style: FluxForgeTheme.dockSans(size: 12, color: color ?? FluxForgeTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Audio Editor Dialog with local state management
class _AudioEditorDialog extends StatefulWidget {
  final timeline.TimelineClip initialClip;
  final void Function(timeline.TimelineClip) onClipChanged;
  final int Function(FadeCurve) curveToInt;

  const _AudioEditorDialog({
    required this.initialClip,
    required this.onClipChanged,
    required this.curveToInt,
  });

  @override
  State<_AudioEditorDialog> createState() => _AudioEditorDialogState();
}

class _AudioEditorDialogState extends State<_AudioEditorDialog> {
  late timeline.TimelineClip _clip;
  double _zoom = 100;
  double _scrollOffset = 0;
  bool _initialZoomSet = false;

  @override
  void initState() {
    super.initState();
    _clip = widget.initialClip;
  }

  void _updateClip(timeline.TimelineClip newClip) {
    setState(() {
      _clip = newClip;
    });
    widget.onClipChanged(newClip);
  }

  @override
  Widget build(BuildContext context) {
    // Calculate dialog dimensions
    final dialogWidth = MediaQuery.of(context).size.width * 0.9;
    final dialogHeight = MediaQuery.of(context).size.height * 0.8;

    // Waveform area width (dialog - sidebar - padding)
    // Sidebar is 200px, plus some padding
    final waveformWidth = dialogWidth - 200 - 32;

    // Calculate zoom to fit entire clip duration
    // Only set initial zoom once
    if (!_initialZoomSet && _clip.duration > 0 && waveformWidth > 0) {
      _zoom = waveformWidth / _clip.duration;
      _scrollOffset = 0;
      _initialZoomSet = true;
    }

    return Dialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: clip_editor.ClipEditor(
          clip: clip_editor.ClipEditorClip(
            id: _clip.id,
            name: _clip.name,
            duration: _clip.duration,
            sampleRate: NativeFFI.instance.getSampleRate() > 0 ? NativeFFI.instance.getSampleRate() : 48000,
            channels: _clip.channels > 0 ? _clip.channels : 2,
            bitDepth: 24,
            fadeIn: _clip.fadeIn,
            fadeOut: _clip.fadeOut,
            fadeInCurve: _clip.fadeInCurve,
            fadeOutCurve: _clip.fadeOutCurve,
            gain: _clip.gain,
            color: _clip.color,
            sourceOffset: _clip.sourceOffset,
            sourceDuration: _clip.sourceDuration ?? _clip.duration,
            waveform: _clip.waveform,
          ),
          zoom: _zoom,
          scrollOffset: _scrollOffset,
          onZoomChange: (zoom) => setState(() => _zoom = zoom),
          onScrollChange: (offset) => setState(() => _scrollOffset = offset),
          onFadeInChange: (id, fadeIn) {
            EngineApi.instance.fadeInClip(id, fadeIn, curveType: widget.curveToInt(_clip.fadeInCurve));
            _updateClip(_clip.copyWith(fadeIn: fadeIn));
          },
          onFadeOutChange: (id, fadeOut) {
            EngineApi.instance.fadeOutClip(id, fadeOut, curveType: widget.curveToInt(_clip.fadeOutCurve));
            _updateClip(_clip.copyWith(fadeOut: fadeOut));
          },
          onFadeInCurveChange: (id, curve) {
            EngineApi.instance.fadeInClip(id, _clip.fadeIn, curveType: widget.curveToInt(curve));
            _updateClip(_clip.copyWith(fadeInCurve: curve));
          },
          onFadeOutCurveChange: (id, curve) {
            EngineApi.instance.fadeOutClip(id, _clip.fadeOut, curveType: widget.curveToInt(curve));
            _updateClip(_clip.copyWith(fadeOutCurve: curve));
          },
          onGainChange: (id, gain) {
            EngineApi.instance.setClipGain(id, gain);
            _updateClip(_clip.copyWith(gain: gain));
          },
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SHORTCUT INTENTS
// ════════════════════════════════════════════════════════════════════════════

/// Intent for importing audio files (Shift+Cmd+I)
class _ImportAudioIntent extends Intent {
  const _ImportAudioIntent();
}

/// Dropdown row for dialogs
class _DialogDropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _DialogDropdownRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Ensure value is in options, fallback to first option if not
    final effectiveValue = options.contains(value) ? value : options.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FluxForgeTheme.dockSans(size: 11)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: DropdownButton<String>(
            value: effectiveValue,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: FluxForgeTheme.bgElevated,
            style: FluxForgeTheme.dockSans(size: 12, color: FluxForgeTheme.textPrimary),
            items: options.map((o) => DropdownMenuItem(
              value: o,
              child: Text(
                o.isEmpty ? '(none)' : o,
                style: FluxForgeTheme.dockSans(
                  color: o.isEmpty ? FluxForgeTheme.textTertiary : FluxForgeTheme.textPrimary,
                ).copyWith(fontStyle: o.isEmpty ? FontStyle.italic : FontStyle.normal),
              ),
            )).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// MIDDLEWARE TIMELINE PAINTERS
// =============================================================================

/// Time ruler painter for middleware timeline
class _MiddlewareTimeRulerPainter extends CustomPainter {
  final double duration;
  final double zoom;
  final double pixelsPerSecond;

  _MiddlewareTimeRulerPainter({
    required this.duration,
    required this.zoom,
    required this.pixelsPerSecond,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..strokeWidth = 1;

    final textStyle = FluxForgeTheme.dockSans(size: 9);

    final scaledPixelsPerSecond = pixelsPerSecond * zoom;

    // Determine tick interval based on zoom
    double majorInterval = 1.0; // 1 second
    if (zoom < 0.5) majorInterval = 2.0;
    if (zoom < 0.25) majorInterval = 5.0;
    if (zoom > 2.0) majorInterval = 0.5;
    if (zoom > 3.0) majorInterval = 0.25;

    // Draw ticks
    for (double t = 0; t <= duration; t += majorInterval / 4) {
      final x = t * scaledPixelsPerSecond;
      final isMajor = (t % majorInterval).abs() < 0.001;
      final isMinor = (t % (majorInterval / 2)).abs() < 0.001;

      if (isMajor) {
        // Major tick with time label
        canvas.drawLine(Offset(x, size.height - 12), Offset(x, size.height), paint);

        final textSpan = TextSpan(text: _formatTime(t), style: textStyle);
        final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 3, 2));
      } else if (isMinor) {
        // Minor tick
        canvas.drawLine(Offset(x, size.height - 8), Offset(x, size.height), paint..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.5));
      } else {
        // Sub-tick
        canvas.drawLine(Offset(x, size.height - 4), Offset(x, size.height), paint..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3));
      }
    }

    // Draw bottom line
    paint.color = FluxForgeTheme.borderSubtle;
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), paint);
  }

  String _formatTime(double seconds) {
    if (seconds < 1) {
      return '${(seconds * 1000).round()}ms';
    }
    final secs = seconds.floor();
    final ms = ((seconds - secs) * 100).round();
    if (ms > 0) {
      return '${secs}.${ms.toString().padLeft(2, '0')}s';
    }
    return '${secs}s';
  }

  @override
  bool shouldRepaint(covariant _MiddlewareTimeRulerPainter oldDelegate) {
    return duration != oldDelegate.duration ||
        zoom != oldDelegate.zoom ||
        pixelsPerSecond != oldDelegate.pixelsPerSecond;
  }
}

/// Grid painter for middleware timeline
class _MiddlewareTimelineGridPainter extends CustomPainter {
  final double zoom;
  final double pixelsPerSecond;
  final double trackHeight;
  final int trackCount;

  _MiddlewareTimelineGridPainter({
    required this.zoom,
    required this.pixelsPerSecond,
    required this.trackHeight,
    required this.trackCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1;

    final scaledPixelsPerSecond = pixelsPerSecond * zoom;

    // Determine grid interval based on zoom
    double gridInterval = 1.0; // 1 second
    if (zoom < 0.5) gridInterval = 2.0;
    if (zoom < 0.25) gridInterval = 5.0;
    if (zoom > 2.0) gridInterval = 0.5;
    if (zoom > 3.0) gridInterval = 0.25;

    // Draw vertical grid lines (time)
    final totalSeconds = size.width / scaledPixelsPerSecond;
    for (double t = 0; t <= totalSeconds; t += gridInterval / 2) {
      final x = t * scaledPixelsPerSecond;
      final isMajor = (t % gridInterval).abs() < 0.001;

      paint.color = isMajor
          ? FluxForgeTheme.borderSubtle.withValues(alpha: 0.4)
          : FluxForgeTheme.borderSubtle.withValues(alpha: 0.15);

      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal grid lines (tracks)
    for (int i = 0; i <= trackCount; i++) {
      final y = i * trackHeight;
      paint.color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw alternating track backgrounds
    for (int i = 0; i < trackCount; i++) {
      if (i % 2 == 1) {
        final rect = Rect.fromLTWH(0, i * trackHeight, size.width, trackHeight);
        canvas.drawRect(rect, Paint()..color = FluxForgeTheme.bgMid.withValues(alpha: 0.3));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MiddlewareTimelineGridPainter oldDelegate) {
    return zoom != oldDelegate.zoom ||
        pixelsPerSecond != oldDelegate.pixelsPerSecond ||
        trackHeight != oldDelegate.trackHeight ||
        trackCount != oldDelegate.trackCount;
  }
}

/// Result type for send destination dialog
class _SendDialogResult {
  final bool isRemove;
  final bool isCreateNew;
  final String? existingBusId;
  final String? existingBusName;
  final String? effectName;
  final DspNodeType? effectType;

  const _SendDialogResult({
    this.isRemove = false,
    this.isCreateNew = false,
    this.existingBusId,
    this.existingBusName,
    this.effectName,
    this.effectType,
  });
}
