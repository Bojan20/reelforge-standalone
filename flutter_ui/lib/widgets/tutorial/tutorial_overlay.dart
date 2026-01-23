/// Tutorial Overlay System (M4)
///
/// Interactive tutorial overlay that guides users through features.
/// Features:
/// - Spotlight effect on target elements
/// - Step-by-step navigation
/// - Progress indicator
/// - Skip/complete actions

import 'package:flutter/material.dart';
import 'tutorial_step.dart';

/// Tutorial overlay widget
class TutorialOverlay extends StatefulWidget {
  final Tutorial tutorial;
  final VoidCallback onComplete;
  final VoidCallback onSkip;
  final int initialStep;

  const TutorialOverlay({
    super.key,
    required this.tutorial,
    required this.onComplete,
    required this.onSkip,
    this.initialStep = 0,
  });

  /// Show tutorial as overlay
  static Future<bool> show(
    BuildContext context, {
    required Tutorial tutorial,
  }) async {
    final result = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: TutorialOverlay(
              tutorial: tutorial,
              onComplete: () => Navigator.of(context).pop(true),
              onSkip: () => Navigator.of(context).pop(false),
            ),
          );
        },
      ),
    );
    return result ?? false;
  }

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late int _currentStep;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _currentStep = widget.initialStep;
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();

    // Call onShow for initial step
    final step = widget.tutorial.steps[_currentStep];
    step.onShow?.call();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  TutorialStep get _step => widget.tutorial.steps[_currentStep];

  void _goToStep(int index) {
    if (index < 0 || index >= widget.tutorial.steps.length) return;

    // Call onHide for current step
    _step.onHide?.call();

    setState(() => _currentStep = index);

    // Call onShow for new step
    widget.tutorial.steps[index].onShow?.call();
  }

  void _handleAction(TutorialAction action) {
    switch (action.type) {
      case TutorialActionType.next:
        if (_step.canProceed?.call() ?? true) {
          if (_currentStep < widget.tutorial.steps.length - 1) {
            _goToStep(_currentStep + 1);
          } else {
            widget.onComplete();
          }
        }
        break;
      case TutorialActionType.previous:
        _goToStep(_currentStep - 1);
        break;
      case TutorialActionType.skip:
        widget.onSkip();
        break;
      case TutorialActionType.finish:
        widget.onComplete();
        break;
      case TutorialActionType.custom:
        action.onAction?.call();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Dark overlay with spotlight cutout
          _buildOverlay(),

          // Tutorial card
          _buildTutorialCard(),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return GestureDetector(
      onTap: () {}, // Absorb taps
      child: CustomPaint(
        size: MediaQuery.of(context).size,
        painter: _SpotlightPainter(
          targetRect: _getTargetRect(),
          padding: _step.highlightPadding,
          showSpotlight: _step.showSpotlight && _step.targetKey != null,
        ),
      ),
    );
  }

  Rect? _getTargetRect() {
    final key = _step.targetKey;
    if (key == null) return null;

    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;

    final position = renderBox.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      position.dx,
      position.dy,
      renderBox.size.width,
      renderBox.size.height,
    );
  }

  Widget _buildTutorialCard() {
    final targetRect = _getTargetRect();
    final screenSize = MediaQuery.of(context).size;

    // Calculate card position based on target and tooltip position
    double? left, right, top, bottom;
    const cardWidth = 320.0;
    const cardMargin = 16.0;

    if (targetRect != null) {
      switch (_step.tooltipPosition) {
        case TutorialTooltipPosition.top:
          bottom = screenSize.height - targetRect.top + cardMargin;
          left = (targetRect.left + targetRect.width / 2 - cardWidth / 2)
              .clamp(cardMargin, screenSize.width - cardWidth - cardMargin);
          break;
        case TutorialTooltipPosition.bottom:
          top = targetRect.bottom + cardMargin;
          left = (targetRect.left + targetRect.width / 2 - cardWidth / 2)
              .clamp(cardMargin, screenSize.width - cardWidth - cardMargin);
          break;
        case TutorialTooltipPosition.left:
          right = screenSize.width - targetRect.left + cardMargin;
          top = (targetRect.top + targetRect.height / 2 - 100)
              .clamp(cardMargin, screenSize.height - 200 - cardMargin);
          break;
        case TutorialTooltipPosition.right:
          left = targetRect.right + cardMargin;
          top = (targetRect.top + targetRect.height / 2 - 100)
              .clamp(cardMargin, screenSize.height - 200 - cardMargin);
          break;
        case TutorialTooltipPosition.center:
          // Center of screen
          break;
      }
    }

    // Default to center if no target
    if (left == null && right == null) {
      left = (screenSize.width - cardWidth) / 2;
    }
    if (top == null && bottom == null) {
      top = (screenSize.height - 200) / 2;
    }

    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: _TutorialCard(
          step: _step,
          currentStep: _currentStep,
          totalSteps: widget.tutorial.steps.length,
          onAction: _handleAction,
        ),
      ),
    );
  }
}

