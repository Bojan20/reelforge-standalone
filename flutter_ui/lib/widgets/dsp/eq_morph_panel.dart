/// EQ Morph Panel
///
/// Morphing EQ that interpolates between two EQ presets.
/// Features:
/// - A/B preset storage
/// - Crossfade slider (0=A, 1=B)
/// - Quick toggle buttons

import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/reelforge_theme.dart';

/// EQ Morph Panel Widget
class EqMorphPanel extends StatefulWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const EqMorphPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<EqMorphPanel> createState() => _EqMorphPanelState();
}

class _EqMorphPanelState extends State<EqMorphPanel>
    with SingleTickerProviderStateMixin {
  final _ffi = NativeFFI.instance;

  double _position = 0.0; // 0.0 = A, 1.0 = B
  bool _isAtA = true;
  bool _initialized = false;

  late AnimationController _animController;
  late Animation<double> _posAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _posAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    _animController.addListener(_onAnimationUpdate);
    _initializeProcessor();
  }

  @override
  void dispose() {
    _animController.dispose();
    _ffi.morphEqDestroy(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    final success = _ffi.morphEqCreate(widget.trackId, sampleRate: widget.sampleRate);
    if (success) {
      setState(() => _initialized = true);
    }
  }

  void _onAnimationUpdate() {
    final newPos = _isAtA ? (1.0 - _posAnimation.value) : _posAnimation.value;
    setState(() => _position = newPos);
    _ffi.morphEqSetPosition(widget.trackId, _position);
  }

  void _goToA() {
    if (_position == 0.0) return;
    _isAtA = true;
    _animController.forward(from: 0.0);
  }

  void _goToB() {
    if (_position == 1.0) return;
    _isAtA = false;
    _animController.forward(from: 0.0);
  }

  void _toggle() {
    if (_position < 0.5) {
      _goToB();
    } else {
      _goToA();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgVoid,
        border: Border.all(color: ReelForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildPresetButtons(),
                  const SizedBox(height: 32),
                  _buildMorphSlider(),
                  const SizedBox(height: 32),
                  _buildToggleButton(),
                  const SizedBox(height: 24),
                  _buildPositionDisplay(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.compare_arrows, color: ReelForgeTheme.accentGreen, size: 20),
          const SizedBox(width: 8),
          Text(
            'EQ MORPH',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (!_initialized)
            Text(
              'Initializing...',
              style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildPresetButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildPresetButton('A', _position < 0.5, ReelForgeTheme.accentCyan, _goToA),
        _buildPresetButton('B', _position > 0.5, ReelForgeTheme.accentOrange, _goToB),
      ],
    );
  }

  Widget _buildPresetButton(
    String label,
    bool isActive,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? color.withValues(alpha: 0.3) : ReelForgeTheme.bgMid,
          border: Border.all(
            color: isActive ? color : ReelForgeTheme.borderMedium,
            width: 3,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? color : ReelForgeTheme.textTertiary,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMorphSlider() {
    return Column(
      children: [
        Text(
          'MORPH POSITION',
          style: TextStyle(
            color: ReelForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              colors: [ReelForgeTheme.accentCyan, ReelForgeTheme.accentOrange],
            ),
          ),
          child: Stack(
            children: [
              // Track background
              Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: ReelForgeTheme.bgVoid,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              // Slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 48,
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: ReelForgeTheme.textPrimary,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 20),
                    overlayColor: ReelForgeTheme.textPrimary.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: _position,
                    onChanged: (v) {
                      setState(() => _position = v);
                      _ffi.morphEqSetPosition(widget.trackId, v);
                      widget.onSettingsChanged?.call();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleButton() {
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ReelForgeTheme.borderMedium),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_horiz,
              color: _position < 0.5 ? ReelForgeTheme.accentCyan : ReelForgeTheme.accentOrange,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              'TOGGLE A↔B',
              style: TextStyle(
                color: _position < 0.5 ? ReelForgeTheme.accentCyan : ReelForgeTheme.accentOrange,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionDisplay() {
    final aPercent = ((1.0 - _position) * 100).round();
    final bPercent = (_position * 100).round();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'A: $aPercent%',
          style: TextStyle(
            color: ReelForgeTheme.accentCyan.withValues(alpha: 0.5 + (1.0 - _position) * 0.5),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 32),
        Text(
          'B: $bPercent%',
          style: TextStyle(
            color: ReelForgeTheme.accentOrange.withValues(alpha: 0.5 + _position * 0.5),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
