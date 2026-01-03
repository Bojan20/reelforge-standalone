/**
 * Event Map - Maps game events to AdapterCommands
 *
 * This is a stub implementation for testing the adapter.
 * In production, RuntimeCore will generate commands dynamically.
 */

import type { AdapterCommand, BusId } from "./audioBackend/types";

/** Game event names */
export type GameEvent =
  | "onBaseGameSpin"
  | "onSpinEnd"
  | "onReelStop"
  | "onWinSmall"
  | "onStopAll";

/** Event to command mapping */
const EVENT_MAP: Record<GameEvent, AdapterCommand[]> = {
  onBaseGameSpin: [
    {
      type: "Play",
      assetId: "spin_loop",
      bus: "SFX" as BusId,
      gain: 1.0,
      loop: true,
    },
  ],

  onSpinEnd: [
    {
      type: "StopAll", // Stop the spin_loop and any other playing sounds
    },
  ],

  onReelStop: [
    {
      type: "Play",
      assetId: "reel_stop",
      bus: "SFX" as BusId,
      gain: 1.0,
      loop: false,
    },
  ],

  onWinSmall: [
    {
      type: "Play",
      assetId: "win_small",
      bus: "SFX" as BusId,
      gain: 1.0,
      loop: false,
    },
  ],

  onStopAll: [
    {
      type: "StopAll",
    },
  ],
};

/**
 * Get commands for a game event
 * @param event - Game event name
 * @returns Array of adapter commands
 */
export function getCommandsForEvent(event: GameEvent): AdapterCommand[] {
  const commands = EVENT_MAP[event];
  if (!commands) {
    console.warn(`[RuntimeStub] Unknown event: ${event}`);
    return [];
  }
  return [...commands]; // Return copy to prevent mutation
}

/**
 * Get all known game events
 */
export function getAllEvents(): GameEvent[] {
  return Object.keys(EVENT_MAP) as GameEvent[];
}

/**
 * Get all required asset IDs for preloading
 */
export function getRequiredAssets(): string[] {
  const assets = new Set<string>();

  for (const commands of Object.values(EVENT_MAP)) {
    for (const cmd of commands) {
      if (cmd.type === "Play") {
        assets.add(cmd.assetId);
      }
    }
  }

  return Array.from(assets);
}
