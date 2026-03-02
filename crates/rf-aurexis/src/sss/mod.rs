pub mod auto_regression;
pub mod burn_test;
pub mod config_diff;
pub mod project_isolation;

pub use auto_regression::{
    AutoRegression, RegressionConfig, RegressionResult, RegressionRun, RegressionStatus,
    StressScenario,
};
pub use burn_test::{
    BurnTest, BurnTestConfig, BurnTestMetrics, BurnTestResult, DriftMetric, TrendDirection,
};
pub use config_diff::{ConfigDiff, ConfigDiffEngine, DiffEntry, DiffType, RiskLevel};
pub use project_isolation::{IsolatedProject, ProjectConfig, ProjectIsolation, ProjectManifest};
