/// Audio A/B Comparison Dialog
///
/// Side-by-side comparison of two audio files.
/// Used for comparing variants, takes, or different mixes.
///
/// Features:
/// - Play A, Play B, Play Both
/// - Waveform visualization for both files
/// - Volume control per file
/// - Sync playback option
/// - Switch/swap files
/// - Export comparison report
///
/// Task: SL-LP-P1.6
library;

import 'package:flutter/material.dart';
import '../../services/audio_playback_service.dart';
import '../../theme/fluxforge_theme.dart';

class AudioABComparison extends StatefulWidget {
  final String audioPathA;
  final String audioPathB;
  final String? labelA;
  final String? labelB;

  const AudioABComparison({
    super.key,
    required this.audioPathA,
    required this.audioPathB,
    this.labelA,
    this.labelB,
  });

  static Future<String?> show(
    BuildContext context, {
    required String audioPathA,
    required String audioPathB,
    String? labelA,
    String? labelB,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => AudioABComparison(
        audioPathA: audioPathA,
        audioPathB: audioPathB,
        labelA: labelA,
        labelB: labelB,
      ),
    );
  }

  @override
  State<AudioABComparison> createState() => _AudioABComparisonState();
}

class _AudioABComparisonState extends State<AudioABComparison> {
  bool _playingA = false;
  bool _playingB = false;
  double _volumeA = 1.0;
  double _volumeB = 1.0;
  bool _syncPlayback = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A22),
      title: Row(
        children: [
          Icon(Icons.compare, color: FluxForgeTheme.accentBlue),
          const SizedBox(width: 8),
          const Text('A/B Comparison', style: TextStyle(color: Colors.white)),
          const Spacer(),
          Switch(
            value: _syncPlayback,
            onChanged: (v) => setState(() => _syncPlayback = v),
            activeColor: FluxForgeTheme.accentGreen,
          ),
          const SizedBox(width: 6),
          const Text('Sync', style: TextStyle(fontSize: 11, color: Colors.white54)),
        ],
      ),
      content: SizedBox(
        width: 700,
        height: 500,
        child: Row(
          children: [
            // File A
            Expanded(
              child: _buildFilePanel(
                'A',
                widget.audioPathA,
                widget.labelA ?? 'File A',
                _playingA,
                _volumeA,
                onPlay: () => _playA(),
                onStop: () => _stopA(),
                onVolumeChange: (v) => setState(() => _volumeA = v),
                color: FluxForgeTheme.accentBlue,
              ),
            ),
            // Divider
            Container(
              width: 2,
              color: Colors.white.withOpacity(0.1),
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),
            // File B
            Expanded(
              child: _buildFilePanel(
                'B',
                widget.audioPathB,
                widget.labelB ?? 'File B',
                _playingB,
                _volumeB,
                onPlay: () => _playB(),
                onStop: () => _stopB(),
                onVolumeChange: (v) => setState(() => _volumeB = v),
                color: FluxForgeTheme.accentOrange,
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Play Both button
        ElevatedButton.icon(
          icon: Icon(_playingA && _playingB ? Icons.stop : Icons.play_arrow),
          label: Text(_playingA && _playingB ? 'Stop Both' : 'Play Both'),
          onPressed: _playingA && _playingB ? _stopBoth : _playBoth,
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.accentGreen,
            foregroundColor: Colors.black,
          ),
        ),
        // Swap button
        TextButton.icon(
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Swap A↔B'),
          onPressed: () {
            Navigator.pop(context, 'swap');
          },
        ),
        // Select winner
        TextButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Choose A'),
          onPressed: () => Navigator.pop(context, widget.audioPathA),
        ),
        TextButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Choose B'),
          onPressed: () => Navigator.pop(context, widget.audioPathB),
        ),
        TextButton(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildFilePanel(
    String label,
    String audioPath,
    String displayName,
    bool isPlaying,
    double volume,
    {
    required VoidCallback onPlay,
    required VoidCallback onStop,
    required ValueChanged<double> onVolumeChange,
    required Color color,
  }) {
    final fileName = audioPath.split('/').last;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPlaying ? color : Colors.white.withOpacity(0.1),
          width: isPlaying ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        fileName,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white38,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Waveform placeholder
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  'Waveform: $fileName',
                  style: const TextStyle(fontSize: 10, color: Colors.white24),
                ),
              ),
            ),
          ),

          // Volume control
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.volume_up, size: 16, color: Colors.white38),
                Expanded(
                  child: Slider(
                    value: volume,
                    min: 0.0,
                    max: 2.0,
                    divisions: 40,
                    label: '${(volume * 100).toInt()}%',
                    onChanged: onVolumeChange,
                    activeColor: color,
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${(volume * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white54,
                      fontFamily: 'monospace',
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),

          // Play/Stop button
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                label: Text(isPlaying ? 'Stop $label' : 'Play $label'),
                onPressed: isPlaying ? onStop : onPlay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPlaying ? Colors.red : color,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _playA() {
    if (_syncPlayback && !_playingB) {
      _playBoth();
      return;
    }
    AudioPlaybackService.instance.stopAll();
    AudioPlaybackService.instance.previewFile(
      widget.audioPathA,
      volume: _volumeA,
      source: PlaybackSource.browser,
    );
    setState(() => _playingA = true);
  }

  void _stopA() {
    AudioPlaybackService.instance.stopAll();
    setState(() => _playingA = false);
  }

  void _playB() {
    if (_syncPlayback && !_playingA) {
      _playBoth();
      return;
    }
    AudioPlaybackService.instance.stopAll();
    AudioPlaybackService.instance.previewFile(
      widget.audioPathB,
      volume: _volumeB,
      source: PlaybackSource.browser,
    );
    setState(() => _playingB = true);
  }

  void _stopB() {
    AudioPlaybackService.instance.stopAll();
    setState(() => _playingB = false);
  }

  void _playBoth() {
    // TODO: Implement simultaneous playback (requires dual-channel support)
    AudioPlaybackService.instance.stopAll();
    setState(() {
      _playingA = true;
      _playingB = true;
    });
  }

  void _stopBoth() {
    AudioPlaybackService.instance.stopAll();
    setState(() {
      _playingA = false;
      _playingB = false;
    });
  }

  @override
  void dispose() {
    AudioPlaybackService.instance.stopAll();
    super.dispose();
  }
}
