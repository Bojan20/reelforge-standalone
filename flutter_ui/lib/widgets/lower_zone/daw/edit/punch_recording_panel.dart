// Punch Recording Panel — FabFilter-style DAW Lower Zone EDIT tab
// Professional punch-in/punch-out recording configuration
// Transport/recording function — NOT a DSP processor (no insert chain)

import 'package:flutter/material.dart';
import '../../../../services/punch_recording_service.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_knob.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

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

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: FabFilterColors.bgDeep),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  Expanded(child: _buildKnobsRow()),
                  const SizedBox(height: 4),
                  _buildTimeline(),
                  const SizedBox(height: 4),
                  _buildStatusBar(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER — title, mode selector, record/stop, track badge, close
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    final isIdle = _service.state == PunchRecordingState.idle;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        border: Border(
          bottom: BorderSide(color: FabFilterColors.orange.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          // Title
          Text('FF PUNCH', style: FabFilterText.sectionHeader.copyWith(
            color: FabFilterColors.orange, fontSize: 10, letterSpacing: 1.2,
          )),
          const SizedBox(width: 10),
          // Mode selector
          _buildModeSelector(),
          const SizedBox(width: 8),
          // Track badge
          if (widget.selectedTrackId != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: FabFilterColors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: FabFilterColors.blue.withValues(alpha: 0.4)),
              ),
              child: Text('TRK ${widget.selectedTrackId}',
                style: FabFilterText.paramLabel.copyWith(
                  color: FabFilterColors.blue, fontSize: 8,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          // Record / Stop button
          _buildRecordButton(isIdle),
          const SizedBox(width: 6),
          // Close
          GestureDetector(
            onTap: () => widget.onAction?.call('close', null),
            child: const Icon(Icons.close, size: 14, color: FabFilterColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return FabEnumSelector(
      label: '',
      value: _mode.index,
      options: const ['MAN', 'AUTO', 'RHR'],
      color: _modeAccent(_mode),
      onChanged: (i) => setState(() => _mode = PunchMode.values[i]),
    );
  }

  Widget _buildRecordButton(bool isIdle) {
    return GestureDetector(
      onTap: isIdle ? _startRecording : _stopRecording,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isIdle
              ? FabFilterColors.red.withValues(alpha: 0.2)
              : FabFilterColors.bgElevated,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isIdle ? FabFilterColors.red : FabFilterColors.textTertiary,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isIdle ? Icons.fiber_manual_record : Icons.stop,
              size: 10,
              color: isIdle ? FabFilterColors.red : FabFilterColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              isIdle ? 'REC' : 'STOP',
              style: FabFilterText.paramLabel.copyWith(
                color: isIdle ? FabFilterColors.red : FabFilterColors.textSecondary,
                fontSize: 9, fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _modeAccent(PunchMode mode) => switch (mode) {
    PunchMode.manual => FabFilterColors.orange,
    PunchMode.auto => FabFilterColors.red,
    PunchMode.rehearsal => FabFilterColors.green,
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // KNOBS ROW — punch points, pre/post roll, count-in
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildKnobsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Punch points
        _buildKnobSection('PUNCH POINTS', [
          _buildTimeKnob(
            label: 'IN',
            time: _punchInTime,
            max: 120.0,
            color: FabFilterColors.orange,
            onChanged: (v) => setState(() {
              _punchInTime = v;
              if (_punchOutTime < _punchInTime + 0.5) {
                _punchOutTime = _punchInTime + 0.5;
              }
            }),
          ),
          const SizedBox(width: 8),
          _buildTimeKnob(
            label: 'OUT',
            time: _punchOutTime,
            max: 120.0,
            color: FabFilterColors.cyan,
            onChanged: (v) => setState(() {
              _punchOutTime = v;
              if (_punchInTime > _punchOutTime - 0.5) {
                _punchInTime = _punchOutTime - 0.5;
              }
            }),
          ),
        ]),
        _buildDivider(),
        // Pre/Post roll
        _buildKnobSection('ROLL', [
          _buildTimeKnob(
            label: 'PRE',
            time: _preRollSeconds,
            max: 10.0,
            color: FabFilterColors.yellow,
            onChanged: (v) => setState(() => _preRollSeconds = v),
          ),
          const SizedBox(width: 8),
          _buildTimeKnob(
            label: 'POST',
            time: _postRollSeconds,
            max: 5.0,
            color: FabFilterColors.blue,
            onChanged: (v) => setState(() => _postRollSeconds = v),
          ),
        ]),
        _buildDivider(),
        // Count-in + status
        _buildCountInSection(),
      ],
    );
  }

  Widget _buildKnobSection(String title, List<Widget> children) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FabSectionLabel(title, color: FabFilterColors.textTertiary),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeKnob({
    required String label,
    required double time,
    required double max,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    final normalized = (time / max).clamp(0.0, 1.0);
    return FabFilterKnob(
      value: normalized,
      label: label,
      display: _formatTime(time),
      color: color,
      size: 52,
      defaultValue: 0.0,
      onChanged: (v) => onChanged(v * max),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 80,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: FabFilterColors.borderSubtle,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COUNT-IN SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCountInSection() {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FabSectionLabel('COUNT-IN', color: FabFilterColors.textTertiary),
          const SizedBox(height: 6),
          FabCompactToggle(
            label: _countInEnabled ? 'ON' : 'OFF',
            active: _countInEnabled,
            onToggle: () => setState(() => _countInEnabled = !_countInEnabled),
            color: FabFilterColors.green,
          ),
          const SizedBox(height: 6),
          if (_countInEnabled)
            FabMiniSlider(
              label: 'BAR',
              value: (_countInBars - 1) / 3.0, // 1-4 bars mapped to 0-1
              display: '$_countInBars',
              activeColor: FabFilterColors.green,
              labelWidth: 26,
              displayWidth: 14,
              onChanged: (v) => setState(() {
                _countInBars = (v * 3).round() + 1; // 0-1 mapped to 1-4
              }),
            ),
          const SizedBox(height: 6),
          // Rehearsal indicator
          if (_mode == PunchMode.rehearsal)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FabFilterColors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: FabFilterColors.green.withValues(alpha: 0.3)),
              ),
              child: Text('NO WRITE', style: FabFilterText.paramLabel.copyWith(
                color: FabFilterColors.green, fontSize: 7,
              )),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUNCH TIMELINE VISUALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTimeline() {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: FabFilterColors.bgVoid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: CustomPaint(
          painter: _PunchTimelinePainter(
            punchIn: _punchInTime,
            punchOut: _punchOutTime,
            preRoll: _preRollSeconds,
            postRoll: _postRollSeconds,
            state: _service.state,
            modeColor: _modeAccent(_mode),
          ),
          size: const Size(double.infinity, 28),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATUS BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStatusBar() {
    final state = _service.state;
    if (state == PunchRecordingState.idle) {
      return SizedBox(
        height: 14,
        child: Row(
          children: [
            Text(
              '${_formatTime(_punchInTime)}  \u2192  ${_formatTime(_punchOutTime)}',
              style: FabFilterText.paramLabel.copyWith(
                color: FabFilterColors.textTertiary, fontSize: 8,
              ),
            ),
            const Spacer(),
            Text(
              'DUR ${_formatTime(_punchOutTime - _punchInTime)}',
              style: FabFilterText.paramLabel.copyWith(
                color: FabFilterColors.orange, fontSize: 8,
              ),
            ),
          ],
        ),
      );
    }

    final (label, color) = switch (state) {
      PunchRecordingState.preRoll => ('PRE-ROLL', FabFilterColors.yellow),
      PunchRecordingState.recording => ('RECORDING', FabFilterColors.red),
      PunchRecordingState.postRoll => ('POST-ROLL', FabFilterColors.blue),
      PunchRecordingState.stopped => ('STOPPED', FabFilterColors.textTertiary),
      PunchRecordingState.idle => ('', FabFilterColors.textTertiary),
    };

    return SizedBox(
      height: 14,
      child: Row(
        children: [
          if (state == PunchRecordingState.recording)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _PulsingDot(color: color),
            ),
          FabHorizontalMeter(
            label: '',
            value: _stateProgress(state),
            color: color,
            height: 10,
            showLabel: false,
          ),
          const SizedBox(width: 8),
          Text(label, style: FabFilterText.paramLabel.copyWith(
            color: color, fontSize: 8, fontWeight: FontWeight.bold,
          )),
        ],
      ),
    );
  }

  double _stateProgress(PunchRecordingState state) => switch (state) {
    PunchRecordingState.preRoll => 0.25,
    PunchRecordingState.recording => 0.7,
    PunchRecordingState.postRoll => 0.9,
    PunchRecordingState.stopped => 1.0,
    PunchRecordingState.idle => 0.0,
  };

  String _formatTime(double seconds) {
    final s = seconds.abs();
    final mins = s ~/ 60;
    final secs = s % 60;
    if (mins > 0) return '${mins}m${secs.toStringAsFixed(1)}s';
    return '${secs.toStringAsFixed(1)}s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PULSING DOT — recording status indicator
// ═══════════════════════════════════════════════════════════════════════════════

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
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
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.4 + _ctrl.value * 0.6),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.3 * _ctrl.value),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PUNCH TIMELINE PAINTER — FabFilter-styled zone visualization
// ═══════════════════════════════════════════════════════════════════════════════

class _PunchTimelinePainter extends CustomPainter {
  final double punchIn;
  final double punchOut;
  final double preRoll;
  final double postRoll;
  final PunchRecordingState state;
  final Color modeColor;

  const _PunchTimelinePainter({
    required this.punchIn,
    required this.punchOut,
    required this.preRoll,
    required this.postRoll,
    required this.state,
    required this.modeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalRange = (punchOut + postRoll) - (punchIn - preRoll);
    if (totalRange <= 0) return;
    final startTime = punchIn - preRoll;

    double timeToX(double t) => ((t - startTime) / totalRange) * size.width;

    // Pre-roll zone
    final preX0 = timeToX(startTime);
    final preX1 = timeToX(punchIn);
    canvas.drawRect(
      Rect.fromLTRB(preX0, 0, preX1, size.height),
      Paint()..color = FabFilterColors.yellow.withValues(alpha: 0.1),
    );

    // Recording zone
    final recX0 = timeToX(punchIn);
    final recX1 = timeToX(punchOut);
    canvas.drawRect(
      Rect.fromLTRB(recX0, 0, recX1, size.height),
      Paint()..color = modeColor.withValues(alpha: 0.15),
    );

    // Post-roll zone
    final postX0 = timeToX(punchOut);
    final postX1 = timeToX(punchOut + postRoll);
    canvas.drawRect(
      Rect.fromLTRB(postX0, 0, postX1, size.height),
      Paint()..color = FabFilterColors.blue.withValues(alpha: 0.1),
    );

    // Punch in marker
    final markerPaint = Paint()
      ..color = FabFilterColors.orange
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(recX0, 0), Offset(recX0, size.height), markerPaint,
    );

    // Punch out marker
    canvas.drawLine(
      Offset(recX1, 0), Offset(recX1, size.height),
      markerPaint..color = FabFilterColors.cyan,
    );

    // Zone labels
    const labelStyle = TextStyle(
      fontSize: 7,
      color: FabFilterColors.textTertiary,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.5,
    );
    _drawLabel(canvas, 'PRE', Offset((preX0 + preX1) / 2, size.height / 2), labelStyle);
    _drawLabel(canvas, 'REC', Offset((recX0 + recX1) / 2, size.height / 2), labelStyle);
    _drawLabel(canvas, 'POST', Offset((postX0 + postX1) / 2, size.height / 2), labelStyle);

    // Active state highlight
    if (state == PunchRecordingState.recording) {
      canvas.drawRect(
        Rect.fromLTRB(recX0, 0, recX1, size.height),
        Paint()
          ..color = FabFilterColors.red.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        Rect.fromLTRB(recX0, 0, recX1, size.height),
        Paint()
          ..color = FabFilterColors.red.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
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
      old.punchIn != punchIn ||
      old.punchOut != punchOut ||
      old.preRoll != preRoll ||
      old.postRoll != postRoll ||
      old.state != state ||
      old.modeColor != modeColor;
}
