/**
 * Soundbank Management System
 *
 * Professional soundbank system for managing audio assets:
 * - Memory budget management
 * - Load priority (startup, level, on-demand)
 * - Streaming policy per bank
 * - Batch loading/unloading
 * - Memory tracking and alerts
 * - Bank dependencies
 */

// ============ TYPES ============

export type LoadPriority = 'startup' | 'level' | 'on-demand';
export type StreamingPolicy = 'full' | 'prefetch' | 'stream';
export type BankStatus = 'unloaded' | 'loading' | 'loaded' | 'error';

export interface SoundbankAsset {
  /** Asset ID */
  id: string;
  /** File path or URL */
  path: string;
  /** Estimated size in bytes */
  sizeBytes: number;
  /** Streaming policy override (inherits from bank if not set) */
  streamingPolicy?: StreamingPolicy;
  /** Decoded AudioBuffer (when loaded) */
  buffer?: AudioBuffer;
}

export interface Soundbank {
  /** Unique bank ID */
  id: string;
  /** Display name */
  name: string;
  /** Description */
  description?: string;
  /** Assets in this bank */
  assets: SoundbankAsset[];
  /** Memory budget in bytes (0 = unlimited) */
  memoryBudget: number;
  /** Load priority */
  loadPriority: LoadPriority;
  /** Default streaming policy for assets */
  streamingPolicy: StreamingPolicy;
  /** Bank dependencies (must be loaded first) */
  dependencies?: string[];
  /** Tags for organization */
  tags?: string[];
  /** Bank version */
  version?: string;
}

export interface BankLoadProgress {
  bankId: string;
  status: BankStatus;
  loaded: number;
  total: number;
  percentage: number;
  error?: string;
}

export interface MemoryUsage {
  /** Total loaded memory */
  loaded: number;
  /** Memory currently streaming */
  streaming: number;
  /** Peak memory usage */
  peak: number;
  /** Per-bank breakdown */
  perBank: Map<string, number>;
  /** Budget status */
  withinBudget: boolean;
  /** Total budget */
  totalBudget: number;
}

export interface SoundbankManagerConfig {
  /** Global memory budget in bytes */
  globalMemoryBudget: number;
  /** Auto-unload banks when over budget */
  autoUnloadOnOverBudget: boolean;
  /** Prefetch size in bytes for streaming */
  prefetchSize: number;
  /** Maximum concurrent loads */
  maxConcurrentLoads: number;
  /** Enable memory alerts */
  enableMemoryAlerts: boolean;
  /** Memory alert threshold (0-1) */
  memoryAlertThreshold: number;
}

// ============ DEFAULT CONFIG ============

const DEFAULT_CONFIG: SoundbankManagerConfig = {
  globalMemoryBudget: 100 * 1024 * 1024, // 100MB
  autoUnloadOnOverBudget: false,
  prefetchSize: 256 * 1024, // 256KB
  maxConcurrentLoads: 4,
  enableMemoryAlerts: true,
  memoryAlertThreshold: 0.9,
};

// ============ SOUNDBANK MANAGER ============

export class SoundbankManager {
  private banks: Map<string, Soundbank> = new Map();
  private bankStatus: Map<string, BankStatus> = new Map();
  private loadedMemory: Map<string, number> = new Map();
  private peakMemory: number = 0;
  private config: SoundbankManagerConfig;
  private ctx: AudioContext;

  // Callbacks
  private onProgress?: (progress: BankLoadProgress) => void;
  private onMemoryAlert?: (usage: MemoryUsage) => void;
  private onBankLoaded?: (bankId: string) => void;
  private onBankUnloaded?: (bankId: string) => void;
  private onError?: (bankId: string, error: Error) => void;

  constructor(
    ctx: AudioContext,
    config: Partial<SoundbankManagerConfig> = {},
    callbacks?: {
      onProgress?: (progress: BankLoadProgress) => void;
      onMemoryAlert?: (usage: MemoryUsage) => void;
      onBankLoaded?: (bankId: string) => void;
      onBankUnloaded?: (bankId: string) => void;
      onError?: (bankId: string, error: Error) => void;
    }
  ) {
    this.ctx = ctx;
    this.config = { ...DEFAULT_CONFIG, ...config };
    this.onProgress = callbacks?.onProgress;
    this.onMemoryAlert = callbacks?.onMemoryAlert;
    this.onBankLoaded = callbacks?.onBankLoaded;
    this.onBankUnloaded = callbacks?.onBankUnloaded;
    this.onError = callbacks?.onError;
  }

  // ============ BANK REGISTRATION ============

