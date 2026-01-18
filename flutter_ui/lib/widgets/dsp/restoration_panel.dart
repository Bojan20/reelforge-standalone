/// FluxForge Studio Audio Restoration Panel
///
/// Professional audio restoration: Denoise, Declick, Declip, Dehum, Dereverb
/// Connected to rf-restore via FFI

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../providers/restoration_provider.dart';

/// Restoration module type
enum RestorationModule {
  denoise,
  declick,
  declip,
  dehum,
  dereverb,
}

/// Restoration Panel Widget
class RestorationPanel extends StatefulWidget {
  /// Track ID to process
  final int trackId;

  /// Sample rate
  final double sampleRate;

  /// Callback when settings change
  final VoidCallback? onSettingsChanged;

  const RestorationPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<RestorationPanel> createState() => _RestorationPanelState();
}

class _RestorationPanelState extends State<RestorationPanel> {
  // Module enables
  bool _denoiseEnabled = false;
  bool _declickEnabled = false;
  bool _declipEnabled = false;
  bool _dehumEnabled = false;
  bool _dereverbEnabled = false;

  // Denoise settings
  double _denoiseStrength = 0.5;
  bool _noiseProfileLearned = false;

  // Declick settings
  double _declickSensitivity = 0.5;
  int _detectedClicks = 0;

  // Declip settings
  double _declipThreshold = 0.9;
  double _clipPercentage = 0.0;

  // Dehum settings
  double _dehumFrequency = 50.0;
  int _dehumHarmonics = 4;
  bool _humDetected = false;

  // Dereverb settings
  double _dereverbAmount = 0.5;
  double _detectedReverbAmount = 0.0;

