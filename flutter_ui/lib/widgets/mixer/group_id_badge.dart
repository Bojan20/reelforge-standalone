/// Group ID Badge — Pro Tools style group membership indicator
///
/// Small colored dot + group letter (a-z).
/// Click opens GroupManagerPanel.
/// Shows tooltip with group name.

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// GROUP COLORS
// ═══════════════════════════════════════════════════════════════════════════

/// Pro Tools-style group colors (a-z → 26 colors).
class GroupColors {
  static const List<Color> palette = [
    Color(0xFFFF4060), // a — red
    Color(0xFF4A9EFF), // b — blue
    Color(0xFF40FF90), // c — green
    Color(0xFFFFD740), // d — yellow
    Color(0xFFFF9040), // e — orange
    Color(0xFF9370DB), // f — purple
    Color(0xFF40C8FF), // g — cyan
    Color(0xFFFF69B4), // h — pink
    Color(0xFF7FFF00), // i — chartreuse
    Color(0xFFFF6347), // j — tomato
    Color(0xFF00CED1), // k — dark turquoise
    Color(0xFFDA70D6), // l — orchid
    Color(0xFFBDB76B), // m — dark khaki
    Color(0xFF87CEEB), // n — sky blue
    Color(0xFFFFA07A), // o — light salmon
    Color(0xFF98FB98), // p — pale green
    Color(0xFFDDA0DD), // q — plum
    Color(0xFFF0E68C), // r — khaki
    Color(0xFFADD8E6), // s — light blue
    Color(0xFFFFB6C1), // t — light pink
    Color(0xFF90EE90), // u — light green
    Color(0xFFE6E6FA), // v — lavender
    Color(0xFFFFDAB9), // w — peach puff
    Color(0xFFD2B48C), // x — tan
    Color(0xFFB0C4DE), // y — light steel blue
    Color(0xFFC0C0C0), // z — silver
  ];

  static Color forGroup(String groupId) {
    if (groupId.isEmpty) return const Color(0xFF555566);
    final idx = groupId.toLowerCase().codeUnitAt(0) - 'a'.codeUnitAt(0);
    if (idx < 0 || idx >= palette.length) return const Color(0xFF555566);
    return palette[idx];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GROUP ID BADGE
// ═══════════════════════════════════════════════════════════════════════════

/// Compact group membership badge showing colored dot(s) + group letter(s).
class GroupIdBadge extends StatelessWidget {
  final String groupId; // "a", "b", "a,c" — comma-separated for multi-group
  final VoidCallback? onTap; // Opens GroupManagerPanel
  final bool isNarrow;

  const GroupIdBadge({
    super.key,
    required this.groupId,
    this.onTap,
    this.isNarrow = false,
  });

  @override
  Widget build(BuildContext context) {
    if (groupId.isEmpty) return _buildEmpty();
    return _buildActive();
  }

  Widget _buildEmpty() {
    return SizedBox(
      height: 14,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF111117),
            borderRadius: BorderRadius.circular(2),
          ),
          child: const Center(
            child: Text(
              '—',
              style: TextStyle(
                color: Color(0xFF333344),
                fontSize: 8,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActive() {
    final groups = groupId.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty).toList();
    if (groups.isEmpty) return _buildEmpty();

    return SizedBox(
      height: 14,
      child: Tooltip(
        message: 'Group${groups.length > 1 ? 's' : ''}: ${groups.map((g) => g.toUpperCase()).join(', ')}',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF14141A),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: GroupColors.forGroup(groups.first).withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < groups.length && i < (isNarrow ? 2 : 4); i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  _buildGroupDot(groups[i]),
                ],
                if (groups.length > (isNarrow ? 2 : 4)) ...[
                  const SizedBox(width: 2),
                  Text(
                    '+${groups.length - (isNarrow ? 2 : 4)}',
                    style: const TextStyle(
                      color: Color(0xFF888899),
                      fontSize: 7,
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

  Widget _buildGroupDot(String gid) {
    final color = GroupColors.forGroup(gid);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 1),
        Text(
          gid.toLowerCase(),
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
