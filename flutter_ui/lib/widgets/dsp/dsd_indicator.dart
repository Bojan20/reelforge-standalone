/// DSD Format Indicator Widget
///
/// Shows current DSD playback status in transport bar:
/// - DSD64/128/256/512 rate indicator
/// - DoP mode indicator
/// - Native DSD vs PCM conversion status

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

/// DSD playback rate
enum DsdRate {
  none,
  dsd64,
  dsd128,
  dsd256,
  dsd512,
}

/// DSD playback mode
enum DsdPlaybackMode {
  /// No DSD content
  none,
  /// Native DSD output (ASIO DSD)
  native,
  /// DSD over PCM (DoP)
  dop,
  /// Converted to PCM for playback
  pcmConversion,
}

/// DSD indicator for transport bar
class DsdIndicator extends StatelessWidget {
  /// Current DSD rate
  final DsdRate rate;

  /// Playback mode
  final DsdPlaybackMode mode;

  /// Whether DSD file is loaded
  final bool isDsdLoaded;

  /// Callback when tapped (shows settings)
  final VoidCallback? onTap;

  const DsdIndicator({
    super.key,
    this.rate = DsdRate.none,
    this.mode = DsdPlaybackMode.none,
    this.isDsdLoaded = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!isDsdLoaded && rate == DsdRate.none) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _getRateColor().withOpacity(0.3),
              _getRateColor().withOpacity(0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _getRateColor().withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // DSD Logo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: _getRateColor(),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Text(
                'DSD',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Rate indicator
            Text(
              _getRateLabel(),
              style: TextStyle(
                color: _getRateColor(),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),

            // Mode indicator
            if (mode != DsdPlaybackMode.none) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: ReelForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  _getModeLabel(),
                  style: TextStyle(
                    color: _getModeColor(),
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getRateLabel() {
    switch (rate) {
      case DsdRate.none:
        return '---';
      case DsdRate.dsd64:
        return '64';
      case DsdRate.dsd128:
        return '128';
      case DsdRate.dsd256:
        return '256';
      case DsdRate.dsd512:
        return '512';
    }
  }

  Color _getRateColor() {
    switch (rate) {
      case DsdRate.none:
        return ReelForgeTheme.textSecondary;
      case DsdRate.dsd64:
        return const Color(0xFF4FC3F7); // Light blue
      case DsdRate.dsd128:
        return const Color(0xFF81C784); // Light green
      case DsdRate.dsd256:
        return const Color(0xFFFFD54F); // Amber
      case DsdRate.dsd512:
        return const Color(0xFFFF8A65); // Deep orange - ULTIMATE
    }
  }

  String _getModeLabel() {
    switch (mode) {
      case DsdPlaybackMode.none:
        return '';
      case DsdPlaybackMode.native:
        return 'NATIVE';
      case DsdPlaybackMode.dop:
        return 'DoP';
      case DsdPlaybackMode.pcmConversion:
        return 'PCM';
    }
  }

  Color _getModeColor() {
    switch (mode) {
      case DsdPlaybackMode.none:
        return ReelForgeTheme.textSecondary;
      case DsdPlaybackMode.native:
        return const Color(0xFF4CAF50); // Green - best
      case DsdPlaybackMode.dop:
        return const Color(0xFF2196F3); // Blue - good
      case DsdPlaybackMode.pcmConversion:
        return const Color(0xFFFF9800); // Orange - converted
    }
  }
}

/// DSD Settings Panel (shown when indicator is tapped)
class DsdSettingsPanel extends StatefulWidget {
  final DsdRate currentRate;
  final DsdPlaybackMode currentMode;
  final bool nativeDsdSupported;
  final ValueChanged<DsdPlaybackMode>? onModeChanged;
  final VoidCallback? onClose;

  const DsdSettingsPanel({
    super.key,
    required this.currentRate,
    required this.currentMode,
    this.nativeDsdSupported = false,
    this.onModeChanged,
    this.onClose,
  });

  @override
  State<DsdSettingsPanel> createState() => _DsdSettingsPanelState();
}

class _DsdSettingsPanelState extends State<DsdSettingsPanel> {
  late DsdPlaybackMode _selectedMode;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.currentMode;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ReelForgeTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4FC3F7), Color(0xFF29B6F6)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'DSD',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Playback Settings',
                style: TextStyle(
                  color: ReelForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: ReelForgeTheme.textSecondary,
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Current status
          _buildStatusRow('Current Format', _getRateName(widget.currentRate)),
          const SizedBox(height: 8),
          _buildStatusRow(
            'Sample Rate',
            '${_getSampleRate(widget.currentRate)} MHz',
          ),
          const SizedBox(height: 16),

          // Playback mode selection
          const Text(
            'Playback Mode',
            style: TextStyle(
              color: ReelForgeTheme.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),

          _buildModeOption(
            DsdPlaybackMode.native,
            'Native DSD',
            'Direct DSD output (best quality)',
            Icons.stars,
            enabled: widget.nativeDsdSupported,
          ),
          const SizedBox(height: 8),

          _buildModeOption(
            DsdPlaybackMode.dop,
            'DoP (DSD over PCM)',
            'DSD encoded in PCM stream',
            Icons.swap_horiz,
          ),
          const SizedBox(height: 8),

          _buildModeOption(
            DsdPlaybackMode.pcmConversion,
            'Convert to PCM',
            'High-quality decimation to PCM',
            Icons.transform,
          ),

          const SizedBox(height: 16),

          // Hardware status
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  widget.nativeDsdSupported
                      ? Icons.check_circle
                      : Icons.info_outline,
                  color: widget.nativeDsdSupported
                      ? Colors.green
                      : ReelForgeTheme.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.nativeDsdSupported
                        ? 'Your audio interface supports native DSD'
                        : 'Native DSD not available on current device',
                    style: TextStyle(
                      color: ReelForgeTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: ReelForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: ReelForgeTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildModeOption(
    DsdPlaybackMode mode,
    String title,
    String description,
    IconData icon, {
    bool enabled = true,
  }) {
    final isSelected = _selectedMode == mode;

    return GestureDetector(
      onTap: enabled
          ? () {
              setState(() => _selectedMode = mode);
              widget.onModeChanged?.call(mode);
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? ReelForgeTheme.accentBlue.withOpacity(0.15)
              : ReelForgeTheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? ReelForgeTheme.accentBlue
                : ReelForgeTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: enabled
                  ? (isSelected
                      ? ReelForgeTheme.accentBlue
                      : ReelForgeTheme.textSecondary)
                  : ReelForgeTheme.textSecondary.withOpacity(0.4),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled
                          ? ReelForgeTheme.textPrimary
                          : ReelForgeTheme.textSecondary.withOpacity(0.4),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      color: enabled
                          ? ReelForgeTheme.textSecondary
                          : ReelForgeTheme.textSecondary.withOpacity(0.3),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: ReelForgeTheme.accentBlue,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  String _getRateName(DsdRate rate) {
    switch (rate) {
      case DsdRate.none:
        return 'None';
      case DsdRate.dsd64:
        return 'DSD64 (1-bit/2.8MHz)';
      case DsdRate.dsd128:
        return 'DSD128 (1-bit/5.6MHz)';
      case DsdRate.dsd256:
        return 'DSD256 (1-bit/11.2MHz)';
      case DsdRate.dsd512:
        return 'DSD512 (1-bit/22.5MHz)';
    }
  }

  String _getSampleRate(DsdRate rate) {
    switch (rate) {
      case DsdRate.none:
        return '---';
      case DsdRate.dsd64:
        return '2.8224';
      case DsdRate.dsd128:
        return '5.6448';
      case DsdRate.dsd256:
        return '11.2896';
      case DsdRate.dsd512:
        return '22.5792';
    }
  }
}

/// Compact DSD badge for track headers
class DsdBadge extends StatelessWidget {
  final DsdRate rate;

  const DsdBadge({super.key, required this.rate});

  @override
  Widget build(BuildContext context) {
    if (rate == DsdRate.none) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: _getColor().withOpacity(0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _getColor().withOpacity(0.5)),
      ),
      child: Text(
        _getLabel(),
        style: TextStyle(
          color: _getColor(),
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getLabel() {
    switch (rate) {
      case DsdRate.none:
        return '';
      case DsdRate.dsd64:
        return 'DSD64';
      case DsdRate.dsd128:
        return 'DSD128';
      case DsdRate.dsd256:
        return 'DSD256';
      case DsdRate.dsd512:
        return 'DSD512';
    }
  }

  Color _getColor() {
    switch (rate) {
      case DsdRate.none:
        return Colors.transparent;
      case DsdRate.dsd64:
        return const Color(0xFF4FC3F7);
      case DsdRate.dsd128:
        return const Color(0xFF81C784);
      case DsdRate.dsd256:
        return const Color(0xFFFFD54F);
      case DsdRate.dsd512:
        return const Color(0xFFFF8A65);
    }
  }
}
