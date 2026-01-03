/**
 * ReelForge M6.9 Route Simulation Panel
 *
 * Event → commands preview with optional audition.
 * Supports both native core mode and routes-only fallback.
 */

import { useState, useCallback, useRef, useMemo } from 'react';
import type { RoutesConfig, RouteAction, PlayAction, SetBusGainAction } from '../core/routesTypes';
import type { NativeAdapterCommand, INativeRuntimeCore, NativeRuntimeCoreWrapper } from '../core/nativeRuntimeCore';
import './RouteSimulationPanel.css';

// Ring buffer capacity for simulation history
const HISTORY_CAPACITY = 50;

/**
 * Simulated command (unified format for display).
 */
export interface SimulatedCommand {
  type: 'Play' | 'Stop' | 'StopAll' | 'SetBusGain';
  assetId?: string;
  bus?: string;
  gain?: number;
  loop?: boolean;
  voiceId?: string;
}

/**
 * Simulation result entry.
 */
export interface SimulationEntry {
  id: number;
  timestamp: number;
  eventName: string;
  commands: SimulatedCommand[];
  mode: 'native' | 'routes';
  auditioned: boolean;
}

interface RouteSimulationPanelProps {
  /** Current routes config */
  config: RoutesConfig;
  /** Native runtime core instance (optional) */
  nativeCore?: INativeRuntimeCore | NativeRuntimeCoreWrapper | null;
  /** Audio backend for audition (optional) */
  audioBackend?: {
    execute: (command: NativeAdapterCommand) => void;
  } | null;
  /** Selected event name to highlight */
  selectedEventName?: string;
}

/**
 * Convert RouteAction to SimulatedCommand.
 */
function actionToSimulatedCommand(
  action: RouteAction,
  defaultBus: string
): SimulatedCommand {
  switch (action.type) {
    case 'Play': {
      const play = action as PlayAction;
      return {
        type: 'Play',
        assetId: play.assetId,
        bus: play.bus || defaultBus,
        gain: play.gain ?? 1.0,
        loop: play.loop ?? false,
      };
    }
    case 'SetBusGain': {
      const busGain = action as SetBusGainAction;
      return {
        type: 'SetBusGain',
        bus: busGain.bus,
        gain: busGain.gain,
      };
    }
    case 'StopAll':
      return { type: 'StopAll' };
    case 'Stop':
      return { type: 'Stop', voiceId: '' };
    default:
      return { type: 'StopAll' };
  }
}

/**
 * Convert NativeAdapterCommand to SimulatedCommand.
 */
function nativeCommandToSimulated(cmd: NativeAdapterCommand): SimulatedCommand {
  switch (cmd.type) {
    case 'Play':
      return {
        type: 'Play',
        assetId: cmd.assetId,
        bus: cmd.bus,
        gain: cmd.gain,
        loop: cmd.loop,
      };
    case 'Stop':
      return {
        type: 'Stop',
        voiceId: cmd.voiceId,
      };
    case 'StopAll':
      return { type: 'StopAll' };
    case 'SetBusGain':
      return {
        type: 'SetBusGain',
        bus: cmd.bus,
        gain: cmd.gain,
      };
    default:
      return { type: 'StopAll' };
  }
}

/**
 * Simulate event using routes config directly.
 */
function simulateFromRoutes(
  eventName: string,
  config: RoutesConfig
): SimulatedCommand[] | null {
  const route = config.events.find((e) => e.name === eventName);
  if (!route) {
    return null;
  }

  return route.actions.map((action) =>
    actionToSimulatedCommand(action, config.defaultBus)
  );
}

