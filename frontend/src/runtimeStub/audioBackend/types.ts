/**
 * AudioBackend Types - Shared types for audio backend abstraction
 *
 * These types allow RuntimeStub to remain backend-agnostic.
 * No React dependencies. No runtime DSP.
 */

/** Audio bus identifiers */
export type BusId = "Master" | "Music" | "SFX" | "UI" | "VO";

/** Play command */
export interface PlayCommand {
  type: "Play";
  assetId: string;
  bus: BusId;
  gain: number;
  loop: boolean;
  startTimeMs?: number;
}

/** Stop a specific voice */
export interface StopCommand {
  type: "Stop";
  voiceId: string;
}

/** Stop all voices */
export interface StopAllCommand {
  type: "StopAll";
}

/** Set bus gain */
export interface SetBusGainCommand {
  type: "SetBusGain";
  bus: BusId;
  gain: number;
}

/** Union of all adapter commands */
export type AdapterCommand =
  | PlayCommand
  | StopCommand
  | StopAllCommand
  | SetBusGainCommand;

/** Latency statistics */
export interface LatencyStats {
  count: number;
  minMs: number;
  maxMs: number;
  avgMs: number;
  lastMs: number;
}

/** Audio backend interface */
export interface AudioBackend {
  /**
   * Preload audio assets
   * @param assetIds - Array of asset IDs to preload
   */
  preload(assetIds: string[]): Promise<void>;

  /**
   * Execute commands sequentially
   * @param commands - Array of commands to execute
   * @returns Map of command index to voiceId for Play commands
   */
  execute(commands: AdapterCommand[]): Map<number, string>;

  /**
   * Get backend statistics (optional)
   */
  getStats?(): {
    activeVoices: number;
    pendingTimers: number;
    busGains: Record<BusId, number>;
  };
}

/** Asset resolver interface */
export interface AssetResolver {
  /**
   * Resolve assetId to audio URL or blob URL
   */
  resolveUrl(assetId: string): string | undefined;
}
