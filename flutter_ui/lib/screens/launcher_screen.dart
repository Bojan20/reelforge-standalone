/// FluxForge Studio Launcher Screen
///
/// Split-screen launcher allowing users to choose between:
/// - DAW Mode (traditional digital audio workstation)
/// - Middleware Mode (game audio authoring, Wwise/FMOD style)

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Application mode selected by user
enum AppMode {
  daw,
  middleware,
}

class LauncherScreen extends StatefulWidget {
  final void Function(AppMode mode) onModeSelected;
  final bool isReady;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const LauncherScreen({
    super.key,
    required this.onModeSelected,
    this.isReady = true,
    this.errorMessage,
    this.onRetry,
  });

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen>
    with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _logoController;
  late AnimationController _panelsController;
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _exitController;
  late AnimationController _hoverController;

  // Animations
  late Animation<double> _logoOpacity;
  late Animation<double> _logoScale;
  late Animation<double> _panelsOpacity;
  late Animation<Offset> _leftPanelSlide;
  late Animation<Offset> _rightPanelSlide;
  late Animation<double> _dividerHeight;

  // Exit animations
  late Animation<double> _exitFade;
  late Animation<double> _exitScale;
  late Animation<double> _selectedPanelScale;
  late Animation<double> _selectedPanelGlow;

  // Hover transition value (-1 = DAW, 0 = none, 1 = Middleware)
  double _hoverValue = 0.0;
  double _targetHoverValue = 0.0;

