/// FluxForge Studio Onboarding Tutorial Overlay
///
/// Interactive 5-step tutorial guiding users through core workflows:
/// 1. Create event
/// 2. Assign audio
/// 3. Test playback
/// 4. Adjust timing
/// 5. Export
///
/// Features:
/// - Spotlight highlighting with dimmed background
/// - Step-by-step guidance with next/back/skip
/// - Progress indicator
/// - Persistent completion tracking via SharedPreferences
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../providers/middleware_provider.dart';
import '../../providers/slot_lab_provider.dart';
import 'tutorial_steps.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Main onboarding overlay widget
class OnboardingOverlay extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback onSkip;
  final bool showInSlotLab;

  const OnboardingOverlay({
    super.key,
    required this.onComplete,
    required this.onSkip,
    this.showInSlotLab = false,
  });

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();

  /// Show onboarding overlay if user hasn't completed it
  static Future<void> showIfNeeded(
    BuildContext context, {
    bool forceShow = false,
    bool showInSlotLab = false,
  }) async {
    if (!forceShow) {
      final completed = await OnboardingState.instance.isCompleted();
      if (completed) return;
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (ctx) => OnboardingOverlay(
        showInSlotLab: showInSlotLab,
        onComplete: () {
          Navigator.of(ctx).pop();
          OnboardingState.instance.markCompleted();
        },
        onSkip: () {
          Navigator.of(ctx).pop();
          OnboardingState.instance.markSkipped();
        },
      ),
    );
  }
}

