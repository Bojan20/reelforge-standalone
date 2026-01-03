/**
 * ReelForge Browser Hook
 *
 * State management for file browser:
 * - Folder tree state
 * - Selection
 * - Audio preview
 * - Favorites persistence
 *
 * @module browser/useBrowser
 */

import { useState, useCallback, useMemo, useRef, useEffect } from 'react';
import type { FileNode } from './FileBrowser';

// ============ Types ============

export interface UseBrowserOptions {
  /** Initial root folders */
  initialRoots?: FileNode[];
  /** Storage key for favorites */
  favoritesKey?: string;
  /** Audio context for preview */
  audioContext?: AudioContext;
  /** On file import */
  onImport?: (file: FileNode) => void;
}

export interface UseBrowserReturn {
  /** Root folders */
  roots: FileNode[];
  /** Selected file */
  selectedFile: FileNode | null;
  /** Currently previewing file */
  previewingFile: FileNode | null;
  /** Is preview playing */
  isPreviewPlaying: boolean;
  /** Select a file */
  selectFile: (file: FileNode) => void;
  /** Open/import a file */
  openFile: (file: FileNode) => void;
  /** Toggle folder expand */
  toggleExpand: (folder: FileNode) => void;
  /** Toggle preview playback */
  togglePreview: (file: FileNode) => void;
  /** Stop preview */
  stopPreview: () => void;
  /** Toggle favorite */
  toggleFavorite: (file: FileNode) => void;
  /** Add root folder */
  addRootFolder: (folder: FileNode) => void;
  /** Remove root folder */
  removeRootFolder: (folderId: string) => void;
  /** Refresh folder contents */
  refreshFolder: (folderId: string, children: FileNode[]) => void;
  /** Set all roots */
  setRoots: (roots: FileNode[]) => void;
  /** Get favorites */
  favorites: Set<string>;
}

// ============ Helpers ============

function updateNodeInTree(
  nodes: FileNode[],
  nodeId: string,
  updater: (node: FileNode) => FileNode
): FileNode[] {
  return nodes.map((node) => {
    if (node.id === nodeId) {
      return updater(node);
    }
    if (node.children) {
      return {
        ...node,
        children: updateNodeInTree(node.children, nodeId, updater),
      };
    }
    return node;
  });
}

/** Find a node by ID in the tree */
export function findNodeInTree(nodes: FileNode[], nodeId: string): FileNode | null {
  for (const node of nodes) {
    if (node.id === nodeId) return node;
    if (node.children) {
      const found = findNodeInTree(node.children, nodeId);
      if (found) return found;
    }
  }
  return null;
}

// ============ Hook ============

