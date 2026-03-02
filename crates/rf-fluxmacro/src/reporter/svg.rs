// ============================================================================
// rf-fluxmacro — SVG Reporter
// ============================================================================
// FM-18: Inline SVG generator for visual report elements.
// Generates: voice timeline, loudness histogram, fatigue curve,
// determinism grid.
// ============================================================================

use crate::security::html_escape;

/// Generate a voice usage timeline SVG (area chart).
/// `data_points` are (time_sec, voice_count) pairs.
/// `max_voices` is the platform voice budget for the ceiling line.
pub fn voice_timeline_svg(
    data_points: &[(f64, u32)],
    max_voices: u32,
    width: u32,
    height: u32,
) -> String {
    if data_points.is_empty() {
        return empty_svg(width, height, "No voice data");
    }

    let padding = 40.0_f64;
    let chart_w = width as f64 - padding * 2.0;
    let chart_h = height as f64 - padding * 2.0;
    let max_time = data_points.last().map(|(t, _)| *t).unwrap_or(1.0);
    let max_v = max_voices.max(1) as f64;

    let mut svg = format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{width}\" height=\"{height}\" viewBox=\"0 0 {width} {height}\">\n"
    );
    svg.push_str(&format!(
        "<rect width=\"{width}\" height=\"{height}\" fill=\"#1a1a2e\" rx=\"4\"/>\n"
    ));

    // Budget ceiling line
    let budget_y = padding + chart_h * (1.0 - max_voices as f64 / max_v);
    svg.push_str(&format!(
        "<line x1=\"{padding}\" y1=\"{budget_y}\" x2=\"{}\" y2=\"{budget_y}\" stroke=\"#FF4444\" stroke-dasharray=\"4,4\" stroke-width=\"1\"/>\n",
        padding + chart_w
    ));
    svg.push_str(&format!(
        "<text x=\"{}\" y=\"{}\" fill=\"#FF4444\" font-size=\"10\" text-anchor=\"end\">Budget: {max_voices}</text>\n",
        padding + chart_w, budget_y - 4.0
    ));

    // Area fill
    let mut path = format!("M{padding},{}", padding + chart_h);
    for (time, voices) in data_points {
        let x = padding + (time / max_time) * chart_w;
        let y = padding + chart_h * (1.0 - *voices as f64 / max_v);
        path.push_str(&format!(" L{x:.1},{y:.1}"));
    }
    path.push_str(&format!(" L{},{} Z", padding + chart_w, padding + chart_h));
    svg.push_str(&format!(
        "<path d=\"{path}\" fill=\"rgba(74,158,255,0.2)\" stroke=\"#4A9EFF\" stroke-width=\"1.5\"/>\n"
    ));

    // Axes labels
    svg.push_str(&format!(
        "<text x=\"{}\" y=\"{}\" fill=\"#888\" font-size=\"10\" text-anchor=\"middle\">Time (s)</text>\n",
        width as f64 / 2.0,
        height as f64 - 5.0
    ));
    svg.push_str(&format!(
        "<text x=\"10\" y=\"{}\" fill=\"#888\" font-size=\"10\" transform=\"rotate(-90, 10, {})\" text-anchor=\"middle\">Voices</text>\n",
        height as f64 / 2.0,
        height as f64 / 2.0
    ));

    svg.push_str("</svg>");
    svg
}

