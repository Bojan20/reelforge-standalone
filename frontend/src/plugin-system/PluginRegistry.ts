/**
 * ReelForge Plugin Registry
 *
 * Central registry for all plugins - built-in and external.
 * Handles plugin discovery, loading, and lifecycle management.
 *
 * @module plugin-system/PluginRegistry
 */

// ============ Types ============

export type PluginCategory =
  | 'effect'
  | 'instrument'
  | 'analyzer'
  | 'utility'
  | 'dynamics'
  | 'eq'
  | 'delay'
  | 'reverb'
  | 'modulation'
  | 'distortion'
  | 'filter';

export type PluginFormat = 'builtin' | 'webaudio' | 'audioworklet' | 'wasm';

export interface PluginParameter {
  id: string;
  name: string;
  type: 'float' | 'int' | 'bool' | 'choice';
  defaultValue: number;
  minValue?: number;
  maxValue?: number;
  step?: number;
  choices?: string[];
  unit?: string;
  automatable?: boolean;
}

export interface PluginDescriptor {
  id: string;
  name: string;
  vendor: string;
  version: string;
  category: PluginCategory;
  subcategory?: string;
  format: PluginFormat;
  description?: string;
  tags?: string[];

  // Audio configuration
  numInputs: number;
  numOutputs: number;
  supportsDouble?: boolean;
  latencySamples?: number;
  tailSamples?: number;

  // Parameters
  parameters: PluginParameter[];

  // UI
  hasCustomUI?: boolean;
  uiWidth?: number;
  uiHeight?: number;

  // Factory function
  factory?: () => Promise<PluginInstance>;
}

export interface PluginInstance {
  id: string;
  descriptorId: string;

  // Lifecycle
  initialize(sampleRate: number, blockSize: number): Promise<void>;
  dispose(): void;
  reset(): void;

  // Processing
  process(inputs: Float32Array[][], outputs: Float32Array[][]): void;

  // Parameters
  getParameter(id: string): number;
  setParameter(id: string, value: number): void;
  getParameterNormalized(id: string): number;
  setParameterNormalized(id: string, value: number): void;

  // State
  getState(): PluginState;
  setState(state: PluginState): void;

  // UI
  openUI?(): void;
  closeUI?(): void;
  isUIOpen?(): boolean;
}

export interface PluginState {
  descriptorId: string;
  version: string;
  parameters: Record<string, number>;
  customData?: unknown;
}

export interface PluginScanResult {
  found: number;
  loaded: number;
  failed: string[];
  scanTime: number;
}

// ============ Plugin Registry ============

class PluginRegistryImpl {
  private descriptors = new Map<string, PluginDescriptor>();
  private instances = new Map<string, PluginInstance>();
  private categoryIndex = new Map<PluginCategory, Set<string>>();
  private listeners = new Set<(event: PluginRegistryEvent) => void>();

  constructor() {
    // Initialize category index
    const categories: PluginCategory[] = [
      'effect', 'instrument', 'analyzer', 'utility',
      'dynamics', 'eq', 'delay', 'reverb', 'modulation', 'distortion', 'filter'
    ];
    for (const cat of categories) {
      this.categoryIndex.set(cat, new Set());
    }
  }

  // ============ Registration ============

  /**
   * Register a plugin descriptor.
   */
  register(descriptor: PluginDescriptor): void {
    if (this.descriptors.has(descriptor.id)) {
      console.warn(`Plugin ${descriptor.id} already registered, replacing`);
    }

    this.descriptors.set(descriptor.id, descriptor);
    this.categoryIndex.get(descriptor.category)?.add(descriptor.id);

    this.emit({ type: 'registered', pluginId: descriptor.id });
  }

  /**
   * Unregister a plugin.
   */
  unregister(pluginId: string): boolean {
    const descriptor = this.descriptors.get(pluginId);
    if (!descriptor) return false;

    // Remove from category index
    this.categoryIndex.get(descriptor.category)?.delete(pluginId);

    // Dispose all instances
    for (const [instanceId, instance] of this.instances) {
      if (instance.descriptorId === pluginId) {
        instance.dispose();
        this.instances.delete(instanceId);
      }
    }

    this.descriptors.delete(pluginId);
    this.emit({ type: 'unregistered', pluginId });

    return true;
  }

  // ============ Discovery ============

  /**
   * Get all registered plugins.
   */
  getAll(): PluginDescriptor[] {
    return Array.from(this.descriptors.values());
  }

  /**
   * Get plugin by ID.
   */
  get(pluginId: string): PluginDescriptor | undefined {
    return this.descriptors.get(pluginId);
  }

  /**
   * Get plugins by category.
   */
  getByCategory(category: PluginCategory): PluginDescriptor[] {
    const ids = this.categoryIndex.get(category);
    if (!ids) return [];

    return Array.from(ids)
      .map(id => this.descriptors.get(id))
      .filter((d): d is PluginDescriptor => d !== undefined);
  }

  /**
   * Search plugins.
   */
  search(query: string): PluginDescriptor[] {
    const lower = query.toLowerCase();

    return this.getAll().filter(d =>
      d.name.toLowerCase().includes(lower) ||
      d.vendor.toLowerCase().includes(lower) ||
      d.tags?.some(t => t.toLowerCase().includes(lower)) ||
      d.description?.toLowerCase().includes(lower)
    );
  }

