// ═══════════════════════════════════════════════════════════════════════════════
// MOCK ENGINE SERVICE — P3.14 Staging Mode
// ═══════════════════════════════════════════════════════════════════════════════
//
// Simulates a game engine for audio testing without a real connection.
// Generates realistic stage event sequences for:
// - Normal spins with various outcomes
// - Free spins feature
// - Bonus games
// - Jackpot hits
// - Cascade/Tumble mechanics
//
// Usage:
//   MockEngineService.instance.start();
//   MockEngineService.instance.triggerSpin();

import 'dart:async';
import 'dart:math';

/// Mock engine operating mode
enum MockEngineMode {
  idle,       // No activity
  manual,     // Manual spin triggering
  autoSpin,   // Automatic spins at interval
  sequence,   // Playing predefined sequence
}

/// Mock game context
enum MockGameContext {
  base,        // Base game
  freeSpins,   // Free spins feature
  bonus,       // Bonus game
  holdWin,     // Hold & Win / Respin
  gamble,      // Gamble feature
}

/// Win tier for outcome generation
enum MockWinTier {
  lose,
  small,
  medium,
  big,
  mega,
  epic,
  jackpotMini,
  jackpotMinor,
  jackpotMajor,
  jackpotGrand,
}

/// Configuration for mock engine behavior
class MockEngineConfig {
  /// Base delay between stage events (ms)
  final int baseDelayMs;

  /// Reel count (affects REEL_STOP count)
  final int reelCount;

  /// Win probability (0.0 - 1.0)
  final double winProbability;

  /// Big win threshold (multiplier of bet)
  final double bigWinThreshold;

  /// Auto-spin interval (ms)
  final int autoSpinIntervalMs;

  /// Enable cascade mechanics
  final bool enableCascade;

  /// Enable anticipation effects
  final bool enableAnticipation;

  /// Free spins probability
  final double freeSpinsTriggerProbability;

  const MockEngineConfig({
    this.baseDelayMs = 100,
    this.reelCount = 5,
    this.winProbability = 0.35,
    this.bigWinThreshold = 20.0,
    this.autoSpinIntervalMs = 3000,
    this.enableCascade = true,
    this.enableAnticipation = true,
    this.freeSpinsTriggerProbability = 0.05,
  });

  /// Studio preset - slower for audio design
  static const studio = MockEngineConfig(
    baseDelayMs: 200,
    autoSpinIntervalMs: 5000,
  );

  /// Turbo preset - fast for stress testing
  static const turbo = MockEngineConfig(
    baseDelayMs: 50,
    autoSpinIntervalMs: 1500,
    winProbability: 0.4,
  );

  /// Demo preset - high win rate for showcase
  static const demo = MockEngineConfig(
    baseDelayMs: 150,
    winProbability: 0.6,
    freeSpinsTriggerProbability: 0.15,
  );
}

/// A single mock stage event
class MockStageEvent {
  final String stage;
  final double timestampMs;
  final Map<String, dynamic> data;

  MockStageEvent({
    required this.stage,
    required this.timestampMs,
    this.data = const {},
  });

  Map<String, dynamic> toJson() => {
    'stage': stage,
    'timestamp_ms': timestampMs,
    ...data,
  };
}

/// Predefined event sequence for testing
class MockEventSequence {
  final String name;
  final String description;
  final List<MockStageEvent> events;

  const MockEventSequence({
    required this.name,
    required this.description,
    required this.events,
  });

  /// Normal spin with small win
  static MockEventSequence normalWin() {
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    return MockEventSequence(
      name: 'Normal Win',
      description: 'Standard spin with small win',
      events: [
        MockStageEvent(stage: 'SPIN_START', timestampMs: now),
        MockStageEvent(stage: 'REEL_SPIN', timestampMs: now + 100),
        MockStageEvent(stage: 'REEL_STOP_0', timestampMs: now + 600),
        MockStageEvent(stage: 'REEL_STOP_1', timestampMs: now + 800),
        MockStageEvent(stage: 'REEL_STOP_2', timestampMs: now + 1000),
        MockStageEvent(stage: 'REEL_STOP_3', timestampMs: now + 1200),
        MockStageEvent(stage: 'REEL_STOP_4', timestampMs: now + 1400),
        MockStageEvent(stage: 'WIN_EVAL', timestampMs: now + 1500),
        MockStageEvent(stage: 'WIN_SMALL', timestampMs: now + 1600, data: {'amount': 5.0}),
        MockStageEvent(stage: 'WIN_LINE_SHOW', timestampMs: now + 1700),
        MockStageEvent(stage: 'ROLLUP_START', timestampMs: now + 1800),
        MockStageEvent(stage: 'ROLLUP_TICK', timestampMs: now + 1900),
        MockStageEvent(stage: 'ROLLUP_TICK', timestampMs: now + 2000),
        MockStageEvent(stage: 'ROLLUP_END', timestampMs: now + 2100),
        MockStageEvent(stage: 'WIN_LINE_HIDE', timestampMs: now + 2300),
        MockStageEvent(stage: 'SPIN_END', timestampMs: now + 2400),
      ],
    );
  }

