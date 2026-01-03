import { useState, useCallback } from 'react';
import type { ReelForgeProject } from '../core/types';

export function useProjectHistory(initialProject: ReelForgeProject | null = null) {
  const [history, setHistory] = useState<ReelForgeProject[]>(initialProject ? [initialProject] : []);
  const [historyIndex, setHistoryIndex] = useState<number>(initialProject ? 0 : -1);

  const saveToHistory = useCallback((newProject: ReelForgeProject) => {
    const newHistory = history.slice(0, historyIndex + 1);
    newHistory.push(JSON.parse(JSON.stringify(newProject)));
    if (newHistory.length > 20) {
      newHistory.shift();
      setHistory(newHistory);
      setHistoryIndex(newHistory.length - 1);
    } else {
      setHistory(newHistory);
      setHistoryIndex(newHistory.length - 1);
    }
  }, [history, historyIndex]);

  const undo = useCallback((): ReelForgeProject | null => {
    if (historyIndex > 0) {
      setHistoryIndex(historyIndex - 1);
      return JSON.parse(JSON.stringify(history[historyIndex - 1]));
    }
    return null;
  }, [history, historyIndex]);

  const redo = useCallback((): ReelForgeProject | null => {
    if (historyIndex < history.length - 1) {
      setHistoryIndex(historyIndex + 1);
      return JSON.parse(JSON.stringify(history[historyIndex + 1]));
    }
    return null;
  }, [history, historyIndex]);

  const canUndo = historyIndex > 0;
  const canRedo = historyIndex < history.length - 1;

  const reset = useCallback(() => {
    setHistory([]);
    setHistoryIndex(-1);
  }, []);

  return {
    saveToHistory,
    undo,
    redo,
    canUndo,
    canRedo,
    reset,
    history,
    historyIndex,
  };
}
