/// Glass Timeline Wrapper
///
/// Theme-aware wrapper that applies Glass styling to any timeline widget
/// when in Glass mode. Uses simple child wrapping approach.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../providers/theme_mode_provider.dart';

/// Theme-aware wrapper for Timeline
/// Automatically applies Glass styling when in Glass mode
class GlassTimelineWrapper extends StatelessWidget {
  final Widget child;

  const GlassTimelineWrapper({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: LiquidGlassTheme.blurLight,
            sigmaY: LiquidGlassTheme.blurLight,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.06),
                  Colors.white.withValues(alpha: 0.03),
                  Colors.black.withValues(alpha: 0.1),
                ],
              ),
            ),
            child: child,
          ),
        ),
      );
    }

    return child;
  }
}

/// Glass-styled clip widget for timeline
class GlassSimpleClip extends StatefulWidget {
  final String name;
  final Color color;
  final double width;
  final double height;
  final bool isSelected;
  final bool isMuted;
  final Widget? waveform;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const GlassSimpleClip({
    super.key,
    required this.name,
    required this.color,
    required this.width,
    required this.height,
    this.isSelected = false,
    this.isMuted = false,
    this.waveform,
    this.onTap,
    this.onDoubleTap,
  });

  @override
  State<GlassSimpleClip> createState() => _GlassSimpleClipState();
}

class _GlassSimpleClipState extends State<GlassSimpleClip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 4,
              sigmaY: 4,
            ),
            child: AnimatedContainer(
              duration: LiquidGlassTheme.animFast,
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.color.withValues(alpha: widget.isSelected ? 0.5 : 0.35),
                    widget.color.withValues(alpha: widget.isSelected ? 0.35 : 0.2),
                    widget.color.withValues(alpha: 0.15),
                  ],
                ),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: widget.isSelected
                      ? widget.color
                      : widget.color.withValues(alpha: _isHovered ? 0.8 : 0.5),
                  width: widget.isSelected ? 2 : 1,
                ),
                boxShadow: widget.isSelected
                    ? [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.4),
                          blurRadius: 8,
                          spreadRadius: -2,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                children: [
                  // Specular highlight
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.4),
                            Colors.white.withValues(alpha: 0.1),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Waveform (if provided)
                  if (widget.waveform != null)
                    Positioned.fill(
                      child: Opacity(
                        opacity: widget.isMuted ? 0.3 : 1.0,
                        child: widget.waveform!,
                      ),
                    ),

                  // Clip name
                  Positioned(
                    top: 2,
                    left: 4,
                    right: 4,
                    child: Text(
                      widget.name,
                      style: TextStyle(
                        color: widget.isMuted
                            ? LiquidGlassTheme.textTertiary
                            : Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Muted overlay
                  if (widget.isMuted)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.volume_off,
                            color: LiquidGlassTheme.textTertiary,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass-styled time ruler for timeline
class GlassTimeRuler extends StatelessWidget {
  final double zoom;
  final double scrollOffset;
  final double totalDuration;
  final double tempo;
  final int beatsPerBar;
  final double height;
  final ValueChanged<double>? onPositionTap;

  const GlassTimeRuler({
    super.key,
    required this.zoom,
    required this.scrollOffset,
    required this.totalDuration,
    this.tempo = 120,
    this.beatsPerBar = 4,
    this.height = 24,
    this.onPositionTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurLight,
          sigmaY: LiquidGlassTheme.blurLight,
        ),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.3),
                Colors.black.withValues(alpha: 0.2),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          child: CustomPaint(
            painter: _GlassTimeRulerPainter(
              zoom: zoom,
              scrollOffset: scrollOffset,
              totalDuration: totalDuration,
              tempo: tempo,
              beatsPerBar: beatsPerBar,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassTimeRulerPainter extends CustomPainter {
  final double zoom;
  final double scrollOffset;
  final double totalDuration;
  final double tempo;
  final int beatsPerBar;

  _GlassTimeRulerPainter({
    required this.zoom,
    required this.scrollOffset,
    required this.totalDuration,
    required this.tempo,
    required this.beatsPerBar,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final beatDuration = 60.0 / tempo;
    final barDuration = beatDuration * beatsPerBar;

    // Calculate visible range
    final visibleStart = scrollOffset;
    final visibleEnd = scrollOffset + (size.width / zoom);

    // Draw bars
    final paint = Paint()
      ..color = LiquidGlassTheme.textTertiary
      ..strokeWidth = 1;

    final textStyle = TextStyle(
      color: LiquidGlassTheme.textSecondary,
      fontSize: 9,
      fontFamily: 'JetBrains Mono',
    );

    int barStart = (visibleStart / barDuration).floor();
    int barEnd = (visibleEnd / barDuration).ceil();

    for (int bar = barStart; bar <= barEnd; bar++) {
      final time = bar * barDuration;
      final x = (time - scrollOffset) * zoom;

      if (x >= 0 && x <= size.width) {
        // Bar line
        canvas.drawLine(
          Offset(x, size.height - 8),
          Offset(x, size.height),
          paint,
        );

        // Bar number
        final textSpan = TextSpan(
          text: '${bar + 1}',
          style: textStyle,
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 2, 4));
      }

      // Draw beat lines
      for (int beat = 1; beat < beatsPerBar; beat++) {
        final beatTime = time + (beat * beatDuration);
        final beatX = (beatTime - scrollOffset) * zoom;
        if (beatX >= 0 && beatX <= size.width) {
          canvas.drawLine(
            Offset(beatX, size.height - 4),
            Offset(beatX, size.height),
            paint..color = LiquidGlassTheme.textTertiary.withValues(alpha: 0.5),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlassTimeRulerPainter oldDelegate) {
    return zoom != oldDelegate.zoom ||
        scrollOffset != oldDelegate.scrollOffset ||
        totalDuration != oldDelegate.totalDuration ||
        tempo != oldDelegate.tempo ||
        beatsPerBar != oldDelegate.beatsPerBar;
  }
}
