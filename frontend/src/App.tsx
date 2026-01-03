import { lazy, Suspense, useState, useEffect, useCallback } from "react";
import { ProjectProvider } from "./project/ProjectContext";
import { PreviewMixProvider } from "./core/PreviewMixContext";
import { InsertSelectionProvider, PluginEditorDrawer } from "./plugin";
import ErrorBoundary from "./components/ErrorBoundary";
import WelcomeScreen, { type RecentProject } from "./components/WelcomeScreen";
import { clearAudioDB } from "./utils/audioStorage";
import "./components/ErrorBoundary.css";

// Lazy load large components for better initial load time
const EventsPage = lazy(() => import("./EventsPage"));
const LayoutDemo = lazy(() => import("./LayoutDemo"));
const ComponentShowcase = lazy(() => import("./demo/ComponentShowcase"));
const UIShowcase = lazy(() => import("./demo/UIShowcase"));

// Loading fallback component
function LoadingFallback() {
  return (
    <div className="rf-loading-fallback">
      <div className="rf-loading-spinner" />
      <div className="rf-loading-text">Loading ReelForge...</div>
    </div>
  );
}

// Demo recent projects (would come from storage in production)
const DEMO_RECENT_PROJECTS: RecentProject[] = [
  {
    id: 'demo-1',
    name: 'Wrath of Olympus',
    path: '~/Projects/wrath-of-olympus.rfproj',
    lastOpened: new Date(Date.now() - 1000 * 60 * 60 * 2), // 2 hours ago
  },
  {
    id: 'demo-2',
    name: 'Slot Game Audio Pack',
    path: '~/Projects/slot-audio-pack.rfproj',
    lastOpened: new Date(Date.now() - 1000 * 60 * 60 * 24), // Yesterday
  },
  {
    id: 'demo-3',
    name: 'Casino Ambience',
    path: '~/Projects/casino-ambience.rfproj',
    lastOpened: new Date(Date.now() - 1000 * 60 * 60 * 24 * 3), // 3 days ago
  },
];

const App = () => {
  // Check URL for demo modes
  const [viewMode, setViewMode] = useState<'welcome' | 'main' | 'legacy' | 'showcase' | 'ui-showcase'>('welcome');
  const [importedFiles, setImportedFiles] = useState<File[]>([]);
  // Key to force fresh ProjectProvider on New Project
  const [projectKey, setProjectKey] = useState(0);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const layout = params.get('layout');
    const skipWelcome = params.get('skip') === 'welcome';

    if (layout === 'legacy') {
      // Old EventsPage UI
      setViewMode('legacy');
    } else if (layout === 'showcase') {
      // Component Showcase Demo
      setViewMode('showcase');
    } else if (layout === 'ui-showcase') {
      // UI Components Showcase (LIST 2)
      setViewMode('ui-showcase');
    } else if (skipWelcome) {
      // Skip welcome screen
      setViewMode('main');
    } else {
      // Default: show welcome screen
      setViewMode('welcome');
    }
  }, []);

  // Welcome screen handlers
  const handleNewProject = useCallback(async () => {
    // Clear persisted audio files from IndexedDB
    await clearAudioDB();
    // Clear localStorage session (routes, events, audio meta)
    localStorage.removeItem('reelforge_session');
    localStorage.removeItem('reelforge_audio_meta');
    // Increment key to force fresh ProjectProvider (clears all state)
    setProjectKey(k => k + 1);
    setImportedFiles([]);
    setViewMode('main');
  }, []);

  const handleOpenProject = useCallback((path?: string) => {
    console.log('[App] Open Project:', path || 'browse');
    setViewMode('main');
  }, []);

  const handleSelectRecentProject = useCallback((project: RecentProject) => {
    console.log('[App] Select Recent Project:', project.name);
    setViewMode('main');
  }, []);

  const handleImportAudioFiles = useCallback((files: File[]) => {
    console.log('[App] Import Audio Files:', files.map(f => f.name));
    setImportedFiles(files);
  }, []);

  const handleEnterEditor = useCallback(() => {
    setViewMode('main');
  }, []);

  // Welcome Screen - Initial landing page
  if (viewMode === 'welcome') {
    return (
      <ErrorBoundary scope="app" showDetails>
        <WelcomeScreen
          recentProjects={DEMO_RECENT_PROJECTS}
          onNewProject={handleNewProject}
          onOpenProject={handleOpenProject}
          onSelectRecentProject={handleSelectRecentProject}
          onImportAudioFiles={handleImportAudioFiles}
          onEnterEditor={handleEnterEditor}
          version="1.0.0-preview"
        />
      </ErrorBoundary>
    );
  }

  // Component Showcase - Demo of all new components (access via ?layout=showcase)
  if (viewMode === 'showcase') {
    return (
      <ErrorBoundary scope="app" showDetails>
        <Suspense fallback={<LoadingFallback />}>
          <ComponentShowcase />
        </Suspense>
      </ErrorBoundary>
    );
  }

  // UI Showcase - LIST 2 UI components (access via ?layout=ui-showcase)
  if (viewMode === 'ui-showcase') {
    return (
      <ErrorBoundary scope="app" showDetails>
        <Suspense fallback={<LoadingFallback />}>
          <UIShowcase />
        </Suspense>
      </ErrorBoundary>
    );
  }

  // Legacy mode - Old EventsPage UI (access via ?layout=legacy)
  if (viewMode === 'legacy') {
    return (
      <ErrorBoundary scope="app" showDetails>
        <ProjectProvider>
          <PreviewMixProvider>
            <InsertSelectionProvider>
              <Suspense fallback={<LoadingFallback />}>
                <div className="app-root">
                  <EventsPage />
                </div>
              </Suspense>
              <PluginEditorDrawer />
            </InsertSelectionProvider>
          </PreviewMixProvider>
        </ProjectProvider>
      </ErrorBoundary>
    );
  }

  // Default: New LayoutDemo UI with full provider stack
  // Pass imported files if any from welcome screen
  // Note: MasterInsertProvider is added inside LayoutDemo because it needs AudioContext refs
  // Key forces fresh state on New Project (incremented in handleNewProject)
  return (
    <ErrorBoundary scope="app" showDetails>
      <ProjectProvider key={`project-${projectKey}`}>
        <PreviewMixProvider key={`preview-${projectKey}`}>
          <InsertSelectionProvider>
            <Suspense fallback={<LoadingFallback />}>
              <LayoutDemo initialImportedFiles={importedFiles} />
            </Suspense>
            <PluginEditorDrawer />
          </InsertSelectionProvider>
        </PreviewMixProvider>
      </ProjectProvider>
    </ErrorBoundary>
  );
};

export default App;
