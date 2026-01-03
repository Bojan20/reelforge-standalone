/**
 * ReelForge Cloud Sync
 *
 * Cloud storage integration, backup system, and cross-device synchronization.
 * Supports multiple cloud providers with offline-first architecture.
 *
 * @module advanced-features/CloudSync
 */

// ============ Types ============

export type CloudProvider = 'reelforge' | 'dropbox' | 'google-drive' | 'onedrive' | 's3';
export type SyncStatus = 'idle' | 'syncing' | 'uploading' | 'downloading' | 'error' | 'offline';
export type ConflictResolution = 'local' | 'remote' | 'merge' | 'manual';

export interface CloudConfig {
  provider: CloudProvider;
  credentials: CloudCredentials;
  syncFolder: string;
  autoSync: boolean;
  syncInterval: number; // ms
  maxFileSize: number; // bytes
  compressionEnabled: boolean;
}

export interface CloudCredentials {
  accessToken?: string;
  refreshToken?: string;
  apiKey?: string;
  expiresAt?: number;
}

export interface SyncItem {
  id: string;
  localPath: string;
  remotePath: string;
  localHash: string;
  remoteHash: string;
  localModified: number;
  remoteModified: number;
  size: number;
  status: 'synced' | 'modified' | 'conflict' | 'new' | 'deleted';
}

export interface SyncResult {
  success: boolean;
  uploaded: number;
  downloaded: number;
  conflicts: SyncConflict[];
  errors: SyncError[];
  duration: number;
}

export interface SyncConflict {
  itemId: string;
  localVersion: FileVersion;
  remoteVersion: FileVersion;
  resolved: boolean;
  resolution?: ConflictResolution;
}

export interface FileVersion {
  hash: string;
  modified: number;
  size: number;
  author?: string;
}

export interface SyncError {
  itemId: string;
  error: string;
  retryable: boolean;
}

export interface BackupConfig {
  enabled: boolean;
  interval: number; // ms
  maxBackups: number;
  includeAudio: boolean;
  compressBackups: boolean;
}

export interface Backup {
  id: string;
  timestamp: number;
  size: number;
  projectId: string;
  projectName: string;
  version: string;
  checksum: string;
}

// ============ Cloud Provider Interface ============

export interface ICloudProvider {
  name: CloudProvider;
  connect(credentials: CloudCredentials): Promise<boolean>;
  disconnect(): Promise<void>;
  isConnected(): boolean;

  listFiles(path: string): Promise<RemoteFile[]>;
  uploadFile(localPath: string, remotePath: string, data: ArrayBuffer): Promise<RemoteFile>;
  downloadFile(remotePath: string): Promise<ArrayBuffer>;
  deleteFile(remotePath: string): Promise<boolean>;

  getFileInfo(remotePath: string): Promise<RemoteFile | null>;
  createFolder(path: string): Promise<boolean>;

  getQuota(): Promise<StorageQuota>;
}

export interface RemoteFile {
  path: string;
  name: string;
  size: number;
  modified: number;
  hash: string;
  isFolder: boolean;
}

export interface StorageQuota {
  used: number;
  total: number;
  available: number;
}

// ============ ReelForge Cloud Provider ============

class ReelForgeCloudProvider implements ICloudProvider {
  name: CloudProvider = 'reelforge';
  private connected = false;
  private baseUrl = 'https://api.reelforge.io/v1';
  private token: string | null = null;

  async connect(credentials: CloudCredentials): Promise<boolean> {
    if (!credentials.accessToken) {
      throw new Error('Access token required');
    }

    // Validate token
    try {
      const response = await fetch(`${this.baseUrl}/auth/validate`, {
        headers: { Authorization: `Bearer ${credentials.accessToken}` }
      });

      if (response.ok) {
        this.token = credentials.accessToken;
        this.connected = true;
        return true;
      }
    } catch {
      // Offline mode
    }

    return false;
  }

