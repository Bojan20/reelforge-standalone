/// Video Processor FX Service — Built-in Video Processing Effects
///
/// #31: Video processor with text overlay, audio-reactive visuals,
/// FFT frequency display, and compositing effects.
///
/// Features:
/// - Text overlay with positioning, font, color, animation
/// - Audio-reactive visual effects (bars, waveform, particles)
/// - FFT frequency spectrum display
/// - Color correction (brightness, contrast, saturation, hue)
/// - Blend modes and opacity control
/// - Effect chain with enable/disable per effect
/// - Preset management with factory presets
/// - JSON serialization for persistence
library;

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// EFFECT TYPES & ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

/// Types of video processor effects
enum VideoEffectType {
  textOverlay,
  audioReactive,
  fftSpectrum,
  colorCorrection,
}

/// Audio-reactive visualization styles
enum ReactiveStyle {
  bars,
  waveform,
  particles,
  circle,
  ring,
}

extension ReactiveStyleX on ReactiveStyle {
  String get label => switch (this) {
    ReactiveStyle.bars => 'Bars',
    ReactiveStyle.waveform => 'Waveform',
    ReactiveStyle.particles => 'Particles',
    ReactiveStyle.circle => 'Circle',
    ReactiveStyle.ring => 'Ring',
  };
}

/// FFT display modes
enum FftDisplayMode {
  linear,
  logarithmic,
  octave,
  thirdOctave,
}

extension FftDisplayModeX on FftDisplayMode {
  String get label => switch (this) {
    FftDisplayMode.linear => 'Linear',
    FftDisplayMode.logarithmic => 'Logarithmic',
    FftDisplayMode.octave => 'Octave',
    FftDisplayMode.thirdOctave => '1/3 Octave',
  };
}

