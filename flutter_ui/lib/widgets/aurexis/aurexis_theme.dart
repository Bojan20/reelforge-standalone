import 'package:flutter/material.dart';

/// AUREXIS panel color scheme and styling constants.
class AurexisColors {
  AurexisColors._();

  // ═══ BACKGROUNDS ═══
  static const Color bgPanel = Color(0xFF0E0E14);
  static const Color bgSection = Color(0xFF13131A);
  static const Color bgSectionHeader = Color(0xFF18181F);
  static const Color bgSlider = Color(0xFF1A1A22);
  static const Color bgInput = Color(0xFF0C0C10);

  // ═══ BORDERS ═══
  static const Color border = Color(0xFF2A2A35);
  static const Color borderSubtle = Color(0xFF1F1F28);

  // ═══ TEXT ═══
  static const Color textPrimary = Color(0xFFE8E8F0);
  static const Color textSecondary = Color(0xFF8888A0);
  static const Color textLabel = Color(0xFF6E6E88);
  static const Color textValue = Color(0xFFBBBBD0);

  // ═══ ACCENT ═══
  static const Color accent = Color(0xFF40FF90);
  static const Color accentDim = Color(0xFF2AAA60);
  static const Color accentGlow = Color(0x4040FF90);

  // ═══ CATEGORY COLORS ═══
  static const Color spatial = Color(0xFF40AAFF);
  static const Color dynamics = Color(0xFFFF6040);
  static const Color music = Color(0xFFBB60FF);
  static const Color variation = Color(0xFFFFAA40);

  // ═══ STATUS ═══
  static const Color locked = Color(0xFFFF4444);
  static const Color modified = Color(0xFFFFAA00);
  static const Color active = Color(0xFF40FF90);
  static const Color inactive = Color(0xFF555566);

  // ═══ FATIGUE LEVELS ═══
  static const Color fatigueFresh = Color(0xFF40FF90);
  static const Color fatigueMild = Color(0xFFAAFF40);
  static const Color fatigueModerate = Color(0xFFFFCC00);
  static const Color fatigueHigh = Color(0xFFFF6600);
  static const Color fatigueCritical = Color(0xFFFF2222);
}

class AurexisTextStyles {
  AurexisTextStyles._();

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: 'SF Mono',
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    color: AurexisColors.textSecondary,
  );

  static const TextStyle paramLabel = TextStyle(
    fontFamily: 'SF Mono',
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: AurexisColors.textLabel,
  );

  static const TextStyle paramValue = TextStyle(
    fontFamily: 'SF Mono',
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AurexisColors.textValue,
  );

  static const TextStyle profileName = TextStyle(
    fontFamily: 'SF Mono',
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AurexisColors.textPrimary,
  );

  static const TextStyle badge = TextStyle(
    fontFamily: 'SF Mono',
    fontSize: 8,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );
}

class AurexisDimens {
  AurexisDimens._();

  static const double panelWidth = 280.0;
  static const double sectionPadding = 8.0;
  static const double sliderHeight = 18.0;
  static const double sectionHeaderHeight = 28.0;
  static const double paramRowHeight = 22.0;
  static const double sectionGap = 2.0;
  static const double borderRadius = 4.0;
}
