/// Branding Models
///
/// Data models for SlotLab branding customization:
/// - Custom logos and icons
/// - Color themes
/// - Font configurations
/// - Display text customization
///
/// Created: 2026-01-30 (P4.18)

import 'dart:convert';
import 'dart:ui' show Color;

// ═══════════════════════════════════════════════════════════════════════════
// BRANDING COLORS
// ═══════════════════════════════════════════════════════════════════════════

/// Color scheme for branding
class BrandingColors {
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color text;
  final Color textSecondary;
  final Color success;
  final Color warning;
  final Color error;

  const BrandingColors({
    this.primary = const Color(0xFF4A9EFF),
    this.secondary = const Color(0xFF40FF90),
    this.accent = const Color(0xFFFFD700),
    this.background = const Color(0xFF0A0A0C),
    this.surface = const Color(0xFF1A1A20),
    this.text = const Color(0xFFFFFFFF),
    this.textSecondary = const Color(0xFFB0B0B0),
    this.success = const Color(0xFF40FF90),
    this.warning = const Color(0xFFFFD700),
    this.error = const Color(0xFFFF4060),
  });

  BrandingColors copyWith({
    Color? primary,
    Color? secondary,
    Color? accent,
    Color? background,
    Color? surface,
    Color? text,
    Color? textSecondary,
    Color? success,
    Color? warning,
    Color? error,
  }) {
    return BrandingColors(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      accent: accent ?? this.accent,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'primary': primary.value,
      'secondary': secondary.value,
      'accent': accent.value,
      'background': background.value,
      'surface': surface.value,
      'text': text.value,
      'textSecondary': textSecondary.value,
      'success': success.value,
      'warning': warning.value,
      'error': error.value,
    };
  }