  async disconnect(): Promise<void> {
    this.token = null;
    this.connected = false;
  }

  isConnected(): boolean {
    return this.connected;
  }

  async listFiles(path: string): Promise<RemoteFile[]> {
    if (!this.connected) throw new Error('Not connected');

    const response = await fetch(`${this.baseUrl}/files/list?path=${encodeURIComponent(path)}`, {
      headers: { Authorization: `Bearer ${this.token}` }
    });

    if (!response.ok) throw new Error('Failed to list files');
    return response.json();
  }

  async uploadFile(localPath: string, remotePath: string, data: ArrayBuffer): Promise<RemoteFile> {
    if (!this.connected) throw new Error('Not connected');

    const formData = new FormData();
    formData.append('file', new Blob([data]));
    formData.append('path', remotePath);
    formData.append('localPath', localPath);

    const response = await fetch(`${this.baseUrl}/files/upload`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.token}` },
      body: formData
    });

    if (!response.ok) throw new Error('Failed to upload file');
    return response.json();
  }

  async downloadFile(remotePath: string): Promise<ArrayBuffer> {
    if (!this.connected) throw new Error('Not connected');

    const response = await fetch(
      `${this.baseUrl}/files/download?path=${encodeURIComponent(remotePath)}`,
      { headers: { Authorization: `Bearer ${this.token}` } }
    );

    if (!response.ok) throw new Error('Failed to download file');
    return response.arrayBuffer();
  }

  async deleteFile(remotePath: string): Promise<boolean> {
    if (!this.connected) throw new Error('Not connected');

    const response = await fetch(
      `${this.baseUrl}/files/delete?path=${encodeURIComponent(remotePath)}`,
      {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${this.token}` }
      }
    );

    return response.ok;
  }

  async getFileInfo(remotePath: string): Promise<RemoteFile | null> {
    if (!this.connected) throw new Error('Not connected');

    const response = await fetch(
      `${this.baseUrl}/files/info?path=${encodeURIComponent(remotePath)}`,
      { headers: { Authorization: `Bearer ${this.token}` } }
    );

    if (response.status === 404) return null;
    if (!response.ok) throw new Error('Failed to get file info');
    return response.json();
  }

  async createFolder(path: string): Promise<boolean> {
    if (!this.connected) throw new Error('Not connected');

    const response = await fetch(`${this.baseUrl}/files/folder`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ path })
    });

    return response.ok;
  }

  async getQuota(): Promise<StorageQuota> {
    if (!this.connected) throw new Error('Not connected');

    const response = await fetch(`${this.baseUrl}/account/quota`, {
      headers: { Authorization: `Bearer ${this.token}` }
    });

    if (!response.ok) throw new Error('Failed to get quota');
    return response.json();
  }
}

// ============ Sync Engine ============

export class SyncEngine {
  private provider: ICloudProvider | null = null;
  private config: CloudConfig | null = null;
  private syncItems = new Map<string, SyncItem>();
  private status: SyncStatus = 'idle';
  private syncTimer: number | null = null;
  private listeners = new Set<(status: SyncStatus) => void>();
  private pendingChanges: SyncItem[] = [];
  private offlineQueue: Array<{ action: 'upload' | 'download' | 'delete'; item: SyncItem }> = [];

  // ============ Initialization ============

  async initialize(config: CloudConfig): Promise<boolean> {
    this.config = config;

    // Create provider
    this.provider = this.createProvider(config.provider);

    // Connect
    const connected = await this.provider.connect(config.credentials);

    if (connected && config.autoSync) {
      this.startAutoSync();
    }

    return connected;
  }

  private createProvider(type: CloudProvider): ICloudProvider {
    switch (type) {
      case 'reelforge':
        return new ReelForgeCloudProvider();
      // Other providers would be implemented here
      default:
        return new ReelForgeCloudProvider();
    }
  }

