// Lower Zone Context Bar — Super-tabs + Sub-tabs
//
// Reusable widget for the top bar of any Lower Zone.
// Contains Super-tabs (1-5) and Sub-tabs (Q-R).

import 'package:flutter/material.dart';

import 'lower_zone_types.dart';
import 'daw_lower_zone_controller.dart' show RecentTabEntry;

/// Generic context bar for Lower Zone
/// Works with any section (DAW, Middleware, SlotLab)
class LowerZoneContextBar extends StatelessWidget {
  /// Super-tab labels (e.g., ['BROWSE', 'EDIT', 'MIX', ...])
  final List<String> superTabLabels;

  /// Super-tab icons
  final List<IconData> superTabIcons;

  /// Keyboard shortcut hints for super-tabs (e.g., ['⌘⇧T', '⌘⇧E', ...])
  /// If null, shows index number (1, 2, 3...)
  final List<String>? superTabShortcuts;

  /// Currently selected super-tab index
  final int selectedSuperTab;

  /// Sub-tab labels for current super-tab
  final List<String> subTabLabels;

  /// Keyboard shortcut hints for sub-tabs (e.g., ['Q', 'W', 'E', 'R'])
  /// If null, uses default Q, W, E, R
  final List<String>? subTabShortcuts;

  /// Tooltips for sub-tabs (P1.4: context for new users)
  final List<String>? subTabTooltips;

  /// Tooltips for super-tabs
  final List<String>? superTabTooltips;

  /// Currently selected sub-tab index
  final int selectedSubTab;

  /// Section accent color
  final Color accentColor;

  /// Whether Lower Zone is expanded
  final bool isExpanded;

  /// Callback when super-tab is selected
  final ValueChanged<int> onSuperTabSelected;

  /// Callback when sub-tab is selected
  final ValueChanged<int> onSubTabSelected;

  /// Callback when toggle button is pressed
  final VoidCallback onToggle;

  /// Optional preset dropdown widget
  final Widget? presetDropdown;

  /// P1.5: Recent tabs for quick access (max 3 shown)
  final List<RecentTabEntry>? recentTabs;

  /// P1.5: Callback when recent tab is selected
  final ValueChanged<RecentTabEntry>? onRecentTabSelected;

  // ═══════════════════════════════════════════════════════════════════════════
  // P2.1: Split View Mode controls
  // ═══════════════════════════════════════════════════════════════════════════

  /// Whether split view is enabled (null = split view not available)
  final bool? splitEnabled;

  /// Current split direction
  final SplitDirection? splitDirection;

  /// Callback to toggle split view on/off
  final VoidCallback? onSplitToggle;

  /// Callback to toggle split direction (horizontal/vertical)
  final VoidCallback? onSplitDirectionToggle;

  /// Callback to swap pane contents
  final VoidCallback? onSwapPanes;

  const LowerZoneContextBar({
    super.key,
    required this.superTabLabels,
    required this.superTabIcons,
    this.superTabShortcuts,
    this.superTabTooltips,
    required this.selectedSuperTab,
    required this.subTabLabels,
    this.subTabShortcuts,
    this.subTabTooltips,
    required this.selectedSubTab,
    required this.accentColor,
    required this.isExpanded,
    required this.onSuperTabSelected,
    required this.onSubTabSelected,
    required this.onToggle,
    this.presetDropdown,
    this.recentTabs,
    this.onRecentTabSelected,
    // P2.1: Split view
    this.splitEnabled,
    this.splitDirection,
    this.onSplitToggle,
    this.onSplitDirectionToggle,
    this.onSwapPanes,
  });

