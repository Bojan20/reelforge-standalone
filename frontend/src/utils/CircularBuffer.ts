/**
 * CircularBuffer - O(1) Queue Operations
 *
 * Fixed-size ring buffer for high-performance queue operations.
 * Replaces Array.shift() (O(n)) with O(1) operations.
 *
 * Use cases:
 * - Event history/logging
 * - Audio sample buffers
 * - Statistics collection
 * - Frame timing history
 *
 * @example
 * const buffer = new CircularBuffer<number>(100);
 * buffer.push(42);
 * const oldest = buffer.shift(); // O(1)!
 * const newest = buffer.peek();
 */

export class CircularBuffer<T> {
  private buffer: (T | undefined)[];
  private head: number = 0; // Read pointer (oldest item)
  private tail: number = 0; // Write pointer (next write position)
  private count: number = 0;
  private readonly capacity: number;

  /**
   * Create a circular buffer with fixed capacity.
   * @param capacity Maximum number of items (must be > 0)
   */
  constructor(capacity: number) {
    if (capacity <= 0) {
      throw new Error('CircularBuffer capacity must be > 0');
    }
    this.capacity = capacity;
    this.buffer = new Array(capacity);
  }

  /**
   * Add item to end of buffer - O(1)
   * If buffer is full, overwrites oldest item.
   */
  push(item: T): void {
    this.buffer[this.tail] = item;
    this.tail = (this.tail + 1) % this.capacity;

    if (this.count < this.capacity) {
      this.count++;
    } else {
      // Buffer was full, oldest item overwritten
      this.head = (this.head + 1) % this.capacity;
    }
  }

  /**
   * Remove and return oldest item - O(1)
   * @returns Oldest item or undefined if empty
   */
  shift(): T | undefined {
    if (this.count === 0) {
      return undefined;
    }

    const item = this.buffer[this.head];
    this.buffer[this.head] = undefined; // Allow GC
    this.head = (this.head + 1) % this.capacity;
    this.count--;

    return item;
  }

  /**
   * Return oldest item without removing - O(1)
   */
  peekFirst(): T | undefined {
    if (this.count === 0) return undefined;
    return this.buffer[this.head];
  }

  /**
   * Return newest item without removing - O(1)
   */
  peekLast(): T | undefined {
    if (this.count === 0) return undefined;
    const lastIndex = (this.tail - 1 + this.capacity) % this.capacity;
    return this.buffer[lastIndex];
  }

  /**
   * Alias for peekLast for compatibility
   */
  peek(): T | undefined {
    return this.peekLast();
  }

  /**
   * Get item at index (0 = oldest) - O(1)
   */
  at(index: number): T | undefined {
    if (index < 0 || index >= this.count) {
      return undefined;
    }
    const actualIndex = (this.head + index) % this.capacity;
    return this.buffer[actualIndex];
  }

  /**
   * Current number of items
   */
  get length(): number {
    return this.count;
  }

  /**
   * Maximum capacity
   */
  get size(): number {
    return this.capacity;
  }

  /**
   * Check if buffer is empty
   */
  isEmpty(): boolean {
    return this.count === 0;
  }

  /**
   * Check if buffer is full
   */
  isFull(): boolean {
    return this.count === this.capacity;
  }

  /**
   * Clear all items - O(1)
   */
  clear(): void {
    // Just reset pointers (items will be overwritten or GC'd)
    this.head = 0;
    this.tail = 0;
    this.count = 0;
    // Fill with undefined for GC
    this.buffer.fill(undefined);
  }

  /**
   * Convert to array (oldest first) - O(n)
   */
  toArray(): T[] {
    const result: T[] = [];
    for (let i = 0; i < this.count; i++) {
      const item = this.buffer[(this.head + i) % this.capacity];
      if (item !== undefined) {
        result.push(item);
      }
    }
    return result;
  }

  /**
   * Iterate over items (oldest first)
   */
  *[Symbol.iterator](): Iterator<T> {
    for (let i = 0; i < this.count; i++) {
      const item = this.buffer[(this.head + i) % this.capacity];
      if (item !== undefined) {
        yield item;
      }
    }
  }

  /**
   * Execute callback for each item (oldest first)
   */
  forEach(callback: (item: T, index: number) => void): void {
    for (let i = 0; i < this.count; i++) {
      const item = this.buffer[(this.head + i) % this.capacity];
      if (item !== undefined) {
        callback(item, i);
      }
    }
  }

  /**
   * Get average of numeric buffer (for statistics)
   */
  average(this: CircularBuffer<number>): number {
    if (this.count === 0) return 0;
    let sum = 0;
    this.forEach(v => sum += v);
    return sum / this.count;
  }

  /**
   * Get min/max of numeric buffer
   */
  minMax(this: CircularBuffer<number>): { min: number; max: number } {
    if (this.count === 0) return { min: 0, max: 0 };
    let min = Infinity;
    let max = -Infinity;
    this.forEach(v => {
      if (v < min) min = v;
      if (v > max) max = v;
    });
    return { min, max };
  }
}

/**
 * Pre-allocated circular buffer for Float32 audio samples
 * Uses typed array for better performance
 */
export class Float32CircularBuffer {
  private buffer: Float32Array;
  private head: number = 0;
  private tail: number = 0;
  private count: number = 0;

  constructor(capacity: number) {
    this.buffer = new Float32Array(capacity);
  }

  push(value: number): void {
    this.buffer[this.tail] = value;
    this.tail = (this.tail + 1) % this.buffer.length;

    if (this.count < this.buffer.length) {
      this.count++;
    } else {
      this.head = (this.head + 1) % this.buffer.length;
    }
  }

  shift(): number {
    if (this.count === 0) return 0;
    const value = this.buffer[this.head];
    this.head = (this.head + 1) % this.buffer.length;
    this.count--;
    return value;
  }

  get length(): number {
    return this.count;
  }

  clear(): void {
    this.head = 0;
    this.tail = 0;
    this.count = 0;
    this.buffer.fill(0);
  }

  /**
   * Get RMS of buffer
   */
  rms(): number {
    if (this.count === 0) return 0;
    let sum = 0;
    for (let i = 0; i < this.count; i++) {
      const value = this.buffer[(this.head + i) % this.buffer.length];
      sum += value * value;
    }
    return Math.sqrt(sum / this.count);
  }

  /**
   * Get peak of buffer
   */
  peak(): number {
    let max = 0;
    for (let i = 0; i < this.count; i++) {
      const abs = Math.abs(this.buffer[(this.head + i) % this.buffer.length]);
      if (abs > max) max = abs;
    }
    return max;
  }
}
