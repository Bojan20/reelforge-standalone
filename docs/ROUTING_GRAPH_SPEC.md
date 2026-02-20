# RoutingGraph Specification

Status: Canonical Structure

## Structure Model

struct RoutingGraph {
    active_channels: usize,

    gains: [f32; MAX_CHANNELS],
    mutes: [bool; MAX_CHANNELS],
    pans: [f32; MAX_CHANNELS],
    effective_gain: [f32; MAX_CHANNELS],

    sends: [[SendSlot; MAX_SENDS]; MAX_CHANNELS],
    insert_chains: [InsertChain; MAX_CHANNELS],
}

No HashMap allowed.
No Vec resizing allowed.
No business logic allowed.

## SendSlot

struct SendSlot {
    active: bool,
    gain: f32,
    target_bus: usize,
    pre_fader: bool,
}

## InsertChain

struct InsertChain {
    plugins: [PluginSlot; MAX_INSERTS],
}

## Execution Loop

for ch in 0..active_channels {
    if mutes[ch] { continue; }

    apply_gain(ch);
    process_inserts(ch);
    apply_pan(ch);
    process_sends(ch);
    write_meter(ch);
}

## Recompile Rule

Solo / VCA / Folder / Automation changes:
1. SessionGraph recomputes state.
2. New RoutingGraph constructed.
3. Atomic swap.
4. Old graph released outside audio thread.
