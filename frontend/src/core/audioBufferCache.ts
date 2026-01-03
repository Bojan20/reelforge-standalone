/**
 * AudioBuffer Cache System
 *
 * Optimizes audio playback by caching decoded AudioBuffers.
 * Prevents redundant fetch() and decodeAudioData() calls for the same audio file.
 *
 * Performance optimizations:
 * - O(1) LRU eviction using doubly-linked list
 * - Conditional debug logging via rfDebug
 */

import { rfDebug } from './dspMetrics';

interface CacheEntry {
  buffer: AudioBuffer;
  url: string;
  lastAccessed: number;
  accessCount: number;
  // Doubly-linked list for O(1) LRU
  prev: string | null;
  next: string | null;
}

export class AudioBufferCache {
  private cache: Map<string, CacheEntry> = new Map();
  private audioContext: AudioContext;
  private maxCacheSize: number;
  private maxAge: number; // milliseconds

  // LRU linked list pointers
  private lruHead: string | null = null; // Oldest (least recently used)
  private lruTail: string | null = null; // Newest (most recently used)

  constructor(
    audioContext: AudioContext,
    maxCacheSize: number = 100,
    maxAge: number = 30 * 60 * 1000 // 30 minutes
  ) {
    this.audioContext = audioContext;
    this.maxCacheSize = maxCacheSize;
    this.maxAge = maxAge;
  }

  /**
   * Get or load an AudioBuffer from cache
   */
  async getBuffer(soundId: string, url: string): Promise<AudioBuffer> {
    const cached = this.cache.get(soundId);

    // Return cached buffer if valid
    if (cached) {
      const age = Date.now() - cached.lastAccessed;

      if (age < this.maxAge) {
        cached.lastAccessed = Date.now();
        cached.accessCount++;
        // Move to tail (most recently used)
        this.moveToTail(soundId);
        rfDebug('AudioCache', `HIT ${soundId} (${cached.accessCount}x)`);
        return cached.buffer;
      } else {
        // Expired, remove from cache
        rfDebug('AudioCache', `EXPIRED ${soundId} (${Math.round(age / 1000)}s)`);
        this.removeFromLRU(soundId);
        this.cache.delete(soundId);
      }
    }

    // Cache miss - fetch and decode
    rfDebug('AudioCache', `MISS ${soundId}`);
    const buffer = await this.loadAndDecode(url);

    // Add to cache
    this.set(soundId, url, buffer);

    return buffer;
  }

  /**
   * Load and decode audio file
   */
  private async loadAndDecode(url: string): Promise<AudioBuffer> {
    const response = await fetch(url);
    const arrayBuffer = await response.arrayBuffer();
    return await this.audioContext.decodeAudioData(arrayBuffer);
  }

  /**
   * Add buffer to cache with O(1) eviction
   */
  private set(soundId: string, url: string, buffer: AudioBuffer): void {
    // Evict oldest entry if cache is full
    if (this.cache.size >= this.maxCacheSize) {
      this.evictLRU();
    }

    const entry: CacheEntry = {
      buffer,
      url,
      lastAccessed: Date.now(),
      accessCount: 1,
      prev: this.lruTail,
      next: null,
    };

    // Add to tail of LRU list
    if (this.lruTail) {
      const tailEntry = this.cache.get(this.lruTail);
      if (tailEntry) {
        tailEntry.next = soundId;
      }
    }
    this.lruTail = soundId;

    if (!this.lruHead) {
      this.lruHead = soundId;
    }

    this.cache.set(soundId, entry);
    rfDebug('AudioCache', `SET ${soundId} (${this.cache.size}/${this.maxCacheSize})`);
  }

  /**
   * Move entry to tail (most recently used) - O(1)
   */
  private moveToTail(soundId: string): void {
    if (this.lruTail === soundId) return; // Already at tail

    const entry = this.cache.get(soundId);
    if (!entry) return;

    // Remove from current position
    if (entry.prev) {
      const prevEntry = this.cache.get(entry.prev);
      if (prevEntry) prevEntry.next = entry.next;
    } else {
      // Was head
      this.lruHead = entry.next;
    }

    if (entry.next) {
      const nextEntry = this.cache.get(entry.next);
      if (nextEntry) nextEntry.prev = entry.prev;
    }

    // Add to tail
    entry.prev = this.lruTail;
    entry.next = null;

    if (this.lruTail) {
      const oldTail = this.cache.get(this.lruTail);
      if (oldTail) oldTail.next = soundId;
    }

    this.lruTail = soundId;
  }

  /**
   * Remove entry from LRU list - O(1)
   */
  private removeFromLRU(soundId: string): void {
    const entry = this.cache.get(soundId);
    if (!entry) return;

    if (entry.prev) {
      const prevEntry = this.cache.get(entry.prev);
      if (prevEntry) prevEntry.next = entry.next;
    } else {
      this.lruHead = entry.next;
    }

    if (entry.next) {
      const nextEntry = this.cache.get(entry.next);
      if (nextEntry) nextEntry.prev = entry.prev;
    } else {
      this.lruTail = entry.prev;
    }
  }

  /**
   * Evict least recently used entry - O(1)
   */
  private evictLRU(): void {
    if (!this.lruHead) return;

    const oldestKey = this.lruHead;
    rfDebug('AudioCache', `EVICT ${oldestKey}`);

    this.removeFromLRU(oldestKey);
    this.cache.delete(oldestKey);
  }

  /**
   * Check if buffer is cached
   */
  has(soundId: string): boolean {
    return this.cache.has(soundId);
  }

  /**
   * Clear entire cache
   */
  clear(): void {
    rfDebug('AudioCache', `CLEAR ${this.cache.size} entries`);
    this.cache.clear();
    this.lruHead = null;
    this.lruTail = null;
  }

  /**
   * Remove specific entry from cache
   */
  remove(soundId: string): boolean {
    if (this.cache.has(soundId)) {
      this.removeFromLRU(soundId);
      return this.cache.delete(soundId);
    }
    return false;
  }

  /**
   * Get cache statistics
   */
  getStats() {
    const entries = Array.from(this.cache.values());
    const totalAccesses = entries.reduce((sum, e) => sum + e.accessCount, 0);

    return {
      size: this.cache.size,
      maxSize: this.maxCacheSize,
      totalAccesses,
      entries: entries.map(e => ({
        lastAccessed: new Date(e.lastAccessed).toISOString(),
        accessCount: e.accessCount,
      })),
    };
  }

  /**
   * Preload multiple audio files into cache
   */
  async preload(files: Array<{ soundId: string; url: string }>): Promise<void> {
    rfDebug('AudioCache', `PRELOAD ${files.length} files`);

    const promises = files.map(({ soundId, url }) =>
      this.getBuffer(soundId, url).catch(err => {
        rfDebug('AudioCache', `PRELOAD FAILED ${soundId}:`, err);
        return null;
      })
    );

    await Promise.all(promises);
    rfDebug('AudioCache', `PRELOAD DONE (${this.cache.size} cached)`);
  }
}
