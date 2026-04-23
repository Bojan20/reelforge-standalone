# Agent 6: GameArchitect — Memory

## Accumulated Knowledge
- Game flow FSM: BASE_GAME → FREE_SPINS → CASCADING → BONUS (with sub-states)
- Feature Composer has 12+ mechanics: free spins, bonus games, cascading, hold & win, wild features, collector, respin, gamble, multiplier, jackpot, pick games
- 3 presets: BASIC (simple), STD (standard), FULL (all mechanics)
- Behavior tree: 22+ node types with visual editor in HELIX BT panel
- Simulation engine runs deterministic spins with configurable parameters

## Patterns
- Executor pattern: each feature mechanic has dedicated executor class
- Game flow integration bridges FSM state with audio/visual systems
- Pacing engine controls timing of events (prevents instant avalanche of wins)
- Stage flow maps game states to audio stages

## Decisions
- Win tier system is fully data-driven via WinTierConfig (P5 model)
- BIG_WIN_END self-manages BIG_WIN_START cleanup
- Feature Composer composes mechanics into coherent game configurations
- BT persistence uses toJson/loadFromJson with dirty flag tracking

## Gotchas
- _bigWinEndFired is a guard against skip-during-hold double-fire
- Free spins balance guard (_isInFreeSpins) prevents incorrect deductions
- Behavior tree coverage provider tracks which paths are tested
