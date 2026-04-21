/// Cubase-style Timeline Edit Toolbar
///
/// Horizontal toolbar with clickable tool icons + number key shortcuts.
/// Sits above the timeline ruler for quick tool switching.
///
/// ┌──────────────────────────────────────────────────────────────────┐
/// │ 🧠 Smart │ ▶ Select │ ▬ Range │ ✂ Split │ 🔗 Glue │ ✕ Erase │ ...
/// └──────────────────────────────────────────────────────────────────┘
///
/// Keyboard shortcuts: 1=Smart, 2=Select, 3=Range, 4=Split, 5=Glue,
///                     6=Erase, 7=Zoom, 8=Mute, 9=Draw, 0=Play

import 'package:flutter/material.dart';
import '../../providers/smart_tool_provider.dart';
import '../../theme/fluxforge_theme.dart';

class TimelineEditToolbar extends StatelessWidget {
  final SmartToolProvider provider;

  /// Snap controls
  final bool snapEnabled;
  final double snapValue;
  final ValueChanged<bool>? onSnapToggle;
  final ValueChanged<double>? onSnapValueChange;

  /// Sample rate selector
  final int sampleRate;
  final ValueChanged<int>? onSampleRateChanged;

  const TimelineEditToolbar({
    super.key,
    required this.provider,
    this.snapEnabled = true,
    this.snapValue = 0.25,
    this.onSnapToggle,
    this.onSnapValueChange,
    this.sampleRate = 48000,
    this.onSampleRateChanged,
  });

  static const double toolbarHeight = 30;