  /// Big win sequence
  static MockEventSequence bigWin() {
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    return MockEventSequence(
      name: 'Big Win',
      description: 'Spin with big win celebration',
      events: [
        MockStageEvent(stage: 'SPIN_START', timestampMs: now),
        MockStageEvent(stage: 'REEL_SPIN', timestampMs: now + 100),
        MockStageEvent(stage: 'ANTICIPATION_ON', timestampMs: now + 500),
        MockStageEvent(stage: 'REEL_STOP_0', timestampMs: now + 700),
        MockStageEvent(stage: 'REEL_STOP_1', timestampMs: now + 900),
        MockStageEvent(stage: 'REEL_STOP_2', timestampMs: now + 1100),
        MockStageEvent(stage: 'REEL_STOP_3', timestampMs: now + 1300),
        MockStageEvent(stage: 'ANTICIPATION_OFF', timestampMs: now + 1400),
        MockStageEvent(stage: 'REEL_STOP_4', timestampMs: now + 1500),
        MockStageEvent(stage: 'WIN_EVAL', timestampMs: now + 1600),
        MockStageEvent(stage: 'WIN_BIG', timestampMs: now + 1700, data: {'amount': 50.0}),
        MockStageEvent(stage: 'BIGWIN_START', timestampMs: now + 1800),
        MockStageEvent(stage: 'ROLLUP_START', timestampMs: now + 2000),
        for (int i = 0; i < 10; i++)
          MockStageEvent(stage: 'ROLLUP_TICK', timestampMs: now + 2100 + (i * 200)),
        MockStageEvent(stage: 'ROLLUP_END', timestampMs: now + 4100),
        MockStageEvent(stage: 'BIGWIN_END', timestampMs: now + 4500),
        MockStageEvent(stage: 'SPIN_END', timestampMs: now + 4700),
      ],
    );
  }

  /// Free spins trigger
  static MockEventSequence freeSpinsTrigger() {
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    return MockEventSequence(
      name: 'Free Spins Trigger',
      description: 'Scatter lands triggering free spins',
      events: [
        MockStageEvent(stage: 'SPIN_START', timestampMs: now),
        MockStageEvent(stage: 'REEL_SPIN', timestampMs: now + 100),
        MockStageEvent(stage: 'REEL_STOP_0', timestampMs: now + 600),
        MockStageEvent(stage: 'SCATTER_LAND', timestampMs: now + 650, data: {'reel': 0}),
        MockStageEvent(stage: 'REEL_STOP_1', timestampMs: now + 800),
        MockStageEvent(stage: 'REEL_STOP_2', timestampMs: now + 1000),
        MockStageEvent(stage: 'SCATTER_LAND', timestampMs: now + 1050, data: {'reel': 2}),
        MockStageEvent(stage: 'ANTICIPATION_ON', timestampMs: now + 1100),
        MockStageEvent(stage: 'REEL_STOP_3', timestampMs: now + 1500),
        MockStageEvent(stage: 'REEL_STOP_4', timestampMs: now + 1900),
        MockStageEvent(stage: 'SCATTER_LAND', timestampMs: now + 1950, data: {'reel': 4}),
        MockStageEvent(stage: 'ANTICIPATION_OFF', timestampMs: now + 2000),
        MockStageEvent(stage: 'FS_TRIGGER', timestampMs: now + 2200, data: {'spins': 10}),
        MockStageEvent(stage: 'FS_INTRO', timestampMs: now + 2500),
        MockStageEvent(stage: 'CONTEXT_ENTER', timestampMs: now + 4000, data: {'context': 'FREESPINS'}),
        MockStageEvent(stage: 'SPIN_END', timestampMs: now + 4200),
      ],
    );
  }

