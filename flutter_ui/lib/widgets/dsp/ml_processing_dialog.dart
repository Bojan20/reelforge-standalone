/// FluxForge Studio ML Processing Dialog
///
/// Dialog for ML/AI audio processing:
/// - Stem separation (vocals, drums, bass, other)
/// - AI denoising
/// - Voice enhancement
/// - Progress tracking

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../providers/ml_provider.dart';

/// ML Processing type
enum MlProcessingType {
  denoise,
  stemSeparation,
  voiceEnhancement,
}

/// ML Processing Dialog
class MlProcessingDialog extends StatefulWidget {
  /// Input file path
  final String inputPath;

  /// Output path (file or directory)
  final String outputPath;

  /// Processing type
  final MlProcessingType type;

  /// Callback when processing completes
  final VoidCallback? onComplete;

  const MlProcessingDialog({
    super.key,
    required this.inputPath,
    required this.outputPath,
    this.type = MlProcessingType.stemSeparation,
    this.onComplete,
  });

  @override
  State<MlProcessingDialog> createState() => _MlProcessingDialogState();

  /// Show the dialog
  static Future<bool?> show(
    BuildContext context, {
    required String inputPath,
    required String outputPath,
    MlProcessingType type = MlProcessingType.stemSeparation,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MlProcessingDialog(
        inputPath: inputPath,
        outputPath: outputPath,
        type: type,
      ),
    );
  }
}

class _MlProcessingDialogState extends State<MlProcessingDialog> {
  Timer? _progressTimer;
  bool _started = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _startProcessing();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _startProcessing() async {
    if (_started) return;
    _started = true;

    final provider = context.read<MlProvider>();

    // Start progress polling
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });

    bool success = false;

    switch (widget.type) {
      case MlProcessingType.denoise:
        success = await provider.startDenoise(
          widget.inputPath,
          widget.outputPath,
        );
      case MlProcessingType.stemSeparation:
        success = await provider.startStemSeparation(
          widget.inputPath,
          widget.outputPath,
        );
      case MlProcessingType.voiceEnhancement:
        success = await provider.startVoiceEnhancement(
          widget.inputPath,
          widget.outputPath,
        );
    }

    _progressTimer?.cancel();

    if (mounted) {
      setState(() => _completed = true);

      if (success) {
        widget.onComplete?.call();
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.of(context).pop(true);
      }
    }
  }

  void _cancel() {
    final provider = context.read<MlProvider>();
    provider.cancel();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MlProvider>(
      builder: (context, provider, _) {
        return Dialog(
          backgroundColor: FluxForgeTheme.bgDeep,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.3)),
          ),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildProgressSection(provider),
                const SizedBox(height: 24),
                _buildActions(provider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    IconData icon;
    String title;

    switch (widget.type) {
      case MlProcessingType.denoise:
        icon = Icons.noise_control_off;
        title = 'AI Denoising';
      case MlProcessingType.stemSeparation:
        icon = Icons.call_split;
        title = 'Stem Separation';
      case MlProcessingType.voiceEnhancement:
        icon = Icons.record_voice_over;
        title = 'Voice Enhancement';
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentCyan.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: FluxForgeTheme.accentCyan, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _getFileName(widget.inputPath),
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressSection(MlProvider provider) {
    final progress = provider.progress;
    final phase = provider.phase;
    final model = provider.currentModel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Model info
        if (model.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.memory, size: 14, color: FluxForgeTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Model: $model',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: provider.isProcessing ? progress : (_completed ? 1.0 : null),
            backgroundColor: FluxForgeTheme.bgSurface,
            valueColor: AlwaysStoppedAnimation(
              provider.hasError
                  ? FluxForgeTheme.accentRed
                  : (_completed ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentCyan),
            ),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 12),

        // Status text
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                provider.hasError
                    ? (provider.errorMessage ?? 'Processing failed')
                    : (_completed ? 'Complete!' : phase),
                style: TextStyle(
                  color: provider.hasError
                      ? FluxForgeTheme.accentRed
                      : (_completed ? FluxForgeTheme.accentGreen : FluxForgeTheme.textPrimary),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(
                color: FluxForgeTheme.accentCyan,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        // Stem separation specific - show output stems
        if (widget.type == MlProcessingType.stemSeparation && _completed && !provider.hasError) ...[
          const SizedBox(height: 16),
          _buildStemOutput(),
        ],
      ],
    );
  }

  Widget _buildStemOutput() {
    final stems = ['vocals', 'drums', 'bass', 'other'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.accentGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 14, color: FluxForgeTheme.accentGreen),
              const SizedBox(width: 6),
              Text(
                'Output Stems',
                style: TextStyle(
                  color: FluxForgeTheme.accentGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: stems.map((stem) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getStemIcon(stem),
                      size: 12,
                      color: _getStemColor(stem),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      stem,
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  IconData _getStemIcon(String stem) {
    switch (stem) {
      case 'vocals':
        return Icons.mic;
      case 'drums':
        return Icons.album;
      case 'bass':
        return Icons.graphic_eq;
      case 'other':
        return Icons.music_note;
      default:
        return Icons.audio_file;
    }
  }

  Color _getStemColor(String stem) {
    switch (stem) {
      case 'vocals':
        return FluxForgeTheme.accentOrange;
      case 'drums':
        return FluxForgeTheme.accentRed;
      case 'bass':
        return FluxForgeTheme.accentCyan;
      case 'other':
        return FluxForgeTheme.accentGreen;
      default:
        return FluxForgeTheme.textSecondary;
    }
  }

  Widget _buildActions(MlProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!_completed)
          TextButton(
            onPressed: _cancel,
            child: Text(
              'Cancel',
              style: TextStyle(color: FluxForgeTheme.textSecondary),
            ),
          ),
        if (_completed) ...[
          if (provider.hasError)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Close',
                style: TextStyle(color: FluxForgeTheme.textSecondary),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Done'),
              style: ElevatedButton.styleFrom(
                backgroundColor: FluxForgeTheme.accentGreen,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ],
    );
  }

  String _getFileName(String path) {
    final parts = path.split('/');
    return parts.isNotEmpty ? parts.last : path;
  }
}
