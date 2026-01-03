/**
 * ReelForge File System API
 *
 * Modern File System Access API wrapper with fallbacks.
 * Provides unified interface for native file operations.
 *
 * @module file-system/FileSystemAPI
 */

// ============ Types ============

export interface FilePickerOptions {
  types?: FilePickerType[];
  excludeAcceptAllOption?: boolean;
  multiple?: boolean;
  startIn?: 'desktop' | 'documents' | 'downloads' | 'music' | 'pictures' | 'videos';
}

export interface FilePickerType {
  description: string;
  accept: Record<string, string[]>;
}

export interface SaveFileOptions {
  suggestedName?: string;
  types?: FilePickerType[];
  excludeAcceptAllOption?: boolean;
}

export interface DirectoryPickerOptions {
  startIn?: 'desktop' | 'documents' | 'downloads' | 'music' | 'pictures' | 'videos';
  mode?: 'read' | 'readwrite';
}

export interface FileEntry {
  name: string;
  path: string;
  kind: 'file' | 'directory';
  size?: number;
  lastModified?: number;
  handle?: FileSystemFileHandle;
}

// ============ File Type Presets ============

export const FILE_TYPES = {
  PROJECT: {
    description: 'ReelForge Project',
    accept: {
      'application/json': ['.rfproj', '.json'],
    },
  },
  PROJECT_ARCHIVE: {
    description: 'ReelForge Project Archive',
    accept: {
      'application/zip': ['.rfproj.zip', '.zip'],
    },
  },
  AUDIO: {
    description: 'Audio Files',
    accept: {
      'audio/*': ['.wav', '.mp3', '.ogg', '.flac', '.m4a', '.aac', '.webm'],
    },
  },
  WAV: {
    description: 'WAV Audio',
    accept: {
      'audio/wav': ['.wav'],
    },
  },
  MIDI: {
    description: 'MIDI Files',
    accept: {
      'audio/midi': ['.mid', '.midi'],
    },
  },
  JSON: {
    description: 'JSON Files',
    accept: {
      'application/json': ['.json'],
    },
  },
  ALL_AUDIO: {
    description: 'All Audio Formats',
    accept: {
      'audio/wav': ['.wav'],
      'audio/mpeg': ['.mp3'],
      'audio/ogg': ['.ogg'],
      'audio/flac': ['.flac'],
      'audio/aac': ['.m4a', '.aac'],
      'audio/webm': ['.webm'],
    },
  },
} as const;

// ============ File System API Class ============

class FileSystemAPIClass {
  private recentHandles = new Map<string, FileSystemFileHandle | FileSystemDirectoryHandle>();

  /**
   * Check if File System Access API is supported.
   */
  isSupported(): boolean {
    return typeof window !== 'undefined' &&
      'showOpenFilePicker' in window &&
      'showSaveFilePicker' in window;
  }

  /**
   * Check if directory picker is supported.
   */
  isDirectoryPickerSupported(): boolean {
    return typeof window !== 'undefined' && 'showDirectoryPicker' in window;
  }

  /**
   * Open file picker and return selected files.
   */
  async openFilePicker(options: FilePickerOptions = {}): Promise<FileEntry[]> {
    if (this.isSupported()) {
      return this.openFilePickerNative(options);
    }
    return this.openFilePickerFallback(options);
  }

  /**
   * Native File System Access API picker.
   */
  private async openFilePickerNative(options: FilePickerOptions): Promise<FileEntry[]> {
    try {
      const handles = await window.showOpenFilePicker({
        types: options.types,
        excludeAcceptAllOption: options.excludeAcceptAllOption,
        multiple: options.multiple ?? false,
        startIn: options.startIn,
      });

      const entries: FileEntry[] = [];

      for (const handle of handles) {
        const file = await handle.getFile();
        const entry: FileEntry = {
          name: file.name,
          path: file.name, // Full path not available in browser
          kind: 'file',
          size: file.size,
          lastModified: file.lastModified,
          handle,
        };
        entries.push(entry);

        // Store handle for later access
        this.recentHandles.set(file.name, handle);
      }

      return entries;
    } catch (err) {
      if ((err as Error).name === 'AbortError') {
        return []; // User cancelled
      }
      throw err;
    }
  }

