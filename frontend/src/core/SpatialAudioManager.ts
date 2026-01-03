/**
 * SpatialAudioManager - Integration of Spatial Audio with AudioContextManager
 *
 * Connects the ReelForge Spatial Audio system to the main audio engine.
 * Provides a unified API for spatial audio control.
 *
 * @module core/SpatialAudioManager
 */

import { AudioContextManager } from './AudioContextManager';
import {
  createSpatialEngine,
  createWebAudioAdapter,
  createDOMAdapter,
  type SpatialEngine,
  type SpatialEngineConfig,
  type RFSpatialEvent,
  type WebAudioAdapter,
  type DOMAdapter,
} from '../reelforge/spatial';

// ============ Types ============

export interface SpatialAudioManagerConfig {
  /** Enable spatial audio processing */
  enabled?: boolean;
  /** Predictive lead time in ms for latency compensation */
  predictiveLeadMs?: number;
  /** Enable debug overlay */
  debugOverlay?: boolean;
  /** Default bus for events without explicit bus */
  defaultBus?: string;
}

export interface SpatialVoice {
  /** Voice ID */
  id: string;
  /** Source audio node */
  sourceNode: AudioNode;
  /** Created panner/gain chain output */
  outputNode: AudioNode;
}

// ============ Manager Class ============

class SpatialAudioManagerClass {
  private engine: SpatialEngine | null = null;
  private audioAdapter: WebAudioAdapter | null = null;
  private domAdapter: DOMAdapter | null = null;
  private config: SpatialAudioManagerConfig = {
    enabled: true,
    predictiveLeadMs: 20,
    debugOverlay: false,
    defaultBus: 'FX',
  };
  private initialized = false;
  private voices = new Map<string, SpatialVoice>();

  /**
   * Initialize spatial audio system.
   * Call once after AudioContext is ready.
   */
  initialize(config?: Partial<SpatialAudioManagerConfig>): void {
    if (this.initialized) {
      console.warn('[SpatialAudioManager] Already initialized');
      return;
    }

    // Merge config
    this.config = { ...this.config, ...config };

    if (!this.config.enabled) {
      console.log('[SpatialAudioManager] Spatial audio disabled');
      return;
    }

    // Get AudioContext
    const ctx = AudioContextManager.getContext();

    // Create spatial engine
    const engineConfig: Partial<SpatialEngineConfig> = {
      predictiveLeadMs: this.config.predictiveLeadMs,
      debugOverlay: this.config.debugOverlay,
    };

    this.engine = createSpatialEngine(engineConfig);

    // Create and attach WebAudio adapter
    this.audioAdapter = createWebAudioAdapter(ctx, {
      rampTimeMs: 20,
      useChannelGains: true,
    });
    this.engine.setAudioAdapter(this.audioAdapter);

    // Create DOM adapter for anchor tracking
    this.domAdapter = createDOMAdapter();

    // Subscribe to AudioContext changes
    AudioContextManager.subscribe((newCtx) => {
      if (newCtx && this.engine) {
        // Recreate audio adapter with new context
        this.audioAdapter = createWebAudioAdapter(newCtx, {
          rampTimeMs: 20,
          useChannelGains: true,
        });
        this.engine.setAudioAdapter(this.audioAdapter);
      }
    });

    // Start engine
    this.engine.start();
    this.initialized = true;

    console.log('[SpatialAudioManager] Initialized with spatial audio enabled');
  }

  /**
   * Register a DOM element as a spatial anchor.
   */
  registerAnchor(id: string, element: HTMLElement): void {
    if (!this.domAdapter) return;
    this.domAdapter.registerAnchor(id, element);
  }

  /**
   * Unregister a spatial anchor.
   */
  unregisterAnchor(id: string): void {
    if (!this.domAdapter) return;
    this.domAdapter.unregisterAnchor(id);
  }

  /**
   * Create a spatialized voice with panning chain.
   */
  createVoice(
    voiceId: string,
    sourceNode: AudioNode,
    destinationNode?: AudioNode
  ): SpatialVoice | null {
    if (!this.audioAdapter) {
      // Fallback: direct connection if spatial disabled
      const dest = destinationNode ?? AudioContextManager.getContext().destination;
      sourceNode.connect(dest);
      return {
        id: voiceId,
        sourceNode,
        outputNode: sourceNode,
      };
    }

    // Create spatialized voice through adapter
    const voiceNodes = this.audioAdapter.createVoice(
      voiceId,
      sourceNode,
      destinationNode ?? AudioContextManager.getContext().destination
    );

    const voice: SpatialVoice = {
      id: voiceId,
      sourceNode,
      outputNode: voiceNodes.filterNode ?? voiceNodes.gainNode ?? sourceNode,
    };

    this.voices.set(voiceId, voice);
    return voice;
  }

