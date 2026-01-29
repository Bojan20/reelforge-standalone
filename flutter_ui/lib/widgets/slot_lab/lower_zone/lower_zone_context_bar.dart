/// SlotLab Lower Zone Context Bar — Two-Row Tab Header
///
/// Implements the super-tab + sub-tab navigation system:
/// - Row 1: 7 Super-tabs (STAGES, EVENTS, MIX, MUSIC, DSP, BAKE, ENGINE) + [+] Menu
/// - Row 2: Sub-tabs (dynamic based on active super-tab)
///
/// Features:
/// - Keyboard shortcuts (Ctrl+Shift+T/E/X/A/G for super-tabs)
/// - Collapsible (shows only super-tabs when collapsed)
/// - Accent color per super-tab
/// - Menu popup for additional panels
///
/// Based on CLAUDE.md specification and MASTER_TODO.md SL-LZ-P0.2
library;

import 'package:flutter/material.dart';
import '../../../theme/fluxforge_theme.dart';
import 'lower_zone_types.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LOWER ZONE CONTEXT BAR
// ═══════════════════════════════════════════════════════════════════════════

/// Two-row header widget for Lower Zone navigation
class LowerZoneContextBar extends StatelessWidget {
  /// Currently active super-tab
  final SuperTab activeSuperTab;

  /// Index of active sub-tab within the super-tab
  final int activeSubTabIndex;

  /// Called when super-tab changes
  final ValueChanged<SuperTab> onSuperTabChanged;

  /// Called when sub-tab changes
  final ValueChanged<int> onSubTabChanged;

  /// Called when menu item is selected
  final ValueChanged<String> onMenuItemSelected;

  /// Whether the lower zone is expanded (shows sub-tabs)
  final bool isExpanded;

  /// Called when collapse/expand button is pressed
  final VoidCallback onToggleExpanded;