  dispose(): void {
    this.stopAutoSync();
    this.provider?.disconnect();
    this.syncItems.clear();
    this.listeners.clear();
  }

  // ============ Auto Sync ============

  private startAutoSync(): void {
    if (this.syncTimer) return;
    if (!this.config) return;

    this.syncTimer = window.setInterval(() => {
      this.sync();
    }, this.config.syncInterval);
  }

  private stopAutoSync(): void {
    if (this.syncTimer) {
      clearInterval(this.syncTimer);
      this.syncTimer = null;
    }
  }

  // ============ Sync Operations ============

  async sync(): Promise<SyncResult> {
    if (!this.provider?.isConnected()) {
      this.setStatus('offline');
      return this.createErrorResult('Not connected');
    }

    const startTime = performance.now();
    this.setStatus('syncing');

    const result: SyncResult = {
      success: true,
      uploaded: 0,
      downloaded: 0,
      conflicts: [],
      errors: [],
      duration: 0
    };

    try {
      // Process offline queue first
      await this.processOfflineQueue(result);

      // Detect changes
      const changes = await this.detectChanges();

      // Handle conflicts
      for (const item of changes.conflicts) {
        result.conflicts.push({
          itemId: item.id,
          localVersion: {
            hash: item.localHash,
            modified: item.localModified,
            size: item.size
          },
          remoteVersion: {
            hash: item.remoteHash,
            modified: item.remoteModified,
            size: item.size
          },
          resolved: false
        });
      }

      // Upload local changes
      for (const item of changes.toUpload) {
        try {
          await this.uploadItem(item);
          result.uploaded++;
        } catch (error) {
          result.errors.push({
            itemId: item.id,
            error: String(error),
            retryable: true
          });
        }
      }

      // Download remote changes
      for (const item of changes.toDownload) {
        try {
          await this.downloadItem(item);
          result.downloaded++;
        } catch (error) {
          result.errors.push({
            itemId: item.id,
            error: String(error),
            retryable: true
          });
        }
      }

      result.success = result.errors.length === 0;
    } catch (error) {
      result.success = false;
      result.errors.push({
        itemId: 'sync',
        error: String(error),
        retryable: true
      });
    }

    result.duration = performance.now() - startTime;
    this.setStatus(result.success ? 'idle' : 'error');

    return result;
  }

  private async detectChanges(): Promise<{
    toUpload: SyncItem[];
    toDownload: SyncItem[];
    conflicts: SyncItem[];
  }> {
    const toUpload: SyncItem[] = [];
    const toDownload: SyncItem[] = [];
    const conflicts: SyncItem[] = [];

    for (const [, item] of this.syncItems) {
      if (item.status === 'new' || item.status === 'modified') {
        // Check if remote also modified
        const remoteInfo = await this.provider!.getFileInfo(item.remotePath);

        if (remoteInfo && remoteInfo.hash !== item.remoteHash) {
          // Both modified - conflict
          item.status = 'conflict';
          conflicts.push(item);
        } else {
          toUpload.push(item);
        }
      } else if (item.status === 'deleted') {
        // Handle deletion
        toUpload.push(item);
      }
    }

    // Check for new remote files
    if (this.config) {
      const remoteFiles = await this.provider!.listFiles(this.config.syncFolder);

      for (const file of remoteFiles) {
        const existing = Array.from(this.syncItems.values())
          .find(item => item.remotePath === file.path);

        if (!existing) {
          // New remote file
          const newItem: SyncItem = {
            id: this.generateId(),
            localPath: this.remoteToLocalPath(file.path),
            remotePath: file.path,
            localHash: '',
            remoteHash: file.hash,
            localModified: 0,
            remoteModified: file.modified,
            size: file.size,
            status: 'new'
          };
          toDownload.push(newItem);
        } else if (file.hash !== existing.remoteHash) {
          // Remote modified
          if (existing.localHash !== existing.remoteHash) {
            // Both modified - conflict
            existing.status = 'conflict';
            conflicts.push(existing);
          } else {
            existing.remoteHash = file.hash;
            existing.remoteModified = file.modified;
            toDownload.push(existing);
          }
        }
      }
    }

    return { toUpload, toDownload, conflicts };
  }

