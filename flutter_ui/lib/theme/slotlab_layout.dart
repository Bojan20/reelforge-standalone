/// SlotLab Layout Design Tokens
///
/// Centralized spacing, typography, and dimension constants
/// for consistent SlotLab UI. Replaces 15+ hardcoded values
/// with a coherent 4-8-12-16-24 grid system.

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SPACING — 4px base grid
// ═══════════════════════════════════════════════════════════════════════════════

class SlotLabSpacing {
  SlotLabSpacing._();

  /// 2px — micro gaps (border offsets, divider margins)
  static const double xxs = 2.0;

  /// 4px — tight gaps (icon-to-label, badge padding)
  static const double xs = 4.0;

  /// 8px — default padding (panel content, list items)
  static const double sm = 8.0;

  /// 12px — medium padding (section content, toolbar items)
  static const double md = 12.0;

  /// 16px — large padding (panel outer padding, section gaps)
  static const double lg = 16.0;

  /// 24px — section separation (between major UI groups)
  static const double xl = 24.0;

  /// 32px — zone separation (between major layout zones)
  static const double xxl = 32.0;

  // ── Common EdgeInsets ──

  static const EdgeInsets panelPadding = EdgeInsets.all(sm);
  static const EdgeInsets sectionPadding = EdgeInsets.all(md);
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(horizontal: sm, vertical: xs);
  static const EdgeInsets tabBarPadding = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets toolbarPadding = EdgeInsets.symmetric(horizontal: sm, vertical: xs);
  static const EdgeInsets chipPadding = EdgeInsets.symmetric(horizontal: sm, vertical: xxs);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TYPOGRAPHY — minimum 10px for any visible text
// ═══════════════════════════════════════════════════════════════════════════════

class SlotLabTypo {
  SlotLabTypo._();

  /// 8px — ONLY for decorative badges (not readable text)
  static const double micro = 8.0;

  /// 10px — secondary info (layer counts, timestamps)
  static const double caption = 10.0;

  /// 11px — default text, tab labels, button labels
  static const double body = 11.0;

  /// 12px — emphasized body text
  static const double bodyEmphasis = 12.0;

  /// 13px — section titles, panel headers
  static const double title = 13.0;

  /// 14px — zone headers, important status
  static const double header = 14.0;

  /// 16px — dialog titles
  static const double dialogTitle = 16.0;

  // ── Common TextStyles ──

  static const TextStyle tabLabel = TextStyle(
    fontSize: body,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  static const TextStyle tabLabelActive = TextStyle(
    fontSize: body,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  static const TextStyle tabLabelInactive = TextStyle(
    fontSize: body,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    color: Color(0xFF606068),
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: title,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.0,
  );

  static const TextStyle categoryLabel = TextStyle(
    fontSize: caption,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.0,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// DIMENSIONS — panel sizes, tab bar heights, constraints
// ═══════════════════════════════════════════════════════════════════════════════

class SlotLabDimens {
  SlotLabDimens._();

  // ── Header ──
  static const double headerRow1Height = 32.0;
  static const double headerRow2Height = 28.0;
  static const double headerTotalHeight = headerRow1Height + headerRow2Height;

  // ── Panel widths ──
  static const double leftPanelWidth = 260.0;
  static const double leftPanelWideWidth = 280.0; // AUREXIS mode
  static const double rightPanelWidth = 300.0;

  // ── Tab bars ──
  static const double panelTabBarHeight = 28.0;
  static const double centerToolbarHeight = 36.0;

  // ── Tab icon/label ──
  static const double tabIconSize = 12.0;
  static const double tabIconLabelGap = 4.0;

  // ── Lower zone (from lower_zone_types.dart) ──
  // These mirror kLowerZone* constants — use those for lower zone
  static const double lowerZoneMinHeight = 150.0;
  static const double lowerZoneMaxHeight = 600.0;
  static const double lowerZoneDefaultHeight = 500.0;

  // ── Buttons ──
  static const double headerIconBtnSize = 26.0;
  static const double diagButtonIconSize = 13.0;

  // ── Borders ──
  static const double borderWidth = 1.0;
  static const double activeBorderWidth = 2.0;
}