  /**
   * Register a soundbank
   */
  registerBank(bank: Soundbank): void {
    this.banks.set(bank.id, bank);
    this.bankStatus.set(bank.id, 'unloaded');
    this.loadedMemory.set(bank.id, 0);
  }

  /**
   * Register multiple banks
   */
  registerBanks(banks: Soundbank[]): void {
    banks.forEach(bank => this.registerBank(bank));
  }

  /**
   * Unregister a soundbank
   */
  unregisterBank(bankId: string): void {
    if (this.bankStatus.get(bankId) === 'loaded') {
      this.unloadBank(bankId);
    }
    this.banks.delete(bankId);
    this.bankStatus.delete(bankId);
    this.loadedMemory.delete(bankId);
  }

  /**
   * Get bank by ID
   */
  getBank(bankId: string): Soundbank | undefined {
    return this.banks.get(bankId);
  }

  /**
   * Get all registered banks
   */
  getAllBanks(): Soundbank[] {
    return Array.from(this.banks.values());
  }

  // ============ LOADING ============

  /**
   * Load a soundbank
   */
  async loadBank(bankId: string): Promise<void> {
    const bank = this.banks.get(bankId);
    if (!bank) {
      throw new Error(`Bank not found: ${bankId}`);
    }

    const status = this.bankStatus.get(bankId);
    if (status === 'loaded') return;
    if (status === 'loading') return;

    // Check dependencies
    if (bank.dependencies) {
      for (const depId of bank.dependencies) {
        const depStatus = this.bankStatus.get(depId);
        if (depStatus !== 'loaded') {
          await this.loadBank(depId);
        }
      }
    }

    // Check memory budget
    const estimatedSize = bank.assets.reduce((sum, a) => sum + a.sizeBytes, 0);
    const currentUsage = this.getTotalLoadedMemory();

    if (this.config.globalMemoryBudget > 0 &&
        currentUsage + estimatedSize > this.config.globalMemoryBudget) {
      if (this.config.autoUnloadOnOverBudget) {
        await this.freeMemory(estimatedSize);
      } else {
        throw new Error(`Memory budget exceeded. Need ${estimatedSize} bytes, have ${this.config.globalMemoryBudget - currentUsage} available.`);
      }
    }

    // Start loading
    this.bankStatus.set(bankId, 'loading');
    this.reportProgress(bankId, 0, bank.assets.length);

    try {
      let loaded = 0;
      const batchSize = this.config.maxConcurrentLoads;

      // Load assets in batches
      for (let i = 0; i < bank.assets.length; i += batchSize) {
        const batch = bank.assets.slice(i, i + batchSize);
        await Promise.all(batch.map(async (asset) => {
          await this.loadAsset(asset, bank.streamingPolicy);
          loaded++;
          this.reportProgress(bankId, loaded, bank.assets.length);
        }));
      }

      // Calculate loaded memory
      const loadedBytes = bank.assets.reduce((sum, a) => {
        if (a.buffer) {
          return sum + (a.buffer.length * a.buffer.numberOfChannels * 4); // Float32
        }
        return sum;
      }, 0);

      this.loadedMemory.set(bankId, loadedBytes);
      this.bankStatus.set(bankId, 'loaded');
      this.updatePeakMemory();
      this.checkMemoryAlert();
      this.onBankLoaded?.(bankId);

    } catch (error) {
      this.bankStatus.set(bankId, 'error');
      this.onError?.(bankId, error as Error);
      throw error;
    }
  }

  /**
   * Load a single asset
   */
  private async loadAsset(asset: SoundbankAsset, defaultPolicy: StreamingPolicy): Promise<void> {
    const policy = asset.streamingPolicy ?? defaultPolicy;

    // For 'stream' policy, we don't load the full buffer
    if (policy === 'stream') {
      // Just validate the asset exists, actual streaming handled elsewhere
      return;
    }

    // For 'prefetch', load only the beginning
    if (policy === 'prefetch') {
      // Load prefetch chunk (handled by streaming system)
      return;
    }

    // For 'full', load entire asset
    try {
      const response = await fetch(asset.path);
      if (!response.ok) {
        throw new Error(`Failed to fetch: ${asset.path}`);
      }
      const arrayBuffer = await response.arrayBuffer();
      const audioBuffer = await this.ctx.decodeAudioData(arrayBuffer);
      asset.buffer = audioBuffer;
    } catch (error) {
      console.error(`Failed to load asset ${asset.id}:`, error);
      throw error;
    }
  }

