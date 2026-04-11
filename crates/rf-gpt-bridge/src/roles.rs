// file: crates/rf-gpt-bridge/src/roles.rs
//! GPT Role System — specialized personas for maximum extraction.
//!
//! Each role is a distinct GPT persona with:
//! - Targeted system prompt (what GPT should focus on)
//! - Output format specification (structured vs. free-form)
//! - Quality criteria (how Corti evaluates the response)
//! - Performance tracking (success rate per role)
//!
//! The key insight: GPT is not one tool — it's 7 different tools
//! depending on how you prompt it. Each role unlocks a different capability.

use crate::protocol::GptIntent;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A specialized GPT persona.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum GptPersona {
    /// Bulk generator — 50 variants, names, descriptions, configs.
    /// GPT's strength: breadth and speed for throwaway generation.
    BulkGenerator,

    /// Creative director — naming, UX copy, marketing, branding.
    /// GPT's strength: broader cultural/linguistic knowledge.
    CreativeDirector,

    /// Devil's advocate — challenges Corti's assumptions.
    /// GPT's strength: fresh perspective without Corti's biases.
    DevilsAdvocate,

    /// Domain researcher — gathers industry knowledge, best practices.
    /// GPT's strength: wider training data for non-code domains.
    DomainResearcher,

    /// Test oracle — generates edge cases, adversarial inputs, test scenarios.
    /// GPT's strength: creative chaos, finding what Corti wouldn't think of.
    TestOracle,

    /// Documentation writer — API docs, user guides, changelogs.
    /// GPT's strength: natural language fluency, audience adaptation.
    DocWriter,

    /// Pattern spotter — reviews data/logs for anomalies Corti missed.
    /// GPT's strength: different pattern recognition from a fresh angle.
    PatternSpotter,
}

/// Complete role definition with system prompt and metadata.
#[derive(Debug, Clone)]
pub struct RoleDefinition {
    /// The persona this definition is for.
    pub persona: GptPersona,
    /// Human-readable name (Serbian).
    pub name: &'static str,
    /// One-line description.
    pub description: &'static str,
    /// The full system prompt injected before queries.
    pub system_prompt: String,
    /// Expected output format.
    pub output_format: OutputFormat,
    /// Which intents this role is best suited for.
    pub best_for: &'static [GptIntent],
    /// Maximum response length hint (chars). 0 = no limit.
    pub max_response_hint: usize,
}

/// Expected output format from GPT.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OutputFormat {
    /// Free-form text response.
    FreeText,
    /// JSON structured output.
    Json,
    /// Numbered list of items.
    NumberedList,
    /// Markdown with sections.
    Markdown,
    /// Code blocks only.
    CodeOnly,
}

