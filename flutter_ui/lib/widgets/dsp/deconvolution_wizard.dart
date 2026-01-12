/// Deconvolution Wizard UI
///
/// Step-by-step wizard for creating custom IRs:
/// - Sweep generation (exponential sine sweep, MLS)
/// - Recording through speaker/mic
/// - Automatic deconvolution
/// - IR cleanup and trimming

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Sweep type for IR capture
enum SweepType {
  /// Exponential Sine Sweep (ESS) - best quality
  exponentialSweep,
  /// Maximum Length Sequence - fastest
  mls,
  /// Linear sweep
  linearSweep,
  /// Pink noise
  pinkNoise,
}

/// Wizard step
enum WizardStep {
  configure,
  generateSweep,
  recordResponse,
  deconvolve,
  cleanup,
  export,
}

/// Deconvolution parameters
class DeconvolutionParams {
  final SweepType sweepType;
  final double sweepLengthSeconds;
  final double startFrequency;
  final double endFrequency;
  final double sampleRate;
  final int preRollSeconds;
  final int tailSeconds;
  final bool regularize;
  final double regularizationDb;

  const DeconvolutionParams({
    this.sweepType = SweepType.exponentialSweep,
    this.sweepLengthSeconds = 10,
    this.startFrequency = 20,
    this.endFrequency = 20000,
    this.sampleRate = 48000,
    this.preRollSeconds = 1,
    this.tailSeconds = 5,
    this.regularize = true,
    this.regularizationDb = -60,
  });
}

/// Deconvolution Wizard
class DeconvolutionWizard extends StatefulWidget {
  final VoidCallback? onClose;
  final void Function(String irPath)? onIrCreated;

  const DeconvolutionWizard({
    super.key,
    this.onClose,
    this.onIrCreated,
  });

  @override
  State<DeconvolutionWizard> createState() => _DeconvolutionWizardState();
}