  /**
   * Unload a soundbank
   */
  unloadBank(bankId: string): void {
    const bank = this.banks.get(bankId);
    if (!bank) return;

    const status = this.bankStatus.get(bankId);
    if (status !== 'loaded') return;

    // Clear asset buffers
    bank.assets.forEach(asset => {
      asset.buffer = undefined;
    });

    this.loadedMemory.set(bankId, 0);
    this.bankStatus.set(bankId, 'unloaded');
    this.onBankUnloaded?.(bankId);
  }

  /**
   * Load all startup banks
   */
  async loadStartupBanks(): Promise<void> {
    const startupBanks = Array.from(this.banks.values())
      .filter(b => b.loadPriority === 'startup');

    for (const bank of startupBanks) {
      await this.loadBank(bank.id);
    }
  }

  /**
   * Load banks by tag
   */
  async loadBanksByTag(tag: string): Promise<void> {
    const taggedBanks = Array.from(this.banks.values())
      .filter(b => b.tags?.includes(tag));

    for (const bank of taggedBanks) {
      await this.loadBank(bank.id);
    }
  }

  // ============ MEMORY MANAGEMENT ============

  /**
   * Get bank status
   */
  getBankStatus(bankId: string): BankStatus {
    return this.bankStatus.get(bankId) ?? 'unloaded';
  }

  /**
   * Get total loaded memory
   */
  getTotalLoadedMemory(): number {
    let total = 0;
    this.loadedMemory.forEach(mem => total += mem);
    return total;
  }

  /**
   * Get memory usage statistics
   */
  getMemoryUsage(): MemoryUsage {
    const loaded = this.getTotalLoadedMemory();
    return {
      loaded,
      streaming: 0, // TODO: Integrate with streaming system
      peak: this.peakMemory,
      perBank: new Map(this.loadedMemory),
      withinBudget: this.config.globalMemoryBudget === 0 ||
                    loaded <= this.config.globalMemoryBudget,
      totalBudget: this.config.globalMemoryBudget,
    };
  }

  /**
   * Set global memory budget
   */
  setMemoryBudget(bytes: number): void {
    this.config.globalMemoryBudget = bytes;
  }

  /**
   * Free memory by unloading banks
   */
  private async freeMemory(needed: number): Promise<void> {
    const currentUsage = this.getTotalLoadedMemory();
    const target = this.config.globalMemoryBudget - needed;

    if (currentUsage <= target) return;

    // Get loaded banks sorted by priority (unload on-demand first, then level)
    const loadedBanks = Array.from(this.banks.entries())
      .filter(([id]) => this.bankStatus.get(id) === 'loaded')
      .map(([id, bank]) => ({ id, bank, memory: this.loadedMemory.get(id) ?? 0 }))
      .sort((a, b) => {
        const priorityOrder = { 'on-demand': 0, 'level': 1, 'startup': 2 };
        return priorityOrder[a.bank.loadPriority] - priorityOrder[b.bank.loadPriority];
      });

    let freed = 0;
    for (const { id, memory } of loadedBanks) {
      if (currentUsage - freed <= target) break;
      this.unloadBank(id);
      freed += memory;
    }
  }

  /**
   * Update peak memory
   */
  private updatePeakMemory(): void {
    const current = this.getTotalLoadedMemory();
    if (current > this.peakMemory) {
      this.peakMemory = current;
    }
  }

  /**
   * Check and trigger memory alert
   */
  private checkMemoryAlert(): void {
    if (!this.config.enableMemoryAlerts) return;
    if (this.config.globalMemoryBudget === 0) return;

    const usage = this.getMemoryUsage();
    const ratio = usage.loaded / usage.totalBudget;

    if (ratio >= this.config.memoryAlertThreshold) {
      this.onMemoryAlert?.(usage);
    }
  }

  // ============ ASSET ACCESS ============

  /**
   * Get audio buffer for an asset
   */
  getBuffer(assetId: string): AudioBuffer | undefined {
    for (const bank of this.banks.values()) {
      const asset = bank.assets.find(a => a.id === assetId);
      if (asset?.buffer) {
        return asset.buffer;
      }
    }
    return undefined;
  }

  /**
   * Check if asset is loaded
   */
  isAssetLoaded(assetId: string): boolean {
    return this.getBuffer(assetId) !== undefined;
  }

  /**
   * Get bank containing an asset
   */
  getBankForAsset(assetId: string): Soundbank | undefined {
    for (const bank of this.banks.values()) {
      if (bank.assets.some(a => a.id === assetId)) {
        return bank;
      }
    }
    return undefined;
  }