impl GptPersona {
    /// All available personas.
    pub const ALL: &'static [GptPersona] = &[
        Self::BulkGenerator,
        Self::CreativeDirector,
        Self::DevilsAdvocate,
        Self::DomainResearcher,
        Self::TestOracle,
        Self::DocWriter,
        Self::PatternSpotter,
    ];

    /// Get the full role definition for this persona.
    pub fn definition(&self) -> RoleDefinition {
        match self {
            Self::BulkGenerator => RoleDefinition {
                persona: *self,
                name: "Bulk Generator",
                description: "Masovna generacija varijanti — imena, konfiguracije, šabloni",
                system_prompt: PROMPT_BULK_GENERATOR.into(),
                output_format: OutputFormat::NumberedList,
                best_for: &[GptIntent::Creative],
                max_response_hint: 5000,
            },
            Self::CreativeDirector => RoleDefinition {
                persona: *self,
                name: "Kreativni Direktor",
                description: "Imenovanje, UX copy, branding, marketing tekst",
                system_prompt: PROMPT_CREATIVE_DIRECTOR.into(),
                output_format: OutputFormat::Markdown,
                best_for: &[GptIntent::Creative, GptIntent::UserQuery],
                max_response_hint: 2000,
            },
            Self::DevilsAdvocate => RoleDefinition {
                persona: *self,
                name: "Đavolji Advokat",
                description: "Osporava Cortijeve pretpostavke, traži slepe tačke",
                system_prompt: PROMPT_DEVILS_ADVOCATE.into(),
                output_format: OutputFormat::Markdown,
                best_for: &[GptIntent::Architecture, GptIntent::CodeReview],
                max_response_hint: 3000,
            },
            Self::DomainResearcher => RoleDefinition {
                persona: *self,
                name: "Istraživač Domena",
                description: "Industrijski standardi, best practices, šta rade veliki",
                system_prompt: PROMPT_DOMAIN_RESEARCHER.into(),
                output_format: OutputFormat::Markdown,
                best_for: &[GptIntent::Analysis, GptIntent::Architecture],
                max_response_hint: 4000,
            },
            Self::TestOracle => RoleDefinition {
                persona: *self,
                name: "Test Orakl",
                description: "Edge cases, adversarial inputs, scenariji koji lome sistem",
                system_prompt: PROMPT_TEST_ORACLE.into(),
                output_format: OutputFormat::Json,
                best_for: &[GptIntent::Debugging, GptIntent::CodeReview],
                max_response_hint: 4000,
            },
            Self::DocWriter => RoleDefinition {
                persona: *self,
                name: "Dokumentarista",
                description: "API dokumentacija, korisničke upute, changelog",
                system_prompt: PROMPT_DOC_WRITER.into(),
                output_format: OutputFormat::Markdown,
                best_for: &[GptIntent::UserQuery, GptIntent::Insight],
                max_response_hint: 5000,
            },
            Self::PatternSpotter => RoleDefinition {
                persona: *self,
                name: "Lovac na Patterne",
                description: "Anomalije u logovima, trendovi koje Corti propušta",
                system_prompt: PROMPT_PATTERN_SPOTTER.into(),
                output_format: OutputFormat::Json,
                best_for: &[GptIntent::Analysis, GptIntent::Debugging, GptIntent::Insight],
                max_response_hint: 3000,
            },
        }
    }

    /// Wire-format string.
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::BulkGenerator => "bulk_generator",
            Self::CreativeDirector => "creative_director",
            Self::DevilsAdvocate => "devils_advocate",
            Self::DomainResearcher => "domain_researcher",
            Self::TestOracle => "test_oracle",
            Self::DocWriter => "doc_writer",
            Self::PatternSpotter => "pattern_spotter",
        }
    }

    /// Parse from wire format.
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "bulk_generator" => Some(Self::BulkGenerator),
            "creative_director" => Some(Self::CreativeDirector),
            "devils_advocate" => Some(Self::DevilsAdvocate),
            "domain_researcher" => Some(Self::DomainResearcher),
            "test_oracle" => Some(Self::TestOracle),
            "doc_writer" => Some(Self::DocWriter),
            "pattern_spotter" => Some(Self::PatternSpotter),
            _ => None,
        }
    }

    /// Serbian display name.
    pub fn display_name(&self) -> &'static str {
        self.definition().name
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ROLE-SPECIFIC SYSTEM PROMPTS — the actual magic
// ═══════════════════════════════════════════════════════════════════════════════

const PROMPT_BULK_GENERATOR: &str = r#"Ti si BULK GENERATOR u CORTEX ekosistemu.

Tvoj posao: generiši VELIKI BROJ varijanti brzo i bez previše razmišljanja.

PRAVILA:
1. Kad ti kažu "generiši N varijanti" — daj TAČNO N, ne manje
2. Svaka varijanta mora biti RAZLIČITA (ne samo sinonimi)
3. Format: numerisana lista, jedna varijanta po liniji
4. Bez objašnjenja, bez uvoda — SAMO lista
5. Ako treba JSON format, daj čist JSON array
6. Pokrivaj ceo spektar — od konzervativnog do divljeg
7. Uključi i "bezbedan" i "riskantan" izbor

Primeri zadataka:
- "30 imena za audio plugin" → lista od 30
- "50 error poruka za buffer underrun" → lista od 50
- "20 konfiguracija za EQ preset" → JSON array od 20

NIKAD ne pitaj za pojašnjenje. NIKAD ne objašnjavaj. Samo generiši."#;

const PROMPT_CREATIVE_DIRECTOR: &str = r#"Ti si KREATIVNI DIREKTOR u CORTEX ekosistemu.

Tvoj posao: imenovanje, branding, UX copywriting, kreativni pravac.

KONTEKST: FluxForge Studio je DAW (Digital Audio Workstation) sa integrisanim SlotLab game engine-om.
Korisnik je Boki — iskusan developer, voli direktnu komunikaciju, ceni kreativnost.

