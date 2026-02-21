/// Mixer Section Divider — vertical separator between channel groups
///
/// Shows section label, track count, and collapsible toggle.
/// Pro Tools style: thin vertical bar between Tracks | Buses | Aux | VCA | Master

import 'package:flutter/material.dart';
import '../../models/mixer_view_models.dart';

class MixerSectionDivider extends StatelessWidget {
  final MixerSection section;
  final int trackCount;
  final bool isVisible;
  final VoidCallback onToggle;

  const MixerSectionDivider({
    super.key,
    required this.section,
    required this.trackCount,
    required this.isVisible,
    required this.onToggle,
  });

  Color get _sectionColor => switch (section) {
    MixerSection.tracks => const Color(0xFF4A9EFF),
    MixerSection.buses => const Color(0xFF40FF90),
    MixerSection.auxes => const Color(0xFF9370DB),
    MixerSection.vcas => const Color(0xFFFF9040),
    MixerSection.master => const Color(0xFFFFD700),
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: 20,
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E12),
          border: Border(
            left: BorderSide(color: Colors.white.withOpacity(0.06)),
            right: BorderSide(color: Colors.white.withOpacity(0.06)),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 4),
            // Section color indicator
            Container(
              width: 12,
              height: 3,
              decoration: BoxDecoration(
                color: _sectionColor,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(height: 6),
            // Vertical label
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(
                  '${section.shortLabel} ($trackCount)',
                  style: TextStyle(
                    color: isVisible
                        ? _sectionColor.withOpacity(0.9)
                        : Colors.white.withOpacity(0.3),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Collapse chevron
            Icon(
              isVisible ? Icons.chevron_left : Icons.chevron_right,
              size: 12,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