/// Generate a loudness histogram SVG.
/// `categories` are (domain_name, measured_lufs, target_lufs, is_pass).
pub fn loudness_histogram_svg(
    categories: &[(&str, f32, f32, bool)],
    width: u32,
    height: u32,
) -> String {
    if categories.is_empty() {
        return empty_svg(width, height, "No loudness data");
    }

    let padding = 50.0_f64;
    let chart_w = width as f64 - padding * 2.0;
    let chart_h = height as f64 - padding * 2.0;
    let bar_gap = 8.0;
    let bar_width = (chart_w - bar_gap * categories.len() as f64) / categories.len() as f64;

    // LUFS range: -30 to 0
    let lufs_min = -30.0_f64;
    let lufs_max = 0.0_f64;
    let lufs_range = lufs_max - lufs_min;

    let mut svg = format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{width}\" height=\"{height}\" viewBox=\"0 0 {width} {height}\">\n"
    );
    svg.push_str(&format!(
        "<rect width=\"{width}\" height=\"{height}\" fill=\"#1a1a2e\" rx=\"4\"/>\n"
    ));

    for (i, (name, measured, target, pass)) in categories.iter().enumerate() {
        let x = padding + i as f64 * (bar_width + bar_gap);

        // Measured bar
        let measured_h = ((*measured as f64 - lufs_min) / lufs_range * chart_h).max(2.0);
        let measured_y = padding + chart_h - measured_h;
        let color = if *pass { "#40FF90" } else { "#FF4444" };
        svg.push_str(&format!(
            "<rect x=\"{x:.1}\" y=\"{measured_y:.1}\" width=\"{bar_width:.1}\" height=\"{measured_h:.1}\" fill=\"{color}\" rx=\"2\"/>\n"
        ));

        // Target line
        let target_h = ((*target as f64 - lufs_min) / lufs_range * chart_h).max(2.0);
        let target_y = padding + chart_h - target_h;
        svg.push_str(&format!(
            "<line x1=\"{x:.1}\" y1=\"{target_y:.1}\" x2=\"{:.1}\" y2=\"{target_y:.1}\" stroke=\"#FFD700\" stroke-width=\"2\" stroke-dasharray=\"3,2\"/>\n",
            x + bar_width
        ));

        // Label
        let label_x = x + bar_width / 2.0;
        svg.push_str(&format!(
            "<text x=\"{label_x:.1}\" y=\"{}\" fill=\"#888\" font-size=\"9\" text-anchor=\"middle\">{}</text>\n",
            padding + chart_h + 15.0,
            html_escape(name)
        ));

        // Value
        svg.push_str(&format!(
            "<text x=\"{label_x:.1}\" y=\"{:.1}\" fill=\"{color}\" font-size=\"9\" text-anchor=\"middle\">{measured:.1}</text>\n",
            measured_y - 4.0
        ));
    }

    svg.push_str("</svg>");
    svg
}

/// Generate a fatigue curve SVG (line chart with threshold markers).
/// `data_points` are (time_min, fatigue_index) pairs.
/// `warning_threshold` and `fail_threshold` mark horizontal lines.
pub fn fatigue_curve_svg(
    data_points: &[(f64, f64)],
    warning_threshold: f64,
    fail_threshold: f64,
    width: u32,
    height: u32,
) -> String {
    if data_points.is_empty() {
        return empty_svg(width, height, "No fatigue data");
    }

    let padding = 40.0_f64;
    let chart_w = width as f64 - padding * 2.0;
    let chart_h = height as f64 - padding * 2.0;
    let max_time = data_points.last().map(|(t, _)| *t).unwrap_or(1.0);
    let max_fatigue = data_points
        .iter()
        .map(|(_, f)| *f)
        .fold(0.0_f64, f64::max)
        .max(fail_threshold * 1.2);

    let mut svg = format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{width}\" height=\"{height}\" viewBox=\"0 0 {width} {height}\">\n"
    );
    svg.push_str(&format!(
        "<rect width=\"{width}\" height=\"{height}\" fill=\"#1a1a2e\" rx=\"4\"/>\n"
    ));

    // Warning threshold
    let warn_y = padding + chart_h * (1.0 - warning_threshold / max_fatigue);
    svg.push_str(&format!(
        "<line x1=\"{padding}\" y1=\"{warn_y:.1}\" x2=\"{}\" y2=\"{warn_y:.1}\" stroke=\"#FFD700\" stroke-dasharray=\"4,4\" stroke-width=\"1\"/>\n",
        padding + chart_w
    ));

    // Fail threshold
    let fail_y = padding + chart_h * (1.0 - fail_threshold / max_fatigue);
    svg.push_str(&format!(
        "<line x1=\"{padding}\" y1=\"{fail_y:.1}\" x2=\"{}\" y2=\"{fail_y:.1}\" stroke=\"#FF4444\" stroke-dasharray=\"4,4\" stroke-width=\"1\"/>\n",
        padding + chart_w
    ));

    // Data line
    let mut path = String::new();
    for (i, (time, fatigue)) in data_points.iter().enumerate() {
        let x = padding + (time / max_time) * chart_w;
        let y = padding + chart_h * (1.0 - fatigue / max_fatigue);
        if i == 0 {
            path.push_str(&format!("M{x:.1},{y:.1}"));
        } else {
            path.push_str(&format!(" L{x:.1},{y:.1}"));
        }
    }
    svg.push_str(&format!(
        "<path d=\"{path}\" fill=\"none\" stroke=\"#4A9EFF\" stroke-width=\"2\"/>\n"
    ));

    svg.push_str("</svg>");
    svg
}

