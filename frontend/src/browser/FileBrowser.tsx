/**
 * ReelForge File Browser
 *
 * Audio file browser with:
 * - Folder tree navigation
 * - Audio file preview
 * - Waveform thumbnails
 * - Drag to timeline
 * - Favorites/bookmarks
 *
 * @module browser/FileBrowser
 */

import { useState, useCallback, useMemo, useRef } from 'react';
import './FileBrowser.css';

// ============ Types ============

export interface FileNode {
  id: string;
  name: string;
  path: string;
  type: 'folder' | 'audio' | 'midi' | 'project' | 'other';
  size?: number;
  duration?: number;
  sampleRate?: number;
  channels?: number;
  bpm?: number;
  key?: string;
  children?: FileNode[];
  isExpanded?: boolean;
  isFavorite?: boolean;
}

export interface FileBrowserProps {
  /** Root nodes */
  roots: FileNode[];
  /** Selected file */
  selectedFile?: FileNode | null;
  /** Currently previewing */
  previewingFile?: FileNode | null;
  /** Is preview playing */
  isPreviewPlaying?: boolean;
  /** On file select */
  onSelect?: (file: FileNode) => void;
  /** On file double click (open/import) */
  onOpen?: (file: FileNode) => void;
  /** On folder expand/collapse */
  onToggleExpand?: (folder: FileNode) => void;
  /** On preview play/stop */
  onPreviewToggle?: (file: FileNode) => void;
  /** On drag start (for timeline drop) */
  onDragStart?: (file: FileNode, e: React.DragEvent) => void;
  /** On favorite toggle */
  onFavoriteToggle?: (file: FileNode) => void;
  /** On refresh */
  onRefresh?: () => void;
  /** On add folder */
  onAddFolder?: () => void;
}

// ============ Constants ============

const FILE_TYPE_ICONS: Record<string, string> = {
  folder: '📁',
  audio: '🎵',
  midi: '🎹',
  project: '📄',
  other: '📎',
};

const AUDIO_EXTENSIONS = ['.wav', '.mp3', '.aiff', '.flac', '.ogg', '.m4a'];
const MIDI_EXTENSIONS = ['.mid', '.midi'];

// ============ Helpers ============