  static const List<TimelineEditTool> _tools = TimelineEditTool.values;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        return Container(
          height: toolbarHeight,
          decoration: const BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            border: Border(
              bottom: BorderSide(color: FluxForgeTheme.bgSurface, width: 1),
            ),
          ),
          child: Row(
            children: [
              // ═══ Tool buttons ═══
              ..._tools.map((tool) => _ToolButton(
                tool: tool,
                isActive: provider.activeTool == tool,
                onTap: () => provider.setActiveTool(tool),
              )),

              const SizedBox(width: 8),

              // ═══ Divider ═══
              Container(
                width: 1,
                height: 18,
                color: FluxForgeTheme.bgSurface,
              ),

              const SizedBox(width: 6),

              // ═══ Edit Mode buttons (Shuffle / Slip / Spot / Grid) ═══
              ...TimelineEditMode.values.map((mode) => _EditModeButton(
                mode: mode,
                isActive: provider.activeEditMode == mode,
                onTap: () => provider.setActiveEditMode(mode),
              )),

              const SizedBox(width: 6),

              // ═══ Divider ═══
              Container(
                width: 1,
                height: 18,
                color: FluxForgeTheme.bgSurface,
              ),

              const SizedBox(width: 8),

              // ═══ Snap toggle ═══
              _SnapButton(
                enabled: snapEnabled,
                onTap: () => onSnapToggle?.call(!snapEnabled),
              ),

              const SizedBox(width: 4),

              // ═══ Snap grid selector ═══
              _SnapGridSelector(
                value: snapValue,
                onChanged: onSnapValueChange,
              ),

              if (onSampleRateChanged != null) ...[
                const SizedBox(width: 6),
                Container(width: 1, height: 18, color: FluxForgeTheme.bgSurface),
                const SizedBox(width: 6),
                _SampleRateSelector(
                  value: sampleRate,
                  onChanged: onSampleRateChanged!,
                ),
              ],

              const Spacer(),

              // ═══ Active tool + mode indicator ═══
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${SmartToolProvider.toolDisplayName(provider.activeTool)} · ${SmartToolProvider.editModeDisplayName(provider.activeEditMode)}',
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tool Button
// ═══════════════════════════════════════════════════════════════════════════════

class _ToolButton extends StatefulWidget {
  final TimelineEditTool tool;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolButton({
    required this.tool,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_ToolButton> createState() => _ToolButtonState();
}

class _ToolButtonState extends State<_ToolButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final icon = SmartToolProvider.toolIcon(widget.tool);
    final shortcut = SmartToolProvider.toolShortcut(widget.tool);
    final name = SmartToolProvider.toolDisplayName(widget.tool);

    final isActive = widget.isActive;
    final accentColor = const Color(0xFF4a9eff);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Tooltip(
        message: '$name ($shortcut)',
        waitDuration: const Duration(milliseconds: 500),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 30,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
            decoration: BoxDecoration(
              color: isActive
                  ? accentColor.withValues(alpha: 0.2)
                  : _hovering
                      ? const Color(0xFF2a2a30)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: isActive
                  ? Border.all(color: accentColor.withValues(alpha: 0.6), width: 1)
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: isActive
                      ? accentColor
                      : _hovering
                          ? FluxForgeTheme.textSecondary
                          : FluxForgeTheme.textTertiary,
                ),
                // Shortcut number badge (bottom-right)
                Positioned(
                  right: 2,
                  bottom: 1,
                  child: Text(
                    shortcut,
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      color: isActive
                          ? accentColor.withValues(alpha: 0.7)
                          : FluxForgeTheme.textTertiary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Edit Mode Button (Shuffle / Slip / Spot / Grid)
// ═══════════════════════════════════════════════════════════════════════════════

class _EditModeButton extends StatefulWidget {
  final TimelineEditMode mode;
  final bool isActive;
  final VoidCallback onTap;

  const _EditModeButton({
    required this.mode,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_EditModeButton> createState() => _EditModeButtonState();
}

class _EditModeButtonState extends State<_EditModeButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final icon = SmartToolProvider.editModeIcon(widget.mode);
    final name = SmartToolProvider.editModeDisplayName(widget.mode);
    final tooltip = SmartToolProvider.editModeTooltip(widget.mode);
    final isActive = widget.isActive;
    final accentColor = const Color(0xFF40ff90); // Green accent for modes

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? accentColor.withValues(alpha: 0.15)
                  : _hovering
                      ? const Color(0xFF2a2a30)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: isActive
                  ? Border.all(color: accentColor.withValues(alpha: 0.5), width: 1)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 12,
                  color: isActive
                      ? accentColor
                      : _hovering
                          ? FluxForgeTheme.textSecondary
                          : FluxForgeTheme.textTertiary,
                ),
                const SizedBox(width: 3),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    color: isActive
                        ? accentColor
                        : _hovering
                            ? FluxForgeTheme.textSecondary
                            : FluxForgeTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Snap Button
// ═══════════════════════════════════════════════════════════════════════════════

class _SnapButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _SnapButton({
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Snap to Grid (J)',
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: enabled
                ? const Color(0xFFff9040).withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: enabled
                  ? const Color(0xFFff9040).withValues(alpha: 0.6)
                  : FluxForgeTheme.bgSurface,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.grid_on,
                size: 12,
                color: enabled ? const Color(0xFFff9040) : FluxForgeTheme.textTertiary,
              ),
              const SizedBox(width: 3),
              Text(
                'Snap',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: enabled ? const Color(0xFFff9040) : FluxForgeTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Snap Grid Selector
// ═══════════════════════════════════════════════════════════════════════════════

class _SnapGridSelector extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;

  const _SnapGridSelector({
    required this.value,
    this.onChanged,
  });

  static final Map<double, String> _snapLabels = {
    0.0625: '1/64',
    0.125: '1/32',
    0.25: '1/16',
    0.5: '1/8',
    1.0: '1/4',
    2.0: '1/2',
    4.0: '1 Bar',
  };

  @override
  Widget build(BuildContext context) {
    final label = _snapLabels[value] ?? '${value}s';

    return PopupMenuButton<double>(
      onSelected: onChanged,
      offset: const Offset(0, 24),
      constraints: const BoxConstraints(minWidth: 80),
      color: FluxForgeTheme.bgDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: FluxForgeTheme.bgSurface),
      ),
      itemBuilder: (context) => _snapLabels.entries.map((e) {
        return PopupMenuItem<double>(
          value: e.key,
          height: 28,
          child: Text(
            e.value,
            style: TextStyle(
              fontSize: 11,
              color: e.key == value ? const Color(0xFF4a9eff) : FluxForgeTheme.textSecondary,
              fontWeight: e.key == value ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.bgSurface, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: FluxForgeTheme.bodySmall.copyWith(
                fontSize: 10,
                color: FluxForgeTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: FluxForgeTheme.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Sample Rate selector dropdown
class _SampleRateSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  static const _rates = [44100, 48000, 88200, 96000, 176400, 192000];

  const _SampleRateSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final label = '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)} kHz';
    return PopupMenuButton<int>(
      onSelected: onChanged,
      tooltip: 'Project Sample Rate',
      constraints: const BoxConstraints(minWidth: 80),
      color: const Color(0xFF1A1A24),
      itemBuilder: (_) => _rates.map((r) {
        final rLabel = '${(r / 1000).toStringAsFixed(r % 1000 == 0 ? 0 : 1)} kHz';
        return PopupMenuItem<int>(
          value: r,
          height: 28,
          child: Row(
            children: [
              if (r == value)
                const Icon(Icons.check, size: 14, color: Color(0xFF64FFDA))
              else
                const SizedBox(width: 14),
              const SizedBox(width: 6),
              Text(rLabel, style: const TextStyle(color: Colors.white, fontSize: 11)),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.bgSurface, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: FluxForgeTheme.bodySmall.copyWith(fontSize: 10, color: FluxForgeTheme.textSecondary)),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 14, color: FluxForgeTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}
