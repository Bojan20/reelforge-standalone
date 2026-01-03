/**
 * Audio Storage Utilities
 *
 * IndexedDB functions for persisting audio files across sessions.
 */

const INDEXEDDB_NAME = 'reelforge-audio';
const INDEXEDDB_STORE = 'audio-files';
const INDEXEDDB_VERSION = 1;

/**
 * Open the audio IndexedDB database.
 */
export const openAudioDB = (): Promise<IDBDatabase> => {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(INDEXEDDB_NAME, INDEXEDDB_VERSION);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
    request.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;
      if (!db.objectStoreNames.contains(INDEXEDDB_STORE)) {
        db.createObjectStore(INDEXEDDB_STORE, { keyPath: 'id' });
      }
    };
  });
};

export interface StoredAudioFile {
  id: string;
  name: string;
  arrayBuffer: ArrayBuffer;
  duration: number;
  waveform: number[];
  /** Offset into source audio where actual content starts (skip MP3/AAC padding) */
  sourceOffset?: number;
}

/**
 * Save audio files to IndexedDB.
 */
export const saveAudioToDB = async (files: StoredAudioFile[]): Promise<void> => {
  const db = await openAudioDB();
  const tx = db.transaction(INDEXEDDB_STORE, 'readwrite');
  const store = tx.objectStore(INDEXEDDB_STORE);

  // Clear existing files
  store.clear();

  // Add new files
  for (const file of files) {
    store.put(file);
  }

  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
};

/**
 * Load all audio files from IndexedDB.
 */
export const loadAudioFromDB = async (): Promise<StoredAudioFile[]> => {
  try {
    const db = await openAudioDB();
    const tx = db.transaction(INDEXEDDB_STORE, 'readonly');
    const store = tx.objectStore(INDEXEDDB_STORE);
    const request = store.getAll();

    return new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error);
    });
  } catch {
    return [];
  }
};

/**
 * Clear all audio files from IndexedDB.
 * Call this on New Project to ensure clean state.
 */
export const clearAudioDB = async (): Promise<void> => {
  try {
    const db = await openAudioDB();
    const tx = db.transaction(INDEXEDDB_STORE, 'readwrite');
    const store = tx.objectStore(INDEXEDDB_STORE);
    store.clear();
    await new Promise<void>((resolve, reject) => {
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch {
    // Ignore errors - DB might not exist yet
  }
};