  /**
   * Ensure asset is loaded (load bank if needed)
   */
  async ensureAssetLoaded(assetId: string): Promise<AudioBuffer> {
    const existing = this.getBuffer(assetId);
    if (existing) return existing;

    const bank = this.getBankForAsset(assetId);
    if (!bank) {
      throw new Error(`Asset not found in any bank: ${assetId}`);
    }

    await this.loadBank(bank.id);

    const buffer = this.getBuffer(assetId);
    if (!buffer) {
      throw new Error(`Asset still not loaded after bank load: ${assetId}`);
    }
    return buffer;
  }

  // ============ PROGRESS REPORTING ============

  private reportProgress(bankId: string, loaded: number, total: number): void {
    this.onProgress?.({
      bankId,
      status: this.bankStatus.get(bankId) ?? 'unloaded',
      loaded,
      total,
      percentage: total > 0 ? (loaded / total) * 100 : 0,
    });
  }

  // ============ SERIALIZATION ============

  /**
   * Export bank definitions (without buffers)
   */
  exportBankDefinitions(): string {
    const banks = Array.from(this.banks.values()).map(bank => ({
      ...bank,
      assets: bank.assets.map(a => ({
        id: a.id,
        path: a.path,
        sizeBytes: a.sizeBytes,
        streamingPolicy: a.streamingPolicy,
      })),
    }));
    return JSON.stringify(banks, null, 2);
  }

  /**
   * Import bank definitions
   */
  importBankDefinitions(json: string): void {
    const banks = JSON.parse(json) as Soundbank[];
    banks.forEach(bank => this.registerBank(bank));
  }

  // ============ DISPOSAL ============

  /**
   * Dispose manager
   */
  dispose(): void {
    // Unload all banks
    this.banks.forEach((_, id) => this.unloadBank(id));
    this.banks.clear();
    this.bankStatus.clear();
    this.loadedMemory.clear();
  }
}

// ============ PRESET SOUNDBANKS ============

export const PRESET_SOUNDBANKS: Record<string, Omit<Soundbank, 'assets'>> = {
  core: {
    id: 'core',
    name: 'Core Sounds',
    description: 'Essential UI and system sounds',
    memoryBudget: 5 * 1024 * 1024, // 5MB
    loadPriority: 'startup',
    streamingPolicy: 'full',
    tags: ['system', 'ui'],
  },
  music: {
    id: 'music',
    name: 'Music',
    description: 'Background music tracks',
    memoryBudget: 50 * 1024 * 1024, // 50MB
    loadPriority: 'startup',
    streamingPolicy: 'stream',
    tags: ['music'],
  },
  sfx_base: {
    id: 'sfx_base',
    name: 'Base SFX',
    description: 'Common game sound effects',
    memoryBudget: 10 * 1024 * 1024, // 10MB
    loadPriority: 'level',
    streamingPolicy: 'full',
    tags: ['sfx', 'game'],
  },
  sfx_wins: {
    id: 'sfx_wins',
    name: 'Win SFX',
    description: 'Win celebration sounds',
    memoryBudget: 20 * 1024 * 1024, // 20MB
    loadPriority: 'level',
    streamingPolicy: 'full',
    tags: ['sfx', 'wins'],
  },
  sfx_bonus: {
    id: 'sfx_bonus',
    name: 'Bonus SFX',
    description: 'Bonus feature sounds',
    memoryBudget: 15 * 1024 * 1024, // 15MB
    loadPriority: 'on-demand',
    streamingPolicy: 'prefetch',
    dependencies: ['sfx_base'],
    tags: ['sfx', 'bonus'],
  },
  ambience: {
    id: 'ambience',
    name: 'Ambience',
    description: 'Background ambience loops',
    memoryBudget: 10 * 1024 * 1024, // 10MB
    loadPriority: 'level',
    streamingPolicy: 'stream',
    tags: ['ambience'],
  },
  voice: {
    id: 'voice',
    name: 'Voice',
    description: 'Voiceover and announcements',
    memoryBudget: 30 * 1024 * 1024, // 30MB
    loadPriority: 'on-demand',
    streamingPolicy: 'prefetch',
    tags: ['voice', 'announcements'],
  },
  jackpot: {
    id: 'jackpot',
    name: 'Jackpot',
    description: 'Jackpot celebration sounds',
    memoryBudget: 25 * 1024 * 1024, // 25MB
    loadPriority: 'on-demand',
    streamingPolicy: 'full',
    dependencies: ['sfx_wins'],
    tags: ['sfx', 'jackpot', 'celebration'],
  },
};