  @override
  Widget build(BuildContext context) {
    // Dynamic height: 32px (super-tabs only) when collapsed, 60px when expanded (+ sub-tabs 28px)
    final height = isExpanded ? kContextBarHeight : kContextBarCollapsedHeight;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        border: Border(
          bottom: BorderSide(color: LowerZoneColors.borderSubtle),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          // Super-tabs row (32px)
          _buildSuperTabs(),
          // Sub-tabs row (28px) — only when expanded
          if (isExpanded) Expanded(child: _buildSubTabs()),
        ],
      ),
    );
  }

  Widget _buildSuperTabs() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Toggle button
          _buildToggleButton(),
          const SizedBox(width: 8),
          // Super-tabs
          ...List.generate(superTabLabels.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _buildSuperTab(index),
            );
          }),
          const Spacer(),
          // P1.5: Recent tabs quick access
          if (recentTabs != null && recentTabs!.isNotEmpty) ...[
            _buildRecentTabs(),
            const SizedBox(width: 8),
          ],
          // Preset dropdown (optional)
          if (presetDropdown != null) ...[
            presetDropdown!,
            const SizedBox(width: 8),
          ],
          // P2.1: Split view controls (if available)
          if (onSplitToggle != null) ...[
            _buildSplitViewControls(),
            const SizedBox(width: 8),
          ],
          // Search (placeholder)
          _buildSearchField(),
        ],
      ),
    );
  }

  Widget _buildToggleButton() {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: LowerZoneColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.border),
        ),
        child: Icon(
          isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
          size: 16,
          color: LowerZoneColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildSuperTab(int index) {
    final isSelected = index == selectedSuperTab;

    // Get tooltip if available
    final tooltipText = superTabTooltips != null && index < superTabTooltips!.length
        ? superTabTooltips![index]
        : null;

    final tabWidget = GestureDetector(
      onTap: () => onSuperTabSelected(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? accentColor.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              superTabIcons[index],
              size: 12,
              color: isSelected ? accentColor : LowerZoneColors.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              superTabLabels[index],
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeLabel,
                fontWeight: FontWeight.bold,
                color: isSelected ? accentColor : LowerZoneColors.textTertiary,
              ),
            ),
            const SizedBox(width: 4),
            // Show keyboard shortcut hint
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.2)
                    : LowerZoneColors.bgMid,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                superTabShortcuts != null && index < superTabShortcuts!.length
                    ? superTabShortcuts![index]
                    : '${index + 1}',
                style: TextStyle(
                  fontSize: LowerZoneTypography.sizeTiny,
                  fontFamily: 'monospace',
                  color: isSelected
                      ? accentColor.withValues(alpha: 0.8)
                      : LowerZoneColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Wrap with Tooltip if available (P1.4)
    if (tooltipText != null) {
      return Tooltip(
        message: tooltipText,
        waitDuration: const Duration(milliseconds: 500),
        child: tabWidget,
      );
    }

    return tabWidget;
  }

  Widget _buildSearchField() {
    return Container(
      width: 150,
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 12, color: LowerZoneColors.textMuted),
          const SizedBox(width: 4),
          Text(
            'Search...',
            style: TextStyle(
              fontSize: LowerZoneTypography.sizeBadge,
              color: LowerZoneColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// P1.5: Build recent tabs quick access icons
  Widget _buildRecentTabs() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label
        Text(
          'Recent:',
          style: TextStyle(
            fontSize: LowerZoneTypography.sizeTiny,
            color: LowerZoneColors.textMuted,
          ),
        ),
        const SizedBox(width: 4),
        // Recent tab buttons
        ...recentTabs!.map((entry) => _buildRecentTabButton(entry)),
      ],
    );
  }

  /// P1.5: Build single recent tab button
  Widget _buildRecentTabButton(RecentTabEntry entry) {
    return Tooltip(
      message: 'Recent: ${entry.label}',
      waitDuration: const Duration(milliseconds: 300),
      child: GestureDetector(
        onTap: () => onRecentTabSelected?.call(entry),
        child: Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: LowerZoneColors.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: LowerZoneColors.border),
          ),
          child: Icon(
            entry.icon,
            size: 12,
            color: LowerZoneColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildSubTabs() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: LowerZoneColors.bgDeep,
        border: Border(
          bottom: BorderSide(color: LowerZoneColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 32), // Align with super-tabs (toggle button space)
          ...List.generate(subTabLabels.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _buildSubTab(index),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSubTab(int index) {
    final isSelected = index == selectedSubTab;
    // Default shortcuts if not provided
    final defaultShortcuts = ['Q', 'W', 'E', 'R'];
    final shortcut = subTabShortcuts != null && index < subTabShortcuts!.length
        ? subTabShortcuts![index]
        : (index < defaultShortcuts.length ? defaultShortcuts[index] : '');

    // Get tooltip if available
    final tooltipText = subTabTooltips != null && index < subTabTooltips!.length
        ? subTabTooltips![index]
        : null;

    final tabWidget = GestureDetector(
      onTap: () => onSubTabSelected(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border(
            bottom: BorderSide(
              color: isSelected ? accentColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              subTabLabels[index],
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeLabel,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? accentColor : LowerZoneColors.textSecondary,
              ),
            ),
            if (shortcut.isNotEmpty) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor.withValues(alpha: 0.15)
                      : LowerZoneColors.bgMid,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  shortcut,
                  style: TextStyle(
                    fontSize: LowerZoneTypography.sizeTiny,
                    fontFamily: 'monospace',
                    color: isSelected
                        ? accentColor.withValues(alpha: 0.7)
                        : LowerZoneColors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // Wrap with Tooltip if available (P1.4)
    if (tooltipText != null) {
      return Tooltip(
        message: tooltipText,
        waitDuration: const Duration(milliseconds: 500),
        child: tabWidget,
      );
    }

    return tabWidget;
  }

  /// P2.1: Build split view control buttons
  Widget _buildSplitViewControls() {
    final isEnabled = splitEnabled ?? false;
    final direction = splitDirection ?? SplitDirection.horizontal;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Split toggle button
        Tooltip(
          message: isEnabled ? 'Disable Split View' : 'Enable Split View (⇧S)',
          waitDuration: const Duration(milliseconds: 300),
          child: GestureDetector(
            onTap: onSplitToggle,
            child: Container(
              width: 28,
              height: 22,
              decoration: BoxDecoration(
                color: isEnabled
                    ? accentColor.withValues(alpha: 0.2)
                    : LowerZoneColors.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isEnabled
                      ? accentColor.withValues(alpha: 0.5)
                      : LowerZoneColors.border,
                ),
              ),
              child: Icon(
                Icons.vertical_split,
                size: 14,
                color: isEnabled ? accentColor : LowerZoneColors.textSecondary,
              ),
            ),
          ),
        ),
        // Direction and swap buttons only shown when split is enabled
        if (isEnabled) ...[
          const SizedBox(width: 4),
          // Direction toggle
          Tooltip(
            message: direction == SplitDirection.horizontal
                ? 'Switch to Vertical Split (⇧D)'
                : 'Switch to Horizontal Split (⇧D)',
            waitDuration: const Duration(milliseconds: 300),
            child: GestureDetector(
              onTap: onSplitDirectionToggle,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: LowerZoneColors.bgMid,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: LowerZoneColors.border),
                ),
                child: Icon(
                  direction == SplitDirection.horizontal
                      ? Icons.view_column
                      : Icons.view_agenda,
                  size: 12,
                  color: LowerZoneColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Swap panes button
          Tooltip(
            message: 'Swap Panes (⇧X)',
            waitDuration: const Duration(milliseconds: 300),
            child: GestureDetector(
              onTap: onSwapPanes,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: LowerZoneColors.bgMid,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: LowerZoneColors.border),
                ),
                child: Icon(
                  Icons.swap_horiz,
                  size: 12,
                  color: LowerZoneColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
