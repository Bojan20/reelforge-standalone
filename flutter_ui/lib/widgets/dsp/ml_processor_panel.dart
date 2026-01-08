/// ReelForge ML Processor Panel
///
/// AI-powered audio processing: Stem Separation, Denoising, Enhancement

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

/// ML Processing mode
enum MlProcessingMode {
  stemSeparation,
  denoise,
  enhance,
  voiceIsolation,
}

/// ML Model type
enum MlModelType {
  htdemucs,
  htdemucsFt,
  demucs,
  mdx,
  deepFilter,
  frcrn,
}

/// ML Processor Panel Widget
class MlProcessorPanel extends StatefulWidget {
  /// Track ID to process
  final int trackId;

  /// Sample rate
  final double sampleRate;

  /// Callback when processing starts
  final VoidCallback? onProcessingStart;

  /// Callback when processing completes
  final VoidCallback? onProcessingComplete;

  const MlProcessorPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onProcessingStart,
    this.onProcessingComplete,
  });

  @override
  State<MlProcessorPanel> createState() => _MlProcessorPanelState();
}

class _MlProcessorPanelState extends State<MlProcessorPanel> {
  // Mode selection
  MlProcessingMode _mode = MlProcessingMode.stemSeparation;
  MlModelType _modelType = MlModelType.htdemucs;

  // Stem separation settings
  bool _extractVocals = true;
  bool _extractDrums = true;
  bool _extractBass = true;
  bool _extractOther = true;

  // Denoise settings
  double _denoiseStrength = 0.5;
  bool _preserveVoice = true;
  bool _adaptiveMode = true;

  // Enhancement settings
  double _clarityAmount = 0.5;
  double _warmthAmount = 0.3;
  bool _autoNormalize = true;

  // Processing state
  bool _isProcessing = false;
  double _progress = 0.0;
  String _statusMessage = 'Ready';

