/**
 * ReelForge M9.2 Worklet Host Utility
 *
 * Manages AudioWorklet module loading with caching per AudioContext.
 * Ensures each worklet module is only loaded once per context.
 *
 * @module plugin/workletHost
 */

/**
 * Cache of loaded modules per AudioContext.
 * Uses WeakMap so contexts can be garbage collected.
 */
const moduleCache = new WeakMap<AudioContext, Map<string, Promise<void>>>();

/**
 * Ensure a worklet module is loaded for the given AudioContext.
 * Uses internal caching to prevent duplicate addModule calls.
 *
 * @param ctx - The AudioContext to load the module into
 * @param moduleUrl - URL of the worklet module (use `new URL('./...', import.meta.url).href`)
 * @returns Promise that resolves when module is ready
 * @throws Error if module fails to load
 */
export async function ensureModuleLoaded(
  ctx: AudioContext,
  moduleUrl: string
): Promise<void> {
  // Get or create the context's module cache
  let contextCache = moduleCache.get(ctx);
  if (!contextCache) {
    contextCache = new Map();
    moduleCache.set(ctx, contextCache);
  }

  // Check if already loading/loaded
  const existing = contextCache.get(moduleUrl);
  if (existing) {
    return existing;
  }

  // Start loading
  const loadPromise = ctx.audioWorklet.addModule(moduleUrl).catch((err) => {
    // Remove from cache on failure so retry is possible
    contextCache?.delete(moduleUrl);
    throw new Error(`Failed to load worklet module "${moduleUrl}": ${err.message}`);
  });

  contextCache.set(moduleUrl, loadPromise);
  return loadPromise;
}

/**
 * Create an AudioWorkletNode after ensuring the module is loaded.
 *
 * @param ctx - The AudioContext
 * @param moduleUrl - URL of the worklet module
 * @param processorName - Name of the registered processor
 * @param options - Optional AudioWorkletNodeOptions
 * @returns The created AudioWorkletNode
 */
export async function createWorkletNode(
  ctx: AudioContext,
  moduleUrl: string,
  processorName: string,
  options?: AudioWorkletNodeOptions
): Promise<AudioWorkletNode> {
  await ensureModuleLoaded(ctx, moduleUrl);
  return new AudioWorkletNode(ctx, processorName, options);
}

/**
 * Check if a module is already loaded for a context.
 * Useful for testing and diagnostics.
 *
 * @param ctx - The AudioContext
 * @param moduleUrl - URL of the worklet module
 * @returns True if module is loaded or loading
 */
export function isModuleLoaded(ctx: AudioContext, moduleUrl: string): boolean {
  const contextCache = moduleCache.get(ctx);
  return contextCache?.has(moduleUrl) ?? false;
}

/**
 * Get the number of loaded modules for a context.
 * Useful for testing.
 *
 * @param ctx - The AudioContext
 * @returns Number of loaded modules
 */
export function getLoadedModuleCount(ctx: AudioContext): number {
  const contextCache = moduleCache.get(ctx);
  return contextCache?.size ?? 0;
}
