/**
 * useRuntimeCore Hook
 *
 * Manages RuntimeStub and Native RuntimeCore lifecycle.
 * Extracted from EventsPage to reduce component complexity.
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import {
  RuntimeStub,
  AudioEngineBackend,
  type LatencyStats,
  type AssetResolver,
  type AdapterCommand,
  type BusId as BackendBusId,
} from '../runtimeStub';
import {
  NativeRuntimeCoreWrapper,
  isNativeRuntimeCoreAvailable,
  getNativeLoadError,
  type NativeAdapterCommand,
} from '../core/nativeRuntimeCore';
import type { RoutesConfig } from '../core/routesTypes';
import type { AudioEngine } from '../core/audioEngine';
import type { AudioFileObject } from '../core/types';

export interface NativeLatencySplit {
  coreMs: number;
  execMs: number;
  totalMs: number;
  count: number;
}

export interface UseRuntimeCoreOptions {
  audioEngine: AudioEngine;
  audioFiles: AudioFileObject[];
}

export interface UseRuntimeCoreReturn {
  // RuntimeStub
  runtimeStubRef: React.MutableRefObject<RuntimeStub | null>;
  audioBackendRef: React.MutableRefObject<AudioEngineBackend | null>;
  latencyStats: LatencyStats | null;
  perEventStats: Record<string, LatencyStats>;
  setLatencyStats: React.Dispatch<React.SetStateAction<LatencyStats | null>>;
  setPerEventStats: React.Dispatch<React.SetStateAction<Record<string, LatencyStats>>>;

  // Native RuntimeCore
  nativeCoreRef: React.MutableRefObject<NativeRuntimeCoreWrapper | null>;
  useNativeCore: boolean;
  setUseNativeCore: React.Dispatch<React.SetStateAction<boolean>>;
  nativeCoreAvailable: boolean;
  nativeCoreError: string | null;
  setNativeCoreError: React.Dispatch<React.SetStateAction<string | null>>;
  nativeLatencySplit: NativeLatencySplit | null;
  setNativeLatencySplit: React.Dispatch<React.SetStateAction<NativeLatencySplit | null>>;

  // Throttle ref for latency updates
  latencyUpdateThrottleRef: React.MutableRefObject<{
    lastUpdate: number;
    pending: boolean;
    rafId: number | null;
  }>;

  // Actions
  handleToggleNativeCore: (enabled: boolean) => void;
  handleReloadCore: (config: RoutesConfig) => Promise<boolean>;
  handleClearStats: () => void;
  handleDeterminismCheck: () => Promise<{ passed: boolean; details: string }>;
  convertNativeCommands: (nativeCommands: NativeAdapterCommand[]) => AdapterCommand[];
}

// Latency update interval exported for consumers
export const LATENCY_UPDATE_INTERVAL_MS = 67; // ~15Hz

export function useRuntimeCore({
  audioEngine,
  audioFiles,
}: UseRuntimeCoreOptions): UseRuntimeCoreReturn {
  // RuntimeStub state
  const [latencyStats, setLatencyStats] = useState<LatencyStats | null>(null);
  const [perEventStats, setPerEventStats] = useState<Record<string, LatencyStats>>({});
  const runtimeStubRef = useRef<RuntimeStub | null>(null);

  // Native RuntimeCore state
  const [useNativeCore, setUseNativeCore] = useState(false);
  const [nativeCoreAvailable, setNativeCoreAvailable] = useState(false);
  const [nativeCoreError, setNativeCoreError] = useState<string | null>(null);
  const nativeCoreRef = useRef<NativeRuntimeCoreWrapper | null>(null);
  const audioBackendRef = useRef<AudioEngineBackend | null>(null);

  // Native core split latency metrics
  const [nativeLatencySplit, setNativeLatencySplit] = useState<NativeLatencySplit | null>(null);

  // Throttle latency UI updates
  const latencyUpdateThrottleRef = useRef<{
    lastUpdate: number;
    pending: boolean;
    rafId: number | null;
  }>({ lastUpdate: 0, pending: false, rafId: null });

  // Initialize RuntimeStub with AudioEngineBackend
  useEffect(() => {
    const assetResolver: AssetResolver = {
      resolveUrl: (assetId: string) => {
        const audioFile = audioFiles.find(
          (f) => f.name === assetId || f.name.replace(/\.[^/.]+$/, '') === assetId
        );
        if (audioFile) {
          return URL.createObjectURL(audioFile.file);
        }
        return undefined;
      },
    };

    const backend = new AudioEngineBackend(audioEngine, assetResolver, true);
    const stub = new RuntimeStub(backend, {
      logLatency: true,
      logCommands: false,
      seqDedupeSize: 128,
    });

    runtimeStubRef.current = stub;
    audioBackendRef.current = backend;

    return () => {
      runtimeStubRef.current = null;
      audioBackendRef.current = null;
    };
  }, [audioEngine, audioFiles]);

  // Initialize Native RuntimeCore
  useEffect(() => {
    const available = isNativeRuntimeCoreAvailable();
    setNativeCoreAvailable(available);

    if (!available) {
      const error = getNativeLoadError();
      setNativeCoreError(error?.message || null);
    } else {
      const manifestPath = 'public/demo/runtime_manifest.json';
      const routesPath = 'runtime_core/tests/fixtures/runtime_routes.json';
      nativeCoreRef.current = new NativeRuntimeCoreWrapper(manifestPath, 1, routesPath);
      console.log('[NativeRuntimeCore] Wrapper created, ready for activation');
    }

    return () => {
      nativeCoreRef.current?.disable();
      nativeCoreRef.current = null;
    };
  }, []);

  // Toggle native core
  const handleToggleNativeCore = useCallback((enabled: boolean) => {
    if (!nativeCoreRef.current) {
      console.warn('[NativeRuntimeCore] No wrapper available');
      return;
    }

    if (enabled) {
      const success = nativeCoreRef.current.enable();
      if (success) {
        setUseNativeCore(true);
        console.log('[NativeRuntimeCore] Enabled');
      } else {
        setNativeCoreError('Failed to enable native core');
      }
    } else {
      nativeCoreRef.current.disable();
      setUseNativeCore(false);
      console.log('[NativeRuntimeCore] Disabled');
    }
  }, []);

  // Hot-reload routes
  const handleReloadCore = useCallback(async (config: RoutesConfig): Promise<boolean> => {
    if (!nativeCoreRef.current) {
      console.warn('[NativeRuntimeCore] RELOAD_FAILED: No wrapper available');
      return false;
    }

    if (!nativeCoreRef.current.isEnabled()) {
      console.warn('[NativeRuntimeCore] RELOAD_SKIPPED: Core not enabled');
      return false;
    }

    try {
      console.log('[NativeRuntimeCore] RELOAD_START');
      const routesJson = JSON.stringify(config, null, 2);
      nativeCoreRef.current.reloadRoutesFromString(routesJson);

      const routesInfo = nativeCoreRef.current.getRoutesInfo();
      console.log(
        `[NativeRuntimeCore] RELOAD_SUCCESS: Routes v${routesInfo?.version ?? 0}, ` +
          `${routesInfo?.eventCount ?? 0} events`
      );
      return true;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`[NativeRuntimeCore] RELOAD_FAILED: ${msg}`);
      return false;
    }
  }, []);

  // Clear stats
  const handleClearStats = useCallback(() => {
    runtimeStubRef.current?.clearStats();
    setLatencyStats(null);
    setPerEventStats({});
    setNativeLatencySplit(null);
  }, []);

  // Determinism check
  const handleDeterminismCheck = useCallback(async (): Promise<{
    passed: boolean;
    details: string;
  }> => {
    const nativeCore = nativeCoreRef.current;
    if (!nativeCore) {
      return { passed: false, details: 'Native core not available' };
    }

    const testEvents = [
      'onBaseGameSpin', 'onReelStop', 'onReelStop', 'onReelStop', 'onWinSmall',
      'onButtonClick', 'onButtonHover', 'onBaseGameSpin', 'onReelStop', 'onWinMedium',
      'onBaseGameSpin', 'onReelStop', 'onReelStop', 'onReelStop', 'onWinBig',
      'onWinEnd', 'onButtonClick', 'onBaseGameSpin', 'onReelStop', 'onReelStop',
      'onBonusEnter', 'onBaseGameSpin', 'onReelStop', 'onWinSmall', 'onBonusExit',
      'onBaseGameSpin', 'onReelStop', 'onReelStop', 'onReelStop', 'onWinMedium',
      'onButtonHover', 'onButtonClick', 'onBaseGameSpin', 'onReelStop', 'onReelStop',
      'onWinSmall', 'onStopAll', 'onBaseGameSpin', 'onReelStop', 'onWinBig',
      'onWinEnd', 'onBaseGameSpin', 'onReelStop', 'onReelStop', 'onReelStop',
      'onButtonClick', 'onWinSmall', 'onWinMedium', 'onWinEnd', 'onStopAll',
    ];

    const stringify = (cmds: NativeAdapterCommand[] | null) => JSON.stringify(cmds);

    try {
      // First run
      nativeCore.reset({ seed: 12345 });
      const run1Results: string[] = [];
      for (const eventName of testEvents) {
        const cmds = nativeCore.submitEvent({ name: eventName });
        run1Results.push(stringify(cmds));
      }

      // Second run (same seed)
      nativeCore.reset({ seed: 12345 });
      const run2Results: string[] = [];
      for (const eventName of testEvents) {
        const cmds = nativeCore.submitEvent({ name: eventName });
        run2Results.push(stringify(cmds));
      }

      // Compare
      let mismatches = 0;
      for (let i = 0; i < testEvents.length; i++) {
        if (run1Results[i] !== run2Results[i]) {
          mismatches++;
        }
      }

      if (mismatches === 0) {
        return { passed: true, details: `${testEvents.length} events matched` };
      } else {
        return { passed: false, details: `${mismatches}/${testEvents.length} mismatched` };
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      return { passed: false, details: `Error: ${msg}` };
    }
  }, []);

  // Convert native commands to adapter commands
  const convertNativeCommands = useCallback(
    (nativeCommands: NativeAdapterCommand[]): AdapterCommand[] => {
      return nativeCommands.map((cmd): AdapterCommand => {
        switch (cmd.type) {
          case 'Play':
            return {
              type: 'Play',
              assetId: cmd.assetId,
              bus: cmd.bus as BackendBusId,
              gain: cmd.gain,
              loop: cmd.loop,
              startTimeMs: cmd.startTimeMs,
            };
          case 'Stop':
            return { type: 'Stop', voiceId: cmd.voiceId };
          case 'StopAll':
            return { type: 'StopAll' };
          case 'SetBusGain':
            return {
              type: 'SetBusGain',
              bus: cmd.bus as BackendBusId,
              gain: cmd.gain,
            };
        }
      });
    },
    []
  );

  return {
    // RuntimeStub
    runtimeStubRef,
    audioBackendRef,
    latencyStats,
    perEventStats,
    setLatencyStats,
    setPerEventStats,

    // Native RuntimeCore
    nativeCoreRef,
    useNativeCore,
    setUseNativeCore,
    nativeCoreAvailable,
    nativeCoreError,
    setNativeCoreError,
    nativeLatencySplit,
    setNativeLatencySplit,

    // Throttle ref
    latencyUpdateThrottleRef,

    // Actions
    handleToggleNativeCore,
    handleReloadCore,
    handleClearStats,
    handleDeterminismCheck,
    convertNativeCommands,
  };
}