  // Model availability
  final Map<MlModelType, bool> _modelAvailable = {
    MlModelType.htdemucs: true,
    MlModelType.htdemucsFt: false,
    MlModelType.demucs: false,
    MlModelType.mdx: false,
    MlModelType.deepFilter: true,
    MlModelType.frcrn: false,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildModeSelector(),
                  const SizedBox(height: 16),
                  _buildModelSelector(),
                  const SizedBox(height: 16),
                  _buildModeSettings(),
                  const SizedBox(height: 16),
                  _buildProgressSection(),
                  const SizedBox(height: 16),
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(
            color: ReelForgeTheme.accentBlue.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.psychology,
            color: ReelForgeTheme.accentBlue,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'ML Processor',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _buildStatusBadge(),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color badgeColor;
    String text;

    if (_isProcessing) {
      badgeColor = ReelForgeTheme.accentOrange;
      text = 'Processing';
    } else {
      badgeColor = ReelForgeTheme.accentGreen;
      text = 'Ready';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: badgeColor,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Processing Mode',
          style: TextStyle(
            color: ReelForgeTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: MlProcessingMode.values.map((mode) {
            final isSelected = mode == _mode;
            return _buildModeChip(mode, isSelected);
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildModeChip(MlProcessingMode mode, bool isSelected) {
    final label = _getModeLabel(mode);
    final icon = _getModeIcon(mode);

    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? ReelForgeTheme.accentBlue.withValues(alpha: 0.2)
              : ReelForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? ReelForgeTheme.accentBlue
                : ReelForgeTheme.bgSurface,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? ReelForgeTheme.accentBlue
                  : ReelForgeTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? ReelForgeTheme.accentBlue
                    : ReelForgeTheme.textPrimary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getModeLabel(MlProcessingMode mode) {
    switch (mode) {
      case MlProcessingMode.stemSeparation:
        return 'Stem Separation';
      case MlProcessingMode.denoise:
        return 'Denoise';
      case MlProcessingMode.enhance:
        return 'Enhance';
      case MlProcessingMode.voiceIsolation:
        return 'Voice Isolation';
    }
  }

  IconData _getModeIcon(MlProcessingMode mode) {
    switch (mode) {
      case MlProcessingMode.stemSeparation:
        return Icons.layers;
      case MlProcessingMode.denoise:
        return Icons.noise_aware;
      case MlProcessingMode.enhance:
        return Icons.auto_fix_high;
      case MlProcessingMode.voiceIsolation:
        return Icons.record_voice_over;
    }
  }

  Widget _buildModelSelector() {
    final availableModels = _getModelsForMode(_mode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI Model',
          style: TextStyle(
            color: ReelForgeTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: ReelForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: ReelForgeTheme.bgSurface),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<MlModelType>(
              value: _modelType,
              isExpanded: true,
              dropdownColor: ReelForgeTheme.bgMid,
              items: availableModels.map((model) {
                final isAvailable = _modelAvailable[model] ?? false;
                return DropdownMenuItem(
                  value: model,
                  child: Row(
                    children: [
                      Text(
                        _getModelLabel(model),
                        style: TextStyle(
                          color: isAvailable
                              ? ReelForgeTheme.textPrimary
                              : ReelForgeTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      if (!isAvailable)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: ReelForgeTheme.accentOrange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Download',
                            style: TextStyle(
                              color: ReelForgeTheme.accentOrange,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _modelType = value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  List<MlModelType> _getModelsForMode(MlProcessingMode mode) {
    switch (mode) {
      case MlProcessingMode.stemSeparation:
        return [
          MlModelType.htdemucs,
          MlModelType.htdemucsFt,
          MlModelType.demucs,
          MlModelType.mdx,
        ];
      case MlProcessingMode.denoise:
      case MlProcessingMode.voiceIsolation:
        return [MlModelType.deepFilter, MlModelType.frcrn];
      case MlProcessingMode.enhance:
        return [MlModelType.frcrn, MlModelType.deepFilter];
    }
  }

  String _getModelLabel(MlModelType model) {
    switch (model) {
      case MlModelType.htdemucs:
        return 'HT-Demucs (Hybrid Transformer)';
      case MlModelType.htdemucsFt:
        return 'HT-Demucs Fine-tuned';
      case MlModelType.demucs:
        return 'Demucs v4';
      case MlModelType.mdx:
        return 'MDX-Net';
      case MlModelType.deepFilter:
        return 'DeepFilterNet';
      case MlModelType.frcrn:
        return 'FRCRN';
    }
  }

  Widget _buildModeSettings() {
    switch (_mode) {
      case MlProcessingMode.stemSeparation:
        return _buildStemSettings();
      case MlProcessingMode.denoise:
        return _buildDenoiseSettings();
      case MlProcessingMode.enhance:
        return _buildEnhanceSettings();
      case MlProcessingMode.voiceIsolation:
        return _buildVoiceSettings();
    }
  }

  Widget _buildStemSettings() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Extract Stems',
            style: TextStyle(
              color: ReelForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildStemToggle('Vocals', _extractVocals, Icons.mic,
                  (v) => setState(() => _extractVocals = v)),
              _buildStemToggle('Drums', _extractDrums, Icons.music_note,
                  (v) => setState(() => _extractDrums = v)),
              _buildStemToggle('Bass', _extractBass, Icons.graphic_eq,
                  (v) => setState(() => _extractBass = v)),
              _buildStemToggle('Other', _extractOther, Icons.queue_music,
                  (v) => setState(() => _extractOther = v)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStemToggle(
    String label,
    bool value,
    IconData icon,
    ValueChanged<bool> onChanged,
  ) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: value
              ? ReelForgeTheme.accentGreen.withValues(alpha: 0.2)
              : ReelForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: value
                ? ReelForgeTheme.accentGreen
                : ReelForgeTheme.bgSurface,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color:
                  value ? ReelForgeTheme.accentGreen : ReelForgeTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color:
                    value ? ReelForgeTheme.accentGreen : ReelForgeTheme.textPrimary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDenoiseSettings() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSlider(
            'Strength',
            _denoiseStrength,
            0.0,
            1.0,
            (v) => setState(() => _denoiseStrength = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCheckbox(
                  'Preserve Voice',
                  _preserveVoice,
                  (v) => setState(() => _preserveVoice = v ?? false),
                ),
              ),
              Expanded(
                child: _buildCheckbox(
                  'Adaptive Mode',
                  _adaptiveMode,
                  (v) => setState(() => _adaptiveMode = v ?? false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnhanceSettings() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSlider(
            'Clarity',
            _clarityAmount,
            0.0,
            1.0,
            (v) => setState(() => _clarityAmount = v),
          ),
          const SizedBox(height: 8),
          _buildSlider(
            'Warmth',
            _warmthAmount,
            0.0,
            1.0,
            (v) => setState(() => _warmthAmount = v),
          ),
          const SizedBox(height: 12),
          _buildCheckbox(
            'Auto Normalize',
            _autoNormalize,
            (v) => setState(() => _autoNormalize = v ?? false),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceSettings() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: ReelForgeTheme.accentCyan,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Isolates voice/dialogue from background noise and music',
                  style: TextStyle(
                    color: ReelForgeTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSlider(
            'Isolation Strength',
            _denoiseStrength,
            0.0,
            1.0,
            (v) => setState(() => _denoiseStrength = v),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: ReelForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
            Text(
              '${(value * 100).toInt()}%',
              style: TextStyle(
                color: ReelForgeTheme.accentBlue,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: ReelForgeTheme.accentBlue,
            inactiveTrackColor: ReelForgeTheme.bgSurface,
            thumbColor: ReelForgeTheme.accentBlue,
            overlayColor: ReelForgeTheme.accentBlue.withValues(alpha: 0.2),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildCheckbox(
    String label,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: ReelForgeTheme.accentBlue,
            side: BorderSide(color: ReelForgeTheme.bgSurface),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: ReelForgeTheme.textPrimary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progress',
                style: TextStyle(
                  color: ReelForgeTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              Text(
                '${(_progress * 100).toInt()}%',
                style: TextStyle(
                  color: ReelForgeTheme.accentBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: ReelForgeTheme.bgDeep,
              valueColor: AlwaysStoppedAnimation<Color>(
                _isProcessing
                    ? ReelForgeTheme.accentOrange
                    : ReelForgeTheme.accentGreen,
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            style: TextStyle(
              color: ReelForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isProcessing ? null : _startProcessing,
            icon: Icon(
              _isProcessing ? Icons.hourglass_top : Icons.play_arrow,
              size: 18,
            ),
            label: Text(_isProcessing ? 'Processing...' : 'Process'),
            style: ElevatedButton.styleFrom(
              backgroundColor: ReelForgeTheme.accentBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (_isProcessing)
          ElevatedButton(
            onPressed: _cancelProcessing,
            style: ElevatedButton.styleFrom(
              backgroundColor: ReelForgeTheme.accentRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('Cancel'),
          ),
      ],
    );
  }

  void _startProcessing() {
    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _statusMessage = 'Initializing...';
    });

    widget.onProcessingStart?.call();

    // Simulate processing progress
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _isProcessing) {
        setState(() {
          _progress = 0.1;
          _statusMessage = 'Loading model...';
        });
      }
    });

    // Would call actual FFI functions:
    // mlStemSeparationStart(inputPath, outputDir, modelType)
  }

  void _cancelProcessing() {
    setState(() {
      _isProcessing = false;
      _progress = 0.0;
      _statusMessage = 'Cancelled';
    });

    // Would call: mlStemSeparationCancel()
  }
}
