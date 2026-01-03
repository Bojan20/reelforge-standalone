/**
 * ReelForge Project Archive
 *
 * Handle project archives (.rfproj.zip) containing:
 * - Project metadata (project.json)
 * - Audio files (audio/)
 * - MIDI files (midi/)
 * - Presets (presets/)
 *
 * Uses JSZip for compression.
 *
 * @module file-system/ProjectArchive
 */

// ============ Types ============

export interface ProjectManifest {
  version: number;
  name: string;
  createdAt: string;
  updatedAt: string;
  description?: string;
  author?: string;
  tempo: number;
  timeSignature: [number, number];
  sampleRate: number;
  audioFiles: AudioFileEntry[];
  midiFiles?: MidiFileEntry[];
  markers?: MarkerEntry[];
}

export interface AudioFileEntry {
  id: string;
  name: string;
  path: string; // Relative path in archive
  duration: number;
  sampleRate: number;
  channels: number;
  size: number;
  hash?: string; // SHA-256 for deduplication
}

export interface MidiFileEntry {
  id: string;
  name: string;
  path: string;
  duration: number;
  trackCount: number;
}

export interface MarkerEntry {
  id: string;
  name: string;
  time: number;
  color?: string;
}

export interface ArchiveProgress {
  phase: 'reading' | 'writing' | 'compressing' | 'extracting';
  current: number;
  total: number;
  fileName?: string;
}

type ProgressCallback = (progress: ArchiveProgress) => void;

// ============ JSZip Dynamic Import ============

import type JSZipType from 'jszip';

let JSZipClass: typeof JSZipType | null = null;

async function getJSZip(): Promise<typeof JSZipType> {
  if (!JSZipClass) {
    const module = await import('jszip');
    JSZipClass = module.default;
  }
  return JSZipClass;
}

// ============ Project Archive Class ============

export class ProjectArchive {
  private manifest: ProjectManifest;
  private audioFiles = new Map<string, ArrayBuffer>();
  private midiFiles = new Map<string, ArrayBuffer>();
  private presets = new Map<string, string>();

  constructor(manifest?: Partial<ProjectManifest>) {
    this.manifest = {
      version: 1,
      name: 'Untitled Project',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      tempo: 120,
      timeSignature: [4, 4],
      sampleRate: 48000,
      audioFiles: [],
      ...manifest,
    };
  }

  // ============ Getters ============

  getName(): string {
    return this.manifest.name;
  }

  getManifest(): Readonly<ProjectManifest> {
    return { ...this.manifest };
  }

  getAudioFiles(): AudioFileEntry[] {
    return [...this.manifest.audioFiles];
  }

  getAudioBuffer(id: string): ArrayBuffer | undefined {
    return this.audioFiles.get(id);
  }

  // ============ Setters ============

  setName(name: string): void {
    this.manifest.name = name;
    this.manifest.updatedAt = new Date().toISOString();
  }

  setTempo(tempo: number): void {
    this.manifest.tempo = tempo;
    this.manifest.updatedAt = new Date().toISOString();
  }

  setTimeSignature(numerator: number, denominator: number): void {
    this.manifest.timeSignature = [numerator, denominator];
    this.manifest.updatedAt = new Date().toISOString();
  }

  // ============ Audio Files ============

  /**
   * Add audio file to archive.
   */
  addAudioFile(
    id: string,
    name: string,
    data: ArrayBuffer,
    metadata: {
      duration: number;
      sampleRate: number;
      channels: number;
    }
  ): void {
    const path = `audio/${id}_${this.sanitizeFileName(name)}`;

    this.audioFiles.set(id, data);

    this.manifest.audioFiles.push({
      id,
      name,
      path,
      duration: metadata.duration,
      sampleRate: metadata.sampleRate,
      channels: metadata.channels,
      size: data.byteLength,
    });

    this.manifest.updatedAt = new Date().toISOString();
  }

