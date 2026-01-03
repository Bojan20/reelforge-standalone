/**
 * useMixerDSP - Bridge between UI mixer state and real DSP processing
 *
 * This hook connects the visual mixer UI to the actual audio processing system.
 * It manages insert chains, DSP instance creation, and parameter updates.
 *
 * @module hooks/useMixerDSP
 */

import { useState, useCallback, useMemo, useRef, useEffect } from 'react';
import { getPluginDefinition, getAllPluginDefinitions } from '../plugin/pluginRegistry';
import { getSharedAudioContext, ensureAudioContextResumed } from '../core/AudioContextManager';
import type { PluginDSPInstance, PluginDefinition } from '../plugin/PluginDefinition';
import { rfDebug } from '../core/dspMetrics';

// ============ Types ============

export interface MixerInsert {
  id: string;
  pluginId: string;
  name: string;
  bypassed: boolean;
  params: Record<string, number>;
}

export interface MixerBus {
  id: string;
  name: string;
  volume: number;
  pan: number;
  muted: boolean;
  solo: boolean;
  inserts: MixerInsert[];
}

interface ActiveDSPInstance {
  insertId: string;
  busId: string;
  dsp: PluginDSPInstance;
  pluginDef: PluginDefinition;
  inputNode: GainNode;
  outputNode: GainNode;
}

// ============ Default Buses ============

const DEFAULT_BUSES: MixerBus[] = [
  { id: 'master', name: 'Master', volume: 0.85, pan: 0, muted: false, solo: false, inserts: [] },
  { id: 'music', name: 'Music', volume: 0.7, pan: 0, muted: false, solo: false, inserts: [] },
  { id: 'sfx', name: 'SFX', volume: 0.9, pan: 0, muted: false, solo: false, inserts: [] },
  { id: 'ambience', name: 'Ambience', volume: 0.5, pan: 0, muted: false, solo: false, inserts: [] },
  { id: 'voice', name: 'Voice', volume: 0.95, pan: 0, muted: false, solo: false, inserts: [] },
];

// ============ Hook ============

export interface UseMixerDSPOptions {
  /** Initial buses */
  initialBuses?: MixerBus[];
  /** Auto-connect to AudioContext on mount */
  autoConnect?: boolean;
}

