/// FluxForge Studio — Collapsed Zone Rail (FLUX_MASTER_TODO 2.1.3)
///
/// Thin (24px) affordance shown in place of a hidden Left/Right/Lower zone
/// so the user can re-expand the panel by clicking, even without knowing
/// the keyboard shortcut (Cmd+L / Cmd+R / Cmd+B).
///
/// Replaces `SizedBox.shrink()` in collapsed branches of LeftZone, RightZone,
/// LowerZone and the SPEC-03 contextual inspector path in MainLayout.

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Which edge the rail sits on. Determines text orientation and chevron icon.
enum RailSide { left, right, lower }

/// 24px clickable rail rendered when a zone is collapsed.
///
/// - left/right rails: vertical (24px wide, full height) with rotated label
/// - lower rail:       horizontal (full width, 22px tall) with regular label
class CollapsedRail extends StatefulWidget {
  final RailSide side;
  final String label;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onExpand;

  const CollapsedRail({
    super.key,
    required this.side,
    required this.label,
    required this.icon,
    required this.accentColor,
    this.onExpand,
  });

  @override
  State<CollapsedRail> createState() => _CollapsedRailState();
}

class _CollapsedRailState extends State<CollapsedRail> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isVertical =
        widget.side == RailSide.left || widget.side == RailSide.right;
    final bg = _hover
        ? widget.accentColor.withValues(alpha: 0.08)
        : FluxForgeTheme.bgDeep;
    final border = _hover ? widget.accentColor : FluxForgeTheme.borderSubtle;

    final tooltip = 'Expand ${widget.label} '
        '(${widget.side == RailSide.left ? 'Cmd+L' : widget.side == RailSide.right ? 'Cmd+R' : 'Cmd+B'})';

    Widget rail = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onExpand,
        child: Container(
          width: isVertical ? 24 : null,
          height: isVertical ? null : 22,
          decoration: BoxDecoration(
            color: bg,
            border: _railBorder(border),
          ),
          child: isVertical
              ? _buildVerticalContent()
              : _buildHorizontalContent(),
        ),
      ),
    );

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 150),
      child: rail,
    );
  }

  Border _railBorder(Color border) {
    switch (widget.side) {
      case RailSide.left:
        return Border(right: BorderSide(color: border, width: 1));
      case RailSide.right:
        return Border(left: BorderSide(color: border, width: 1));
      case RailSide.lower:
        return Border(top: BorderSide(color: border, width: 1));
    }
  }

  Widget _buildVerticalContent() {
    final chevron = widget.side == RailSide.left
        ? Icons.chevron_right
        : Icons.chevron_left;
    final textColor = _hover
        ? widget.accentColor
        : FluxForgeTheme.textSecondary;

    return Column(
      children: [
        const SizedBox(height: 6),
        Icon(chevron, size: 14, color: textColor),
        const SizedBox(height: 8),
        Icon(widget.icon, size: 14, color: textColor),
        const SizedBox(height: 8),
        // Rotated label fills remaining height
        Expanded(
          child: RotatedBox(
            quarterTurns: widget.side == RailSide.left ? 3 : 1,
            child: Center(
              child: Text(
                widget.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildHorizontalContent() {
    final textColor = _hover
        ? widget.accentColor
        : FluxForgeTheme.textSecondary;
    return Row(
      children: [
        const SizedBox(width: 8),
        Icon(Icons.expand_less, size: 14, color: textColor),
        const SizedBox(width: 6),
        Icon(widget.icon, size: 14, color: textColor),
        const SizedBox(width: 8),
        Text(
          widget.label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: textColor,
          ),
        ),
        const Spacer(),
        Text(
          'CLICK TO EXPAND',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.8,
            color: FluxForgeTheme.textTertiary,
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
