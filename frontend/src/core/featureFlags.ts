/**
 * ReelForge Feature Flags
 *
 * Centralized feature flag system for gradual rollouts,
 * A/B testing, and development features.
 */

// ============ Types ============

export type FeatureFlagKey =
  // Audio features
  | 'audio.offlineRender'
  | 'audio.advancedDSP'
  | 'audio.spatialAudio'
  // UI features
  | 'ui.darkMode'
  | 'ui.compactView'
  | 'ui.advancedMixer'
  // Performance features
  | 'perf.webWorkers'
  | 'perf.wasmDSP'
  | 'perf.gpuAcceleration'
  // Development features
  | 'dev.debugOverlay'
  | 'dev.mockData'
  | 'dev.verboseLogging';

export interface FeatureFlag {
  key: FeatureFlagKey;
  enabled: boolean;
  description: string;
  /** Environment where flag is available */
  environment: 'all' | 'development' | 'production';
  /** Optional percentage for gradual rollout (0-100) */
  rolloutPercent?: number;
}

export interface FeatureFlagsConfig {
  flags: Record<FeatureFlagKey, FeatureFlag>;
  version: string;
}

// ============ Default Flags ============

const DEFAULT_FLAGS: Record<FeatureFlagKey, FeatureFlag> = {
  // Audio features
  'audio.offlineRender': {
    key: 'audio.offlineRender',
    enabled: true,
    description: 'Enable offline audio rendering for export',
    environment: 'all',
  },
  'audio.advancedDSP': {
    key: 'audio.advancedDSP',
    enabled: true,
    description: 'Advanced DSP processing (EQ, compression, etc.)',
    environment: 'all',
  },
  'audio.spatialAudio': {
    key: 'audio.spatialAudio',
    enabled: false,
    description: 'Experimental spatial audio support',
    environment: 'development',
  },

  // UI features
  'ui.darkMode': {
    key: 'ui.darkMode',
    enabled: true,
    description: 'Dark mode theme',
    environment: 'all',
  },
  'ui.compactView': {
    key: 'ui.compactView',
    enabled: false,
    description: 'Compact UI layout for smaller screens',
    environment: 'all',
  },
  'ui.advancedMixer': {
    key: 'ui.advancedMixer',
    enabled: true,
    description: 'Advanced mixer view with insert chains',
    environment: 'all',
  },

  // Performance features
  'perf.webWorkers': {
    key: 'perf.webWorkers',
    enabled: true,
    description: 'Use Web Workers for heavy processing',
    environment: 'all',
  },
  'perf.wasmDSP': {
    key: 'perf.wasmDSP',
    enabled: false,
    description: 'WebAssembly DSP processing',
    environment: 'development',
    rolloutPercent: 10,
  },
  'perf.gpuAcceleration': {
    key: 'perf.gpuAcceleration',
    enabled: false,
    description: 'GPU acceleration for visualizations',
    environment: 'development',
  },

  // Development features
  'dev.debugOverlay': {
    key: 'dev.debugOverlay',
    enabled: import.meta.env.DEV,
    description: 'Show debug overlay with performance stats',
    environment: 'development',
  },
  'dev.mockData': {
    key: 'dev.mockData',
    enabled: false,
    description: 'Use mock data instead of real API',
    environment: 'development',
  },
  'dev.verboseLogging': {
    key: 'dev.verboseLogging',
    enabled: import.meta.env.DEV,
    description: 'Enable verbose console logging',
    environment: 'development',
  },
};

// ============ Feature Flags Manager ============

class FeatureFlagsManager {
  private flags: Map<FeatureFlagKey, FeatureFlag> = new Map();
  private overrides: Map<FeatureFlagKey, boolean> = new Map();
  private listeners: Set<(key: FeatureFlagKey, enabled: boolean) => void> = new Set();
  private userId: string | null = null;

  constructor() {
    this.initializeFlags();
    this.loadOverrides();
  }

  private initializeFlags(): void {
    for (const [key, flag] of Object.entries(DEFAULT_FLAGS)) {
      this.flags.set(key as FeatureFlagKey, { ...flag });
    }
  }

  private loadOverrides(): void {
    try {
      const stored = localStorage.getItem('rf-feature-flags');
      if (stored) {
        const overrides = JSON.parse(stored) as Record<string, boolean>;
        for (const [key, value] of Object.entries(overrides)) {
          this.overrides.set(key as FeatureFlagKey, value);
        }
      }
    } catch {
      // Ignore localStorage errors
    }
  }

  private saveOverrides(): void {
    try {
      const overrides = Object.fromEntries(this.overrides);
      localStorage.setItem('rf-feature-flags', JSON.stringify(overrides));
    } catch {
      // Ignore localStorage errors
    }
  }

  // ============ Public API ============

