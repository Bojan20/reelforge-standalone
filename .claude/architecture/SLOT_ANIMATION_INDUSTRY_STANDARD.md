# SLOT ANIMATION INDUSTRY STANDARD — AAA Quality Specification
**Date:** 2026-01-25
**Author:** FluxForge Studio (Claude Code)
**Standard:** IGT, Aristocrat, NetEnt, Pragmatic Play, Big Time Gaming

---

## EXECUTIVE SUMMARY

Ovaj dokument definiše **industry-standard** animacioni sistem za slot igre, baziran na analizi vodećih kompanija (IGT, Aristocrat, NetEnt, Pragmatic Play, Big Time Gaming).

**Cilj:** 100% AAA kvalitet — nerazlučiv od pravih slot mašina.

---

## 1. REEL ANIMATION SYSTEM

### 1.1 Animation Phases (6 faza)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ IDLE → ACCELERATING → SPINNING → DECELERATING → BOUNCING → STOPPED         │
│   0ms     100ms         560ms+      300ms         200ms       ∞             │
└─────────────────────────────────────────────────────────────────────────────┘
```

| Phase | Duration | Easing | Description |
|-------|----------|--------|-------------|
| **IDLE** | — | — | Stationary, čeka spin |
| **ACCELERATING** | 100ms | `easeOutQuad` | 0 → puna brzina (ubrzava brzo) |
| **SPINNING** | 560ms+ | `linear` | Konstantna brzina rotacije |
| **DECELERATING** | 300ms | `easeInQuad` | Usporava, simboli se "usidravaju" |
| **BOUNCING** | 200ms | `elasticOut` | 15% overshoot bounce |
| **STOPPED** | — | — | Mirovanje, čeka sledeći spin |

### 1.2 Per-Reel Stagger (Kaskadno Zaustavljanje)

```
Reel 0: ────────────■ STOP (t=0)
Reel 1: ────────────────■ STOP (t=370ms)
Reel 2: ────────────────────■ STOP (t=740ms)
Reel 3: ────────────────────────■ STOP (t=1110ms)
Reel 4: ────────────────────────────■ STOP (t=1480ms)
```

**Timing po profilu:**

| Profile | Stagger | Total Spin | Use Case |
|---------|---------|------------|----------|
| Normal | 400ms | 2400ms | Desktop casual |
| Turbo | 200ms | 1200ms | Autoplay |
| Mobile | 350ms | 2100ms | Touch devices |
| **Studio** | 370ms | 2220ms | Audio testing |

### 1.3 Easing Curves (Industry Standard)

```dart
// ═══════════════════════════════════════════════════════════════════════════
// ACCELERATION — Fast start, slow end (feels "snappy")
// ═══════════════════════════════════════════════════════════════════════════
double easeOutQuad(double t) => 1 - pow(1 - t, 2);

// ═══════════════════════════════════════════════════════════════════════════
// DECELERATION — Slow start, fast end (feels "heavy")
// ═══════════════════════════════════════════════════════════════════════════
double easeInQuad(double t) => t * t;

