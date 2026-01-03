import type { AudioFileObject } from './types';

const DB_NAME = "ReelForgeDB";
const DB_VERSION = 1;
const AUDIO_STORE = "audioFiles";

const openDB = (): Promise<IDBDatabase> => {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);

    request.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;
      if (!db.objectStoreNames.contains(AUDIO_STORE)) {
        db.createObjectStore(AUDIO_STORE, { keyPath: "id" });
      }
    };
  });
};

export const saveAudioFileToDB = async (audioFile: AudioFileObject): Promise<void> => {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const transaction = db.transaction([AUDIO_STORE], "readwrite");
      const store = transaction.objectStore(AUDIO_STORE);
      const request = store.put({
        id: audioFile.id,
        name: audioFile.name,
        fileData: reader.result,
        fileName: audioFile.file.name,
        fileType: audioFile.file.type,
        duration: audioFile.duration,
        size: audioFile.size,
      });

      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    };
    reader.onerror = () => reject(reader.error);
    reader.readAsArrayBuffer(audioFile.file);
  });
};

export const loadAudioFilesFromDB = async (): Promise<AudioFileObject[]> => {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction([AUDIO_STORE], "readonly");
    const store = transaction.objectStore(AUDIO_STORE);
    const request = store.getAll();

    request.onsuccess = () => {
      const files = request.result || [];
      const restoredFiles = files.map((fileData: any) => {
        const blob = new Blob([fileData.fileData], { type: fileData.fileType });
        const file = new File([blob], fileData.fileName, { type: fileData.fileType });
        const newUrl = URL.createObjectURL(blob);
        return {
          id: fileData.id,
          name: fileData.name,
          file: file,
          url: newUrl,
          duration: fileData.duration,
          size: fileData.size,
        };
      });
      resolve(restoredFiles);
    };
    request.onerror = () => reject(request.error);
  });
};

export const clearAudioFilesFromDB = async (): Promise<void> => {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction([AUDIO_STORE], "readwrite");
    const store = transaction.objectStore(AUDIO_STORE);
    const request = store.clear();

    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
};