export function useMixerDSP(options: UseMixerDSPOptions = {}) {
  const { initialBuses = DEFAULT_BUSES, autoConnect = true } = options;

  // State
  const [buses, setBuses] = useState<MixerBus[]>(initialBuses);
  const [isConnected, setIsConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Refs for DSP instances
  const dspInstancesRef = useRef<Map<string, ActiveDSPInstance>>(new Map());
  const busGainsRef = useRef<Map<string, GainNode>>(new Map());
  const masterGainRef = useRef<GainNode | null>(null);
  const ctxRef = useRef<AudioContext | null>(null);

  // Generate unique insert ID
  const generateInsertId = useCallback(() => {
    return `insert_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
  }, []);

  // Connect to AudioContext
  const connect = useCallback(async () => {
    try {
      await ensureAudioContextResumed();
      const ctx = getSharedAudioContext();
      ctxRef.current = ctx;

      // Create master gain
      const masterGain = ctx.createGain();
      masterGain.gain.value = 0.85;
      masterGain.connect(ctx.destination);
      masterGainRef.current = masterGain;

      // Create bus gains
      for (const bus of buses) {
        const busGain = ctx.createGain();
        busGain.gain.value = bus.muted ? 0 : bus.volume;

        if (bus.id === 'master') {
          // Master bus output is already masterGain
          busGainsRef.current.set(bus.id, masterGain);
        } else {
          busGain.connect(masterGain);
          busGainsRef.current.set(bus.id, busGain);
        }
      }

      setIsConnected(true);
      setError(null);
      rfDebug('MixerDSP', 'Connected to AudioContext');
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to connect';
      setError(msg);
      rfDebug('MixerDSP', 'Connection error:', err);
    }
  }, [buses]);

  // Disconnect and cleanup
  const disconnect = useCallback(() => {
    // Dispose all DSP instances
    dspInstancesRef.current.forEach((instance) => {
      try {
        instance.dsp.disconnect();
        instance.dsp.dispose();
        instance.inputNode.disconnect();
        instance.outputNode.disconnect();
      } catch {
        // Ignore cleanup errors
      }
    });
    dspInstancesRef.current.clear();

    // Disconnect bus gains
    busGainsRef.current.forEach((gain) => {
      try {
        gain.disconnect();
      } catch {
        // Ignore
      }
    });
    busGainsRef.current.clear();

    // Disconnect master
    if (masterGainRef.current) {
      try {
        masterGainRef.current.disconnect();
      } catch {
        // Ignore
      }
      masterGainRef.current = null;
    }

    ctxRef.current = null;
    setIsConnected(false);
    rfDebug('MixerDSP', 'Disconnected');
  }, []);

  // Auto-connect on mount
  useEffect(() => {
    if (autoConnect) {
      connect();
    }
    return () => {
      disconnect();
    };
  }, [autoConnect, connect, disconnect]);

  // Add insert to bus
  const addInsert = useCallback((busId: string, pluginId: string): string | null => {
    const pluginDef = getPluginDefinition(pluginId);
    if (!pluginDef) {
      rfDebug('MixerDSP', `Plugin not found: ${pluginId}`);
      return null;
    }

    const insertId = generateInsertId();

    // Get default params from plugin definition
    const defaultParams: Record<string, number> = {};
    for (const param of pluginDef.params) {
      defaultParams[param.id] = param.default;
    }

    const newInsert: MixerInsert = {
      id: insertId,
      pluginId,
      name: pluginDef.displayName,
      bypassed: false,
      params: defaultParams,
    };

    // Create DSP instance if connected
    if (ctxRef.current && isConnected) {
      try {
        const ctx = ctxRef.current;
        const dsp = pluginDef.createDSP(ctx);

        // Create input/output wrappers
        const inputNode = ctx.createGain();
        const outputNode = ctx.createGain();

        // Wire: inputNode -> dsp.input ... dsp.output -> outputNode
        inputNode.connect(dsp.getInputNode());
        dsp.connect(outputNode);

        // Apply initial params
        dsp.applyParams(defaultParams);

        // Store instance
        dspInstancesRef.current.set(insertId, {
          insertId,
          busId,
          dsp,
          pluginDef,
          inputNode,
          outputNode,
        });

        rfDebug('MixerDSP', `Created DSP instance for ${pluginDef.displayName}`);
      } catch (err) {
        rfDebug('MixerDSP', `Failed to create DSP for ${pluginId}:`, err);
      }
    }

    // Update UI state
    setBuses((prev) =>
      prev.map((bus) =>
        bus.id === busId
          ? { ...bus, inserts: [...bus.inserts, newInsert] }
          : bus
      )
    );

    return insertId;
  }, [isConnected, generateInsertId]);

  // Remove insert from bus
  const removeInsert = useCallback((busId: string, insertId: string) => {
    // Dispose DSP instance
    const instance = dspInstancesRef.current.get(insertId);
    if (instance) {
      try {
        instance.dsp.disconnect();
        instance.dsp.dispose();
        instance.inputNode.disconnect();
        instance.outputNode.disconnect();
      } catch {
        // Ignore cleanup errors
      }
      dspInstancesRef.current.delete(insertId);
      rfDebug('MixerDSP', `Removed DSP instance ${insertId}`);
    }

    // Update UI state
    setBuses((prev) =>
      prev.map((bus) =>
        bus.id === busId
          ? { ...bus, inserts: bus.inserts.filter((i) => i.id !== insertId) }
          : bus
      )
    );
  }, []);

  // Toggle insert bypass
  const toggleBypass = useCallback((busId: string, insertId: string) => {
    const instance = dspInstancesRef.current.get(insertId);

    setBuses((prev) =>
      prev.map((bus) => {
        if (bus.id !== busId) return bus;
        return {
          ...bus,
          inserts: bus.inserts.map((insert) => {
            if (insert.id !== insertId) return insert;
            const newBypassed = !insert.bypassed;

            // Update DSP bypass
            if (instance && instance.dsp.setBypass) {
              instance.dsp.setBypass(newBypassed);
            }

            return { ...insert, bypassed: newBypassed };
          }),
        };
      })
    );
  }, []);

  // Update insert params
  const updateInsertParams = useCallback(
    (busId: string, insertId: string, params: Record<string, number>) => {
      const instance = dspInstancesRef.current.get(insertId);

      // Update DSP params
      if (instance) {
        instance.dsp.applyParams(params);
      }

      // Update UI state
      setBuses((prev) =>
        prev.map((bus) => {
          if (bus.id !== busId) return bus;
          return {
            ...bus,
            inserts: bus.inserts.map((insert) =>
              insert.id === insertId
                ? { ...insert, params: { ...insert.params, ...params } }
                : insert
            ),
          };
        })
      );
    },
    []
  );

  // Update bus volume
  const setBusVolume = useCallback((busId: string, volume: number) => {
    const busGain = busGainsRef.current.get(busId);
    if (busGain && ctxRef.current) {
      const now = ctxRef.current.currentTime;
      busGain.gain.cancelScheduledValues(now);
      busGain.gain.setValueAtTime(busGain.gain.value, now);
      busGain.gain.linearRampToValueAtTime(volume, now + 0.01);
    }

    setBuses((prev) =>
      prev.map((bus) => (bus.id === busId ? { ...bus, volume } : bus))
    );
  }, []);

  // Toggle bus mute
  const toggleMute = useCallback((busId: string) => {
    setBuses((prev) =>
      prev.map((bus) => {
        if (bus.id !== busId) return bus;
        const newMuted = !bus.muted;

        const busGain = busGainsRef.current.get(busId);
        if (busGain && ctxRef.current) {
          const now = ctxRef.current.currentTime;
          busGain.gain.cancelScheduledValues(now);
          busGain.gain.setValueAtTime(busGain.gain.value, now);
          busGain.gain.linearRampToValueAtTime(newMuted ? 0 : bus.volume, now + 0.01);
        }

        return { ...bus, muted: newMuted };
      })
    );
  }, []);

  // Get available plugins for picker
  const availablePlugins = useMemo(() => {
    return getAllPluginDefinitions().map((def) => ({
      id: def.id,
      name: def.displayName,
      category: def.category,
      icon: def.icon ?? '🔌',
      description: def.description,
    }));
  }, []);

  // Get insert DSP instance (for advanced use)
  const getInsertDSP = useCallback((insertId: string): PluginDSPInstance | null => {
    return dspInstancesRef.current.get(insertId)?.dsp ?? null;
  }, []);

  return {
    // State
    buses,
    isConnected,
    error,
    availablePlugins,

    // Connection
    connect,
    disconnect,

    // Bus operations
    setBusVolume,
    toggleMute,

    // Insert operations
    addInsert,
    removeInsert,
    toggleBypass,
    updateInsertParams,
    getInsertDSP,

    // Setters for UI state
    setBuses,
  };
}

export type MixerDSPReturn = ReturnType<typeof useMixerDSP>;