  // Analysis state
  bool _analyzed = false;
  double _noiseFloorDb = -60.0;
  double _overallQuality = 1.0;
  List<String> _recommendations = [];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
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
                  _buildQuickActions(),
                  const SizedBox(height: 16),
                  _buildModuleCard(
                    RestorationModule.denoise,
                    'Denoise',
                    Icons.noise_aware,
                    _denoiseEnabled,
                    (v) => setState(() => _denoiseEnabled = v),
                    _buildDenoiseContent(),
                  ),
                  const SizedBox(height: 12),
                  _buildModuleCard(
                    RestorationModule.declick,
                    'Declick',
                    Icons.touch_app_outlined,
                    _declickEnabled,
                    (v) => setState(() => _declickEnabled = v),
                    _buildDeclickContent(),
                  ),
                  const SizedBox(height: 12),
                  _buildModuleCard(
                    RestorationModule.declip,
                    'Declip',
                    Icons.content_cut,
                    _declipEnabled,
                    (v) => setState(() => _declipEnabled = v),
                    _buildDeclipContent(),
                  ),
                  const SizedBox(height: 12),
                  _buildModuleCard(
                    RestorationModule.dehum,
                    'Dehum',
                    Icons.electrical_services,
                    _dehumEnabled,
                    (v) => setState(() => _dehumEnabled = v),
                    _buildDehumContent(),
                  ),
                  const SizedBox(height: 12),
                  _buildModuleCard(
                    RestorationModule.dereverb,
                    'Dereverb',
                    Icons.spatial_audio,
                    _dereverbEnabled,
                    (v) => setState(() => _dereverbEnabled = v),
                    _buildDereverbContent(),
                  ),
                  if (_analyzed) ...[
                    const SizedBox(height: 16),
                    _buildAnalysisResults(),
                  ],
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
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(
            color: FluxForgeTheme.accentGreen.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.healing,
            color: FluxForgeTheme.accentGreen,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Audio Restoration',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _buildQualityIndicator(),
        ],
      ),
    );
  }

  Widget _buildQualityIndicator() {
    final color = _overallQuality > 0.8
        ? FluxForgeTheme.accentGreen
        : _overallQuality > 0.5
            ? FluxForgeTheme.accentOrange
            : FluxForgeTheme.accentRed;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${(_overallQuality * 100).toInt()}% Quality',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _analyzeAudio,
            icon: const Icon(Icons.search, size: 16),
            label: const Text('Analyze'),
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentCyan,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _autoFix,
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('Auto Fix'),
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModuleCard(
    RestorationModule module,
    String title,
    IconData icon,
    bool enabled,
    ValueChanged<bool> onEnabledChanged,
    Widget content,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: enabled
              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
              : FluxForgeTheme.bgSurface,
        ),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () => onEnabledChanged(!enabled),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: enabled
                        ? FluxForgeTheme.accentGreen
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled
                          ? FluxForgeTheme.textPrimary
                          : FluxForgeTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  _buildToggleSwitch(enabled, onEnabledChanged),
                ],
              ),
            ),
          ),
          // Content
          if (enabled)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: content,
            ),
        ],
      ),
    );
  }

  Widget _buildToggleSwitch(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 40,
        height: 22,
        decoration: BoxDecoration(
          color: value
              ? FluxForgeTheme.accentGreen
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(11),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDenoiseContent() {
    return Column(
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
              child: OutlinedButton.icon(
                onPressed: _learnNoiseProfile,
                icon: Icon(
                  _noiseProfileLearned ? Icons.check : Icons.record_voice_over,
                  size: 14,
                ),
                label: Text(_noiseProfileLearned ? 'Profile Learned' : 'Learn Noise'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _noiseProfileLearned
                      ? FluxForgeTheme.accentGreen
                      : FluxForgeTheme.accentCyan,
                  side: BorderSide(
                    color: _noiseProfileLearned
                        ? FluxForgeTheme.accentGreen
                        : FluxForgeTheme.accentCyan,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            if (_noiseProfileLearned) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: FluxForgeTheme.textSecondary,
                ),
                onPressed: () {
                  setState(() => _noiseProfileLearned = false);
                  // Would call: restorationClearNoiseProfile()
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Noise Floor: ${_noiseFloorDb.toStringAsFixed(1)} dB',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildDeclickContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSlider(
          'Sensitivity',
          _declickSensitivity,
          0.0,
          1.0,
          (v) => setState(() => _declickSensitivity = v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 14,
              color: FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              '$_detectedClicks clicks detected',
              style: TextStyle(
                color: _detectedClicks > 0
                    ? FluxForgeTheme.accentOrange
                    : FluxForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDeclipContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSlider(
          'Threshold',
          _declipThreshold,
          0.5,
          1.0,
          (v) => setState(() => _declipThreshold = v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.warning_amber,
              size: 14,
              color: _clipPercentage > 0.01
                  ? FluxForgeTheme.accentRed
                  : FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              '${(_clipPercentage * 100).toStringAsFixed(2)}% clipped',
              style: TextStyle(
                color: _clipPercentage > 0.01
                    ? FluxForgeTheme.accentRed
                    : FluxForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDehumContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildFrequencySelector(),
            ),
            const SizedBox(width: 12),
            _buildHarmonicsSelector(),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              _humDetected ? Icons.check_circle : Icons.info_outline,
              size: 14,
              color: _humDetected
                  ? FluxForgeTheme.accentGreen
                  : FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              _humDetected
                  ? 'Hum detected at ${_dehumFrequency.toInt()} Hz'
                  : 'No hum detected',
              style: TextStyle(
                color: _humDetected
                    ? FluxForgeTheme.accentOrange
                    : FluxForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFrequencySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Frequency',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _buildFreqButton(50.0, '50 Hz'),
            const SizedBox(width: 8),
            _buildFreqButton(60.0, '60 Hz'),
          ],
        ),
      ],
    );
  }

  Widget _buildFreqButton(double freq, String label) {
    final isSelected = _dehumFrequency == freq;
    return GestureDetector(
      onTap: () => setState(() => _dehumFrequency = freq),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.2)
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? FluxForgeTheme.accentGreen
                : FluxForgeTheme.bgSurface,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? FluxForgeTheme.accentGreen
                : FluxForgeTheme.textPrimary,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildHarmonicsSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Harmonics',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.bgSurface),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _dehumHarmonics,
              dropdownColor: FluxForgeTheme.bgMid,
              items: [2, 4, 6, 8].map((n) {
                return DropdownMenuItem(
                  value: n,
                  child: Text(
                    '$n',
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 11,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _dehumHarmonics = v);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDereverbContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSlider(
          'Amount',
          _dereverbAmount,
          0.0,
          1.0,
          (v) => setState(() => _dereverbAmount = v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.spatial_audio_off,
              size: 14,
              color: FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              'Detected reverb: ${(_detectedReverbAmount * 100).toInt()}%',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
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
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
              ),
            ),
            Text(
              '${(value * 100).toInt()}%',
              style: TextStyle(
                color: FluxForgeTheme.accentGreen,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: FluxForgeTheme.accentGreen,
            inactiveTrackColor: FluxForgeTheme.bgSurface,
            thumbColor: FluxForgeTheme.accentGreen,
            overlayColor: FluxForgeTheme.accentGreen.withValues(alpha: 0.2),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
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

  Widget _buildAnalysisResults() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.accentCyan.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 16,
                color: FluxForgeTheme.accentCyan,
              ),
              const SizedBox(width: 8),
              Text(
                'Recommendations',
                style: TextStyle(
                  color: FluxForgeTheme.accentCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._recommendations.map((rec) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(color: FluxForgeTheme.textSecondary),
                    ),
                    Expanded(
                      child: Text(
                        rec,
                        style: TextStyle(
                          color: FluxForgeTheme.textPrimary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  void _learnNoiseProfile() {
    // Learn noise profile from selection
    final provider = context.read<RestorationProvider>();
    // For now, simulate - real implementation needs audio selection
    setState(() {
      _noiseProfileLearned = true;
    });
  }

  Future<void> _analyzeAudio() async {
    final provider = context.read<RestorationProvider>();

    // Sync settings to provider
    _syncSettingsToProvider(provider);

    // In real implementation, analyze actual audio file
    // For now, use FFI analysis if available
    // await provider.analyzeFile(audioPath);

    // Simulate analysis results for demo
    setState(() {
      _analyzed = true;
      _noiseFloorDb = -55.0;
      _detectedClicks = 12;
      _clipPercentage = 0.02;
      _humDetected = true;
      _detectedReverbAmount = 0.3;
      _overallQuality = 0.75;
      _recommendations = [
        'Apply denoise to reduce background noise',
        'Use declick to remove 12 detected clicks',
        'Enable dehum at 50Hz',
      ];
    });

    // Auto-configure from analysis if provider has results
    if (provider.analysis != null) {
      provider.autoConfigureFromAnalysis();
      _syncSettingsFromProvider(provider);
    }
  }

  void _autoFix() {
    final provider = context.read<RestorationProvider>();

    setState(() {
      _denoiseEnabled = _noiseFloorDb > -60.0;
      _declickEnabled = _detectedClicks > 0;
      _declipEnabled = _clipPercentage > 0.01;
      _dehumEnabled = _humDetected;
      _dereverbEnabled = _detectedReverbAmount > 0.2;
    });

    // Sync to provider
    _syncSettingsToProvider(provider);
  }

  void _syncSettingsToProvider(RestorationProvider provider) {
    provider.setDenoiseEnabled(_denoiseEnabled);
    provider.setDenoiseStrength(_denoiseStrength);
    provider.setDeclickEnabled(_declickEnabled);
    provider.setDeclickSensitivity(_declickSensitivity);
    provider.setDeclipEnabled(_declipEnabled);
    provider.setDeclipThreshold(_declipThreshold);
    provider.setDehumEnabled(_dehumEnabled);
    provider.setDehumFrequency(_dehumFrequency);
    provider.setDehumHarmonics(_dehumHarmonics);
    provider.setDereverbEnabled(_dereverbEnabled);
    provider.setDereverbAmount(_dereverbAmount);
  }

  void _syncSettingsFromProvider(RestorationProvider provider) {
    setState(() {
      _denoiseEnabled = provider.denoiseEnabled;
      _denoiseStrength = provider.denoiseStrength;
      _declickEnabled = provider.declickEnabled;
      _declickSensitivity = provider.declickSensitivity;
      _declipEnabled = provider.declipEnabled;
      _declipThreshold = provider.declipThreshold;
      _dehumEnabled = provider.dehumEnabled;
      _dehumFrequency = provider.dehumFrequency;
      _dehumHarmonics = provider.dehumHarmonics;
      _dereverbEnabled = provider.dereverbEnabled;
      _dereverbAmount = provider.dereverbAmount;
    });
  }
}