export function useBrowser(options: UseBrowserOptions = {}): UseBrowserReturn {
  const {
    initialRoots = [],
    favoritesKey = 'rf-browser-favorites',
    audioContext,
    onImport,
  } = options;

  // State
  const [roots, setRoots] = useState<FileNode[]>(initialRoots);
  const [selectedFile, setSelectedFile] = useState<FileNode | null>(null);
  const [previewingFile, setPreviewingFile] = useState<FileNode | null>(null);
  const [isPreviewPlaying, setIsPreviewPlaying] = useState(false);

  // Favorites from localStorage
  const [favorites, setFavorites] = useState<Set<string>>(() => {
    try {
      const stored = localStorage.getItem(favoritesKey);
      return stored ? new Set(JSON.parse(stored)) : new Set();
    } catch {
      return new Set();
    }
  });

  // Audio refs
  const audioBufferRef = useRef<AudioBuffer | null>(null);
  const sourceNodeRef = useRef<AudioBufferSourceNode | null>(null);

  // Save favorites to localStorage
  useEffect(() => {
    localStorage.setItem(favoritesKey, JSON.stringify([...favorites]));
  }, [favorites, favoritesKey]);

  // Apply favorites to tree
  const rootsWithFavorites = useMemo(() => {
    const applyFavorites = (nodes: FileNode[]): FileNode[] => {
      return nodes.map((node) => ({
        ...node,
        isFavorite: favorites.has(node.id),
        children: node.children ? applyFavorites(node.children) : undefined,
      }));
    };
    return applyFavorites(roots);
  }, [roots, favorites]);

  // Select file
  const selectFile = useCallback((file: FileNode) => {
    setSelectedFile(file);
  }, []);

  // Open/import file
  const openFile = useCallback(
    (file: FileNode) => {
      if (file.type === 'folder') {
        // Toggle expand for folders
        setRoots((prev) =>
          updateNodeInTree(prev, file.id, (node) => ({
            ...node,
            isExpanded: !node.isExpanded,
          }))
        );
      } else {
        // Import file
        onImport?.(file);
      }
    },
    [onImport]
  );

  // Toggle folder expand
  const toggleExpand = useCallback((folder: FileNode) => {
    setRoots((prev) =>
      updateNodeInTree(prev, folder.id, (node) => ({
        ...node,
        isExpanded: !node.isExpanded,
      }))
    );
  }, []);

  // Stop current preview
  const stopPreview = useCallback(() => {
    if (sourceNodeRef.current) {
      try {
        sourceNodeRef.current.stop();
      } catch {
        // Already stopped
      }
      sourceNodeRef.current.disconnect();
      sourceNodeRef.current = null;
    }
    setIsPreviewPlaying(false);
  }, []);

  // Toggle preview
  const togglePreview = useCallback(
    async (file: FileNode) => {
      // If same file, toggle play/stop
      if (previewingFile?.id === file.id) {
        if (isPreviewPlaying) {
          stopPreview();
        } else {
          // Resume play (would need to track position)
          // For simplicity, restart from beginning
          if (audioBufferRef.current && audioContext) {
            const source = audioContext.createBufferSource();
            source.buffer = audioBufferRef.current;
            source.connect(audioContext.destination);
            source.onended = () => {
              setIsPreviewPlaying(false);
            };
            source.start();
            sourceNodeRef.current = source;
            setIsPreviewPlaying(true);
          }
        }
        return;
      }

      // Different file, stop current and load new
      stopPreview();
      setPreviewingFile(file);

      if (!audioContext || file.type !== 'audio') return;

      try {
        // Load audio file
        const response = await fetch(file.path);
        const arrayBuffer = await response.arrayBuffer();
        const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

        audioBufferRef.current = audioBuffer;

        // Play
        const source = audioContext.createBufferSource();
        source.buffer = audioBuffer;
        source.connect(audioContext.destination);
        source.onended = () => {
          setIsPreviewPlaying(false);
        };
        source.start();
        sourceNodeRef.current = source;
        setIsPreviewPlaying(true);
      } catch (error) {
        console.error('Failed to load audio for preview:', error);
        setPreviewingFile(null);
      }
    },
    [previewingFile, isPreviewPlaying, audioContext, stopPreview]
  );

  // Toggle favorite
  const toggleFavorite = useCallback((file: FileNode) => {
    setFavorites((prev) => {
      const next = new Set(prev);
      if (next.has(file.id)) {
        next.delete(file.id);
      } else {
        next.add(file.id);
      }
      return next;
    });
  }, []);

  // Add root folder
  const addRootFolder = useCallback((folder: FileNode) => {
    setRoots((prev) => [...prev, { ...folder, isExpanded: true }]);
  }, []);

  // Remove root folder
  const removeRootFolder = useCallback((folderId: string) => {
    setRoots((prev) => prev.filter((r) => r.id !== folderId));
  }, []);

  // Refresh folder contents
  const refreshFolder = useCallback((folderId: string, children: FileNode[]) => {
    setRoots((prev) =>
      updateNodeInTree(prev, folderId, (node) => ({
        ...node,
        children,
      }))
    );
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      stopPreview();
    };
  }, [stopPreview]);

  return useMemo(
    () => ({
      roots: rootsWithFavorites,
      selectedFile,
      previewingFile,
      isPreviewPlaying,
      selectFile,
      openFile,
      toggleExpand,
      togglePreview,
      stopPreview,
      toggleFavorite,
      addRootFolder,
      removeRootFolder,
      refreshFolder,
      setRoots,
      favorites,
    }),
    [
      rootsWithFavorites,
      selectedFile,
      previewingFile,
      isPreviewPlaying,
      selectFile,
      openFile,
      toggleExpand,
      togglePreview,
      stopPreview,
      toggleFavorite,
      addRootFolder,
      removeRootFolder,
      refreshFolder,
      favorites,
    ]
  );
}

export default useBrowser;
