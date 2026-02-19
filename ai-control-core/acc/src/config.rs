use globset::{Glob, GlobSet, GlobSetBuilder};
use serde::Deserialize;
use std::{fs, path::{Path, PathBuf}};

#[derive(Debug, Clone, Deserialize)]
pub struct GatesConfig {
    pub run_git_status_clean_before_apply: bool,
    pub run_typecheck: bool,
    pub run_tests: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ProviderToggle {
    pub enabled: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ProvidersConfig {
    pub claude: ProviderToggle,
    pub openai: ProviderToggle,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AccConfigFile {
    pub repo_root: String,
    pub watch: Vec<String>,
    pub ignore: Vec<String>,
    pub locked_paths: Vec<String>,
    pub diffpack_path: String,
    pub history_dir: String,
    pub gates: GatesConfig,
    pub providers: ProvidersConfig,
    pub listen_addr: Option<String>,
}

#[derive(Debug, Clone)]
pub struct AccConfig {
    pub repo_root: PathBuf,
    pub watch: Vec<String>,
    pub ignore: Vec<String>,
    pub locked_paths: Vec<String>,
    pub diffpack_path: PathBuf,
    pub history_dir: PathBuf,
    pub gates: GatesConfig,
    pub providers: ProvidersConfig,
    pub listen_addr: String,
    pub ignore_globset: GlobSet,
    pub locked_globset: GlobSet,
}

impl AccConfig {
    pub fn load() -> Result<Self, String> {
        if let Ok(p) = std::env::var("ACC_CONFIG") {
            let cfg_path = PathBuf::from(p);
            return Self::load_from_path(&cfg_path);
        }

        let cwd = std::env::current_dir().map_err(|e| e.to_string())?;

        let p1 = cwd.join("acc.config.json");
        if p1.exists() {
            return Self::load_from_path(&p1);
        }

        let p2 = cwd.join("ai-control-core").join("acc").join("acc.config.json");
        if p2.exists() {
            return Self::load_from_path(&p2);
        }

        Err(format!(
            "acc.config.json not found. Tried: {:?} and {:?}. You can also set ACC_CONFIG=/path/to/acc.config.json",
            p1, p2
        ))
    }

    pub fn load_from_path(cfg_path: &Path) -> Result<Self, String> {
        let raw = fs::read_to_string(cfg_path).map_err(|e| format!("Failed to read {cfg_path:?}: {e}"))?;
        let file_cfg: AccConfigFile = serde_json::from_str(&raw)
            .map_err(|e| format!("Invalid acc.config.json: {e}"))?;

        let base_dir = cfg_path.parent().unwrap_or_else(|| Path::new("."));
        let repo_root = base_dir.join(&file_cfg.repo_root).canonicalize()
            .map_err(|e| format!("Invalid repo_root path: {e}"))?;

        let diffpack_path = repo_root.join(&file_cfg.diffpack_path);
        let history_dir = repo_root.join(&file_cfg.history_dir);

        let listen_addr = file_cfg.listen_addr.unwrap_or_else(|| "127.0.0.1:8787".to_string());

        let ignore_globset = build_globset(&file_cfg.ignore)?;
        let locked_globset = build_globset(&file_cfg.locked_paths)?;

        Ok(Self {
            repo_root,
            watch: file_cfg.watch,
            ignore: file_cfg.ignore,
            locked_paths: file_cfg.locked_paths,
            diffpack_path,
            history_dir,
            gates: file_cfg.gates,
            providers: file_cfg.providers,
            listen_addr,
            ignore_globset,
            locked_globset,
        })
    }

    pub fn is_ignored(&self, rel_path: &Path) -> bool {
        self.ignore_globset.is_match(rel_path)
    }

    pub fn is_locked(&self, rel_path: &Path) -> bool {
        self.locked_globset.is_match(rel_path)
    }

    pub fn state_dir(&self) -> PathBuf {
        self.repo_root.join("AI_BRAIN").join("state")
    }
}

fn build_globset(patterns: &[String]) -> Result<GlobSet, String> {
    let mut builder = GlobSetBuilder::new();
    for p in patterns {
        let g = Glob::new(p).map_err(|e| format!("Invalid glob {p}: {e}"))?;
        builder.add(g);
    }
    builder.build().map_err(|e| e.to_string())
}
