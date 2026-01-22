/// Spatial Stats Panel — Engine stats and configuration
///
/// Features:
/// - Active events count, pool utilization
/// - Processing time (avg, peak)
/// - Events/second, dropped, rate-limited
/// - Config toggles (Doppler, HRTF, etc.)
/// - Render mode selector
/// - Listener position controls

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auto_spatial_provider.dart';
import '../../spatial/auto_spatial.dart';
import 'spatial_widgets.dart';

/// Stats and Config panel
class SpatialStatsPanel extends StatelessWidget {
  final bool compact;

  const SpatialStatsPanel({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoSpatialProvider>(
      builder: (context, provider, _) {
        if (compact) {
          return _buildCompactLayout(provider);
        }
        return _buildFullLayout(provider);
      },
    );
  }

  Widget _buildCompactLayout(AutoSpatialProvider provider) {
    final stats = provider.stats;
    final config = provider.config;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          Row(
            children: [
              _CompactStat(
                label: 'Active',
                value: '${stats.activeEvents}',
                color: const Color(0xFF40ff90),
              ),
              const SizedBox(width: 8),
              _CompactStat(
                label: 'Pool',
                value: '${stats.poolUtilization}%',
                color: stats.poolUtilization > 80
                    ? const Color(0xFFff4060)
                    : const Color(0xFF4a9eff),
              ),
              const SizedBox(width: 8),
              _CompactStat(
                label: 'Proc',
                value: '${stats.avgProcessingTimeUs.toStringAsFixed(0)}us',
                color: const Color(0xFF40c8ff),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Config toggles
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _ConfigChip(
                label: 'Doppler',
                enabled: config.enableDoppler,
                onTap: () => provider.setDopplerEnabled(!config.enableDoppler),
              ),
              _ConfigChip(
                label: 'HRTF',
                enabled: config.enableHRTF,
                onTap: () => provider.setHRTFEnabled(!config.enableHRTF),
              ),
              _ConfigChip(
                label: 'Reverb',
                enabled: config.enableReverb,
                onTap: () => provider.setReverbEnabled(!config.enableReverb),
              ),
              _ConfigChip(
                label: 'Dist',
                enabled: config.enableDistanceAttenuation,
                onTap: () => provider
                    .setDistanceAttenuationEnabled(!config.enableDistanceAttenuation),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFullLayout(AutoSpatialProvider provider) {
    final stats = provider.stats;
    final config = provider.config;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats section
          _SectionHeader(title: 'Engine Statistics'),
          _buildStatsGrid(stats),
          const SizedBox(height: 16),

          // Render mode
          _SectionHeader(title: 'Render Mode'),
          _RenderModeSelector(
            value: config.renderMode,
            onChanged: provider.setRenderMode,
          ),
          const SizedBox(height: 16),

          // Feature toggles
          _SectionHeader(title: 'Features'),
          _buildFeatureToggles(provider, config),
          const SizedBox(height: 16),

          // Listener position
          _SectionHeader(title: 'Listener Position'),
          _buildListenerControls(provider, config),
          const SizedBox(height: 16),

          // Global scales
          _SectionHeader(title: 'Global Scales'),
          Row(
            children: [
              Expanded(
                child: SpatialSlider(
                  label: 'Pan Scale',
                  value: config.globalPanScale,
                  min: 0,
                  max: 2,
                  onChanged: provider.setGlobalPanScale,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SpatialSlider(
                  label: 'Width Scale',
                  value: config.globalWidthScale,
                  min: 0,
                  max: 2,
                  onChanged: provider.setGlobalWidthScale,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Actions
          _SectionHeader(title: 'Actions'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.clear_all, size: 14),
                  label: const Text('Clear Events', style: TextStyle(fontSize: 10)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  onPressed: provider.clearEvents,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Reset Config', style: TextStyle(fontSize: 10)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  onPressed: () {
                    provider.updateConfig(const AutoSpatialConfig());
                    provider.resetAllRulesToDefaults();
                    provider.resetAllBusPoliciesToDefaults();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(AutoSpatialStats stats) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3a3a4a)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.event,
                  label: 'Active Events',
                  value: '${stats.activeEvents}',
                  color: const Color(0xFF40ff90),
                ),
              ),
              Expanded(
                child: _StatCard(
                  icon: Icons.donut_large,
                  label: 'Pool Usage',
                  value: '${stats.poolUtilization}%',
                  color: stats.poolUtilization > 80
                      ? const Color(0xFFff4060)
                      : const Color(0xFF4a9eff),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.timer,
                  label: 'Avg Process',
                  value: '${stats.avgProcessingTimeUs.toStringAsFixed(1)}us',
                  color: const Color(0xFF40c8ff),
                ),
              ),
              Expanded(
                child: _StatCard(
                  icon: Icons.speed,
                  label: 'Peak Process',
                  value: '${stats.peakProcessingTimeUs.toStringAsFixed(1)}us',
                  color: const Color(0xFFff9040),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.trending_up,
                  label: 'Events/sec',
                  value: '${stats.eventsThisSecond}',
                  color: const Color(0xFF40c8ff),
                ),
              ),
              Expanded(
                child: _StatCard(
                  icon: Icons.block,
                  label: 'Dropped',
                  value: '${stats.droppedEvents}',
                  color: stats.droppedEvents > 0
                      ? const Color(0xFFff4060)
                      : Colors.white38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.check_circle,
                  label: 'Total Processed',
                  value: '${stats.totalEventsProcessed}',
                  color: Colors.white70,
                ),
              ),
              Expanded(
                child: _StatCard(
                  icon: Icons.pan_tool,
                  label: 'Rate Limited',
                  value: '${stats.rateLimitedEvents}',
                  color: stats.rateLimitedEvents > 0
                      ? const Color(0xFFff9040)
                      : Colors.white38,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureToggles(AutoSpatialProvider provider, AutoSpatialConfig config) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FeatureToggle(
          label: 'Doppler Effect',
          icon: Icons.speed,
          value: config.enableDoppler,
          onChanged: provider.setDopplerEnabled,
        ),
        _FeatureToggle(
          label: 'Distance Atten',
          icon: Icons.straighten,
          value: config.enableDistanceAttenuation,
          onChanged: provider.setDistanceAttenuationEnabled,
        ),
        _FeatureToggle(
          label: 'Occlusion',
          icon: Icons.layers,
          value: config.enableOcclusion,
          onChanged: provider.setOcclusionEnabled,
        ),
        _FeatureToggle(
          label: 'Reverb Send',
          icon: Icons.blur_on,
          value: config.enableReverb,
          onChanged: provider.setReverbEnabled,
        ),
        _FeatureToggle(
          label: 'HRTF Binaural',
          icon: Icons.headphones,
          value: config.enableHRTF,
          onChanged: provider.setHRTFEnabled,
        ),
        _FeatureToggle(
          label: 'Freq Absorption',
          icon: Icons.equalizer,
          value: config.enableFrequencyDependentAbsorption,
          onChanged: provider.setFrequencyAbsorptionEnabled,
        ),
        _FeatureToggle(
          label: 'Event Fade-out',
          icon: Icons.animation,
          value: config.enableEventFadeOut,
          onChanged: provider.setEventFadeOutEnabled,
        ),
      ],
    );
  }

  Widget _buildListenerControls(AutoSpatialProvider provider, AutoSpatialConfig config) {
    final listener = config.listenerPosition;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SpatialSlider(
                label: 'X (L/R)',
                value: listener.x,
                min: -1,
                max: 1,
                onChanged: (v) => provider.setListenerPosition(
                  ListenerPosition(
                    x: v,
                    y: listener.y,
                    z: listener.z,
                    rotationRad: listener.rotationRad,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SpatialSlider(
                label: 'Y (B/F)',
                value: listener.y,
                min: -1,
                max: 1,
                onChanged: (v) => provider.setListenerPosition(
                  ListenerPosition(
                    x: listener.x,
                    y: v,
                    z: listener.z,
                    rotationRad: listener.rotationRad,
                  ),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: SpatialSlider(
                label: 'Z (D/U)',
                value: listener.z,
                min: -1,
                max: 1,
                onChanged: (v) => provider.setListenerPosition(
                  ListenerPosition(
                    x: listener.x,
                    y: listener.y,
                    z: v,
                    rotationRad: listener.rotationRad,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SpatialSlider(
                label: 'Rotation',
                value: listener.rotationRad,
                min: -3.14159,
                max: 3.14159,
                onChanged: (v) => provider.setListenerPosition(
                  ListenerPosition(
                    x: listener.x,
                    y: listener.y,
                    z: listener.z,
                    rotationRad: v,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white54,
              side: const BorderSide(color: Colors.white24),
            ),
            onPressed: () =>
                provider.setListenerPosition(ListenerPosition.center),
            child: const Text('Reset to Center', style: TextStyle(fontSize: 10)),
          ),
        ),
      ],
    );
  }
}

/// Section header
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Stat card
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Feature toggle
class _FeatureToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FeatureToggle({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = value ? const Color(0xFF40ff90) : Colors.white38;

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value
              ? const Color(0xFF40ff90).withValues(alpha: 0.15)
              : const Color(0xFF121216),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: value
                ? const Color(0xFF40ff90).withValues(alpha: 0.3)
                : const Color(0xFF3a3a4a),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// Render mode selector
class _RenderModeSelector extends StatelessWidget {
  final SpatialRenderMode value;
  final ValueChanged<SpatialRenderMode> onChanged;

  const _RenderModeSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: SpatialRenderMode.values.map((mode) {
        final isSelected = value == mode;
        final label = switch (mode) {
          SpatialRenderMode.stereo => 'Stereo',
          SpatialRenderMode.binaural => 'Binaural',
          SpatialRenderMode.ambisonicsFirstOrder => 'FOA',
          SpatialRenderMode.ambisonicsHigherOrder => 'HOA',
          SpatialRenderMode.atmos => 'Atmos',
        };
        final icon = switch (mode) {
          SpatialRenderMode.stereo => Icons.speaker,
          SpatialRenderMode.binaural => Icons.headphones,
          SpatialRenderMode.ambisonicsFirstOrder => Icons.threed_rotation,
          SpatialRenderMode.ambisonicsHigherOrder => Icons.threed_rotation,
          SpatialRenderMode.atmos => Icons.surround_sound,
        };

        return GestureDetector(
          onTap: () => onChanged(mode),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF4a9eff).withValues(alpha: 0.2)
                  : const Color(0xFF121216),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF4a9eff)
                    : const Color(0xFF3a3a4a),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isSelected ? const Color(0xFF4a9eff) : Colors.white54,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF4a9eff) : Colors.white54,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Compact stat
class _CompactStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _CompactStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 8),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// Config chip for compact mode
class _ConfigChip extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ConfigChip({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? const Color(0xFF40ff90) : Colors.white38;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFF40ff90).withValues(alpha: 0.15)
              : const Color(0xFF121216),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 9),
        ),
      ),
    );
  }
}
