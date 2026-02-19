mod config;
mod diffpack;
mod gitops;
mod logging;
mod server;
mod state;
mod watcher;

use crate::config::AccConfig;
use crate::logging::init_tracing;
use crate::server::run_server;
use crate::watcher::start_watcher;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    init_tracing();

    let cfg = AccConfig::load()?;
    tracing::info!(listen_addr=%cfg.listen_addr, repo_root=%cfg.repo_root.display(), "ACC boot");

    if let Err(e) = start_watcher(cfg.clone()).await {
        tracing::error!(error=%e, "Watcher failed to start");
    }

    run_server(cfg).await?;
    Ok(())
}