  /**
   * Destroy a spatialized voice.
   */
  destroyVoice(voiceId: string): void {
    if (this.audioAdapter) {
      this.audioAdapter.destroyVoice(voiceId);
    }
    this.voices.delete(voiceId);
  }

  /**
   * Send a spatial event for tracking.
   */
  sendEvent(event: Omit<RFSpatialEvent, 'timeMs'> & { timeMs?: number }): void {
    if (!this.engine) return;

    const fullEvent: RFSpatialEvent = {
      ...event,
      timeMs: event.timeMs ?? performance.now(),
      bus: event.bus ?? (this.config.defaultBus as 'FX'),
    };

    this.engine.onEvent(fullEvent);
  }

  /**
   * Set pan directly for a voice (bypass event system).
   */
  setPan(voiceId: string, pan: number): void {
    if (!this.audioAdapter) return;
    this.audioAdapter.setPan(voiceId, pan);
  }

  /**
   * Set stereo width for a voice.
   */
  setWidth(voiceId: string, width: number): void {
    if (!this.audioAdapter) return;
    this.audioAdapter.setWidth(voiceId, width);
  }

  /**
   * Set LPF cutoff for a voice.
   */
  setLPF(voiceId: string, hz: number): void {
    if (!this.audioAdapter) return;
    this.audioAdapter.setLPF(voiceId, hz);
  }

  /**
   * Set gain for a voice.
   */
  setGain(voiceId: string, db: number): void {
    if (!this.audioAdapter) return;
    this.audioAdapter.setGain(voiceId, db);
  }

  /**
   * Stop the spatial engine.
   */
  stop(): void {
    if (this.engine) {
      this.engine.stop();
    }
  }

  /**
   * Resume the spatial engine.
   */
  resume(): void {
    if (this.engine) {
      this.engine.start();
    }
  }

  /**
   * Check if spatial audio is enabled and running.
   */
  isRunning(): boolean {
    return this.initialized && this.config.enabled === true;
  }

  /**
   * Dispose and clean up.
   */
  dispose(): void {
    if (this.engine) {
      this.engine.stop();
      this.engine = null;
    }

    if (this.audioAdapter) {
      this.audioAdapter.clear();
      this.audioAdapter = null;
    }

    this.domAdapter = null;
    this.voices.clear();
    this.initialized = false;
  }

  /**
   * Get the underlying SpatialEngine for advanced use.
   */
  getEngine(): SpatialEngine | null {
    return this.engine;
  }

  /**
   * Get the DOM adapter for anchor registration.
   */
  getDOMAdapter(): DOMAdapter | null {
    return this.domAdapter;
  }
}

// ============ Singleton Export ============

export const SpatialAudioManager = new SpatialAudioManagerClass();

// ============ Hook for React ============

import { useEffect, useCallback, useRef } from 'react';

/**
 * React hook for using spatial audio in components.
 */
export function useSpatialAudio() {
  const initialized = useRef(false);

  useEffect(() => {
    if (!initialized.current) {
      SpatialAudioManager.initialize();
      initialized.current = true;
    }

    return () => {
      // Don't dispose on unmount - let app handle lifecycle
    };
  }, []);

  const registerAnchor = useCallback((id: string, element: HTMLElement | null) => {
    if (element) {
      SpatialAudioManager.registerAnchor(id, element);
    } else {
      SpatialAudioManager.unregisterAnchor(id);
    }
  }, []);

  const sendEvent = useCallback((event: Omit<RFSpatialEvent, 'timeMs'>) => {
    SpatialAudioManager.sendEvent(event);
  }, []);

  const setPan = useCallback((voiceId: string, pan: number) => {
    SpatialAudioManager.setPan(voiceId, pan);
  }, []);

  return {
    registerAnchor,
    sendEvent,
    setPan,
    isRunning: SpatialAudioManager.isRunning(),
  };
}

/**
 * React hook to register an element as a spatial anchor.
 */
export function useSpatialAnchor(anchorId: string) {
  const refCallback = useCallback(
    (element: HTMLElement | null) => {
      if (element) {
        SpatialAudioManager.registerAnchor(anchorId, element);
      } else {
        SpatialAudioManager.unregisterAnchor(anchorId);
      }
    },
    [anchorId]
  );

  useEffect(() => {
    return () => {
      SpatialAudioManager.unregisterAnchor(anchorId);
    };
  }, [anchorId]);

  return refCallback;
}
