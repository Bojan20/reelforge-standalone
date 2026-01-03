/**
 * ReelForge M7.1 Preview Executor Hook
 *
 * Single execution path for all audio commands.
 * Syncs preview mix state before executing audio commands.
 * All command execution (Audition, GameEventFired, LocalFlood) MUST go through this.
 */

import { useCallback, useRef } from 'react';
import { usePreviewMix } from '../core/PreviewMixContext';
import type { BusId } from '../core/types';

/** Command types matching RuntimeCore/RouteSimulation */
export interface ExecutableCommand {
  type: 'Play' | 'Stop' | 'StopAll' | 'SetBusGain' | 'Fade' | 'Pause';
  assetId?: string;
  bus?: string;
  gain?: number;
  loop?: boolean;
  voiceId?: string;
  // Extended parameters
  fadeIn?: number;       // Fade in duration in seconds
  fadeOut?: number;      // Fade out duration in seconds
  delay?: number;        // Delay before execution in seconds
  pan?: number;          // -1.0 (left) to 1.0 (right), default 0.0 (center)
  loopCount?: number;    // Number of loops (0 = infinite when loop=true)
  overlap?: boolean;     // Allow overlapping instances
  // Fade-specific
  targetVolume?: number; // Target volume for Fade action
  duration?: number;     // Fade duration in seconds
  durationUp?: number;   // Asymmetric fade up duration
  durationDown?: number; // Asymmetric fade down duration
  // Pause-specific
  overall?: boolean;     // Pause entire audio system
}

/** Last executed command for debug display */
export interface LastCommandInfo {
  type: string;
  bus?: string;
  timestamp: number;
}

interface AudioExecutor {
  execute: (cmd: ExecutableCommand) => void;
}

interface UsePreviewExecutorOptions {
  /** Audio backend for execution */
  audioExecutor?: AudioExecutor | null;
  /** Log commands to console */
  logCommands?: boolean;
}

export function usePreviewExecutor({
  audioExecutor,
  logCommands = false,
}: UsePreviewExecutorOptions = {}) {
  const {
    setBusGain,
    onVoiceStart,
    onVoiceEnd,
    onStopAll,
    fullReset,
    snapshot,
  } = usePreviewMix();

  // Track last command for debug overlay
  const lastCommandRef = useRef<LastCommandInfo | null>(null);

  /**
   * Normalize bus string to BusId.
   */
  const normalizeBusId = useCallback((bus?: string): BusId => {
    if (!bus) return 'sfx';
    const lower = bus.toLowerCase();
    switch (lower) {
      case 'master': return 'master';
      case 'music': return 'music';
      case 'sfx': return 'sfx';
      case 'ambience': return 'ambience';
      case 'voice':
      case 'vo': return 'voice';
      default: return 'sfx';
    }
  }, []);

  /**
   * Execute a single command with preview sync.
   */
  const executeCommand = useCallback((cmd: ExecutableCommand) => {
    const busId = normalizeBusId(cmd.bus);

    // Update last command for debug
    lastCommandRef.current = {
      type: cmd.type,
      bus: cmd.bus,
      timestamp: Date.now(),
    };

    if (logCommands) {
      console.log('[PreviewExecutor] Command:', cmd.type, cmd.bus || '', cmd);
    }

    // Sync preview mix state BEFORE executing audio
    switch (cmd.type) {
      case 'Play':
        onVoiceStart(busId);
        break;
      case 'Stop':
        onVoiceEnd(busId);
        break;
      case 'StopAll':
        onStopAll();
        break;
      case 'SetBusGain':
        if (cmd.gain !== undefined) {
          setBusGain(busId, cmd.gain);
        }
        break;
      case 'Fade':
        // Fade adjusts gain over time - update target gain
        if (cmd.targetVolume !== undefined) {
          setBusGain(busId, cmd.targetVolume);
        }
        break;
      case 'Pause':
        // Pause stops playback but keeps state
        if (cmd.overall) {
          onStopAll();
        } else {
          onVoiceEnd(busId);
        }
        break;
    }

    // Execute audio command if backend available
    if (audioExecutor) {
      audioExecutor.execute(cmd);
    }
  }, [audioExecutor, logCommands, normalizeBusId, onVoiceStart, onVoiceEnd, onStopAll, setBusGain]);

  /**
   * Execute multiple commands with preview sync.
   */
  const executeCommands = useCallback((commands: ExecutableCommand[]) => {
    for (const cmd of commands) {
      executeCommand(cmd);
    }
  }, [executeCommand]);

  /**
   * Local flood: trigger N events without WS.
   * Uses provided event-to-commands mapper.
   */
  const localFlood = useCallback((
    count: number,
    getCommandsForEvent: (eventName: string) => ExecutableCommand[],
    eventName: string = 'onReelStop',
    throttleMs: number = 0,
  ): { sentCount: number; cancelFlood: () => void } => {
    let cancelled = false;
    let sentCount = 0;

    const cancelFlood = () => {
      cancelled = true;
    };

    const sendBatch = () => {
      if (cancelled || sentCount >= count) {
        return;
      }

      const commands = getCommandsForEvent(eventName);
      executeCommands(commands);
      sentCount++;

      if (sentCount < count) {
        if (throttleMs > 0) {
          setTimeout(sendBatch, throttleMs);
        } else {
          // Immediate next tick to not block UI
          requestAnimationFrame(sendBatch);
        }
      }
    };

    // Start flooding
    sendBatch();

    return { sentCount: count, cancelFlood };
  }, [executeCommands]);

  /**
   * Full reset (project load, session reset).
   */
  const reset = useCallback(() => {
    fullReset();
  }, [fullReset]);

  /**
   * Get last executed command info.
   */
  const getLastCommand = useCallback((): LastCommandInfo | null => {
    return lastCommandRef.current;
  }, []);

  return {
    executeCommand,
    executeCommands,
    localFlood,
    reset,
    getLastCommand,
    snapshot,
    // Re-export individual handlers for direct access
    onVoiceStart,
    onVoiceEnd,
    onStopAll: () => {
      onStopAll();
      if (audioExecutor) {
        audioExecutor.execute({ type: 'StopAll' });
      }
    },
    setBusGain: (busId: BusId, gain: number) => {
      setBusGain(busId, gain);
      if (audioExecutor) {
        audioExecutor.execute({ type: 'SetBusGain', bus: busId, gain });
      }
    },
  };
}