// ═══════════════════════════════════════════════════════════════════════════
// BOUNCE — Elastic overshoot (slot machine "clunk")
// ═══════════════════════════════════════════════════════════════════════════
double elasticOut(double t, {double overshoot = 0.15}) {
  if (t == 0 || t == 1) return t;
  final p = 0.3;  // Period
  final s = p / 4;  // Offset
  return pow(2, -10 * t) * sin((t - s) * (2 * pi) / p) + 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// ADVANCED: Spring-Mass-Damper (Pro Quality)
// ═══════════════════════════════════════════════════════════════════════════
double criticallyDampedSpring(double t, double target, double velocity) {
  // ζ = 1 (critically damped — no oscillation)
  final omega = 20.0;  // Natural frequency
  return target - (target + velocity / omega) * exp(-omega * t);
}
```

### 1.4 Symbol Motion During Spin

**Blur Effect:**
```dart
// Motion blur intensity based on phase
double getBlurIntensity(ReelPhase phase, double phaseProgress) {
  switch (phase) {
    case ReelPhase.accelerating:
      return phaseProgress * 0.7;  // 0 → 0.7
    case ReelPhase.spinning:
      return 0.7;  // Constant max
    case ReelPhase.decelerating:
      return 0.7 * (1 - phaseProgress);  // 0.7 → 0
    default:
      return 0.0;
  }
}
```

**Speed Lines:**
```dart
class _SpeedLinesPainter extends CustomPainter {
  final int lineCount = 8;
  final double speed;  // 0.0-1.0

  @override
  void paint(Canvas canvas, Size size) {
    if (speed < 0.3) return;  // Only show at high speed

    final paint = Paint()
      ..color = Colors.white.withOpacity(speed * 0.3)
      ..strokeWidth = 2.0;

    for (int i = 0; i < lineCount; i++) {
      final y = size.height * (i / lineCount);
      final startX = size.width * (1 - speed);
      canvas.drawLine(Offset(startX, y), Offset(size.width, y), paint);
    }
  }
}
```

---

## 2. WIN PRESENTATION SYSTEM

### 2.1 Industry Standard 3-Phase Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: SYMBOL HIGHLIGHT (1050ms)                                          │
│ ├── 3 cycles × 350ms pulse                                                  │
│ ├── Winning symbols glow + bounce                                           │
│ └── Audio: WIN_SYMBOL_HIGHLIGHT                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ PHASE 2: TIER PLAQUE + ROLLUP (1500-20000ms, tier-based)                    │
│ ├── "BIG WIN!" / "MEGA WIN!" etc. plaque appears                           │
│ ├── Coin counter animates from 0 → win amount                              │
│ ├── Particles spawn based on tier                                          │
│ └── Audio: WIN_PRESENT_[TIER], ROLLUP_START, ROLLUP_TICK×N, ROLLUP_END     │
├─────────────────────────────────────────────────────────────────────────────┤
│ PHASE 3: WIN LINE CYCLING (1500ms per line)                                 │
│ ├── Each win line shown sequentially                                        │
│ ├── Line path + symbol positions highlighted                               │
│ ├── Plaque HIDES when this phase starts                                    │
│ └── Audio: WIN_LINE_SHOW (per line)                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

**CRITICAL:** Phase 3 starts **STRICTLY AFTER** Phase 2 ends. No overlap.

### 2.2 Win Tier Classification (Industry Standard)

| Tier | Win/Bet Ratio | Plaque Text | Rollup Duration | Ticks/sec | Particle Count |
|------|---------------|-------------|-----------------|-----------|----------------|
| **SMALL** | < 5x | "WIN!" | 1500ms | 15 | 10 |
| **BIG** | 5x - 15x | "BIG WIN!" | 2500ms | 12 | 20 |
| **SUPER** | 15x - 30x | "SUPER WIN!" | 4000ms | 10 | 30 |
| **MEGA** | 30x - 60x | "MEGA WIN!" | 7000ms | 8 | 40 |
| **EPIC** | 60x - 100x | "EPIC WIN!" | 12000ms | 6 | 50 |
| **ULTRA** | 100x+ | "ULTRA WIN!" | 20000ms | 4 | 60 |

**NOTE:** BIG WIN je **PRVI major tier** — industry standard (Zynga, NetEnt, Pragmatic Play).

### 2.3 Win Tier Visual Configuration

```dart
class WinTierConfig {
  final String label;           // "BIG WIN!"
  final Color primaryColor;     // Dominant color
  final Color glowColor;        // Glow/particle color
  final double fontSize;        // Plaque font size
  final double particleScale;   // Particle size multiplier
  final List<Color> gradient;   // Background gradient
  final Duration rollupDuration;
  final int ticksPerSecond;

  static const Map<String, WinTierConfig> tiers = {
    'SMALL': WinTierConfig(
      label: 'WIN!',
      primaryColor: Color(0xFF4CAF50),  // Green
      glowColor: Color(0xFF81C784),
      fontSize: 48,
      particleScale: 1.0,
      gradient: [Color(0xFF1B5E20), Color(0xFF4CAF50)],
      rollupDuration: Duration(milliseconds: 1500),
      ticksPerSecond: 15,
    ),
    'BIG': WinTierConfig(
      label: 'BIG WIN!',
      primaryColor: Color(0xFFFFD700),  // Gold
      glowColor: Color(0xFFFFE55C),
      fontSize: 64,
      particleScale: 1.2,
      gradient: [Color(0xFFB8860B), Color(0xFFFFD700)],
      rollupDuration: Duration(milliseconds: 2500),
      ticksPerSecond: 12,
    ),
    'SUPER': WinTierConfig(
      label: 'SUPER WIN!',
      primaryColor: Color(0xFFFF9800),  // Orange
      glowColor: Color(0xFFFFB74D),
      fontSize: 72,
      particleScale: 1.4,
      gradient: [Color(0xFFE65100), Color(0xFFFF9800)],
      rollupDuration: Duration(milliseconds: 4000),
      ticksPerSecond: 10,
    ),
    'MEGA': WinTierConfig(
      label: 'MEGA WIN!',
      primaryColor: Color(0xFFE040FB),  // Purple
      glowColor: Color(0xFFEA80FC),
      fontSize: 80,
      particleScale: 1.6,
      gradient: [Color(0xFF7B1FA2), Color(0xFFE040FB)],
      rollupDuration: Duration(milliseconds: 7000),
      ticksPerSecond: 8,
    ),
    'EPIC': WinTierConfig(
      label: 'EPIC WIN!',
      primaryColor: Color(0xFF00BCD4),  // Cyan
      glowColor: Color(0xFF4DD0E1),
      fontSize: 88,
      particleScale: 1.8,
      gradient: [Color(0xFF006064), Color(0xFF00BCD4)],
      rollupDuration: Duration(milliseconds: 12000),
      ticksPerSecond: 6,
    ),
    'ULTRA': WinTierConfig(
      label: 'ULTRA WIN!',
      primaryColor: Color(0xFFFF1744),  // Red
      glowColor: Color(0xFFFF5252),
      fontSize: 96,
      particleScale: 2.0,
      gradient: [Color(0xFFB71C1C), Color(0xFFFF1744)],
      rollupDuration: Duration(milliseconds: 20000),
      ticksPerSecond: 4,
    ),
  };
}
```

### 2.4 Rollup Counter Animation

```dart
class RollupCounter extends StatefulWidget {
  final double targetAmount;
  final Duration duration;
  final int ticksPerSecond;
  final void Function(int tick)? onTick;  // Audio callback

  @override
  State<RollupCounter> createState() => _RollupCounterState();
}

class _RollupCounterState extends State<RollupCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _valueAnimation;
  Timer? _tickTimer;
  int _tickCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    // Easing curve: starts fast, slows at end (classic slot feel)
    _valueAnimation = Tween<double>(
      begin: 0,
      end: widget.targetAmount,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,  // Fast start, slow end
    ));

    // Tick timer for audio sync
    final tickInterval = Duration(
      milliseconds: (1000 / widget.ticksPerSecond).round(),
    );
    _tickTimer = Timer.periodic(tickInterval, (_) {
      if (_controller.isAnimating) {
        widget.onTick?.call(_tickCount++);
      }
    });

    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _valueAnimation,
      builder: (context, child) {
        return Text(
          '\$${_valueAnimation.value.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [
              Shadow(color: Colors.black, blurRadius: 4),
            ],
          ),
        );
      },
    );
  }
}
```

### 2.5 Win Line Rendering

```dart
class WinLinePainter extends CustomPainter {
  final List<Point<int>> positions;  // (reel, row) coordinates
  final Color lineColor;
  final double progress;  // 0-1 for animation
  final double pulseValue;  // 0-1 for glow pulse

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty) return;

    final cellWidth = size.width / 5;   // 5 reels
    final cellHeight = size.height / 3; // 3 rows

    // Calculate center points
    final points = positions.map((p) => Offset(
      (p.x + 0.5) * cellWidth,
      (p.y + 0.5) * cellHeight,
    )).toList();

    // ═══════════════════════════════════════════════════════════════════════
    // LAYER 1: Outer Glow
    // ═══════════════════════════════════════════════════════════════════════
    final glowPaint = Paint()
      ..color = lineColor.withOpacity(0.3 + pulseValue * 0.2)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8);

    _drawConnectingLine(canvas, points, glowPaint);

    // ═══════════════════════════════════════════════════════════════════════
    // LAYER 2: Main Line
    // ═══════════════════════════════════════════════════════════════════════
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    _drawConnectingLine(canvas, points, linePaint);

    // ═══════════════════════════════════════════════════════════════════════
    // LAYER 3: White Core (highlight)
    // ═══════════════════════════════════════════════════════════════════════
    final corePaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    _drawConnectingLine(canvas, points, corePaint);

    // ═══════════════════════════════════════════════════════════════════════
    // LAYER 4: Position Dots
    // ═══════════════════════════════════════════════════════════════════════
    for (final point in points) {
      // Outer glow
      canvas.drawCircle(
        point,
        10 + pulseValue * 4,
        Paint()..color = lineColor.withOpacity(0.5),
      );
      // Inner dot
      canvas.drawCircle(
        point,
        6,
        Paint()..color = Colors.white,
      );
    }
  }

  void _drawConnectingLine(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }
}
```

---

## 3. SYMBOL EFFECTS

### 3.1 Symbol Glow (Winning)

```dart
class SymbolGlow extends StatelessWidget {
  final Widget child;
  final Color glowColor;
  final double intensity;  // 0-1

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(intensity * 0.8),
            blurRadius: 20 * intensity,
            spreadRadius: 5 * intensity,
          ),
        ],
      ),
      child: child,
    );
  }
}
```

### 3.2 Symbol Bounce (Landing)

```dart
class SymbolBounce extends StatefulWidget {
  final Widget child;
  final bool isActive;