/// Text alignment for overlay
enum TextPosition {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

extension TextPositionX on TextPosition {
  String get label => switch (this) {
    TextPosition.topLeft => 'Top Left',
    TextPosition.topCenter => 'Top Center',
    TextPosition.topRight => 'Top Right',
    TextPosition.centerLeft => 'Center Left',
    TextPosition.center => 'Center',
    TextPosition.centerRight => 'Center Right',
    TextPosition.bottomLeft => 'Bottom Left',
    TextPosition.bottomCenter => 'Bottom Center',
    TextPosition.bottomRight => 'Bottom Right',
  };
}

/// Blend modes for compositing
enum VideoBlendMode {
  normal,
  multiply,
  screen,
  overlay,
  additive,
}

extension VideoBlendModeX on VideoBlendMode {
  String get label => switch (this) {
    VideoBlendMode.normal => 'Normal',
    VideoBlendMode.multiply => 'Multiply',
    VideoBlendMode.screen => 'Screen',
    VideoBlendMode.overlay => 'Overlay',
    VideoBlendMode.additive => 'Additive',
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// VIDEO EFFECT — Base model for all effects
// ═══════════════════════════════════════════════════════════════════════════════

/// A single video processor effect in the chain
class VideoEffect {
  final String id;
  String name;
  VideoEffectType type;
  bool enabled;
  double opacity; // 0.0 to 1.0
  VideoBlendMode blendMode;

  // ── Text Overlay params ──
  String overlayText;
  TextPosition textPosition;
  double fontSize; // 12 to 200
  int textColorValue; // ARGB as int
  int bgColorValue;   // ARGB as int (background box)
  bool textBold;
  bool textItalic;
  bool textShadow;
  double textOffsetX; // -1.0 to 1.0 (relative)
  double textOffsetY; // -1.0 to 1.0 (relative)

  // ── Audio-Reactive params ──
  ReactiveStyle reactiveStyle;
  double reactiveIntensity; // 0.0 to 1.0
  double reactiveSmoothing; // 0.0 to 1.0
  int reactiveColorValue;
  int reactiveColor2Value; // gradient second color
  double reactiveScale;    // 0.1 to 3.0
  bool reactiveFlipY;

  // ── FFT Spectrum params ──
  FftDisplayMode fftMode;
  int fftSize; // 256, 512, 1024, 2048, 4096
  double fftFloor;   // -120 to 0 dB
  double fftCeiling;  // -60 to 0 dB
  int fftColorValue;
  double fftBarWidth; // 1 to 20
  bool fftFilled;
  bool fftMirror;

  // ── Color Correction params ──
  double brightness;  // -1.0 to 1.0
  double contrast;    // -1.0 to 1.0
  double saturation;  // -1.0 to 1.0
  double hueShift;    // -180 to 180
  double gamma;       // 0.1 to 3.0

  VideoEffect({
    required this.id,
    required this.name,
    required this.type,
    this.enabled = true,
    this.opacity = 1.0,
    this.blendMode = VideoBlendMode.normal,
    // Text
    this.overlayText = 'Text',
    this.textPosition = TextPosition.bottomCenter,
    this.fontSize = 32,
    this.textColorValue = 0xFFFFFFFF,
    this.bgColorValue = 0x80000000,
    this.textBold = false,
    this.textItalic = false,
    this.textShadow = true,
    this.textOffsetX = 0,
    this.textOffsetY = 0,
    // Audio-Reactive
    this.reactiveStyle = ReactiveStyle.bars,
    this.reactiveIntensity = 0.7,
    this.reactiveSmoothing = 0.3,
    this.reactiveColorValue = 0xFF00CCFF,
    this.reactiveColor2Value = 0xFFFF6600,
    this.reactiveScale = 1.0,
    this.reactiveFlipY = false,
    // FFT
    this.fftMode = FftDisplayMode.logarithmic,
    this.fftSize = 2048,
    this.fftFloor = -90,
    this.fftCeiling = -6,
    this.fftColorValue = 0xFF00FF88,
    this.fftBarWidth = 3,
    this.fftFilled = true,
    this.fftMirror = false,
    // Color Correction
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.hueShift = 0,
    this.gamma = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'enabled': enabled,
    'opacity': opacity,
    'blendMode': blendMode.name,
    'overlayText': overlayText,
    'textPosition': textPosition.name,
    'fontSize': fontSize,
    'textColorValue': textColorValue,
    'bgColorValue': bgColorValue,
    'textBold': textBold,
    'textItalic': textItalic,
    'textShadow': textShadow,
    'textOffsetX': textOffsetX,
    'textOffsetY': textOffsetY,
    'reactiveStyle': reactiveStyle.name,
    'reactiveIntensity': reactiveIntensity,
    'reactiveSmoothing': reactiveSmoothing,
    'reactiveColorValue': reactiveColorValue,
    'reactiveColor2Value': reactiveColor2Value,
    'reactiveScale': reactiveScale,
    'reactiveFlipY': reactiveFlipY,
    'fftMode': fftMode.name,
    'fftSize': fftSize,
    'fftFloor': fftFloor,
    'fftCeiling': fftCeiling,
    'fftColorValue': fftColorValue,
    'fftBarWidth': fftBarWidth,
    'fftFilled': fftFilled,
    'fftMirror': fftMirror,
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
    'hueShift': hueShift,
    'gamma': gamma,
  };

  factory VideoEffect.fromJson(Map<String, dynamic> json) => VideoEffect(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    type: VideoEffectType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => VideoEffectType.textOverlay,
    ),
    enabled: json['enabled'] as bool? ?? true,
    opacity: (json['opacity'] as num? ?? 1.0).toDouble().clamp(0.0, 1.0),
    blendMode: VideoBlendMode.values.firstWhere(
      (b) => b.name == json['blendMode'],
      orElse: () => VideoBlendMode.normal,
    ),
    overlayText: json['overlayText'] as String? ?? 'Text',
    textPosition: TextPosition.values.firstWhere(
      (p) => p.name == json['textPosition'],
      orElse: () => TextPosition.bottomCenter,
    ),
    fontSize: (json['fontSize'] as num? ?? 32).toDouble().clamp(12, 200),
    textColorValue: json['textColorValue'] as int? ?? 0xFFFFFFFF,
    bgColorValue: json['bgColorValue'] as int? ?? 0x80000000,
    textBold: json['textBold'] as bool? ?? false,
    textItalic: json['textItalic'] as bool? ?? false,
    textShadow: json['textShadow'] as bool? ?? true,
    textOffsetX: (json['textOffsetX'] as num? ?? 0).toDouble().clamp(-1.0, 1.0),
    textOffsetY: (json['textOffsetY'] as num? ?? 0).toDouble().clamp(-1.0, 1.0),
    reactiveStyle: ReactiveStyle.values.firstWhere(
      (s) => s.name == json['reactiveStyle'],
      orElse: () => ReactiveStyle.bars,
    ),
    reactiveIntensity: (json['reactiveIntensity'] as num? ?? 0.7).toDouble().clamp(0.0, 1.0),
    reactiveSmoothing: (json['reactiveSmoothing'] as num? ?? 0.3).toDouble().clamp(0.0, 1.0),
    reactiveColorValue: json['reactiveColorValue'] as int? ?? 0xFF00CCFF,
    reactiveColor2Value: json['reactiveColor2Value'] as int? ?? 0xFFFF6600,
    reactiveScale: (json['reactiveScale'] as num? ?? 1.0).toDouble().clamp(0.1, 3.0),
    reactiveFlipY: json['reactiveFlipY'] as bool? ?? false,
    fftMode: FftDisplayMode.values.firstWhere(
      (m) => m.name == json['fftMode'],
      orElse: () => FftDisplayMode.logarithmic,
    ),
    fftSize: const [256, 512, 1024, 2048, 4096].contains(json['fftSize'] as int? ?? 2048)
        ? json['fftSize'] as int
        : 2048,
    fftFloor: (json['fftFloor'] as num? ?? -90).toDouble().clamp(-120, 0),
    fftCeiling: (json['fftCeiling'] as num? ?? -6).toDouble().clamp(-60, 0),
    fftColorValue: json['fftColorValue'] as int? ?? 0xFF00FF88,
    fftBarWidth: (json['fftBarWidth'] as num? ?? 3).toDouble().clamp(1, 20),
    fftFilled: json['fftFilled'] as bool? ?? true,
    fftMirror: json['fftMirror'] as bool? ?? false,
    brightness: (json['brightness'] as num? ?? 0).toDouble().clamp(-1.0, 1.0),
    contrast: (json['contrast'] as num? ?? 0).toDouble().clamp(-1.0, 1.0),
    saturation: (json['saturation'] as num? ?? 0).toDouble().clamp(-1.0, 1.0),
    hueShift: (json['hueShift'] as num? ?? 0).toDouble().clamp(-180, 180),
    gamma: (json['gamma'] as num? ?? 1.0).toDouble().clamp(0.1, 3.0),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// VIDEO PROCESSOR PRESET
// ═══════════════════════════════════════════════════════════════════════════════

/// A saved preset containing a full effect chain
class VideoProcessorPreset {
  final String id;
  String name;
  final List<VideoEffect> effects;
  final bool isFactory;

  VideoProcessorPreset({
    required this.id,
    required this.name,
    required this.effects,
    this.isFactory = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'effects': effects.map((e) => e.toJson()).toList(),
    'isFactory': isFactory,
  };

  factory VideoProcessorPreset.fromJson(Map<String, dynamic> json) =>
      VideoProcessorPreset(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        effects: (json['effects'] as List<dynamic>?)
                ?.map((e) => VideoEffect.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        isFactory: json['isFactory'] as bool? ?? false,
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// VIDEO PROCESSOR SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service for managing video processor effects chain
class VideoProcessorService extends ChangeNotifier {
  VideoProcessorService._();
  static final VideoProcessorService instance = VideoProcessorService._();

  /// Effect chain (ordered)
  final List<VideoEffect> _effects = [];

  /// Saved presets
  final Map<String, VideoProcessorPreset> _presets = {};

  /// Currently selected effect index
  int _selectedIndex = -1;

  /// Whether the processor is active (processing video)
  bool _active = false;

  /// Callback for when effects change (notify render engine)
  void Function(String effectId, String param)? onEffectChanged;

  /// Callback for active state changes
  void Function(bool active)? onActiveChanged;

  // Getters
  List<VideoEffect> get effects => List.unmodifiable(_effects);
  int get effectCount => _effects.length;
  int get selectedIndex => _selectedIndex;
  VideoEffect? get selectedEffect =>
      _selectedIndex >= 0 && _selectedIndex < _effects.length
          ? _effects[_selectedIndex]
          : null;
  bool get active => _active;
  int get enabledCount => _effects.where((e) => e.enabled).length;
  List<VideoProcessorPreset> get presets => _presets.values.toList();
  List<VideoProcessorPreset> get factoryPresets =>
      _presets.values.where((p) => p.isFactory).toList();
  List<VideoProcessorPreset> get userPresets =>
      _presets.values.where((p) => !p.isFactory).toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // EFFECT CHAIN MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a new effect to the chain
  VideoEffect addEffect(VideoEffectType type, {String? name}) {
    final id = 'vfx_${DateTime.now().millisecondsSinceEpoch}';
    final effectName = name ?? switch (type) {
      VideoEffectType.textOverlay => 'Text Overlay',
      VideoEffectType.audioReactive => 'Audio Reactive',
      VideoEffectType.fftSpectrum => 'FFT Spectrum',
      VideoEffectType.colorCorrection => 'Color Correction',
    };
    final effect = VideoEffect(id: id, name: effectName, type: type);
    _effects.add(effect);
    _selectedIndex = _effects.length - 1;
    onEffectChanged?.call(id, 'add');
    notifyListeners();
    return effect;
  }

  /// Remove an effect from the chain
  void removeEffect(String id) {
    final index = _effects.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _effects.removeAt(index);
    if (_selectedIndex >= _effects.length) {
      _selectedIndex = _effects.length - 1;
    }
    onEffectChanged?.call(id, 'remove');
    notifyListeners();
  }

  /// Move an effect in the chain
  void moveEffect(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= _effects.length) return;
    if (toIndex < 0 || toIndex >= _effects.length) return;
    if (fromIndex == toIndex) return;
    final effect = _effects.removeAt(fromIndex);
    _effects.insert(toIndex, effect);
    _selectedIndex = toIndex;
    onEffectChanged?.call(effect.id, 'move');
    notifyListeners();
  }

  /// Duplicate an effect
  void duplicateEffect(String id) {
    final source = _findEffect(id);
    if (source == null) return;
    final newId = 'vfx_${DateTime.now().millisecondsSinceEpoch}';
    final copy = VideoEffect.fromJson(source.toJson());
    // Override id and name
    final duplicate = VideoEffect(
      id: newId,
      name: '${source.name} (copy)',
      type: copy.type,
      enabled: copy.enabled,
      opacity: copy.opacity,
      blendMode: copy.blendMode,
      overlayText: copy.overlayText,
      textPosition: copy.textPosition,
      fontSize: copy.fontSize,
      textColorValue: copy.textColorValue,
      bgColorValue: copy.bgColorValue,
      textBold: copy.textBold,
      textItalic: copy.textItalic,
      textShadow: copy.textShadow,
      textOffsetX: copy.textOffsetX,
      textOffsetY: copy.textOffsetY,
      reactiveStyle: copy.reactiveStyle,
      reactiveIntensity: copy.reactiveIntensity,
      reactiveSmoothing: copy.reactiveSmoothing,
      reactiveColorValue: copy.reactiveColorValue,
      reactiveColor2Value: copy.reactiveColor2Value,
      reactiveScale: copy.reactiveScale,
      reactiveFlipY: copy.reactiveFlipY,
      fftMode: copy.fftMode,
      fftSize: copy.fftSize,
      fftFloor: copy.fftFloor,
      fftCeiling: copy.fftCeiling,
      fftColorValue: copy.fftColorValue,
      fftBarWidth: copy.fftBarWidth,
      fftFilled: copy.fftFilled,
      fftMirror: copy.fftMirror,
      brightness: copy.brightness,
      contrast: copy.contrast,
      saturation: copy.saturation,
      hueShift: copy.hueShift,
      gamma: copy.gamma,
    );
    final index = _effects.indexWhere((e) => e.id == id);
    _effects.insert(index + 1, duplicate);
    _selectedIndex = index + 1;
    onEffectChanged?.call(newId, 'add');
    notifyListeners();
  }

  /// Select an effect by index
  void selectEffect(int index) {
    if (index < -1 || index >= _effects.length) return;
    _selectedIndex = index;
    notifyListeners();
  }

  /// Toggle effect enabled state
  void toggleEffect(String id) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.enabled = !effect.enabled;
    onEffectChanged?.call(id, 'enabled');
    notifyListeners();
  }

  /// Toggle processor active state
  void toggleActive() {
    _active = !_active;
    onActiveChanged?.call(_active);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PARAMETER SETTERS — Text Overlay
  // ═══════════════════════════════════════════════════════════════════════════

  void setOverlayText(String id, String text) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.overlayText = text;
    onEffectChanged?.call(id, 'overlayText');
    notifyListeners();
  }

  void setTextPosition(String id, TextPosition pos) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.textPosition = pos;
    onEffectChanged?.call(id, 'textPosition');
    notifyListeners();
  }

  void setFontSize(String id, double size) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.fontSize = size.clamp(12, 200);
    onEffectChanged?.call(id, 'fontSize');
    notifyListeners();
  }

  void setTextColor(String id, int colorValue) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.textColorValue = colorValue;
    onEffectChanged?.call(id, 'textColor');
    notifyListeners();
  }

  void setTextBgColor(String id, int colorValue) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.bgColorValue = colorValue;
    onEffectChanged?.call(id, 'bgColor');
    notifyListeners();
  }

  void setTextStyle(String id, {bool? bold, bool? italic, bool? shadow}) {
    final effect = _findEffect(id);
    if (effect == null) return;
    if (bold != null) effect.textBold = bold;
    if (italic != null) effect.textItalic = italic;
    if (shadow != null) effect.textShadow = shadow;
    onEffectChanged?.call(id, 'textStyle');
    notifyListeners();
  }

  void setTextOffset(String id, double x, double y) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.textOffsetX = x.clamp(-1.0, 1.0);
    effect.textOffsetY = y.clamp(-1.0, 1.0);
    onEffectChanged?.call(id, 'textOffset');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PARAMETER SETTERS — Audio-Reactive
  // ═══════════════════════════════════════════════════════════════════════════

  void setReactiveStyle(String id, ReactiveStyle style) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.reactiveStyle = style;
    onEffectChanged?.call(id, 'reactiveStyle');
    notifyListeners();
  }

  void setReactiveIntensity(String id, double intensity) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.reactiveIntensity = intensity.clamp(0.0, 1.0);
    onEffectChanged?.call(id, 'reactiveIntensity');
    notifyListeners();
  }

