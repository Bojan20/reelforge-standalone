/// FluxForge Studio Splash Screen
///
/// Professional intro screen with logo animation
/// Shown before the main application loads

import 'package:flutter/material.dart';
import 'dart:async';
import '../theme/fluxforge_theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final String? loadingMessage;
  final double? progress;
  final bool hasError;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const SplashScreen({
    super.key,
    required this.onComplete,
    this.loadingMessage,
    this.progress,
    this.hasError = false,
    this.errorMessage,
    this.onRetry,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _progressController;
  late AnimationController _pulseController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _progressOpacity;
  late Animation<double> _glowIntensity;

  @override
  void initState() {
    super.initState();

    // Logo animation
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: Curves.elasticOut,
      ),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    // Text animation
    _textController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: Curves.easeOut,
      ),
    );

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _textController,
        curve: Curves.easeOutCubic,
      ),
    );

    // Progress bar animation
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _progressOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _progressController,
        curve: Curves.easeOut,
      ),
    );

    // Pulse animation for logo glow
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _glowIntensity = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Start animations sequence
    _startAnimations();
  }

  bool _disposed = false;

  void _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (_disposed) return;
    _logoController.forward();

    await Future.delayed(const Duration(milliseconds: 600));
    if (_disposed) return;
    _textController.forward();

    await Future.delayed(const Duration(milliseconds: 400));
    if (_disposed) return;
    _progressController.forward();
  }

  @override
  void dispose() {
    _disposed = true;
    _logoController.dispose();
    _textController.dispose();
    _progressController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FluxForgeTheme.bgVoid,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [
                  FluxForgeTheme.bgMid,
                  FluxForgeTheme.bgVoid,
                ],
              ),
            ),
          ),

          // Subtle grid pattern
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(),
            ),
          ),

          // Main content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo with glow effect
                AnimatedBuilder(
                  animation: Listenable.merge([_logoController, _pulseController]),
                  builder: (context, child) {
                    return Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: FluxForgeTheme.accentBlue
                                    .withAlpha((255 * _glowIntensity.value * 0.6).round()),
                                blurRadius: 40 * _glowIntensity.value,
                                spreadRadius: 10 * _glowIntensity.value,
                              ),
                            ],
                          ),
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: _buildLogo(),
                ),

                const SizedBox(height: 40),

                // Title
                AnimatedBuilder(
                  animation: _textController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _textOpacity.value,
                      child: SlideTransition(
                        position: _textSlide,
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            FluxForgeTheme.accentBlue,
                            FluxForgeTheme.accentCyan,
                          ],
                        ).createShader(bounds),
                        child: Text(
                          'FluxForge Studio',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 8,
                            color: FluxForgeTheme.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'AUTHORING TOOL & DAW',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 6,
                          color: FluxForgeTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 60),

                // Loading indicator or error
                AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, _) {
                    return Opacity(
                      opacity: _progressOpacity.value,
                      child: widget.hasError
                          ? _buildError()
                          : _buildProgress(),
                    );
                  },
                ),
              ],
            ),
          ),

          // Version info at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: AnimatedBuilder(
              animation: _textController,
              builder: (context, child) {
                return Opacity(
                  opacity: _textOpacity.value * 0.5,
                  child: child,
                );
              },
              child: Column(
                children: [
                  Text(
                    'v0.1.0',
                    style: TextStyle(
                      fontSize: 11,
                      color: FluxForgeTheme.textTertiary,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '© 2025 VanVinkl Studio',
                    style: TextStyle(
                      fontSize: 10,
                      color: FluxForgeTheme.textDisabled,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            FluxForgeTheme.bgSurface,
            FluxForgeTheme.bgMid,
          ],
        ),
        border: Border.all(
          color: FluxForgeTheme.accentBlue.withAlpha(128),
          width: 2,
        ),
      ),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer ring
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: FluxForgeTheme.accentBlue.withAlpha(77),
                  width: 1,
                ),
              ),
            ),
            // Inner symbol - stylized R
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  FluxForgeTheme.accentBlue,
                  FluxForgeTheme.accentCyan,
                ],
              ).createShader(bounds),
              child: Text(
                'R',
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w200,
                  color: FluxForgeTheme.textPrimary,
                  letterSpacing: -2,
                ),
              ),
            ),
            // Audio waveform decoration
            Positioned(
              bottom: 24,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(7, (i) {
                  final heights = [4.0, 8.0, 14.0, 18.0, 14.0, 8.0, 4.0];
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    width: 3,
                    height: heights[i],
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentBlue.withAlpha(179),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return SizedBox(
      width: 280,
      child: Column(
        children: [
          // Progress bar
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgElevated,
              borderRadius: BorderRadius.circular(1.5),
            ),
            child: widget.progress != null
                ? FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: widget.progress!.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            FluxForgeTheme.accentBlue,
                            FluxForgeTheme.accentCyan,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  )
                : const _IndeterminateProgress(),
          ),
          const SizedBox(height: 16),
          // Loading message
          Text(
            widget.loadingMessage ?? 'Initializing...',
            style: TextStyle(
              fontSize: 12,
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Column(
      children: [
        Icon(
          Icons.error_outline,
          color: FluxForgeTheme.errorRed,
          size: 32,
        ),
        const SizedBox(height: 12),
        Text(
          'Initialization Failed',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: FluxForgeTheme.errorRed,
          ),
        ),
        if (widget.errorMessage != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: 300,
            child: Text(
              widget.errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (widget.onRetry != null)
          TextButton(
            onPressed: widget.onRetry,
            style: TextButton.styleFrom(
              foregroundColor: FluxForgeTheme.accentBlue,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Retry'),
          ),
      ],
    );
  }
}

/// Indeterminate progress animation
class _IndeterminateProgress extends StatefulWidget {
  const _IndeterminateProgress();

  @override
  State<_IndeterminateProgress> createState() => _IndeterminateProgressState();
}

class _IndeterminateProgressState extends State<_IndeterminateProgress>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return FractionallySizedBox(
          widthFactor: 0.3,
          alignment: Alignment(-1.0 + 2.0 * _controller.value, 0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  FluxForgeTheme.accentBlue,
                  FluxForgeTheme.accentCyan,
                ],
              ),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        );
      },
    );
  }
}

/// Background grid painter
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.textPrimary.withAlpha(5)
      ..strokeWidth = 0.5;

    const spacing = 50.0;

    // Vertical lines
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontal lines
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