class _DeconvolutionWizardState extends State<DeconvolutionWizard> {
  WizardStep _currentStep = WizardStep.configure;
  DeconvolutionParams _params = const DeconvolutionParams();
  bool _isProcessing = false;
  double _progress = 0;
  String _statusMessage = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 560,
      constraints: const BoxConstraints(maxHeight: 700),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FluxForgeTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          _buildStepIndicator(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildCurrentStep(),
            ),
          ),
          _buildNavigation(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF00BCD4), Color(0xFF0097A7)],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_fix_high, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deconvolution Wizard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Create custom impulse responses',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: FluxForgeTheme.bgMid,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: WizardStep.values.map((step) {
          final index = step.index;
          final currentIndex = _currentStep.index;
          final isComplete = index < currentIndex;
          final isCurrent = index == currentIndex;

          return Row(
            children: [
              if (index > 0)
                Container(
                  width: 24,
                  height: 2,
                  color: isComplete
                      ? const Color(0xFF00BCD4)
                      : FluxForgeTheme.border,
                ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isComplete
                      ? const Color(0xFF00BCD4)
                      : isCurrent
                          ? const Color(0xFF00BCD4).withOpacity(0.3)
                          : FluxForgeTheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isCurrent || isComplete
                        ? const Color(0xFF00BCD4)
                        : FluxForgeTheme.border,
                    width: isCurrent ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: isComplete
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: isCurrent
                                ? FluxForgeTheme.textPrimary
                                : FluxForgeTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case WizardStep.configure:
        return _buildConfigureStep();
      case WizardStep.generateSweep:
        return _buildGenerateSweepStep();
      case WizardStep.recordResponse:
        return _buildRecordStep();
      case WizardStep.deconvolve:
        return _buildDeconvolveStep();
      case WizardStep.cleanup:
        return _buildCleanupStep();
      case WizardStep.export:
        return _buildExportStep();
    }
  }

  Widget _buildConfigureStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle('Configure Sweep Parameters'),
        const SizedBox(height: 16),

        // Sweep type selection
        _buildSectionTitle('Sweep Type'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SweepType.values.map((type) {
            final isSelected = _params.sweepType == type;
            return _buildSweepTypeCard(type, isSelected);
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Sweep parameters
        _buildSectionTitle('Sweep Parameters'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildParamField(
                'Length',
                '${_params.sweepLengthSeconds.toStringAsFixed(0)} sec',
                Icons.timer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildParamField(
                'Start Freq',
                '${_params.startFrequency.toStringAsFixed(0)} Hz',
                Icons.graphic_eq,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildParamField(
                'End Freq',
                '${(_params.endFrequency / 1000).toStringAsFixed(0)} kHz',
                Icons.graphic_eq,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildParamField(
                'Sample Rate',
                '${(_params.sampleRate / 1000).toStringAsFixed(1)} kHz',
                Icons.speed,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildParamField(
                'Pre-roll',
                '${_params.preRollSeconds} sec',
                Icons.skip_previous,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildParamField(
                'Tail',
                '${_params.tailSeconds} sec',
                Icons.skip_next,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Regularization
        _buildSectionTitle('Deconvolution Options'),
        const SizedBox(height: 8),
        _buildCheckOption(
          'Regularization',
          'Apply Tikhonov regularization to reduce noise',
          _params.regularize,
          (v) => setState(() => _params = DeconvolutionParams(
                sweepType: _params.sweepType,
                sweepLengthSeconds: _params.sweepLengthSeconds,
                startFrequency: _params.startFrequency,
                endFrequency: _params.endFrequency,
                sampleRate: _params.sampleRate,
                preRollSeconds: _params.preRollSeconds,
                tailSeconds: _params.tailSeconds,
                regularize: v,
                regularizationDb: _params.regularizationDb,
              )),
        ),
      ],
    );
  }

  Widget _buildSweepTypeCard(SweepType type, bool isSelected) {
    final info = _getSweepTypeInfo(type);

    return GestureDetector(
      onTap: () => setState(() => _params = DeconvolutionParams(
            sweepType: type,
            sweepLengthSeconds: _params.sweepLengthSeconds,
            startFrequency: _params.startFrequency,
            endFrequency: _params.endFrequency,
            sampleRate: _params.sampleRate,
            preRollSeconds: _params.preRollSeconds,
            tailSeconds: _params.tailSeconds,
            regularize: _params.regularize,
            regularizationDb: _params.regularizationDb,
          )),
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00BCD4).withOpacity(0.15)
              : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF00BCD4) : FluxForgeTheme.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              info['icon'] as IconData,
              color: isSelected
                  ? const Color(0xFF00BCD4)
                  : FluxForgeTheme.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              info['name'] as String,
              style: TextStyle(
                color: isSelected
                    ? FluxForgeTheme.textPrimary
                    : FluxForgeTheme.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              info['desc'] as String,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary.withOpacity(0.7),
                fontSize: 9,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getSweepTypeInfo(SweepType type) {
    switch (type) {
      case SweepType.exponentialSweep:
        return {
          'name': 'Exp Sweep',
          'desc': 'Best quality',
          'icon': Icons.show_chart,
        };
      case SweepType.mls:
        return {
          'name': 'MLS',
          'desc': 'Fastest',
          'icon': Icons.grid_4x4,
        };
      case SweepType.linearSweep:
        return {
          'name': 'Linear',
          'desc': 'Simple',
          'icon': Icons.trending_up,
        };
      case SweepType.pinkNoise:
        return {
          'name': 'Pink Noise',
          'desc': 'Alternative',
          'icon': Icons.waves,
        };
    }
  }

  Widget _buildGenerateSweepStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle('Generate Test Signal'),
        const SizedBox(height: 16),
        _buildInfoCard(
          Icons.volume_up,
          'Ready to Generate',
          'Click Generate to create the ${_getSweepTypeName(_params.sweepType)} test signal. '
              'This will be played through your speakers to capture the room response.',
        ),
        const SizedBox(height: 20),
        if (_isProcessing) ...[
          _buildProgressBar(),
          const SizedBox(height: 12),
          Text(
            _statusMessage,
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ] else
          Center(
            child: ElevatedButton.icon(
              onPressed: _generateSweep,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Generate Sweep'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle('Record Room Response'),
        const SizedBox(height: 16),
        _buildInfoCard(
          Icons.mic,
          'Recording Setup',
          '1. Position your microphone in the listening position\n'
              '2. Click Record to start playback and capture\n'
              '3. Wait for the sweep to complete\n'
              '4. Recording will stop automatically',
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildRecordButton(),
            const SizedBox(width: 16),
            _buildPlaybackMeter(),
          ],
        ),
      ],
    );
  }

  Widget _buildRecordButton() {
    return GestureDetector(
      onTap: _startRecording,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: _isProcessing ? Colors.red : const Color(0xFF00BCD4),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (_isProcessing ? Colors.red : const Color(0xFF00BCD4))
                  .withOpacity(0.4),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          _isProcessing ? Icons.stop : Icons.fiber_manual_record,
          color: Colors.white,
          size: 40,
        ),
      ),
    );
  }

  Widget _buildPlaybackMeter() {
    return Container(
      width: 200,
      height: 80,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Input Level',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF4CAF50),
                        Color(0xFFFFEB3B),
                        Color(0xFFFF5722),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMeterLabel('-60'),
              _buildMeterLabel('-30'),
              _buildMeterLabel('-12'),
              _buildMeterLabel('0'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeterLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: FluxForgeTheme.textSecondary.withOpacity(0.6),
        fontSize: 8,
      ),
    );
  }

  Widget _buildDeconvolveStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle('Deconvolve Response'),
        const SizedBox(height: 16),
        _buildInfoCard(
          Icons.analytics,
          'Processing',
          'The recorded response will be deconvolved against the original sweep '
              'to extract the impulse response of your space.',
        ),
        const SizedBox(height: 20),
        if (_isProcessing) ...[
          _buildProgressBar(),
          const SizedBox(height: 12),
          Text(
            _statusMessage,
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ] else
          Center(
            child: ElevatedButton.icon(
              onPressed: _deconvolve,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Start Deconvolution'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCleanupStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle('Clean Up IR'),
        const SizedBox(height: 16),
        // IR waveform preview
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Text(
              'IR Waveform Preview',
              style: TextStyle(color: FluxForgeTheme.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildCleanupOption(
                'Trim Start',
                Icons.content_cut,
                '0 ms',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCleanupOption(
                'Trim End',
                Icons.content_cut,
                '2500 ms',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCleanupOption(
                'Fade Out',
                Icons.trending_down,
                '500 ms',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildCheckOption(
          'Normalize',
          'Normalize IR to 0 dBFS peak',
          true,
          (v) {},
        ),
        const SizedBox(height: 8),
        _buildCheckOption(
          'Remove DC',
          'Remove DC offset from IR',
          true,
          (v) {},
        ),
      ],
    );
  }

  Widget _buildCleanupOption(String label, IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: FluxForgeTheme.textSecondary, size: 18),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle('Export Impulse Response'),
        const SizedBox(height: 16),
        _buildInfoCard(
          Icons.check_circle,
          'IR Created Successfully',
          'Your impulse response is ready. Choose a format and location to save it.',
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('Export Format'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildFormatChip('WAV 24-bit', true),
            _buildFormatChip('WAV 32-bit float', false),
            _buildFormatChip('FLAC', false),
            _buildFormatChip('AIFF', false),
          ],
        ),
        const SizedBox(height: 20),
        // IR stats
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Duration', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12)),
                  Text('2.5 seconds', style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12)),
                ],
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Sample Rate', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12)),
                  Text('48 kHz', style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12)),
                ],
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Channels', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12)),
                  Text('Stereo', style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12)),
                ],
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('File Size', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12)),
                  Text('~720 KB', style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormatChip(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00BCD4).withOpacity(0.2)
              : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00BCD4) : FluxForgeTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF00BCD4) : FluxForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildNavigation() {
    final isFirstStep = _currentStep.index == 0;
    final isLastStep = _currentStep.index == WizardStep.values.length - 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          if (!isFirstStep)
            TextButton.icon(
              onPressed: _isProcessing ? null : _previousStep,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back'),
              style: TextButton.styleFrom(
                foregroundColor: FluxForgeTheme.textSecondary,
              ),
            ),
          const Spacer(),
          if (!isLastStep)
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _nextStep,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Next'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4),
                foregroundColor: Colors.white,
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Export IR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: FluxForgeTheme.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: FluxForgeTheme.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF00BCD4).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00BCD4).withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF00BCD4), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParamField(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: FluxForgeTheme.textSecondary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 9,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckOption(String title, String description, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: value ? const Color(0xFF00BCD4).withOpacity(0.1) : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: value ? const Color(0xFF00BCD4).withOpacity(0.5) : FluxForgeTheme.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: value ? const Color(0xFF00BCD4) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: value ? const Color(0xFF00BCD4) : FluxForgeTheme.border,
                ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Column(
      children: [
        LinearProgressIndicator(
          value: _progress,
          backgroundColor: FluxForgeTheme.bgMid,
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00BCD4)),
        ),
        const SizedBox(height: 8),
        Text(
          '${(_progress * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _getSweepTypeName(SweepType type) {
    switch (type) {
      case SweepType.exponentialSweep:
        return 'Exponential Sine Sweep';
      case SweepType.mls:
        return 'Maximum Length Sequence';
      case SweepType.linearSweep:
        return 'Linear Sweep';
      case SweepType.pinkNoise:
        return 'Pink Noise';
    }
  }

  void _nextStep() {
    if (_currentStep.index < WizardStep.values.length - 1) {
      setState(() {
        _currentStep = WizardStep.values[_currentStep.index + 1];
      });
    }
  }

  void _previousStep() {
    if (_currentStep.index > 0) {
      setState(() {
        _currentStep = WizardStep.values[_currentStep.index - 1];
      });
    }
  }

  void _generateSweep() {
    setState(() {
      _isProcessing = true;
      _progress = 0;
      _statusMessage = 'Generating sweep...';
    });
    // Simulate processing
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _progress = 1;
        });
        _nextStep();
      }
    });
  }

  void _startRecording() {
    setState(() {
      _isProcessing = !_isProcessing;
      _statusMessage = _isProcessing ? 'Recording...' : '';
    });
  }

  void _deconvolve() {
    setState(() {
      _isProcessing = true;
      _progress = 0;
      _statusMessage = 'Deconvolving...';
    });
    // Simulate processing
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _progress = 1;
        });
        _nextStep();
      }
    });
  }

  void _export() {
    widget.onIrCreated?.call('/path/to/exported_ir.wav');
    widget.onClose?.call();
  }
}
