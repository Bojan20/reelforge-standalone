/// Recording Panel
///
/// Displays:
/// - Armed tracks list
/// - Record/Stop global controls
/// - Output directory picker
/// - Recording status & indicators
/// - Real-time recording meters

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/recording_provider.dart';
// import '../../providers/track_provider.dart';  // TODO: Create TrackProvider
import '../../theme/fluxforge_theme.dart';

class RecordingPanel extends StatefulWidget {
  const RecordingPanel({super.key});

  @override
  State<RecordingPanel> createState() => _RecordingPanelState();
}

class _RecordingPanelState extends State<RecordingPanel> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Initialize recording system
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecordingProvider>().initialize();
    });

    // Refresh at 10 Hz
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        context.read<RecordingProvider>().refresh();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RecordingProvider>(
      builder: (context, recording, _) {
        return Container(
          color: FluxForgeTheme.bgDeep,
          child: Column(
            children: [
              // Header with global controls
              _buildHeader(recording),

              // Armed tracks list
              Expanded(
                child: _buildArmedTracksList(recording),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(RecordingProvider recording) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.bgSurface, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title & status
          Row(
            children: [
              const Text(
                'RECORDING',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 12),
              if (recording.isRecording)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentRed,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'REC',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              Text(
                '${recording.armedCount} armed · ${recording.recordingCount} recording',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Output directory
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxForgeTheme.bgSurface),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 14,
                        color: FluxForgeTheme.textSecondary.withOpacity(0.7),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          recording.outputDir.isEmpty ? 'No output directory' : recording.outputDir,
                          style: TextStyle(
                            color: FluxForgeTheme.textSecondary,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.folder_open, size: 16),
                color: FluxForgeTheme.accentBlue,
                tooltip: 'Choose Output Directory',
                onPressed: () => _selectOutputDirectory(recording),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Global record controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Record button
              ElevatedButton.icon(
                onPressed: recording.armedCount > 0 && !recording.isRecording
                    ? () => recording.startRecording()
                    : null,
                icon: const Icon(Icons.fiber_manual_record, size: 18),
                label: const Text('RECORD'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FluxForgeTheme.accentRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Stop button
              ElevatedButton.icon(
                onPressed: recording.isRecording
                    ? () => recording.stopRecording()
                    : null,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('STOP'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FluxForgeTheme.bgSurface,
                  foregroundColor: FluxForgeTheme.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Clear all button
              IconButton(
                icon: const Icon(Icons.clear_all, size: 18),
                color: FluxForgeTheme.textSecondary,
                tooltip: 'Clear All',
                onPressed: recording.armedCount > 0 && !recording.isRecording
                    ? () => recording.clearAll()
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArmedTracksList(RecordingProvider recording) {
    if (recording.armedCount == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mic_none,
              size: 64,
              color: FluxForgeTheme.textSecondary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No Armed Tracks',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary.withOpacity(0.6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Arm tracks from the mixer or timeline to start recording',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary.withOpacity(0.5),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // TODO: Replace with actual track list from TrackProvider
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: recording.armedCount,
      itemBuilder: (context, index) {
        // Mock track data until TrackProvider is implemented
        return _ArmedTrackItem(
          trackId: index,
          trackName: 'Track ${index + 1}',
          trackColor: FluxForgeTheme.accentBlue,
          isRecording: recording.isRecording,
          recordingPath: recording.getRecordingPath(index),
          onDisarm: () => recording.disarmTrack(index),
        );
      },
    );
  }

  Future<void> _selectOutputDirectory(RecordingProvider recording) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Recording Output Directory',
      initialDirectory: recording.outputDir,
    );

    if (result != null && mounted) {
      await recording.setOutputDir(result);
    }
  }
}

class _ArmedTrackItem extends StatelessWidget {
  final int trackId;
  final String trackName;
  final Color trackColor;
  final bool isRecording;
  final String? recordingPath;
  final VoidCallback onDisarm;

  const _ArmedTrackItem({
    required this.trackId,
    required this.trackName,
    required this.trackColor,
    required this.isRecording,
    this.recordingPath,
    required this.onDisarm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isRecording
              ? FluxForgeTheme.accentRed.withOpacity(0.5)
              : FluxForgeTheme.bgSurface,
          width: isRecording ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          // Track color indicator
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),

          // Track info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      trackName,
                      style: const TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isRecording)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentRed,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'REC',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  recordingPath ?? 'Ready to record',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary.withOpacity(0.7),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Disarm button
          IconButton(
            icon: Icon(
              Icons.radio_button_checked,
              size: 20,
              color: isRecording
                  ? FluxForgeTheme.accentRed
                  : FluxForgeTheme.accentOrange,
            ),
            tooltip: 'Disarm Track',
            onPressed: isRecording ? null : onDisarm,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}