  @override
  State<SymbolBounce> createState() => _SymbolBounceState();
}

class _SymbolBounceState extends State<SymbolBounce>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 350),
    );

    _bounce = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0, end: -20),  // Up
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -20, end: 0),  // Down
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0, end: -8),   // Small up
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -8, end: 0),   // Settle
        weight: 25,
      ),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
  }

  @override
  void didUpdateWidget(SymbolBounce oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounce,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _bounce.value),
          child: widget.child,
        );
      },
    );
  }
}
```

### 3.3 Symbol Scale Pulse (Win Highlight)

```dart
class SymbolPulse extends StatefulWidget {
  final Widget child;
  final bool isPulsing;
  final int cycles;  // 3 for standard win

  @override
  State<SymbolPulse> createState() => _SymbolPulseState();
}

class _SymbolPulseState extends State<SymbolPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 350),  // One cycle
    );

    _scale = Tween<double>(begin: 1.0, end: 1.15)
        .animate(CurvedAnimation(
          parent: _controller,
          curve: Curves.easeInOut,
        ));
  }

  @override
  void didUpdateWidget(SymbolPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing && !oldWidget.isPulsing) {
      _runPulseCycles();
    } else if (!widget.isPulsing) {
      _controller.stop();
      _controller.reset();
    }
  }

  void _runPulseCycles() async {
    for (int i = 0; i < widget.cycles; i++) {
      await _controller.forward();
      await _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value,
          child: widget.child,
        );
      },
    );
  }
}
```

---

## 4. PARTICLE SYSTEM

### 4.1 Particle Configuration

```dart
class ParticleConfig {
  final int count;
  final Duration lifetime;
  final double initialVelocityMin;
  final double initialVelocityMax;
  final double gravity;
  final double rotation;  // Radians per second
  final List<Color> colors;
  final double sizeMin;
  final double sizeMax;

