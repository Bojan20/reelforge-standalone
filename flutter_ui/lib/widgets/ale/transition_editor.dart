/// Transition Editor Widget
///
/// Editor for ALE transition profiles with sync modes, fades, and curves.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ale_provider.dart';

/// Transition profile list and editor
class TransitionEditor extends StatefulWidget {
  final VoidCallback? onTransitionChanged;

  const TransitionEditor({
    super.key,
    this.onTransitionChanged,
  });

  @override
  State<TransitionEditor> createState() => _TransitionEditorState();
}

class _TransitionEditorState extends State<TransitionEditor> {
  String? _selectedTransitionId;

  @override
  Widget build(BuildContext context) {
    return Consumer<AleProvider>(
      builder: (context, ale, child) {
        final transitions = ale.profile?.transitions ?? {};

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2a2a35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(transitions.length),

              // Transition list
              Expanded(
                child: transitions.isEmpty
                    ? _buildEmptyState()
                    : _buildTransitionList(transitions),
              ),

              // Selected transition details
              if (_selectedTransitionId != null &&
                  transitions.containsKey(_selectedTransitionId))
                _buildTransitionDetails(transitions[_selectedTransitionId]!),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz, color: Color(0xFF40c8ff), size: 18),
          const SizedBox(width: 8),
          const Text(
            'Transitions',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF2a2a35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 11,
              ),
            ),
          ),
          const Spacer(),
          _ActionButton(
            icon: Icons.add,
            tooltip: 'Add Transition',
            onPressed: () => _showAddTransitionDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.swap_horizontal_circle_outlined,
            color: Color(0xFF666666),
            size: 32,
          ),
          const SizedBox(height: 8),
          const Text(
            'No custom transitions',
            style: TextStyle(color: Color(0xFF666666), fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            'Using default transition',
            style: TextStyle(color: Color(0xFF555555), fontSize: 10),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _showAddTransitionDialog(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Transition'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF40c8ff),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransitionList(Map<String, AleTransitionProfile> transitions) {
    final sortedIds = transitions.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: sortedIds.length,
      itemBuilder: (context, index) {
        final id = sortedIds[index];
        final trans = transitions[id]!;
        final isSelected = id == _selectedTransitionId;

        return _TransitionTile(
          transition: trans,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedTransitionId = isSelected ? null : id;
            });
          },
        );
      },
    );
  }

  Widget _buildTransitionDetails(AleTransitionProfile trans) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        border: Border(
          top: BorderSide(color: Color(0xFF2a2a35)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Name
          Text(
            trans.name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 12),

          // Sync mode
          Row(
            children: [
              const SizedBox(
                width: 80,
                child: Text(
                  'Sync Mode',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 11),
                ),
              ),
              _SyncModeBadge(mode: trans.syncMode),
            ],
          ),

          const SizedBox(height: 8),

          // Fade times
          Row(
            children: [
              Expanded(
                child: _FadeInfo(
                  label: 'Fade In',
                  durationMs: trans.fadeInMs,
                  color: const Color(0xFF40ff90),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FadeInfo(
                  label: 'Fade Out',
                  durationMs: trans.fadeOutMs,
                  color: const Color(0xFFff9040),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Overlap
          Row(
            children: [
              const SizedBox(
                width: 80,
                child: Text(
                  'Overlap',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 11),
                ),
              ),
              Expanded(
                child: _OverlapBar(overlap: trans.overlap),
              ),
              const SizedBox(width: 8),
              Text(
                '${(trans.overlap * 100).toInt()}%',
                style: const TextStyle(
                  color: Color(0xFF4a9eff),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Fade curve preview
          SizedBox(
            height: 60,
            child: _FadeCurvePreview(
              fadeInMs: trans.fadeInMs,
              fadeOutMs: trans.fadeOutMs,
              overlap: trans.overlap,
            ),
          ),

          const SizedBox(height: 12),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _selectedTransitionId = null),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF888888),
                ),
                child: const Text('Close'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () {
                  // TODO: Implement transition editing
                },
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF4a9eff),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddTransitionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a20),
        title: const Text(
          'Add Transition',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Transition creation wizard coming soon.',
          style: TextStyle(color: Color(0xFF888888)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Transition list tile
class _TransitionTile extends StatelessWidget {
  final AleTransitionProfile transition;
  final bool isSelected;
  final VoidCallback? onTap;

  const _TransitionTile({
    required this.transition,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF2a2a35)
                : const Color(0xFF121216),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF40c8ff).withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF40c8ff).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.swap_horiz,
                  color: Color(0xFF40c8ff),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transition.name,
                      style: const TextStyle(
                        color: Color(0xFFcccccc),
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${transition.fadeInMs}ms / ${transition.fadeOutMs}ms',
                      style: const TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),

              // Sync mode badge
              _SyncModeBadge(mode: transition.syncMode, small: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sync mode badge
class _SyncModeBadge extends StatelessWidget {
  final SyncMode mode;
  final bool small;

  const _SyncModeBadge({
    required this.mode,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _getModeInfo();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: small ? 12 : 14),
          SizedBox(width: small ? 4 : 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: small ? 9 : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, IconData) _getModeInfo() {
    return switch (mode) {
      SyncMode.immediate => ('Immediate', const Color(0xFF4a9eff), Icons.bolt),
      SyncMode.beat => ('Beat', const Color(0xFF40ff90), Icons.music_note),
      SyncMode.bar => ('Bar', const Color(0xFFffff40), Icons.view_week),
      SyncMode.phrase => ('Phrase', const Color(0xFFff9040), Icons.view_module),
      SyncMode.nextDownbeat => ('Downbeat', const Color(0xFFff4060), Icons.arrow_downward),
      SyncMode.custom => ('Custom', const Color(0xFF888888), Icons.tune),
    };
  }
}

/// Fade info display
class _FadeInfo extends StatelessWidget {
  final String label;
  final int durationMs;
  final Color color;

  const _FadeInfo({
    required this.label,
    required this.durationMs,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${durationMs}ms',
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Overlap bar
class _OverlapBar extends StatelessWidget {
  final double overlap;

  const _OverlapBar({required this.overlap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: const Color(0xFF2a2a35),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          FractionallySizedBox(
            widthFactor: overlap.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4a9eff), Color(0xFF40c8ff)],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fade curve preview visualization
class _FadeCurvePreview extends StatelessWidget {
  final int fadeInMs;
  final int fadeOutMs;
  final double overlap;

  const _FadeCurvePreview({
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.overlap,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FadeCurvePainter(
        fadeInMs: fadeInMs,
        fadeOutMs: fadeOutMs,
        overlap: overlap,
      ),
      size: Size.infinite,
    );
  }
}

/// Fade curve painter
class _FadeCurvePainter extends CustomPainter {
  final int fadeInMs;
  final int fadeOutMs;
  final double overlap;

  _FadeCurvePainter({
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.overlap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalDuration = fadeOutMs + fadeInMs * (1 - overlap);
    final fadeOutEnd = fadeOutMs / totalDuration;
    final fadeInStart = 1.0 - fadeInMs / totalDuration;

    // Background grid
    final gridPaint = Paint()
      ..color = const Color(0xFF2a2a35)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      final y = i / 4 * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Fade out curve (from layer)
    final fadeOutPath = Path();
    fadeOutPath.moveTo(0, 0);

    for (double t = 0; t <= fadeOutEnd; t += 0.01) {
      final x = t * size.width;
      final progress = t / fadeOutEnd;
      final curve = _easeOutQuad(progress);
      final y = curve * size.height;
      fadeOutPath.lineTo(x, y);
    }

    fadeOutPath.lineTo(fadeOutEnd * size.width, size.height);
    fadeOutPath.lineTo(size.width, size.height);
    fadeOutPath.lineTo(size.width, size.height);
    fadeOutPath.close();

    canvas.drawPath(
      fadeOutPath,
      Paint()
        ..color = const Color(0xFFff9040).withValues(alpha: 0.2)
        ..style = PaintingStyle.fill,
    );

    // Fade in curve (to layer)
    final fadeInPath = Path();
    fadeInPath.moveTo(0, size.height);
    fadeInPath.lineTo(fadeInStart * size.width, size.height);

    for (double t = fadeInStart; t <= 1.0; t += 0.01) {
      final x = t * size.width;
      final progress = (t - fadeInStart) / (1.0 - fadeInStart);
      final curve = 1.0 - _easeOutQuad(progress);
      final y = curve * size.height;
      fadeInPath.lineTo(x, y);
    }

    fadeInPath.lineTo(size.width, 0);
    fadeInPath.close();

    canvas.drawPath(
      fadeInPath,
      Paint()
        ..color = const Color(0xFF40ff90).withValues(alpha: 0.2)
        ..style = PaintingStyle.fill,
    );

    // Fade out line
    final fadeOutLinePath = Path();
    fadeOutLinePath.moveTo(0, 0);

    for (double t = 0; t <= fadeOutEnd; t += 0.01) {
      final x = t * size.width;
      final progress = t / fadeOutEnd;
      final curve = _easeOutQuad(progress);
      final y = curve * size.height;
      fadeOutLinePath.lineTo(x, y);
    }

    canvas.drawPath(
      fadeOutLinePath,
      Paint()
        ..color = const Color(0xFFff9040)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    // Fade in line
    final fadeInLinePath = Path();
    fadeInLinePath.moveTo(fadeInStart * size.width, size.height);

    for (double t = fadeInStart; t <= 1.0; t += 0.01) {
      final x = t * size.width;
      final progress = (t - fadeInStart) / (1.0 - fadeInStart);
      final curve = 1.0 - _easeOutQuad(progress);
      final y = curve * size.height;
      fadeInLinePath.lineTo(x, y);
    }

    canvas.drawPath(
      fadeInLinePath,
      Paint()
        ..color = const Color(0xFF40ff90)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    // Overlap region indicator
    if (overlap > 0) {
      final overlapStart = fadeInStart;
      final overlapEnd = fadeOutEnd;

      if (overlapStart < overlapEnd) {
        canvas.drawRect(
          Rect.fromLTRB(
            overlapStart * size.width,
            0,
            overlapEnd * size.width,
            size.height,
          ),
          Paint()
            ..color = const Color(0xFF4a9eff).withValues(alpha: 0.1)
            ..style = PaintingStyle.fill,
        );
      }
    }

    // Labels
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // From label
    textPainter.text = const TextSpan(
      text: 'FROM',
      style: TextStyle(
        color: Color(0xFFff9040),
        fontSize: 9,
        fontWeight: FontWeight.w600,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(4, 4));

    // To label
    textPainter.text = const TextSpan(
      text: 'TO',
      style: TextStyle(
        color: Color(0xFF40ff90),
        fontSize: 9,
        fontWeight: FontWeight.w600,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - textPainter.width - 4, 4));
  }

  double _easeOutQuad(double t) {
    return t * (2 - t);
  }

  @override
  bool shouldRepaint(_FadeCurvePainter oldDelegate) {
    return fadeInMs != oldDelegate.fadeInMs ||
        fadeOutMs != oldDelegate.fadeOutMs ||
        overlap != oldDelegate.overlap;
  }
}

/// Small action button
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: const Color(0xFF2a2a35),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: const Color(0xFF888888),
            size: 14,
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
