// FluxForge Slot Lab - Fullscreen Slot Audio Sandbox
//
// Premium "casino-grade" UI for slot game audio design.
// Inspired by Wwise + FMOD but 100% focused on slot games.

import 'package:flutter/material.dart';

/// Fullscreen Slot Lab interface
class SlotLabScreen extends StatefulWidget {
  final VoidCallback onClose;

  const SlotLabScreen({
    super.key,
    required this.onClose,
  });

  @override
  State<SlotLabScreen> createState() => _SlotLabScreenState();
}

class _SlotLabScreenState extends State<SlotLabScreen> {
  // Game spec state
  int _reelCount = 5;
  int _rowCount = 3;
  String _volatility = 'Medium';
  double _balance = 10000.0;
  double _bet = 1.0;
  double _lastWin = 0.0;
  bool _isSpinning = false;

  // Simulated reel symbols
  final List<List<String>> _reelSymbols = [
    ['7', 'BAR', 'BELL', 'CHERRY', 'WILD'],
    ['BAR', '7', 'BONUS', 'BELL', 'CHERRY'],
    ['CHERRY', 'WILD', '7', 'BAR', 'BELL'],
    ['BELL', 'CHERRY', 'BAR', 'BONUS', '7'],
    ['WILD', 'BELL', 'CHERRY', '7', 'BAR'],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0A0A0C),
                  Color(0xFF121218),
                  Color(0xFF0A0A0C),
                ],
              ),
            ),
          ),

          // Main content
          Column(
            children: [
              // Header with slot machine style
              _buildHeader(),

              // Main area - 3 columns
              Expanded(
                child: Row(
                  children: [
                    // Left: Game Spec & Paytable
                    _buildLeftPanel(),

                    // Center: Mock Slot View
                    Expanded(
                      flex: 3,
                      child: _buildCenterPanel(),
                    ),

                    // Right: Event Trigger Matrix & Mixer
                    _buildRightPanel(),
                  ],
                ),
              ),

              // Bottom: Stage Timeline
              _buildBottomPanel(),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HEADER - Slot Machine Style
  // ===========================================================================

  Widget _buildHeader() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A22), Color(0xFF242430), Color(0xFF1A1A22)],
        ),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFFFD700).withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFAA00).withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 20),

          // Close button
          _buildGlassButton(
            icon: Icons.arrow_back,
            onTap: widget.onClose,
            tooltip: 'Back to DAW',
          ),

          const SizedBox(width: 20),

          // Logo and title
          const Icon(Icons.casino, color: Color(0xFFFFD700), size: 32),
          const SizedBox(width: 12),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FLUXFORGE SLOT LAB',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              Text(
                'Synthetic Slot Engine v1.0',
                style: TextStyle(
                  color: Color(0xFFFFAA00),
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Reel display preview (decorative)
          _buildReelPreview(),

          const Spacer(),

          // Status indicators
          _buildStatusIndicators(),

          const SizedBox(width: 20),
        ],
      ),
    );
  }

  Widget _buildReelPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) => _buildMiniReel(i)),
      ),
    );
  }

  Widget _buildMiniReel(int index) {
    final symbols = ['7', 'BAR', '🔔', '🍒', '⭐'];
    return Container(
      width: 36,
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            const Color(0xFF1A1A22),
            Colors.black.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.2),
        ),
      ),
      child: Center(
        child: Text(
          symbols[index],
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFFD700),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicators() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStatusChip('BALANCE', '\$${_balance.toStringAsFixed(2)}', const Color(0xFF40FF90)),
        const SizedBox(width: 12),
        _buildStatusChip('BET', '\$${_bet.toStringAsFixed(2)}', const Color(0xFF4A9EFF)),
        const SizedBox(width: 12),
        _buildStatusChip('LAST WIN', '\$${_lastWin.toStringAsFixed(2)}', const Color(0xFFFFD700)),
      ],
    );
  }

  Widget _buildStatusChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // LEFT PANEL - Game Spec & Paytable
  // ===========================================================================

  Widget _buildLeftPanel() {
    return Container(
      width: 280,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121216).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          _buildPanelHeader('GAME SPEC', Icons.settings),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSpecRow('Grid', '$_reelCount x $_rowCount'),
                  _buildSpecRow('Pay Model', 'Ways (243)'),
                  _buildSpecRow('Volatility', _volatility),
                  _buildSpecRow('RTP Target', '96.5%'),

                  const SizedBox(height: 16),
                  _buildSectionTitle('PAYTABLE'),

                  _buildPaytableRow('7', '500x', true, true, false),
                  _buildPaytableRow('BAR', '200x', true, true, false),
                  _buildPaytableRow('BELL', '100x', true, false, true),
                  _buildPaytableRow('CHERRY', '50x', true, false, false),
                  _buildPaytableRow('WILD', 'Sub', false, true, true),
                  _buildPaytableRow('BONUS', 'FS', false, false, true),

                  const SizedBox(height: 16),
                  _buildSectionTitle('FEATURE RULES'),

                  _buildFeatureRule('3+ Scatters → 10-20 FS'),
                  _buildFeatureRule('Big Win Tier 1: 50x'),
                  _buildFeatureRule('Big Win Tier 2: 200x'),
                  _buildFeatureRule('Big Win Tier 3: 900x'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaytableRow(String symbol, String payout, bool sfx, bool music, bool duck) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              symbol,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              payout,
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 11,
              ),
            ),
          ),
          _buildLedIndicator(sfx, const Color(0xFF40FF90)),
          const SizedBox(width: 4),
          _buildLedIndicator(music, const Color(0xFF4A9EFF)),
          const SizedBox(width: 4),
          _buildLedIndicator(duck, const Color(0xFFFF9040)),
        ],
      ),
    );
  }

  Widget _buildLedIndicator(bool active, Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : color.withValues(alpha: 0.2),
        boxShadow: active
            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)]
            : null,
      ),
    );
  }

  Widget _buildFeatureRule(String rule) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.chevron_right, size: 14, color: Color(0xFFFFAA00)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              rule,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CENTER PANEL - Mock Slot View
  // ===========================================================================

  Widget _buildCenterPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          // Waveform / Audio preview area
          Expanded(
            flex: 2,
            child: _buildWaveformArea(),
          ),

          const SizedBox(height: 12),

          // Mock slot reels
          Expanded(
            flex: 3,
            child: _buildMockSlot(),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          _buildPanelHeader('AUDIO LAYERS', Icons.graphic_eq),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildAudioLayer('Rollup Loop', const Color(0xFF9B59B6), 0.7),
                  _buildAudioLayer('Big Win Stinger', const Color(0xFFFF9040), 0.9),
                  _buildAudioLayer('Crowd Cheers', const Color(0xFFE74C3C), 0.5),
                  _buildAudioLayer('Low Brass Hits', const Color(0xFFF1C40F), 0.6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioLayer(String name, Color color, double level) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
              name,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: level,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.6)],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockSlot() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A22), Color(0xFF0D0D10), Color(0xFF1A1A22)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFAA00).withValues(alpha: 0.1),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _isSpinning ? 'SPINNING...' : 'GOOD LUCK!',
              style: TextStyle(
                color: _isSpinning ? const Color(0xFFFFAA00) : const Color(0xFF40FF90),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),

          // Reels
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: List.generate(
                  _reelCount,
                  (i) => Expanded(child: _buildReel(i)),
                ),
              ),
            ),
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSlotButton('SPIN', const Color(0xFF40FF90), _handleSpin),
                const SizedBox(width: 16),
                _buildSlotButton('TURBO', const Color(0xFFFFAA00), () {}),
                const SizedBox(width: 16),
                _buildSlotButton('AUTO', const Color(0xFF4A9EFF), () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReel(int reelIndex) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          _rowCount,
          (row) => _buildSymbol(_reelSymbols[reelIndex][row]),
        ),
      ),
    );
  }

  Widget _buildSymbol(String symbol) {
    Color symbolColor;
    switch (symbol) {
      case '7':
        symbolColor = const Color(0xFFFF4040);
        break;
      case 'WILD':
        symbolColor = const Color(0xFFFFD700);
        break;
      case 'BONUS':
        symbolColor = const Color(0xFF40FF90);
        break;
      default:
        symbolColor = Colors.white;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      child: Text(
        symbol,
        style: TextStyle(
          color: symbolColor,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSlotButton(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, color.withValues(alpha: 0.7)],
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  void _handleSpin() {
    if (_isSpinning) return;

    setState(() {
      _isSpinning = true;
      _balance -= _bet;
    });

    // Simulate spin
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isSpinning = false;
          // Random win for demo
          if (DateTime.now().millisecond % 3 == 0) {
            _lastWin = _bet * (10 + DateTime.now().millisecond % 50);
            _balance += _lastWin;
          } else {
            _lastWin = 0;
          }
        });
      }
    });
  }

  // ===========================================================================
  // RIGHT PANEL - Event Trigger Matrix & Mixer
  // ===========================================================================

  Widget _buildRightPanel() {
    return Container(
      width: 320,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121216).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          // Volatility Dial
          _buildVolatilitySection(),

          const Divider(color: Color(0xFF2A2A35), height: 1),

          // Scenario Controls
          _buildScenarioControls(),

          const Divider(color: Color(0xFF2A2A35), height: 1),

          // Event Trigger Matrix
          Expanded(child: _buildEventTriggerMatrix()),
        ],
      ),
    );
  }

  Widget _buildVolatilitySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text(
            'VOLATILITY',
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildVolatilityOption('Low', const Color(0xFF40FF90)),
              _buildVolatilityOption('Med', const Color(0xFFF1C40F)),
              _buildVolatilityOption('High', const Color(0xFFFF9040)),
              _buildVolatilityOption('Insane', const Color(0xFFFF4040)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVolatilityOption(String label, Color color) {
    final isSelected = _volatility.toLowerCase().startsWith(label.toLowerCase());
    return GestureDetector(
      onTap: () => setState(() => _volatility = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : color.withValues(alpha: 0.6),
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildScenarioControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SCENARIO CONTROLS',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildScenarioButton('Force Win'),
              _buildScenarioButton('Big Win'),
              _buildScenarioButton('Free Spins'),
              _buildScenarioButton('Near Miss'),
              _buildScenarioButton('Batch 50'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScenarioButton(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A35),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A45)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFCCCCCC),
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEventTriggerMatrix() {
    return Column(
      children: [
        _buildPanelHeader('EVENT TRIGGER MATRIX', Icons.grid_on),
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF1A1A22),
          child: const Row(
            children: [
              Expanded(flex: 3, child: Text('STAGE', style: TextStyle(color: Color(0xFF888888), fontSize: 10))),
              SizedBox(width: 30, child: Text('SFX', style: TextStyle(color: Color(0xFF40FF90), fontSize: 10), textAlign: TextAlign.center)),
              SizedBox(width: 30, child: Text('MUS', style: TextStyle(color: Color(0xFF4A9EFF), fontSize: 10), textAlign: TextAlign.center)),
              SizedBox(width: 30, child: Text('DUK', style: TextStyle(color: Color(0xFFFF9040), fontSize: 10), textAlign: TextAlign.center)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildMatrixRow('SPIN START', true, true, false),
              _buildMatrixRow('REEL STOP 1', true, false, false),
              _buildMatrixRow('REEL STOP 2', true, false, false),
              _buildMatrixRow('REEL STOP 3', true, false, false),
              _buildMatrixRow('REEL STOP 4', true, false, false),
              _buildMatrixRow('REEL STOP 5', true, true, false),
              _buildMatrixRow('WIN PRESENT', true, true, true),
              _buildMatrixRow('ROLLUP START', true, true, true),
              _buildMatrixRow('BIG WIN TIER', true, true, true),
              _buildMatrixRow('FEATURE ENTER', true, true, true),
              _buildMatrixRow('FEATURE EXIT', true, true, false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMatrixRow(String stage, bool sfx, bool music, bool duck) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              stage,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          SizedBox(width: 30, child: Center(child: _buildLedIndicator(sfx, const Color(0xFF40FF90)))),
          SizedBox(width: 30, child: Center(child: _buildLedIndicator(music, const Color(0xFF4A9EFF)))),
          SizedBox(width: 30, child: Center(child: _buildLedIndicator(duck, const Color(0xFFFF9040)))),
        ],
      ),
    );
  }

  // ===========================================================================
  // BOTTOM PANEL - Stage Timeline
  // ===========================================================================

  Widget _buildBottomPanel() {
    return Container(
      height: 100,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121216).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          // Stage segments
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  _buildStageSegment('SPIN\nSTART', const Color(0xFF4A9EFF), true),
                  _buildStageSegment('REEL\nSTOP', const Color(0xFF9B59B6), false),
                  _buildStageSegment('ANTIC', const Color(0xFFE74C3C), false),
                  _buildStageSegment('WIN\nPRESENT', const Color(0xFFF1C40F), false),
                  _buildStageSegment('ROLLUP', const Color(0xFF40FF90), false),
                  _buildStageSegment('BIG\nWIN', const Color(0xFFFF9040), false),
                  _buildStageSegment('FEATURE', const Color(0xFFE91E63), false),
                  _buildStageSegment('SPIN\nEND', const Color(0xFF4A9EFF), false),
                ],
              ),
            ),
          ),

          // Transport controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF2A2A35))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTransportButton(Icons.skip_previous),
                _buildTransportButton(Icons.play_arrow),
                _buildTransportButton(Icons.stop),
                _buildTransportButton(Icons.repeat),
                _buildTransportButton(Icons.skip_next),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageSegment(String label, Color color, bool isActive) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.3) : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? color : color.withValues(alpha: 0.3),
            width: isActive ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? color : color.withValues(alpha: 0.6),
              fontSize: 9,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransportButton(IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Icon(icon, color: const Color(0xFF888888), size: 20),
    );
  }

  // ===========================================================================
  // COMMON WIDGETS
  // ===========================================================================

  Widget _buildPanelHeader(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A22),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFFFFD700)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF888888),
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildGlassButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }
}