  static const Map<String, ParticleConfig> tiers = {
    'SMALL': ParticleConfig(
      count: 10,
      lifetime: Duration(seconds: 2),
      initialVelocityMin: 100,
      initialVelocityMax: 200,
      gravity: 100,
      rotation: 2.0,
      colors: [Colors.green, Colors.lightGreen],
      sizeMin: 4,
      sizeMax: 8,
    ),
    'BIG': ParticleConfig(
      count: 20,
      lifetime: Duration(seconds: 3),
      initialVelocityMin: 150,
      initialVelocityMax: 300,
      gravity: 80,
      rotation: 3.0,
      colors: [Colors.amber, Colors.yellow, Colors.orange],
      sizeMin: 6,
      sizeMax: 12,
    ),
    // ... SUPER, MEGA, EPIC, ULTRA
  };
}
```

### 4.2 Particle Pool (Zero GC Pressure)

```dart
class ParticlePool {
  final List<Particle> _pool = [];
  int _activeCount = 0;

  Particle acquire() {
    if (_activeCount < _pool.length) {
      return _pool[_activeCount++];
    }
    final particle = Particle();
    _pool.add(particle);
    _activeCount++;
    return particle;
  }

  void release(Particle particle) {
    final index = _pool.indexOf(particle);
    if (index != -1 && index < _activeCount) {
      // Swap with last active
      final last = _pool[_activeCount - 1];
      _pool[index] = last;
      _pool[_activeCount - 1] = particle;
      _activeCount--;
    }
  }