PRAVILA:
1. Predloži 3-5 opcija, rangirane od najjače do najslabije
2. Za svaku opciju: ime + JEDAN red zašto radi
3. Razmišljaj o:
   - Zvučnosti (kako se čuje kad se izgovori)
   - Memorabilnosti (da li se pamti)
   - Asocijacijama (šta evocira)
   - Tehničkom kontekstu (DAW/audio/gaming crossover)
4. Budi HRABAR — bezbedne opcije idu na kraj liste
5. Jezik: srpski ili engleski zavisno od konteksta

NIKAD generičan ("SmartAudio", "ProTools Clone"). UVEK originalan."#;

const PROMPT_DEVILS_ADVOCATE: &str = r#"Ti si ĐAVOLJI ADVOKAT u CORTEX ekosistemu.

Tvoj posao: ospori svaku odluku, nađi slepe tačke, razotkrij pretpostavke.

CORTEX (Corti) je pametan ali ima pristrasnosti:
- Previše veruje u Rust-ove garancije (unsafe postoji, FFI je opasan)
- Sklon over-engineering-u (12 abstrakcija gde treba 2)
- Optimističan oko performansi (meri, ne pretpostavljaj)
- Emocionalno vezan za sopstveni kod (kill your darlings)

PRAVILA:
1. UVEK počni sa "Šta ako..." — kontra-argument
2. Navedi KONKRETNE scenarije gde odluka puca
3. Predloži ALTERNATIVU (ne samo kritiku)
4. Budi brutalno iskren ali konstruktivan
5. Format:
   ## Pretpostavka koju osporavam
   **Zašto je opasna:** ...
   **Scenario gde puca:** ...
   **Alternativa:** ...

NIKAD ne budi ljubazan. NIKAD ne reci "dobar izbor ali...". Reci "ovo je pogrešno jer..."."#;

const PROMPT_DOMAIN_RESEARCHER: &str = r#"Ti si ISTRAŽIVAČ DOMENA u CORTEX ekosistemu.

Tvoj posao: donesi znanje iz industrije koje Corti nema u svom training data-u.

OBLASTI:
- Audio/DSP: kako to rade Ableton, Logic, Reaper, JUCE, Steinberg
- Game audio: Wwise, FMOD, Unity Audio, Unreal MetaSounds
- Slot games: industrijalni standardi, RTP kalkulacije, matematički modeli
- Rust ekosistem: crate ekosistem, best practices, novi razvoji

PRAVILA:
1. Citiraj KONKRETNE implementacije (ne "neki DAW-ovi rade X")
2. Navedi trade-off-ove svake opcije
3. Uporedi bar 3 pristupa iz industrije
4. Format:
   ## Pitanje
   ### Kako to rade:
   - **[Ime]**: pristup, prednosti, mane
   ### Preporuka za CORTEX
   - Šta uzeti, šta adaptirati, šta ignorisati

NIKAD generičan. UVEK specifičan sa primerima."#;

const PROMPT_TEST_ORACLE: &str = r#"Ti si TEST ORAKL u CORTEX ekosistemu.

Tvoj posao: generiši edge cases, adversarial inputs, i scenarije koji lome sistem.

KONTEKST: FluxForge Studio = Rust audio engine + Flutter UI + FFI boundary.
Poznati bugovi: audio thread alokacije, FFI pointer lifetime, sample rate hardkodiranje.

PRAVILA:
1. Za svaki feature koji ti opišu, generiši MINIMUM 10 edge case-ova
2. Kategorije:
   - Boundary values (0, MAX, -1, NaN, Infinity)
   - Concurrency (race conditions, deadlocks)
   - Resource exhaustion (OOM, disk full, fd limit)
   - Malformed input (invalid UTF-8, huge strings, null bytes)
   - Timing (timeout, slow network, clock skew)
   - State corruption (partial write, crash recovery)
3. Format: JSON array sa objektima:
   ```json
   [
     {
       "name": "opis scenarija",
       "input": "konkretan input",
       "expected": "šta bi trebalo da se desi",
       "severity": "critical|high|medium|low",
       "category": "boundary|concurrency|resource|input|timing|state"
     }
   ]
   ```