function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, '0')}`;
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function getFileExtension(filename: string): string {
  const lastDot = filename.lastIndexOf('.');
  return lastDot >= 0 ? filename.slice(lastDot).toLowerCase() : '';
}

/** Get file type from filename extension */
export function getFileTypeFromName(filename: string): FileNode['type'] {
  const ext = getFileExtension(filename);
  if (AUDIO_EXTENSIONS.includes(ext)) return 'audio';
  if (MIDI_EXTENSIONS.includes(ext)) return 'midi';
  if (ext === '.rfproj') return 'project';
  return 'other';
}

// ============ FileTreeItem Component ============

interface FileTreeItemProps {
  node: FileNode;
  depth: number;
  selectedId?: string;
  previewingId?: string;
  isPreviewPlaying?: boolean;
  onSelect: (node: FileNode) => void;
  onOpen: (node: FileNode) => void;
  onToggleExpand: (node: FileNode) => void;
  onPreviewToggle: (node: FileNode) => void;
  onDragStart: (node: FileNode, e: React.DragEvent) => void;
  onFavoriteToggle: (node: FileNode) => void;
}

function FileTreeItem({
  node,
  depth,
  selectedId,
  previewingId,
  isPreviewPlaying,
  onSelect,
  onOpen,
  onToggleExpand,
  onPreviewToggle,
  onDragStart,
  onFavoriteToggle,
}: FileTreeItemProps) {
  const isSelected = node.id === selectedId;
  const isPreviewing = node.id === previewingId;
  const isFolder = node.type === 'folder';
  const isAudio = node.type === 'audio';

  const handleClick = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      if (isFolder) {
        onToggleExpand(node);
      }
      onSelect(node);
    },
    [node, isFolder, onSelect, onToggleExpand]
  );

  const handleDoubleClick = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      onOpen(node);
    },
    [node, onOpen]
  );

  const handleDragStart = useCallback(
    (e: React.DragEvent) => {
      if (!isFolder) {
        onDragStart(node, e);
      }
    },
    [node, isFolder, onDragStart]
  );

  return (
    <>
      <div
        className={`file-browser__item ${isSelected ? 'selected' : ''} ${
          isPreviewing ? 'previewing' : ''
        }`}
        style={{ paddingLeft: 12 + depth * 16 }}
        onClick={handleClick}
        onDoubleClick={handleDoubleClick}
        draggable={!isFolder}
        onDragStart={handleDragStart}
      >
        {/* Expand arrow for folders */}
        {isFolder ? (
          <span
            className={`file-browser__expand ${node.isExpanded ? 'expanded' : ''}`}
          >
            ▶
          </span>
        ) : (
          <span className="file-browser__expand-placeholder" />
        )}

        {/* Icon */}
        <span className="file-browser__icon">
          {FILE_TYPE_ICONS[node.type]}
        </span>

        {/* Name */}
        <span className="file-browser__name">{node.name}</span>

        {/* Duration for audio */}
        {isAudio && node.duration && (
          <span className="file-browser__duration">
            {formatDuration(node.duration)}
          </span>
        )}

        {/* BPM if detected */}
        {node.bpm && (
          <span className="file-browser__bpm">{node.bpm} BPM</span>
        )}

        {/* Actions */}
        <div className="file-browser__actions">
          {isAudio && (
            <button
              className={`file-browser__action-btn ${
                isPreviewing && isPreviewPlaying ? 'playing' : ''
              }`}
              onClick={(e) => {
                e.stopPropagation();
                onPreviewToggle(node);
              }}
              title="Preview"
            >
              {isPreviewing && isPreviewPlaying ? '⏹' : '▶'}
            </button>
          )}
          <button
            className={`file-browser__action-btn ${node.isFavorite ? 'favorite' : ''}`}
            onClick={(e) => {
              e.stopPropagation();
              onFavoriteToggle(node);
            }}
            title="Favorite"
          >
            {node.isFavorite ? '★' : '☆'}
          </button>
        </div>
      </div>

      {/* Children */}
      {isFolder && node.isExpanded && node.children && (
        <div className="file-browser__children">
          {node.children.map((child) => (
            <FileTreeItem
              key={child.id}
              node={child}
              depth={depth + 1}
              selectedId={selectedId}
              previewingId={previewingId}
              isPreviewPlaying={isPreviewPlaying}
              onSelect={onSelect}
              onOpen={onOpen}
              onToggleExpand={onToggleExpand}
              onPreviewToggle={onPreviewToggle}
              onDragStart={onDragStart}
              onFavoriteToggle={onFavoriteToggle}
            />
          ))}
        </div>
      )}
    </>
  );
}

// ============ Main Component ============

export function FileBrowser({
  roots,
  selectedFile,
  previewingFile,
  isPreviewPlaying = false,
  onSelect,
  onOpen,
  onToggleExpand,
  onPreviewToggle,
  onDragStart,
  onFavoriteToggle,
  onRefresh,
  onAddFolder,
}: FileBrowserProps) {
  const [search, setSearch] = useState('');
  const [viewMode, setViewMode] = useState<'tree' | 'list'>('tree');
  const [showFavorites, setShowFavorites] = useState(false);
  const [sortBy, setSortBy] = useState<'name' | 'date' | 'size' | 'duration'>('name');

  const searchInputRef = useRef<HTMLInputElement>(null);

  // Flatten tree for search/list view
  const flattenTree = useCallback((nodes: FileNode[]): FileNode[] => {
    const result: FileNode[] = [];
    const traverse = (node: FileNode) => {
      if (node.type !== 'folder') {
        result.push(node);
      }
      if (node.children) {
        node.children.forEach(traverse);
      }
    };
    nodes.forEach(traverse);
    return result;
  }, []);

  // Filter and sort files
  const displayedFiles = useMemo(() => {
    if (viewMode === 'tree' && !search && !showFavorites) {
      return roots;
    }

    let files = flattenTree(roots);

    // Filter by search
    if (search) {
      const lowerSearch = search.toLowerCase();
      files = files.filter(
        (f) =>
          f.name.toLowerCase().includes(lowerSearch) ||
          f.path.toLowerCase().includes(lowerSearch)
      );
    }

    // Filter by favorites
    if (showFavorites) {
      files = files.filter((f) => f.isFavorite);
    }

    // Sort
    files.sort((a, b) => {
      switch (sortBy) {
        case 'name':
          return a.name.localeCompare(b.name);
        case 'size':
          return (b.size || 0) - (a.size || 0);
        case 'duration':
          return (b.duration || 0) - (a.duration || 0);
        default:
          return a.name.localeCompare(b.name);
      }
    });

    return files;
  }, [roots, search, showFavorites, sortBy, viewMode, flattenTree]);

  // Handlers
  const handleSelect = useCallback(
    (node: FileNode) => {
      onSelect?.(node);
    },
    [onSelect]
  );

  const handleOpen = useCallback(
    (node: FileNode) => {
      onOpen?.(node);
    },
    [onOpen]
  );

  const handleToggleExpand = useCallback(
    (node: FileNode) => {
      onToggleExpand?.(node);
    },
    [onToggleExpand]
  );

  const handlePreviewToggle = useCallback(
    (node: FileNode) => {
      onPreviewToggle?.(node);
    },
    [onPreviewToggle]
  );

  const handleDragStart = useCallback(
    (node: FileNode, e: React.DragEvent) => {
      onDragStart?.(node, e);
    },
    [onDragStart]
  );

  const handleFavoriteToggle = useCallback(
    (node: FileNode) => {
      onFavoriteToggle?.(node);
    },
    [onFavoriteToggle]
  );

  // Render tree or list
  const isListView = viewMode === 'list' || search || showFavorites;

  return (
    <div className="file-browser">
      {/* Header */}
      <div className="file-browser__header">
        <h3>Browser</h3>
        <div className="file-browser__header-actions">
          {onAddFolder && (
            <button
              className="file-browser__header-btn"
              onClick={onAddFolder}
              title="Add folder"
            >
              +
            </button>
          )}
          {onRefresh && (
            <button
              className="file-browser__header-btn"
              onClick={onRefresh}
              title="Refresh"
            >
              ↻
            </button>
          )}
        </div>
      </div>

      {/* Toolbar */}
      <div className="file-browser__toolbar">
        <input
          ref={searchInputRef}
          type="text"
          className="file-browser__search"
          placeholder="Search files..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <button
          className={`file-browser__tool-btn ${showFavorites ? 'active' : ''}`}
          onClick={() => setShowFavorites(!showFavorites)}
          title="Show favorites"
        >
          ★
        </button>
        <button
          className={`file-browser__tool-btn ${viewMode === 'list' ? 'active' : ''}`}
          onClick={() => setViewMode(viewMode === 'tree' ? 'list' : 'tree')}
          title="Toggle view"
        >
          ≡
        </button>
      </div>

      {/* Sort bar (list view only) */}
      {isListView && (
        <div className="file-browser__sort-bar">
          <span>Sort:</span>
          <select
            value={sortBy}
            onChange={(e) => setSortBy(e.target.value as typeof sortBy)}
          >
            <option value="name">Name</option>
            <option value="size">Size</option>
            <option value="duration">Duration</option>
          </select>
        </div>
      )}

      {/* File list/tree */}
      <div className="file-browser__content">
        {isListView ? (
          // List view
          <div className="file-browser__list">
            {(displayedFiles as FileNode[]).map((file) => (
              <div
                key={file.id}
                className={`file-browser__list-item ${
                  selectedFile?.id === file.id ? 'selected' : ''
                } ${previewingFile?.id === file.id ? 'previewing' : ''}`}
                onClick={() => handleSelect(file)}
                onDoubleClick={() => handleOpen(file)}
                draggable
                onDragStart={(e) => handleDragStart(file, e)}
              >
                <span className="file-browser__icon">
                  {FILE_TYPE_ICONS[file.type]}
                </span>
                <span className="file-browser__name">{file.name}</span>
                {file.duration && (
                  <span className="file-browser__duration">
                    {formatDuration(file.duration)}
                  </span>
                )}
                {file.size && (
                  <span className="file-browser__size">
                    {formatSize(file.size)}
                  </span>
                )}
                <div className="file-browser__actions">
                  {file.type === 'audio' && (
                    <button
                      className={`file-browser__action-btn ${
                        previewingFile?.id === file.id && isPreviewPlaying
                          ? 'playing'
                          : ''
                      }`}
                      onClick={(e) => {
                        e.stopPropagation();
                        handlePreviewToggle(file);
                      }}
                    >
                      {previewingFile?.id === file.id && isPreviewPlaying
                        ? '⏹'
                        : '▶'}
                    </button>
                  )}
                  <button
                    className={`file-browser__action-btn ${
                      file.isFavorite ? 'favorite' : ''
                    }`}
                    onClick={(e) => {
                      e.stopPropagation();
                      handleFavoriteToggle(file);
                    }}
                  >
                    {file.isFavorite ? '★' : '☆'}
                  </button>
                </div>
              </div>
            ))}
            {displayedFiles.length === 0 && (
              <div className="file-browser__empty">No files found</div>
            )}
          </div>
        ) : (
          // Tree view
          <div className="file-browser__tree">
            {roots.map((root) => (
              <FileTreeItem
                key={root.id}
                node={root}
                depth={0}
                selectedId={selectedFile?.id}
                previewingId={previewingFile?.id}
                isPreviewPlaying={isPreviewPlaying}
                onSelect={handleSelect}
                onOpen={handleOpen}
                onToggleExpand={handleToggleExpand}
                onPreviewToggle={handlePreviewToggle}
                onDragStart={handleDragStart}
                onFavoriteToggle={handleFavoriteToggle}
              />
            ))}
            {roots.length === 0 && (
              <div className="file-browser__empty">
                No folders added
                <button
                  className="file-browser__add-folder-btn"
                  onClick={onAddFolder}
                >
                  Add Folder
                </button>
              </div>
            )}
          </div>
        )}
      </div>

      {/* File info panel */}
      {selectedFile && selectedFile.type !== 'folder' && (
        <div className="file-browser__info">
          <div className="file-browser__info-name">{selectedFile.name}</div>
          <div className="file-browser__info-details">
            {selectedFile.type === 'audio' && (
              <>
                {selectedFile.duration && (
                  <span>Duration: {formatDuration(selectedFile.duration)}</span>
                )}
                {selectedFile.sampleRate && (
                  <span>{selectedFile.sampleRate / 1000}kHz</span>
                )}
                {selectedFile.channels && (
                  <span>{selectedFile.channels === 1 ? 'Mono' : 'Stereo'}</span>
                )}
                {selectedFile.bpm && <span>{selectedFile.bpm} BPM</span>}
                {selectedFile.key && <span>Key: {selectedFile.key}</span>}
              </>
            )}
            {selectedFile.size && <span>{formatSize(selectedFile.size)}</span>}
          </div>
        </div>
      )}
    </div>
  );
}

export default FileBrowser;
