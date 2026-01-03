/**
 * AudioContextManager - Singleton for AudioContext lifecycle
 *
 * Ensures only ONE AudioContext exists per application.
 * Handles suspension, resume, and cleanup.
 */

interface AudioContextManagerState {
  context: AudioContext | null;
  isResuming: boolean;
  resumePromise: Promise<void> | null;
}

class AudioContextManagerClass {
  private state: AudioContextManagerState = {
    context: null,
    isResuming: false,
    resumePromise: null,
  };

  private listeners: Set<(ctx: AudioContext | null) => void> = new Set();

  /**
   * Get or create the shared AudioContext.
   * Creates lazily on first access.
   * @throws Error if AudioContext is not available in this environment
   */
  getContext(): AudioContext {
    if (!this.state.context || this.state.context.state === 'closed') {
      // Check for AudioContext availability
      const AudioContextClass = window.AudioContext ||
        (window as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;

      if (!AudioContextClass) {
        throw new Error('AudioContext is not supported in this browser');
      }

      try {
        this.state.context = new AudioContextClass();
      } catch (error) {
        // AudioContext creation can fail due to:
        // - Too many AudioContexts (browser limit)
        // - System audio unavailable
        // - Permissions denied
        const message = error instanceof Error ? error.message : 'Unknown error';
        throw new Error(`Failed to create AudioContext: ${message}`);
      }

      // Notify listeners
      this.listeners.forEach(fn => fn(this.state.context));
    }
    return this.state.context;
  }

  /**
   * Try to get or create context, returning null on failure.
   * Use this when AudioContext is optional.
   */
  tryGetContext(): AudioContext | null {
    try {
      return this.getContext();
    } catch {
      return null;
    }
  }

  /**
   * Check if context exists without creating one.
   */
  hasContext(): boolean {
    return this.state.context !== null && this.state.context.state !== 'closed';
  }

  /**
   * Check if AudioContext is supported in this environment.
   */
  isSupported(): boolean {
    return typeof window !== 'undefined' &&
      (typeof window.AudioContext !== 'undefined' ||
        typeof (window as { webkitAudioContext?: unknown }).webkitAudioContext !== 'undefined');
  }

  /**
   * Get context state safely.
   */
  getState(): AudioContext['state'] | null {
    return this.state.context?.state ?? null;
  }

  /**
   * Resume context if suspended (requires user gesture).
   * Creates context if it doesn't exist yet.
   * Returns immediately if already running.
   */
  async resume(): Promise<void> {
    // Ensure context exists before trying to resume
    const ctx = this.getContext();

    if (ctx.state === 'running') return;
    if (ctx.state === 'closed') {
      throw new Error('Cannot resume closed AudioContext');
    }

    // Debounce multiple resume calls
    if (this.state.isResuming && this.state.resumePromise) {
      return this.state.resumePromise;
    }

    this.state.isResuming = true;
    this.state.resumePromise = ctx.resume().finally(() => {
      this.state.isResuming = false;
      this.state.resumePromise = null;
    });

    return this.state.resumePromise;
  }

  /**
   * Suspend context to save resources.
   */
  async suspend(): Promise<void> {
    const ctx = this.state.context;
    if (!ctx || ctx.state !== 'running') return;
    await ctx.suspend();
  }

  /**
   * Close and dispose the context.
   * Call on app unmount or page unload.
   */
  async dispose(): Promise<void> {
    const ctx = this.state.context;
    if (!ctx) return;

    if (ctx.state !== 'closed') {
      try {
        await ctx.close();
      } catch {
        // Already closed or error - ignore
      }
    }

    this.state.context = null;
    this.listeners.forEach(fn => fn(null));
  }

  /**
   * Subscribe to context changes (creation, disposal).
   */
  subscribe(listener: (ctx: AudioContext | null) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /**
   * Get sample rate (or default).
   */
  getSampleRate(): number {
    return this.state.context?.sampleRate ?? 44100;
  }

  /**
   * Get current time from context.
   */
  getCurrentTime(): number {
    return this.state.context?.currentTime ?? 0;
  }

  /**
   * Create a gain node from shared context.
   */
  createGain(): GainNode {
    return this.getContext().createGain();
  }

  /**
   * Decode audio data using shared context.
   */
  async decodeAudioData(arrayBuffer: ArrayBuffer): Promise<AudioBuffer> {
    return this.getContext().decodeAudioData(arrayBuffer);
  }
}

// Singleton instance
export const AudioContextManager = new AudioContextManagerClass();

// Setup cleanup on page unload
if (typeof window !== 'undefined') {
  window.addEventListener('beforeunload', () => {
    AudioContextManager.dispose();
  });

  // Also handle visibility change for mobile
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      AudioContextManager.suspend();
    } else {
      // Resume when tab becomes visible again
      AudioContextManager.resume().catch(() => {
        // Resume may require user gesture - that's OK
      });
    }
  });
}

// Legacy compatibility - direct context access
export function getSharedAudioContext(): AudioContext {
  return AudioContextManager.getContext();
}

export function ensureAudioContextResumed(): Promise<void> {
  return AudioContextManager.resume();
}
