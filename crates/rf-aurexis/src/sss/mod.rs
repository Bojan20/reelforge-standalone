pub mod project_isolation;
pub mod config_diff;
pub mod auto_regression;
pub mod burn_test;

pub use project_isolation::{
    ProjectManifest, ProjectConfig, ProjectIsolation, IsolatedProject,
};
pub use config_diff::{
    ConfigDiff, DiffEntry, DiffType, RiskLevel, ConfigDiffEngine,
};
pub use auto_regression::{
    AutoRegression, RegressionConfig, RegressionResult, RegressionRun,
    RegressionStatus, StressScenario,
};
pub use burn_test::{
    BurnTest, BurnTestConfig, BurnTestResult, BurnTestMetrics,
    DriftMetric, TrendDirection,
};