  /// Cascade/tumble sequence
  static MockEventSequence cascade() {
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    return MockEventSequence(
      name: 'Cascade Win',
      description: 'Tumble mechanics with multiple cascades',
      events: [
        MockStageEvent(stage: 'SPIN_START', timestampMs: now),
        MockStageEvent(stage: 'REEL_SPIN', timestampMs: now + 100),
        MockStageEvent(stage: 'REEL_STOP_0', timestampMs: now + 600),
        MockStageEvent(stage: 'REEL_STOP_1', timestampMs: now + 800),
        MockStageEvent(stage: 'REEL_STOP_2', timestampMs: now + 1000),
        MockStageEvent(stage: 'REEL_STOP_3', timestampMs: now + 1200),
        MockStageEvent(stage: 'REEL_STOP_4', timestampMs: now + 1400),
        MockStageEvent(stage: 'WIN_EVAL', timestampMs: now + 1500),
        MockStageEvent(stage: 'WIN_SMALL', timestampMs: now + 1600),
        // Cascade 1
        MockStageEvent(stage: 'CASCADE_START', timestampMs: now + 1800, data: {'cascade': 1}),
        MockStageEvent(stage: 'CASCADE_SYMBOL_POP', timestampMs: now + 1900),
        MockStageEvent(stage: 'CASCADE_SYMBOL_POP', timestampMs: now + 2000),
        MockStageEvent(stage: 'CASCADE_DROP', timestampMs: now + 2200),
        MockStageEvent(stage: 'CASCADE_LAND', timestampMs: now + 2600),
        MockStageEvent(stage: 'WIN_EVAL', timestampMs: now + 2700),
        MockStageEvent(stage: 'WIN_SMALL', timestampMs: now + 2800),
        // Cascade 2
        MockStageEvent(stage: 'CASCADE_START', timestampMs: now + 3000, data: {'cascade': 2}),
        MockStageEvent(stage: 'MULT_INCREASE', timestampMs: now + 3100, data: {'multiplier': 2}),
        MockStageEvent(stage: 'CASCADE_SYMBOL_POP', timestampMs: now + 3200),
        MockStageEvent(stage: 'CASCADE_DROP', timestampMs: now + 3400),
        MockStageEvent(stage: 'CASCADE_LAND', timestampMs: now + 3800),
        MockStageEvent(stage: 'WIN_EVAL', timestampMs: now + 3900),
        MockStageEvent(stage: 'WIN_MEDIUM', timestampMs: now + 4000),
        MockStageEvent(stage: 'CASCADE_END', timestampMs: now + 4200),
        MockStageEvent(stage: 'SPIN_END', timestampMs: now + 4400),
      ],
    );
  }

  /// Jackpot hit
  static MockEventSequence jackpot() {
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    return MockEventSequence(
      name: 'Jackpot Grand',
      description: 'Grand jackpot win',
      events: [
        MockStageEvent(stage: 'SPIN_START', timestampMs: now),
        MockStageEvent(stage: 'REEL_SPIN', timestampMs: now + 100),
        MockStageEvent(stage: 'ANTICIPATION_ON', timestampMs: now + 400),
        MockStageEvent(stage: 'REEL_STOP_0', timestampMs: now + 800),
        MockStageEvent(stage: 'REEL_STOP_1', timestampMs: now + 1200),
        MockStageEvent(stage: 'REEL_STOP_2', timestampMs: now + 1600),
        MockStageEvent(stage: 'REEL_STOP_3', timestampMs: now + 2000),
        MockStageEvent(stage: 'REEL_STOP_4', timestampMs: now + 2400),
        MockStageEvent(stage: 'ANTICIPATION_OFF', timestampMs: now + 2500),
        MockStageEvent(stage: 'JACKPOT_TRIGGER', timestampMs: now + 2700),
        MockStageEvent(stage: 'JACKPOT_GRAND', timestampMs: now + 3000, data: {'amount': 10000.0}),
        MockStageEvent(stage: 'JACKPOT_CELEBRATION', timestampMs: now + 3500),
        for (int i = 0; i < 20; i++)
          MockStageEvent(stage: 'ROLLUP_TICK', timestampMs: now + 4000 + (i * 150)),
        MockStageEvent(stage: 'ROLLUP_END', timestampMs: now + 7000),
        MockStageEvent(stage: 'JACKPOT_COLLECT', timestampMs: now + 7500),
        MockStageEvent(stage: 'SPIN_END', timestampMs: now + 8000),
      ],
    );
  }
}