class _OnboardingOverlayState extends State<OnboardingOverlay>
    with SingleTickerProviderStateMixin {
  int _currentStepIndex = 0;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late List<TutorialStep> _steps;

  @override
  void initState() {
    super.initState();

    // Select steps based on section
    _steps = widget.showInSlotLab
        ? TutorialSteps.slotLabSteps
        : TutorialSteps.basicSteps;

    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStepIndex < _steps.length - 1) {
      setState(() {
        _currentStepIndex++;
      });
      _animController.forward(from: 0);
    } else {
      widget.onComplete();
    }
  }

  void _previousStep() {
    if (_currentStepIndex > 0) {
      setState(() {
        _currentStepIndex--;
      });
      _animController.forward(from: 0);
    }
  }

  void _skip() {
    widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    final currentStep = _steps[_currentStepIndex];
    final progress = (_currentStepIndex + 1) / _steps.length;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Dimmed background with spotlight cutout
          CustomPaint(
            size: MediaQuery.of(context).size,
            painter: _SpotlightPainter(
              spotlightRect: currentStep.spotlightRect,
              spotlightRadius: currentStep.spotlightRadius,
            ),
          ),

          // Tutorial content card
          Positioned(
            left: currentStep.tooltipPosition.dx,
            top: currentStep.tooltipPosition.dy,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _TutorialCard(
                step: currentStep,
                stepNumber: _currentStepIndex + 1,
                totalSteps: _steps.length,
                progress: progress,
                onNext: _nextStep,
                onPrevious: _currentStepIndex > 0 ? _previousStep : null,
                onSkip: _skip,
                isLastStep: _currentStepIndex == _steps.length - 1,
              ),
            ),
          ),

          // Arrow pointing to spotlight (if needed)
          if (currentStep.showArrow)
            Positioned(
              left: currentStep.arrowPosition.dx,
              top: currentStep.arrowPosition.dy,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: _AnimatedArrow(
                  direction: currentStep.arrowDirection,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Spotlight painter for dimmed background with cutout
class _SpotlightPainter extends CustomPainter {
  final Rect? spotlightRect;
  final double spotlightRadius;

  _SpotlightPainter({
    this.spotlightRect,
    this.spotlightRadius = 8.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    if (spotlightRect != null) {
      // Create path with spotlight cutout
      final path = Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRRect(
          RRect.fromRectAndRadius(
            spotlightRect!,
            Radius.circular(spotlightRadius),
          ),
        )
        ..fillType = PathFillType.evenOdd;

      canvas.drawPath(path, dimPaint);

      // Draw glow around spotlight
      final glowPaint = Paint()
        ..color = FluxForgeTheme.accentBlue.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          spotlightRect!.inflate(4),
          Radius.circular(spotlightRadius + 4),
        ),
        glowPaint,
      );
    } else {
      // No spotlight, just dim everything
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        dimPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      spotlightRect != oldDelegate.spotlightRect ||
      spotlightRadius != oldDelegate.spotlightRadius;
}

/// Tutorial content card
class _TutorialCard extends StatelessWidget {
  final TutorialStep step;
  final int stepNumber;
  final int totalSteps;
  final double progress;
  final VoidCallback onNext;
  final VoidCallback? onPrevious;
  final VoidCallback onSkip;
  final bool isLastStep;

  const _TutorialCard({
    required this.step,
    required this.stepNumber,
    required this.totalSteps,
    required this.progress,
    required this.onNext,
    this.onPrevious,
    required this.onSkip,
    required this.isLastStep,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      constraints: const BoxConstraints(maxHeight: 500),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with progress
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'STEP $stepNumber/$totalSteps',
                            style: const TextStyle(
                              color: FluxForgeTheme.accentBlue,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          step.icon,
                          color: step.iconColor,
                          size: 20,
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: FluxForgeTheme.textMuted,
                      ),
                      onPressed: onSkip,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: FluxForgeTheme.bgDeep,
                    valueColor: AlwaysStoppedAnimation(step.iconColor),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    step.title,
                    style: const TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Description
                  Text(
                    step.description,
                    style: const TextStyle(
                      color: FluxForgeTheme.textMuted,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),

                  // Instructions
                  if (step.instructions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.bgMid,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: step.iconColor.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                color: step.iconColor,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'HOW TO:',
                                style: TextStyle(
                                  color: step.iconColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...step.instructions.map((instruction) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 6),
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: step.iconColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        instruction,
                                        style: const TextStyle(
                                          color: FluxForgeTheme.textSecondary,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                  ],

                  // Tips
                  if (step.tips.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...step.tips.map((tip) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.star,
                                color: FluxForgeTheme.warningOrange,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  tip,
                                  style: const TextStyle(
                                    color: FluxForgeTheme.textSecondary,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),
          ),

          // Footer with navigation buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Back button
                if (onPrevious != null)
                  TextButton.icon(
                    onPressed: onPrevious,
                    icon: const Icon(
                      Icons.arrow_back,
                      size: 16,
                    ),
                    label: const Text('BACK'),
                    style: TextButton.styleFrom(
                      foregroundColor: FluxForgeTheme.textMuted,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),

                // Next/Finish button
                ElevatedButton.icon(
                  onPressed: onNext,
                  icon: Icon(
                    isLastStep ? Icons.check : Icons.arrow_forward,
                    size: 16,
                  ),
                  label: Text(isLastStep ? 'FINISH' : 'NEXT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: step.iconColor,
                    foregroundColor: FluxForgeTheme.textPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
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
}

/// Animated arrow pointing to spotlight
class _AnimatedArrow extends StatefulWidget {
  final ArrowDirection direction;

  const _AnimatedArrow({
    required this.direction,
  });

  @override
  State<_AnimatedArrow> createState() => _AnimatedArrowState();
}

class _AnimatedArrowState extends State<_AnimatedArrow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0, end: 8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final offset = _getOffset();
        return Transform.translate(
          offset: offset,
          child: child,
        );
      },
      child: Icon(
        _getIconForDirection(),
        color: FluxForgeTheme.accentBlue,
        size: 32,
        shadows: [
          Shadow(
            color: FluxForgeTheme.accentBlue.withValues(alpha: 0.5),
            blurRadius: 8,
          ),
        ],
      ),
    );
  }

  Offset _getOffset() {
    switch (widget.direction) {
      case ArrowDirection.up:
        return Offset(0, -_animation.value);
      case ArrowDirection.down:
        return Offset(0, _animation.value);
      case ArrowDirection.left:
        return Offset(-_animation.value, 0);
      case ArrowDirection.right:
        return Offset(_animation.value, 0);
    }
  }

  IconData _getIconForDirection() {
    switch (widget.direction) {
      case ArrowDirection.up:
        return Icons.arrow_upward_rounded;
      case ArrowDirection.down:
        return Icons.arrow_downward_rounded;
      case ArrowDirection.left:
        return Icons.arrow_back_rounded;
      case ArrowDirection.right:
        return Icons.arrow_forward_rounded;
    }
  }
}

/// Onboarding completion state manager
class OnboardingState {
  static final OnboardingState _instance = OnboardingState._internal();
  static OnboardingState get instance => _instance;

  OnboardingState._internal();

  static const String _keyCompleted = 'onboarding_completed';
  static const String _keySkipped = 'onboarding_skipped';

  Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyCompleted) ?? false;
  }

  Future<bool> isSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySkipped) ?? false;
  }

  Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCompleted, true);
    await prefs.setBool(_keySkipped, false);
  }

  Future<void> markSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySkipped, true);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCompleted);
    await prefs.remove(_keySkipped);
  }
}
