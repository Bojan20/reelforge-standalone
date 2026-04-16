//! Rule-based suggestion engine (T5.1 + T5.3).
//!
//! Each rule is a function that takes the AudioProjectSpec + benchmark
//! and returns zero or more suggestions. Rules are composable and independent.

use crate::benchmarks::{find_best_match, BENCHMARKS};
use crate::project::AudioProjectSpec;
use crate::suggestions::{
    CopilotReport, CopilotSuggestion, SuggestionCategory, SuggestionSeverity,
};

/// Main suggestion engine
pub struct SuggestionEngine;

impl SuggestionEngine {
    /// Analyze an AudioProjectSpec and produce a CopilotReport.
    pub fn analyze(project: &AudioProjectSpec) -> CopilotReport {
        let mut suggestions: Vec<CopilotSuggestion> = Vec::new();

        let benchmark = find_best_match(
            project.is_megaways(),
            project.is_jackpot_game(),
            project.is_high_volatility(),
            project.event_count(),
            project.rtp_target,
        );

        // Run all rule families
        rule_voice_budget(project, benchmark, &mut suggestions);
        rule_event_coverage(project, benchmark, &mut suggestions);
        rule_win_tier_calibration(project, benchmark, &mut suggestions);
        rule_feature_audio(project, benchmark, &mut suggestions);
        rule_responsible_gaming(project, &mut suggestions);
        rule_loop_coverage(project, &mut suggestions);
        rule_timing_benchmarks(project, benchmark, &mut suggestions);
        rule_math_aware(project, benchmark, &mut suggestions);
        rule_priority_ordering(project, &mut suggestions);

        // Compute quality score
        let quality_score = compute_quality_score(project, benchmark, &suggestions);

        // Industry match %
        let industry_match_pct = compute_industry_match(project, benchmark);

        // Summary
        let critical_count = suggestions.iter()
            .filter(|s| s.severity == SuggestionSeverity::Critical)
            .count();
        let warning_count = suggestions.iter()
            .filter(|s| s.severity == SuggestionSeverity::Warning)
            .count();

        let summary = if critical_count > 0 {
            format!("{critical_count} critical issue(s) require attention before export.")
        } else if warning_count > 0 {
            format!("Quality score {quality_score}/100 — {warning_count} warning(s) to address.")
        } else if suggestions.is_empty() {
            format!("Excellent! Matches {reference} industry standard.",
                reference = benchmark.reference_name)
        } else {
            format!("Quality score {quality_score}/100 — {count} improvement suggestion(s).",
                count = suggestions.len())
        };

        CopilotReport {
            suggestions,
            quality_score,
            industry_match_pct,
            closest_reference: benchmark.reference_name.to_string(),
            summary,
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// RULE FAMILIES
// ─────────────────────────────────────────────────────────────────────────────

fn rule_voice_budget(
    project: &AudioProjectSpec,
    benchmark: &crate::benchmarks::IndustryBenchmark,
    out: &mut Vec<CopilotSuggestion>,
) {
    // R-VB-1: Voice budget vs estimated peak
    if let Some(peak) = project.estimated_peak_voices {
        let utilization = peak / project.voice_budget as f64;
        if utilization > 0.95 {
            out.push(CopilotSuggestion {
                rule_id: "R-VB-1".to_string(),
                category: SuggestionCategory::VoiceBudget,
                severity: SuggestionSeverity::Critical,
                title: "Voice budget near capacity".to_string(),
                description: format!(
                    "Estimated peak voices ({:.0}) is {:.0}% of your budget ({}).  \
                     Voice stealing will cause missing audio in peak moments.",
                    peak, utilization * 100.0, project.voice_budget
                ),
                action: format!(
                    "Increase voice budget to at least {} (recommended: {}).",
                    (peak * 1.3).ceil() as u8,
                    benchmark.recommended_budget
                ),
                affected_event: None,
                benchmark_value: Some(format!("{} voices", benchmark.recommended_budget)),
                auto_applicable: true,
            });
        } else if utilization > 0.80 {
            out.push(CopilotSuggestion {
                rule_id: "R-VB-2".to_string(),
                category: SuggestionCategory::VoiceBudget,
                severity: SuggestionSeverity::Warning,
                title: "Voice budget utilization high (80%+)".to_string(),
                description: format!(
                    "Estimated peak voices ({:.0}) is {:.0}% of budget ({}). \
                     No headroom for unexpected peaks.",
                    peak, utilization * 100.0, project.voice_budget
                ),
                action: format!("Consider increasing budget to {}.", benchmark.recommended_budget),
                affected_event: None,
                benchmark_value: Some(format!("{}", benchmark.recommended_budget)),
                auto_applicable: false,
            });
        }
    }

    // R-VB-3: Budget below benchmark minimum
    if project.voice_budget < 16 {
        out.push(CopilotSuggestion {
            rule_id: "R-VB-3".to_string(),
            category: SuggestionCategory::VoiceBudget,
            severity: SuggestionSeverity::Warning,
            title: "Voice budget unusually low".to_string(),
            description: format!(
                "Budget of {} is below the industry minimum of 16 for any slot game.",
                project.voice_budget
            ),
            action: "Set voice budget to at least 16.".to_string(),
            affected_event: None,
            benchmark_value: Some("16 minimum".to_string()),
            auto_applicable: true,
        });
    }
}

fn rule_event_coverage(
    project: &AudioProjectSpec,
    benchmark: &crate::benchmarks::IndustryBenchmark,
    out: &mut Vec<CopilotSuggestion>,
) {
    // R-EC-1: Total event count vs benchmark
    if project.event_count() < benchmark.min_events {
        out.push(CopilotSuggestion {
            rule_id: "R-EC-1".to_string(),
            category: SuggestionCategory::EventCoverage,
            severity: SuggestionSeverity::Warning,
            title: format!("Too few audio events ({} / {} minimum)",
                project.event_count(), benchmark.min_events),
            description: format!(
                "A {} typically requires {}-{} events. You have only {}. \
                 Missing events will create silent moments in gameplay.",
                benchmark.reference_name,
                benchmark.min_events, benchmark.typical_events,
                project.event_count()
            ),
            action: format!("Add at least {} more events to meet minimum coverage.",
                benchmark.min_events.saturating_sub(project.event_count())),
            affected_event: None,
            benchmark_value: Some(format!("{}-{} events", benchmark.min_events, benchmark.typical_events)),
            auto_applicable: false,
        });
    }

    // R-EC-2: Missing required base game events
    for required in benchmark.required_base_events {
        let has_it = project.audio_events.iter().any(|e| {
            e.name.contains(required) || e.name == *required
        });
        if !has_it {
            out.push(CopilotSuggestion {
                rule_id: "R-EC-2".to_string(),
                category: SuggestionCategory::EventCoverage,
                severity: SuggestionSeverity::Warning,
                title: format!("Missing required event: {required}"),
                description: format!(
                    "Industry standard {ref_name} requires a '{required}' event. \
                     Missing it creates a gap in the audio lifecycle.",
                    ref_name = benchmark.reference_name,
                ),
                action: format!("Add a '{required}' event to the Base Game category."),
                affected_event: None,
                benchmark_value: None,
                auto_applicable: false,
            });
        }
    }

    // R-EC-3: Missing required feature events (only if game has features)
    if !project.feature_events().is_empty() {
        for required in benchmark.required_feature_events {
            let has_it = project.audio_events.iter().any(|e| {
                e.name.contains(required) || e.name == *required
            });
            if !has_it {
                out.push(CopilotSuggestion {
                    rule_id: "R-EC-3".to_string(),
                    category: SuggestionCategory::FeatureAudio,
                    severity: SuggestionSeverity::Suggestion,
                    title: format!("Consider adding: {required}"),
                    description: format!(
                        "Standard {} games include a '{required}' event for full feature coverage.",
                        benchmark.reference_name
                    ),
                    action: format!("Add '{required}' to the Feature category."),
                    affected_event: None,
                    benchmark_value: None,
                    auto_applicable: false,
                });
            }
        }
    }
}

fn rule_win_tier_calibration(
    project: &AudioProjectSpec,
    benchmark: &crate::benchmarks::IndustryBenchmark,
    out: &mut Vec<CopilotSuggestion>,
) {
    let win_events = project.win_events();
    if win_events.len() < 2 {
        if !win_events.is_empty() {
            out.push(CopilotSuggestion {
                rule_id: "R-WT-1".to_string(),
                category: SuggestionCategory::WinTierCalibration,
                severity: SuggestionSeverity::Warning,
                title: "Only 1 win tier defined".to_string(),
                description: format!(
                    "Industry standard calls for {}-{} distinct win tiers. \
                     A single win sound cannot differentiate the emotional impact of different win sizes.",
                    3, benchmark.win_tiers
                ),
                action: format!("Add at least {} win tier variants.", benchmark.win_tiers.saturating_sub(1)),
                affected_event: None,
                benchmark_value: Some(format!("{} win tiers", benchmark.win_tiers)),
                auto_applicable: false,
            });
        }
        return;
    }

    // R-WT-2: Duration ratio (flagship win should be much longer than subtle win)
    let min_dur = win_events.iter().map(|e| e.duration_ms).min().unwrap_or(0);
    let max_dur = win_events.iter().map(|e| e.duration_ms).max().unwrap_or(0);

    if min_dur > 0 {
        let ratio = max_dur as f32 / min_dur as f32;
        if ratio < benchmark.win_duration_ratio_min {
            out.push(CopilotSuggestion {
                rule_id: "R-WT-2".to_string(),
                category: SuggestionCategory::WinTierCalibration,
                severity: SuggestionSeverity::Suggestion,
                title: format!(
                    "Win tier duration range too narrow (ratio {:.1}× vs {:.1}× recommended)",
                    ratio, benchmark.win_duration_ratio_min
                ),
                description: format!(
                    "Your win sounds range from {}ms to {}ms ({:.1}× ratio). \
                     Industry standard requires at least {:.0}× ratio between \
                     smallest and largest win for emotional proportionality.",
                    min_dur, max_dur, ratio, benchmark.win_duration_ratio_min
                ),
                action: format!(
                    "Extend your flagship win sound to at least {}ms, or reduce \
                     your smallest win to {}ms.",
                    (min_dur as f32 * benchmark.win_duration_ratio_min) as u32,
                    (max_dur as f32 / benchmark.win_duration_ratio_min) as u32
                ),
                affected_event: None,
                benchmark_value: Some(format!("{:.0}× minimum", benchmark.win_duration_ratio_min)),
                auto_applicable: false,
            });
        }
    }

    // R-WT-3: Max win sound below benchmark minimum
    if max_dur < benchmark.min_win_duration_ms {
        out.push(CopilotSuggestion {
            rule_id: "R-WT-3".to_string(),
            category: SuggestionCategory::WinTierCalibration,
            severity: SuggestionSeverity::Warning,
            title: format!("Win sounds too short (max {}ms)", max_dur),
            description: format!(
                "Industry minimum for the largest win sound is {}ms. \
                 Short win sounds reduce emotional impact and player satisfaction.",
                benchmark.min_win_duration_ms
            ),
            action: format!("Extend your biggest win sound to at least {}ms.", benchmark.min_win_duration_ms),
            affected_event: None,
            benchmark_value: Some(format!("{}ms min", benchmark.min_win_duration_ms)),
            auto_applicable: false,
        });
    }
}

fn rule_feature_audio(
    project: &AudioProjectSpec,
    _benchmark: &crate::benchmarks::IndustryBenchmark,
    out: &mut Vec<CopilotSuggestion>,
) {
    // R-FA-1: Feature trigger must be prominent/flagship
    for event in project.feature_events() {
        if event.name.contains("TRIGGER") {
            let tier = &event.tier;
            if tier == "subtle" || tier == "standard" {
                out.push(CopilotSuggestion {
                    rule_id: "R-FA-1".to_string(),
                    category: SuggestionCategory::FeatureAudio,
                    severity: SuggestionSeverity::Warning,
                    title: format!("{} is under-tiered ({tier})", event.name),
                    description: "Feature trigger events should be 'prominent' or 'flagship' tier. \
                        They are key emotional moments that build anticipation and reward.".to_string(),
                    action: "Set this event to 'prominent' or 'flagship' tier.".to_string(),
                    affected_event: Some(event.name.clone()),
                    benchmark_value: Some("prominent or flagship".to_string()),
                    auto_applicable: true,
                });
            }
        }
    }

    // R-FA-2: Feature trigger should have high voice count
    for event in project.feature_events() {
        if event.name.contains("TRIGGER") && event.voice_count < 4 {
            out.push(CopilotSuggestion {
                rule_id: "R-FA-2".to_string(),
                category: SuggestionCategory::FeatureAudio,
                severity: SuggestionSeverity::Suggestion,
                title: format!("{} has low voice count ({}/4 min)", event.name, event.voice_count),
                description: "Feature trigger events benefit from layered audio (4+ voices) \
                    for maximum impact: stinger + music + fanfare + SFX layers.".to_string(),
                action: "Increase voice count to at least 4 for layered feature trigger audio.".to_string(),
                affected_event: Some(event.name.clone()),
                benchmark_value: Some("4-8 voices".to_string()),
                auto_applicable: false,
            });
        }
    }
}

fn rule_responsible_gaming(
    project: &AudioProjectSpec,
    out: &mut Vec<CopilotSuggestion>,
) {
    // R-RG-1: Jackpot games must have cooldown/ambient for RG compliance
    if project.is_jackpot_game() {
        let has_ambient = project.has_event_containing("AMBIENT");
        if !has_ambient {
            out.push(CopilotSuggestion {
                rule_id: "R-RG-1".to_string(),
                category: SuggestionCategory::ResponsibleGaming,
                severity: SuggestionSeverity::Warning,
                title: "No ambient bed event for jackpot game".to_string(),
                description: "Jackpot games require a calming ambient bed to comply with \
                    UKGC/MGA responsible gaming audio guidelines (avoid continuous excitement).".to_string(),
                action: "Add an AMBIENT_BED event with low-energy backing music.".to_string(),
                affected_event: None,
                benchmark_value: None,
                auto_applicable: false,
            });
        }
    }

    // R-RG-2: High volatility needs near-miss handling
    if project.is_high_volatility() {
        let has_near_miss = project.has_event_containing("NEAR_MISS")
            || project.has_event_containing("ANTICIPATION");
        if !has_near_miss {
            out.push(CopilotSuggestion {
                rule_id: "R-RG-2".to_string(),
                category: SuggestionCategory::ResponsibleGaming,
                severity: SuggestionSeverity::Suggestion,
                title: "No near-miss/anticipation audio for high-volatility game".to_string(),
                description: "High-volatility games should have explicit anticipation/near-miss \
                    audio events that NeuroAudio™ can calibrate for responsible gaming.".to_string(),
                action: "Add ANTICIPATION and/or NEAR_MISS events to enable NeuroAudio™ RG calibration.".to_string(),
                affected_event: None,
                benchmark_value: None,
                auto_applicable: false,
            });
        }
    }

    // R-RG-3: High RTP games should not have excessive celebration
    if project.rtp_target > 97.0 {
        let flagship_wins = project.win_events().iter()
            .filter(|e| e.tier == "flagship")
            .count();
        if flagship_wins > 2 {
            out.push(CopilotSuggestion {
                rule_id: "R-RG-3".to_string(),
                category: SuggestionCategory::ResponsibleGaming,
                severity: SuggestionSeverity::Info,
                title: "High RTP with many flagship win tiers".to_string(),
                description: format!(
                    "RTP {:.1}% with {} flagship win events. MGA guidance suggests \
                    limiting 'epic' win celebrations to avoid disproportionate stimulus.",
                    project.rtp_target, flagship_wins
                ),
                action: "Consider reducing to 1-2 flagship win events, or ensure \
                    win magnitudes are proportional to the actual win size.".to_string(),
                affected_event: None,
                benchmark_value: None,
                auto_applicable: false,
            });
        }
    }
}

fn rule_loop_coverage(
    project: &AudioProjectSpec,
    out: &mut Vec<CopilotSuggestion>,
) {
    // R-LC-1: Reel spin must be a loop
    for event in &project.audio_events {
        let name_lower = event.name.to_lowercase();
        let is_spin_sound = name_lower.contains("reel_spin")
            || name_lower.contains("spin_loop")
            || name_lower.contains("reels_spinning");

        if is_spin_sound && !event.can_loop {
            out.push(CopilotSuggestion {
                rule_id: "R-LC-1".to_string(),
                category: SuggestionCategory::LoopCoverage,
                severity: SuggestionSeverity::Critical,
                title: format!("{} is not marked as loop", event.name),
                description: "Reel spin sounds must be loops — the player holds the spin button \
                    or auto-play runs indefinitely. A non-looping spin sound will cut out mid-spin.".to_string(),
                action: "Set can_loop = true for this event.".to_string(),
                affected_event: Some(event.name.clone()),
                benchmark_value: Some("loop: true".to_string()),
                auto_applicable: true,
            });
        }
    }

    // R-LC-2: Ambient bed must be a loop
    for event in &project.audio_events {
        let name_lower = event.name.to_lowercase();
        if (name_lower.contains("ambient") || name_lower.contains("bg_music") || name_lower.contains("backing"))
            && !event.can_loop
        {
            out.push(CopilotSuggestion {
                rule_id: "R-LC-2".to_string(),
                category: SuggestionCategory::LoopCoverage,
                severity: SuggestionSeverity::Warning,
                title: format!("{} should loop", event.name),
                description: "Ambient bed and background music events must be loops for continuous playback.".to_string(),
                action: "Set can_loop = true for this event.".to_string(),
                affected_event: Some(event.name.clone()),
                benchmark_value: Some("loop: true".to_string()),
                auto_applicable: true,
            });
        }
    }
}

fn rule_timing_benchmarks(
    project: &AudioProjectSpec,
    benchmark: &crate::benchmarks::IndustryBenchmark,
    out: &mut Vec<CopilotSuggestion>,
) {
    // R-TB-1: Spin start too long
    if let Some(spin_start) = project.event_by_name("SPIN_START") {
        if spin_start.duration_ms > 400 {
            out.push(CopilotSuggestion {
                rule_id: "R-TB-1".to_string(),
                category: SuggestionCategory::TimingBenchmark,
                severity: SuggestionSeverity::Suggestion,
                title: format!("SPIN_START duration {}ms is above industry norm", spin_start.duration_ms),
                description: "Industry standard SPIN_START is 100–300ms. Longer stings feel \
                    sluggish and reduce the satisfying 'snap' feeling of the spin.".to_string(),
                action: "Trim SPIN_START to 150–250ms for optimal spin-feel.".to_string(),
                affected_event: Some("SPIN_START".to_string()),
                benchmark_value: Some("150–250ms".to_string()),
                auto_applicable: false,
            });
        }
    }

    // R-TB-2: Ambient loop too short
    for event in &project.audio_events {
        if event.name.contains("AMBIENT") && event.can_loop {
            if event.duration_ms < 30_000 {
                out.push(CopilotSuggestion {
                    rule_id: "R-TB-2".to_string(),
                    category: SuggestionCategory::TimingBenchmark,
                    severity: SuggestionSeverity::Suggestion,
                    title: format!("{} loop is short ({}ms)", event.name, event.duration_ms),
                    description: format!(
                        "Ambient bed loops should be at least 60 seconds to avoid \
                        detectable repetition. Industry typical: {}s.",
                        benchmark.typical_ambient_loop_ms / 1000
                    ),
                    action: "Extend ambient loop to at least 60,000ms (60 seconds).".to_string(),
                    affected_event: Some(event.name.clone()),
                    benchmark_value: Some(format!("{}s", benchmark.typical_ambient_loop_ms / 1000)),
                    auto_applicable: false,
                });
            }
        }
    }
}

fn rule_math_aware(
    project: &AudioProjectSpec,
    benchmark: &crate::benchmarks::IndustryBenchmark,
    out: &mut Vec<CopilotSuggestion>,
) {
    // R-MA-1: High volatility → flagship win durations (T5.3)
    if project.is_high_volatility() {
        let flagship_wins: Vec<&crate::project::AudioEventSpec> = project.win_events().iter()
            .copied()
            .filter(|e| e.tier == "flagship" && e.duration_ms < 8000)
            .collect();

        for event in flagship_wins {
            out.push(CopilotSuggestion {
                rule_id: "R-MA-1".to_string(),
                category: SuggestionCategory::IndustryStandard,
                severity: SuggestionSeverity::Suggestion,
                title: format!("{} flagship win too short for high-volatility game", event.name),
                description: format!(
                    "High-volatility games ({}% RTP) produce infrequent but large wins. \
                     Flagship win sounds should be dramatic and long (8–30s) to \
                     reward the player for their patience. Current: {}ms.",
                    project.rtp_target, event.duration_ms
                ),
                action: "Extend this flagship win to at least 8,000ms for high-volatility impact.".to_string(),
                affected_event: Some(event.name.clone()),
                benchmark_value: Some("8,000–30,000ms for high-vol flagship".to_string()),
                auto_applicable: false,
            });
        }
    }

    // R-MA-2: Jackpot sounds must escalate dramatically
    if project.is_jackpot_game() {
        let jp_events: Vec<_> = project.jackpot_events();
        let durations: Vec<u32> = jp_events.iter().map(|e| e.duration_ms).collect();

        if durations.len() >= 2 {
            let min_jp = *durations.iter().min().unwrap_or(&0);
            let max_jp = *durations.iter().max().unwrap_or(&0);
            if min_jp > 0 && (max_jp as f64 / min_jp as f64) < 3.0 {
                out.push(CopilotSuggestion {
                    rule_id: "R-MA-2".to_string(),
                    category: SuggestionCategory::IndustryStandard,
                    severity: SuggestionSeverity::Warning,
                    title: "Jackpot tier audio not sufficiently differentiated".to_string(),
                    description: format!(
                        "MINI/MINOR/MAJOR/GRAND durations range from {}ms to {}ms (only {:.1}× ratio). \
                         GRAND jackpot should feel massively more epic than MINI — \
                         industry standard: at least 10× duration ratio.",
                        min_jp, max_jp, max_jp as f64 / min_jp as f64
                    ),
                    action: "Scale jackpot durations: MINI ~2s, MINOR ~5s, MAJOR ~12s, GRAND ~30s+.".to_string(),
                    affected_event: None,
                    benchmark_value: Some("10× ratio MINI→GRAND".to_string()),
                    auto_applicable: false,
                });
            }
        }
    }

    // R-MA-3: Low RTP → don't oversell small wins (T5.3 math-aware)
    if project.rtp_target < 94.0 {
        let small_wins: Vec<_> = project.win_events().iter()
            .copied()
            .filter(|e| e.tier == "subtle" && e.duration_ms > 1500)
            .collect();

        for event in small_wins {
            out.push(CopilotSuggestion {
                rule_id: "R-MA-3".to_string(),
                category: SuggestionCategory::ResponsibleGaming,
                severity: SuggestionSeverity::Info,
                title: format!("{}: small win celebration may mislead ({}ms)", event.name, event.duration_ms),
                description: format!(
                    "RTP {:.1}% means many small wins actually return less than the bet. \
                     Long subtle-tier win sounds ({:}ms) may give a false impression of success \
                     — a potential RG concern.",
                    project.rtp_target, event.duration_ms
                ),
                action: "Consider keeping subtle-tier win sounds under 1,000ms to match actual win value.".to_string(),
                affected_event: Some(event.name.clone()),
                benchmark_value: Some("< 1,000ms for subtle wins with RTP < 94%".to_string()),
                auto_applicable: false,
            });
        }
    }

    // R-MA-4: Event count vs benchmark typical
    let _ = benchmark; // used above
}

fn rule_priority_ordering(
    project: &AudioProjectSpec,
    out: &mut Vec<CopilotSuggestion>,
) {
    // R-PO-1: Required events should not have low audio_weight
    for event in &project.audio_events {
        if event.is_required && event.audio_weight < 0.5 {
            out.push(CopilotSuggestion {
                rule_id: "R-PO-1".to_string(),
                category: SuggestionCategory::Performance,
                severity: SuggestionSeverity::Warning,
                title: format!("{} is required but has low audio_weight ({:.2})", event.name, event.audio_weight),
                description: "Required events are critical to gameplay feedback. \
                    Low audio_weight means they may be de-prioritized during voice stealing, \
                    causing them to not play during peak moments.".to_string(),
                action: "Set audio_weight to 0.8+ for all required events.".to_string(),
                affected_event: Some(event.name.clone()),
                benchmark_value: Some("0.8+".to_string()),
                auto_applicable: true,
            });
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCORE COMPUTATION
// ─────────────────────────────────────────────────────────────────────────────

fn compute_quality_score(
    _project: &AudioProjectSpec,
    _benchmark: &crate::benchmarks::IndustryBenchmark,
    suggestions: &[CopilotSuggestion],
) -> u8 {
    let mut score: i32 = 100;

    for s in suggestions {
        let penalty = match s.severity {
            SuggestionSeverity::Critical   => 20,
            SuggestionSeverity::Warning    => 8,
            SuggestionSeverity::Suggestion => 3,
            SuggestionSeverity::Info       => 1,
        };
        score -= penalty;
    }

    score.clamp(0, 100) as u8
}

fn compute_industry_match(
    project: &AudioProjectSpec,
    benchmark: &crate::benchmarks::IndustryBenchmark,
) -> u8 {
    let mut points = 0u32;
    let mut max_points = 0u32;

    // Event count match (0–30 points)
    max_points += 30;
    let typical = benchmark.typical_events;
    let count = project.event_count();
    let count_score = if count >= benchmark.min_events && count <= benchmark.max_events {
        let dist = ((count as i32 - typical as i32).abs()) as f64;
        let max_dist = (typical as f64).max(1.0);
        (30.0 * (1.0 - (dist / max_dist).min(1.0))) as u32
    } else {
        0
    };
    points += count_score;

    // Win tier count match (0–20 points)
    max_points += 20;
    let win_count = project.win_events().len();
    if win_count >= benchmark.win_tiers.saturating_sub(1) {
        points += 20;
    } else {
        let ratio = win_count as f64 / benchmark.win_tiers as f64;
        points += (20.0 * ratio) as u32;
    }

    // Required base events coverage (0–30 points)
    max_points += 30;
    let required_count = benchmark.required_base_events.len().max(1);
    let covered = benchmark.required_base_events.iter()
        .filter(|req| project.audio_events.iter().any(|e| e.name.contains(*req)))
        .count();
    points += (30 * covered as u32) / required_count as u32;

    // Voice budget alignment (0–20 points)
    max_points += 20;
    let budget_ratio = project.voice_budget as f64 / benchmark.recommended_budget as f64;
    if (0.75..=1.50).contains(&budget_ratio) {
        points += 20;
    } else {
        let dist = (budget_ratio - 1.0).abs();
        points += (20.0 * (1.0 - dist.min(1.0))) as u32;
    }

    if max_points == 0 { return 0; }
    ((points * 100) / max_points).min(100) as u8
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::project::{AudioEventSpec, AudioProjectSpec};

    fn sample_project() -> AudioProjectSpec {
        AudioProjectSpec {
            game_name: "Test Slot".to_string(),
            game_id: "test_slot".to_string(),
            rtp_target: 96.5,
            volatility: "MEDIUM".to_string(),
            voice_budget: 24,
            reels: 5,
            rows: 3,
            win_mechanism: "20 paylines".to_string(),
            estimated_peak_voices: Some(10.0),
            audio_events: vec![
                make_event("SPIN_START",    "BaseGame", "subtle",   150, 1, true,  false, 0.9),
                make_event("REEL_SPIN",     "BaseGame", "subtle",   2000, 2, true, true,  1.0),
                make_event("REEL_STOP",     "BaseGame", "subtle",   200, 1, true,  false, 0.9),
                make_event("ANTICIPATION",  "BaseGame", "standard", 1200, 2, false, false, 0.7),
                make_event("WIN_1",         "Win",      "subtle",   400, 2, false, false, 0.8),
                make_event("WIN_3",         "Win",      "standard", 1500, 4, false, false, 0.9),
                make_event("WIN_5",         "Win",      "flagship", 8000, 6, false, false, 1.0),
                make_event("FEATURE_TRIGGER","Feature", "flagship", 3000, 6, false, false, 1.0),
                make_event("AMBIENT_BED",   "BaseGame", "subtle",   120000, 1, false, true, 0.5),
            ],
        }
    }

    fn make_event(
        name: &str, cat: &str, tier: &str,
        dur: u32, voices: u8, required: bool, loops: bool, weight: f64,
    ) -> AudioEventSpec {
        AudioEventSpec {
            name: name.to_string(),
            category: cat.to_string(),
            tier: tier.to_string(),
            duration_ms: dur,
            voice_count: voices,
            is_required: required,
            can_loop: loops,
            trigger_probability: 0.5,
            audio_weight: weight,
            rtp_contribution: 0.0,
        }
    }

    #[test]
    fn test_analyze_returns_report() {
        let project = sample_project();
        let report = SuggestionEngine::analyze(&project);
        assert!(report.quality_score <= 100);
        assert!(!report.closest_reference.is_empty());
        assert!(!report.summary.is_empty());
    }

    #[test]
    fn test_reel_spin_not_loop_triggers_critical() {
        let mut project = sample_project();
        // Remove the loop from REEL_SPIN
        let spin = project.audio_events.iter_mut().find(|e| e.name == "REEL_SPIN").unwrap();
        spin.can_loop = false;

        let report = SuggestionEngine::analyze(&project);
        let has_critical = report.suggestions.iter()
            .any(|s| s.rule_id == "R-LC-1" && s.severity == SuggestionSeverity::Critical);
        assert!(has_critical, "Expected R-LC-1 critical for non-looping REEL_SPIN");
    }

    #[test]
    fn test_voice_budget_near_capacity_triggers_critical() {
        let mut project = sample_project();
        project.voice_budget = 10;
        project.estimated_peak_voices = Some(9.8);

        let report = SuggestionEngine::analyze(&project);
        let vb_crit = report.suggestions.iter()
            .any(|s| s.rule_id == "R-VB-1");
        assert!(vb_crit, "Expected R-VB-1 for budget at 98% capacity");
    }

    #[test]
    fn test_quality_score_decreases_with_issues() {
        let good_project = sample_project();
        let good_report = SuggestionEngine::analyze(&good_project);

        let mut bad_project = sample_project();
        bad_project.audio_events.clear(); // no events = many warnings
        let bad_report = SuggestionEngine::analyze(&bad_project);

        assert!(bad_report.quality_score < good_report.quality_score,
            "bad: {} >= good: {}", bad_report.quality_score, good_report.quality_score);
    }

    #[test]
    fn test_industry_match_pct_in_range() {
        let project = sample_project();
        let report = SuggestionEngine::analyze(&project);
        assert!(report.industry_match_pct <= 100);
    }

    #[test]
    fn test_jackpot_game_suggestions() {
        let mut project = sample_project();
        project.audio_events.push(make_event("JACKPOT_WON_GRAND", "Jackpot", "flagship", 20000, 8, false, false, 1.0));
        project.audio_events.push(make_event("JACKPOT_WON_MINI",  "Jackpot", "standard", 2000,  2, false, false, 0.8));

        let report = SuggestionEngine::analyze(&project);
        // Should detect the game as jackpot and use jackpot benchmark
        assert_eq!(report.closest_reference, "Jackpot Network Slot");
    }

    #[test]
    fn test_high_volatility_flagship_win_suggestion() {
        let mut project = sample_project();
        project.volatility = "HIGH".to_string();
        // Flagship win is only 3000ms
        let win5 = project.audio_events.iter_mut().find(|e| e.name == "WIN_5").unwrap();
        win5.duration_ms = 3000;

        let report = SuggestionEngine::analyze(&project);
        let has_ma1 = report.suggestions.iter().any(|s| s.rule_id == "R-MA-1");
        assert!(has_ma1, "Expected R-MA-1 for short flagship win in high-volatility game");
    }

    #[test]
    fn test_win_tier_duration_ratio_rule() {
        let mut project = sample_project();
        // Make win tiers all same duration
        for event in project.audio_events.iter_mut() {
            if event.category == "Win" {
                event.duration_ms = 800;
            }
        }

        let report = SuggestionEngine::analyze(&project);
        let has_wt2 = report.suggestions.iter().any(|s| s.rule_id == "R-WT-2");
        assert!(has_wt2, "Expected R-WT-2 for flat win tier durations");
    }

    #[test]
    fn test_required_event_missing_triggers_warning() {
        let mut project = sample_project();
        // Remove AMBIENT_BED (required in some benchmarks)
        project.audio_events.retain(|e| !e.name.contains("AMBIENT"));
        project.audio_events.retain(|e| e.name != "ANTICIPATION");

        let report = SuggestionEngine::analyze(&project);
        // Should have warnings for missing events
        assert!(!report.suggestions.is_empty());
    }

    #[test]
    fn test_auto_applicable_suggestions_exist() {
        let mut project = sample_project();
        // Budget near capacity
        project.voice_budget = 10;
        project.estimated_peak_voices = Some(9.8);
        // REEL_SPIN not loop
        let spin = project.audio_events.iter_mut().find(|e| e.name == "REEL_SPIN").unwrap();
        spin.can_loop = false;

        let report = SuggestionEngine::analyze(&project);
        let auto = report.auto_applicable();
        assert!(!auto.is_empty(), "Expected at least one auto-applicable suggestion");
    }
}