  /**
   * Fallback using input element.
   */
  private async openFilePickerFallback(options: FilePickerOptions): Promise<FileEntry[]> {
    return new Promise((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.multiple = options.multiple ?? false;

      // Build accept string from types
      if (options.types) {
        const accepts: string[] = [];
        for (const type of options.types) {
          for (const [mime, exts] of Object.entries(type.accept)) {
            accepts.push(mime);
            accepts.push(...exts);
          }
        }
        input.accept = accepts.join(',');
      }

      input.onchange = () => {
        const files = input.files;
        if (!files || files.length === 0) {
          resolve([]);
          return;
        }

        const entries: FileEntry[] = [];
        for (let i = 0; i < files.length; i++) {
          const file = files[i];
          entries.push({
            name: file.name,
            path: file.name,
            kind: 'file',
            size: file.size,
            lastModified: file.lastModified,
          });
        }
        resolve(entries);
      };

      input.click();
    });
  }

  /**
   * Save file with picker.
   */
  async saveFilePicker(
    data: Blob | ArrayBuffer | string,
    options: SaveFileOptions = {}
  ): Promise<FileEntry | null> {
    if (this.isSupported()) {
      return this.saveFilePickerNative(data, options);
    }
    return this.saveFilePickerFallback(data, options);
  }

  /**
   * Native save file picker.
   */
  private async saveFilePickerNative(
    data: Blob | ArrayBuffer | string,
    options: SaveFileOptions
  ): Promise<FileEntry | null> {
    try {
      const handle = await window.showSaveFilePicker({
        suggestedName: options.suggestedName,
        types: options.types,
        excludeAcceptAllOption: options.excludeAcceptAllOption,
      });

      const writable = await handle.createWritable();

      if (data instanceof Blob) {
        await writable.write(data);
      } else if (data instanceof ArrayBuffer) {
        await writable.write(new Blob([data]));
      } else {
        await writable.write(data);
      }

      await writable.close();

      const file = await handle.getFile();
      this.recentHandles.set(file.name, handle);

      return {
        name: file.name,
        path: file.name,
        kind: 'file',
        size: file.size,
        lastModified: file.lastModified,
        handle,
      };
    } catch (err) {
      if ((err as Error).name === 'AbortError') {
        return null; // User cancelled
      }
      throw err;
    }
  }

  /**
   * Fallback save using download link.
   */
  private async saveFilePickerFallback(
    data: Blob | ArrayBuffer | string,
    options: SaveFileOptions
  ): Promise<FileEntry | null> {
    const blob = data instanceof Blob
      ? data
      : data instanceof ArrayBuffer
        ? new Blob([data])
        : new Blob([data], { type: 'text/plain' });

    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = options.suggestedName || 'untitled';

    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);

    URL.revokeObjectURL(url);

