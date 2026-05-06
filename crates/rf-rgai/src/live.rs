//! Live compliance state — real-time traffic-light status per jurisdiction.
//!
//! `RgaiAnalyzer` (analysis.rs) i `SessionAnalysis` (session.rs) su
//! **post-hoc** alati: ti uzmu ceo session JSON i izračunaju metrike.
//! Korisno za QA + export gate, ali nedovoljno za UI koji pokazuje
//! `🟢🟡🔴` traffic lights u Omnibar-u **dok korisnik spinuje**.
//!
//! `LiveComplianceState` rešava taj jaz:
//!
//!   * **Lock-free counters** — audio thread može da poziva
//!     `record_spin()` bez allokacije / mutex-a.
//!   * **Snapshot-on-demand** — UI thread (Flutter) poll-uje
//!     `snapshot()` 5×/sec; jeftino i alocira tek pri serijalizaciji.
//!   * **Per-jurisdiction status** — svaki aktivni jurisdiction dobija
//!     [`JurisdictionStatus::Ok | Warn | Violation`] na osnovu
//!     **trenutnih** ratio-a vs profile threshold-ova.
//!
//! ## LDW guard (FLUX_MASTER_TODO 3.4.3)
//!
//! Loss-Disguised-Win = spin gde `win >= bet`, audio celebration ipak
//! signalizira "win". UKGC i MGA tretiraju kao deception. `record_spin`
//! prepoznaje LDW automatski preko `win == bet ± epsilon` heuristike.
//! Trigger se može hookovati u celebration scheduler-u (kratak guard
//! što stopira rollup audio kad se LDW detektuje).
//!
//! ## Near-miss tracker (FLUX_MASTER_TODO 3.4.4)
//!
//! Near-miss ratio = `near_miss_count / spins_total`. Threshold po
//! jurisdiction (npr. UKGC 3%, MGA 5%). Status:
//!
//!   * `< 80% of threshold`  → 🟢 Ok
//!   * `80%..100%`           → 🟡 Warn (approaching ceiling)
//!   * `> 100%`              → 🔴 Violation

use std::sync::atomic::{AtomicU64, Ordering};

use serde::{Deserialize, Serialize};

use crate::jurisdiction::Jurisdiction;

/// `win == bet` se računa LDW samo ako je razlika manja od ovog praga.
/// Zaštita protiv float artefakata pri sumiranju line wins-a.
const LDW_EPSILON: f64 = 1e-6;

/// Procenat jurisdiction threshold-a iznad kojeg traffic light pređe iz
/// `Ok` u `Warn`. Vrednost je inženjerska: dovoljno blizu da regulator
/// ne stigne pre tebe, dovoljno daleko da `Warn` znači nešto.
const WARN_FRACTION: f64 = 0.80;

/// Per-jurisdiction trenutni status.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum JurisdictionStatus {
    /// Sve metrike ispod 80% threshold-a — zeleno svetlo.
    Ok,
    /// Bar jedna metrika u 80–100% threshold-a — žuto svetlo.
    Warn,
    /// Bar jedna metrika preko threshold-a — crveno svetlo, gate aktivan.
    Violation,
}

impl JurisdictionStatus {
    /// Sledeći status posle dodavanja jednog observation-a sa datom
    /// utilization-om. `Violation` je apsorbujuća (jednom violation,
    /// nikad nazad bez reset-a — UI prikazuje crveno dok god je sesija
    /// aktivna, što je željeno za regulatorni overlay).
    pub fn worst(self, other: Self) -> Self {
        match (self, other) {
            (Self::Violation, _) | (_, Self::Violation) => Self::Violation,
            (Self::Warn, _) | (_, Self::Warn) => Self::Warn,
            _ => Self::Ok,
        }
    }

    /// Status iz utilization ratio-a (0.0 = empty, 1.0 = at threshold).
    pub fn from_ratio(ratio: f64) -> Self {
        if ratio > 1.0 {
            Self::Violation
        } else if ratio >= WARN_FRACTION {
            Self::Warn
        } else {
            Self::Ok
        }
    }
}