  const LowerZoneContextBar({
    super.key,
    required this.activeSuperTab,
    required this.activeSubTabIndex,
    required this.onSuperTabChanged,
    required this.onSubTabChanged,
    required this.onMenuItemSelected,
    required this.isExpanded,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final superConfig = getSuperTabConfig(activeSuperTab);

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1),
          bottom: isExpanded
              ? BorderSide(color: superConfig.accentColor.withValues(alpha: 0.3), width: 1)
              : BorderSide.none,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Super-tabs
          _buildSuperTabRow(context),

          // Row 2: Sub-tabs (only when expanded and not menu)
          if (isExpanded && activeSuperTab != SuperTab.menu)
            _buildSubTabRow(context),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUPER-TAB ROW (Row 1)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSuperTabRow(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          // Collapse/Expand button
          _CollapseButton(
            isExpanded: isExpanded,
            onTap: onToggleExpanded,
          ),

          const SizedBox(width: 4),

          // Divider
          Container(
            width: 1,
            height: 20,
            color: FluxForgeTheme.borderSubtle,
          ),

          const SizedBox(width: 4),

          // Super-tab buttons (all except menu)
          for (final superTab in SuperTab.values.where((t) => t != SuperTab.menu)) ...[
            _SuperTabButton(
              config: getSuperTabConfig(superTab),
              isActive: activeSuperTab == superTab,
              onTap: () => onSuperTabChanged(superTab),
            ),
            const SizedBox(width: 2),
          ],

          const Spacer(),

          // Menu button ([+])
          _MenuButton(
            onItemSelected: onMenuItemSelected,
          ),

          const SizedBox(width: 4),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUB-TAB ROW (Row 2)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSubTabRow(BuildContext context) {
    final subTabs = getSubTabsForSuperTab(activeSuperTab);
    final superConfig = getSuperTabConfig(activeSuperTab);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          // Sub-tab buttons
          for (int i = 0; i < subTabs.length; i++) ...[
            _SubTabButton(
              config: subTabs[i],
              isActive: activeSubTabIndex == i,
              accentColor: superConfig.accentColor,
              onTap: () => onSubTabChanged(i),
            ),
            if (i < subTabs.length - 1) const SizedBox(width: 4),
          ],

          const Spacer(),

          // Active tab indicator
          Text(
            '${superConfig.label} › ${subTabs[activeSubTabIndex.clamp(0, subTabs.length - 1)].label}',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COLLAPSE BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class _CollapseButton extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onTap;

  const _CollapseButton({
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isExpanded ? 'Collapse (`)' : 'Expand (`)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 200),
            turns: isExpanded ? 0 : 0.5,
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUPER-TAB BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class _SuperTabButton extends StatefulWidget {
  final SuperTabConfig config;
  final bool isActive;
  final VoidCallback onTap;

  const _SuperTabButton({
    required this.config,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_SuperTabButton> createState() => _SuperTabButtonState();
}

class _SuperTabButtonState extends State<_SuperTabButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = widget.isActive || _isHovering;

    return Tooltip(
      message: widget.config.shortcut != null
          ? '${widget.config.description} (${widget.config.shortcut})'
          : widget.config.description,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? widget.config.accentColor.withValues(alpha: 0.15)
                  : _isHovering
                      ? FluxForgeTheme.bgDeep.withValues(alpha: 0.5)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: widget.isActive
                  ? Border.all(
                      color: widget.config.accentColor.withValues(alpha: 0.3),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.config.icon,
                  size: 14,
                  color: widget.isActive
                      ? widget.config.accentColor
                      : isHighlighted
                          ? FluxForgeTheme.textPrimary
                          : FluxForgeTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.config.label,
                  style: TextStyle(
                    color: widget.isActive
                        ? widget.config.accentColor
                        : isHighlighted
                            ? FluxForgeTheme.textPrimary
                            : FluxForgeTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.normal,
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

// ═══════════════════════════════════════════════════════════════════════════
// SUB-TAB BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class _SubTabButton extends StatefulWidget {
  final SubTabConfig config;
  final bool isActive;
  final Color accentColor;
  final VoidCallback onTap;

  const _SubTabButton({
    required this.config,
    required this.isActive,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_SubTabButton> createState() => _SubTabButtonState();
}

class _SubTabButtonState extends State<_SubTabButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = widget.isActive || _isHovering;

    return Tooltip(
      message: widget.config.shortcutKey != null
          ? '${widget.config.description} (${widget.config.shortcutKey})'
          : widget.config.description,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? widget.accentColor.withValues(alpha: 0.1)
                  : _isHovering
                      ? FluxForgeTheme.bgMid.withValues(alpha: 0.5)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
              border: widget.isActive
                  ? Border(
                      bottom: BorderSide(
                        color: widget.accentColor,
                        width: 2,
                      ),
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.config.icon,
                  size: 12,
                  color: widget.isActive
                      ? widget.accentColor
                      : isHighlighted
                          ? FluxForgeTheme.textPrimary
                          : FluxForgeTheme.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.config.label,
                  style: TextStyle(
                    color: widget.isActive
                        ? widget.accentColor
                        : isHighlighted
                            ? FluxForgeTheme.textPrimary
                            : FluxForgeTheme.textMuted,
                    fontSize: 10,
                    fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                // Shortcut hint
                if (widget.config.shortcutKey != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      widget.config.shortcutKey!,
                      style: TextStyle(
                        color: FluxForgeTheme.textMuted.withValues(alpha: 0.7),
                        fontSize: 8,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MENU BUTTON ([+])
// ═══════════════════════════════════════════════════════════════════════════

class _MenuButton extends StatefulWidget {
  final ValueChanged<String> onItemSelected;

  const _MenuButton({
    required this.onItemSelected,
  });

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: widget.onItemSelected,
      tooltip: 'Additional Panels',
      offset: const Offset(0, 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: FluxForgeTheme.bgMid,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovering
                ? FluxForgeTheme.bgDeep.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _isHovering
                  ? FluxForgeTheme.borderSubtle
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add,
                size: 14,
                color: _isHovering
                    ? FluxForgeTheme.textPrimary
                    : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 2),
              Text(
                'More',
                style: TextStyle(
                  color: _isHovering
                      ? FluxForgeTheme.textPrimary
                      : FluxForgeTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
      itemBuilder: (context) => [
        for (final item in kMenuItems)
          PopupMenuItem<String>(
            value: item.id,
            child: Row(
              children: [
                Icon(item.icon, size: 16, color: FluxForgeTheme.textSecondary),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
