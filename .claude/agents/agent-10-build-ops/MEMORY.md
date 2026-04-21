# Agent 10: BuildOps — Memory

## Accumulated Knowledge
- ExFAT creates ._* files → codesign fails
- DerivedData MUST be on internal disk (HOME)
- edition "2024" requires nightly Rust
- Homebrew paths now use $(brew --prefix)
- bundle_dylibs.sh has cycle detection (visited set)

## Patterns
- Build: cargo → copy dylibs → analyze → xcodebuild → copy to bundle → open
- Test: cargo test -p <crate>
- Benchmark: cargo bench -p rf-bench
- Fuzz: cargo test -p rf-fuzz

## Gotchas
- clean_xattrs.sh must run before xcodebuild on ExFAT
- Pods ._* files also cause issues
- @rpath linking requires correct install_name_tool settings
