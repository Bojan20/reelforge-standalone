use crate::config::AccConfig;
use notify::{Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use std::{path::{Path, PathBuf}, sync::Arc};
use tokio::sync::mpsc;

pub async fn start_watcher(cfg: AccConfig) -> Result<(), String> {
    let cfg = Arc::new(cfg);

    let (tx, mut rx) = mpsc::channel::<(EventKind, PathBuf)>(512);

    let mut watcher: RecommendedWatcher =
        notify::recommended_watcher(move |res: notify::Result<Event>| {
            if let Ok(event) = res {
                if let Some(path) = event.paths.get(0).cloned() {
                    let kind = event.kind.clone();
                    let _ = tx.blocking_send((kind, path));
                }
            }
        })
        .map_err(|e| format!("notify watcher init failed: {e}"))?;

    for pattern_root in &cfg.watch {
        let root = glob_root(pattern_root);
        let abs = cfg.repo_root.join(root);
        if abs.exists() {
            watcher
                .watch(&abs, RecursiveMode::Recursive)
                .map_err(|e| format!("watch failed for {abs:?}: {e}"))?;
            tracing::info!(path=%abs.display(), "watching");
        } else {
            tracing::warn!(path=%abs.display(), "watch root does not exist yet");
        }
    }

    tokio::spawn(async move {
        let _watcher_keepalive = watcher;

        while let Some((kind, abs_path)) = rx.recv().await {
            let rel = abs_path.strip_prefix(&cfg.repo_root).unwrap_or(&abs_path).to_path_buf();
            if cfg.is_ignored(Path::new(&rel)) {
                continue;
            }
            tracing::debug!(event=?kind, file=%rel.display(), "fs change");
        }
    });

    Ok(())
}

fn glob_root(p: &str) -> &str {
    p.split(&['*', '?', '[', '{'][..])
        .next()
        .unwrap_or(p)
        .trim_end_matches('/')
}