  factory BrandingColors.fromJson(Map<String, dynamic> json) {
    return BrandingColors(
      primary: Color(json['primary'] as int? ?? 0xFF4A9EFF),
      secondary: Color(json['secondary'] as int? ?? 0xFF40FF90),
      accent: Color(json['accent'] as int? ?? 0xFFFFD700),
      background: Color(json['background'] as int? ?? 0xFF0A0A0C),
      surface: Color(json['surface'] as int? ?? 0xFF1A1A20),
      text: Color(json['text'] as int? ?? 0xFFFFFFFF),
      textSecondary: Color(json['textSecondary'] as int? ?? 0xFFB0B0B0),
      success: Color(json['success'] as int? ?? 0xFF40FF90),
      warning: Color(json['warning'] as int? ?? 0xFFFFD700),
      error: Color(json['error'] as int? ?? 0xFFFF4060),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BRANDING FONTS
// ═══════════════════════════════════════════════════════════════════════════

/// Font configuration for branding
class BrandingFonts {
  final String titleFont;
  final String bodyFont;
  final String monoFont;
  final double titleSize;
  final double bodySize;
  final double smallSize;

  const BrandingFonts({
    this.titleFont = 'Roboto',
    this.bodyFont = 'Roboto',
    this.monoFont = 'Roboto Mono',
    this.titleSize = 24.0,
    this.bodySize = 14.0,
    this.smallSize = 12.0,
  });

  BrandingFonts copyWith({
    String? titleFont,
    String? bodyFont,
    String? monoFont,
    double? titleSize,
    double? bodySize,
    double? smallSize,
  }) {
    return BrandingFonts(
      titleFont: titleFont ?? this.titleFont,
      bodyFont: bodyFont ?? this.bodyFont,
      monoFont: monoFont ?? this.monoFont,
      titleSize: titleSize ?? this.titleSize,
      bodySize: bodySize ?? this.bodySize,
      smallSize: smallSize ?? this.smallSize,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'titleFont': titleFont,
      'bodyFont': bodyFont,
      'monoFont': monoFont,
      'titleSize': titleSize,
      'bodySize': bodySize,
      'smallSize': smallSize,
    };
  }

  factory BrandingFonts.fromJson(Map<String, dynamic> json) {
    return BrandingFonts(
      titleFont: json['titleFont'] as String? ?? 'Roboto',
      bodyFont: json['bodyFont'] as String? ?? 'Roboto',
      monoFont: json['monoFont'] as String? ?? 'Roboto Mono',
      titleSize: (json['titleSize'] as num?)?.toDouble() ?? 24.0,
      bodySize: (json['bodySize'] as num?)?.toDouble() ?? 14.0,
      smallSize: (json['smallSize'] as num?)?.toDouble() ?? 12.0,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BRANDING ASSETS
// ═══════════════════════════════════════════════════════════════════════════

/// Asset paths for branding
class BrandingAssets {
  final String? logoPath;
  final String? iconPath;
  final String? splashPath;
  final String? backgroundPath;
  final String? watermarkPath;

  const BrandingAssets({
    this.logoPath,
    this.iconPath,
    this.splashPath,
    this.backgroundPath,
    this.watermarkPath,
  });

  bool get hasLogo => logoPath != null && logoPath!.isNotEmpty;
  bool get hasIcon => iconPath != null && iconPath!.isNotEmpty;
  bool get hasSplash => splashPath != null && splashPath!.isNotEmpty;
  bool get hasBackground => backgroundPath != null && backgroundPath!.isNotEmpty;
  bool get hasWatermark => watermarkPath != null && watermarkPath!.isNotEmpty;

  BrandingAssets copyWith({
    String? logoPath,
    String? iconPath,
    String? splashPath,
    String? backgroundPath,
    String? watermarkPath,
  }) {
    return BrandingAssets(
      logoPath: logoPath ?? this.logoPath,
      iconPath: iconPath ?? this.iconPath,
      splashPath: splashPath ?? this.splashPath,
      backgroundPath: backgroundPath ?? this.backgroundPath,
      watermarkPath: watermarkPath ?? this.watermarkPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'logoPath': logoPath,
      'iconPath': iconPath,
      'splashPath': splashPath,
      'backgroundPath': backgroundPath,
      'watermarkPath': watermarkPath,
    };
  }

  factory BrandingAssets.fromJson(Map<String, dynamic> json) {
    return BrandingAssets(
      logoPath: json['logoPath'] as String?,
      iconPath: json['iconPath'] as String?,
      splashPath: json['splashPath'] as String?,
      backgroundPath: json['backgroundPath'] as String?,
      watermarkPath: json['watermarkPath'] as String?,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BRANDING TEXT
// ═══════════════════════════════════════════════════════════════════════════

/// Custom text labels for branding
class BrandingText {
  final String appName;
  final String companyName;
  final String copyright;
  final String slogan;
  final String spinButtonLabel;
  final String autoSpinLabel;
  final String turboLabel;
  final String balanceLabel;
  final String betLabel;
  final String winLabel;

  const BrandingText({
    this.appName = 'FluxForge Studio',
    this.companyName = 'Your Company',
    this.copyright = '© 2026 Your Company. All rights reserved.',
    this.slogan = 'Professional Slot Audio',
    this.spinButtonLabel = 'SPIN',
    this.autoSpinLabel = 'AUTO',
    this.turboLabel = 'TURBO',
    this.balanceLabel = 'BALANCE',
    this.betLabel = 'BET',
    this.winLabel = 'WIN',
  });

  BrandingText copyWith({
    String? appName,
    String? companyName,
    String? copyright,
    String? slogan,
    String? spinButtonLabel,
    String? autoSpinLabel,
    String? turboLabel,
    String? balanceLabel,
    String? betLabel,
    String? winLabel,
  }) {
    return BrandingText(
      appName: appName ?? this.appName,
      companyName: companyName ?? this.companyName,
      copyright: copyright ?? this.copyright,
      slogan: slogan ?? this.slogan,
      spinButtonLabel: spinButtonLabel ?? this.spinButtonLabel,
      autoSpinLabel: autoSpinLabel ?? this.autoSpinLabel,
      turboLabel: turboLabel ?? this.turboLabel,
      balanceLabel: balanceLabel ?? this.balanceLabel,
      betLabel: betLabel ?? this.betLabel,
      winLabel: winLabel ?? this.winLabel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'appName': appName,
      'companyName': companyName,
      'copyright': copyright,
      'slogan': slogan,
      'spinButtonLabel': spinButtonLabel,
      'autoSpinLabel': autoSpinLabel,
      'turboLabel': turboLabel,
      'balanceLabel': balanceLabel,
      'betLabel': betLabel,
      'winLabel': winLabel,
    };
  }

  factory BrandingText.fromJson(Map<String, dynamic> json) {
    return BrandingText(
      appName: json['appName'] as String? ?? 'FluxForge Studio',
      companyName: json['companyName'] as String? ?? 'Your Company',
      copyright: json['copyright'] as String? ?? '© 2026 Your Company. All rights reserved.',
      slogan: json['slogan'] as String? ?? 'Professional Slot Audio',
      spinButtonLabel: json['spinButtonLabel'] as String? ?? 'SPIN',
      autoSpinLabel: json['autoSpinLabel'] as String? ?? 'AUTO',
      turboLabel: json['turboLabel'] as String? ?? 'TURBO',
      balanceLabel: json['balanceLabel'] as String? ?? 'BALANCE',
      betLabel: json['betLabel'] as String? ?? 'BET',
      winLabel: json['winLabel'] as String? ?? 'WIN',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BRANDING CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/// Complete branding configuration
class BrandingConfig {
  final String id;
  final String name;
  final BrandingColors colors;
  final BrandingFonts fonts;
  final BrandingAssets assets;
  final BrandingText text;
  final bool showWatermark;
  final double watermarkOpacity;
  final DateTime createdAt;
  final DateTime updatedAt;

  BrandingConfig({
    required this.id,
    required this.name,
    BrandingColors? colors,
    BrandingFonts? fonts,
    BrandingAssets? assets,
    BrandingText? text,
    this.showWatermark = false,
    this.watermarkOpacity = 0.3,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : colors = colors ?? const BrandingColors(),
        fonts = fonts ?? const BrandingFonts(),
        assets = assets ?? const BrandingAssets(),
        text = text ?? const BrandingText(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  BrandingConfig copyWith({
    String? id,
    String? name,
    BrandingColors? colors,
    BrandingFonts? fonts,
    BrandingAssets? assets,
    BrandingText? text,
    bool? showWatermark,
    double? watermarkOpacity,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BrandingConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      colors: colors ?? this.colors,
      fonts: fonts ?? this.fonts,
      assets: assets ?? this.assets,
      text: text ?? this.text,
      showWatermark: showWatermark ?? this.showWatermark,
      watermarkOpacity: watermarkOpacity ?? this.watermarkOpacity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'colors': colors.toJson(),
      'fonts': fonts.toJson(),
      'assets': assets.toJson(),
      'text': text.toJson(),
      'showWatermark': showWatermark,
      'watermarkOpacity': watermarkOpacity,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory BrandingConfig.fromJson(Map<String, dynamic> json) {
    return BrandingConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed',
      colors: json['colors'] != null
          ? BrandingColors.fromJson(json['colors'] as Map<String, dynamic>)
          : null,
      fonts: json['fonts'] != null
          ? BrandingFonts.fromJson(json['fonts'] as Map<String, dynamic>)
          : null,
      assets: json['assets'] != null
          ? BrandingAssets.fromJson(json['assets'] as Map<String, dynamic>)
          : null,
      text: json['text'] != null
          ? BrandingText.fromJson(json['text'] as Map<String, dynamic>)
          : null,
      showWatermark: json['showWatermark'] as bool? ?? false,
      watermarkOpacity: (json['watermarkOpacity'] as num?)?.toDouble() ?? 0.3,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory BrandingConfig.fromJsonString(String jsonString) {
    return BrandingConfig.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BUILT-IN PRESETS
// ═══════════════════════════════════════════════════════════════════════════

/// Built-in branding presets
class BuiltInBrandingPresets {
  /// Default FluxForge theme
  static BrandingConfig fluxForgeDefault() {
    return BrandingConfig(
      id: 'fluxforge_default',
      name: 'FluxForge Default',
      colors: const BrandingColors(),
      fonts: const BrandingFonts(),
      text: const BrandingText(),
    );
  }

  /// Dark gold casino theme
  static BrandingConfig darkGoldCasino() {
    return BrandingConfig(
      id: 'dark_gold_casino',
      name: 'Dark Gold Casino',
      colors: const BrandingColors(
        primary: Color(0xFFFFD700),
        secondary: Color(0xFFFFB300),
        accent: Color(0xFFFF6B35),
        background: Color(0xFF0D0D0D),
        surface: Color(0xFF1A1A1A),
      ),
      text: const BrandingText(
        appName: 'Golden Slots',
        slogan: 'Fortune Awaits',
      ),
    );
  }

  /// Neon Vegas theme
  static BrandingConfig neonVegas() {
    return BrandingConfig(
      id: 'neon_vegas',
      name: 'Neon Vegas',
      colors: const BrandingColors(
        primary: Color(0xFFFF00FF),
        secondary: Color(0xFF00FFFF),
        accent: Color(0xFFFF1493),
        background: Color(0xFF0A0014),
        surface: Color(0xFF1A0028),
      ),
      text: const BrandingText(
        appName: 'Vegas Nights',
        slogan: 'Light Up Your Wins',
      ),
    );
  }

  /// Classic red theme
  static BrandingConfig classicRed() {
    return BrandingConfig(
      id: 'classic_red',
      name: 'Classic Red',
      colors: const BrandingColors(
        primary: Color(0xFFDC143C),
        secondary: Color(0xFFB8860B),
        accent: Color(0xFFFFD700),
        background: Color(0xFF1A0A0A),
        surface: Color(0xFF2A1A1A),
      ),
      text: const BrandingText(
        appName: 'Royal Casino',
        slogan: 'Play Like Royalty',
      ),
    );
  }

  /// Ocean blue theme
  static BrandingConfig oceanBlue() {
    return BrandingConfig(
      id: 'ocean_blue',
      name: 'Ocean Blue',
      colors: const BrandingColors(
        primary: Color(0xFF0099CC),
        secondary: Color(0xFF00CC99),
        accent: Color(0xFF66CCFF),
        background: Color(0xFF0A1428),
        surface: Color(0xFF142438),
      ),
      text: const BrandingText(
        appName: 'Ocean Treasure',
        slogan: 'Dive Into Fortune',
      ),
    );
  }

  /// All built-in presets
  static List<BrandingConfig> all() {
    return [
      fluxForgeDefault(),
      darkGoldCasino(),
      neonVegas(),
      classicRed(),
      oceanBlue(),
    ];
  }
}
