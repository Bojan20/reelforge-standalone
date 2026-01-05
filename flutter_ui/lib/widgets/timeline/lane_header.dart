/// Lane Header Widget
///
/// Compact header for recording lanes in comping view:
/// - Take name and number
/// - Active/audition toggle
/// - Rating indicator
/// - Mute/solo buttons
/// - Expand/collapse

import 'package:flutter/material.dart';
import '../../models/comping_models.dart';
import '../../theme/reelforge_theme.dart';

class LaneHeader extends StatelessWidget {
  final RecordingLane lane;
  final bool isActive;
  final bool isCompLane;
  final VoidCallback? onActivate;
  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleVisible;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onRename;

  const LaneHeader({
    super.key,
    required this.lane,
    this.isActive = false,
    this.isCompLane = false,
    this.onActivate,
    this.onToggleMute,
    this.onToggleVisible,
    this.onDelete,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final height = lane.height;

    return GestureDetector(
      onTap: onActivate,
      child: Container(
        width: 100,
        height: height,
        decoration: BoxDecoration(
          color: isActive
              ? ReelForgeTheme.accentBlue.withValues(alpha: 0.2)
              : ReelForgeTheme.bgDeep,
          border: Border(
            right: BorderSide(
              color: isActive
                  ? ReelForgeTheme.accentBlue
                  : ReelForgeTheme.borderSubtle,
            ),
            bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: name + active indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  // Active indicator
                  if (isActive)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: ReelForgeTheme.accentGreen,
                        shape: BoxShape.circle,
                      ),
                    ),

                  // Lane name
                  Expanded(
                    child: Text(
                      isCompLane ? 'Comp' : lane.displayName,
                      style: ReelForgeTheme.label.copyWith(
                        fontSize: 10,
                        color: isActive
                            ? ReelForgeTheme.textPrimary
                            : ReelForgeTheme.textSecondary,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Visibility toggle
                  InkWell(
                    onTap: onToggleVisible,
                    child: Icon(
                      lane.visible
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 12,
                      color: lane.visible
                          ? ReelForgeTheme.textSecondary
                          : ReelForgeTheme.textDisabled,
                    ),
                  ),
                ],
              ),
            ),

            // Middle: mute button if space
            if (height > 40) ...[
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    // Mute button
                    _buildMiniButton(
                      label: 'M',
                      isActive: lane.muted,
                      activeColor: ReelForgeTheme.accentOrange,
                      onTap: onToggleMute,
                    ),
                    const SizedBox(width: 4),
                    // Take count
                    Text(
                      '${lane.takes.length}',
                      style: ReelForgeTheme.mono.copyWith(
                        fontSize: 9,
                        color: ReelForgeTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniButton({
    required String label,
    required bool isActive,
    required Color activeColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 16,
        height: 14,
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isActive ? activeColor : ReelForgeTheme.borderSubtle,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: isActive
                ? ReelForgeTheme.bgDeepest
                : ReelForgeTheme.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// Expanded lane header with more controls
class LaneHeaderExpanded extends StatelessWidget {
  final RecordingLane lane;
  final bool isActive;
  final VoidCallback? onActivate;
  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleVisible;
  final VoidCallback? onDelete;
  final VoidCallback? onDuplicate;
  final ValueChanged<TakeRating>? onRatingChanged;

  const LaneHeaderExpanded({
    super.key,
    required this.lane,
    this.isActive = false,
    this.onActivate,
    this.onToggleMute,
    this.onToggleVisible,
    this.onDelete,
    this.onDuplicate,
    this.onRatingChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: lane.height,
      decoration: BoxDecoration(
        color: isActive
            ? ReelForgeTheme.accentBlue.withValues(alpha: 0.15)
            : ReelForgeTheme.bgDeep,
        border: Border(
          right: BorderSide(
            color: isActive
                ? ReelForgeTheme.accentBlue
                : ReelForgeTheme.borderSubtle,
            width: isActive ? 2 : 1,
          ),
          bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with name
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                // Active indicator
                GestureDetector(
                  onTap: onActivate,
                  child: Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: isActive
                          ? ReelForgeTheme.accentGreen
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isActive
                            ? ReelForgeTheme.accentGreen
                            : ReelForgeTheme.textTertiary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),

                // Lane name
                Expanded(
                  child: Text(
                    lane.displayName,
                    style: ReelForgeTheme.label.copyWith(
                      fontSize: 11,
                      color: isActive
                          ? ReelForgeTheme.textPrimary
                          : ReelForgeTheme.textSecondary,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Menu
                PopupMenuButton<String>(
                  iconSize: 14,
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_vert,
                    size: 14,
                    color: ReelForgeTheme.textTertiary,
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'delete':
                        onDelete?.call();
                        break;
                      case 'duplicate':
                        onDuplicate?.call();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'duplicate',
                      height: 32,
                      child: Row(
                        children: [
                          Icon(Icons.copy, size: 14),
                          SizedBox(width: 8),
                          Text('Duplicate', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      height: 32,
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 14, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Controls
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // M/S buttons
                  Row(
                    children: [
                      _buildControlButton(
                        'M',
                        lane.muted,
                        ReelForgeTheme.accentOrange,
                        onToggleMute,
                      ),
                      const SizedBox(width: 4),
                      _buildControlButton(
                        'V',
                        lane.visible,
                        ReelForgeTheme.accentBlue,
                        onToggleVisible,
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Rating (if has takes)
                  if (lane.takes.isNotEmpty) ...[
                    Text(
                      '${lane.takes.length} take${lane.takes.length > 1 ? 's' : ''}',
                      style: ReelForgeTheme.mono.copyWith(
                        fontSize: 9,
                        color: ReelForgeTheme.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(
    String label,
    bool isActive,
    Color activeColor,
    VoidCallback? onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 18,
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isActive ? activeColor : ReelForgeTheme.borderSubtle,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isActive
                ? ReelForgeTheme.bgDeepest
                : ReelForgeTheme.textTertiary,
          ),
        ),
      ),
    );
  }
}