/// Mock Engine Service singleton
class MockEngineService {
  MockEngineService._();
  static final instance = MockEngineService._();

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  MockEngineConfig _config = MockEngineConfig.studio;
  MockEngineMode _mode = MockEngineMode.idle;
  MockGameContext _context = MockGameContext.base;
  bool _isRunning = false;
  int _spinCount = 0;
  int _freeSpinsRemaining = 0;

  Timer? _autoSpinTimer;
  Timer? _sequenceTimer;
  final _random = Random();

  /// Event stream
  final StreamController<MockStageEvent> _eventController =
      StreamController<MockStageEvent>.broadcast();

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  MockEngineConfig get config => _config;
  set config(MockEngineConfig value) => _config = value;
  MockEngineMode get mode => _mode;
  MockGameContext get context => _context;
  MockGameContext get currentContext => _context;  // Alias for compatibility
  bool get isRunning => _isRunning;
  int get spinCount => _spinCount;
  int get freeSpinsRemaining => _freeSpinsRemaining;
  Stream<MockStageEvent> get events => _eventController.stream;

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  void setConfig(MockEngineConfig config) {
    _config = config;
  }

  void setMode(MockEngineMode mode) {
    if (_mode == mode) return;
    _mode = mode;

    if (mode == MockEngineMode.autoSpin && _isRunning) {
      _startAutoSpin();
    } else {
      _stopAutoSpin();
    }
  }

