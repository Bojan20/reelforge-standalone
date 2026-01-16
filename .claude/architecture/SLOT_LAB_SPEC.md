# FLUXFORGE SLOT LAB

## Synthetic Slot Engine & Audio-First Slot Sandbox

Ovaj dokument definiše **Slot Lab** kao posebnu sekciju unutar FluxForge Studio-a. Slot Lab nije kazino simulator i ne izlaže stvarnu matematiku. To je **Synthetic Slot Engine**: dramaturški realan, audio‑orijentisan mock slot koji koristi samo javne ulaze (paytable, GDD, simboli, feature pravila) i proizvodi „verovatne" ishode za potrebe audio dizajna, UX ritma i muzičkog flow‑a.

Cilj: omogućiti audio dizajneru da **pre klijenta** izgradi kompletnu zvučnu dramaturgiju igre – bez zavisnosti od pravog engine‑a i bez otkrivanja IP‑a.

---

## 1. Šta Slot Lab koristi (javna istina)

Slot Lab prihvata isključivo:

* Paytable (simboli, isplate, težine)
* GDD feature pravila (FS, respin, HNW, multipliers)
* Grid dimenzije (5×3, 6×5…)
* Big Win pragovi (Tier 1/2/3)
* Timing profil (Normal / Turbo / Mobile / Studio)
* „Volatility feel" (Low / Mid / High / Insane)

Ne koristi:

* Pravi kazino simulator
* Regulativne matematičke modele
* Proprietary algoritme klijenta

---

## 2. Synthetic Slot Engine

Umesto pravog simulatora, Slot Lab koristi **Synthetic Spin Generator** koji:

* proizvodi dramaturški realne ishode
* generiše male, srednje i velike dobitke
* stvara near‑miss situacije
* povremeno ulazi u feature
* poštuje „volatility feel"

Rezultat je slot koji se ponaša kao prava igra, ali je potpuno bezbedan i generički.

---

## 3. Slot Lab UI – Svetski raspored

**Levo – Game Spec Panel**

* Grid / Pay model
* Symbol set (LP/HP/W/SC)
* Feature pravila
* Big Win pragovi
* Volatility Dial
* Timing profil

**Centar – Mock Slot View**

* Reels / Grid
* HUD (Balance, Bet, Win)
* Status bar (GOOD LUCK / YOU WIN)
* Spin, Turbo, Autoplay
* Minimalni skin (Glass / Dark / Gold)

**Dole – Stage Timeline**

* SPIN_START → REEL_STOP → WIN_PRESENT → ROLLUP → BIGWIN → FEATURE → SPIN_END
* Replay / Loop poslednjeg spina
* Marker po stage‑u

**Desno – Event Trigger Matrix & Audio**

* Redovi: kanonski STAGES
* Kolone: SFX / Music / Duck / Params
* Slot‑orijentisani audio mapping
* Waveform editor (loop, fade, sync)

**Donje desno – Mixer**

* SFX / Music / VO / UI / Master
* Slot‑spec ducking
* Big Win exception rules

---

## 4. Slot‑spec funkcije koje niko nema

### Volatility Dial

Jedan globalni kontroler koji menja:

* učestalost win‑ova
* učestalost anticipation‑a
* frekvenciju big win‑ova
* ulazak u feature

Audio dizajner odmah čuje razliku između „meke" i „tvrde" igre.

### Scenario Controls

* Force Win (Small / Medium / Big)
* Force Big Win Tier 1/2/3
* Force Free Spins
* Force Near‑Miss
* Replay Last Spin
* Batch Play (50/100)

### Heatmap Mode

Overlay preko grid‑a:

* gde se najčešće pojavljuje win
* gde se javlja scatter
* gde se pali anticipation

Audio dizajn dobija prostornu inteligenciju.

### Emotional Curve View

Graf poslednjih N spinova:

* Tension
* Release
* Impact

Slot se posmatra kao emotivni tok, ne kao niz zvukova.

### Audio‑First Mode

* Minimalna grafika
* Fokus na Stage Timeline
* Metri učestalosti stage‑ova
* Vizualizacija audio opterećenja

Profesionalni režim za miks.

---

## 5. Vrednost

Slot Lab omogućava:

* dizajn kompletnog audio flow‑a bez klijenta
* testiranje muzike, tranzicija i dramaturgije
* rad bez IP rizika
* univerzalnu primenu na sve slot projekte

FluxForge Studio ne imitira engine.
On stvara **slot svet za zvuk**.

To je razlika između alata koji „reaguju na evente" i sistema koji razume igru kao emocionalni tok.