/// Generate a determinism hash grid SVG.
/// `run_hashes` are hash strings from multiple runs. All should match.
pub fn determinism_grid_svg(run_hashes: &[&str], width: u32, height: u32) -> String {
    if run_hashes.is_empty() {
        return empty_svg(width, height, "No determinism data");
    }

    let cell_size = 30.0_f64;
    let padding = 20.0_f64;
    let cols = run_hashes.len();

    let mut svg = format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{width}\" height=\"{height}\" viewBox=\"0 0 {width} {height}\">\n"
    );
    svg.push_str(&format!(
        "<rect width=\"{width}\" height=\"{height}\" fill=\"#1a1a2e\" rx=\"4\"/>\n"
    ));

    let reference = run_hashes[0];
    for (i, hash) in run_hashes.iter().enumerate() {
        let x = padding + i as f64 * (cell_size + 4.0);
        let y = padding;
        let matches = *hash == reference;
        let color = if matches { "#40FF90" } else { "#FF4444" };
        svg.push_str(&format!(
            "<rect x=\"{x:.1}\" y=\"{y:.1}\" width=\"{cell_size}\" height=\"{cell_size}\" fill=\"{color}\" rx=\"3\" opacity=\"0.8\"/>\n"
        ));
        svg.push_str(&format!(
            "<text x=\"{:.1}\" y=\"{:.1}\" fill=\"#1a1a2e\" font-size=\"10\" text-anchor=\"middle\" font-weight=\"bold\">{}</text>\n",
            x + cell_size / 2.0,
            y + cell_size / 2.0 + 3.0,
            if matches { "=" } else { "X" }
        ));
        svg.push_str(&format!(
            "<text x=\"{:.1}\" y=\"{:.1}\" fill=\"#888\" font-size=\"8\" text-anchor=\"middle\">Run {}</text>\n",
            x + cell_size / 2.0,
            y + cell_size + 14.0,
            i + 1
        ));
    }

    // Hash preview (first 8 chars)
    let all_match = run_hashes.iter().all(|h| *h == reference);
    let status = if all_match {
        format!(
            "All {} runs match: {}...",
            cols,
            &reference[..8.min(reference.len())]
        )
    } else {
        format!("MISMATCH detected across {} runs", cols)
    };
    let status_color = if all_match { "#40FF90" } else { "#FF4444" };
    svg.push_str(&format!(
        "<text x=\"{padding}\" y=\"{}\" fill=\"{status_color}\" font-size=\"11\">{}</text>\n",
        padding + cell_size + 35.0,
        html_escape(&status)
    ));

    svg.push_str("</svg>");
    svg
}

fn empty_svg(width: u32, height: u32, message: &str) -> String {
    format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{width}\" height=\"{height}\">\
         <rect width=\"{width}\" height=\"{height}\" fill=\"#1a1a2e\" rx=\"4\"/>\
         <text x=\"{}\" y=\"{}\" fill=\"#666\" font-size=\"12\" text-anchor=\"middle\">{}</text>\
         </svg>",
        width / 2,
        height / 2,
        html_escape(message)
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn voice_timeline_produces_svg() {
        let data = vec![(0.0, 5), (1.0, 15), (2.0, 30), (3.0, 20), (4.0, 10)];
        let svg = voice_timeline_svg(&data, 32, 600, 200);
        assert!(svg.contains("<svg"));
        assert!(svg.contains("</svg>"));
        assert!(svg.contains("Budget: 32"));
    }

    #[test]
    fn loudness_histogram_produces_svg() {
        let data = vec![
            ("UI", -20.0, -20.0, true),
            ("SFX", -15.0, -18.0, false),
            ("MUS", -16.5, -16.0, true),
        ];
        let svg = loudness_histogram_svg(&data, 400, 200);
        assert!(svg.contains("<svg"));
        assert!(svg.contains("UI"));
    }

    #[test]
    fn fatigue_curve_produces_svg() {
        let data = vec![(0.0, 0.1), (5.0, 0.3), (10.0, 0.6), (15.0, 0.4)];
        let svg = fatigue_curve_svg(&data, 0.5, 0.8, 400, 200);
        assert!(svg.contains("<svg"));
    }

    #[test]
    fn determinism_grid_all_match() {
        let hashes = vec!["abc123def456", "abc123def456", "abc123def456"];
        let svg = determinism_grid_svg(&hashes, 300, 100);
        assert!(svg.contains("All 3 runs match"));
        assert!(svg.contains("#40FF90"));
    }

    #[test]
    fn determinism_grid_mismatch() {
        let hashes = vec!["abc123", "abc123", "xyz789"];
        let svg = determinism_grid_svg(&hashes, 300, 100);
        assert!(svg.contains("MISMATCH"));
    }

    #[test]
    fn empty_data_produces_message() {
        let svg = voice_timeline_svg(&[], 32, 400, 200);
        assert!(svg.contains("No voice data"));
    }
}