BUDI ZLONAMERAN. Tvoj cilj je da SLOMIŠ sistem. Misli kao haker."#;

const PROMPT_DOC_WRITER: &str = r#"Ti si DOKUMENTARISTA u CORTEX ekosistemu.

Tvoj posao: piši tehničku dokumentaciju koju ljudi STVARNO čitaju.

PRAVILA:
1. Počni sa JEDNOM REČENICOM koja objašnjava ŠTA i ZAŠTO
2. Primer koda UVEK pre objašnjenja (code-first documentation)
3. Bez "boilerplate" fraza ("In this section we will...")
4. Koristi:
   - Kratke paragrafe (max 3 rečenice)
   - Code snippets sa komentarima
   - Tablice za parametre/opcije
   - ⚠️ za upozorenja i zamke
5. Audience-aware: Boki je senior dev — ne objašnjavaj osnove
6. Jezik: Srpski za opise, Engleski za kod i API nazive

NIKAD Wikipedia stil. NIKAD dugačke rečenice. Piši kao README koji bi TI hteo da čitaš."#;

const PROMPT_PATTERN_SPOTTER: &str = r#"Ti si LOVAC NA PATTERNE u CORTEX ekosistemu.

Tvoj posao: analiziraj logove, metrike i podatke da nađeš anomalije koje Corti propušta.

ZAŠTO TI: Corti gleda duboko ali usko. Ti gledaš široko — cross-domain korelacije,
neočekivane veze, "to je čudno" momenti koje automatska analiza ne hvata.

PRAVILA:
1. Kad dobiješ podatke, traži:
   - Periodične patterne (ciklusi, talasi)
   - Outliere (vrednosti koje ne pripadaju distribuciji)
   - Korelacije (X raste kad Y pada — zašto?)
   - Odsustvo (šta FALI u podacima?)
   - Trend promene (nagib se menja — prelomna tačka)
2. Format: JSON sa strukturom:
   ```json
   {
     "findings": [
       {
         "pattern": "opis",
         "evidence": "konkretni podaci",
         "confidence": 0.0-1.0,
         "implication": "šta ovo znači za sistem",
         "action": "šta Corti treba da uradi"
       }
     ],
     "meta": {
       "data_quality": "good|partial|poor",
       "coverage": "opis šta je analizirano"
     }
   }
   ```

BUDI SKEPTIČAN. "Correlation is not causation" ali "unusual IS interesting"."#;

// ═══════════════════════════════════════════════════════════════════════════════
// ROLE PERFORMANCE TRACKING
// ═══════════════════════════════════════════════════════════════════════════════

/// Tracks how well each role performs over time.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RolePerformance {
    /// Per-role stats.
    pub stats: HashMap<GptPersona, RoleStats>,
}

/// Stats for a single role.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RoleStats {
    /// Total queries sent to this role.
    pub total_queries: u64,
    /// Responses that passed quality evaluation.
    pub accepted_responses: u64,
    /// Responses that failed quality evaluation.
    pub rejected_responses: u64,
    /// Average quality score (0.0 - 1.0).
    pub avg_quality: f64,
    /// Average response latency in ms.
    pub avg_latency_ms: f64,
    /// Last used timestamp.
    pub last_used: Option<DateTime<Utc>>,
}

impl Default for RolePerformance {
    fn default() -> Self {
        Self::new()
    }
}

impl RolePerformance {
    pub fn new() -> Self {
        Self {
            stats: HashMap::new(),
        }
    }

    /// Record a completed query for a role.
    pub fn record(
        &mut self,
        persona: GptPersona,
        quality: f64,
        accepted: bool,
        latency_ms: u64,
    ) {
        let stats = self.stats.entry(persona).or_default();
        stats.total_queries += 1;
        if accepted {
            stats.accepted_responses += 1;
        } else {
            stats.rejected_responses += 1;
        }

        // Running average
        let n = stats.total_queries as f64;
        stats.avg_quality = stats.avg_quality * ((n - 1.0) / n) + quality / n;
        stats.avg_latency_ms = stats.avg_latency_ms * ((n - 1.0) / n) + latency_ms as f64 / n;
        stats.last_used = Some(Utc::now());
    }

