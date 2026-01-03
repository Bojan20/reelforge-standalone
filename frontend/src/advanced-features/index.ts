/**
 * ReelForge Advanced Features
 *
 * Performance monitoring, advanced export, cloud sync, and collaboration.
 *
 * @module advanced-features
 */

// Performance Monitoring
export {
  PerformanceMonitor,
  formatBytes,
  formatLatency,
  getHealthColor,
  getCpuColor,
  type CPUMetrics,
  type MemoryMetrics,
  type LatencyMetrics,
  type BufferMetrics,
  type PluginMetrics,
  type PerformanceSnapshot,
  type PerformanceAlert
} from './PerformanceMonitor';

// Advanced Export
export {
  AdvancedExport,
  downloadBlob,
  downloadAsZip,
  PLATFORM_PRESETS,
  type ExportFormat,
  type BitDepth,
  type SampleRate,
  type ExportSettings,
  type StemExportConfig,
  type MetadataConfig,
  type PlatformPreset,
  type BatchExportJob,
  type ExportProgress,
  type ProgressCallback,
  type ExportEvent
} from './AdvancedExport';

// Cloud Sync
export {
  SyncEngine,
  BackupManager,
  createSyncEngine,
  createBackupManager,
  type CloudProvider,
  type SyncStatus,
  type ConflictResolution,
  type CloudConfig,
  type CloudCredentials,
  type SyncItem,
  type SyncResult,
  type SyncConflict,
  type SyncError,
  type BackupConfig,
  type Backup,
  type ICloudProvider,
  type RemoteFile,
  type StorageQuota
} from './CloudSync';

// Collaboration System
export {
  CollaborationClient,
  SessionManager,
  createCollaborationClient,
  createSessionManager,
  getUserColor,
  generateUserColor,
  type ConnectionStatus,
  type UserRole,
  type EditLockType,
  type CollaborationConfig,
  type User,
  type UserPresence,
  type CursorPosition,
  type Selection,
  type Viewport,
  type EditLock,
  type CollaborationSession,
  type OperationType,
  type Operation,
  type OperationResult,
  type ChatMessage
} from './CollaborationSystem';
