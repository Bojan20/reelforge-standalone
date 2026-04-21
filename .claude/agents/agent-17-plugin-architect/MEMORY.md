# Agent 17: PluginArchitect — Memory

## Accumulated Knowledge
- MIDI was completely missing in 4/5 formats (BUG #24 — fixed)
- CLAP extensions: params flush, state stream, latency, GUI
- LV2 URID map: 17 pre-registered URIs, global thread-safe
- Out-of-process GUI avoids Flutter Metal conflicts
- PDC tracked per-plugin, compensated in chain

## Patterns
- Lifecycle: scan → load → instantiate → activate → process → deactivate → destroy
- CLAP Drop: destroy() → plugin_ptr = null
- LV2 Drop: cleanup() → handle = null_mut + descriptor = null

## Gotchas
- CLAP query_ext() can return null
- LV2 URID mutex can be poisoned
- Plugin can be unloaded between get() and use() — hold Arc
- closeEditor() is async — must await before deactivate
