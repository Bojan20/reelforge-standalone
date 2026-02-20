# Engine Invariants

1. RoutingGraph memory stable during process().
2. No heap allocation in audio thread.
3. Graph swap is atomic and lock-free.
4. Solo recompute complexity O(n).
5. No per-sample envelope traversal.
6. Freeze replaces DSP chain.
7. Undo triggers routing recompilation.
8. Processing time < buffer duration.

Violation of invariant = engine regression.