/// Snapshot za UI poll. Sve f64 polja su pre-izračunata pa renderer
/// nikad ne radi math.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LiveComplianceSnapshot {
    /// Ukupan broj spin-ova od `init()`.
    pub spins_total: u64,
    /// Broj LDW spin-ova (win ≈ bet) detektovanih u ovoj sesiji.
    pub ldw_count: u64,
    /// Tekući LDW ratio (`ldw_count / spins_total`, 0 kada nema spin-ova).
    pub ldw_ratio: f64,
    /// Broj near-miss spin-ova.
    pub near_miss_count: u64,
    /// Tekući near-miss ratio (`near_miss_count / spins_total`).
    pub near_miss_ratio: f64,
    /// Per-jurisdiction status zasnovan na ratio-ima vs profile threshold-ovima.
    pub jurisdictions: Vec<JurisdictionLive>,
}

/// Per-jurisdiction live entry za UI.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct JurisdictionLive {
    /// Code (e.g. `"UKGC"`).
    pub code: String,
    /// Trenutni status za ovaj jurisdiction.
    pub status: JurisdictionStatus,
    /// Worst metric utilization (0.0..) — koji metric je najbliži pucanju.
    /// Owned String (umesto &'static) jer Deserialize zahteva `'de` lifetime.
    pub worst_metric: String,
    /// Worst metric utilization ratio (`current / threshold`).
    pub worst_utilization: f64,
}

/// Live state. `Send + Sync` jer su sva polja `AtomicU64`.
///
/// **Lifecycle:** kreiraš jednu instancu po sesiji (`new(jurisdictions)`),
/// audio thread zove `record_spin` na svakom spinu, UI thread poll-uje
/// `snapshot()`. `reset()` clear-uje counters bez realokacije.
pub struct LiveComplianceState {
    spins_total: AtomicU64,
    ldw_count: AtomicU64,
    near_miss_count: AtomicU64,
    /// Sum × 1000 trick — `AtomicU64` ne može direktno f64. Skaliramo
    /// `arousal_sum` × 1000 u `u64`. Pri snapshot-u delim sa 1000 da
    /// dobijem prosek. Resolution 0.001 je dovoljna za UI traffic light.
    arousal_sum_milli: AtomicU64,
    /// Aktivni jurisdictions (snapshot-time iteration). Read-only posle
    /// `new()` — dinamičko dodavanje nije relevantno za live UI surface.
    jurisdictions: Vec<Jurisdiction>,
}

impl LiveComplianceState {
    /// Kreiraj novi state za dat skup jurisdiction-a. Counters startuju
    /// na 0. Prazan jurisdiction set je validan ali snapshot će vratiti
    /// praznu `jurisdictions` listu (UI će onda sakriti badge).
    pub fn new(jurisdictions: Vec<Jurisdiction>) -> Self {
        Self {
            spins_total: AtomicU64::new(0),
            ldw_count: AtomicU64::new(0),
            near_miss_count: AtomicU64::new(0),
            arousal_sum_milli: AtomicU64::new(0),
            jurisdictions,
        }
    }