  private async uploadItem(item: SyncItem): Promise<void> {
    this.setStatus('uploading');

    // Read local file
    const data = await this.readLocalFile(item.localPath);

    // Compress if enabled
    const uploadData = this.config?.compressionEnabled
      ? await this.compress(data)
      : data;

    // Upload
    const result = await this.provider!.uploadFile(
      item.localPath,
      item.remotePath,
      uploadData
    );

    // Update item
    item.remoteHash = result.hash;
    item.remoteModified = result.modified;
    item.status = 'synced';
  }

  private async downloadItem(item: SyncItem): Promise<void> {
    this.setStatus('downloading');

    // Download
    let data = await this.provider!.downloadFile(item.remotePath);

    // Decompress if needed
    if (this.config?.compressionEnabled) {
      data = await this.decompress(data);
    }

    // Write local file
    await this.writeLocalFile(item.localPath, data);

    // Update hash
    item.localHash = item.remoteHash;
    item.localModified = item.remoteModified;
    item.status = 'synced';
  }

  private async processOfflineQueue(result: SyncResult): Promise<void> {
    const queue = [...this.offlineQueue];
    this.offlineQueue = [];

    for (const entry of queue) {
      try {
        if (entry.action === 'upload') {
          await this.uploadItem(entry.item);
          result.uploaded++;
        } else if (entry.action === 'download') {
          await this.downloadItem(entry.item);
          result.downloaded++;
        } else if (entry.action === 'delete') {
          await this.provider!.deleteFile(entry.item.remotePath);
        }
      } catch (error) {
        // Re-queue failed items
        this.offlineQueue.push(entry);
        result.errors.push({
          itemId: entry.item.id,
          error: String(error),
          retryable: true
        });
      }
    }
  }

  // ============ Conflict Resolution ============

  async resolveConflict(
    conflict: SyncConflict,
    resolution: ConflictResolution
  ): Promise<boolean> {
    const item = this.syncItems.get(conflict.itemId);
    if (!item) return false;

    switch (resolution) {
      case 'local':
        // Keep local version, upload
        await this.uploadItem(item);
        break;

      case 'remote':
        // Keep remote version, download
        await this.downloadItem(item);
        break;

      case 'merge':
        // Attempt merge (for compatible formats)
        await this.mergeVersions(item);
        break;

      case 'manual':
        // User handles manually
        return false;
    }

    conflict.resolved = true;
    conflict.resolution = resolution;
    return true;
  }

  private async mergeVersions(item: SyncItem): Promise<void> {
    // Download remote
    const remoteData = await this.provider!.downloadFile(item.remotePath);
    const localData = await this.readLocalFile(item.localPath);

    // Simple merge for JSON files
    if (item.localPath.endsWith('.json')) {
      try {
        const localObj = JSON.parse(new TextDecoder().decode(localData));
        const remoteObj = JSON.parse(new TextDecoder().decode(remoteData));

        // Deep merge
        const merged = this.deepMerge(remoteObj, localObj);
        const mergedData = new TextEncoder().encode(JSON.stringify(merged, null, 2));

        await this.writeLocalFile(item.localPath, mergedData.buffer as ArrayBuffer);
        await this.uploadItem(item);
      } catch {
        throw new Error('Merge failed - incompatible data');
      }
    } else {
      throw new Error('Merge not supported for this file type');
    }
  }

