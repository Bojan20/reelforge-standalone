/// GPU DSP Settings Panel
///
/// Controls for GPU-accelerated DSP processing:
/// - GPU device selection
/// - FFT size configuration
/// - EQ processing mode
/// - Convolution settings
/// - Performance monitoring

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// GPU processing mode
enum GpuProcessingMode {
  /// CPU only (fallback)
  cpuOnly,
  /// GPU for FFT only
  gpuFft,
  /// GPU for EQ processing
  gpuEq,
  /// GPU for convolution
  gpuConvolution,
  /// Full GPU pipeline
  gpuFull,
}

/// GPU device info
class GpuDeviceInfo {
  final String name;
  final String vendor;
  final int vramMb;
  final bool supportsCompute;
  final int maxWorkgroupSize;

  const GpuDeviceInfo({
    required this.name,
    required this.vendor,
    required this.vramMb,
    required this.supportsCompute,
    required this.maxWorkgroupSize,
  });

  static const GpuDeviceInfo placeholder = GpuDeviceInfo(
    name: 'Detecting...',
    vendor: '',
    vramMb: 0,
    supportsCompute: false,
    maxWorkgroupSize: 0,
  );
}

/// GPU performance stats
class GpuPerformanceStats {
  final double gpuUtilization;
  final double vramUsedMb;
  final double kernelTimeMs;
  final double transferTimeMs;
  final int activeWorkgroups;

  const GpuPerformanceStats({
    this.gpuUtilization = 0,
    this.vramUsedMb = 0,
    this.kernelTimeMs = 0,
    this.transferTimeMs = 0,
    this.activeWorkgroups = 0,
  });
}

/// GPU Settings Panel
class GpuSettingsPanel extends StatefulWidget {
  final GpuDeviceInfo? deviceInfo;
  final GpuProcessingMode currentMode;
  final GpuPerformanceStats stats;
  final ValueChanged<GpuProcessingMode>? onModeChanged;
  final ValueChanged<int>? onFftSizeChanged;
  final VoidCallback? onClose;

  const GpuSettingsPanel({
    super.key,
    this.deviceInfo,
    this.currentMode = GpuProcessingMode.cpuOnly,
    this.stats = const GpuPerformanceStats(),
    this.onModeChanged,
    this.onFftSizeChanged,
    this.onClose,
  });

  @override
  State<GpuSettingsPanel> createState() => _GpuSettingsPanelState();
}