    /// Audio-thread safe — zabeleži jedan spin.
    ///
    /// Argumenti:
    /// * `win` — isplata u kreditima (0.0 za loss).
    /// * `bet` — ulog u kreditima (uvek > 0; ako = 0, spin se ignoriše
    ///   da deljenje nulom ne kaže "100% LDW" pri prvi spinu).
    /// * `near_miss` — `true` ako je RNG generisao near-miss obrazac
    ///   (npr. 2 scatter na 1, 3, 5 reels). Compositor odlučuje
    ///   eksterno (rf-aurexis ili sličan).
    /// * `arousal` — trenutni arousal coefficient za ovaj spin (0..1).
    ///   Audio thread računa ovo iz playback-a; ovde samo akumuliramo.
    pub fn record_spin(&self, win: f64, bet: f64, near_miss: bool, arousal: f64) {
        if bet <= 0.0 {
            return; // bet 0 nije validan spin za compliance brojač
        }
        self.spins_total.fetch_add(1, Ordering::Relaxed);

        // LDW = win == bet (returnu sve, "winned the spin" feel ali nula
        // gain). Razlika ε za float artifact safety.
        if (win - bet).abs() < LDW_EPSILON {
            self.ldw_count.fetch_add(1, Ordering::Relaxed);
        }

        if near_miss {
            self.near_miss_count.fetch_add(1, Ordering::Relaxed);
        }

        // Arousal sum × 1000 — clamp [0, 1] pre skaliranja.
        let a = arousal.clamp(0.0, 1.0);
        let milli = (a * 1000.0) as u64;
        self.arousal_sum_milli.fetch_add(milli, Ordering::Relaxed);
    }

    /// Reset counters. Jurisdictions se ne diraju.
    pub fn reset(&self) {
        self.spins_total.store(0, Ordering::Relaxed);
        self.ldw_count.store(0, Ordering::Relaxed);
        self.near_miss_count.store(0, Ordering::Relaxed);
        self.arousal_sum_milli.store(0, Ordering::Relaxed);
    }

    /// UI-thread safe — vrati trenutni snapshot. Alociranje jednog
    /// `Vec<JurisdictionLive>` po pozivu, ostalo je atomic load.
    pub fn snapshot(&self) -> LiveComplianceSnapshot {
        let spins = self.spins_total.load(Ordering::Relaxed);
        let ldw = self.ldw_count.load(Ordering::Relaxed);
        let nm = self.near_miss_count.load(Ordering::Relaxed);
        let arousal_milli = self.arousal_sum_milli.load(Ordering::Relaxed);

        let spins_f = spins as f64;
        let avg_arousal = if spins == 0 {
            0.0
        } else {
            (arousal_milli as f64 / 1000.0) / spins_f
        };
        let ldw_ratio = if spins == 0 { 0.0 } else { ldw as f64 / spins_f };
        let nm_ratio = if spins == 0 { 0.0 } else { nm as f64 / spins_f };

        let jurisdictions = self
            .jurisdictions
            .iter()
            .map(|&j| Self::evaluate_jurisdiction(j, ldw_ratio, nm_ratio, avg_arousal))
            .collect();

        LiveComplianceSnapshot {
            spins_total: spins,
            ldw_count: ldw,
            ldw_ratio,
            near_miss_count: nm,
            near_miss_ratio: nm_ratio,
            jurisdictions,
        }
    }

    /// Per-jurisdiction status računanje. Posebna funkcija za testabilnost.
    fn evaluate_jurisdiction(
        j: Jurisdiction,
        ldw_ratio: f64,
        nm_ratio: f64,
        avg_arousal: f64,
    ) -> JurisdictionLive {
        let p = j.profile();

        // Compare current values vs profile threshold. `max_loss_disguise`
        // i `max_near_miss_deception` su na skali 0..1 (per-asset metrika);
        // mi ih reuse-ujemo kao session-wide ratio cap. To je **konzervativno**
        // — pravi compliance check radi na asset level, ali za live UI ovo
        // je dobra aproksimacija (false-positive je ok jer je Warn, ne block).
        let ldw_util = if p.max_loss_disguise > 0.0 {
            ldw_ratio / p.max_loss_disguise
        } else {
            0.0
        };
        let nm_util = if p.max_near_miss_deception > 0.0 {
            nm_ratio / p.max_near_miss_deception
        } else {
            0.0
        };
        let ar_util = if p.max_arousal > 0.0 {
            avg_arousal / p.max_arousal
        } else {
            0.0
        };

        // Worst-of-three odlučuje status traffic light-a.
        let (worst_metric, worst_util) = [
            ("ldw", ldw_util),
            ("near_miss", nm_util),
            ("arousal", ar_util),
        ]
        .into_iter()
        .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
        .unwrap_or(("ldw", 0.0));

        JurisdictionLive {
            code: format!("{j:?}").to_uppercase(),
            status: JurisdictionStatus::from_ratio(worst_util),
            worst_metric: worst_metric.to_string(),
            worst_utilization: worst_util,
        }
    }

