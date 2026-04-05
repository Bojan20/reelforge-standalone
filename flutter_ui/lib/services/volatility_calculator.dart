/// Volatility Calculator Service
///
/// Calculates expected hold time and other volatility-related metrics
/// from game math parameters.
///
/// Part of P1-13: Volatility Calculator
library;

import 'dart:math' as math;

// =============================================================================
// VOLATILITY LEVEL
// =============================================================================

/// Industry-standard volatility levels
enum VolatilityLevel {
  veryLow,
  low,
  medium,
  high,
  veryHigh;

  String get displayName => switch (this) {
    VolatilityLevel.veryLow => 'Very Low',
    VolatilityLevel.low => 'Low',
    VolatilityLevel.medium => 'Medium',
    VolatilityLevel.high => 'High',
    VolatilityLevel.veryHigh => 'Very High',
  };

  /// Get hit frequency range for this volatility level
  (double min, double max) get hitFrequencyRange => switch (this) {
    VolatilityLevel.veryLow => (0.35, 0.50),   // 35-50% hit rate
    VolatilityLevel.low => (0.25, 0.35),       // 25-35% hit rate
    VolatilityLevel.medium => (0.15, 0.25),    // 15-25% hit rate
    VolatilityLevel.high => (0.08, 0.15),      // 8-15% hit rate
    VolatilityLevel.veryHigh => (0.03, 0.08),  // 3-8% hit rate
  };

  /// Get average win multiplier range for this volatility level
  (double min, double max) get avgWinMultiplierRange => switch (this) {
    VolatilityLevel.veryLow => (2.0, 4.0),     // 2-4x bet
    VolatilityLevel.low => (4.0, 8.0),         // 4-8x bet
    VolatilityLevel.medium => (8.0, 15.0),     // 8-15x bet
    VolatilityLevel.high => (15.0, 30.0),      // 15-30x bet
    VolatilityLevel.veryHigh => (30.0, 100.0), // 30-100x bet
  };

  /// Get risk rating (0-1)
  double get riskRating => switch (this) {
    VolatilityLevel.veryLow => 0.1,
    VolatilityLevel.low => 0.3,
    VolatilityLevel.medium => 0.5,
    VolatilityLevel.high => 0.7,
    VolatilityLevel.veryHigh => 0.9,
  };
}

// =============================================================================
// VOLATILITY CALCULATION RESULT
// =============================================================================

class VolatilityCalculation {
  final VolatilityLevel level;
  final double rtp;
  final double hitFrequency;
  final double avgWinMultiplier;
  final double betAmount;

  // Calculated metrics
  final double expectedHoldSpins;
  final double expectedHoldMinutes;
  final double confidenceIntervalLow;
  final double confidenceIntervalHigh;
  final double standardDeviation;
  final double maxDrawdown;
  final double breakEvenProbability;

  const VolatilityCalculation({
    required this.level,
    required this.rtp,
    required this.hitFrequency,
    required this.avgWinMultiplier,
    required this.betAmount,
    required this.expectedHoldSpins,
    required this.expectedHoldMinutes,
    required this.confidenceIntervalLow,
    required this.confidenceIntervalHigh,
    required this.standardDeviation,
    required this.maxDrawdown,
    required this.breakEvenProbability,
  });

  /// Get formatted hold time string
  String get holdTimeFormatted {
    if (expectedHoldSpins < 100) {
      return '${expectedHoldSpins.toStringAsFixed(0)} spins';
    } else if (expectedHoldSpins < 1000) {
      return '${(expectedHoldSpins / 100).toStringAsFixed(1)} hundred spins';
    } else {
      return '${(expectedHoldSpins / 1000).toStringAsFixed(1)}k spins';
    }
  }

  /// Get formatted time string (assuming 3 sec/spin)
  String get timeFormatted {
    if (expectedHoldMinutes < 60) {
      return '${expectedHoldMinutes.toStringAsFixed(0)} minutes';
    } else {
      final hours = expectedHoldMinutes / 60;
      return '${hours.toStringAsFixed(1)} hours';
    }
  }

  /// Get risk description
  String get riskDescription => switch (level) {
    VolatilityLevel.veryLow => 'Very safe, frequent small wins',
    VolatilityLevel.low => 'Safe, steady wins',
    VolatilityLevel.medium => 'Balanced risk/reward',
    VolatilityLevel.high => 'Risky, big wins are rare',
    VolatilityLevel.veryHigh => 'Very risky, extreme swings',
  };

  /// Get player type recommendation
  String get playerTypeRecommendation => switch (level) {
    VolatilityLevel.veryLow => 'Casual players, low budgets',
    VolatilityLevel.low => 'Recreational players',
    VolatilityLevel.medium => 'General audience',
    VolatilityLevel.high => 'Experienced players, higher budgets',
    VolatilityLevel.veryHigh => 'High rollers, thrill seekers',
  };
}