class _GpuSettingsPanelState extends State<GpuSettingsPanel> {
  late GpuProcessingMode _selectedMode;
  int _fftSize = 4096;
  bool _enableAutoTuning = true;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.currentMode;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 16),

          // Device info
          _buildDeviceInfo(),
          const SizedBox(height: 16),

          // Processing mode
          _buildProcessingMode(),
          const SizedBox(height: 16),

          // FFT settings
          _buildFftSettings(),
          const SizedBox(height: 16),

          // Performance stats
          _buildPerformanceStats(),
          const SizedBox(height: 16),

          // Auto-tuning toggle
          _buildAutoTuning(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF76B900), Color(0xFF5A8F00)], // NVIDIA green
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.memory,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GPU DSP Settings',
                style: FluxForgeTheme.dockSans(
                  size: 16,
                  weight: FontWeight.bold,
                  color: FluxForgeTheme.textPrimary,
                ),
              ),
              Text(
                'Hardware-accelerated audio processing',
                style: FluxForgeTheme.dockSans(
                  size: 11,
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          color: FluxForgeTheme.textSecondary,
          onPressed: widget.onClose,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _buildDeviceInfo() {
    final device = widget.deviceInfo ?? GpuDeviceInfo.placeholder;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: device.supportsCompute
              ? const Color(0xFF76B900).withValues(alpha: 0.3)
              : FluxForgeTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                device.supportsCompute ? Icons.check_circle : Icons.warning,
                color: device.supportsCompute
                    ? const Color(0xFF76B900)
                    : Colors.orange,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  device.name,
                  style: FluxForgeTheme.dockSans(
                    size: 13,
                    weight: FontWeight.w500,
                    color: FluxForgeTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildDeviceStat('Vendor', device.vendor.isEmpty ? '—' : device.vendor),
              const SizedBox(width: 16),
              _buildDeviceStat('VRAM', '${device.vramMb} MB'),
              const SizedBox(width: 16),
              _buildDeviceStat('Workgroup', '${device.maxWorkgroupSize}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: FluxForgeTheme.dockSans(
            size: 9,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: FluxForgeTheme.dockSans(
            size: 11,
            weight: FontWeight.w500,
            color: FluxForgeTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildProcessingMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Processing Mode',
          style: FluxForgeTheme.dockSans(
            size: 11,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildModeChip(GpuProcessingMode.cpuOnly, 'CPU Only', Icons.computer),
            _buildModeChip(GpuProcessingMode.gpuFft, 'GPU FFT', Icons.show_chart),
            _buildModeChip(GpuProcessingMode.gpuEq, 'GPU EQ', Icons.equalizer),
            _buildModeChip(GpuProcessingMode.gpuConvolution, 'GPU Conv', Icons.blur_on),
            _buildModeChip(GpuProcessingMode.gpuFull, 'Full GPU', Icons.rocket_launch),
          ],
        ),
      ],
    );
  }

  Widget _buildModeChip(GpuProcessingMode mode, String label, IconData icon) {
    final isSelected = _selectedMode == mode;
    final isAvailable = widget.deviceInfo?.supportsCompute ?? false;
    final canSelect = mode == GpuProcessingMode.cpuOnly || isAvailable;

    return GestureDetector(
      onTap: canSelect
          ? () {
              setState(() => _selectedMode = mode);
              widget.onModeChanged?.call(mode);
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF76B900).withValues(alpha: 0.2)
              : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF76B900)
                : canSelect
                    ? FluxForgeTheme.border
                    : FluxForgeTheme.border.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? const Color(0xFF76B900)
                  : canSelect
                      ? FluxForgeTheme.textSecondary
                      : FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: FluxForgeTheme.dockSans(
                size: 11,
                weight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? FluxForgeTheme.textPrimary
                    : canSelect
                        ? FluxForgeTheme.textSecondary
                        : FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFftSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FFT Size',
          style: FluxForgeTheme.dockSans(
            size: 11,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildFftSizeButton(1024),
            const SizedBox(width: 8),
            _buildFftSizeButton(2048),
            const SizedBox(width: 8),
            _buildFftSizeButton(4096),
            const SizedBox(width: 8),
            _buildFftSizeButton(8192),
            const SizedBox(width: 8),
            _buildFftSizeButton(16384),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Larger = better frequency resolution, higher latency',
          style: FluxForgeTheme.dockSans(
            size: 10,
            color: FluxForgeTheme.textSecondary.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildFftSizeButton(int size) {
    final isSelected = _fftSize == size;
    final sizeK = size >= 1024 ? '${size ~/ 1024}K' : '$size';

    return GestureDetector(
      onTap: () {
        setState(() => _fftSize = size);
        widget.onFftSizeChanged?.call(size);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
              : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.border,
          ),
        ),
        child: Text(
          sizeK,
          style: FluxForgeTheme.dockSans(
            size: 11,
            weight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildPerformanceStats() {
    final stats = widget.stats;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance',
            style: FluxForgeTheme.dockSans(
              size: 10,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildStatBar('GPU', stats.gpuUtilization, '%')),
              const SizedBox(width: 12),
              Expanded(child: _buildStatBar('VRAM', stats.vramUsedMb, 'MB')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildStatValue('Kernel', '${stats.kernelTimeMs.toStringAsFixed(2)} ms')),
              const SizedBox(width: 12),
              Expanded(child: _buildStatValue('Transfer', '${stats.transferTimeMs.toStringAsFixed(2)} ms')),
              const SizedBox(width: 12),
              Expanded(child: _buildStatValue('Workgroups', '${stats.activeWorkgroups}')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBar(String label, double value, String unit) {
    final percentage = (value / 100).clamp(0.0, 1.0);
    final color = percentage > 0.8
        ? Colors.red
        : percentage > 0.6
            ? Colors.orange
            : const Color(0xFF76B900);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: FluxForgeTheme.dockSans(
                size: 10,
                color: FluxForgeTheme.textSecondary,
              ),
            ),
            Text(
              '${value.toStringAsFixed(1)}$unit',
              style: FluxForgeTheme.dockSans(
                size: 10,
                weight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: percentage,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: FluxForgeTheme.dockSans(
            size: 9,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: FluxForgeTheme.dockMono(
            size: 11,
            color: FluxForgeTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildAutoTuning() {
    return GestureDetector(
      onTap: () {
        setState(() => _enableAutoTuning = !_enableAutoTuning);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _enableAutoTuning
              ? const Color(0xFF76B900).withValues(alpha: 0.1)
              : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _enableAutoTuning
                ? const Color(0xFF76B900).withValues(alpha: 0.5)
                : FluxForgeTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _enableAutoTuning ? Icons.auto_awesome : Icons.auto_awesome_outlined,
              color: _enableAutoTuning
                  ? const Color(0xFF76B900)
                  : FluxForgeTheme.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Auto-Tuning',
                    style: FluxForgeTheme.dockSans(
                      size: 12,
                      weight: FontWeight.w500,
                      color: FluxForgeTheme.textPrimary,
                    ),
                  ),
                  Text(
                    'Automatically optimize workgroup size and batch parameters',
                    style: FluxForgeTheme.dockSans(
                      size: 10,
                      color: FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 20,
              decoration: BoxDecoration(
                color: _enableAutoTuning
                    ? const Color(0xFF76B900)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedAlign(
                alignment: _enableAutoTuning
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact GPU indicator for toolbar
class GpuIndicator extends StatelessWidget {
  final GpuProcessingMode mode;
  final double utilization;
  final VoidCallback? onTap;

  const GpuIndicator({
    super.key,
    this.mode = GpuProcessingMode.cpuOnly,
    this.utilization = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (mode == GpuProcessingMode.cpuOnly) {
      return const SizedBox.shrink();
    }

    final color = utilization > 80
        ? Colors.red
        : utilization > 60
            ? Colors.orange
            : const Color(0xFF76B900);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.3),
              color.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                'GPU',
                style: FluxForgeTheme.dockSans(
                  size: 8,
                  weight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _getModeLabel(),
              style: FluxForgeTheme.dockSans(
                size: 10,
                weight: FontWeight.w500,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${utilization.toStringAsFixed(0)}%',
              style: FluxForgeTheme.dockMono(
                size: 10,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getModeLabel() {
    switch (mode) {
      case GpuProcessingMode.cpuOnly:
        return 'OFF';
      case GpuProcessingMode.gpuFft:
        return 'FFT';
      case GpuProcessingMode.gpuEq:
        return 'EQ';
      case GpuProcessingMode.gpuConvolution:
        return 'CONV';
      case GpuProcessingMode.gpuFull:
        return 'FULL';
    }
  }
}