  void setReactiveSmoothing(String id, double smoothing) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.reactiveSmoothing = smoothing.clamp(0.0, 1.0);
    onEffectChanged?.call(id, 'reactiveSmoothing');
    notifyListeners();
  }

  void setReactiveColor(String id, int colorValue) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.reactiveColorValue = colorValue;
    onEffectChanged?.call(id, 'reactiveColor');
    notifyListeners();
  }

  void setReactiveColor2(String id, int colorValue) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.reactiveColor2Value = colorValue;
    onEffectChanged?.call(id, 'reactiveColor2');
    notifyListeners();
  }

  void setReactiveScale(String id, double scale) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.reactiveScale = scale.clamp(0.1, 3.0);
    onEffectChanged?.call(id, 'reactiveScale');
    notifyListeners();
  }

  void setReactiveFlipY(String id, bool flip) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.reactiveFlipY = flip;
    onEffectChanged?.call(id, 'reactiveFlipY');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PARAMETER SETTERS — FFT Spectrum
  // ═══════════════════════════════════════════════════════════════════════════

  void setFftMode(String id, FftDisplayMode mode) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.fftMode = mode;
    onEffectChanged?.call(id, 'fftMode');
    notifyListeners();
  }

  void setFftSize(String id, int size) {
    final effect = _findEffect(id);
    if (effect == null) return;
    // Only valid power-of-2 sizes
    final valid = [256, 512, 1024, 2048, 4096];
    effect.fftSize = valid.contains(size) ? size : 2048;
    onEffectChanged?.call(id, 'fftSize');
    notifyListeners();
  }

  void setFftRange(String id, double floor, double ceiling) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.fftFloor = floor.clamp(-120, 0);
    effect.fftCeiling = ceiling.clamp(-60, 0);
    onEffectChanged?.call(id, 'fftRange');
    notifyListeners();
  }

  void setFftColor(String id, int colorValue) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.fftColorValue = colorValue;
    onEffectChanged?.call(id, 'fftColor');
    notifyListeners();
  }

  void setFftBarWidth(String id, double width) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.fftBarWidth = width.clamp(1, 20);
    onEffectChanged?.call(id, 'fftBarWidth');
    notifyListeners();
  }

  void setFftFilled(String id, bool filled) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.fftFilled = filled;
    onEffectChanged?.call(id, 'fftFilled');
    notifyListeners();
  }

  void setFftMirror(String id, bool mirror) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.fftMirror = mirror;
    onEffectChanged?.call(id, 'fftMirror');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PARAMETER SETTERS — Color Correction
  // ═══════════════════════════════════════════════════════════════════════════

  void setBrightness(String id, double value) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.brightness = value.clamp(-1.0, 1.0);
    onEffectChanged?.call(id, 'brightness');
    notifyListeners();
  }

  void setContrast(String id, double value) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.contrast = value.clamp(-1.0, 1.0);
    onEffectChanged?.call(id, 'contrast');
    notifyListeners();
  }

  void setSaturation(String id, double value) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.saturation = value.clamp(-1.0, 1.0);
    onEffectChanged?.call(id, 'saturation');
    notifyListeners();
  }

  void setHueShift(String id, double value) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.hueShift = value.clamp(-180, 180);
    onEffectChanged?.call(id, 'hueShift');
    notifyListeners();
  }

  void setGamma(String id, double value) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.gamma = value.clamp(0.1, 3.0);
    onEffectChanged?.call(id, 'gamma');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMMON PARAMETER SETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  void setEffectOpacity(String id, double opacity) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.opacity = opacity.clamp(0.0, 1.0);
    onEffectChanged?.call(id, 'opacity');
    notifyListeners();
  }

  void setEffectBlendMode(String id, VideoBlendMode mode) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.blendMode = mode;
    onEffectChanged?.call(id, 'blendMode');
    notifyListeners();
  }

  void renameEffect(String id, String newName) {
    final effect = _findEffect(id);
    if (effect == null) return;
    effect.name = newName;
    onEffectChanged?.call(id, 'name');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRESET MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load factory presets (addIfAbsent)
  void loadFactoryPresets() {
    void addIfAbsent(VideoProcessorPreset preset) {
      if (!_presets.containsKey(preset.id)) {
        _presets[preset.id] = preset;
      }
    }

    addIfAbsent(_presetLowerThird());
    addIfAbsent(_presetAudioVisualizer());
    addIfAbsent(_presetSpectrumAnalyzer());
    addIfAbsent(_presetCinematicLook());
    notifyListeners();
  }

  /// Save current effect chain as a preset
  void savePreset(String name) {
    final id = 'preset_${DateTime.now().millisecondsSinceEpoch}';
    final preset = VideoProcessorPreset(
      id: id,
      name: name,
      effects: _effects.map((e) => VideoEffect.fromJson(e.toJson())).toList(),
    );
    _presets[id] = preset;
    notifyListeners();
  }

  /// Load a preset (replaces current chain)
  void loadPreset(String presetId) {
    final preset = _presets[presetId];
    if (preset == null) return;
    _effects.clear();
    for (final e in preset.effects) {
      _effects.add(VideoEffect.fromJson(e.toJson()));
    }
    _selectedIndex = _effects.isEmpty ? -1 : 0;
    notifyListeners();
  }

  /// Remove a preset
  void removePreset(String presetId) {
    final preset = _presets[presetId];
    if (preset == null || preset.isFactory) return;
    _presets.remove(presetId);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FACTORY PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  VideoProcessorPreset _presetLowerThird() => VideoProcessorPreset(
    id: 'factory_lower_third',
    name: 'Lower Third Title',
    isFactory: true,
    effects: [
      VideoEffect(
        id: 'lt_text',
        name: 'Title Text',
        type: VideoEffectType.textOverlay,
        overlayText: 'TITLE',
        textPosition: TextPosition.bottomLeft,
        fontSize: 36,
        textBold: true,
        textShadow: true,
        textOffsetX: 0.05,
        textOffsetY: -0.1,
      ),
    ],
  );

  VideoProcessorPreset _presetAudioVisualizer() => VideoProcessorPreset(
    id: 'factory_audio_viz',
    name: 'Audio Visualizer',
    isFactory: true,
    effects: [
      VideoEffect(
        id: 'av_reactive',
        name: 'Audio Bars',
        type: VideoEffectType.audioReactive,
        reactiveStyle: ReactiveStyle.bars,
        reactiveIntensity: 0.8,
        reactiveSmoothing: 0.4,
        blendMode: VideoBlendMode.additive,
      ),
      VideoEffect(
        id: 'av_color',
        name: 'Color Grade',
        type: VideoEffectType.colorCorrection,
        contrast: 0.2,
        saturation: 0.3,
      ),
    ],
  );

  VideoProcessorPreset _presetSpectrumAnalyzer() => VideoProcessorPreset(
    id: 'factory_spectrum',
    name: 'Spectrum Analyzer',
    isFactory: true,
    effects: [
      VideoEffect(
        id: 'sa_fft',
        name: 'FFT Display',
        type: VideoEffectType.fftSpectrum,
        fftMode: FftDisplayMode.logarithmic,
        fftSize: 4096,
        fftFilled: true,
        fftMirror: true,
        fftBarWidth: 2,
      ),
    ],
  );

  VideoProcessorPreset _presetCinematicLook() => VideoProcessorPreset(
    id: 'factory_cinematic',
    name: 'Cinematic Look',
    isFactory: true,
    effects: [
      VideoEffect(
        id: 'cin_color',
        name: 'Cinematic Grade',
        type: VideoEffectType.colorCorrection,
        brightness: -0.05,
        contrast: 0.25,
        saturation: -0.15,
        gamma: 1.1,
      ),
      VideoEffect(
        id: 'cin_text',
        name: 'Watermark',
        type: VideoEffectType.textOverlay,
        overlayText: 'PREVIEW',
        textPosition: TextPosition.topRight,
        fontSize: 16,
        textColorValue: 0x60FFFFFF,
        bgColorValue: 0x00000000,
        opacity: 0.5,
      ),
    ],
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
    'effects': _effects.map((e) => e.toJson()).toList(),
    'selectedIndex': _selectedIndex,
    'active': _active,
    'presets': _presets.values
        .where((p) => !p.isFactory)
        .map((p) => p.toJson())
        .toList(),
  };

  void fromJson(Map<String, dynamic> json) {
    _effects.clear();
    _presets.clear();
    _active = json['active'] as bool? ?? false;
    _selectedIndex = json['selectedIndex'] as int? ?? -1;

    final effectList = json['effects'] as List<dynamic>?;
    if (effectList != null) {
      for (final item in effectList) {
        _effects.add(VideoEffect.fromJson(item as Map<String, dynamic>));
      }
    }

    final presetList = json['presets'] as List<dynamic>?;
    if (presetList != null) {
      for (final item in presetList) {
        final preset = VideoProcessorPreset.fromJson(item as Map<String, dynamic>);
        _presets[preset.id] = preset;
      }
    }

    // Always load factory presets
    loadFactoryPresets();

    if (_selectedIndex >= _effects.length) {
      _selectedIndex = _effects.isEmpty ? -1 : 0;
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  VideoEffect? _findEffect(String id) {
    final idx = _effects.indexWhere((e) => e.id == id);
    return idx >= 0 ? _effects[idx] : null;
  }
}
