// Punch Recording Panel — DAW Lower Zone EDIT tab
// Professional punch-in/punch-out recording with pre-roll, count-in, and rehearsal mode

import 'package:flutter/material.dart';
import '../../../../services/punch_recording_service.dart';
import '../../lower_zone_types.dart';

class PunchRecordingPanel extends StatefulWidget {
  final int? selectedTrackId;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const PunchRecordingPanel({super.key, this.selectedTrackId, this.onAction});

  @override
  State<PunchRecordingPanel> createState() => _PunchRecordingPanelState();
}

class _PunchRecordingPanelState extends State<PunchRecordingPanel> {
  final _service = PunchRecordingService.instance;

  PunchMode _mode = PunchMode.auto;
  double _punchInTime = 10.0;
  double _punchOutTime = 20.0;
  double _preRollSeconds = 2.0;
  double _postRollSeconds = 1.0;
  bool _countInEnabled = true;
  int _countInBars = 1;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _startRecording() {
    _service.startRecording(PunchRecordingConfig(
      mode: _mode,
      preRollSeconds: _preRollSeconds,
      postRollSeconds: _postRollSeconds,
      punchInTime: _punchInTime,
      punchOutTime: _punchOutTime,
      countInEnabled: _countInEnabled,
      countInBars: _countInBars,
    ));
    widget.onAction?.call('punchRecord', {
      'mode': _mode.name,
      'punchIn': _punchInTime,
      'punchOut': _punchOutTime,
    });
  }

  void _stopRecording() {
    _service.stopRecording();
    widget.onAction?.call('punchStop', null);
  }

  @override
  Widget build(BuildContext context) {
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
                  _buildPunchPoints(),
                  const SizedBox(height: 12),
                  _buildPrePostRoll(),
                  const SizedBox(height: 12),
                  _buildCountIn(),
                  const SizedBox(height: 12),
                  _buildTransportControls(),
                  const SizedBox(height: 12),
                  _buildStatusIndicator(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.fiber_manual_record, size: 16, color: Colors.red),
        const SizedBox(width: 6),
        Text('PUNCH RECORDING', style: LowerZoneTypography.title.copyWith(color: Colors.white70)),
        const Spacer(),
        if (widget.selectedTrackId != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('Track ${widget.selectedTrackId}',
                style: LowerZoneTypography.badge.copyWith(color: Colors.blue)),
          ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mode', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
        const SizedBox(height: 4),
        Row(
          children: PunchMode.values.map((mode) {
            final isActive = _mode == mode;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text(mode.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: LowerZoneTypography.sizeBadge,
                      color: isActive ? Colors.white : Colors.white54,
                    )),
                selected: isActive,
                selectedColor: _modeColor(mode),
                backgroundColor: Colors.white.withOpacity(0.05),
                onSelected: (_) => setState(() => _mode = mode),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Color _modeColor(PunchMode mode) => switch (mode) {
    PunchMode.manual => Colors.orange,
    PunchMode.auto => Colors.red.shade700,
    PunchMode.rehearsal => Colors.green.shade700,
  };

  Widget _buildPunchPoints() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Punch Points', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: _buildTimeField('Punch In', _punchInTime, (v) => setState(() => _punchInTime = v))),
            const SizedBox(width: 8),
            Expanded(child: _buildTimeField('Punch Out', _punchOutTime, (v) => setState(() => _punchOutTime = v))),
          ],
        ),
        const SizedBox(height: 6),
        // Visual timeline
        _buildPunchTimeline(),
      ],
    );
  }

  Widget _buildPunchTimeline() {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: CustomPaint(
        painter: _PunchTimelinePainter(
          punchIn: _punchInTime,
          punchOut: _punchOutTime,
          preRoll: _preRollSeconds,
          postRoll: _postRollSeconds,
          state: _service.state,
        ),
        size: const Size(double.infinity, 32),
      ),
    );
  }

  Widget _buildTimeField(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: LowerZoneTypography.badge.copyWith(color: Colors.white38)),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value,
                min: 0,
                max: 120,
                divisions: 240,
                activeColor: Colors.red.shade400,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 48,
              child: Text('${value.toStringAsFixed(1)}s',
                  style: LowerZoneTypography.value.copyWith(color: Colors.white70)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPrePostRoll() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pre/Post Roll', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _buildCompactSlider('Pre-Roll', _preRollSeconds, 0, 10,
                  (v) => setState(() => _preRollSeconds = v), 's'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildCompactSlider('Post-Roll', _postRollSeconds, 0, 5,
                  (v) => setState(() => _postRollSeconds = v), 's'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCountIn() {
    return Row(
      children: [
        Switch(
          value: _countInEnabled,
          activeColor: Colors.red.shade400,
          onChanged: (v) => setState(() => _countInEnabled = v),
        ),
        Text('Count-In', style: LowerZoneTypography.label.copyWith(color: Colors.white70)),
        const SizedBox(width: 12),
        if (_countInEnabled)
          DropdownButton<int>(
            value: _countInBars,
            dropdownColor: const Color(0xFF1a1a20),
            style: LowerZoneTypography.value.copyWith(color: Colors.white70),
            items: [1, 2, 4].map((b) => DropdownMenuItem(
              value: b,
              child: Text('$b bar${b > 1 ? 's' : ''}'),
            )).toList(),
            onChanged: (v) => setState(() => _countInBars = v!),
          ),
      ],
    );
  }

  Widget _buildTransportControls() {
    final isRecording = _service.isRecording;
    final state = _service.state;

    return Row(
      children: [
        // Record / Stop button
        ElevatedButton.icon(
          onPressed: state == PunchRecordingState.idle ? _startRecording : _stopRecording,
          icon: Icon(
            state == PunchRecordingState.idle ? Icons.fiber_manual_record : Icons.stop,
            size: 16,
          ),
          label: Text(state == PunchRecordingState.idle ? 'RECORD' : 'STOP',
              style: const TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(
            backgroundColor: state == PunchRecordingState.idle
                ? Colors.red.shade700
                : Colors.grey.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
        const SizedBox(width: 8),
        // Rehearsal toggle
        if (_mode == PunchMode.rehearsal)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Text('REHEARSAL — No audio recorded',
                style: LowerZoneTypography.badge.copyWith(color: Colors.green)),
          ),
      ],
    );
  }

  Widget _buildStatusIndicator() {
    final state = _service.state;
    if (state == PunchRecordingState.idle) return const SizedBox.shrink();

    final (label, color) = switch (state) {
      PunchRecordingState.preRoll => ('PRE-ROLL', Colors.orange),
      PunchRecordingState.recording => ('RECORDING', Colors.red),
      PunchRecordingState.postRoll => ('POST-ROLL', Colors.blue),
      PunchRecordingState.stopped => ('STOPPED', Colors.grey),
      PunchRecordingState.idle => ('', Colors.transparent),
    };

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          if (state == PunchRecordingState.recording)
            const _PulsingDot(color: Colors.red),
          if (state == PunchRecordingState.recording)
            const SizedBox(width: 8),
          Text(label, style: LowerZoneTypography.label.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          )),
        ],
      ),
    );
  }

  Widget _buildCompactSlider(String label, double value, double min, double max,
      ValueChanged<double> onChanged, String unit) {
    return Row(
      children: [
        Text(label, style: LowerZoneTypography.badge.copyWith(color: Colors.white38)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: Colors.red.shade400,
            onChanged: onChanged,
          ),
        ),
        Text('${value.toStringAsFixed(1)}$unit',
            style: LowerZoneTypography.badge.copyWith(color: Colors.white70)),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(0.4 + _ctrl.value * 0.6),
        ),
      ),
    );
  }
}

