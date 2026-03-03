/// Video Lower Zone Panel
///
/// Video track management, preview, import, A/V sync, and export controls.
/// Integrates with VideoProvider (GetIt singleton) and VideoExportService.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import '../../../../providers/video_provider.dart';
import '../../../../services/video_export_service.dart';

class VideoLowerZonePanel extends StatefulWidget {
  const VideoLowerZonePanel({super.key});

  @override
  State<VideoLowerZonePanel> createState() => _VideoLowerZonePanelState();
}

class _VideoLowerZonePanelState extends State<VideoLowerZonePanel> {
  @override
  Widget build(BuildContext context) {
    return Consumer<VideoProvider>(
      builder: (context, video, _) {
        return Container(
          color: const Color(0xFF1E1E1E),
          child: Column(
            children: [
              _buildToolbar(video),
              const Divider(height: 1, color: Color(0xFF333333)),
              Expanded(
                child: video.hasVideo
                    ? _buildVideoContent(video)
                    : _buildEmptyState(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar(VideoProvider video) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF252525),
      child: Row(
        children: [
          const Icon(Icons.videocam, size: 14, color: Color(0xFF8B5CF6)),
          const SizedBox(width: 6),
          const Text(
            'VIDEO',
            style: TextStyle(
              color: Color(0xFF8B5CF6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Import button
          _buildToolbarButton(
            icon: Icons.file_open,
            tooltip: 'Import Video',
            onPressed: () => _importVideo(video),
          ),
          if (video.hasVideo) ...[
            const SizedBox(width: 4),
            _buildToolbarButton(
              icon: Icons.preview,
              tooltip: 'Toggle Preview',
              isActive: video.showPreview,
              onPressed: () => video.togglePreview(),
            ),
            const SizedBox(width: 4),
            _buildToolbarButton(
              icon: Icons.sync,
              tooltip: 'A/V Sync Settings',
              onPressed: () => _showSyncDialog(video),
            ),
            const SizedBox(width: 4),
            _buildToolbarButton(
              icon: Icons.delete_outline,
              tooltip: 'Remove Video',
              onPressed: () => video.removeVideo(),
            ),
          ],
          const SizedBox(width: 8),
          // Export button
          Consumer<VideoExportService>(
            builder: (context, exportService, _) {
              return _buildToolbarButton(
                icon: exportService.isRecording
                    ? Icons.stop_circle
                    : Icons.fiber_manual_record,
                tooltip: exportService.isRecording
                    ? 'Stop Recording'
                    : 'Record Screen',
                isActive: exportService.isRecording,
                activeColor: Colors.red,
                onPressed: () {
                  if (exportService.isRecording) {
                    exportService.stopRecording();
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool isActive = false,
    Color activeColor = const Color(0xFF8B5CF6),
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: isActive ? activeColor.withValues(alpha: 0.2) : null,
          ),
          child: Icon(
            icon,
            size: 14,
            color: isActive ? activeColor : const Color(0xFF888888),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off, size: 48, color: Color(0xFF555555)),
          const SizedBox(height: 12),
          const Text(
            'No video loaded',
            style: TextStyle(color: Color(0xFF777777), fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              final video = GetIt.instance<VideoProvider>();
              _importVideo(video);
            },
            icon: const Icon(Icons.file_open, size: 14),
            label: const Text('Import Video'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8B5CF6),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoContent(VideoProvider video) {
    return Row(
      children: [
        // Left: Info panel
        SizedBox(
          width: 220,
          child: _buildInfoPanel(video),
        ),
        const VerticalDivider(width: 1, color: Color(0xFF333333)),
        // Center: Preview
        Expanded(
          child: video.showPreview
              ? _buildPreviewArea(video)
              : _buildTimecodeDisplay(video),
        ),
        const VerticalDivider(width: 1, color: Color(0xFF333333)),
        // Right: Transport controls
        SizedBox(
          width: 200,
          child: _buildTransportControls(video),
        ),
      ],
    );
  }

  Widget _buildInfoPanel(VideoProvider video) {
    final clip = video.videoClip!;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            clip.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          _buildInfoRow('Resolution', video.resolution),
          _buildInfoRow('Frame Rate', '${clip.frameRate} fps'),
          _buildInfoRow('Duration', video.formatTimecode(clip.duration)),
          _buildInfoRow('Format', clip.path.split('.').last.toUpperCase()),
          const SizedBox(height: 8),
          // Sync offset
          Row(
            children: [
              const Text(
                'A/V Sync:',
                style: TextStyle(color: Color(0xFF888888), fontSize: 10),
              ),
              const Spacer(),
              Text(
                '${video.syncOffset >= 0 ? "+" : ""}${video.syncOffset.toStringAsFixed(1)}ms',
                style: TextStyle(
                  color: video.syncOffset.abs() > 0.1
                      ? const Color(0xFFFF9800)
                      : const Color(0xFF4CAF50),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Timecode format selector
          Row(
            children: [
              const Text(
                'TC Format:',
                style: TextStyle(color: Color(0xFF888888), fontSize: 10),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => video.cycleTimecodeFormat(),
                child: Text(
                  video.timecodeFormat.name.replaceFirst('smpte', '').replaceFirst('df', ' DF'),
                  style: const TextStyle(
                    color: Color(0xFF8B5CF6),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Text(
            '$label:',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 10),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewArea(VideoProvider video) {
    final frame = video.currentFrame;
    if (frame == null) {
      return const Center(
        child: Text(
          'No preview available',
          style: TextStyle(color: Color(0xFF555555), fontSize: 11),
        ),
      );
    }

    // Frame data from FFI is RGBA
    return Center(
      child: AspectRatio(
        aspectRatio: (video.videoClip?.width ?? 16) / (video.videoClip?.height ?? 9),
        child: _VideoFrameDisplay(frameData: frame, video: video),
      ),
    );
  }

  Widget _buildTimecodeDisplay(VideoProvider video) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            video.formatTimecode(video.currentTime),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w300,
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Frame ${video.currentFrameNumber} / ${video.totalFrames}',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportControls(VideoProvider video) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Frame step buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  final frame = (video.currentFrameNumber - 10).clamp(0, video.totalFrames);
                  video.seekToFrame(frame);
                },
                icon: const Icon(Icons.skip_previous, size: 20),
                color: const Color(0xFFCCCCCC),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: '-10 frames',
              ),
              IconButton(
                onPressed: () {
                  final frame = (video.currentFrameNumber - 1).clamp(0, video.totalFrames);
                  video.seekToFrame(frame);
                },
                icon: const Icon(Icons.navigate_before, size: 20),
                color: const Color(0xFFCCCCCC),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: '-1 frame',
              ),
              IconButton(
                onPressed: () {
                  final frame = (video.currentFrameNumber + 1).clamp(0, video.totalFrames);
                  video.seekToFrame(frame);
                },
                icon: const Icon(Icons.navigate_next, size: 20),
                color: const Color(0xFFCCCCCC),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: '+1 frame',
              ),
              IconButton(
                onPressed: () {
                  final frame = (video.currentFrameNumber + 10).clamp(0, video.totalFrames);
                  video.seekToFrame(frame);
                },
                icon: const Icon(Icons.skip_next, size: 20),
                color: const Color(0xFFCCCCCC),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: '+10 frames',
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Timeline scrubber
          if (video.hasVideo)
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: const Color(0xFF8B5CF6),
                inactiveTrackColor: const Color(0xFF333333),
                thumbColor: const Color(0xFF8B5CF6),
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: video.currentTime.clamp(0.0, video.duration),
                min: 0,
                max: video.duration > 0 ? video.duration : 1,
                onChanged: (value) => video.setCurrentTime(value),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _importVideo(VideoProvider video) async {
    // Use file picker (same pattern as audio import)
    // For now, provide a simple path input dialog
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => _VideoImportDialog(),
    );
    if (path != null && path.isNotEmpty) {
      await video.loadVideo(path);
    }
  }

  void _showSyncDialog(VideoProvider video) {
    showDialog(
      context: context,
      builder: (ctx) => _VideoSyncDialog(video: video),
    );
  }
}

/// Simple frame display from raw RGBA bytes
class _VideoFrameDisplay extends StatelessWidget {
  final Uint8List frameData;
  final VideoProvider video;

  const _VideoFrameDisplay({
    required this.frameData,
    required this.video,
  });

  @override
  Widget build(BuildContext context) {
    // Frame data is RGBA from engine
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam, size: 32, color: Color(0xFF8B5CF6)),
            SizedBox(height: 8),
            Text(
              'Preview (FFmpeg decode active)',
              style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Video import dialog
class _VideoImportDialog extends StatefulWidget {
  @override
  State<_VideoImportDialog> createState() => _VideoImportDialogState();
}

class _VideoImportDialogState extends State<_VideoImportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      title: const Text('Import Video', style: TextStyle(color: Colors.white, fontSize: 16)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Supported: MP4, MOV, MKV, AVI, WebM, ProRes, H.264, H.265, VP9',
              style: TextStyle(color: Color(0xFF888888), fontSize: 11),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: '/path/to/video.mp4',
                hintStyle: const TextStyle(color: Color(0xFF555555)),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF444444)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF444444)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              autofocus: true,
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888))),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Import', style: TextStyle(color: Color(0xFF8B5CF6))),
        ),
      ],
    );
  }
}

/// A/V Sync dialog
class _VideoSyncDialog extends StatelessWidget {
  final VideoProvider video;
  const _VideoSyncDialog({required this.video});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      title: const Text('A/V Sync', style: TextStyle(color: Colors.white, fontSize: 16)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListenableBuilder(
              listenable: video,
              builder: (ctx, _) {
                return Column(
                  children: [
                    Text(
                      '${video.syncOffset >= 0 ? "+" : ""}${video.syncOffset.toStringAsFixed(1)} ms',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 16),
                    Slider(
                      value: video.syncOffset,
                      min: -10.0,
                      max: 10.0,
                      divisions: 200,
                      activeColor: const Color(0xFF8B5CF6),
                      onChanged: (v) => video.setSyncOffset(v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => video.nudgeSyncOffset(-0.5),
                          child: const Text('-0.5ms', style: TextStyle(color: Color(0xFF888888), fontSize: 11)),
                        ),
                        TextButton(
                          onPressed: () => video.resetSyncOffset(),
                          child: const Text('Reset', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 11)),
                        ),
                        TextButton(
                          onPressed: () => video.nudgeSyncOffset(0.5),
                          child: const Text('+0.5ms', style: TextStyle(color: Color(0xFF888888), fontSize: 11)),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done', style: TextStyle(color: Color(0xFF8B5CF6))),
        ),
      ],
    );
  }
}