  /**
   * Remove audio file from archive.
   */
  removeAudioFile(id: string): boolean {
    const index = this.manifest.audioFiles.findIndex(f => f.id === id);
    if (index === -1) return false;

    this.manifest.audioFiles.splice(index, 1);
    this.audioFiles.delete(id);
    this.manifest.updatedAt = new Date().toISOString();

    return true;
  }

  // ============ Markers ============

  addMarker(id: string, name: string, time: number, color?: string): void {
    if (!this.manifest.markers) {
      this.manifest.markers = [];
    }

    this.manifest.markers.push({ id, name, time, color });
    this.manifest.updatedAt = new Date().toISOString();
  }

  // ============ Presets ============

  addPreset(name: string, data: string): void {
    this.presets.set(name, data);
    this.manifest.updatedAt = new Date().toISOString();
  }

  getPreset(name: string): string | undefined {
    return this.presets.get(name);
  }

  // ============ Export ============

  /**
   * Export archive as Blob.
   */
  async exportAsBlob(onProgress?: ProgressCallback): Promise<Blob> {
    const JSZipConstructor = await getJSZip();
    const zip = new JSZipConstructor();

    const totalFiles = this.audioFiles.size + this.midiFiles.size + this.presets.size + 1;
    let processed = 0;

    // Add manifest
    onProgress?.({
      phase: 'writing',
      current: processed,
      total: totalFiles,
      fileName: 'project.json',
    });

    zip.file('project.json', JSON.stringify(this.manifest, null, 2));
    processed++;

    // Add audio files
    for (const [id, data] of this.audioFiles) {
      const entry = this.manifest.audioFiles.find(f => f.id === id);
      const path = entry?.path || `audio/${id}.wav`;

      onProgress?.({
        phase: 'writing',
        current: processed,
        total: totalFiles,
        fileName: path,
      });

      zip.file(path, data);
      processed++;
    }

    // Add MIDI files
    for (const [id, data] of this.midiFiles) {
      const entry = this.manifest.midiFiles?.find(f => f.id === id);
      const path = entry?.path || `midi/${id}.mid`;

      onProgress?.({
        phase: 'writing',
        current: processed,
        total: totalFiles,
        fileName: path,
      });

      zip.file(path, data);
      processed++;
    }

    // Add presets
    for (const [name, data] of this.presets) {
      const path = `presets/${name}.json`;

      onProgress?.({
        phase: 'writing',
        current: processed,
        total: totalFiles,
        fileName: path,
      });

      zip.file(path, data);
      processed++;
    }

    // Compress
    onProgress?.({
      phase: 'compressing',
      current: 0,
      total: 100,
    });

    return zip.generateAsync(
      {
        type: 'blob',
        compression: 'DEFLATE',
        compressionOptions: { level: 6 },
      },
      (meta: { percent: number }) => {
        onProgress?.({
          phase: 'compressing',
          current: Math.round(meta.percent),
          total: 100,
        });
      }
    );
  }

  /**
   * Export archive as ArrayBuffer.
   */
  async exportAsArrayBuffer(onProgress?: ProgressCallback): Promise<ArrayBuffer> {
    const blob = await this.exportAsBlob(onProgress);
    return blob.arrayBuffer();
  }

  // ============ Import ============

