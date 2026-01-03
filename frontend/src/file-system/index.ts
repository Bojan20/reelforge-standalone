/**
 * ReelForge File System Module
 *
 * Comprehensive file management for professional DAW:
 * - Modern File System Access API
 * - Project archives (.rfproj.zip)
 * - Audio metadata extraction
 * - Auto-save with recovery
 * - Project templates
 *
 * @module file-system
 */

// File System API
export {
  FileSystemAPI,
  FILE_TYPES,
  type FilePickerOptions,
  type FilePickerType,
  type SaveFileOptions,
  type DirectoryPickerOptions,
  type FileEntry,
} from './FileSystemAPI';

// Project Archives
export {
  ProjectArchive,
  generateArchiveFilename,
  formatFileSize,
  type ProjectManifest,
  type AudioFileEntry,
  type MidiFileEntry,
  type MarkerEntry,
  type ArchiveProgress,
} from './ProjectArchive';

// Audio Metadata
export {
  AudioMetadataExtractor,
  audioMetadataExtractor,
  formatDuration,
  formatBPM,
  getAudioFormat,
  type AudioMetadata,
  type BPMResult,
  type KeyResult,
} from './AudioMetadata';

// Auto-Save
export {
  AutoSaveManager,
  formatAutoSaveTime,
  formatDataSize,
  type AutoSaveEntry,
  type AutoSaveConfig,
  type RecoveryInfo,
} from './AutoSave';

// Project Templates
export {
  ProjectTemplateManager,
  BUILT_IN_TEMPLATES,
  getCategoryDisplayName,
  getCategoryIcon,
  type ProjectTemplate,
  type TemplateCategory,
  type TemplateData,
  type TemplateTrack,
  type TemplateBus,
  type TemplateMarker,
} from './ProjectTemplates';

// React Components
export {
  AudioFileBrowser,
  type AudioFileItem,
  type ViewMode,
  type SortBy,
  type SortOrder,
  type AudioFileBrowserProps,
} from './components';