  // Hover state
  AppMode? _hoveredMode;
  AppMode? _selectedMode;
  bool _animationsComplete = false;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startAnimationSequence();
  }

  void _initAnimations() {
    // Logo animation
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: Curves.elasticOut,
      ),
    );

    // Panels animation
    _panelsController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _panelsOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _panelsController,
        curve: Curves.easeOut,
      ),
    );

    _leftPanelSlide = Tween<Offset>(
      begin: const Offset(-0.3, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _panelsController,
        curve: Curves.easeOutCubic,
      ),
    );

    _rightPanelSlide = Tween<Offset>(
      begin: const Offset(0.3, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _panelsController,
        curve: Curves.easeOutCubic,
      ),
    );

    _dividerHeight = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _panelsController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    // Continuous pulse for accents
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    // Wave animation for visualizations
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();

    // Exit animation (smooth transition out)
    _exitController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _exitController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeInCubic),
      ),
    );

    _exitScale = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _exitController,
        curve: Curves.easeInCubic,
      ),
    );

    _selectedPanelScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _exitController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _selectedPanelGlow = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _exitController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    // Hover transition controller for smooth panel transitions
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    )..addListener(() {
      setState(() {
        // Smoothly interpolate hover value
        _hoverValue = _hoverValue + (_targetHoverValue - _hoverValue) * 0.15;
      });
    });
    _hoverController.repeat();
  }

  void _startAnimationSequence() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _logoController.forward();

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _panelsController.forward();

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _animationsComplete = true;
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _panelsController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    _exitController.dispose();
    _hoverController.dispose();
    super.dispose();
  }

  void _onModeHover(AppMode? mode) {
    setState(() {
      _hoveredMode = mode;
      // Set target for smooth interpolation
      if (mode == AppMode.daw) {
        _targetHoverValue = -1.0;
      } else if (mode == AppMode.middleware) {
        _targetHoverValue = 1.0;
      } else {
        _targetHoverValue = 0.0;
      }
    });
  }

  void _onModeSelected(AppMode mode) {
    if (_isExiting || !widget.isReady) return;

    setState(() {
      _isExiting = true;
      _selectedMode = mode;
    });

    // Start exit animation
    _exitController.forward().then((_) {
      widget.onModeSelected(mode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08080A),
      body: AnimatedBuilder(
        animation: _exitController,
        builder: (context, child) {
          return Opacity(
            opacity: _exitFade.value,
            child: Transform.scale(
              scale: _exitScale.value,
              child: child,
            ),
          );
        },
        child: Stack(
          children: [
            // Background
            _buildBackground(),

            // Main content
            Column(
              children: [
                // Header with logo
                _buildHeader(),

                // Split panels
                Expanded(
                  child: AnimatedBuilder(
                    animation: _panelsController,
                    builder: (context, _) {
                      return Opacity(
                        opacity: _panelsOpacity.value,
                        child: Row(
                          children: [
                            // LEFT: DAW Mode
                            Expanded(
                              child: SlideTransition(
                                position: _leftPanelSlide,
                                child: _buildModePanel(
                                  mode: AppMode.daw,
                                  title: 'DAW',
                                  subtitle: 'Digital Audio Workstation',
                                  description: 'Professional music production,\nmixing, mastering & sound design',
                                  icon: Icons.music_note_rounded,
                                  accentColor: const Color(0xFF4A9EFF),
                                  secondaryColor: const Color(0xFF40C8FF),
                                  features: [
                                    'Multi-track recording & editing',
                                    '64-band parametric EQ',
                                    'Advanced dynamics processing',
                                    'MIDI sequencing & piano roll',
                                    'Plugin hosting (VST3/AU/CLAP)',
                                    'Professional metering & analysis',
                                  ],
                                ),
                              ),
                            ),

                            // Center divider
                            _buildDivider(),

                            // RIGHT: Middleware Mode
                            Expanded(
                              child: SlideTransition(
                                position: _rightPanelSlide,
                                child: _buildModePanel(
                                  mode: AppMode.middleware,
                                  title: 'MIDDLEWARE',
                                  subtitle: 'Game Audio Authoring',
                                  description: 'Interactive audio for games,\nWwise/FMOD-style workflow',
                                  icon: Icons.gamepad_rounded,
                                  accentColor: const Color(0xFFFF9040),
                                  secondaryColor: const Color(0xFFFFD700),
                                  features: [
                                    'Event-based audio system',
                                    'RTPC & state management',
                                    'Ducking & sidechain matrix',
                                    'Random & sequence containers',
                                    'Slot game audio profiles',
                                    'Live engine integration',
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Footer
                _buildFooter(),
              ],
            ),

            // Selection flash overlay
            if (_isExiting && _selectedMode != null)
              _buildSelectionFlash(),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionFlash() {
    final isDAW = _selectedMode == AppMode.daw;
    final color = isDAW ? const Color(0xFF4A9EFF) : const Color(0xFFFF9040);

    return AnimatedBuilder(
      animation: _exitController,
      builder: (context, _) {
        return Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: isDAW ? const Alignment(-0.5, 0) : const Alignment(0.5, 0),
                  radius: 1.5,
                  colors: [
                    color.withValues(alpha: _selectedPanelGlow.value * 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        // Base gradient
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.2,
              colors: [
                Color(0xFF101014),
                Color(0xFF08080A),
              ],
            ),
          ),
        ),

        // Left accent glow (DAW - blue)
        Positioned(
          left: -100,
          top: 100,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final intensity = 0.1 + 0.05 * _pulseController.value;
              return Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF4A9EFF).withValues(alpha: intensity),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Right accent glow (Middleware - orange)
        Positioned(
          right: -100,
          bottom: 100,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final intensity = 0.1 + 0.05 * (1 - _pulseController.value);
              return Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFF9040).withValues(alpha: intensity),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Grid overlay
        Positioned.fill(
          child: CustomPaint(
            painter: _GridPainter(opacity: 0.03),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return AnimatedBuilder(
      animation: _logoController,
      builder: (context, child) {
        return Opacity(
          opacity: _logoOpacity.value,
          child: Transform.scale(
            scale: _logoScale.value,
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            // Logo
            _buildLogo(),
            const SizedBox(height: 20),
            // Title
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF4A9EFF), Color(0xFFFF9040)],
              ).createShader(bounds),
              child: const Text(
                'FluxForge Studio',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 6,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'SELECT YOUR WORKSPACE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 4,
                color: Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final glow = 0.3 + 0.2 * _pulseController.value;
        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4A9EFF).withValues(alpha: glow * 0.5),
                blurRadius: 30,
                spreadRadius: 5,
              ),
              BoxShadow(
                color: const Color(0xFFFF9040).withValues(alpha: glow * 0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.asset(
          'assets/branding/fluxforge_icon_256.png',
          width: 120,
          height: 120,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return AnimatedBuilder(
      animation: _panelsController,
      builder: (context, _) {
        return Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 40),
          child: FractionallySizedBox(
            heightFactor: _dividerHeight.value,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.white.withValues(alpha: 0.2),
                    Colors.white.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.3, 0.7, 1.0],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildModePanel({
    required AppMode mode,
    required String title,
    required String subtitle,
    required String description,
    required IconData icon,
    required Color accentColor,
    required Color secondaryColor,
    required List<String> features,
  }) {
    final isSelected = _selectedMode == mode;
    final isOtherSelected = _selectedMode != null && _selectedMode != mode;

    // Smooth hover intensity: 0.0 to 1.0
    // For DAW: intensity increases as _hoverValue goes to -1
    // For Middleware: intensity increases as _hoverValue goes to +1
    final double hoverIntensity;
    final double otherFade;
    if (mode == AppMode.daw) {
      hoverIntensity = (-_hoverValue).clamp(0.0, 1.0);
      otherFade = _hoverValue.clamp(0.0, 1.0);
    } else {
      hoverIntensity = _hoverValue.clamp(0.0, 1.0);
      otherFade = (-_hoverValue).clamp(0.0, 1.0);
    }

    final isActive = isSelected || hoverIntensity > 0.1;

    return AnimatedBuilder(
      animation: _exitController,
      builder: (context, child) {
        // Scale up selected panel, fade out other panel
        double scale = 1.0;
        double opacity = 1.0;

        if (_isExiting) {
          if (isSelected) {
            scale = _selectedPanelScale.value;
          } else if (isOtherSelected) {
            opacity = 1.0 - (_exitController.value * 2).clamp(0.0, 1.0);
          }
        }

        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: child,
          ),
        );
      },
      child: Opacity(
        opacity: widget.isReady ? 1.0 : 0.5,
        child: MouseRegion(
          onEnter: (_) => _isExiting ? null : _onModeHover(mode),
          onExit: (_) => _isExiting ? null : _onModeHover(null),
          child: GestureDetector(
            onTap: () => _onModeSelected(mode),
          child: Container(
            margin: EdgeInsets.all(24 - (8 * hoverIntensity) - (isSelected ? 8 : 0)),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Color.lerp(
                Colors.white.withValues(alpha: 0.02),
                accentColor.withValues(alpha: 0.08),
                isSelected ? 1.0 : hoverIntensity,
              ),
              border: Border.all(
                color: Color.lerp(
                  Colors.white.withValues(alpha: 0.05),
                  accentColor.withValues(alpha: 0.4),
                  isSelected ? 1.0 : hoverIntensity,
                )!,
                width: 1 + (isActive ? 1 : 0),
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: isSelected ? 0.4 : 0.2 * hoverIntensity),
                        blurRadius: isSelected ? 60 : 40 * hoverIntensity,
                        spreadRadius: isSelected ? 10 : 0,
                      ),
                    ]
                  : null,
            ),
            child: Opacity(
              opacity: _isExiting ? 1.0 : (1.0 - otherFade * 0.5),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon with visualization
                  _buildModeIcon(mode, icon, accentColor, secondaryColor, isActive),

                  const SizedBox(height: 32),

                  // Title
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 8,
                      color: Color.lerp(Colors.white, accentColor, isSelected ? 1.0 : hoverIntensity),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 3,
                      color: Color.lerp(
                        const Color(0xFF888888),
                        accentColor.withValues(alpha: 0.8),
                        isSelected ? 1.0 : hoverIntensity,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Description
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Color(0xFF999999),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Features list
                  ...features.map((feature) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: Color.lerp(
                            const Color(0xFF555555),
                            accentColor,
                            isSelected ? 1.0 : hoverIntensity,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          feature,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color.lerp(
                              const Color(0xFF777777),
                              Colors.white.withValues(alpha: 0.9),
                              isSelected ? 1.0 : hoverIntensity,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),

                  const Spacer(),

                  // Enter button
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: isActive
                          ? LinearGradient(
                              colors: [
                                Color.lerp(Colors.white.withValues(alpha: 0.1), accentColor, hoverIntensity)!,
                                Color.lerp(Colors.white.withValues(alpha: 0.1), secondaryColor, hoverIntensity)!,
                              ],
                            )
                          : null,
                      color: isActive ? null : Colors.white.withValues(alpha: 0.05),
                      border: Border.all(
                        color: Color.lerp(
                          Colors.white.withValues(alpha: 0.1),
                          Colors.transparent,
                          hoverIntensity,
                        )!,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ENTER ${mode == AppMode.daw ? 'DAW' : 'MIDDLEWARE'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                            color: Color.lerp(
                              const Color(0xFF888888),
                              Colors.white,
                              isSelected ? 1.0 : hoverIntensity,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward,
                          size: 16,
                          color: Color.lerp(
                            const Color(0xFF888888),
                            Colors.white,
                            isSelected ? 1.0 : hoverIntensity,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),  // end Opacity
      ),  // end AnimatedBuilder
    );
  }

  Widget _buildModeIcon(
    AppMode mode,
    IconData icon,
    Color accentColor,
    Color secondaryColor,
    bool isHovered,
  ) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated visualization
          if (mode == AppMode.daw)
            _buildWaveformVisualization(accentColor, isHovered)
          else
            _buildNodeVisualization(accentColor, secondaryColor, isHovered),

          // Icon
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0A0A0C),
              border: Border.all(
                color: isHovered
                    ? accentColor.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.1),
                width: 2,
              ),
              boxShadow: isHovered
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.3),
                        blurRadius: 20,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              size: 32,
              color: isHovered ? accentColor : const Color(0xFF666666),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformVisualization(Color color, bool isHovered) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(120, 120),
          painter: _WaveformPainter(
            progress: _waveController.value,
            color: color,
            isActive: isHovered && _animationsComplete,
          ),
        );
      },
    );
  }

  Widget _buildNodeVisualization(Color color, Color secondary, bool isHovered) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(120, 120),
          painter: _NodePainter(
            progress: _waveController.value,
            primaryColor: color,
            secondaryColor: secondary,
            isActive: isHovered && _animationsComplete,
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          // Loading / Error indicator
          if (widget.errorMessage != null) ...[
            Text(
              widget.errorMessage!,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFFF4060),
              ),
            ),
            const SizedBox(height: 8),
            if (widget.onRetry != null)
              GestureDetector(
                onTap: widget.onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFFF4060).withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(fontSize: 11, color: Color(0xFFFF4060)),
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ] else if (!widget.isReady) ...[
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Color(0xFF1A1A20),
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A9EFF)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'v0.1.0',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.3),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '© 2025 VanVinkl Studio',
            style: TextStyle(
              fontSize: 9,
              color: Colors.white.withValues(alpha: 0.2),
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _GridPainter extends CustomPainter {
  final double opacity;

  _GridPainter({this.opacity = 0.05});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 0.5;

    const spacing = 40.0;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isActive;

  _WaveformPainter({
    required this.progress,
    required this.color,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    final paint = Paint()
      ..color = color.withValues(alpha: isActive ? 0.6 : 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Draw circular waveform
    final path = Path();
    const segments = 60;

    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2 * math.pi - math.pi / 2;
      final waveOffset = isActive
          ? math.sin(angle * 8 + progress * 2 * math.pi) * 8
          : math.sin(angle * 8) * 3;
      final r = radius + waveOffset;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isActive != isActive;
  }
}

class _NodePainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isActive;

  _NodePainter({
    required this.progress,
    required this.primaryColor,
    required this.secondaryColor,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 15;

    // Draw connection lines
    final linePaint = Paint()
      ..color = primaryColor.withValues(alpha: isActive ? 0.4 : 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Node positions
    final nodes = <Offset>[];
    const nodeCount = 6;

    for (int i = 0; i < nodeCount; i++) {
      final angle = (i / nodeCount) * 2 * math.pi - math.pi / 2;
      final wobble = isActive ? math.sin(progress * 2 * math.pi + i) * 5 : 0.0;
      final r = radius + wobble;
      nodes.add(Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      ));
    }

    // Draw lines between nodes
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        if ((j - i) % 2 == 1 || j - i == nodes.length - 1) {
          canvas.drawLine(nodes[i], nodes[j], linePaint);
        }
      }
    }

    // Draw nodes
    final nodePaint = Paint()
      ..style = PaintingStyle.fill;

    for (int i = 0; i < nodes.length; i++) {
      final isHighlighted = isActive && ((progress * nodeCount).floor() % nodeCount == i);
      nodePaint.color = isHighlighted ? secondaryColor : primaryColor.withValues(alpha: isActive ? 0.8 : 0.4);
      canvas.drawCircle(nodes[i], isHighlighted ? 6 : 4, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NodePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isActive != isActive;
  }
}