/// Spotlight painter for highlighting target elements
class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final double padding;
  final bool showSpotlight;

  _SpotlightPainter({
    this.targetRect,
    this.padding = 8.0,
    this.showSpotlight = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.75);

    if (targetRect == null || !showSpotlight) {
      // No spotlight - just dark overlay
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }

    // Draw overlay with spotlight cutout
    final spotlightRect = Rect.fromLTRB(
      targetRect!.left - padding,
      targetRect!.top - padding,
      targetRect!.right + padding,
      targetRect!.bottom + padding,
    );

    // Create path with hole
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(spotlightRect, const Radius.circular(8)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Draw spotlight border
    final borderPaint = Paint()
      ..color = const Color(0xFF4A9EFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(spotlightRect, const Radius.circular(8)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return targetRect != oldDelegate.targetRect ||
        padding != oldDelegate.padding ||
        showSpotlight != oldDelegate.showSpotlight;
  }
}

/// Tutorial card widget
class _TutorialCard extends StatelessWidget {
  final TutorialStep step;
  final int currentStep;
  final int totalSteps;
  final void Function(TutorialAction) onAction;

  const _TutorialCard({
    required this.step,
    required this.currentStep,
    required this.totalSteps,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF4A9EFF).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon and title
                Row(
                  children: [
                    if (step.icon != null) ...[
                      Icon(
                        step.icon,
                        color: const Color(0xFF4A9EFF),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        step.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Description
                Text(
                  step.content,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),

                // Image (if present)
                if (step.imagePath != null) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      step.imagePath!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Actions
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF4A9EFF).withValues(alpha: 0.1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          // Progress indicator
          ...List.generate(totalSteps, (index) {
            final isActive = index == currentStep;
            final isPast = index < currentStep;
            return Container(
              width: isActive ? 24 : 8,
              height: 8,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: isPast || isActive
                    ? const Color(0xFF4A9EFF)
                    : Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),

          const Spacer(),

          // Step counter
          Text(
            '${currentStep + 1} / $totalSteps',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (int i = 0; i < step.actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _buildActionButton(step.actions[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton(TutorialAction action) {
    if (action.isPrimary) {
      return ElevatedButton(
        onPressed: () => onAction(action),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4A9EFF),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        child: Text(action.label),
      );
    }

    return TextButton(
      onPressed: () => onAction(action),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: 0.7),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: Text(action.label),
    );
  }
}

/// Tutorial launcher widget (for Help menu)
class TutorialLauncher extends StatelessWidget {
  final List<Tutorial> tutorials;
  final void Function(Tutorial) onTutorialSelected;

  const TutorialLauncher({
    super.key,
    required this.tutorials,
    required this.onTutorialSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Group tutorials by category
    final grouped = <TutorialCategory, List<Tutorial>>{};
    for (final tutorial in tutorials) {
      grouped.putIfAbsent(tutorial.category, () => []).add(tutorial);
    }

    return Container(
      width: 400,
      constraints: const BoxConstraints(maxHeight: 500),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A42)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF3A3A42)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.school, color: Color(0xFF4A9EFF), size: 20),
                const SizedBox(width: 12),
                const Text(
                  'Interactive Tutorials',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: Colors.white54,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Tutorial list
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final category in TutorialCategory.values)
                    if (grouped.containsKey(category)) ...[
                      _buildCategoryHeader(category),
                      const SizedBox(height: 8),
                      ...grouped[category]!.map((t) => _buildTutorialItem(context, t)),
                      const SizedBox(height: 16),
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryHeader(TutorialCategory category) {
    return Row(
      children: [
        Icon(category.icon, color: Colors.white54, size: 16),
        const SizedBox(width: 8),
        Text(
          category.displayName,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTutorialItem(BuildContext context, Tutorial tutorial) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onTutorialSelected(tutorial);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A32),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tutorial.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tutorial.description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tutorial.difficulty.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tutorial.difficulty.displayName,
                    style: TextStyle(
                      color: tutorial.difficulty.color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${tutorial.estimatedMinutes} min',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
