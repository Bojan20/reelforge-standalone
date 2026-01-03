/**
 * ReelForge M6.9 Asset Index
 *
 * Utility for manifest-driven asset lookup with search.
 * Provides debounced search and fast lookup by ID.
 */

/**
 * Asset metadata from runtime_manifest.json
 */
export interface AssetMeta {
  id: string;
  path?: string;
}

/**
 * Manifest file structure
 */
export interface RuntimeManifest {
  manifestVersion: string;
  assets: AssetMeta[];
}

/**
 * Asset index for fast lookup and search.
 *
 * Build once from manifest, use for:
 * - O(1) lookup by ID
 * - Case-insensitive search across id and path
 */
export class AssetIndex {
  private assets: AssetMeta[];
  private byId: Map<string, AssetMeta>;

  constructor(assets: AssetMeta[] = []) {
    this.assets = [...assets];
    this.byId = new Map(assets.map((a) => [a.id, a]));
  }

  /**
   * Create AssetIndex from manifest JSON.
   */
  static fromManifest(manifest: RuntimeManifest): AssetIndex {
    return new AssetIndex(manifest.assets);
  }

  /**
   * Create AssetIndex from raw JSON string.
   * @throws Error if JSON is invalid
   */
  static fromJson(json: string): AssetIndex {
    const manifest = JSON.parse(json) as RuntimeManifest;
    return AssetIndex.fromManifest(manifest);
  }

  /**
   * Get all assets.
   */
  getAll(): readonly AssetMeta[] {
    return this.assets;
  }

  /**
   * Get asset by ID.
   */
  get(id: string): AssetMeta | undefined {
    return this.byId.get(id);
  }

  /**
   * Check if asset exists.
   */
  has(id: string): boolean {
    return this.byId.has(id);
  }

  /**
   * Get asset count.
   */
  get count(): number {
    return this.assets.length;
  }

  /**
   * Get all asset IDs as a Set (for validation).
   */
  getIdSet(): Set<string> {
    return new Set(this.byId.keys());
  }

  /**
   * Search assets by query.
   *
   * Case-insensitive search across id and path.
   * Returns all matches if query is empty.
   *
   * @param query Search query
   * @param limit Maximum results (default: unlimited)
   */
  search(query: string, limit?: number): AssetMeta[] {
    return searchAssets(this.assets, query, limit);
  }
}

/**
 * Pure search function for unit testing.
 *
 * Case-insensitive search across id and path.
 * Returns all assets if query is empty.
 *
 * @param assets Asset array to search
 * @param query Search query
 * @param limit Maximum results (default: unlimited)
 */
export function searchAssets(
  assets: readonly AssetMeta[],
  query: string,
  limit?: number
): AssetMeta[] {
  const q = query.trim().toLowerCase();

  // Return all if empty query
  if (!q) {
    return limit !== undefined ? assets.slice(0, limit) : [...assets];
  }

  const results: AssetMeta[] = [];

  for (const asset of assets) {
    // Check id (always present)
    if (asset.id.toLowerCase().includes(q)) {
      results.push(asset);
      if (limit !== undefined && results.length >= limit) {
        break;
      }
      continue;
    }

    // Check path (optional)
    if (asset.path && asset.path.toLowerCase().includes(q)) {
      results.push(asset);
      if (limit !== undefined && results.length >= limit) {
        break;
      }
    }
  }

  return results;
}

/**
 * Create a debounced search function.
 *
 * @param index AssetIndex to search
 * @param delay Debounce delay in ms (default: 100)
 * @param limit Max results per search
 * @returns Debounced search function that returns a Promise
 */
export function createDebouncedSearch(
  index: AssetIndex,
  delay = 100,
  limit?: number
): (query: string) => Promise<AssetMeta[]> {
  let timeoutId: ReturnType<typeof setTimeout> | null = null;
  let currentResolve: ((results: AssetMeta[]) => void) | null = null;

  return (query: string): Promise<AssetMeta[]> => {
    // Cancel previous timeout
    if (timeoutId !== null) {
      clearTimeout(timeoutId);
    }

    // Resolve previous promise with empty if pending
    if (currentResolve) {
      currentResolve([]);
    }

    return new Promise((resolve) => {
      currentResolve = resolve;

      timeoutId = setTimeout(() => {
        timeoutId = null;
        currentResolve = null;
        resolve(index.search(query, limit));
      }, delay);
    });
  };
}

/**
 * Load manifest from fetch (browser context).
 *
 * @param url URL to runtime_manifest.json
 * @returns Promise resolving to AssetIndex
 * @throws Error if fetch or parse fails
 */
export async function loadAssetIndexFromUrl(url: string): Promise<AssetIndex> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch manifest: ${response.status} ${response.statusText}`);
  }
  const manifest = (await response.json()) as RuntimeManifest;
  return AssetIndex.fromManifest(manifest);
}