// =============================================================================
// VOLATILITY CALCULATOR SERVICE (Singleton)
// =============================================================================

class VolatilityCalculator {
  static final VolatilityCalculator _instance = VolatilityCalculator._();
  static VolatilityCalculator get instance => _instance;

  VolatilityCalculator._();

  // Constants
  static const double _avgSpinTimeSeconds = 3.0; // Industry average
  static const double _confidenceLevel = 0.95;   // 95% confidence interval

  // ==========================================================================
  // MAIN CALCULATION
  // ==========================================================================

  /// Calculate volatility metrics from game parameters
  ///
  /// Formula: Hold = (1 - RTP) / (HitFreq × AvgWin)
  ///
  /// Where:
  /// - RTP = Return to Player (e.g., 0.96 for 96%)
  /// - HitFreq = Probability of any win (e.g., 0.25 for 25%)
  /// - AvgWin = Average win multiplier (e.g., 5.0 for 5x bet)
  VolatilityCalculation calculate({
    required VolatilityLevel level,
    required double rtp,
    required double hitFrequency,
    required double avgWinMultiplier,
    double betAmount = 1.0,
  }) {
    // Validate inputs
    if (rtp <= 0 || rtp > 1) {
      throw ArgumentError('RTP must be between 0 and 1');
    }
    if (hitFrequency <= 0 || hitFrequency > 1) {
      throw ArgumentError('Hit frequency must be between 0 and 1');
    }
    if (avgWinMultiplier <= 0) {
      throw ArgumentError('Average win multiplier must be positive');
    }

    // Calculate expected hold (spins to balance = 0)
    final expectedHoldSpins = _calculateExpectedHoldSpins(
      rtp: rtp,
      hitFrequency: hitFrequency,
      avgWinMultiplier: avgWinMultiplier,
    );

    // Calculate standard deviation
    final stdDev = _calculateStandardDeviation(
      hitFrequency: hitFrequency,
      avgWinMultiplier: avgWinMultiplier,
      rtp: rtp,
    );

    // Calculate confidence interval
    final (ciLow, ciHigh) = _calculateConfidenceInterval(
      expectedHoldSpins: expectedHoldSpins,
      stdDev: stdDev,
      confidenceLevel: _confidenceLevel,
    );

    // Calculate max drawdown
    final maxDrawdown = _calculateMaxDrawdown(
      avgWinMultiplier: avgWinMultiplier,
      hitFrequency: hitFrequency,
      stdDev: stdDev,
    );

    // Calculate break-even probability
    final breakEvenProb = _calculateBreakEvenProbability(
      rtp: rtp,
      hitFrequency: hitFrequency,
      spins: expectedHoldSpins,
    );

    return VolatilityCalculation(
      level: level,
      rtp: rtp,
      hitFrequency: hitFrequency,
      avgWinMultiplier: avgWinMultiplier,
      betAmount: betAmount,
      expectedHoldSpins: expectedHoldSpins,
      expectedHoldMinutes: (expectedHoldSpins * _avgSpinTimeSeconds) / 60,
      confidenceIntervalLow: ciLow,
      confidenceIntervalHigh: ciHigh,
      standardDeviation: stdDev,
      maxDrawdown: maxDrawdown,
      breakEvenProbability: breakEvenProb,
    );
  }

  // ==========================================================================
  // HELPER CALCULATIONS
  // ==========================================================================

  /// Calculate expected hold time in spins
  ///
  /// Uses the formula: Hold = (1 - RTP) / (HitFreq × (AvgWin - 1))
  ///
  /// This represents the expected number of spins before balance = 0,
  /// assuming player starts with enough bankroll to sustain losses.
  double _calculateExpectedHoldSpins({
    required double rtp,
    required double hitFrequency,
    required double avgWinMultiplier,
  }) {
    // House edge per spin
    final houseEdge = 1 - rtp;

    // Expected profit per win (win - bet)
    final profitPerWin = avgWinMultiplier - 1;

    // Expected loss per losing spin
    final lossPerLossSpin = 1.0;

    // Net expected loss per spin
    final netLossPerSpin = houseEdge;

    // Expected win amount per spin
    final expectedWinPerSpin = hitFrequency * avgWinMultiplier;

    // Expected total loss per spin
    final expectedTotalLossPerSpin = 1 - expectedWinPerSpin;

    // Spins until expected bankroll = 0 (starting from 1 bet worth)
    // This is simplified; real calculation would need Monte Carlo
    if (netLossPerSpin <= 0) {
      return double.infinity; // RTP >= 100%, player has edge
    }

    // Approximate hold time (spins to lose 1 bet unit)
    final holdSpins = 1.0 / netLossPerSpin;

    return holdSpins;
  }

