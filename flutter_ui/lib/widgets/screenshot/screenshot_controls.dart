/// Screenshot Controls Widget
///
/// UI controls for screenshot capture in SlotLab:
/// - Quick capture button
/// - Settings panel (format, quality)
/// - History panel with thumbnails
/// - Keyboard shortcut support
///
/// Created: 2026-01-30 (P4.16)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../services/screenshot_service.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SCREENSHOT BUTTON
// ═══════════════════════════════════════════════════════════════════════════

/// Quick screenshot capture button
class ScreenshotButton extends StatefulWidget {
  final GlobalKey? targetKey;
  final VoidCallback? onCaptured;
  final bool showTooltip;

  const ScreenshotButton({
    super.key,
    this.targetKey,
    this.onCaptured,
    this.showTooltip = true,
  });

  @override
  State<ScreenshotButton> createState() => _ScreenshotButtonState();
}

class _ScreenshotButtonState extends State<ScreenshotButton> {
  bool _isCapturing = false;

  Future<void> _capture() async {
    if (_isCapturing || widget.targetKey == null) return;

    setState(() => _isCapturing = true);

    try {
      final boundary = widget.targetKey!.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null) {
        _showError('Could not find target widget');
        return;
      }

      final result = await ScreenshotService.instance.captureWidget(boundary);

      if (result.success) {
        widget.onCaptured?.call();
        _showSuccess(result);
      } else {
        _showError(result.error ?? 'Unknown error');
      }
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  void _showSuccess(ScreenshotResult result) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF40FF90)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Screenshot saved (${result.sizeString})',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: () => ScreenshotService.instance.openScreenshotsFolder(),
              child: const Text('Open Folder'),
            ),
          ],
        ),
        backgroundColor: FluxForgeTheme.bgSurface,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showError(String error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Screenshot failed: $error'),
        backgroundColor: const Color(0xFFFF4060),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      icon: _isCapturing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.camera_alt, size: 18),
      onPressed: _isCapturing ? null : _capture,
      color: Colors.white70,
    );

    if (widget.showTooltip) {
      return Tooltip(
        message: 'Take Screenshot (⌘+Shift+S)',
        child: button,
      );
    }
    return button;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SCREENSHOT SETTINGS PANEL
// ═══════════════════════════════════════════════════════════════════════════

/// Settings panel for screenshot configuration
class ScreenshotSettingsPanel extends StatefulWidget {
  final VoidCallback? onConfigChanged;

  const ScreenshotSettingsPanel({
    super.key,
    this.onConfigChanged,
  });

  @override
  State<ScreenshotSettingsPanel> createState() => _ScreenshotSettingsPanelState();
}

class _ScreenshotSettingsPanelState extends State<ScreenshotSettingsPanel> {
  late ScreenshotConfig _config;

  @override
  void initState() {
    super.initState();
    _config = ScreenshotService.instance.config;
  }

