/// FluxForge Studio Right Zone (Inspector)
///
/// Property inspector with collapsible sections:
/// - General (name, category, priority)
/// - Playback (volume, pitch, filters)
/// - Routing (bus, sends)
/// - RTPC (game parameters)
/// - States (state groups)
/// - Advanced (scope, 3D settings)
///
/// 1:1 migration from React RightZone.tsx

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../models/layout_models.dart';

/// Inspected object types
enum InspectedObjectType {
  event,
  command,
  sound,
  bus,
  none,
}

/// Icon map for inspected objects
const Map<InspectedObjectType, String> _typeIcons = {
  InspectedObjectType.event: '🎯',
  InspectedObjectType.command: '▶',
  InspectedObjectType.sound: '🔊',
  InspectedObjectType.bus: '🔈',
  InspectedObjectType.none: '',
};

/// Right Zone widget
class RightZone extends StatefulWidget {
  /// Whether zone is collapsed
  final bool collapsed;

  /// Type of inspected object
  final InspectedObjectType objectType;

  /// Object name/title
  final String? objectName;

  /// Inspector sections
  final List<InspectorSection> sections;

  /// On collapse toggle
  final VoidCallback? onToggleCollapse;

  const RightZone({
    super.key,
    this.collapsed = false,
    required this.objectType,
    this.objectName,
    this.sections = const [],
    this.onToggleCollapse,
  });

  @override
  State<RightZone> createState() => _RightZoneState();
}

class _RightZoneState extends State<RightZone> {
  late Set<String> _expandedSections;

  @override
  void initState() {
    super.initState();
    _expandedSections = widget.sections
        .where((s) => s.expanded)
        .map((s) => s.id)
        .toSet();
  }

  void _toggleSection(String id) {
    setState(() {
      if (_expandedSections.contains(id)) {
        _expandedSections.remove(id);
      } else {
        _expandedSections.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsed) {
      return const SizedBox.shrink();
    }

    // Completely empty when nothing selected
    if (widget.objectType == InspectedObjectType.none) {
      return Container(
        width: 280,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          border: Border(
            left: BorderSide(
              color: FluxForgeTheme.borderSubtle,
              width: 1,
            ),
          ),
        ),
      );
    }

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(
          left: BorderSide(
            color: FluxForgeTheme.borderSubtle,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Inspector',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary,
            ),
          ),
          const Spacer(),
          if (widget.onToggleCollapse != null)
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 18),
              onPressed: widget.onToggleCollapse,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              color: FluxForgeTheme.textSecondary,
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    // Empty state - no placeholder, just empty space
    return const SizedBox.shrink();
  }

  Widget _buildContent() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Object header
        if (widget.objectName != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Text(
                  _typeIcons[widget.objectType] ?? '',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.objectName!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: FluxForgeTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Sections
        ...widget.sections.map((section) => _InspectorSectionWidget(
              id: section.id,
              title: section.title,
              expanded: _expandedSections.contains(section.id),
              onToggle: () => _toggleSection(section.id),
              child: section.content,
            )),
      ],
    );
  }
}

/// Inspector section widget
class _InspectorSectionWidget extends StatelessWidget {
  final String id;
  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const _InspectorSectionWidget({
    required this.id,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        GestureDetector(
          onTap: onToggle,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              border: Border(
                bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: FluxForgeTheme.fastDuration,
                  child: const Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Content
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
          crossFadeState:
              expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: FluxForgeTheme.fastDuration,
        ),
      ],
    );
  }
}

// ============ Field Components ============

/// Text field widget
class InspectorTextField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String>? onChange;
  final String? placeholder;
  final bool disabled;

  const InspectorTextField({
    super.key,
    required this.label,
    required this.value,
    this.onChange,
    this.placeholder,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 28,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: TextField(
              controller: TextEditingController(text: value),
              onChanged: onChange,
              enabled: !disabled,
              style: const TextStyle(
                fontSize: 12,
                color: FluxForgeTheme.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: placeholder,
                hintStyle: TextStyle(color: FluxForgeTheme.textSecondary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Select field widget
class InspectorSelectField extends StatelessWidget {
  final String label;
  final String value;
  final List<({String value, String label})> options;
  final ValueChanged<String>? onChange;
  final bool disabled;

  const InspectorSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    this.onChange,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 28,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox(),
              dropdownColor: FluxForgeTheme.bgElevated,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              style: const TextStyle(
                fontSize: 12,
                color: FluxForgeTheme.textPrimary,
              ),
              items: options
                  .map((opt) => DropdownMenuItem(
                        value: opt.value,
                        child: Text(opt.label),
                      ))
                  .toList(),
              onChanged: disabled ? null : (v) => onChange?.call(v!),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slider field widget
class InspectorSliderField extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String? unit;
  final ValueChanged<double>? onChange;
  final String Function(double)? formatValue;
  final bool disabled;
  final double? defaultValue;

  const InspectorSliderField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    this.unit,
    this.onChange,
    this.formatValue,
    this.disabled = false,
    this.defaultValue,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final displayValue = formatValue?.call(value) ?? value.toString();
    final resetValue = defaultValue ?? (min < 0 && max > 0 ? 0 : min);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onDoubleTap: disabled ? null : () => onChange?.call(resetValue),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgDeepest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(
                      children: [
                        FractionallySizedBox(
                          widthFactor: percentage,
                          child: Container(
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.accentBlue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: SliderTheme(
                            data: SliderThemeData(
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: SliderComponentShape.noOverlay,
                              trackHeight: 0,
                            ),
                            child: Slider(
                              value: value.clamp(min, max),
                              min: min,
                              max: max,
                              onChanged: disabled ? null : onChange,
                              activeColor: Colors.transparent,
                              inactiveColor: Colors.transparent,
                              thumbColor: FluxForgeTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  child: Text(
                    '$displayValue${unit ?? ''}',
                    style: FluxForgeTheme.monoSmall.copyWith(fontSize: 10),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Checkbox field widget
class InspectorCheckboxField extends StatelessWidget {
  final String label;
  final bool checked;
  final ValueChanged<bool>? onChange;
  final bool disabled;

  const InspectorCheckboxField({
    super.key,
    required this.label,
    required this.checked,
    this.onChange,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: disabled ? null : () => onChange?.call(!checked),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: checked
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: checked
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.borderSubtle,
                ),
              ),
              child: checked
                  ? const Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: disabled
                    ? FluxForgeTheme.textSecondary
                    : FluxForgeTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