  /**
   * Set user ID for consistent rollout hashing.
   */
  setUserId(userId: string): void {
    this.userId = userId;
  }

  /**
   * Check if a feature is enabled.
   */
  isEnabled(key: FeatureFlagKey): boolean {
    // Check overrides first
    if (this.overrides.has(key)) {
      return this.overrides.get(key)!;
    }

    const flag = this.flags.get(key);
    if (!flag) return false;

    // Check environment
    if (flag.environment === 'development' && !import.meta.env.DEV) {
      return false;
    }
    if (flag.environment === 'production' && import.meta.env.DEV) {
      return false;
    }

    // Check rollout percentage
    if (flag.rolloutPercent !== undefined && flag.rolloutPercent < 100) {
      return this.isInRollout(key, flag.rolloutPercent);
    }

    return flag.enabled;
  }

  /**
   * Deterministic rollout check based on user ID and flag key.
   */
  private isInRollout(key: FeatureFlagKey, percent: number): boolean {
    const seed = this.userId || 'anonymous';
    const hash = this.hashString(`${seed}:${key}`);
    const bucket = hash % 100;
    return bucket < percent;
  }

  /**
   * Simple string hash (FNV-1a).
   */
  private hashString(str: string): number {
    let hash = 2166136261;
    for (let i = 0; i < str.length; i++) {
      hash ^= str.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return Math.abs(hash);
  }

  /**
   * Get all flags.
   */
  getAllFlags(): FeatureFlag[] {
    return Array.from(this.flags.values()).map((flag) => ({
      ...flag,
      enabled: this.isEnabled(flag.key),
    }));
  }

  /**
   * Get flag info.
   */
  getFlag(key: FeatureFlagKey): FeatureFlag | undefined {
    const flag = this.flags.get(key);
    if (!flag) return undefined;
    return { ...flag, enabled: this.isEnabled(key) };
  }

  /**
   * Override a flag value (persisted to localStorage).
   */
  override(key: FeatureFlagKey, enabled: boolean): void {
    this.overrides.set(key, enabled);
    this.saveOverrides();
    this.notifyListeners(key, enabled);
  }

  /**
   * Clear override for a flag.
   */
  clearOverride(key: FeatureFlagKey): void {
    this.overrides.delete(key);
    this.saveOverrides();
    this.notifyListeners(key, this.isEnabled(key));
  }

  /**
   * Clear all overrides.
   */
  clearAllOverrides(): void {
    this.overrides.clear();
    this.saveOverrides();
  }

  /**
   * Subscribe to flag changes.
   */
  subscribe(listener: (key: FeatureFlagKey, enabled: boolean) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notifyListeners(key: FeatureFlagKey, enabled: boolean): void {
    this.listeners.forEach((listener) => listener(key, enabled));
  }

  /**
   * Export current config for debugging.
   */
  exportConfig(): FeatureFlagsConfig {
    const flags: Record<string, FeatureFlag> = {};
    for (const [key, flag] of this.flags) {
      flags[key] = { ...flag, enabled: this.isEnabled(key) };
    }
    return {
      flags: flags as Record<FeatureFlagKey, FeatureFlag>,
      version: '1.0.0',
    };
  }
}

// ============ Singleton Instance ============

export const featureFlags = new FeatureFlagsManager();

// ============ React Hook ============

import { useEffect, useState, useSyncExternalStore } from 'react';

/**
 * Hook to check if a feature is enabled.
 */
export function useFeatureFlag(key: FeatureFlagKey): boolean {
  return useSyncExternalStore(
    (onStoreChange) => featureFlags.subscribe((changedKey) => {
      if (changedKey === key) onStoreChange();
    }),
    () => featureFlags.isEnabled(key),
    () => featureFlags.isEnabled(key)
  );
}

/**
 * Hook to get all feature flags.
 */
export function useFeatureFlags(): FeatureFlag[] {
  const [flags, setFlags] = useState(() => featureFlags.getAllFlags());

  useEffect(() => {
    return featureFlags.subscribe(() => {
      setFlags(featureFlags.getAllFlags());
    });
  }, []);

  return flags;
}

// ============ Conditional Rendering Helper ============

interface FeatureProps {
  flag: FeatureFlagKey;
  children: React.ReactNode;
  fallback?: React.ReactNode;
}

/**
 * Component for conditional rendering based on feature flags.
 */
export function Feature({ flag, children, fallback = null }: FeatureProps): React.ReactNode {
  const enabled = useFeatureFlag(flag);
  return enabled ? children : fallback;
}

// ============ Development Tools ============

if (import.meta.env.DEV) {
  // Expose to window for debugging
  (window as unknown as { rfFeatureFlags: FeatureFlagsManager }).rfFeatureFlags = featureFlags;
}