  void _updateConfig(ScreenshotConfig newConfig) {
    setState(() {
      _config = newConfig;
      ScreenshotService.instance.setConfig(newConfig);
    });
    widget.onConfigChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border.all(color: FluxForgeTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.camera_alt, size: 16, color: Color(0xFF4A9EFF)),
              const SizedBox(width: 8),
              const Text(
                'SCREENSHOT SETTINGS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Format dropdown
          _buildDropdown<ScreenshotFormat>(
            label: 'Format',
            value: _config.format,
            items: ScreenshotFormat.values,
            itemLabel: (f) => f.label,
            onChanged: (f) => _updateConfig(_config.copyWith(format: f)),
          ),
          const SizedBox(height: 8),

          // Quality dropdown
          _buildDropdown<ScreenshotQuality>(
            label: 'Quality',
            value: _config.quality,
            items: ScreenshotQuality.values,
            itemLabel: (q) => '${q.label} (${q.pixelRatio}x)',
            onChanged: (q) => _updateConfig(_config.copyWith(quality: q)),
          ),
          const SizedBox(height: 12),

          // Toggles
          _buildToggle(
            'Include timestamp',
            _config.includeTimestamp,
            (v) => _updateConfig(_config.copyWith(includeTimestamp: v)),
          ),
          const SizedBox(height: 4),
          _buildToggle(
            'Hide UI elements',
            _config.hideUI,
            (v) => _updateConfig(_config.copyWith(hideUI: v)),
          ),

          const SizedBox(height: 12),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),

          // Open folder button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Open Screenshots Folder'),
              onPressed: () => ScreenshotService.instance.openScreenshotsFolder(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: FluxForgeTheme.border),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required void Function(T?) onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              border: Border.all(color: FluxForgeTheme.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isDense: true,
                isExpanded: true,
                dropdownColor: FluxForgeTheme.bgSurface,
                style: const TextStyle(fontSize: 11, color: Colors.white),
                items: items.map((item) {
                  return DropdownMenuItem<T>(
                    value: item,
                    child: Text(itemLabel(item)),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggle(String label, bool value, void Function(bool) onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SCREENSHOT HISTORY PANEL
// ═══════════════════════════════════════════════════════════════════════════

/// Panel showing recent screenshots with thumbnails
class ScreenshotHistoryPanel extends StatefulWidget {
  const ScreenshotHistoryPanel({super.key});

  @override
  State<ScreenshotHistoryPanel> createState() => _ScreenshotHistoryPanelState();
}

class _ScreenshotHistoryPanelState extends State<ScreenshotHistoryPanel> {
  @override
  Widget build(BuildContext context) {
    final history = ScreenshotService.instance.history;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border.all(color: FluxForgeTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.history, size: 16, color: Color(0xFF40C8FF)),
              const SizedBox(width: 8),
              const Text(
                'SCREENSHOT HISTORY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (history.isNotEmpty)
                TextButton(
                  onPressed: () {
                    ScreenshotService.instance.clearHistory();
                    setState(() {});
                  },
                  child: const Text('Clear', style: TextStyle(fontSize: 10)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // History list
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No screenshots yet',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ),
            )
          else
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final result = history[index];
                  return _buildHistoryItem(result);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(ScreenshotResult result) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgMid,
                border: Border.all(color: FluxForgeTheme.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: result.filePath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        File(result.filePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.white38),
                        ),
                      ),
                    )
                  : const Center(
                      child: Icon(Icons.image, color: Colors.white38),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          // Info
          Text(
            result.sizeString,
            style: const TextStyle(fontSize: 9, color: Colors.white54),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            result.fileSizeString,
            style: const TextStyle(fontSize: 9, color: Colors.white38),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SCREENSHOT MODE OVERLAY
// ═══════════════════════════════════════════════════════════════════════════

/// Full-screen overlay for screenshot mode
class ScreenshotModeOverlay extends StatefulWidget {
  final GlobalKey targetKey;
  final VoidCallback onClose;

  const ScreenshotModeOverlay({
    super.key,
    required this.targetKey,
    required this.onClose,
  });

  @override
  State<ScreenshotModeOverlay> createState() => _ScreenshotModeOverlayState();
}

class _ScreenshotModeOverlayState extends State<ScreenshotModeOverlay> {
  bool _isCapturing = false;
  ScreenshotResult? _lastResult;

  Future<void> _capture() async {
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      final boundary = widget.targetKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null) {
        _showError('Could not find target widget');
        return;
      }

      final result = await ScreenshotService.instance.captureWidget(boundary);

      setState(() => _lastResult = result);

      if (!result.success) {
        _showError(result.error ?? 'Unknown error');
      }
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  void _showError(String error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Screenshot failed: $error'),
        backgroundColor: const Color(0xFFFF4060),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: Stack(
        children: [
          // Content area
          Positioned.fill(
            child: Column(
              children: [
                // Top bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: FluxForgeTheme.bgDeep,
                  child: Row(
                    children: [
                      const Icon(Icons.camera_alt, color: Color(0xFF4A9EFF)),
                      const SizedBox(width: 12),
                      const Text(
                        'SCREENSHOT MODE',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const Spacer(),
                      // Capture button
                      ElevatedButton.icon(
                        icon: _isCapturing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.camera),
                        label: Text(_isCapturing ? 'Capturing...' : 'Capture'),
                        onPressed: _isCapturing ? null : _capture,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4A9EFF),
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Close button
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: widget.onClose,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),

                // Main content
                Expanded(
                  child: Row(
                    children: [
                      // Settings panel
                      Container(
                        width: 220,
                        padding: const EdgeInsets.all(12),
                        color: FluxForgeTheme.bgSurface,
                        child: Column(
                          children: [
                            const ScreenshotSettingsPanel(),
                            const SizedBox(height: 12),
                            const Expanded(child: ScreenshotHistoryPanel()),
                          ],
                        ),
                      ),

                      // Preview area
                      Expanded(
                        child: Container(
                          color: FluxForgeTheme.bgDeep,
                          child: Center(
                            child: _lastResult != null && _lastResult!.success
                                ? _buildPreview(_lastResult!)
                                : _buildPlaceholder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.camera_alt_outlined,
          size: 64,
          color: Colors.white.withAlpha(50),
        ),
        const SizedBox(height: 16),
        Text(
          'Click "Capture" to take a screenshot',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withAlpha(100),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Keyboard shortcut: ⌘+Shift+S',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withAlpha(60),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(ScreenshotResult result) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Preview image
        Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 400),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF40FF90), width: 2),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF40FF90).withAlpha(50),
                blurRadius: 20,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(result.filePath!),
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Info
        Text(
          'Saved: ${result.sizeString} • ${result.fileSizeString}',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 8),

        // Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Open Folder'),
              onPressed: () => ScreenshotService.instance.openScreenshotsFolder(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.camera_alt, size: 16),
              label: const Text('Capture Another'),
              onPressed: _capture,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4A9EFF),
                side: const BorderSide(color: Color(0xFF4A9EFF)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