  private deepMerge(target: Record<string, unknown>, source: Record<string, unknown>): Record<string, unknown> {
    const result = { ...target };

    for (const key of Object.keys(source)) {
      if (
        source[key] &&
        typeof source[key] === 'object' &&
        !Array.isArray(source[key]) &&
        target[key] &&
        typeof target[key] === 'object'
      ) {
        result[key] = this.deepMerge(
          target[key] as Record<string, unknown>,
          source[key] as Record<string, unknown>
        );
      } else {
        result[key] = source[key];
      }
    }

    return result;
  }

  // ============ File Tracking ============

  trackFile(localPath: string, remotePath: string): SyncItem {
    const id = this.generateId();
    const item: SyncItem = {
      id,
      localPath,
      remotePath,
      localHash: '',
      remoteHash: '',
      localModified: Date.now(),
      remoteModified: 0,
      size: 0,
      status: 'new'
    };

    this.syncItems.set(id, item);
    this.pendingChanges.push(item);

    return item;
  }

  untrackFile(itemId: string): boolean {
    return this.syncItems.delete(itemId);
  }

  markModified(itemId: string): void {
    const item = this.syncItems.get(itemId);
    if (item) {
      item.status = 'modified';
      item.localModified = Date.now();
      this.pendingChanges.push(item);
    }
  }

  markDeleted(itemId: string): void {
    const item = this.syncItems.get(itemId);
    if (item) {
      item.status = 'deleted';
      this.pendingChanges.push(item);
    }
  }

  // ============ Status ============

  getStatus(): SyncStatus {
    return this.status;
  }

  private setStatus(status: SyncStatus): void {
    this.status = status;
    for (const listener of this.listeners) {
      listener(status);
    }
  }