  void releaseAll() {
    _activeCount = 0;
  }

  Iterable<Particle> get active => _pool.take(_activeCount);
}

class Particle {
  double x = 0, y = 0;
  double vx = 0, vy = 0;
  double life = 0;
  double maxLife = 3.0;
  double size = 8;
  double rotation = 0;
  double rotationSpeed = 2.0;
  Color color = Colors.gold;

  void reset({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required double size,
    required Color color,
    double life = 3.0,
  }) {
    this.x = x;
    this.y = y;
    this.vx = vx;
    this.vy = vy;
    this.size = size;
    this.color = color;
    this.life = life;
    this.maxLife = life;
    this.rotation = 0;
  }

  void update(double dt, double gravity) {
    x += vx * dt;
    y += vy * dt;
    vy += gravity * dt;
    rotation += rotationSpeed * dt;
    life -= dt;
  }

  double get opacity => (life / maxLife).clamp(0, 1);
  bool get isDead => life <= 0;
}
```

---

## 5. ANTICIPATION & SPECIAL EFFECTS

### 5.1 Anticipation (Last Reels Glow)

```dart
class AnticipationOverlay extends StatefulWidget {
  final Set<int> anticipationReels;  // Which reels are in anticipation

  @override
  State<AnticipationOverlay> createState() => _AnticipationOverlayState();
}

class _AnticipationOverlayState extends State<AnticipationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.anticipationReels.isEmpty) return SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _AnticipationPainter(
            reels: widget.anticipationReels,
            intensity: _controller.value,
          ),
        );
      },
    );
  }
}

class _AnticipationPainter extends CustomPainter {
  final Set<int> reels;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final reelWidth = size.width / 5;

    for (final reel in reels) {
      final center = Offset((reel + 0.5) * reelWidth, size.height / 2);

      // Golden radial glow
      final gradient = RadialGradient(
        colors: [
          Color(0xFFFFD700).withOpacity(0.6 * intensity),
          Color(0xFFFFD700).withOpacity(0.0),
        ],
      );

      final paint = Paint()
        ..shader = gradient.createShader(
          Rect.fromCircle(center: center, radius: reelWidth),
        );

      canvas.drawCircle(center, reelWidth * (0.8 + intensity * 0.2), paint);
    }
  }
}
```

### 5.2 Near Miss Shake

```dart
class NearMissShake extends StatefulWidget {
  final Widget child;
  final bool isShaking;

  @override
  State<NearMissShake> createState() => _NearMissShakeState();
}

