/// DAW Panel Shared Helpers (P0.1)
///
/// Common UI builders used across multiple DAW Lower Zone panels.
/// Extracted to avoid duplication.
///
/// Created: 2026-01-26
library;

import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SHARED HEADER BUILDERS
// ═══════════════════════════════════════════════════════════════════════════

/// Standard section header (icon + title)
Widget buildSectionHeader(String title, IconData icon, {Color? color}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color ?? LowerZoneColors.dawAccent),
      const SizedBox(width: 6),
      Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color ?? LowerZoneColors.dawAccent,
          letterSpacing: 0.5,
        ),
      ),
    ],
  );
}

/// Browser-style header (used in BROWSE panels)
Widget buildBrowserHeader(String title, IconData icon) {
  return buildSectionHeader(title, icon);
}

/// Sub-section header (smaller, muted)
Widget buildSubSectionHeader(String label) {
  return Text(
    label,
    style: const TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.bold,
      color: LowerZoneColors.textMuted,
      letterSpacing: 0.5,
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED INFO DISPLAYS
// ═══════════════════════════════════════════════════════════════════════════

/// Property row (label + value)
Widget buildPropertyRow(String label, String value) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    margin: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(
      color: LowerZoneColors.bgDeepest,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// Info row with icon
Widget buildInfoRow(String label, String value, IconData icon) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    margin: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(
      color: LowerZoneColors.bgDeepest,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      children: [
        Icon(icon, size: 12, color: LowerZoneColors.textMuted),
        const SizedBox(width: 6),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED EMPTY STATES
// ═══════════════════════════════════════════════════════════════════════════

/// Generic empty state widget
Widget buildEmptyState({
  required IconData icon,
  required String title,
  String? subtitle,
  double iconSize = 48,
}) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: iconSize,
          color: LowerZoneColors.textMuted.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: LowerZoneColors.textMuted,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              color: LowerZoneColors.textTertiary,
            ),
          ),
        ],
      ],
    ),
  );
}