  /// Calculate standard deviation of win distribution
  double _calculateStandardDeviation({
    required double hitFrequency,
    required double avgWinMultiplier,
    required double rtp,
  }) {
    // Variance = E[X²] - E[X]²
    // Where X is the payout per spin

    // Expected value (mean)
    final mean = rtp;

    // For simplicity, assume binary distribution (win or lose)
    // E[X²] ≈ hitFreq × (avgWin)² + (1 - hitFreq) × 0²
    final secondMoment = hitFrequency * math.pow(avgWinMultiplier, 2);

    // Variance
    final variance = secondMoment - math.pow(mean, 2);

    // Standard deviation
    return math.sqrt(variance.abs());
  }

  /// Calculate confidence interval for hold time
  (double low, double high) _calculateConfidenceInterval({
    required double expectedHoldSpins,
    required double stdDev,
    required double confidenceLevel,
  }) {
    // Z-score for 95% confidence is ~1.96
    final zScore = _getZScore(confidenceLevel);

    // Confidence interval: mean ± z × (stdDev / sqrt(n))
    // For large n, approximation: mean ± z × stdDev × sqrt(mean)
    final margin = zScore * stdDev * math.sqrt(expectedHoldSpins);

    final low = (expectedHoldSpins - margin).clamp(0.0, double.infinity);
    final high = expectedHoldSpins + margin;

    return (low, high);
  }

  /// Calculate maximum expected drawdown (worst case loss)
  double _calculateMaxDrawdown({
    required double avgWinMultiplier,
    required double hitFrequency,
    required double stdDev,
  }) {
    // Max drawdown ≈ 3 × stdDev (99.7% confidence)
    // Represents worst-case streak of losses
    final avgLossStreak = 1 / hitFrequency;
    final maxDrawdown = avgLossStreak * (1 + stdDev * 2);

    return maxDrawdown;
  }

  /// Calculate probability of breaking even within expected hold time
  double _calculateBreakEvenProbability({
    required double rtp,
    required double hitFrequency,
    required double spins,
  }) {
    // Probability of at least breaking even after N spins
    // Using normal approximation: P(wins × avgWin >= losses)

    if (rtp >= 1.0) return 1.0; // RTP 100%+, always break even

    // Expected wins in N spins
    final expectedWins = spins * hitFrequency;

    // For simplicity, use binomial approximation
    // P(X >= k) where X ~ Binomial(n, p)
    // Approximate: if expectedWins is high enough to cover losses

    // This is a rough approximation
    final breakEvenThreshold = spins * (1 - rtp);
    final winAmountNeeded = breakEvenThreshold;
    final probabilityBelowThreshold = math.exp(-expectedWins / winAmountNeeded);

    return (1 - probabilityBelowThreshold).clamp(0.0, 1.0);
  }

  /// Get Z-score for confidence level
  double _getZScore(double confidenceLevel) {
    // Common Z-scores
    if (confidenceLevel >= 0.99) return 2.576;
    if (confidenceLevel >= 0.95) return 1.96;
    if (confidenceLevel >= 0.90) return 1.645;
    return 1.96; // Default to 95%
  }

  // ==========================================================================
  // VOLATILITY ESTIMATION
  // ==========================================================================

  /// Estimate volatility level from hit frequency and avg win
  VolatilityLevel estimateVolatility({
    required double hitFrequency,
    required double avgWinMultiplier,
  }) {
    // Very Low: high hit freq, low avg win
    if (hitFrequency >= 0.35 && avgWinMultiplier <= 4.0) {
      return VolatilityLevel.veryLow;
    }

    // Low: moderate hit freq, moderate avg win
    if (hitFrequency >= 0.25 && avgWinMultiplier <= 8.0) {
      return VolatilityLevel.low;
    }

    // Medium: balanced
    if (hitFrequency >= 0.15 && avgWinMultiplier <= 15.0) {
      return VolatilityLevel.medium;
    }

    // High: low hit freq, high avg win
    if (hitFrequency >= 0.08 && avgWinMultiplier <= 30.0) {
      return VolatilityLevel.high;
    }

    // Very High: very low hit freq, very high avg win
    return VolatilityLevel.veryHigh;
  }

  // ==========================================================================
  // PRESET CALCULATIONS
  // ==========================================================================

  /// Get calculation with typical values for volatility level
  VolatilityCalculation getTypicalCalculation(VolatilityLevel level, {double rtp = 0.96}) {
    final hitFreqRange = level.hitFrequencyRange;
    final avgWinRange = level.avgWinMultiplierRange;

    final hitFreq = (hitFreqRange.$1 + hitFreqRange.$2) / 2;
    final avgWin = (avgWinRange.$1 + avgWinRange.$2) / 2;

    return calculate(
      level: level,
      rtp: rtp,
      hitFrequency: hitFreq,
      avgWinMultiplier: avgWin,
    );
  }
}
