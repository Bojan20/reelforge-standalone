// Elastic Audio Panel — DAW Lower Zone EDIT tab
// Pitch correction and time manipulation per clip (Pro Tools Elastic Audio style)

import 'package:flutter/material.dart';
import '../../../../services/elastic_audio_service.dart';
import '../../lower_zone_types.dart';

class ElasticAudioPanel extends StatefulWidget {
  final int? selectedTrackId;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const ElasticAudioPanel({super.key, this.selectedTrackId, this.onAction});

  @override
  State<ElasticAudioPanel> createState() => _ElasticAudioPanelState();
}

class _ElasticAudioPanelState extends State<ElasticAudioPanel> {
  final _service = ElasticAudioService.instance;

  ElasticMode _mode = ElasticMode.polyphonic;
  double _pitchShift = 0.0; // semitones
  double _finePitch = 0.0; // cents (-50 to +50)
  bool _preserveFormants = true;
  bool _enabled = false;

  @override
  Widget build(BuildContext context) {
    if (widget.selectedTrackId == null) {
      return _buildNoSelection();
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildModeSelector(),
                  const SizedBox(height: 12),
                  _buildPitchControls(),
                  const SizedBox(height: 12),
                  _buildFinePitchControl(),
                  const SizedBox(height: 12),
                  _buildOptions(),
                  const SizedBox(height: 12),
                  _buildPitchPresets(),
                  const SizedBox(height: 12),
                  _buildAnalysisInfo(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSelection() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.waves, size: 32, color: Colors.white24),
          const SizedBox(height: 8),
          Text('Select a clip for Elastic Audio',
              style: LowerZoneTypography.label.copyWith(color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.waves, size: 16, color: Colors.purple),
        const SizedBox(width: 6),
        Text('ELASTIC AUDIO', style: LowerZoneTypography.title.copyWith(color: Colors.white70)),
        const Spacer(),
        // Enable toggle
        Switch(
          value: _enabled,
          activeColor: Colors.purple,
          onChanged: (v) {
            setState(() => _enabled = v);
            if (v) {
              _service.setClipConfig(widget.selectedTrackId!.toString(), ElasticAudioConfig(
                mode: _mode,
                pitchShift: _pitchShift + _finePitch / 100.0,
                preserveFormants: _preserveFormants,
              ));
            } else {
              _service.removeClipConfig(widget.selectedTrackId!.toString());
            }
            widget.onAction?.call('elasticAudio', {'enabled': v});
          },
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    final modes = [
      (ElasticMode.polyphonic, 'Polyphonic', Icons.music_note, 'Best for chords, pads, complex audio'),
      (ElasticMode.monophonic, 'Monophonic', Icons.mic, 'Best for solo vocals, instruments'),
      (ElasticMode.rhythmic, 'Rhythmic', Icons.surround_sound, 'Best for drums, percussion, loops'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Processing Mode', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
        const SizedBox(height: 4),
        Row(
          children: modes.map((m) {
            final isActive = _mode == m.$1;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: m.$4,
                  child: InkWell(
                    onTap: () {
                      setState(() => _mode = m.$1);
                      _applyConfig();
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: (isActive ? Colors.purple : Colors.white).withOpacity(isActive ? 0.2 : 0.05),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isActive ? Colors.purple.withOpacity(0.5) : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(m.$3, size: 16, color: isActive ? Colors.purple : Colors.white38),
                          const SizedBox(height: 2),
                          Text(m.$2, style: LowerZoneTypography.badge.copyWith(
                              color: isActive ? Colors.purple : Colors.white54)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPitchControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Pitch Shift', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
            const Spacer(),
            Text(_formatPitch(_pitchShift),
                style: LowerZoneTypography.value.copyWith(
                    color: _pitchShift != 0 ? Colors.purple : Colors.white54,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _pitchShift,
                min: -24,
                max: 24,
                divisions: 48,
                activeColor: Colors.purple,
                onChanged: (v) {
                  setState(() => _pitchShift = v);
                  _applyConfig();
                },
              ),
            ),
          ],
        ),
        // Quick semitone buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [-12, -7, -5, -3, -1, 0, 1, 3, 5, 7, 12].map((st) {
            final isActive = _pitchShift == st.toDouble();
            return GestureDetector(
              onTap: () {
                setState(() => _pitchShift = st.toDouble());
                _applyConfig();
              },
              child: Container(
                width: 28,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: (isActive ? Colors.purple : Colors.white).withOpacity(isActive ? 0.3 : 0.05),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  st > 0 ? '+$st' : '$st',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    color: isActive ? Colors.purple : Colors.white38,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFinePitchControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Fine Tune (cents)', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
            const Spacer(),
            Text('${_finePitch > 0 ? '+' : ''}${_finePitch.toStringAsFixed(0)}¢',
                style: LowerZoneTypography.value.copyWith(
                    color: _finePitch != 0 ? Colors.purple.shade200 : Colors.white54)),
          ],
        ),
        Slider(
          value: _finePitch,
          min: -50,
          max: 50,
          divisions: 100,
          activeColor: Colors.purple.shade300,
          onChanged: (v) {
            setState(() => _finePitch = v);
            _applyConfig();
          },
        ),
      ],
    );
  }

  Widget _buildOptions() {
    return Row(
      children: [
        Switch(
          value: _preserveFormants,
          activeColor: Colors.purple,
          onChanged: (v) {
            setState(() => _preserveFormants = v);
            _applyConfig();
          },
        ),
        Text('Preserve Formants', style: LowerZoneTypography.label.copyWith(color: Colors.white70)),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Prevents chipmunk effect when pitch shifting vocals',
          child: Icon(Icons.info_outline, size: 14, color: Colors.white24),
        ),
      ],
    );
  }

  Widget _buildPitchPresets() {
    final presets = [
      ('Octave Down', -12.0),
      ('5th Down', -7.0),
      ('Original', 0.0),
      ('5th Up', 7.0),
      ('Octave Up', 12.0),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Presets', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: presets.map((p) {
            return ActionChip(
              label: Text(p.$1, style: TextStyle(
                fontSize: LowerZoneTypography.sizeBadge,
                color: _pitchShift == p.$2 ? Colors.white : Colors.white54,
              )),
              backgroundColor: _pitchShift == p.$2
                  ? Colors.purple.withOpacity(0.3)
                  : Colors.white.withOpacity(0.05),
              onPressed: () {
                setState(() => _pitchShift = p.$2);
                _applyConfig();
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAnalysisInfo() {
    if (!_enabled) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.purple.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Analysis', style: LowerZoneTypography.label.copyWith(color: Colors.purple.shade200)),
          const SizedBox(height: 4),
          _infoRow('Mode', _mode.name),
          _infoRow('Total Shift', _formatPitch(_pitchShift + _finePitch / 100.0)),
          _infoRow('Formant Preservation', _preserveFormants ? 'On' : 'Off'),
          _infoRow('Latency', _mode == ElasticMode.rhythmic ? '~5ms' : '~10ms'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(label, style: LowerZoneTypography.badge.copyWith(color: Colors.white38)),
          const Spacer(),
          Text(value, style: LowerZoneTypography.badge.copyWith(color: Colors.white54)),
        ],
      ),
    );
  }

  String _formatPitch(double semitones) {
    if (semitones == 0) return '0 st';
    return '${semitones > 0 ? '+' : ''}${semitones.toStringAsFixed(1)} st';
  }

  void _applyConfig() {
    if (!_enabled) return;
    _service.setClipConfig(widget.selectedTrackId!.toString(), ElasticAudioConfig(
      mode: _mode,
      pitchShift: _pitchShift + _finePitch / 100.0,
      preserveFormants: _preserveFormants,
    ));
    widget.onAction?.call('elasticAudioUpdate', {
      'mode': _mode.name,
      'pitchShift': _pitchShift,
      'finePitch': _finePitch,
      'preserveFormants': _preserveFormants,
    });
  }
}
