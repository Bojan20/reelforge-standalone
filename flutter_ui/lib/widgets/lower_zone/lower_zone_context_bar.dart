// Lower Zone Context Bar — Super-tabs + Sub-tabs
//
// Reusable widget for the top bar of any Lower Zone.
// Contains Super-tabs (1-5) and Sub-tabs (Q-R).

import 'package:flutter/material.dart';

import 'lower_zone_types.dart';

/// Generic context bar for Lower Zone
/// Works with any section (DAW, Middleware, SlotLab)
class LowerZoneContextBar extends StatelessWidget {
  /// Super-tab labels (e.g., ['BROWSE', 'EDIT', 'MIX', ...])
  final List<String> superTabLabels;

  /// Super-tab icons
  final List<IconData> superTabIcons;

  /// Currently selected super-tab index
  final int selectedSuperTab;

  /// Sub-tab labels for current super-tab
  final List<String> subTabLabels;

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

  const LowerZoneContextBar({
    super.key,
    required this.superTabLabels,
    required this.superTabIcons,
    required this.selectedSuperTab,
    required this.subTabLabels,
    required this.selectedSubTab,
    required this.accentColor,
    required this.isExpanded,
    required this.onSuperTabSelected,
    required this.onSubTabSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kContextBarHeight,
      decoration: const BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        border: Border(
          bottom: BorderSide(color: LowerZoneColors.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          // Super-tabs row (32px)
          _buildSuperTabs(),
          // Sub-tabs row (28px)
          if (isExpanded) _buildSubTabs(),
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
    return GestureDetector(
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
            Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeTiny,
                color: isSelected ? accentColor.withValues(alpha: 0.6) : LowerZoneColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
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
    final shortcuts = ['Q', 'W', 'E', 'R'];
    return GestureDetector(
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
            const SizedBox(width: 4),
            Text(
              shortcuts[index],
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeTiny,
                color: isSelected ? accentColor.withValues(alpha: 0.5) : LowerZoneColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