class _NearMissShakeState extends State<NearMissShake>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
  }

  @override
  void didUpdateWidget(NearMissShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isShaking && !oldWidget.isShaking) {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final shake = sin(_controller.value * pi * 6) * 4 * (1 - _controller.value);
        return Transform.translate(
          offset: Offset(shake, 0),
          child: widget.child,
        );
      },
    );
  }
}
```

---

## 6. AUDIO-VISUAL SYNC

### 6.1 Stage→Animation Mapping

| Stage | Visual Effect | Duration |
|-------|--------------|----------|
| `SPIN_START` | Reels start accelerating | 100ms |
| `REEL_SPINNING` | Motion blur active | 560ms+ |
| `ANTICIPATION_ON` | Golden glow on reel | Until REEL_STOP |
| `REEL_STOP_N` | Bounce animation | 200ms |
| `WIN_SYMBOL_HIGHLIGHT` | 3× pulse cycle | 1050ms |
| `WIN_PRESENT_[TIER]` | Plaque appear + particles | Tier-based |
| `ROLLUP_START` | Counter begins | — |
| `ROLLUP_TICK` | Counter increment | 67-250ms |
| `ROLLUP_END` | Counter stops | — |
| `WIN_LINE_SHOW` | Line path + dots | 1500ms |

### 6.2 Audio Trigger Points

```dart
// In _finalizeSpin() after all reels stopped:
void _triggerWinAudioSequence(SlotLabSpinResult result) {
  final tier = _getWinTier(result.winRatio);
  final config = WinTierConfig.tiers[tier]!;

  // Phase 1: Symbol Highlight (immediate)
  eventRegistry.triggerStage('WIN_SYMBOL_HIGHLIGHT');

  // Phase 2: Tier + Rollup (after 1050ms)
  Future.delayed(Duration(milliseconds: 1050), () {
    eventRegistry.triggerStage('WIN_PRESENT_$tier');
    eventRegistry.triggerStage('ROLLUP_START');

    // Rollup ticks
    final tickInterval = 1000 ~/ config.ticksPerSecond;
    final totalTicks = config.rollupDuration.inMilliseconds ~/ tickInterval;

    for (int i = 0; i < totalTicks; i++) {
      Future.delayed(Duration(milliseconds: i * tickInterval), () {
        eventRegistry.triggerStage('ROLLUP_TICK');
      });
    }

    // Rollup end
    Future.delayed(config.rollupDuration, () {
      eventRegistry.triggerStage('ROLLUP_END');
      _startWinLinePresentation();  // Phase 3
    });
  });
}
```

---

## 7. V8: ENHANCED WIN PLAQUE ANIMATION (2026-01-25)

### 7.1 Screen Flash Effect

Brief white/gold flash when plaque appears for dramatic impact:

```dart
// Animation controller (150ms)
_screenFlashController = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 150),
);
_screenFlashOpacity = Tween<double>(begin: 0.8, end: 0.0).animate(
  CurvedAnimation(parent: _screenFlashController, curve: Curves.easeOut),
);

// Trigger at Phase 2 start
_screenFlashController.forward(from: 0);
```

### 7.2 Plaque Glow Pulse

Continuous pulsing glow effect during plaque display:

```dart
// 400ms cycle, repeating
_plaqueGlowController = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 400),
)..repeat(reverse: true);
_plaqueGlowPulse = Tween<double>(begin: 0.7, end: 1.0).animate(
  CurvedAnimation(parent: _plaqueGlowController, curve: Curves.easeInOut),
);
```

### 7.3 Celebration Particle Burst

Particle explosion on plaque entrance based on tier:

```dart
void _spawnPlaqueCelebrationParticles(String tier) {
  final particleCount = switch (tier) {
    'ULTRA' => 80,
    'EPIC' => 60,
    'MEGA' => 45,
    'SUPER' => 30,
    'BIG' => 20,
    _ => 10,
  };

  // Burst from center outward in all directions
  for (int i = 0; i < particleCount; i++) {
    final angle = random.nextDouble() * pi * 2;
    final speed = 0.02 + random.nextDouble() * 0.03;

    _particles.add(_particlePool.acquire(
      x: 0.5,  // Center X
      y: 0.45, // Above center (plaque position)
      vx: cos(angle) * speed,
      vy: sin(angle) * speed - 0.01,  // Upward bias
      size: random.nextDouble() * 10 + 5,
      color: _getParticleColor(tier),
      type: i % 3 == 0 ? ParticleType.coin : ParticleType.sparkle,
    ));
  }
}
```

### 7.4 Tier-Based Scale Multipliers

Dramatic entrance with tier-based scaling:

| Tier | Scale Multiplier | Slide Distance |
|------|------------------|----------------|
| ULTRA | 1.25 | 80px |
| EPIC | 1.2 | 80px |
| MEGA | 1.15 | 80px |
| SUPER | 1.1 | 80px |
| BIG | 1.05 | 80px |
| SMALL | 1.0 | 40px |

---

## 8. STOP BUTTON CONTROL SYSTEM (2026-01-25)

### 8.1 isReelsSpinning vs isPlayingStages

**Problem:** STOP button was visible during win presentation (not just reel spinning).

**Solution:** Separate tracking for actual reel spinning vs overall stage playback.

| State | Purpose | Usage |
|-------|---------|-------|
| `isPlayingStages` | True during all stages (spin + win) | Disable SPIN button |
| `isReelsSpinning` | True ONLY while reels spinning | Show STOP button |

### 8.2 State Transitions

```
SPIN_START → isReelsSpinning = true
    ↓
