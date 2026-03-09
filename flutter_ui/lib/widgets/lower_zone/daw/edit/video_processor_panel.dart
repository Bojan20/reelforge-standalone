/// Video Processor Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// #31: Built-in video processor with text overlay, audio-reactive
/// visuals, FFT frequency display, and color correction.
///
/// Features:
/// - Effect chain list with enable/disable and reorder
/// - Type-specific parameter editors
/// - Preview visualization
/// - Preset management
library;

import 'package:flutter/material.dart';
import '../../../../services/video_processor_service.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class VideoProcessorPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const VideoProcessorPanel({super.key, this.onAction});

  @override
  State<VideoProcessorPanel> createState() => _VideoProcessorPanelState();
}

class _VideoProcessorPanelState extends State<VideoProcessorPanel> {
  final _service = VideoProcessorService.instance;
  late TextEditingController _overlayTextCtrl;
  String? _lastSyncedEffectId;

  @override
  void initState() {
    super.initState();
    _overlayTextCtrl = TextEditingController();
    _service.addListener(_onChanged);
    _syncOverlayText();
  }

  @override
  void dispose() {
    _overlayTextCtrl.dispose();
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      _syncOverlayText();
      setState(() {});
    }
  }

  void _syncOverlayText() {
    final effect = _service.selectedEffect;
    if (effect != null && effect.type == VideoEffectType.textOverlay) {
      if (_lastSyncedEffectId != effect.id ||
          _overlayTextCtrl.text != effect.overlayText) {
        _lastSyncedEffectId = effect.id;
        if (_overlayTextCtrl.text != effect.overlayText) {
          _overlayTextCtrl.text = effect.overlayText;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 220, child: _buildEffectChain()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        Expanded(flex: 3, child: _buildParamEditor()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        SizedBox(width: 200, child: _buildPresetsPanel()),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LEFT: Effect Chain
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildEffectChain() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(children: [
            FabSectionLabel('FX CHAIN'),
            const Spacer(),
            _iconBtn(Icons.add, 'Add effect', () => _showAddMenu()),
            _iconBtn(
              _service.active ? Icons.power_settings_new : Icons.power_off,
              _service.active ? 'Deactivate' : 'Activate',
              () => _service.toggleActive(),
            ),
          ]),
        ),
        Expanded(
          child: _service.effects.isEmpty
              ? Center(child: Text(
                  'No effects.\n\nTap + to add a\nvideo effect.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary),
                ))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: _service.effects.length,
                  onReorder: (from, to) {
                    if (to > from) to--;
                    _service.moveEffect(from, to);
                  },
                  itemBuilder: (_, i) => _buildEffectItem(i, _service.effects[i]),
                ),
        ),
        // Status bar
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: FabFilterColors.border)),
          ),
          child: Row(children: [
            Text('Effects: ${_service.effectCount}', style: const TextStyle(
              fontSize: 9, color: FabFilterColors.textTertiary)),
            const Spacer(),
            Text(
              _service.active ? 'ACTIVE' : 'BYPASS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: _service.active
                    ? FabFilterColors.green : FabFilterColors.textDisabled,
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildEffectItem(int index, VideoEffect effect) {
    final selected = index == _service.selectedIndex;
    final typeIcon = switch (effect.type) {
      VideoEffectType.textOverlay => Icons.text_fields,
      VideoEffectType.audioReactive => Icons.equalizer,
      VideoEffectType.fftSpectrum => Icons.bar_chart,
      VideoEffectType.colorCorrection => Icons.palette,
    };

    return InkWell(
      key: ValueKey(effect.id),
      onTap: () => _service.selectEffect(index),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? FabFilterColors.cyan.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(color: FabFilterColors.cyan.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(children: [
          // Type icon
          Icon(typeIcon, size: 14,
            color: effect.enabled ? FabFilterColors.textSecondary : FabFilterColors.textDisabled),
          const SizedBox(width: 6),
          // Name + type
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(effect.name, style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: effect.enabled ? FabFilterColors.textPrimary : FabFilterColors.textDisabled,
              ), overflow: TextOverflow.ellipsis),
              Text(switch (effect.type) {
                  VideoEffectType.textOverlay => 'Text Overlay',
                  VideoEffectType.audioReactive => 'Audio Reactive',
                  VideoEffectType.fftSpectrum => 'FFT Spectrum',
                  VideoEffectType.colorCorrection => 'Color Correction',
                },
                style: const TextStyle(fontSize: 9, color: FabFilterColors.textTertiary)),
            ],
          )),
          // Enable toggle
          GestureDetector(
            onTap: () => _service.toggleEffect(effect.id),
            child: Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: effect.enabled
                    ? FabFilterColors.green.withValues(alpha: 0.3)
                    : FabFilterColors.bgMid,
                border: Border.all(
                  color: effect.enabled ? FabFilterColors.green : FabFilterColors.border),
              ),
              child: effect.enabled
                  ? const Icon(Icons.check, size: 10, color: FabFilterColors.green)
                  : null,
            ),
          ),
        ]),
      ),
    );
  }

  void _showAddMenu() {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);

    showMenu<VideoEffectType>(
      context: context,
      position: RelativeRect.fromLTRB(offset.dx + 180, offset.dy + 30, offset.dx + 400, 0),
      items: VideoEffectType.values.map((type) {
        final icon = switch (type) {
          VideoEffectType.textOverlay => Icons.text_fields,
          VideoEffectType.audioReactive => Icons.equalizer,
          VideoEffectType.fftSpectrum => Icons.bar_chart,
          VideoEffectType.colorCorrection => Icons.palette,
        };
        final label = switch (type) {
          VideoEffectType.textOverlay => 'Text Overlay',
          VideoEffectType.audioReactive => 'Audio Reactive',
          VideoEffectType.fftSpectrum => 'FFT Spectrum',
          VideoEffectType.colorCorrection => 'Color Correction',
        };
        return PopupMenuItem(
          value: type,
          child: Row(children: [
            Icon(icon, size: 16, color: FabFilterColors.textSecondary),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12)),
          ]),
        );
      }).toList(),
    ).then((type) {
      if (type != null) _service.addEffect(type);
    });
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CENTER: Parameter Editor
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildParamEditor() {
    final effect = _service.selectedEffect;

    if (effect == null) {
      return Center(child: Text(
        'Select or add an effect to edit parameters',
        style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 12),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: FabFilterColors.border)),
            color: FabFilterColors.bgMid,
          ),
          child: Row(children: [
            Text(effect.name, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: FabFilterColors.textPrimary)),
            const Spacer(),
            // Blend mode
            _dropdownSmall<VideoBlendMode>(
              value: effect.blendMode,
              items: VideoBlendMode.values,
              label: (b) => b.label,
              onChanged: (b) => _service.setEffectBlendMode(effect.id, b),
            ),
            const SizedBox(width: 8),
            // Opacity
            SizedBox(
              width: 60,
              child: Row(children: [
                const Text('Op:', style: TextStyle(fontSize: 9, color: FabFilterColors.textTertiary)),
                const SizedBox(width: 2),
                Expanded(child: SliderTheme(
                  data: _sliderTheme(context),
                  child: Slider(
                    value: effect.opacity,
                    onChanged: (v) => _service.setEffectOpacity(effect.id, v),
                  ),
                )),
              ]),
            ),
            const SizedBox(width: 4),
            _toolbarButton(Icons.copy, 'Duplicate', () {
              _service.duplicateEffect(effect.id);
            }),
            const SizedBox(width: 4),
            _toolbarButton(Icons.delete_outline, 'Delete', () {
              _service.removeEffect(effect.id);
            }),
          ]),
        ),

        // Type-specific params
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: switch (effect.type) {
              VideoEffectType.textOverlay => _buildTextOverlayParams(effect),
              VideoEffectType.audioReactive => _buildAudioReactiveParams(effect),
              VideoEffectType.fftSpectrum => _buildFftSpectrumParams(effect),
              VideoEffectType.colorCorrection => _buildColorCorrectionParams(effect),
            },
          ),
        ),
      ],
    );
  }

  // ── Text Overlay Parameters ──

  Widget _buildTextOverlayParams(VideoEffect effect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FabSectionLabel('TEXT'),
        const SizedBox(height: 8),
        // Text input
        TextField(
          controller: _overlayTextCtrl,
          style: const TextStyle(fontSize: 11, color: FabFilterColors.textPrimary),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(),
            hintText: 'Enter text...',
            hintStyle: TextStyle(color: FabFilterColors.textDisabled),
          ),
          onChanged: (text) => _service.setOverlayText(effect.id, text),
        ),
        const SizedBox(height: 12),
        // Position
        FabSectionLabel('POSITION'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4, runSpacing: 4,
          children: TextPosition.values.map((pos) => _positionChip(
            pos, effect.textPosition == pos,
            () => _service.setTextPosition(effect.id, pos),
          )).toList(),
        ),
        const SizedBox(height: 12),
        // Font size
        _paramSlider('Font Size', effect.fontSize, 12, 200,
          (v) => _service.setFontSize(effect.id, v)),
        // Offset X/Y
        _paramSlider('Offset X', effect.textOffsetX, -1.0, 1.0,
          (v) => _service.setTextOffset(effect.id, v, effect.textOffsetY)),
        _paramSlider('Offset Y', effect.textOffsetY, -1.0, 1.0,
          (v) => _service.setTextOffset(effect.id, effect.textOffsetX, v)),
        const SizedBox(height: 8),
        // Style toggles
        FabSectionLabel('STYLE'),
        const SizedBox(height: 4),
        Row(children: [
          _toggleChip('Bold', effect.textBold,
            () => _service.setTextStyle(effect.id, bold: !effect.textBold)),
          const SizedBox(width: 4),
          _toggleChip('Italic', effect.textItalic,
            () => _service.setTextStyle(effect.id, italic: !effect.textItalic)),
          const SizedBox(width: 4),
          _toggleChip('Shadow', effect.textShadow,
            () => _service.setTextStyle(effect.id, shadow: !effect.textShadow)),
        ]),
      ],
    );
  }

  // ── Audio-Reactive Parameters ──

  Widget _buildAudioReactiveParams(VideoEffect effect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FabSectionLabel('VISUALIZATION'),
        const SizedBox(height: 8),
        // Style selector
        Wrap(
          spacing: 4, runSpacing: 4,
          children: ReactiveStyle.values.map((style) => _toggleChip(
            style.label, effect.reactiveStyle == style,
            () => _service.setReactiveStyle(effect.id, style),
          )).toList(),
        ),
        const SizedBox(height: 12),
        FabSectionLabel('PARAMETERS'),
        const SizedBox(height: 4),
        _paramSlider('Intensity', effect.reactiveIntensity, 0, 1,
          (v) => _service.setReactiveIntensity(effect.id, v)),
        _paramSlider('Smoothing', effect.reactiveSmoothing, 0, 1,
          (v) => _service.setReactiveSmoothing(effect.id, v)),
        _paramSlider('Scale', effect.reactiveScale, 0.1, 3.0,
          (v) => _service.setReactiveScale(effect.id, v)),
        const SizedBox(height: 8),
        _toggleChip('Flip Y', effect.reactiveFlipY,
          () => _service.setReactiveFlipY(effect.id, !effect.reactiveFlipY)),
        const SizedBox(height: 12),
        // Preview
        FabSectionLabel('PREVIEW'),
        const SizedBox(height: 4),
        SizedBox(
          height: 80,
          child: CustomPaint(
            size: const Size(double.infinity, 80),
            painter: _ReactivePreviewPainter(
              style: effect.reactiveStyle,
              intensity: effect.reactiveIntensity,
              colorValue: effect.reactiveColorValue,
              color2Value: effect.reactiveColor2Value,
            ),
          ),
        ),
      ],
    );
  }

  // ── FFT Spectrum Parameters ──

  Widget _buildFftSpectrumParams(VideoEffect effect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FabSectionLabel('DISPLAY MODE'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4, runSpacing: 4,
          children: FftDisplayMode.values.map((mode) => _toggleChip(
            mode.label, effect.fftMode == mode,
            () => _service.setFftMode(effect.id, mode),
          )).toList(),
        ),
        const SizedBox(height: 12),
        FabSectionLabel('FFT SIZE'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4, runSpacing: 4,
          children: [256, 512, 1024, 2048, 4096].map((size) => _toggleChip(
            '$size', effect.fftSize == size,
            () => _service.setFftSize(effect.id, size),
          )).toList(),
        ),
        const SizedBox(height: 12),
        FabSectionLabel('RANGE'),
        const SizedBox(height: 4),
        _paramSlider('Floor (dB)', effect.fftFloor, -120, 0,
          (v) => _service.setFftRange(effect.id, v, effect.fftCeiling)),
        _paramSlider('Ceiling (dB)', effect.fftCeiling, -60, 0,
          (v) => _service.setFftRange(effect.id, effect.fftFloor, v)),
        _paramSlider('Bar Width', effect.fftBarWidth, 1, 20,
          (v) => _service.setFftBarWidth(effect.id, v)),
        const SizedBox(height: 8),
        Row(children: [
          _toggleChip('Filled', effect.fftFilled,
            () => _service.setFftFilled(effect.id, !effect.fftFilled)),
          const SizedBox(width: 4),
          _toggleChip('Mirror', effect.fftMirror,
            () => _service.setFftMirror(effect.id, !effect.fftMirror)),
        ]),
        const SizedBox(height: 12),
        // Preview
        FabSectionLabel('PREVIEW'),
        const SizedBox(height: 4),
        SizedBox(
          height: 80,
          child: CustomPaint(
            size: const Size(double.infinity, 80),
            painter: _FftPreviewPainter(
              colorValue: effect.fftColorValue,
              barWidth: effect.fftBarWidth,
              filled: effect.fftFilled,
              mirror: effect.fftMirror,
            ),
          ),
        ),
      ],
    );
  }

  // ── Color Correction Parameters ──

  Widget _buildColorCorrectionParams(VideoEffect effect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FabSectionLabel('COLOR CORRECTION'),
        const SizedBox(height: 8),
        _paramSlider('Brightness', effect.brightness, -1, 1,
          (v) => _service.setBrightness(effect.id, v)),
        _paramSlider('Contrast', effect.contrast, -1, 1,
          (v) => _service.setContrast(effect.id, v)),
        _paramSlider('Saturation', effect.saturation, -1, 1,
          (v) => _service.setSaturation(effect.id, v)),
        _paramSlider('Hue Shift', effect.hueShift, -180, 180,
          (v) => _service.setHueShift(effect.id, v)),
        _paramSlider('Gamma', effect.gamma, 0.1, 3.0,
          (v) => _service.setGamma(effect.id, v)),
        const SizedBox(height: 12),
        // Reset button
        Center(child: _actionButton('Reset All', () {
          _service.setBrightness(effect.id, 0);
          _service.setContrast(effect.id, 0);
          _service.setSaturation(effect.id, 0);
          _service.setHueShift(effect.id, 0);
          _service.setGamma(effect.id, 1.0);
        })),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RIGHT: Presets & Info
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildPresetsPanel() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            FabSectionLabel('PRESETS'),
            const Spacer(),
            _iconBtn(Icons.auto_fix_high, 'Load factory', () {
              _service.loadFactoryPresets();
            }),
            _iconBtn(Icons.save, 'Save preset', () {
              _service.savePreset('Preset ${_service.presets.length + 1}');
            }),
          ]),
          const SizedBox(height: 8),
          if (_service.presets.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'No presets.\n\nTap factory icon to load\nbuilt-in presets.',
                style: const TextStyle(fontSize: 10, color: FabFilterColors.textTertiary),
              ),
            )
          else
            Expanded(child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _service.presets.length,
              itemBuilder: (_, i) => _buildPresetItem(_service.presets[i]),
            )),

          const Spacer(),
          // Effect info
          FabSectionLabel('INFO'),
          const SizedBox(height: 4),
          Text('Total effects: ${_service.effectCount}',
            style: const TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
          Text('Enabled: ${_service.enabledCount}',
            style: TextStyle(fontSize: 10,
              color: _service.enabledCount > 0 ? FabFilterColors.green : FabFilterColors.textTertiary)),
          Text('Processor: ${_service.active ? "ON" : "OFF"}',
            style: TextStyle(fontSize: 10,
              color: _service.active ? FabFilterColors.green : FabFilterColors.textTertiary)),
          const SizedBox(height: 12),
          FabSectionLabel('EFFECT TYPES'),
          const SizedBox(height: 4),
          Text(
            'Text Overlay — titles, credits\n'
            'Audio Reactive — bars, wave, particles\n'
            'FFT Spectrum — frequency display\n'
            'Color Correction — grade & look',
            style: const TextStyle(fontSize: 9, color: FabFilterColors.textTertiary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetItem(VideoProcessorPreset preset) {
    return InkWell(
      onTap: () => _service.loadPreset(preset.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(
            preset.isFactory ? Icons.star : Icons.bookmark_outline,
            size: 12,
            color: preset.isFactory ? FabFilterColors.orange : FabFilterColors.textTertiary,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(preset.name, style: const TextStyle(
            fontSize: 10, color: FabFilterColors.textPrimary),
            overflow: TextOverflow.ellipsis)),
          Text('${preset.effects.length} fx', style: const TextStyle(
            fontSize: 9, color: FabFilterColors.textTertiary)),
          if (!preset.isFactory) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _service.removePreset(preset.id),
              child: const Icon(Icons.close, size: 10, color: FabFilterColors.textDisabled),
            ),
          ],
        ]),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return SizedBox(
      width: 24, height: 24,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        color: FabFilterColors.textSecondary,
        disabledColor: FabFilterColors.textDisabled,
        onPressed: onPressed,
      ),
    );
  }

  Widget _toolbarButton(IconData icon, String tooltip, VoidCallback? onPressed, {Color? color}) {
    final enabled = onPressed != null;
    final c = color ?? FabFilterColors.textSecondary;
    return SizedBox(
      width: 24, height: 24,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        color: enabled ? c : FabFilterColors.textDisabled,
        onPressed: onPressed,
      ),
    );
  }

  Widget _paramSlider(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(
            fontSize: 10, color: FabFilterColors.textSecondary),
            overflow: TextOverflow.ellipsis),
        ),
        Expanded(child: SliderTheme(
          data: _sliderTheme(context),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        )),
        SizedBox(
          width: 40,
          child: Text(
            max > 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(2),
            style: const TextStyle(fontSize: 9, color: FabFilterColors.cyan),
            textAlign: TextAlign.right,
          ),
        ),
      ]),
    );
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? FabFilterColors.cyan.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active ? FabFilterColors.cyan : FabFilterColors.border),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 9,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          color: active ? FabFilterColors.cyan : FabFilterColors.textSecondary,
        )),
      ),
    );
  }

  Widget _positionChip(TextPosition pos, bool active, VoidCallback onTap) {
    // Short labels for the 3×3 grid
    final short = switch (pos) {
      TextPosition.topLeft => 'TL',
      TextPosition.topCenter => 'TC',
      TextPosition.topRight => 'TR',
      TextPosition.centerLeft => 'CL',
      TextPosition.center => 'C',
      TextPosition.centerRight => 'CR',
      TextPosition.bottomLeft => 'BL',
      TextPosition.bottomCenter => 'BC',
      TextPosition.bottomRight => 'BR',
    };
    return _toggleChip(short, active, onTap);
  }

  Widget _actionButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FabFilterColors.border),
        ),
        child: Text(label, style: const TextStyle(
          fontSize: 10, color: FabFilterColors.textSecondary)),
      ),
    );
  }

  Widget _dropdownSmall<T>({
    required T value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: FabFilterColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          style: const TextStyle(fontSize: 9, color: FabFilterColors.textSecondary),
          dropdownColor: FabFilterColors.bgElevated,
          items: items.map((item) => DropdownMenuItem(
            value: item,
            child: Text(label(item)),
          )).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }

  SliderThemeData _sliderTheme(BuildContext context) {
    return SliderTheme.of(context).copyWith(
      trackHeight: 2,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
      activeTrackColor: FabFilterColors.cyan,
      inactiveTrackColor: FabFilterColors.bgMid,
      thumbColor: FabFilterColors.cyan,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PREVIEW PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _ReactivePreviewPainter extends CustomPainter {
  final ReactiveStyle style;
  final double intensity;
  final int colorValue;
  final int color2Value;

  _ReactivePreviewPainter({
    required this.style,
    required this.intensity,
    required this.colorValue,
    required this.color2Value,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(colorValue).withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final barCount = 32;
    final barWidth = size.width / barCount;

    for (int i = 0; i < barCount; i++) {
      // Deterministic "spectrum" shape
      final normalized = i / barCount;
      final height = (0.3 + 0.7 * intensity) *
          size.height *
          (1.0 - (normalized - 0.3).abs()) *
          (0.5 + 0.5 * ((i * 7) % 5) / 4);

      final x = i * barWidth;
      canvas.drawRect(
        Rect.fromLTWH(x + 1, size.height - height.clamp(0, size.height), barWidth - 2, height.clamp(0, size.height)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ReactivePreviewPainter old) =>
      style != old.style ||
      intensity != old.intensity ||
      colorValue != old.colorValue ||
      color2Value != old.color2Value;
}

class _FftPreviewPainter extends CustomPainter {
  final int colorValue;
  final double barWidth;
  final bool filled;
  final bool mirror;

  _FftPreviewPainter({
    required this.colorValue,
    required this.barWidth,
    required this.filled,
    required this.mirror,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(colorValue).withValues(alpha: 0.7)
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1;

    final barCount = (size.width / barWidth).floor().clamp(1, 128);
    final bw = size.width / barCount;

    for (int i = 0; i < barCount; i++) {
      // Deterministic log-scale spectrum shape
      final normalized = i / barCount;
      final logPos = (normalized * 3 + 0.1).clamp(0.1, 3.0);
      final height = size.height * (0.8 - 0.6 * logPos / 3) *
          (0.6 + 0.4 * ((i * 13 + 7) % 11) / 10);

      final x = i * bw;
      final h = height.clamp(2.0, size.height);

      if (mirror) {
        final halfH = h / 2;
        canvas.drawRect(
          Rect.fromLTWH(x + 1, size.height / 2 - halfH, bw - 2, halfH),
          paint,
        );
        canvas.drawRect(
          Rect.fromLTWH(x + 1, size.height / 2, bw - 2, halfH),
          paint,
        );
      } else {
        canvas.drawRect(
          Rect.fromLTWH(x + 1, size.height - h, bw - 2, h),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FftPreviewPainter old) =>
      colorValue != old.colorValue ||
      barWidth != old.barWidth ||
      filled != old.filled ||
      mirror != old.mirror;
}