  /**
   * Get plugins by format.
   */
  getByFormat(format: PluginFormat): PluginDescriptor[] {
    return this.getAll().filter(d => d.format === format);
  }

  // ============ Instance Management ============

  /**
   * Create plugin instance.
   */
  async createInstance(
    pluginId: string,
    instanceId?: string
  ): Promise<PluginInstance | undefined> {
    const descriptor = this.descriptors.get(pluginId);
    if (!descriptor) {
      console.error(`Plugin ${pluginId} not found`);
      return undefined;
    }

    if (!descriptor.factory) {
      console.error(`Plugin ${pluginId} has no factory`);
      return undefined;
    }

    const instance = await descriptor.factory();
    const id = instanceId ?? `${pluginId}_${Date.now()}`;

    // Set instance ID
    (instance as { id: string }).id = id;
    (instance as { descriptorId: string }).descriptorId = pluginId;

    this.instances.set(id, instance);
    this.emit({ type: 'instanceCreated', pluginId, instanceId: id });

    return instance;
  }

  /**
   * Get plugin instance.
   */
  getInstance(instanceId: string): PluginInstance | undefined {
    return this.instances.get(instanceId);
  }

  /**
   * Dispose plugin instance.
   */
  disposeInstance(instanceId: string): boolean {
    const instance = this.instances.get(instanceId);
    if (!instance) return false;

    instance.dispose();
    this.instances.delete(instanceId);
    this.emit({ type: 'instanceDisposed', pluginId: instance.descriptorId, instanceId });

    return true;
  }

  /**
   * Get all instances of a plugin.
   */
  getInstances(pluginId: string): PluginInstance[] {
    return Array.from(this.instances.values())
      .filter(i => i.descriptorId === pluginId);
  }

  // ============ Events ============

  /**
   * Subscribe to registry events.
   */
  subscribe(callback: (event: PluginRegistryEvent) => void): () => void {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  private emit(event: PluginRegistryEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }

  // ============ Utilities ============

  /**
   * Get statistics.
   */
  getStats(): {
    totalPlugins: number;
    byCategory: Record<string, number>;
    byFormat: Record<string, number>;
    totalInstances: number;
  } {
    const byCategory: Record<string, number> = {};
    const byFormat: Record<string, number> = {};

    for (const descriptor of this.descriptors.values()) {
      byCategory[descriptor.category] = (byCategory[descriptor.category] || 0) + 1;
      byFormat[descriptor.format] = (byFormat[descriptor.format] || 0) + 1;
    }

    return {
      totalPlugins: this.descriptors.size,
      byCategory,
      byFormat,
      totalInstances: this.instances.size,
    };
  }

  /**
   * Clear all plugins and instances.
   */
  clear(): void {
    // Dispose all instances
    for (const instance of this.instances.values()) {
      instance.dispose();
    }
    this.instances.clear();

    // Clear descriptors
    this.descriptors.clear();

    // Clear category index
    for (const set of this.categoryIndex.values()) {
      set.clear();
    }

    this.emit({ type: 'cleared' });
  }
}

// ============ Event Types ============

export type PluginRegistryEvent =
  | { type: 'registered'; pluginId: string }
  | { type: 'unregistered'; pluginId: string }
  | { type: 'instanceCreated'; pluginId: string; instanceId: string }
  | { type: 'instanceDisposed'; pluginId: string; instanceId: string }
  | { type: 'cleared' };

// ============ Singleton Instance ============

export const PluginRegistry = new PluginRegistryImpl();

// ============ Helper Functions ============

/**
 * Get category display name.
 */
export function getCategoryDisplayName(category: PluginCategory): string {
  const names: Record<PluginCategory, string> = {
    effect: 'Effects',
    instrument: 'Instruments',
    analyzer: 'Analyzers',
    utility: 'Utilities',
    dynamics: 'Dynamics',
    eq: 'EQ',
    delay: 'Delay',
    reverb: 'Reverb',
    modulation: 'Modulation',
    distortion: 'Distortion',
    filter: 'Filter',
  };
  return names[category];
}

/**
 * Get all categories.
 */
export function getAllCategories(): PluginCategory[] {
  return [
    'effect', 'instrument', 'analyzer', 'utility',
    'dynamics', 'eq', 'delay', 'reverb', 'modulation', 'distortion', 'filter'
  ];
}

/**
 * Validate plugin descriptor.
 */
export function validateDescriptor(descriptor: Partial<PluginDescriptor>): string[] {
  const errors: string[] = [];

  if (!descriptor.id) errors.push('Missing id');
  if (!descriptor.name) errors.push('Missing name');
  if (!descriptor.vendor) errors.push('Missing vendor');
  if (!descriptor.version) errors.push('Missing version');
  if (!descriptor.category) errors.push('Missing category');
  if (!descriptor.format) errors.push('Missing format');
  if (descriptor.numInputs === undefined) errors.push('Missing numInputs');
  if (descriptor.numOutputs === undefined) errors.push('Missing numOutputs');
  if (!descriptor.parameters) errors.push('Missing parameters');

  return errors;
}