  /**
   * Import archive from Blob.
   */
  static async fromBlob(blob: Blob, onProgress?: ProgressCallback): Promise<ProjectArchive> {
    const JSZipConstructor = await getJSZip();
    const zip = await JSZipConstructor.loadAsync(blob);

    // Read manifest
    const manifestFile = zip.file('project.json');
    if (!manifestFile) {
      throw new Error('Invalid archive: missing project.json');
    }

    onProgress?.({
      phase: 'reading',
      current: 0,
      total: Object.keys(zip.files).length,
      fileName: 'project.json',
    });

    const manifestText = await manifestFile.async('text');
    const manifest = JSON.parse(manifestText) as ProjectManifest;

    const archive = new ProjectArchive(manifest);

    // Count files
    const fileEntries = Object.entries(zip.files).filter(([, file]) => !(file as { dir: boolean }).dir);
    let processed = 1;

    // Read audio files
    for (const audioEntry of manifest.audioFiles) {
      const file = zip.file(audioEntry.path);
      if (file) {
        onProgress?.({
          phase: 'extracting',
          current: processed,
          total: fileEntries.length,
          fileName: audioEntry.path,
        });

        const data = await file.async('arraybuffer');
        archive.audioFiles.set(audioEntry.id, data);
        processed++;
      }
    }

    // Read MIDI files
    if (manifest.midiFiles) {
      for (const midiEntry of manifest.midiFiles) {
        const file = zip.file(midiEntry.path);
        if (file) {
          onProgress?.({
            phase: 'extracting',
            current: processed,
            total: fileEntries.length,
            fileName: midiEntry.path,
          });

          const data = await file.async('arraybuffer');
          archive.midiFiles.set(midiEntry.id, data);
          processed++;
        }
      }
    }

    // Read presets
    const presetPaths = Object.keys(zip.files).filter(
      (path) => path.startsWith('presets/') && path.endsWith('.json')
    );

    for (const path of presetPaths) {
      const file = zip.file(path);
      if (file) {
        onProgress?.({
          phase: 'extracting',
          current: processed,
          total: fileEntries.length,
          fileName: path,
        });

        const data = await file.async('text');
        const name = path.replace('presets/', '').replace('.json', '');
        archive.presets.set(name, data);
        processed++;
      }
    }

    return archive;
  }

  /**
   * Import archive from ArrayBuffer.
   */
  static async fromArrayBuffer(buffer: ArrayBuffer, onProgress?: ProgressCallback): Promise<ProjectArchive> {
    return ProjectArchive.fromBlob(new Blob([buffer]), onProgress);
  }

  /**
   * Import archive from File.
   */
  static async fromFile(file: File, onProgress?: ProgressCallback): Promise<ProjectArchive> {
    return ProjectArchive.fromBlob(file, onProgress);
  }

  // ============ Utilities ============

  /**
   * Sanitize filename for archive paths.
   */
  private sanitizeFileName(name: string): string {
    return name
      .replace(/[<>:"/\\|?*]/g, '_')
      .replace(/\s+/g, '_')
      .substring(0, 100);
  }

  /**
   * Calculate total archive size (uncompressed).
   */
  getUncompressedSize(): number {
    let size = JSON.stringify(this.manifest).length;

    for (const data of this.audioFiles.values()) {
      size += data.byteLength;
    }

    for (const data of this.midiFiles.values()) {
      size += data.byteLength;
    }

    for (const data of this.presets.values()) {
      size += data.length;
    }

    return size;
  }

  /**
   * Get audio file count.
   */
  getAudioFileCount(): number {
    return this.audioFiles.size;
  }

  /**
   * Get total audio duration.
   */
  getTotalAudioDuration(): number {
    return this.manifest.audioFiles.reduce((sum, f) => sum + f.duration, 0);
  }

  /**
   * Clone archive (deep copy).
   */
  clone(): ProjectArchive {
    const clone = new ProjectArchive({ ...this.manifest });

    for (const [id, data] of this.audioFiles) {
      clone.audioFiles.set(id, data.slice(0));
    }

    for (const [id, data] of this.midiFiles) {
      clone.midiFiles.set(id, data.slice(0));
    }

    for (const [name, data] of this.presets) {
      clone.presets.set(name, data);
    }

    return clone;
  }
}

// ============ Utility Functions ============

/**
 * Generate suggested archive filename.
 */
export function generateArchiveFilename(projectName: string): string {
  const safeName = projectName.replace(/[^a-zA-Z0-9\s-]/g, '').trim();
  const date = new Date().toISOString().split('T')[0];
  return `${safeName}_${date}.rfproj.zip`;
}

/**
 * Format file size for display.
 */
export function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}