    return {
      name: options.suggestedName || 'untitled',
      path: options.suggestedName || 'untitled',
      kind: 'file',
    };
  }

  /**
   * Open directory picker.
   */
  async openDirectoryPicker(options: DirectoryPickerOptions = {}): Promise<FileEntry | null> {
    if (!this.isDirectoryPickerSupported()) {
      throw new Error('Directory picker not supported');
    }

    try {
      const handle = await window.showDirectoryPicker({
        startIn: options.startIn,
        mode: options.mode ?? 'read',
      });

      this.recentHandles.set(handle.name, handle);

      return {
        name: handle.name,
        path: handle.name,
        kind: 'directory',
        handle: handle as unknown as FileSystemFileHandle,
      };
    } catch (err) {
      if ((err as Error).name === 'AbortError') {
        return null;
      }
      throw err;
    }
  }

  /**
   * Read file from handle or entry.
   */
  async readFile(entry: FileEntry): Promise<File> {
    if (entry.handle) {
      return entry.handle.getFile();
    }
    throw new Error('No file handle available');
  }

  /**
   * Read file as text.
   */
  async readFileAsText(entry: FileEntry): Promise<string> {
    const file = await this.readFile(entry);
    return file.text();
  }

  /**
   * Read file as ArrayBuffer.
   */
  async readFileAsArrayBuffer(entry: FileEntry): Promise<ArrayBuffer> {
    const file = await this.readFile(entry);
    return file.arrayBuffer();
  }

  /**
   * Read file as JSON.
   */
  async readFileAsJSON<T = unknown>(entry: FileEntry): Promise<T> {
    const text = await this.readFileAsText(entry);
    return JSON.parse(text);
  }

  /**
   * Write to existing file handle.
   */
  async writeFile(entry: FileEntry, data: Blob | ArrayBuffer | string): Promise<void> {
    if (!entry.handle) {
      throw new Error('No file handle available');
    }

    const writable = await entry.handle.createWritable();

    if (data instanceof Blob) {
      await writable.write(data);
    } else if (data instanceof ArrayBuffer) {
      await writable.write(new Blob([data]));
    } else {
      await writable.write(data);
    }

    await writable.close();
  }

  /**
   * List files in directory.
   */
  async listDirectory(dirEntry: FileEntry): Promise<FileEntry[]> {
    if (!dirEntry.handle || dirEntry.kind !== 'directory') {
      throw new Error('Not a directory handle');
    }

    const dirHandle = dirEntry.handle as unknown as FileSystemDirectoryHandle;
    const entries: FileEntry[] = [];

    for await (const [name, handle] of dirHandle.entries()) {
      if (handle.kind === 'file') {
        const fileHandle = handle as FileSystemFileHandle;
        const file = await fileHandle.getFile();
        entries.push({
          name,
          path: `${dirEntry.path}/${name}`,
          kind: 'file',
          size: file.size,
          lastModified: file.lastModified,
          handle: fileHandle,
        });
      } else {
        entries.push({
          name,
          path: `${dirEntry.path}/${name}`,
          kind: 'directory',
          handle: handle as unknown as FileSystemFileHandle,
        });
      }
    }

    return entries;
  }

  /**
   * Request permission for handle.
   */
  async requestPermission(
    handle: FileSystemFileHandle | FileSystemDirectoryHandle,
    mode: 'read' | 'readwrite' = 'read'
  ): Promise<boolean> {
    const options = { mode };

    // Check current permission
    if ((await handle.queryPermission(options)) === 'granted') {
      return true;
    }

    // Request permission
    return (await handle.requestPermission(options)) === 'granted';
  }

  /**
   * Get recent file handle by name.
   */
  getRecentHandle(name: string): FileSystemFileHandle | FileSystemDirectoryHandle | undefined {
    return this.recentHandles.get(name);
  }

  /**
   * Clear recent handles.
   */
  clearRecentHandles(): void {
    this.recentHandles.clear();
  }
}

// Singleton instance
export const FileSystemAPI = new FileSystemAPIClass();

// ============ Type Declarations for File System Access API ============

declare global {
  interface Window {
    showOpenFilePicker(options?: {
      types?: FilePickerType[];
      excludeAcceptAllOption?: boolean;
      multiple?: boolean;
      startIn?: string;
    }): Promise<FileSystemFileHandle[]>;

    showSaveFilePicker(options?: {
      suggestedName?: string;
      types?: FilePickerType[];
      excludeAcceptAllOption?: boolean;
    }): Promise<FileSystemFileHandle>;

    showDirectoryPicker(options?: {
      startIn?: string;
      mode?: 'read' | 'readwrite';
    }): Promise<FileSystemDirectoryHandle>;
  }

  interface FileSystemFileHandle {
    getFile(): Promise<File>;
    createWritable(): Promise<FileSystemWritableFileStream>;
    queryPermission(options?: { mode?: string }): Promise<PermissionState>;
    requestPermission(options?: { mode?: string }): Promise<PermissionState>;
  }

  interface FileSystemDirectoryHandle {
    entries(): AsyncIterable<[string, FileSystemHandle]>;
    getFileHandle(name: string, options?: { create?: boolean }): Promise<FileSystemFileHandle>;
    getDirectoryHandle(name: string, options?: { create?: boolean }): Promise<FileSystemDirectoryHandle>;
    removeEntry(name: string, options?: { recursive?: boolean }): Promise<void>;
    queryPermission(options?: { mode?: string }): Promise<PermissionState>;
    requestPermission(options?: { mode?: string }): Promise<PermissionState>;
  }

  interface FileSystemWritableFileStream extends WritableStream {
    write(data: BufferSource | Blob | string): Promise<void>;
    seek(position: number): Promise<void>;
    truncate(size: number): Promise<void>;
  }
}
