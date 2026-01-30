/// Breadcrumb Trail Widget
///
/// Shows hierarchical navigation context for Lower Zone:
/// - Super-tab > Sub-tab > Panel (if applicable)
/// - Clickable navigation to parent levels
/// - Compact horizontal layout
///
/// Example: "EVENTS > Event List > Container Audio"
library;

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Breadcrumb item with label and optional navigation
class BreadcrumbItem {
  final String label;
  final VoidCallback? onTap;
  final Color? accentColor;

  const BreadcrumbItem({
    required this.label,
    this.onTap,
    this.accentColor,
  });
}

/// Breadcrumb trail widget showing hierarchical navigation context
class BreadcrumbTrail extends StatelessWidget {
  final List<BreadcrumbItem> items;
  final double height;
  final EdgeInsets padding;

  const BreadcrumbTrail({
    super.key,
    required this.items,
    this.height = 24,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Home icon
          Icon(
            Icons.home_rounded,
            size: 14,
            color: FluxForgeTheme.textMuted,
          ),
          const SizedBox(width: 6),

          // Breadcrumb items
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) ...[
              // Separator
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: FluxForgeTheme.textMuted.withValues(alpha: 0.5),
                ),
              ),
            ],

            // Breadcrumb item
            _BreadcrumbItemWidget(
              item: items[i],
              isLast: i == items.length - 1,
            ),
          ],

          const Spacer(),

          // Optional: Quick actions
          _buildQuickActions(),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Collapse all button
        _QuickActionButton(
          icon: Icons.unfold_less_rounded,
          tooltip: 'Collapse All',
          onTap: () {
            // TODO: Wire to controller
          },
        ),
        const SizedBox(width: 4),

        // Expand all button
        _QuickActionButton(
          icon: Icons.unfold_more_rounded,
          tooltip: 'Expand All',
          onTap: () {
            // TODO: Wire to controller
          },
        ),
      ],
    );
  }
}

/// Individual breadcrumb item widget
class _BreadcrumbItemWidget extends StatefulWidget {
  final BreadcrumbItem item;
  final bool isLast;

  const _BreadcrumbItemWidget({
    required this.item,
    required this.isLast,
  });

  @override
  State<_BreadcrumbItemWidget> createState() => _BreadcrumbItemWidgetState();
}

class _BreadcrumbItemWidgetState extends State<_BreadcrumbItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isClickable = widget.item.onTap != null && !widget.isLast;

    return MouseRegion(
      cursor: isClickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isClickable ? widget.item.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _isHovered && isClickable
                ? FluxForgeTheme.bgSurface.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: widget.isLast && widget.item.accentColor != null
                ? Border.all(
                    color: widget.item.accentColor!.withValues(alpha: 0.3),
                    width: 1,
                  )
                : null,
          ),
          child: Text(
            widget.item.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: widget.isLast ? FontWeight.w600 : FontWeight.w400,
              color: widget.isLast
                  ? (widget.item.accentColor ?? FluxForgeTheme.textPrimary)
                  : (_isHovered && isClickable
                      ? FluxForgeTheme.textPrimary
                      : FluxForgeTheme.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick action button in breadcrumb trail
class _QuickActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<_QuickActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _isHovered
                  ? FluxForgeTheme.bgSurface.withValues(alpha: 0.5)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _isHovered
                  ? FluxForgeTheme.textPrimary
                  : FluxForgeTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