REEL_STOP_0..4 (visual animation)
    ↓
onAllReelsVisualStop() → isReelsSpinning = false
    ↓
WIN_PRESENT, ROLLUP, WIN_LINE_SHOW (isPlayingStages still true)
    ↓
SPIN_END → isPlayingStages = false
```

### 8.3 Implementation

**SlotLabProvider:**
```dart
// Set true on SPIN_START
if (stageType == 'SPIN_START') {
  _isReelsSpinning = true;
  notifyListeners();
}

// Called by slot_preview_widget when ALL reels visually stopped
void onAllReelsVisualStop() {
  if (_isReelsSpinning) {
    _isReelsSpinning = false;
    notifyListeners();
  }
}
```

**Premium Slot Preview:**
```dart
// In build()
final isSpinning = provider.isPlayingStages;       // For SPIN button disable
final isReelsActuallySpinning = provider.isReelsSpinning;  // For STOP button

// Pass to ControlBar
_ControlBar(
  isSpinning: isSpinning,
  showStopButton: isReelsActuallySpinning,  // STOP only during reel spinning
  ...
)
```

---

## 9. IMPLEMENTATION STATUS

| Feature | Status | Notes |
|---------|--------|-------|
| 6-Phase Reel Animation | ✅ 100% | All phases implemented |
| Per-Reel Stagger | ✅ 100% | 370ms studio profile |
| IGT Sequential Buffer | ✅ 100% | Implemented 2026-01-25 |
| Motion Blur | ✅ 100% | Gradient overlay |
| Symbol Bounce | ✅ 100% | Elastic overshoot |
| Win Tier Classification | ✅ 100% | BIG = first major tier |
| 3-Phase Win Presentation | ✅ 100% | Strict sequential |
| Rollup Counter | ✅ 100% | Tier-based timing |
| Win Line Rendering | ✅ 100% | 3-layer + dots |
| Particle System | ✅ 100% | Object pooled |
| Anticipation Glow | ✅ 100% | Pulsing radial |
| Near Miss Shake | ✅ 100% | Dampened oscillation |
| **V8: Win Plaque Animation** | ✅ 100% | Screen flash, glow pulse, particle burst |
| **STOP Button Control** | ✅ 100% | isReelsSpinning tracking |

**Overall:** 100% Industry Standard Implementation

---

## 8. REFERENCE: Industry Companies

| Company | Signature Style | Key Features |
|---------|----------------|--------------|
| **IGT** | Classic, reliable | State machine, sequential stops, clear feedback |
| **Aristocrat** | Premium, smooth | Spring physics, rich particles, dramatic wins |
| **NetEnt** | Modern, polished | Cascade effects, 3D symbols, cinematic wins |
| **Pragmatic Play** | Bold, colorful | Big tier badges, intense particles, fast rollup |
| **Big Time Gaming** | Innovative | Megaways, expanding reels, feature previews |

---

## APPENDIX: Timing Reference Card

```
SPIN CYCLE (Studio Profile):
├── Acceleration:     100ms
├── Spinning:         560ms (base) + stagger
├── Per-Reel Stop:    370ms apart
├── Bounce:           200ms
└── Total:            ~2500ms (5 reels)

WIN PRESENTATION:
├── Phase 1:          1050ms (3 × 350ms pulse)
├── Phase 2:          1500-20000ms (tier-based)
└── Phase 3:          1500ms × line_count

PARTICLE LIFETIME:    2-4 seconds
ANTICIPATION PULSE:   800ms (repeat)
NEAR MISS SHAKE:      500ms
```