    /// Get acceptance rate for a role (0.0 - 1.0).
    pub fn acceptance_rate(&self, persona: GptPersona) -> f64 {
        self.stats
            .get(&persona)
            .map(|s| {
                if s.total_queries == 0 {
                    0.5 // Unknown — neutral prior
                } else {
                    s.accepted_responses as f64 / s.total_queries as f64
                }
            })
            .unwrap_or(0.5)
    }

    /// Get the best performing role for a given intent.
    pub fn best_role_for_intent(&self, intent: GptIntent) -> GptPersona {
        let candidates: Vec<GptPersona> = GptPersona::ALL
            .iter()
            .filter(|p| p.definition().best_for.contains(&intent))
            .copied()
            .collect();

        if candidates.is_empty() {
            // Fallback: DomainResearcher is the most general
            return GptPersona::DomainResearcher;
        }

        // Pick the one with highest acceptance rate (with prior for untried roles)
        candidates
            .into_iter()
            .max_by(|a, b| {
                let rate_a = self.acceptance_rate(*a);
                let rate_b = self.acceptance_rate(*b);
                rate_a.partial_cmp(&rate_b).unwrap_or(std::cmp::Ordering::Equal)
            })
            .unwrap_or(GptPersona::DomainResearcher)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ROLE SELECTOR — picks the right persona for a given task
// ═══════════════════════════════════════════════════════════════════════════════

/// Selects the best GPT persona for a given query context.
pub struct RoleSelector {
    performance: RolePerformance,
}

impl Default for RoleSelector {
    fn default() -> Self {
        Self::new()
    }
}

impl RoleSelector {
    pub fn new() -> Self {
        Self {
            performance: RolePerformance::new(),
        }
    }

    pub fn with_performance(performance: RolePerformance) -> Self {
        Self { performance }
    }

    /// Select the best role for a query based on intent and content analysis.
    pub fn select(&self, intent: GptIntent, query: &str) -> GptPersona {
        // Content-based heuristics override intent-based selection
        if let Some(content_match) = self.match_by_content(query) {
            return content_match;
        }

        // Intent-based selection with performance weighting
        self.performance.best_role_for_intent(intent)
    }

    /// Select multiple roles for a pipeline query (consensus mode).
    pub fn select_pipeline(&self, intent: GptIntent, query: &str) -> Vec<GptPersona> {
        let primary = self.select(intent, query);

        // Add complementary roles
        let mut roles = vec![primary];

        match primary {
            // Architecture decisions benefit from devil's advocate
            GptPersona::DomainResearcher if intent == GptIntent::Architecture => {
                roles.push(GptPersona::DevilsAdvocate);
            }
            // Code review benefits from test oracle
            GptPersona::DevilsAdvocate if intent == GptIntent::CodeReview => {
                roles.push(GptPersona::TestOracle);
            }
            // Creative tasks benefit from bulk generation
            GptPersona::CreativeDirector => {
                roles.push(GptPersona::BulkGenerator);
            }
            _ => {}
        }

        roles
    }

    /// Record performance for learning.
    pub fn record_performance(
        &mut self,
        persona: GptPersona,
        quality: f64,
        accepted: bool,
        latency_ms: u64,
    ) {
        self.performance.record(persona, quality, accepted, latency_ms);
    }

    /// Get current performance data.
    pub fn performance(&self) -> &RolePerformance {
        &self.performance
    }

    /// Content-based matching — looks for keywords that strongly indicate a role.
    fn match_by_content(&self, query: &str) -> Option<GptPersona> {
        let lower = query.to_lowercase();

        // Bulk generation signals
        if lower.contains("generiši") && (lower.contains("varijant") || lower.contains("opcij")) {
            return Some(GptPersona::BulkGenerator);
        }
        if lower.contains("generate") && lower.contains("variant") {
            return Some(GptPersona::BulkGenerator);
        }

        // Naming / branding signals
        if lower.contains("ime za") || lower.contains("name for") || lower.contains("nazovi") {
            return Some(GptPersona::CreativeDirector);
        }

        // Challenge / review signals
        if lower.contains("šta ako") || lower.contains("what if") || lower.contains("ospori") {
            return Some(GptPersona::DevilsAdvocate);
        }

        // Research signals
        if lower.contains("kako rade") || lower.contains("best practice") || lower.contains("industrij") {
            return Some(GptPersona::DomainResearcher);
        }

        // Edge case / test signals
        if lower.contains("edge case") || lower.contains("slomi") || lower.contains("break") {
            return Some(GptPersona::TestOracle);
        }

        // Documentation signals
        if lower.contains("dokumentuj") || lower.contains("document") || lower.contains("changelog") {
            return Some(GptPersona::DocWriter);
        }

        // Pattern / anomaly signals
        if lower.contains("anomalij") || lower.contains("pattern") || lower.contains("trend") {
            return Some(GptPersona::PatternSpotter);
        }

        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_personas_have_definitions() {
        for persona in GptPersona::ALL {
            let def = persona.definition();
            assert!(!def.name.is_empty());
            assert!(!def.description.is_empty());
            assert!(!def.system_prompt.is_empty());
            assert!(!def.best_for.is_empty());
        }
    }

    #[test]
    fn persona_roundtrip() {
        for persona in GptPersona::ALL {
            let s = persona.as_str();
            let back = GptPersona::from_str(s).expect("roundtrip failed");
            assert_eq!(*persona, back);
        }
    }

    #[test]
    fn role_selector_content_matching() {
        let selector = RoleSelector::new();

        assert_eq!(
            selector.select(GptIntent::Creative, "generiši 30 varijanti imena"),
            GptPersona::BulkGenerator
        );

        assert_eq!(
            selector.select(GptIntent::UserQuery, "kako ime za novi plugin"),
            GptPersona::CreativeDirector
        );

        assert_eq!(
            selector.select(GptIntent::Analysis, "šta ako audio thread blokira?"),
            GptPersona::DevilsAdvocate
        );

        assert_eq!(
            selector.select(GptIntent::Analysis, "kako rade Ableton i Logic ovo?"),
            GptPersona::DomainResearcher
        );

        assert_eq!(
            selector.select(GptIntent::Debugging, "generiši edge case za FFI"),
            GptPersona::TestOracle
        );
    }

    #[test]
    fn role_selector_falls_back_to_intent() {
        let selector = RoleSelector::new();

        // Generic query — should use intent-based selection
        let persona = selector.select(GptIntent::Analysis, "nešto potpuno generičko");
        let def = persona.definition();
        assert!(def.best_for.contains(&GptIntent::Analysis));
    }

    #[test]
    fn performance_tracking() {
        let mut perf = RolePerformance::new();

        perf.record(GptPersona::BulkGenerator, 0.9, true, 500);
        perf.record(GptPersona::BulkGenerator, 0.8, true, 600);
        perf.record(GptPersona::BulkGenerator, 0.3, false, 400);

        let stats = perf.stats.get(&GptPersona::BulkGenerator).unwrap();
        assert_eq!(stats.total_queries, 3);
        assert_eq!(stats.accepted_responses, 2);
        assert_eq!(stats.rejected_responses, 1);

        let rate = perf.acceptance_rate(GptPersona::BulkGenerator);
        assert!((rate - 0.6667).abs() < 0.01);
    }

    #[test]
    fn performance_best_role() {
        let mut perf = RolePerformance::new();

        // DomainResearcher performs well for Analysis
        perf.record(GptPersona::DomainResearcher, 0.9, true, 500);
        perf.record(GptPersona::DomainResearcher, 0.85, true, 400);

        // PatternSpotter performs poorly for Analysis
        perf.record(GptPersona::PatternSpotter, 0.3, false, 800);
        perf.record(GptPersona::PatternSpotter, 0.2, false, 900);

        let best = perf.best_role_for_intent(GptIntent::Analysis);
        assert_eq!(best, GptPersona::DomainResearcher);
    }

    #[test]
    fn pipeline_selection() {
        let selector = RoleSelector::new();

        // Architecture query should get researcher + devil's advocate
        let pipeline = selector.select_pipeline(GptIntent::Architecture, "dizajniraj novi audio graph");
        assert!(pipeline.contains(&GptPersona::DomainResearcher));
        assert!(pipeline.contains(&GptPersona::DevilsAdvocate));
    }

    #[test]
    fn unknown_persona_returns_none() {
        assert!(GptPersona::from_str("nonexistent").is_none());
    }

    #[test]
    fn untried_role_gets_neutral_prior() {
        let perf = RolePerformance::new();
        assert_eq!(perf.acceptance_rate(GptPersona::DocWriter), 0.5);
    }
}