export default function RouteSimulationPanel({
  config,
  nativeCore,
  audioBackend,
  selectedEventName,
}: RouteSimulationPanelProps) {
  const [history, setHistory] = useState<SimulationEntry[]>([]);
  const [auditionEnabled, setAuditionEnabled] = useState(false);
  const nextIdRef = useRef(1);

  // Available events from config
  const eventNames = useMemo(
    () => config.events.map((e) => e.name),
    [config.events]
  );

  // Simulation mode
  const mode: 'native' | 'routes' = nativeCore ? 'native' : 'routes';

  /**
   * Simulate an event and optionally audition.
   */
  const simulateEvent = useCallback(
    (eventName: string) => {
      let commands: SimulatedCommand[];
      let simMode: 'native' | 'routes' = 'routes';

      if (nativeCore) {
        // Native mode: use submitEvent
        try {
          const nativeCommands = nativeCore.submitEvent({ name: eventName });
          if (nativeCommands) {
            commands = nativeCommands.map(nativeCommandToSimulated);
            simMode = 'native';
          } else {
            // Core returned null (disabled?), fallback to routes
            const routesCommands = simulateFromRoutes(eventName, config);
            if (!routesCommands) {
              return; // Unknown event
            }
            commands = routesCommands;
          }
        } catch {
          // Fallback to routes-only on error
          const routesCommands = simulateFromRoutes(eventName, config);
          if (!routesCommands) {
            return; // Unknown event
          }
          commands = routesCommands;
        }
      } else {
        // Routes-only mode
        const routesCommands = simulateFromRoutes(eventName, config);
        if (!routesCommands) {
          return; // Unknown event
        }
        commands = routesCommands;
      }

      // Create history entry
      const entry: SimulationEntry = {
        id: nextIdRef.current++,
        timestamp: Date.now(),
        eventName,
        commands,
        mode: simMode,
        auditioned: auditionEnabled && !!audioBackend,
      };

      // Add to history (ring buffer)
      setHistory((prev) => {
        const newHistory = [entry, ...prev];
        if (newHistory.length > HISTORY_CAPACITY) {
          newHistory.pop();
        }
        return newHistory;
      });

      // Audition if enabled
      if (auditionEnabled && audioBackend && nativeCore) {
        const nativeCommands = nativeCore.submitEvent({ name: eventName });
        if (nativeCommands) {
          for (const cmd of nativeCommands) {
            audioBackend.execute(cmd);
          }
        }
      }
    },
    [nativeCore, config, auditionEnabled, audioBackend]
  );

  /**
   * Clear simulation history.
   */
  const clearHistory = useCallback(() => {
    setHistory([]);
  }, []);

  /**
   * Format timestamp for display.
   */
  const formatTime = (ts: number): string => {
    const d = new Date(ts);
    return d.toLocaleTimeString('en-US', {
      hour12: false,
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  };

  return (
    <div className="rf-sim-panel">
      <div className="rf-sim-header">
        <div className="rf-sim-title">
          <span className="rf-sim-title-icon">🔬</span>
          <span>Route Simulation</span>
          <span className={`rf-sim-mode rf-sim-mode-${mode}`}>
            {mode === 'native' ? 'Native' : 'Routes-only'}
          </span>
        </div>

        <div className="rf-sim-controls">
          <label className="rf-sim-audition">
            <input
              type="checkbox"
              checked={auditionEnabled}
              onChange={(e) => setAuditionEnabled(e.target.checked)}
              disabled={!audioBackend || !nativeCore}
            />
            <span>Audition</span>
            {(!audioBackend || !nativeCore) && (
              <span className="rf-sim-audition-note">(requires native core)</span>
            )}
          </label>

          <button
            type="button"
            className="rf-sim-clear-btn"
            onClick={clearHistory}
            disabled={history.length === 0}
          >
            Clear
          </button>
        </div>
      </div>

      {/* Event Trigger Buttons */}
      <div className="rf-sim-events">
        <div className="rf-sim-events-header">
          Events ({eventNames.length})
        </div>
        <div className="rf-sim-events-grid">
          {eventNames.map((name) => (
            <button
              key={name}
              type="button"
              className={`rf-sim-event-btn ${name === selectedEventName ? 'is-selected' : ''}`}
              onClick={() => simulateEvent(name)}
              title={`Simulate ${name}`}
            >
              {name}
            </button>
          ))}
          {eventNames.length === 0 && (
            <div className="rf-sim-events-empty">No events defined</div>
          )}
        </div>
      </div>

      {/* Simulation History */}
      <div className="rf-sim-history">
        <div className="rf-sim-history-header">
          History ({history.length}/{HISTORY_CAPACITY})
        </div>
        <div className="rf-sim-history-list">
          {history.length === 0 && (
            <div className="rf-sim-history-empty">
              Click an event button to simulate
            </div>
          )}
          {history.map((entry) => (
            <div key={entry.id} className="rf-sim-entry">
              <div className="rf-sim-entry-header">
                <span className="rf-sim-entry-time">{formatTime(entry.timestamp)}</span>
                <span className="rf-sim-entry-event">{entry.eventName}</span>
                <span className={`rf-sim-entry-mode rf-sim-mode-${entry.mode}`}>
                  {entry.mode}
                </span>
                {entry.auditioned && (
                  <span className="rf-sim-entry-auditioned">🔊</span>
                )}
              </div>
              <div className="rf-sim-entry-commands">
                {entry.commands.map((cmd, idx) => (
                  <div key={idx} className="rf-sim-command">
                    <span className={`rf-sim-cmd-type rf-sim-cmd-${cmd.type.toLowerCase()}`}>
                      {cmd.type}
                    </span>
                    {cmd.type === 'Play' && (
                      <>
                        <span className="rf-sim-cmd-asset">{cmd.assetId}</span>
                        <span className="rf-sim-cmd-detail">
                          {cmd.bus} @ {(cmd.gain ?? 1).toFixed(2)}
                          {cmd.loop && ' 🔁'}
                        </span>
                      </>
                    )}
                    {cmd.type === 'SetBusGain' && (
                      <>
                        <span className="rf-sim-cmd-bus">{cmd.bus}</span>
                        <span className="rf-sim-cmd-gain">→ {(cmd.gain ?? 1).toFixed(2)}</span>
                      </>
                    )}
                    {cmd.type === 'Stop' && cmd.voiceId && (
                      <span className="rf-sim-cmd-voice">{cmd.voiceId}</span>
                    )}
                  </div>
                ))}
                {entry.commands.length === 0 && (
                  <div className="rf-sim-command rf-sim-no-commands">
                    No commands
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