  void setContext(MockGameContext context) {
    _context = context;
    // Reset free spins when manually changing context
    if (context == MockGameContext.freeSpins) {
      _freeSpinsRemaining = 10;
    } else {
      _freeSpinsRemaining = 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _spinCount = 0;

    if (_mode == MockEngineMode.autoSpin) {
      _startAutoSpin();
    }
  }

  void stop() {
    _isRunning = false;
    _stopAutoSpin();
    _sequenceTimer?.cancel();
  }

  void dispose() {
    stop();
    _eventController.close();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPIN GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Trigger a single spin with random outcome
  Future<void> triggerSpin() async {
    if (!_isRunning) return;

    _spinCount++;
    final outcome = _generateOutcome();
    final events = _generateSpinEvents(outcome);

    await _playEvents(events);
  }

  /// Trigger a spin with specific outcome
  Future<void> triggerSpinWithOutcome(MockWinTier outcome) async {
    if (!_isRunning) return;

    _spinCount++;
    final events = _generateSpinEvents(outcome);
    await _playEvents(events);
  }

  /// Play a predefined sequence
  Future<void> playSequence(MockEventSequence sequence) async {
    if (!_isRunning) return;

    for (final event in sequence.events) {
      _emit(event);
      await Future.delayed(Duration(milliseconds: _config.baseDelayMs));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO-SPIN
  // ═══════════════════════════════════════════════════════════════════════════

  void _startAutoSpin() {
    _stopAutoSpin();
    _autoSpinTimer = Timer.periodic(
      Duration(milliseconds: _config.autoSpinIntervalMs),
      (_) => triggerSpin(),
    );
  }

  void _stopAutoSpin() {
    _autoSpinTimer?.cancel();
    _autoSpinTimer = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OUTCOME GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  MockWinTier _generateOutcome() {
    final roll = _random.nextDouble();

    // In free spins, higher win chances
    final winChance = _context == MockGameContext.freeSpins
        ? _config.winProbability * 1.5
        : _config.winProbability;

    if (roll > winChance) {
      return MockWinTier.lose;
    }

    // Weighted win tiers
    final tierRoll = _random.nextDouble();
    if (tierRoll < 0.5) return MockWinTier.small;
    if (tierRoll < 0.75) return MockWinTier.medium;
    if (tierRoll < 0.90) return MockWinTier.big;
    if (tierRoll < 0.96) return MockWinTier.mega;
    if (tierRoll < 0.99) return MockWinTier.epic;

    // Rare jackpots
    final jackpotRoll = _random.nextDouble();
    if (jackpotRoll < 0.5) return MockWinTier.jackpotMini;
    if (jackpotRoll < 0.8) return MockWinTier.jackpotMinor;
    if (jackpotRoll < 0.95) return MockWinTier.jackpotMajor;
    return MockWinTier.jackpotGrand;
  }

  List<MockStageEvent> _generateSpinEvents(MockWinTier outcome) {
    final events = <MockStageEvent>[];
    var time = 0.0;

    // SPIN_START
    events.add(MockStageEvent(stage: 'SPIN_START', timestampMs: time));
    time += _config.baseDelayMs;

    // REEL_SPIN
    events.add(MockStageEvent(stage: 'REEL_SPIN', timestampMs: time));
    time += _config.baseDelayMs * 3;

    // Check for anticipation
    final hasAnticipation = _config.enableAnticipation &&
        (outcome.index >= MockWinTier.big.index || _random.nextDouble() < 0.1);

    if (hasAnticipation) {
      events.add(MockStageEvent(stage: 'ANTICIPATION_ON', timestampMs: time));
      time += _config.baseDelayMs;
    }

    // REEL_STOP per reel
    for (int i = 0; i < _config.reelCount; i++) {
      time += _config.baseDelayMs * 2;

      // Scatter lands?
      if (_random.nextDouble() < 0.15) {
        events.add(MockStageEvent(
          stage: 'SCATTER_LAND',
          timestampMs: time - 20,
          data: {'reel': i},
        ));
      }

      events.add(MockStageEvent(
        stage: 'REEL_STOP_$i',
        timestampMs: time,
        data: {'reel': i},
      ));
    }

    if (hasAnticipation) {
      time += _config.baseDelayMs;
      events.add(MockStageEvent(stage: 'ANTICIPATION_OFF', timestampMs: time));
    }

    // WIN_EVAL
    time += _config.baseDelayMs;
    events.add(MockStageEvent(stage: 'WIN_EVAL', timestampMs: time));

    // Outcome-specific events
    time += _config.baseDelayMs;
    events.addAll(_generateOutcomeEvents(outcome, time));

    // Update time after outcome events
    time += _getOutcomeDuration(outcome);

    // Check for free spins trigger
    if (_random.nextDouble() < _config.freeSpinsTriggerProbability &&
        _context == MockGameContext.base) {
      time += _config.baseDelayMs;
      events.add(MockStageEvent(
        stage: 'FS_TRIGGER',
        timestampMs: time,
        data: {'spins': 10},
      ));
      _freeSpinsRemaining = 10;
      _context = MockGameContext.freeSpins;
    }

    // Handle free spins decrement
    if (_context == MockGameContext.freeSpins) {
      _freeSpinsRemaining--;
      if (_freeSpinsRemaining <= 0) {
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'FS_END', timestampMs: time));
        _context = MockGameContext.base;
      }
    }

    // SPIN_END
    time += _config.baseDelayMs;
    events.add(MockStageEvent(stage: 'SPIN_END', timestampMs: time));

    return events;
  }

  List<MockStageEvent> _generateOutcomeEvents(MockWinTier outcome, double startTime) {
    final events = <MockStageEvent>[];
    var time = startTime;

    switch (outcome) {
      case MockWinTier.lose:
        // No win events
        break;

      case MockWinTier.small:
        events.add(MockStageEvent(stage: 'WIN_SMALL', timestampMs: time, data: {'amount': 2.0}));
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'WIN_LINE_SHOW', timestampMs: time));
        time += _config.baseDelayMs * 2;
        events.add(MockStageEvent(stage: 'ROLLUP_START', timestampMs: time));
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'ROLLUP_TICK', timestampMs: time));
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'ROLLUP_END', timestampMs: time));
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'WIN_LINE_HIDE', timestampMs: time));
        break;

      case MockWinTier.medium:
        events.add(MockStageEvent(stage: 'WIN_MEDIUM', timestampMs: time, data: {'amount': 10.0}));
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'WIN_LINE_SHOW', timestampMs: time));
        time += _config.baseDelayMs * 2;
        events.add(MockStageEvent(stage: 'ROLLUP_START', timestampMs: time));
        for (int i = 0; i < 5; i++) {
          time += _config.baseDelayMs;
          events.add(MockStageEvent(stage: 'ROLLUP_TICK', timestampMs: time));
        }
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'ROLLUP_END', timestampMs: time));
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'WIN_LINE_HIDE', timestampMs: time));
        break;

      case MockWinTier.big:
        events.add(MockStageEvent(stage: 'WIN_BIG', timestampMs: time, data: {'amount': 50.0}));
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'BIGWIN_START', timestampMs: time));
        time += _config.baseDelayMs * 2;
        events.add(MockStageEvent(stage: 'ROLLUP_START', timestampMs: time));
        for (int i = 0; i < 10; i++) {
          time += _config.baseDelayMs;
          events.add(MockStageEvent(stage: 'ROLLUP_TICK', timestampMs: time));
        }
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'ROLLUP_END', timestampMs: time));
        time += _config.baseDelayMs * 2;
        events.add(MockStageEvent(stage: 'BIGWIN_END', timestampMs: time));
        break;

      case MockWinTier.mega:
        events.add(MockStageEvent(stage: 'WIN_MEGA', timestampMs: time, data: {'amount': 200.0}));
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'MEGAWIN_START', timestampMs: time));
        time += _config.baseDelayMs * 2;
        events.add(MockStageEvent(stage: 'ROLLUP_START', timestampMs: time));
        for (int i = 0; i < 15; i++) {
          time += _config.baseDelayMs;
          events.add(MockStageEvent(stage: 'ROLLUP_TICK_FAST', timestampMs: time));
        }
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'ROLLUP_END', timestampMs: time));
        time += _config.baseDelayMs * 3;
        events.add(MockStageEvent(stage: 'MEGAWIN_END', timestampMs: time));
        break;

      case MockWinTier.epic:
        events.add(MockStageEvent(stage: 'WIN_EPIC', timestampMs: time, data: {'amount': 500.0}));
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'EPICWIN_START', timestampMs: time));
        time += _config.baseDelayMs * 3;
        events.add(MockStageEvent(stage: 'ROLLUP_START', timestampMs: time));
        for (int i = 0; i < 20; i++) {
          time += _config.baseDelayMs;
          events.add(MockStageEvent(stage: 'ROLLUP_TICK_FAST', timestampMs: time));
        }
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'ROLLUP_END', timestampMs: time));
        time += _config.baseDelayMs * 4;
        events.add(MockStageEvent(stage: 'EPICWIN_END', timestampMs: time));
        break;

      case MockWinTier.jackpotMini:
      case MockWinTier.jackpotMinor:
      case MockWinTier.jackpotMajor:
      case MockWinTier.jackpotGrand:
        final jackpotName = outcome.name.replaceFirst('jackpot', 'JACKPOT_').toUpperCase();
        final amounts = {
          MockWinTier.jackpotMini: 100.0,
          MockWinTier.jackpotMinor: 500.0,
          MockWinTier.jackpotMajor: 2000.0,
          MockWinTier.jackpotGrand: 10000.0,
        };
        events.add(MockStageEvent(stage: 'JACKPOT_TRIGGER', timestampMs: time));
        time += _config.baseDelayMs * 2;
        events.add(MockStageEvent(
          stage: jackpotName,
          timestampMs: time,
          data: {'amount': amounts[outcome]},
        ));
        time += _config.baseDelayMs * 2;
        events.add(MockStageEvent(stage: 'JACKPOT_CELEBRATION', timestampMs: time));
        time += _config.baseDelayMs * 3;
        events.add(MockStageEvent(stage: 'ROLLUP_START', timestampMs: time));
        for (int i = 0; i < 25; i++) {
          time += _config.baseDelayMs;
          events.add(MockStageEvent(stage: 'ROLLUP_TICK', timestampMs: time));
        }
        time += _config.baseDelayMs;
        events.add(MockStageEvent(stage: 'ROLLUP_END', timestampMs: time));
        time += _config.baseDelayMs * 2;
        events.add(MockStageEvent(stage: 'JACKPOT_COLLECT', timestampMs: time));
        break;
    }

    return events;
  }

  double _getOutcomeDuration(MockWinTier outcome) {
    return switch (outcome) {
      MockWinTier.lose => _config.baseDelayMs.toDouble(),
      MockWinTier.small => _config.baseDelayMs * 5.0,
      MockWinTier.medium => _config.baseDelayMs * 8.0,
      MockWinTier.big => _config.baseDelayMs * 15.0,
      MockWinTier.mega => _config.baseDelayMs * 22.0,
      MockWinTier.epic => _config.baseDelayMs * 28.0,
      _ => _config.baseDelayMs * 35.0, // Jackpots
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT PLAYBACK
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _playEvents(List<MockStageEvent> events) async {
    double lastTime = 0;

    for (final event in events) {
      final delay = (event.timestampMs - lastTime).clamp(0, double.infinity);
      if (delay > 0) {
        await Future.delayed(Duration(milliseconds: delay.toInt()));
      }
      _emit(event);
      lastTime = event.timestampMs;
    }
  }

  void _emit(MockStageEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }
}