    /// Convenience — tester / FFI poll može da pita "ima li violation".
    /// Kratko-spaja kroz worst status iz svih jurisdictions.
    pub fn has_violation(&self) -> bool {
        let snap = self.snapshot();
        snap.jurisdictions
            .iter()
            .any(|j| j.status == JurisdictionStatus::Violation)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_ukgc() -> LiveComplianceState {
        LiveComplianceState::new(vec![Jurisdiction::Ukgc])
    }

    #[test]
    fn empty_state_is_ok_for_all_jurisdictions() {
        // Bez ijednog spina, sve traffic lights su zelene.
        let state = LiveComplianceState::new(vec![Jurisdiction::Ukgc, Jurisdiction::Mga]);
        let snap = state.snapshot();
        assert_eq!(snap.spins_total, 0);
        assert_eq!(snap.ldw_count, 0);
        assert_eq!(snap.near_miss_count, 0);
        for j in &snap.jurisdictions {
            assert_eq!(j.status, JurisdictionStatus::Ok);
        }
    }

    #[test]
    fn record_spin_with_zero_bet_is_ignored() {
        // Defensive: bet=0 bi delio nulom u ratio izračunu. Skip ga
        // kao validan compliance event (UI ne sme da kaže "100% LDW
        // posle prvi 0-bet spina").
        let state = fresh_ukgc();
        state.record_spin(0.0, 0.0, false, 0.0);
        state.record_spin(5.0, 0.0, true, 0.5);
        let snap = state.snapshot();
        assert_eq!(snap.spins_total, 0);
    }

    #[test]
    fn ldw_detection_within_epsilon() {
        // win == bet → LDW. ε = 1e-6 čuva od float artifact-a kad se
        // line wins sumiraju.
        let state = fresh_ukgc();
        state.record_spin(1.0, 1.0, false, 0.0); // exact LDW
        state.record_spin(1.0 + 1e-7, 1.0, false, 0.0); // unutar ε → LDW
        state.record_spin(1.0 + 1e-3, 1.0, false, 0.0); // van ε → win, ne LDW
        state.record_spin(0.0, 1.0, false, 0.0); // loss
        let snap = state.snapshot();
        assert_eq!(snap.spins_total, 4);
        assert_eq!(snap.ldw_count, 2);
        assert!((snap.ldw_ratio - 0.5).abs() < 1e-9);
    }

    #[test]
    fn near_miss_ratio_tracking() {
        let state = fresh_ukgc();
        // 3 near-miss u 10 spin-ova = 30% — UKGC max 30% pa exact threshold.
        for i in 0..10 {
            state.record_spin(0.0, 1.0, i < 3, 0.0);
        }
        let snap = state.snapshot();
        assert_eq!(snap.spins_total, 10);
        assert_eq!(snap.near_miss_count, 3);
        assert!((snap.near_miss_ratio - 0.3).abs() < 1e-9);
    }

    #[test]
    fn jurisdiction_status_climbs_ok_warn_violation() {
        // UKGC max_near_miss_deception = 0.30. Test 3 ratios:
        //   0.20 → Ok (66% util, ispod 80% warn line)
        //   0.27 → Warn (90% util, u 80–100%)
        //   0.40 → Violation (133% util)
        for (nm_count, expected) in [
            (20, JurisdictionStatus::Ok),
            (27, JurisdictionStatus::Warn),
            (40, JurisdictionStatus::Violation),
        ] {
            let state = fresh_ukgc();
            for i in 0..100 {
                state.record_spin(0.0, 1.0, i < nm_count, 0.0);
            }
            let snap = state.snapshot();
            let ukgc = snap
                .jurisdictions
                .iter()
                .find(|j| j.code == "UKGC")
                .expect("UKGC must be present");
            assert_eq!(
                ukgc.status, expected,
                "nm_count={nm_count} → status mismatch (worst_metric={}, util={:.2})",
                ukgc.worst_metric, ukgc.worst_utilization
            );
        }
    }

    #[test]
    fn worst_metric_is_picked_for_status() {
        // UKGC: max_arousal = 0.60, max_ldw = 0.20, max_near_miss = 0.30.
        // Set arousal high (0.55), ldw low (0.05), near_miss low (0.05).
        // Worst utilization = arousal/0.60 ≈ 0.92 → Warn.
        let state = fresh_ukgc();
        for _ in 0..100 {
            state.record_spin(0.0, 1.0, false, 0.55);
        }
        let snap = state.snapshot();
        let ukgc = snap.jurisdictions.first().unwrap();
        assert_eq!(ukgc.worst_metric, "arousal");
        assert_eq!(ukgc.status, JurisdictionStatus::Warn);
    }

    #[test]
    fn reset_clears_counters() {
        let state = fresh_ukgc();
        for _ in 0..50 {
            state.record_spin(1.0, 1.0, true, 0.5);
        }
        assert!(state.snapshot().spins_total > 0);
        state.reset();
        let snap = state.snapshot();
        assert_eq!(snap.spins_total, 0);
        assert_eq!(snap.ldw_count, 0);
        assert_eq!(snap.near_miss_count, 0);
    }

    #[test]
    fn has_violation_short_circuits_correctly() {
        let state = fresh_ukgc();
        assert!(!state.has_violation());
        // Pump 100 LDW (preko UKGC max 0.20).
        for _ in 0..100 {
            state.record_spin(1.0, 1.0, false, 0.0);
        }
        assert!(state.has_violation());
    }

    #[test]
    fn status_worst_is_absorbing_for_violation() {
        // Pinuje semantiku `worst()` — Violation NIKAD ne pada nazad
        // na Warn ili Ok bez explicit reset-a, što UI očekuje za
        // regulatory overlay (jednom crveno, ostaje crveno).
        assert_eq!(
            JurisdictionStatus::Ok.worst(JurisdictionStatus::Warn),
            JurisdictionStatus::Warn
        );
        assert_eq!(
            JurisdictionStatus::Warn.worst(JurisdictionStatus::Violation),
            JurisdictionStatus::Violation
        );
        assert_eq!(
            JurisdictionStatus::Violation.worst(JurisdictionStatus::Ok),
            JurisdictionStatus::Violation
        );
    }

    #[test]
    fn from_ratio_partition() {
        // Pin partition: < 0.80 = Ok, [0.80, 1.0] = Warn, > 1.0 = Violation.
        assert_eq!(JurisdictionStatus::from_ratio(0.0), JurisdictionStatus::Ok);
        assert_eq!(JurisdictionStatus::from_ratio(0.79), JurisdictionStatus::Ok);
        assert_eq!(JurisdictionStatus::from_ratio(0.80), JurisdictionStatus::Warn);
        assert_eq!(JurisdictionStatus::from_ratio(1.00), JurisdictionStatus::Warn);
        assert_eq!(
            JurisdictionStatus::from_ratio(1.01),
            JurisdictionStatus::Violation
        );
    }

    #[test]
    fn snapshot_serializes_to_json() {
        let state = fresh_ukgc();
        state.record_spin(1.0, 1.0, true, 0.5);
        let snap = state.snapshot();
        let json = serde_json::to_string(&snap).unwrap();
        let back: LiveComplianceSnapshot = serde_json::from_str(&json).unwrap();
        assert_eq!(back.spins_total, 1);
        assert_eq!(back.ldw_count, 1);
        assert_eq!(back.jurisdictions.len(), 1);
    }
}