class _PunchTimelinePainter extends CustomPainter {
  final double punchIn;
  final double punchOut;
  final double preRoll;
  final double postRoll;
  final PunchRecordingState state;

  _PunchTimelinePainter({
    required this.punchIn,
    required this.punchOut,
    required this.preRoll,
    required this.postRoll,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalRange = (punchOut + postRoll) - (punchIn - preRoll);
    if (totalRange <= 0) return;
    final startTime = punchIn - preRoll;

    double timeToX(double t) => ((t - startTime) / totalRange) * size.width;

    // Pre-roll zone
    final preRollRect = Rect.fromLTRB(timeToX(startTime), 0, timeToX(punchIn), size.height);
    canvas.drawRect(preRollRect, Paint()..color = Colors.orange.withOpacity(0.15));

    // Recording zone
    final recRect = Rect.fromLTRB(timeToX(punchIn), 0, timeToX(punchOut), size.height);
    canvas.drawRect(recRect, Paint()..color = Colors.red.withOpacity(0.2));

    // Post-roll zone
    final postRect = Rect.fromLTRB(timeToX(punchOut), 0, timeToX(punchOut + postRoll), size.height);
    canvas.drawRect(postRect, Paint()..color = Colors.blue.withOpacity(0.15));

    // Punch in/out markers
    final markerPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2;
    canvas.drawLine(Offset(timeToX(punchIn), 0), Offset(timeToX(punchIn), size.height), markerPaint);
    canvas.drawLine(Offset(timeToX(punchOut), 0), Offset(timeToX(punchOut), size.height), markerPaint);

    // Labels
    final textStyle = TextStyle(fontSize: 8, color: Colors.white38);
    _drawLabel(canvas, 'PRE', preRollRect.center, textStyle);
    _drawLabel(canvas, 'REC', recRect.center, textStyle);
    _drawLabel(canvas, 'POST', postRect.center, textStyle);
  }

  void _drawLabel(Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PunchTimelinePainter old) =>
      old.punchIn != punchIn || old.punchOut != punchOut ||
      old.preRoll != preRoll || old.postRoll != postRoll || old.state != state;
}
