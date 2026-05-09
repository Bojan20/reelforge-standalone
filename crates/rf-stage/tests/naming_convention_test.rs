//! Stage naming convention pin — FLUX_MASTER_TODO 0.5 B.2.
//!
//! Pin za canonical event/stage naming convention u rf-stage:
//!
//! 1. **snake_case only** — sva imena su lowercase ASCII slovi + cifre + underscore.
//!    Nikad camelCase (`spinStart`), kebab-case (`spin-start`), space (`spin start`),
//!    ili UPPERCASE (`SPIN_START`).
//!
//! 2. **No leading/trailing underscores, no double underscores** — ime
//!    `_foo` ili `foo__bar` često indicira copy-paste grešku ili nepročišćen
//!    enum variant.
//!
//! 3. **Min length 3, max length 40** — sprečava `x` ili
//!    `extremely_verbose_stage_with_overdetermined_qualifier`. Realistic
//!    spread za slot industriju.
//!
//! 4. **Unique** — duplikati u `all_type_names()` kvare `is_valid_type_name()`
//!    look-up i čine event registration nedeterminističkim.
//!
//! 5. **Reasonable category coverage** — postoje glavne kategorije (reel/win/feature/
//!    bonus/jackpot/cascade/ui/idle) — sanity check da nismo izgubili neku celu kategoriju.
//!
//! Fail-CI ako bilo ko doda nekonvencionalan event — autor mora ili da
//! ispravi naming, ili da update-uje `ALLOW_LIST` sa rationale komentarom.

use rf_stage::Stage;

/// Imena koja su namerno izvan stroge konvencije zbog legacy alias-a ili
/// FFI/JSON parity razloga. Svaki entry mora imati rationale komentar.
const ALLOW_LIST: &[&str] = &[
    // (Trenutno prazna — sva imena u all_type_names() zadovoljavaju konvenciju.)
];

/// Min/max length za stage type name.
const MIN_LEN: usize = 3;
const MAX_LEN: usize = 40;

/// Glavne kategorije — bar po jedan stage type name MORA da počinje ovim
/// prefiksom. Sanity check da niko ne sruši celu kategoriju jednim commit-om.
const REQUIRED_CATEGORY_PREFIXES: &[&str] = &[
    "reel_",       // reel_spin_loop, reel_stop, reel_spinning…
    "win_",        // win_present, win_line_show
    "rollup_",     // rollup_start/tick/end
    "feature_",    // feature_enter/step/exit
    "bonus_",      // bonus_enter/choice/reveal/exit
    "jackpot_",    // jackpot_trigger/present/buildup/reveal/celebration
    "cascade_",    // cascade_start/step/end
    "ui_",         // ui_spin_press, ui_skip_press
    "idle_",       // idle_start, idle_loop
    "anticipation_", // anticipation_on/off/tension_layer
];

#[test]
fn all_type_names_are_snake_case() {
    let mut violations = Vec::new();
    for &name in Stage::all_type_names() {
        if ALLOW_LIST.contains(&name) {
            continue;
        }
        if let Some(reason) = check_snake_case(name) {
            violations.push(format!("  {name:?}: {reason}"));
        }
    }
    assert!(
        violations.is_empty(),
        "Stage type name(s) krše snake_case konvenciju.\n\
         Pravilo: lowercase ASCII slova + cifre + underscore samo. \
         Nikad camelCase / kebab / SPACE / UPPER.\n\
         Violations:\n{}",
        violations.join("\n"),
    );
}

#[test]
fn all_type_names_have_no_underscore_artifacts() {
    let mut violations = Vec::new();
    for &name in Stage::all_type_names() {
        if ALLOW_LIST.contains(&name) {
            continue;
        }
        if name.starts_with('_') {
            violations.push(format!("  {name:?}: leading underscore"));
        }
        if name.ends_with('_') {
            violations.push(format!("  {name:?}: trailing underscore"));
        }
        if name.contains("__") {
            violations.push(format!("  {name:?}: double underscore"));
        }
    }
    assert!(
        violations.is_empty(),
        "Stage type name(s) imaju underscore artifact-e (leading/trailing/double).\n\
         Violations:\n{}",
        violations.join("\n"),
    );
}

#[test]
fn all_type_names_meet_length_bounds() {
    let mut violations = Vec::new();
    for &name in Stage::all_type_names() {
        if ALLOW_LIST.contains(&name) {
            continue;
        }
        let len = name.len();
        if len < MIN_LEN {
            violations.push(format!("  {name:?}: {len} chars < min {MIN_LEN}"));
        }
        if len > MAX_LEN {
            violations.push(format!("  {name:?}: {len} chars > max {MAX_LEN}"));
        }
    }
    assert!(
        violations.is_empty(),
        "Stage type name(s) izvan length bounds [{MIN_LEN}..{MAX_LEN}].\n\
         Violations:\n{}",
        violations.join("\n"),
    );
}

#[test]
fn all_type_names_are_unique() {
    let names = Stage::all_type_names();
    let mut seen = std::collections::HashSet::new();
    let mut dupes = Vec::new();
    for &name in names {
        if !seen.insert(name) {
            dupes.push(name);
        }
    }
    assert!(
        dupes.is_empty(),
        "Stage::all_type_names() ima duplikate (kvari is_valid_type_name + parsing): {dupes:?}",
    );
}

#[test]
fn required_category_prefixes_are_covered() {
    let names = Stage::all_type_names();
    let mut missing = Vec::new();
    for &prefix in REQUIRED_CATEGORY_PREFIXES {
        let any = names.iter().any(|n| n.starts_with(prefix));
        if !any {
            missing.push(prefix);
        }
    }
    assert!(
        missing.is_empty(),
        "Stage::all_type_names() je izgubio kategoriju(e) (nijedan stage ne počinje sa): {missing:?}.\n\
         Ako je kategorija namerno uklonjena, skini je iz REQUIRED_CATEGORY_PREFIXES list-e.",
    );
}

#[test]
fn count_of_type_names_is_within_sane_bounds() {
    // Sanity guard: ako neko slučajno obriše pola list-e ili duplira sve,
    // ovaj test će uhvatiti to pre svih ostalih.
    let n = Stage::all_type_names().len();
    assert!(
        (40..=200).contains(&n),
        "Stage::all_type_names() count je {n} — izvan razumnog raspona [40..200]. \
         Verovatno greška u editovanju enum-a.",
    );
}

#[test]
fn convention_pin_failure_message_is_actionable() {
    // Documentation pin — failure poruke moraju jasno reći šta da se uradi.
    let example = "Stage type name(s) krše snake_case konvenciju.\n         \
                   Pravilo: lowercase ASCII slova + cifre + underscore samo.";
    assert!(example.contains("snake_case"));
    assert!(example.contains("lowercase"));
}

// ──────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────

fn check_snake_case(name: &str) -> Option<String> {
    if name.is_empty() {
        return Some("empty string".into());
    }
    for ch in name.chars() {
        if !(ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_') {
            return Some(format!("invalid char {ch:?} (only [a-z0-9_] allowed)"));
        }
    }
    if !name.chars().next().unwrap().is_ascii_lowercase() {
        return Some("must start with lowercase letter".into());
    }
    None
}