  onStatusChange(callback: (status: SyncStatus) => void): () => void {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  getSyncItems(): SyncItem[] {
    return Array.from(this.syncItems.values());
  }

  getPendingChanges(): SyncItem[] {
    return [...this.pendingChanges];
  }

  async getQuota(): Promise<StorageQuota | null> {
    if (!this.provider?.isConnected()) return null;
    return this.provider.getQuota();
  }

  // ============ Utilities ============

  private generateId(): string {
    return `sync_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  private remoteToLocalPath(remotePath: string): string {
    // Convert remote path to local path
    // This would be implemented based on project structure
    return remotePath.replace(/^\//, '');
  }

  private async readLocalFile(path: string): Promise<ArrayBuffer> {
    // In browser, use IndexedDB or File System Access API
    // This is a placeholder implementation
    const response = await fetch(path);
    return response.arrayBuffer();
  }

  private async writeLocalFile(_path: string, _data: ArrayBuffer): Promise<void> {
    // In browser, use IndexedDB or File System Access API
    // This is a placeholder implementation
  }

  private async compress(data: ArrayBuffer): Promise<ArrayBuffer> {
    // Use CompressionStream if available
    if ('CompressionStream' in window) {
      const cs = new CompressionStream('gzip');
      const writer = cs.writable.getWriter();
      writer.write(new Uint8Array(data));
      writer.close();

      const reader = cs.readable.getReader();
      const chunks: Uint8Array[] = [];

      let done = false;
      while (!done) {
        const result = await reader.read();
        done = result.done;
        if (result.value) {
          chunks.push(result.value);
        }
      }

      const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
      const result = new Uint8Array(totalLength);
      let offset = 0;
      for (const chunk of chunks) {
        result.set(chunk, offset);
        offset += chunk.length;
      }

      return result.buffer as ArrayBuffer;
    }

    return data;
  }

  private async decompress(data: ArrayBuffer): Promise<ArrayBuffer> {
    if ('DecompressionStream' in window) {
      const ds = new DecompressionStream('gzip');
      const writer = ds.writable.getWriter();
      writer.write(new Uint8Array(data));
      writer.close();

      const reader = ds.readable.getReader();
      const chunks: Uint8Array[] = [];

      let done = false;
      while (!done) {
        const result = await reader.read();
        done = result.done;
        if (result.value) {
          chunks.push(result.value);
        }
      }

      const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
      const result = new Uint8Array(totalLength);
      let offset = 0;
      for (const chunk of chunks) {
        result.set(chunk, offset);
        offset += chunk.length;
      }

      return result.buffer as ArrayBuffer;
    }

    return data;
  }

  private createErrorResult(error: string): SyncResult {
    return {
      success: false,
      uploaded: 0,
      downloaded: 0,
      conflicts: [],
      errors: [{ itemId: 'sync', error, retryable: false }],
      duration: 0
    };
  }
}

// ============ Backup Manager ============

export class BackupManager {
  private config: BackupConfig;
  private backups: Backup[] = [];
  private backupTimer: number | null = null;
  private storage: ICloudProvider | null = null;

  constructor(config: BackupConfig) {
    this.config = config;
  }

  // ============ Initialization ============

  async initialize(storage: ICloudProvider): Promise<void> {
    this.storage = storage;

    // Load existing backups
    await this.loadBackupIndex();

    // Start auto-backup if enabled
    if (this.config.enabled) {
      this.startAutoBackup();
    }
  }

  dispose(): void {
    this.stopAutoBackup();
  }

  // ============ Auto Backup ============

  private startAutoBackup(): void {
    if (this.backupTimer) return;

    this.backupTimer = window.setInterval(() => {
      this.createBackup();
    }, this.config.interval);
  }

  private stopAutoBackup(): void {
    if (this.backupTimer) {
      clearInterval(this.backupTimer);
      this.backupTimer = null;
    }
  }

  // ============ Backup Operations ============

  async createBackup(): Promise<Backup | null> {
    if (!this.storage?.isConnected()) return null;

    const backup: Backup = {
      id: this.generateBackupId(),
      timestamp: Date.now(),
      size: 0,
      projectId: this.getCurrentProjectId(),
      projectName: this.getCurrentProjectName(),
      version: '1.0.0',
      checksum: ''
    };

    try {
      // Collect project files
      const files = await this.collectProjectFiles();

      // Create backup archive
      const archive = await this.createArchive(files);
      backup.size = archive.byteLength;
      backup.checksum = await this.calculateChecksum(archive);

      // Upload backup
      await this.storage.uploadFile(
        `backup_${backup.id}`,
        `/backups/${backup.projectId}/${backup.id}.rfbak`,
        archive
      );

      // Add to index
      this.backups.push(backup);

      // Cleanup old backups
      await this.cleanupOldBackups();

      // Save index
      await this.saveBackupIndex();

      return backup;
    } catch (error) {
      console.error('Backup failed:', error);
      return null;
    }
  }

  async restoreBackup(backupId: string): Promise<boolean> {
    if (!this.storage?.isConnected()) return false;

    const backup = this.backups.find(b => b.id === backupId);
    if (!backup) return false;

    try {
      // Download backup
      const archive = await this.storage.downloadFile(
        `/backups/${backup.projectId}/${backup.id}.rfbak`
      );

      // Verify checksum
      const checksum = await this.calculateChecksum(archive);
      if (checksum !== backup.checksum) {
        throw new Error('Backup checksum mismatch');
      }

      // Extract archive
      await this.extractArchive(archive);

      return true;
    } catch (error) {
      console.error('Restore failed:', error);
      return false;
    }
  }

  async deleteBackup(backupId: string): Promise<boolean> {
    if (!this.storage?.isConnected()) return false;

    const backup = this.backups.find(b => b.id === backupId);
    if (!backup) return false;

    try {
      await this.storage.deleteFile(
        `/backups/${backup.projectId}/${backup.id}.rfbak`
      );

      this.backups = this.backups.filter(b => b.id !== backupId);
      await this.saveBackupIndex();

      return true;
    } catch {
      return false;
    }
  }

  // ============ Backup Index ============

  private async loadBackupIndex(): Promise<void> {
    if (!this.storage?.isConnected()) return;

    try {
      const data = await this.storage.downloadFile('/backups/index.json');
      const json = new TextDecoder().decode(data);
      this.backups = JSON.parse(json);
    } catch {
      this.backups = [];
    }
  }

  private async saveBackupIndex(): Promise<void> {
    if (!this.storage?.isConnected()) return;

    const json = JSON.stringify(this.backups, null, 2);
    const data = new TextEncoder().encode(json);

    await this.storage.uploadFile(
      'backup_index',
      '/backups/index.json',
      data.buffer as ArrayBuffer
    );
  }

  private async cleanupOldBackups(): Promise<void> {
    // Sort by timestamp descending
    const sorted = [...this.backups].sort((a, b) => b.timestamp - a.timestamp);

    // Keep only maxBackups
    while (sorted.length > this.config.maxBackups) {
      const oldest = sorted.pop();
      if (oldest) {
        await this.deleteBackup(oldest.id);
      }
    }
  }

  // ============ Getters ============

  getBackups(): Backup[] {
    return [...this.backups];
  }

  getBackupsByProject(projectId: string): Backup[] {
    return this.backups.filter(b => b.projectId === projectId);
  }

  getLatestBackup(projectId?: string): Backup | null {
    const filtered = projectId
      ? this.backups.filter(b => b.projectId === projectId)
      : this.backups;

    if (filtered.length === 0) return null;

    return filtered.reduce((latest, backup) =>
      backup.timestamp > latest.timestamp ? backup : latest
    );
  }

  // ============ Utilities ============

  private generateBackupId(): string {
    const date = new Date().toISOString().slice(0, 10).replace(/-/g, '');
    const time = new Date().toISOString().slice(11, 19).replace(/:/g, '');
    return `${date}_${time}_${Math.random().toString(36).substr(2, 6)}`;
  }

  private getCurrentProjectId(): string {
    // Would be connected to project store
    return 'project_1';
  }

  private getCurrentProjectName(): string {
    // Would be connected to project store
    return 'Untitled Project';
  }

  private async collectProjectFiles(): Promise<Map<string, ArrayBuffer>> {
    // Collect all project files
    // This would integrate with project file system
    return new Map();
  }

  private async createArchive(files: Map<string, ArrayBuffer>): Promise<ArrayBuffer> {
    // Create a simple archive format
    // In production, would use proper archive library
    const encoder = new TextEncoder();
    const chunks: Uint8Array[] = [];

    // Header
    const header = {
      version: 1,
      files: Array.from(files.keys()),
      compressed: this.config.compressBackups
    };
    const headerBytes = encoder.encode(JSON.stringify(header) + '\n---\n');
    chunks.push(headerBytes);

    // Files
    for (const [, data] of files) {
      const sizeBytes = new Uint8Array(4);
      new DataView(sizeBytes.buffer).setUint32(0, data.byteLength, true);
      chunks.push(sizeBytes);
      chunks.push(new Uint8Array(data));
    }

    // Combine
    const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
    const result = new Uint8Array(totalLength);
    let offset = 0;
    for (const chunk of chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }

    return result.buffer as ArrayBuffer;
  }

  private async extractArchive(_archive: ArrayBuffer): Promise<void> {
    // Extract archive to project directory
    // This would integrate with project file system
  }

  private async calculateChecksum(data: ArrayBuffer): Promise<string> {
    // Use SubtleCrypto for SHA-256
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  }
}

// ============ Factory ============

export function createSyncEngine(): SyncEngine {
  return new SyncEngine();
}

export function createBackupManager(config: Partial<BackupConfig> = {}): BackupManager {
  const defaultConfig: BackupConfig = {
    enabled: true,
    interval: 15 * 60 * 1000, // 15 minutes
    maxBackups: 10,
    includeAudio: false,
    compressBackups: true
  };

  return new BackupManager({ ...defaultConfig, ...config });
}
