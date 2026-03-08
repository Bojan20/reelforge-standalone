# Reaper DAW → FluxForge Studio: Kompletna Analiza Feature-a

> **Datum:** 2026-03-08
> **Cilj:** Identifikovati SVE Reaper feature-e relevantne za sound dizajnere i audio tehničare koje možemo implementirati u FluxForge Studio.
> **Metod:** Web research + poređenje sa trenutnim FluxForge mogućnostima.

---

## Sadržaj

1. [Routing & Signal Flow](#1-routing--signal-flow)
2. [Item/Media Handling](#2-itemmedia-handling)
3. [Rendering & Bouncing](#3-rendering--bouncing)
4. [FX Chain & Processing](#4-fx-chain--processing)
5. [Automation](#5-automation)
6. [Custom Actions & Macros](#6-custom-actions--macros)
7. [Project Organization](#7-project-organization)
8. [Media Explorer](#8-media-explorer)
9. [SWS Extensions](#9-sws-extensions)
10. [Sound Design Specific](#10-sound-design-specific)
11. [UI/UX Filozofija](#11-uiux-filozofija)
12. [MIDI za Sound Design](#12-midi-za-sound-design)
13. [Spectral Editing](#13-spectral-editing)
14. [Video Integracija](#14-video-integracija)
15. [Mrežna Saradnja](#15-mrežna-saradnja)
16. [Performanse & Efikasnost](#16-performanse--efikasnost)
17. [Extensibility & Scripting](#17-extensibility--scripting)
18. [File Management](#18-file-management)
19. [Game Audio Integracija](#19-game-audio-integracija)
20. [Kreativni Sound Design Trikovi](#20-kreativni-sound-design-trikovi)
21. [FluxForge vs Reaper — Gap Analiza](#21-fluxforge-vs-reaper--gap-analiza)
22. [Prioriteti Implementacije](#22-prioriteti-implementacije)

---

## 1. Routing & Signal Flow

### 1.1 Routing Matrix (Alt+R / Option+R)

**Šta radi u Reaper-u:**
Globalni grid prikaz koji pokazuje svaki trak u sesiji i omogućava slanje audio signala sa bilo kog traka na bilo koji drugi trak jednim klikom. Pristupa se preko View > Routing Matrix.

**Ključni detalji:**
- Svaki trak u Reaperu ima **64 interna audio kanala** za rutiranje između FX-ova, trakova i izlaza
- Grid format: redovi = source trakovi, kolone = destination trakovi
- Klik na presek = kreiranje send-a
- Podržava audio I MIDI rutiranje iz istog interfejsa
- Prikazuje i hardware I/O, ne samo interne rute

**Zašto je vredno za sound dizajnere:**
Omogućava kompleksne setup-e za layering zvukova — npr. jedan udarac može ići na dry trak, reverb bus, parallel compression bus i sidechain input istovremeno, sve podešeno iz jednog prozora. Za audio tehničare, ovo znači brzo podešavanje monitoring rutova, fold-down mikseva i višestrukih izlaza.

**Jedinstvenost:**
Izuzetno retko u ovom obliku. Pro Tools ima ograničen bus sistem, Logic ima aux trakove ali ne ovako fleksibilan matrix. Jedino Nuendo/Cubase ima sličnu fleksibilnost ali sa komplikovanijom konfiguracijom. Reaper je bukvalno "anything to anywhere" rutiranje.

**FluxForge status:** ✅ Imamo Advanced Routing Panel + Audio Graph Panel + Stem Routing. Routing matrix je implementiran sa 6 buseva (Master/Music/SFX/Voice/Ambience/Aux). **Ali nemamo 64 internih kanala po traku niti Pin Connector nivo kontrole.**

---

### 1.2 Folder Tracks kao Buses

**Šta radi u Reaper-u:**
Kada trak stoji unutar foldera, signal automatski ide na parent trak, stvarajući submix. Folder trak se ponaša kao bus — može imati svoje FX-ove, volume, pan. Nema potrebe za eksplicitnim bus kreiranjem.

**Ključni detalji:**
- Drag trak u folder = automatski routing
- Folder može sadržati druge foldere (neograničena dubina)
- Folder trak ima sve mogućnosti regularnog traka (FX, automation, sends)
- "Folder kompakt mode" — prikazuje samo folder header sa sumiranim metrima

**Zašto je vredno za sound dizajnere:**
Sound dizajneri mogu organizovati slojeve zvuka (attack layer, body layer, tail layer) u folder i procesirati ih zajedno ili pojedinačno. Audio tehničar može imati folder za dialog, folder za ambijente, folder za efekte — svaki sa svojim procesiranjem.

**Jedinstvenost:**
Ovo je Reaper-ova originalna inovacija. Drugi DAW-ovi zahtevaju eksplicitno kreiranje bus trakova i ručno rutiranje. Pro Tools zahteva Aux trak + sends. Logic zahteva Summing Stack kreiranje.

**FluxForge status:** ✅ Imamo bus hijerarhiju (Master/Music/SFX/Voice/Ambience/Aux) ali **folder-as-bus paradigma gde drag-and-drop kreira automatski routing NIJE implementirana.**

---

### 1.3 Sidechain Routing

**Šta radi u Reaper-u:**
Drag-and-drop rutiranje sidechain signala. Vučeš audio sa jednog traka direktno na sidechain ulaz kompresora/gate-a na drugom traku. Detector Input u ReaComp-u bira izvor sidechain signala.

**Ključni detalji:**
- Drag iz traka na FX sidechain input
- ReaComp ima "Detector Input" dropdown za izbor sidechain izvora
- Podržava multi-channel sidechain (ne samo stereo)
- Sidechain filter u kompresoru za frekventno-selektivan sidechain

**Zašto je vredno za sound dizajnere:**
Sidechain je ključan za ducking (muzika se utišava kad lik priča), ritmičke pumping efekte, i gate kontrolu (jedan zvuk otvara gate za drugi). Za game audio, sidechain ducking je standard za prioritizaciju dijaloga.

**Jedinstvenost:**
Većina DAW-ova ovo podržava, ali Reaper-ov drag-and-drop pristup je znatno jednostavniji od Pro Tools-ovog bus-baziranog sistema ili Logic-ovog send-baziranog sistema.

**FluxForge status:** ✅ Imamo sidechain podršku u Compressor Ultimate. **Drag-and-drop sidechain routing iz routing matrice treba proveriti.**

---

### 1.4 Hardware Outputs i Multi-Output

**Šta radi u Reaper-u:**
Svaki trak može slati na proizvoljne hardware izlaze, bez ograničenja na stereo master. Pin connector kontroliše koji kanali idu gde.

**Ključni detalji:**
- Nema gornje granice na broj izlaza
- Per-trak output assignment
- Hardware output monitoring sa latency compensation
- Podržava ASIO, CoreAudio, WASAPI, JACK

**Zašto je vredno za sound dizajnere:**
Audio tehničar može slati različite mikseve na različite izlaze (stage monitor mix, in-ear mix, FOH mix) iz jednog projekta. Sound dizajner može imati reference monitor na jednom izlazu i surround setup na drugom.

**FluxForge status:** ✅ Imamo I/O Selector i Control Room Panel. **Multi-output assignment per-trak treba proveriti.**

---

### 1.5 Pin Connector

**Šta radi u Reaper-u:**
Kontroliše koji od 64 internih kanala ulazi/izlazi iz svakog plugin-a u lancu. Moguće rutirati kanal 1-2 u jedan plugin, kanal 3-4 u drugi, i kombinovati ih na izlazu.

**Ključni detalji:**
- Vizuelni matrix: redovi = ulazni kanali, kolone = izlazni kanali plugin-a
- Svaki FX u chain-u ima svoj pin connector
- Omogućava mid/side procesiranje bez dodatnih trakova
- Omogućava multi-mono procesiranje stereo signala
- Kanali koji ne idu u plugin prolaze netaknuti ("pass-through")

**Zašto je vredno za sound dizajnere:**
Mid/side procesiranje — kompresuj samo mid, reverb samo na side. L/R nezavisna obrada — različit EQ na levom i desnom kanalu. Za surround, kontrola nad svakim kanalom je esencijalna.

**Jedinstvenost:**
Potpuno jedinstveno za Reaper. Nijedan drugi mainstream DAW ne nudi ovaj nivo kontrole nad internim kanalima plugin-a. Pro Tools ima ograničen channel routing u AudioSuite. Logic nema ekvivalent.

**FluxForge status:** ❌ **Nemamo Pin Connector ekvivalent. Ovo je značajan gap za napredne korisnike.**

---

## 2. Item/Media Handling

### 2.1 Take System (Multiple Takes per Item)

**Šta radi u Reaper-u:**
Svako snimanje preko postojećeg itema kreira novi "take" unutar istog itema. Prebacivanje između take-ova klikom na dropdown na vrhu itema. Take-ovi se mogu prikazati u lane-ovima za vizuelni pregled.

**Ključni detalji:**
- Neograničen broj take-ova po itemu
- Vizuelni lane-ovi (View > Show takes in lanes)
- Comping: split na granicama, izaberi take po segmentu
- Svaki take čuva sopstvene: FX, pitch, playrate, volume, pan, reverse status
- Take envelopes — per-take automatizacija
- "Glue" take-ova u finalni rezultat

**Zašto je vredno za sound dizajnere:**
Snimanje više varijacija istog zvuka (različite udarce, različite teksture) i brzo poređenje unutar istog itema. Comping — slaganje najboljeg dela iz svakog take-a — je direktan.

**Jedinstvenost:**
Pro Tools ima Playlists (slično ali sa više koraka). Logic ima Take Folders. Reaper-ova implementacija je najdirektnija — nema skrivenih menija, nema ograničenja na broj take-ova.

**FluxForge status:** ⚠️ Imamo comping lanes. **Dubina implementacije (per-take FX, per-take envelopes, per-take pitch/playrate) treba proveriti.**

---

### 2.2 Stretch Markers

**Šta radi u Reaper-u:**
Specifične tačke unutar itema koje omogućavaju lokalno istezanje/kompresiju vremena. Ručno ili automatsko postavljanje (Dynamic Split > Add stretch markers). Mogu se pomerati za fine-tuning tajminga bez uticaja na ostatak itema.

**Ključni detalji:**
- Ručno postavljanje: Shift+W na poziciji kursora
- Automatsko: Dynamic Split sa opcijom "Add stretch markers at transients"
- Pomeranje markera = lokalno time-stretch
- Gore/dole pomeranje = pitch shift na tom segmentu
- Svaki segment između markera može koristiti različit stretch algoritam
- Non-destructive — originalni fajl ostaje netaknut
- Čuva transijente dok menja sustain

**Zašto je vredno za sound dizajnere:**
Sync-ovanje zvučnog efekta sa slikom — istegnuti udarac da tačno odgovara trajanju vizuelnog efekta. Kreativno warping-ovanje za sound design — tape-stop efekat progresivnim usporavanjem.

**Jedinstvenost:**
Pro Tools ima Elastic Audio (slično ali destruktivnije). Cubase ima AudioWarp. Reaper-ova implementacija je non-destructive i per-item, sa pitch kontrolom per-segment.

**FluxForge status:** ⚠️ Imamo warp handles na timeline-u. **Stretch markers sa per-segment pitch kontrolom treba proveriti.**

---

### 2.3 Razor Edits

**Šta radi u Reaper-u:**
Alt+desni klik drag za marquee selekciju dela itema i/ili envelopa. Omogućava hirurški precizno sečenje, pomeranje, kopiranje, brisanje, ili istezanje sekcija.

**Ključni detalji:**
- Alt+desni klik drag = kreiranje razor selekcije
- Može se primeniti na mediju i automation envelope NEZAVISNO
- Selekcija može obuhvatiti više trakova istovremeno
- Akcije na selekciji: cut, copy, delete, move, stretch, split, reverse
- Razor selekcija se čuva dok se eksplicitno ne ukloni
- Može selektovati samo envelope (bez medija) za preciznu automation editaciju
- Podržava i MIDI iteme

**Zašto je vredno za sound dizajnere:**
Najbrži način za preciznu editaciju — izaberi deo zvuka, pomeri ga, bez potrebe za split/select/move/crossfade ciklusom. Posebno moćno za foley editing gde se stotine sitnih zvukova moraju precizno pozicionirati.

**Jedinstvenost:**
Potpuno jedinstveno za Reaper. Nijedan drugi DAW nema ekvivalent. Pro Tools-ov Edit selection i Logic-ov Marquee tool su najbliži ali daleko ograničeniji — ne podržavaju nezavisnu selekciju envelope-a, ne podržavaju stretch na selekciji.

**FluxForge status:** ⚠️ Imamo `edit_mode_pro` i smart tool. **Razor edit paradigma (nezavisna media/envelope selekcija + stretch na selekciji) NIJE implementirana.**

---

### 2.4 Item Properties & Non-Destructive Processing

**Šta radi u Reaper-u:**
Desni klik > Item Properties daje pristup svim parametrima itema na jednom mestu.

**Ključni detalji:**
- **Playrate:** brzina reprodukcije (0.01x do 100x)
- **Pitch:** ±24 semitona sa fine-tuning u centima
- **Preserve pitch when changing playrate:** toggle za tape-style vs time-stretch
- **Channel mode:** Mono (L), Mono (R), Mono (L+R), Stereo, Reverse stereo, Mono (downmix)
- **Snap offset:** tačka u itemu koja se "lepi" na grid umesto početka
- **Fade in/out:** oblik, trajanje, auto-crossfade
- **Position, length, rate** — precizne numeričke vrednosti
- **Notes:** tekst polje za beleške o itemu
- **Take properties:** pitch, volume, pan, phase invert per-take

**Zašto je vredno za sound dizajnere:**
Sve promene su non-destructive — originalni fajl ostaje netaknut. Eksperimentisanje sa sound dizajnom je potpuno bezrizično. Snap offset je ključan za zvukove gde je "udarac" negde u sredini fajla (ne na početku).

**FluxForge status:** ⚠️ Imamo clip properties na timelinu. **Kompletnost (snap offset, channel mode selection, notes polje) treba proveriti.**

---

### 2.5 Glue Items

**Šta radi u Reaper-u:**
Ctrl+Shift+G spaja više itema u jedan. Novi item sadrži sve procesiranje (pitch, stretch, FX) — flattened u novi fajl.

**Ključni detalji:**
- Spaja sve selektovane iteme na istom traku
- Čuva crossfade-ove između itema
- Primenjuje item FX, pitch, stretch, volume u rezultat
- Originalni fajlovi ostaju na disku (non-destructive)
- Može se un-glue (revert to original items)

**Zašto je vredno za sound dizajnere:**
Kada sound dizajner završi layering i editovanje, glue konsoliduje sve u jedan čist item za dalje procesiranje ili export. Mogućnost un-glue znači da se uvek može vratiti na originalne elemente.

**Jedinstvenost:**
Pro Tools ima "Consolidate" (ali je destruktivan). Logic ima "Bounce in Place" (ali kreira novi trak). Reaper-ov glue je in-place i reversibilan.

**FluxForge status:** ⚠️ **Bounce/consolidate sa un-glue mogućnošću treba proveriti.**

---

### 2.6 Dynamic Split

**Šta radi u Reaper-u:**
Automatsko sečenje itema na osnovu transijenata, gate threshold-a, ili tišine.

**Ključni detalji:**
- **At transients:** detektuje transijente i seče na njima
- **At gate edges:** seče gde signal pada ispod threshold-a
- **Add stretch markers:** umesto rezova, dodaje stretch markere na transijente
- **Split into ReaSamplOmatic5000 instances:** automatski kreira drum kit iz snimka
- Podešavanja: sensitivity, min slice length, pad, fade
- Preview pre primene

**Zašto je vredno za sound dizajnere:**
Brzo sečenje drum hitova, foley zvukova, ili bilo kog materijala sa jasnim transijentima. Opcija "add stretch markers" umesto rezova je jedinstvena — omogućava warping bez gubitka konteksta.

**Jedinstvenost:**
Većina DAW-ova ima transient detection i auto-split. Ali opcija da doda stretch markere umesto rezova i da automatski kreira ReaSamplOmatic5000 instrumente je potpuno jedinstvena.

**FluxForge status:** ⚠️ Imamo transient designer DSP. **Automatic split workflow sa opcijom stretch markers NIJE implementiran.**

---

### 2.7 Nudge System

**Šta radi u Reaper-u:**
Precizno pomeranje itema, kursora, ili selekcije u konfigurabilnim koracima.

**Ključni detalji:**
- Konfigurabilan nudge amount: samples, milisekunde, sekunde, frames, beats, measures
- Nudge levo/desno: item pozicija, item edge (trim), cursor, selekcija
- Nudge gore/dole: volume, pitch
- Presets za različite nudge veličine
- Keyboard shortcuts za svaki smer i veličinu

**Zašto je vredno za sound dizajnere:**
Precizno pozicioniranje zvukova prema slici — pomeri 1 frame levo, pomeri 10ms desno. Za foley, preciznost na nivou milisekundi je esencijalna.

**FluxForge status:** ⚠️ **Nudge sistem sa konfigurabilnim koracima treba proveriti.**

---

## 3. Rendering & Bouncing

### 3.1 Region Render Matrix

**Šta radi u Reaper-u:**
Kreiranje regiona na timeline-u, imenovanje ih, i eksportovanje kao zasebne fajlove sa jednim pritiskom dugmeta. Za svaki region možeš definisati koji trakovi/busevi se renderuju.

**Ključni detalji:**
- Kreiranje regiona: Shift+R (ili selektuj time range + klikni "Region" u marker panelu)
- Region Render Matrix: File > Render > "Region render matrix"
- Matrix format: redovi = regioni, kolone = trakovi/busevi
- Checkbox na preseku = "renderuj ovaj trak za ovaj region"
- Regioni mogu da se preklapaju
- Svaki region → zasebni fajl(ovi) pri renderu
- Wildcard imenovanje fajlova

**Zašto je vredno za sound dizajnere:**
Ovo je "killer feature" — kreiranje biblioteke zvukova iz jednog projekta. Imenuj region "explosion_close", drugi "explosion_distant", render sve odjednom. Za game audio, render svih varijacija jednog zvuka u jednom potezu. Za film, render svih reels-ova odjednom.

**Jedinstvenost:**
Izuzetno retko. Pro Tools nema ništa slično (zahteva ručni export svakog regiona). Nuendo ima nešto slično ali je komplikovanije. Reaper-ova Region Render Matrix je industrijski standard za batch rendering.

**FluxForge status:** ❌ **Nemamo Region Render Matrix. Imamo audio export provider ali bez region-based batch renderinga. Ovo je KRITIČAN gap za sound design workflow.**

---

### 3.2 Wildcard Tokens u Imenima Fajlova

**Šta radi u Reaper-u:**
U Render dijalogu koristiš tokene za automatsko generisanje imena fajlova i folder struktura.

**Ključni detalji — potpuna lista tokena:**
- `$project` — ime projekta
- `$region` — ime regiona
- `$regionindex` / `$regionnumber` — redni broj regiona
- `$track` — ime traka
- `$tracknumber` — redni broj traka
- `$marker(N)` — ime markera sa ID-jem N
- `$filenumber` — sekvencijalni broj fajla u batch renderu
- `$timelineorder` — redosled na timelinu
- `$timelineorder_track` — redosled po traku
- `$tempo` — tempo projekta
- `$timesig` — time signature
- `$samplerate` — sample rate
- `$starttime` — početno vreme regiona/itema
- `$year`, `$month`, `$day`, `$hour`, `$minute` — datum/vreme
- Kombinacija kreira folder strukturu: `$project/$region/$track` kreira podfoldere

**Primer za game audio:**
`SFX_$region_$tracknumber_$filenumber` → `SFX_explosion_01_001.wav`

**Zašto je vredno za sound dizajnere:**
Eliminše ručno imenovanje stotina fajlova. Za game audio, automatsko imenovanje po konvenciji klijenta/engine-a. Za biblioteke zvukova, konzistentno imenovanje po kategorijama.

**Jedinstvenost:**
Nijedan drugi DAW ne nudi ovaj nivo fleksibilnosti u imenovanju renderovanih fajlova. Pro Tools ima fiksne naming konvencije. Logic nema wildcard sistem.

**FluxForge status:** ❌ **Nemamo wildcard token sistem za render. KRITIČAN gap.**

---

### 3.3 Batch Rendering & Stem Export

**Šta radi u Reaper-u:**
Stem Manager omogućava čuvanje i pozivanje višestrukih solo/mute stanja i batch renderovanje svih konfiguracija.

**Ključni detalji:**
- Stem Manager: selektuj trakove > Save stem configuration
- Više konfiguracija: "Dialog stems", "Music stems", "FX stems"
- Render Queue: dodaj više render konfiguracija u queue
- Sekvencijalno renderovanje bez reload-ovanja projekta
- Podržava: WAV, AIFF, MP3, OGG, FLAC, WavPack, MIDI
- Bit depth: 8, 16, 24, 32, 64 (float)
- Sample rate: bilo koji
- Dither opcije
- Normalize opcije (peak, RMS, LUFS)
- Tail length za reverb/delay
- Multi-channel rendering (surround)

**Zašto je vredno za sound dizajnere:**
Isporuka stem-ova za film/TV/igre — jedan klik renderuje sve potrebne formate i konfiguracije. Render queue za batch procesiranje velikih projekata.

**Jedinstvenost:**
Pro Tools zahteva pojedinačne bounce-ove ili skripte. Nuendo ima sličan sistem ali je skuplji. Logic ima Bounce All Tracks ali bez konfigurabilnog stem sistema.

**FluxForge status:** ⚠️ Imamo audio export provider. **Stem Manager sa konfiguracijom i render queue NIJE implementiran.**

---

### 3.4 Render Presets & Loudness Report

**Šta radi u Reaper-u:**
Čuvanje render podešavanja kao preset-a i generisanje loudness izveštaja.

**Ključni detalji:**
- Render Presets: format + sample rate + bit depth + dither + naming = preset
- Presets za razlicite destinacije: "Broadcast -24 LUFS", "Spotify -14 LUFS", "Film -27 LUFS"
- **Loudness Report:** interaktivan HTML fajl sa:
  - Integrated LUFS
  - Short-term LUFS graf
  - Momentary LUFS graf
  - True Peak level
  - Loudness Range (LRA)
  - Clipping detection
- **Dry Run:** analiza bez pisanja fajlova — proveriš loudness pre renderovanja
- Report se generiše za svaki stem/region/master render

**Zašto je vredno za sound dizajnere:**
Audio tehničari moraju isporučiti u različitim formatima i loudness standardima. Jedan preset po standardu + automatski loudness report eliminišu potrebu za eksternim alatima (WLM, Youlean).

**Jedinstvenost:**
HTML loudness report sa dry-run opcijom je jedinstven za Reaper. Nijedan drugi DAW ne generiše interaktivni izveštaj automatski pri renderu.

**FluxForge status:** ⚠️ Imamo Limiter Ultimate sa LUFS metering-om i loudness targets (8 platformi). **HTML loudness report i render presets NISU implementirani.**

---

## 4. FX Chain & Processing

### 4.1 FX Chains (Save/Load)

**Šta radi u Reaper-u:**
Serijsko procesiranje plugin-ova na traku ili itemu. Čuvanje celog lanca kao .rfxchain preset.

**Ključni detalji:**
- Drag-and-drop reorder plugin-ova u chain-u
- Save chain: desni klik > "Save FX chain as..."
- Load chain: "Add FX" > browse chains
- Chain sadrži: plugin-e, njihova podešavanja, redosled, wet/dry mix
- Podeljene u kategorije/foldere za organizaciju
- FX chain se može primeniti na trak ILI na item

**FluxForge status:** ✅ Imamo insert chains. **Save/load FX chain presets treba proveriti.**

---

### 4.2 FX Containers (REAPER 7+)

**Šta radi u Reaper-u:**
Grupe plugin-ova koje žive unutar jednog kontejnera sa konfigurabilnim parameter mapping-om i internim rutiranjem.

**Ključni detalji:**
- Kontejner = "plugin koji sadrži plugin-e"
- Interni routing: serijski, paralelni, ili custom (via pin connector)
- **Parameter mapping:** do 16 makro kontrola koje kontrolišu parametre unutrašnjih plugin-a
- Kontejneri se mogu **gnezditi** (kontejner u kontejneru)
- Čuvanje kontejnera kao preset — ponovo koristi kompleksne lance kao jedan "plugin"
- UI: kontejner se pojavljuje kao jedan red u FX chain-u sa expand/collapse

**Primer za sound design:**
Multi-band distortion kontejner:
- Splitter (3-band crossover)
- Low band → tube saturation
- Mid band → tape saturation
- High band → soft clip
- Mixer (recombine)
- Sve kontrolisano sa 3 makro knoba (drive per band)

**Jedinstvenost:**
Cubase ima sličnu funkcionalnost sa Channel Strip-om. Ableton ima Rack-ove. Ali Reaper-ovi kontejneri su potpuno fleksibilni, gnjezdivi, i rade sa bilo kojim plugin formatom.

**FluxForge status:** ❌ **Nemamo FX Container koncept. Imamo insert chains ali ne nestable kontejnere sa parameter mapping-om.**

---

### 4.3 Parallel FX Chains (REAPER 7+)

**Šta radi u Reaper-u:**
Bilo koji FX u lancu može biti postavljen da radi paralelno umesto serijski.

**Ključni detalji:**
- Desni klik na FX > "Run in parallel with previous FX"
- Vizuelna oznaka: `||` između paralelnih plugin-a
- Signal se deli, svaki plugin dobija kopiju, rezultati se sumiraju
- Podržava wet/dry mix per-plugin
- Više plugin-a može biti u istoj paralelnoj grupi
- Nema potrebe za kreiranje dodatnih trakova ili sends-a

**Primer za sound design:**
- Clean signal ⟶ EQ ⟶ Output
- Clean signal ⟶ Distortion ⟶ ||Output (paralelno sa EQ)
- Clean signal ⟶ Reverb ⟶ ||Output (paralelno sa oba)

**Jedinstvenost:**
Veoma retko u tradicionalnim DAW-ovima. Ableton ima Rack-ove za ovo, Bitwig ima "The Grid". U kontekstu klasičnog DAW interfejsa, potpuno jedinstveno za Reaper.

**FluxForge status:** ❌ **Nemamo inline parallel FX mode. Parallel processing zahteva kreiranje dodatnih trakova/sends.**

---

### 4.4 Pin Connector (detalji)

**Šta radi u Reaper-u:**
Kontroliše koji od 64 internih kanala ulazi/izlazi iz svakog plugin-a u lancu.

**Ključni detalji:**
- UI: matrix grid — redovi = ulazni kanali, kolone = plugin kanali
- Klik na presek = routing
- "Pass-through" kanali koji zaobilaze plugin
- Svaki FX u chain-u ima SOPSTVENI pin connector
- Primeri korišćenja:
  - **Mid/side:** encode stereo u M/S, procesuj mid i side razlicitim EQ-om, decode nazad
  - **Multi-mono:** L kanal kroz jedan reverb, R kanal kroz drugi
  - **Surround:** svaki kanal (L/R/C/LFE/Ls/Rs) kroz drugačiji procesing
  - **Sidechain filter:** rutiranje sidechain signala na specifične kanale plugin-a

**FluxForge status:** ❌ **Nemamo ekvivalent. Ovo zahteva arhitekturnu promenu u tome kako FX chain procesira kanale.**

---

### 4.5 JSFX (Jesusonic FX)

**Šta radi u Reaper-u:**
Tekst-bazirani plugin-i pisani u EEL2 jeziku koji se kompajliraju on-the-fly.

**Ključni detalji:**
- **Jezik:** EEL2 (Expression Evaluation Language) — C-like sintaksa
- **Kompilacija:** instant, u realnom vremenu dok edituješ
- **Editor:** ugrađen u Reaper sa syntax highlighting i debugger-om
- **Mogućnosti:**
  - Audio procesiranje (sample-by-sample ili block-based)
  - MIDI procesiranje
  - Video procesiranje
  - Custom GUI sa slider-ima, grafovima, metrima
  - Pristup FFT, trigonometrija, string operacije
- **Performanse:** kompajlirani kod, blizu C performansi
- **Biblioteka:** 200+ ugrađenih JSFX, stotine community efekata
- **Primeri ugrađenih:**
  - Convolution reverb
  - Granular delay/looper
  - Spectral analyzer
  - MIDI harmonizer
  - Loudness meter
  - Tube simulator

**Zašto je vredno za sound dizajnere:**
Power users mogu napisati custom plugin za specifičnu potrebu za 30 minuta. Npr. specijalizovan pitch shifter koji prati dinamiku ulaznog signala, ili granular delay sa custom grain shaping.

**Jedinstvenost:**
Potpuno jedinstveno za Reaper. Nijedan drugi DAW nema ugrađeni, skriptabilni plugin format sa instant kompilacijom, debugovanjem, i GUI mogućnostima.

**FluxForge status:** ⚠️ Imamo FluxMacro sistem (53 tasks). **JSFX-style user-scriptable audio effects (sa sample-level processing) NIJE implementiran. FluxMacro je više workflow automation, ne DSP scripting.**

---

### 4.6 FX Parameter Modulation

**Šta radi u Reaper-u:**
Linkovanje parametara između plugin-ova — modulacija jednog parametra drugim.

**Ključni detalji:**
- **LFO modulation:** sine, triangle, square, sawtooth, random — na bilo koji FX parametar
- **Audio signal modulation:** ulazni audio kontroliše FX parametar (envelope follower)
- **MIDI CC modulation:** MIDI kontroler menja FX parametar
- **Parameter linking:** parametar A kontroliše parametar B (isti ili različit plugin)
  - Smer: normal, inverted
  - Scale: koliko jaako A utiče na B
  - Offset: bazna vrednost B
  - Curve: linearna, logaritamska, eksponencijalna
- **Baseline mode:** modulacija oko centralne vrednosti ili od minimuma

**Zašto je vredno za sound dizajnere:**
Modulacija je osnova kreativnosti u sound dizajnu — LFO na filter cutoff-u za pokret, envelope follower za reaktivno procesiranje, linkovanje parametara za kompleksne performanse.

**Jedinstvenost:**
Ableton ima Max for Live, Bitwig ima ugrađenu modulaciju (najmoćnija). Reaper-ova implementacija je manje vizuelna od Bitwig-ove ali jednako moćna i funkcioniše sa svim plugin formatima.

**FluxForge status:** ⚠️ Imamo LFO i envelope follower u Saturator Ultimate i Delay Ultimate. **Generička FX parameter modulation (LFO/envelope follower na BILO KOJI parametar BILO KOG plugin-a) NIJE implementirana.**

---

### 4.7 Per-Effect Wet/Dry Mix

**Šta radi u Reaper-u:**
Svaki plugin u chain-u ima sopstveni wet/dry knob, nezavisno od toga da li plugin sam ima tu opciju.

**Ključni detalji:**
- Desni klik na plugin > "Set wet/dry mix"
- Slider od 0% (dry) do 100% (wet)
- Radi sa SVIM pluginima, čak i onima bez ugrađenog mix knoba
- Implementirano na host nivou — plugin ne mora da podržava ovu funkciju

**Zašto je vredno za sound dizajnere:**
Parallel processing bez kreiranje trakova — npr. 30% distortion blend sa original signalom. Mnogi kvalitetni plugin-i (posebno stariji) nemaju mix knob.

**Jedinstvenost:**
Retko kao host-level funkcija. Većina DAW-ova zahteva da plugin sam ima mix kontrolu ili da se kreira parallel trak.

**FluxForge status:** ⚠️ Naši Ultimate procesori imaju mix knob. **Host-level wet/dry za SVE plugin-e treba proveriti.**

---

## 5. Automation

### 5.1 Automation Modes

**Šta radi u Reaper-u:**
Pet režima za automatizaciju sa različitim ponašanjem.

**Ključni detalji:**
- **Trim/Read (default):** playback automatizacija; kontrole menjaju overall nivo nezavisno od fader pozicije — idealno za globalne adjustmente nakon crtanja automatizacije
- **Read:** striktni playback, kontrole ne upisuju promene
- **Write:** uvek upisuje, čak i kad se ne reprodukuje — opasan režim, koristi se retko
- **Touch:** upisuje samo dok držiš kontrolu, vraća se na prethodnu vrednost kad pustiš — najčešći režim za fine-tuning
- **Latch:** počinje upisivanje kad promeniš parametar, drži novu vrednost do zaustavljanja playback-a — za dugačke promene

**Zašto je vredno za sound dizajnere:**
Touch mode je idealan za fino podešavanje — npr. blago podizanje volumena u delu koji je pretih. Trim mode je izuzetno moćan: možeš nacrtati detaljnu automatizaciju, a onda jednim fader-om podići ili spustiti celokupan nivo bez uništavanja oblika krivulje.

**FluxForge status:** ⚠️ Imamo automation provider/lanes. **Automation modes (trim/read/touch/latch/write) treba proveriti.**

---

### 5.2 Automation Items

**Šta radi u Reaper-u:**
Kontejneri za envelope podatke koji se mogu loop-ovati, kopirati, istezati i pool-ovati kao regularni media itemi.

**Ključni detalji:**
- Kreiranje: Insert automation item na envelope lane
- Duplim klikom na automation item: pristup LFO podešavanjima (sine/triangle/square/sawtooth/random)
- **Looping:** automation item se ponavlja — idealno za ritmičke efekte
- **Copy/paste:** iste automatizacije na više mesta
- **Stretch:** istezanje automation itema menja "brzinu" automatizacije
- **Stacking:** više automation itema na istom envelope-u — aditivno se sabiraju
- **Pool-ovanje:** pool-ovane kopije dele podatke — edituj jednu, sve se menjaju

**Zašto je vredno za sound dizajnere:**
LFO tremolo na 20 mesta u projektu — jedan edit menja sve pool-ovane kopije. Ritmički filter sweep koji se loop-uje bez ručnog crtanja svake tacke. Stacking za kombinovanje baseline automatizacije sa LFO modulacijom.

**Jedinstvenost:**
Potpuno jedinstveno za Reaper. Nijedan drugi DAW nema koncept "automation itema" koji se ponašaju kao media itemi sa looping-om, pooling-om i stacking-om.

**FluxForge status:** ❌ **Nemamo Automation Items koncept. Imamo automation lanes sa tačkama ali ne kontejnerizovane, loop-ovane, pool-ovane automation blokove.**

---

### 5.3 Take Envelopes (Per-Item Automation)

**Šta radi u Reaper-u:**
Automatizacija na nivou itema (take-a), ne traka. Svaki take može imati sopstvene envelope.

**Ključni detalji:**
- Dostupni take envelopes: Volume, Pan, Mute, Pitch, Playrate
- Per-take FX parameter envelopes — automatizuj parametar item-level FX-a
- Envelopes se premeštaju zajedno sa itemom
- Nezavisni od track-level automatizacije — oba se primenjuju (multiplikativno)
- Prikazuju se unutar itema na timeline-u

**Zašto je vredno za sound dizajnere:**
Svaki zvuk može imati svoju automatizaciju koja se premešta zajedno sa njim. Ako pomeriš zvučni efekat na drugu poziciju na timelinu, automatizacija ide sa njim. Na track nivou, automatizacija ostaje na mestu.

**Jedinstvenost:**
Retko. Pro Tools nema take-level automatizaciju (clip gain je jedino slično). Logic ima region-based automation ali je manje fleksibilna i ne podržava FX parameter envelopes.

**FluxForge status:** ❌ **Nemamo per-item/per-take automation envelopes. Automatizacija je samo na track nivou.**

---

## 6. Custom Actions & Macros

### 6.1 Action List

**Šta radi u Reaper-u:**
Centralni registar SVIH akcija u Reaperu.

**Ključni detalji:**
- Pristup: `?` taster ili Actions > Show Action List
- **3000+** ugrađenih akcija
- Pretraga po imenu
- Sekcije: Main, MIDI Editor, Media Explorer, MIDI Inline Editor
- Svaka akcija ima jedinstveni command ID
- Mapiranje na keyboard shortcut, MIDI CC, toolbar dugme, ili OSC komandu
- Filter po kategoriji, shortcut-u, custom action statusu
- "Run" dugme za instant izvršavanje bez mapiranja

**FluxForge status:** ⚠️ FluxMacro sistem pokriva automation aspect. **Centralizovani Action List UI sa pretragom i mapiranjem NIJE implementiran kao poseban panel.**

---

### 6.2 Custom Actions (Macros)

**Šta radi u Reaper-u:**
Kombinovanje više akcija u jednu sekvencijalnu makro komandu.

**Ključni detalji:**
- Kreiranje: Action List > "New action" > "New custom action"
- Drag akcije u custom action listu
- Sekvencijalno izvršavanje (top to bottom)
- Može sadržati: ugrađene akcije, SWS akcije, skripte, druge custom actions
- Custom action se pojavljuje u Action List-u kao regularna akcija
- Može se mapirati na shortcut/toolbar/MIDI

**Primer za sound design workflow:**
"Prepare SFX for Export" custom action:
1. Split item at transients (Dynamic Split)
2. Normalize each item to -1dB
3. Add fade in (10ms)
4. Add fade out (50ms)
5. Name items by position
6. Create regions from items
— sve jednim tasterom.

**FluxForge status:** ✅ FluxMacro sistem (53 tasks done) pokriva ovo. **Treba proveriti koliko je moćan u poređenju.**

---

### 6.3 Cycle Actions (SWS)

**Šta radi u Reaper-u:**
Svako pozivanje akcije izvršava sledeći korak u ciklusu.

**Ključni detalji:**
- Korak 1 se izvršava prvi put, korak 2 sledeći put, i tako u krug
- Podržava: kondicionalne (if/then), ponavljanja, naprednu logiku
- "Cycle Action Editor" u SWS Extensions
- Može kombinovati ugrađene akcije, SWS akcije, skripte

**Primer:**
Toggle prikaz jednim tasterom:
1. Poziv → Waveform peaks view
2. Poziv → Spectral peaks view
3. Poziv → Spectrogram view
4. Poziv → Waveform peaks view (ciklus se ponavlja)

**Jedinstvenost:**
Potpuno jedinstveno za Reaper/SWS ekosistem. Nijedan drugi DAW nema ciklične akcije.

**FluxForge status:** ❌ **Nemamo cycle actions. FluxMacro bi mogao da se proširi sa ovom funkcionalnošću.**

---

### 6.4 ReaScript (Lua/EEL/Python)

**Šta radi u Reaper-u:**
Punopravno skriptiranje unutar Reapera sa pristupom svim API funkcijama.

**Ključni detalji:**
- **Jezici:** EEL2 (najbrži, interni), Lua (najlakši za učenje), Python (najširi ekosistem)
- **API pristup:** pozivanje bilo koje Reaper akcije + pristup većini C++ API funkcija
- **UI kreiranje:** dedicated script window sa drawing primitivima, loading images, mouse input
- **MIDI manipulacija:** čitanje/pisanje MIDI događaja u realnom vremenu
- **Automatizacija:** batch operacije na itemima, trakovima, envelope-ima
- **Editor:** ugrađen sa syntax highlighting, breakpoints, output console
- **Distribucija:** ReaPack package manager za deljenje skripti
- **Popularne community skripte:**
  - Script: Dynamic Reaper Item Split (DRIS)
  - Script: Batch renamer sa regex podrškom
  - Script: Auto-region creator po itemima
  - Script: Loudness normalizer sa custom LUFS target-om
  - Script: SFX librarian sa metadata editovanjem

**FluxForge status:** ⚠️ FluxMacro sistem postoji. **Lua/Python scripting sa punim API pristupom NIJE implementiran. Ovo je ogroman ekosistem gap.**

---

## 7. Project Organization

### 7.1 Track Manager

**Šta radi u Reaper-u:**
Prozor za pregled i kontrolu svih trakova sa filterima.

**Ključni detalji:**
- Lista svih trakova sa: ime, boja, visibility toggle, lock toggle, FX bypass toggle
- Pretraga po imenu
- Batch operacije: selektuj više trakova i promeni visibility/lock/color
- "Show only selected" filter
- Track height presets
- Drag-and-drop reorder
- Folder expand/collapse

**FluxForge status:** ⚠️ **Track manager panel treba proveriti.**

---

### 7.2 Markers & Regions

**Šta radi u Reaper-u:**
Navigacioni i organizacioni sistem na timeline-u.

**Ključni detalji:**
- **Markers (M taster):** označavaju pojedinačne tačke — sync points, cue points, notes
- **Regions (Shift+R):** označavaju opsege sa početkom i krajem — sekcije pesme, SFX granice, render zone
- **Region/Marker Manager:** editovanje imena, trajanja, boja i ID-jeva za sve na jednom mestu
- **Boje:** svaki marker/region može imati svoju boju
- **Navigacija:** klik na marker = skok na tu poziciju
- **Projekat Notes:** tekst beleške vezane za marker
- **SWS Marker Actions:** akcije koje se triggeruju kad play cursor pređe marker (`!` + action ID u imenu markera)

**FluxForge status:** ⚠️ Imamo marker/tempo/video trakove. **Region Manager panel i Marker Actions treba proveriti.**

---

### 7.3 Project Tabs

**Šta radi u Reaper-u:**
Više projekata otvorenih istovremeno u tabovima.

**Ključni detalji:**
- Svaki tab = kompletno nezavisan projekat
- Copy/paste itema između tabova
- Drag-and-drop transfer
- Svaki tab ima sopstveni undo history
- Razmena FX chain presets-a između projekata
- "Pin" tab da spreči zatvaranje
- Ctrl+Tab za brzo prebacivanje

**Zašto je vredno za sound dizajnere:**
Biblioteka zvukova u jednom tabu, aktivni projekat u drugom — drag-and-drop transfer. Uporedite mikseve iz različitih sesija. Reference projekat za A/B poređenje.

**Jedinstvenost:**
Retko. Pro Tools nema project tabove (zahteva zatvaranje jednog projekta da otvorite drugi). Cubase/Nuendo ima ograničenu varijantu. Logic nema tabove.

**FluxForge status:** ❌ **Nemamo project tabs. Jedan projekat = jedan prozor.**

---

### 7.4 Sub-Projects

**Šta radi u Reaper-u:**
Reaper projekti (.rpp) mogu biti korišćeni na timeline-u kao media itemi.

**Ključni detalji:**
- Insert sub-project: Insert > Media File > izaberi .rpp fajl
- Sub-projekat se prikazuje kao renderovani audio item
- Dvostruki klik = otvori sub-projekat u novom tabu
- Save sub-projekta → automatski renderuje .rpp-prox (proxy audio)
- `=START` i `=END` markeri u sub-projektu definišu granice
- Sub-projekti mogu sadržati druge sub-projekte (neograničena dubina)
- Master rate/pitch automatizacija sub-projekta za kreativno warping-ovanje

**Zašto je vredno za sound dizajnere:**
Hijerarhija projekata — svaki SFX je zaseban projekat sa svojim procesiranjem:
- `Explosion_Close.rpp` (sub-projekat)
- `Explosion_Distant.rpp` (sub-projekat)
- `Explosions_Master.rpp` (master projekat koji sadrži oba kao iteme)

Za game audio, svaka varijacija zvuka je sub-projekat, master organizuje sve.

**Jedinstvenost:**
Nuendo ima sličnu funkcionalnost sa MediaBay integracijom. Pro Tools nema pravi sub-project sistem. Logic nema ekvivalent.

**FluxForge status:** ❌ **Nemamo sub-projects. Ovo zahteva arhitekturnu podršku za ugneždene projekte.**

---

### 7.5 Track Lanes

**Šta radi u Reaper-u:**
Vizuelni lane-ovi unutar jednog traka za upravljanje take-ovima i layering.

**Ključni detalji:**
- Svaki trak može imati N lane-ova
- Lane-ovi prikazuju take-ove za comping
- Lane-ovi se mogu koristiti za layering nezavisnih zvukova
- Vertical stacking — vizuelno jasno koji zvuci su na istom traku
- Per-lane mute/solo
- Drag između lane-ova za reorganizaciju

**FluxForge status:** ⚠️ Imamo comping lanes. **Detalji implementacije treba proveriti.**

---

## 8. Media Explorer

### 8.1 Built-in Media Browser

**Šta radi u Reaper-u:**
Integrisani browser za pretraživanje medija na disku sa preview mogućnostima.

**Ključni detalji:**
- **Pristup:** Ctrl+Alt+X (ili View > Media Explorer)
- **Preview:** klikni na fajl da čuješ preview pre importa
- **Preview routing:** preview audio može ići na dedicirani trak (ne samo na master)
- **Tempo/pitch matching:** preview se sinhronizuje sa projektnim tempom i key-em
- **Favorites:** bookmark foldere za brzi pristup
- **History:** lista nedavno pregledanih folddera
- **File types:** WAV, AIFF, MP3, FLAC, OGG, MIDI, video, RPP
- **Shortcut insert:** Enter = insert na kursor poziciji, ili drag-and-drop na timeline
- **Database caching:** za brži pregled velikih biblioteka
- **Dockable:** može biti dockovan u bilo koju poziciju UI-ja

**FluxForge status:** ⚠️ Imamo audio pool/browser panel. **Preview routing, tempo matching, favorites, history treba proveriti.**

---

### 8.2 Metadata Reading & Editing

**Šta radi u Reaper-u:**
Čitanje i editovanje BWF i ID3 metadata direktno iz Media Explorer-a.

**Ključni detalji:**
- **Čitanje:** BWF Description, BPM, Key, Artist, Genre, Comment, ISRC
- **Editovanje:** desni klik > "Edit metadata" za promenu polja
- **Pretraga po metadata:** pretraži biblioteku po BWF Description ili ID3 tagovima
- **Batch metadata editing:** selektuj više fajlova, edituj metadata za sve odjednom
- **Wildcard search u metadata:** `explosion AND close NOT reverb`
- **Custom columns:** prikaži koje metadata polja želiš u browser listi
- **iXML podrška:** čitanje iXML metadata iz profesionalnih snimaka (scene, take, notes)

**Zašto je vredno za sound dizajnere:**
Tagiranje zvukova sa opisima i ključnim rečima direktno u DAW-u. Pretraživanje biblioteke od 100k+ zvukova po sadržaju umesto po imenu fajla. Eliminiše potrebu za eksternim alatima (Soundminer $300+, BaseHead $200+).

**Jedinstvenost:**
Retko za ugrađen DAW browser. Pro Tools Workspace ima osnovni metadata prikaz ali ne editovanje. Logic nema metadata pretragu. Jedino Nuendo MediaBay nudi sličnu funkcionalnost.

**FluxForge status:** ❌ **Metadata reading/editing/search u audio browser-u NIJE implementiran. Značajan gap za profesionalne sound dizajnere.**

---

### 8.3 Advanced Search Operators

**Šta radi u Reaper-u:**
Boolean pretraga u Media Explorer-u.

**Ključni detalji:**
- **AND:** `explosion AND close` — oba termina moraju biti prisutna
- **OR:** `explosion OR blast` — bar jedan termin
- **NOT:** `explosion NOT reverb` — isključi termine
- **Kombinacija:** `(explosion OR blast) AND close NOT reverb`
- **Pretraga po:** imenu fajla, metadata poljima, path-u
- **Case insensitive:** podrazumevano

**FluxForge status:** ❌ **Boolean search u media browser-u NIJE implementiran.**

---

## 9. SWS Extensions

### 9.1 Snapshots

**Šta radi u Reaper-u:**
Čuvanje i pozivanje stanja miksa — instant A/B poređenje.

**Ključni detalji:**
- **10 kategorija parametara za čuvanje:** Volume, Pan, Mute/Solo, FX Chain (sa/bez parametara), Sends, Faze/Polarity, Track Selection, Visibility, Track Names, Clip Gain
- **Selective recall:** pozovi samo volume iz snapshot-a A i FX iz snapshot-a B
- **All tracks ili selected:** čuvaj stanje svih trakova ili samo selektovanih
- **Instant switch:** bez reload-ovanja, bez delay-a
- **Naming:** svaki snapshot ima ime za identifikaciju
- **Mix history:** efektivno čuvaš "verzije" miksa

**Primer korišćenja:**
- Snapshot 1: "Dry mix — no FX"
- Snapshot 2: "Wet mix — full reverb"
- Snapshot 3: "Client A request — louder vocals"
- Snapshot 4: "Client B request — more bass"
- Instant prebacivanje jednim klikom.

**Jedinstvenost:**
Pro Tools nema ekvivalent (VCA i Scene automation su ograničeniji). Logic nema mix snapshot sistem. Cubase ima MixConsole History ali je manje fleksibilan. Potpuno jedinstveno za Reaper/SWS.

**FluxForge status:** ❌ **Nemamo Mix Snapshots sistem. Ovo je relativno laka implementacija sa visokim impaktom.**

---

### 9.2 Auto-Color/Icon/Layout

**Šta radi u Reaper-u:**
Automatsko bojenje trakova, markera i regiona na osnovu imena.

**Ključni detalji:**
- **Pravila:** definisanje regex pattern-a i pridružene boje
  - Primer: `*vox*` → zelena, `*drum*` → crvena, `*sfx*` → narandžasta
- **Auto-Icon:** automatsko dodeljivanje ikona trakovima po imenu
- **Auto-Layout:** automatsko podešavanje track height-a i lane prikaza po tipu
- **Primena:** automatski pri kreiranju traka ili batch na postojeće
- **Import/Export:** deljenje pravila među korisnicima

**FluxForge status:** ❌ **Nemamo auto-color pravila. Ručno bojenje postoji ali ne automatsko po imenu.**

---

### 9.3 Region Playlist

**Šta radi u Reaper-u:**
Non-linearni playback baziran na regionima.

**Ključni detalji:**
- Definiši redosled reprodukcije regiona nezavisno od pozicije na timeline-u
- Primer: reprodukuj Region 3, pa Region 1, pa Region 5
- Looping pojedinih regiona u playlist-u
- "Smooth Seek" za glatke prelaze između regiona
- Export playlist-e kao tekst/CSV

**Zašto je vredno za sound dizajnere:**
Prezentacija zvučnih efekata klijentu — kreiranje "playlist-e" različitih zvukova za audiciju bez premeštanja itema. Review sesije gde klijent želi da čuje specifične zvukove u specifičnom redosledu.

**FluxForge status:** ❌ **Nemamo Region Playlist.**

---

### 9.4 Console Extension

**Šta radi u Reaper-u:**
Komandna linija za brzo izvršavanje akcija.

**Ključni detalji:**
- Otvaranje: SWS > Open console
- Kucanje imena akcije ili dela imena
- Fuzzy matching — ne mora da bude tačno ime
- Instant izvršavanje bez navigacije kroz menije
- History prethodno izvršenih komandi

**Jedinstvenost:**
Slično Spotlight-u/Alfred-u na macOS-u, ali za DAW akcije. Potpuno jedinstveno u DAW svetu.

**FluxForge status:** ❌ **Nemamo command palette / console. Ovo je relativno laka implementacija.**

---

### 9.5 Marker Actions

**Šta radi u Reaper-u:**
Akcije vezane za timeline pozicije — triggeruju se kada play cursor pređe marker.

**Ključni detalji:**
- Ime markera sadrži `!` + command ID: `!_SWS_SAVEVIEW` — triggeruje SWS Save View akciju
- Može triggerovati: bilo koju Reaper akciju, custom action, skriptu
- Više akcija na istom markeru (razdvojene razmakom)
- Korisno za: automatsko prebacivanje screenset-a po sekciji, automatsko solo-ovanje trakova, cue-based procesiranje

**Zašto je vredno za sound dizajnere:**
Automatizacija bazirana na poziciji — kad pesma dođe do chorus-a, automatski se menja layout. Za interaktivni audio testing, triggerovanje test akcija na specifičnim pozicijama.

**FluxForge status:** ❌ **Nemamo timeline-triggered actions u DAW sekciji. SlotLab ima EventRegistry ali je odvojen sistem.**

---

## 10. Sound Design Specific

### 10.1 Pitch Envelope (Take Pitch Envelope)

**Šta radi u Reaper-u:**
Per-item envelope za kontrolu pitch-a kroz vreme.

**Ključni detalji:**
- **Pristup:** desni klik na item > Take > Take pitch envelope
- **Default opseg:** ±3 semitona (preporučeno proširiti na ±12 ili više)
- **Rezolucija:** centi (1/100 semitona)
- **Crtanje:** olovka, freehand, ili numerički unos
- **Pitch shift kvalitet:** podržava sve Reaper time-stretch algoritme
- **Kombinacija sa playrate:** pitch envelope + playrate envelope = potpuna kontrola nad tonom i brzinom

**Primeri za sound design:**
- **Doppler efekat:** pitch envelope koji pada sa C# na B dok auto prolazi
- **Rising tension:** postepen rast pitch-a od 0 do +5 semitona tokom 10 sekundi
- **Tape wobble:** blaga LFO modulacija pitch-a za vintage karakter
- **Kreativni dizajn:** drastična pitch promena za alien/robotic glasove

**Jedinstvenost:**
Pro Tools nema per-item pitch envelope (zahteva Elastic Audio + track automation). Logic ima Flex Pitch ali je primarno za vokale. Reaper-ova implementacija je najfleksibilnija za sound dizajn jer je per-item i non-destructive.

**FluxForge status:** ❌ **Nemamo per-item pitch envelope. Imamo `rf-pitch` crate ali ne UI za per-item pitch envelope crtanje.**

---

### 10.2 Playrate Envelope

**Šta radi u Reaper-u:**
Kontrola brzine reprodukcije itema sa opcijom da pitch prati promenu brzine.

**Ključni detalji:**
- **Pristup:** desni klik na item > Take > Take playrate envelope
- **Opcija "Preserve pitch when changing playrate":**
  - ON: menja brzinu, pitch ostaje isti (time-stretch)
  - OFF: menja brzinu I pitch (tape-style)
- **Opseg:** 0.01x do 100x (podrazumevano 0.1x do 4x)
- **Automatizacija:** crtanje krivulje promene brzine kroz vreme

**Primeri za sound design:**
- **Tape stop:** postepeno usporavanje od 1x do 0x — klasičan vinly/tape efekat
- **Speed ramp:** normalna brzina → ubrzanje → normalna brzina za dramatičan efekat
- **Slow-motion audio:** usporavanje eksplozije na 0.25x za epski efekat
- **Varispeed:** korišćenje playrate za realistično menjanje brzine magnetofona

**Jedinstvenost:**
Veoma retko kao per-item kontrola. Većina DAW-ova nema playrate envelope — nude samo globalni playback speed ili clip-based time-stretch.

**FluxForge status:** ❌ **Nemamo per-item playrate envelope.**

---

### 10.3 Non-Destructive Reverse

**Šta radi u Reaper-u:**
Instant obrtanje zvuka bez kreiranja novog fajla.

**Ključni detalji:**
- **Pristup:** desni klik > Item settings > Reverse active take
- **Instant:** nema renderovanja, nema čekanja
- **Non-destructive:** originalni fajl ostaje netaknut
- **Toggle:** klikni ponovo da vratiš u normalno stanje
- **Pitch/stretch:** čuva pitch i stretch podešavanja

**Primeri za sound design:**
- **Reverse reverb:** reverb tail → reverse → pad pre udarca
- **Reverse cymbal:** swell efekat pre downbeat-a
- **Reverse speech:** za horror/sci-fi atmosferu
- **Sound design eksperimentisanje:** brzo probanje kako zvuk zvuči unatraške

**FluxForge status:** ⚠️ **Non-destructive reverse treba proveriti.**

---

### 10.4 Item-Level FX (Take FX)

**Šta radi u Reaper-u:**
FX chain se može primeniti na individualni item umesto na ceo trak.

**Ključni detalji:**
- **Pristup:** desni klik na item > "Take FX chain" ili Shift+E dok je item selektovan
- **Svaki item** može imati sopstveni skup plugin-ova
- **Procesiranje:** item FX se procesira PRE track FX-a
- **Nezavisnost:** različiti zvuci na istom traku mogu imati potpuno različit FX
- **Take FX vs Track FX:** Take FX = per-clip, Track FX = per-track. Oba se primenjuju.
- **"Render take FX":** flatten take FX u novi take dok originalni ostaje (A/B poređenje)
- **Per-effect mix:** svaki plugin u take FX chain-u ima sopstveni wet/dry

**Zašto je ovo #1 feature za sound dizajnere:**
U tipičnom sound design projektu, imaš 200 različitih zvukova. Bez item-level FX, svaki zvuk koji zahteva drugačiji procesing mora biti na zasebnom traku → projekat sa 200 trakova. Sa item-level FX, svi zvuci mogu biti organizovani tematski (npr. svi zvuci eksplozija na jednom traku) sa per-zvuk procesiranjem.

**Jedinstvenost:**
Potpuno jedinstveno za Reaper. Nijedan drugi mainstream DAW ne nudi per-item FX chains. Ovo je NAJČEŠĆI razlog zašto sound dizajneri biraju Reaper nad Pro Tools-om i drugim DAW-ovima.

**FluxForge status:** ❌ **NEMAMO Item-Level FX. Ovo je NAJKRITIČNIJI gap za sound design workflow. Zahteva arhitekturnu podršku u rf-engine za per-clip FX processing pipeline.**

---

### 10.5 ReaSamplOmatic5000

**Šta radi u Reaper-u:**
Ugrađeni sampler koji živi u FX chain-u i reaguje na MIDI ulaz.

**Ključni detalji:**
- **Učitava** bilo koji audio fajl, mapira po klavijaturi
- **Note range:** Start/End polja definišu koji MIDI notovi triggeruju sample
- **Velocity slojevi:** ghost note (<40), regular (40-100), accent (>100)
- **Round-robin:** varijacije za izbegavanje "machine gun" efekta
- **ADSR envelope:** Attack, Decay, Sustain, Release
- **Filter:** lowpass, highpass, bandpass sa resonance
- **Pitch tracking:** hromatski playback — jedan sample, sve note
- **Multi-sample:** više RS5K instanci na jednom traku za realističan instrument
- **CPU:** gotovo nula overhead

**Kreativni workflow:**
1. Snimi udarac po metalu
2. Dynamic Split → automatski seče na udarce
3. "Send items to RS5K" → svaki udarac se mapira na notu
4. MIDI sekvenca → instant custom perkusivni instrument
5. Dodaj FX iza RS5K → per-note procesiranje

**Zašto je vredno za sound dizajnere:**
Pretvaranje snimljenih zvukova u svirajuće instrumente. Za game audio, kreiranje varijacija zvukova sa velocity i round robin kontrolom. Za film, kreiranje custom Foley instrumenata od snimljenog materijala.

**FluxForge status:** ⚠️ Imamo soundbank sistem. **Sampler sa MIDI triggering-om, velocity layers, round-robin, ADSR, filter treba proveriti.**

---

### 10.6 Time-Stretching Algoritmi

**Šta radi u Reaper-u:**
Najširi izbor algoritama za time-stretching od bilo kog DAW-a.

**Ključni detalji:**
- **Elastique Pro:** polifonični izvori (gitare, miksevi, orkestri) — najbolji kvalitet
- **Elastique Soloist:** monofonični (vokali, solo instrumenti) — fokus na pitch accuracy
- **Elastique Efficient:** manji CPU load za real-time rad
- **Rubber Band:** open source alternativa, dobar za dronove i padove
- **SoundTouch:** brz, CPU-lagan, za manje zahtevne primene
- **Simple Windowed (DIRAC-style):** za specijalne efekte — granularni artefakti pri velikom stretch-u
- **Opcije per-algoritam:**
  - Balanced / Tonal Optimised / Transient Optimised
  - Formant preservation (čuva vokalnu boju pri pitch shift-u)
  - Window size kontrola za granular algoritme

**Zašto je vredno za sound dizajnere:**
Različiti algoritmi daju različite artefakte — ponekad su artefakti POŽELJNI za sound design. Simple Windowed algoritam pri 10x stretch-u kreira granularne teksture. Elastique Pro čuva čistoću pri umerenom stretch-u. Sound dizajner bira algoritam po željenom rezultatu.

**FluxForge status:** ⚠️ Imamo audio warping. **Višestruki algoritmi sa per-item izborom treba proveriti. `rf-engine` koristi linearni SRC, Lanczos-3 implementiran ali nije uključen.**

---

### 10.7 Spectral Editing (Detalji)

**Šta radi u Reaper-u:**
Vizualizacija frekvencije na Y osi i vremena na X osi za hirurško editovanje.

**Ključni detalji:**
- **Režimi prikaza:**
  - Peaks (standardni waveform)
  - Spectral Peaks (hibridni — waveform sa frekvencijskim bojama)
  - Spectrogram (čist frekvencijski prikaz)
  - Kombinacije (peaks + spectral)
- **Spectral Edit Mode:**
  - Selekcija oblasti u frekventnom/vremenskom domenu
  - Primena gain, kompresije, gate-a na selektovanu oblast
  - 4 kontrole: fade in/out po frekvenciji i vremenu
  - Više spectral edit regiona po itemu
- **Podešavanja:**
  - FFT size (rezolucija)
  - Color map (boje za različite nivoe)
  - Transparency
  - Min/max frequency range
  - Per-track ili per-item podešavanje

**Limitacija:** Nije moćan kao iZotope RX za profesionalnu restauraciju, ali za brze popravke eliminiše potrebu za round-trip-om u eksterni editor.

**FluxForge status:** ✅ Imamo spectral editor/repair panel. **Nivo implementacije (spectral peaks hybrid view, per-item spectral editing, multi-region selection) treba proveriti.**

---

### 10.8 Feedback Loops u Rutiranju

**Šta radi u Reaper-u:**
Reaper dozvoljava kreiranje feedback petlji u rutiranju — signal iz traka A ide na B, iz B nazad na A.

**Ključni detalji:**
- Reaper ne blokira feedback rutiranje (većina DAW-ova ga zabranjuje)
- Moguće kreiranje self-oscillating delay-eva, drone generatora, feedback distortion-a
- Potreban je limiter ili gate da se spreči neograničen buildup
- 1 buffer latency u feedback loopu (deterministično ponašanje)

**Zašto je vredno za sound dizajnere:**
Kreiranje dronova, self-oscillation efekata, eksperimentalnog zvuka koji je nemoguć bez feedback petlji. Ovo je territory za napredni sound design.

**FluxForge status:** ⚠️ **Feedback rutiranje treba proveriti — većina DAW-ova ga blokira.**

---

## 11. UI/UX Filozofija

### 11.1 Screensets

**Šta radi u Reaper-u:**
Čuvanje kompletnog stanja UI layout-a — koji prozori su otvoreni, gde, koje veličine, zoom nivo.

**Ključni detalji:**
- **10 screenset slotova:** brojevi 1-0 na tastaturi
- **Čuva:** pozicije prozora, veličine, vidljivost, dock stanje, zoom, scroll poziciju
- **Instant prebacivanje:** jedan taster = kompletna promena layout-a
- **Per-project:** svaki projekat može imati sopstvene screenset-e
- **Primer setup-a:**
  - Screenset 1: "Edit" — veliki timeline, mala mixer
  - Screenset 2: "Mix" — pun mixer, mali timeline
  - Screenset 3: "Sound Design" — Media Explorer + timeline + FX chain
  - Screenset 4: "Record" — veliki metar + transport + timeline

**FluxForge status:** ⚠️ Imamo split view/lower zone. **Screenset sistem (save/recall kompletnog UI stanja) NIJE implementiran.**

---

### 11.2 Docker System

**Šta radi u Reaper-u:**
16 dock pozicija gde bilo koji prozor može biti "dockovan."

**Ključni detalji:**
- **16 pozicija:** 4 ivice (gore/dole/levo/desno) × 4 slota
- **Tabbed docking:** više prozora u istom dock-u sa tabovima
- **Floating ili docked:** svaki prozor može biti u oba stanja
- **Resize:** svaki dock se može resize-ovati
- **Auto-hide:** dock se sakriva kada nije u fokusu
- **Prozori koji se mogu dock-ovati:** FX browser, routing matrix, MIDI editor, Media Explorer, Track Manager, Region/Marker Manager, Video, Big Clock, Navigator, i svi SWS/skript prozori

**FluxForge status:** ⚠️ **Docker sistem sa tabeliranim panelima treba proveriti.**

---

### 11.3 Custom Toolbars

**Šta radi u Reaper-u:**
Do 16 custom floating toolbara pored glavnog.

**Ključni detalji:**
- **Main toolbar:** prilagodljiv redosled dugmadi
- **Floating toolbars:** 16 dodatnih, svaki sa custom akcijama
- **Toolbar dugmad:** bilo koja Reaper akcija, custom action, skripta
- **Toggle dugmad:** za on/off stanja (npr. metronome on/off)
- **Separatori i razmaci** za vizuelno grupisanje
- **Ikone:** custom ikone za svako dugme
- **Pozicija:** floating, docked na ivicu, docked u toolbar area

**FluxForge status:** ⚠️ **Customizable toolbars treba proveriti.**

---

### 11.4 WALTER Theme Engine

**Šta radi u Reaper-u:**
Kompletni sistem za definisanje vizuelnog layout-a svih UI elemenata.

**Ključni detalji:**
- **WALTER = Window Arrangement Logic Template Engine for REAPER**
- **Skripting:** theme autori pišu WALTER skripte za raspored i ponašanje UI elemenata
- **Elementi:** track paneli, mixer paneli, envelope paneli, transport, toolbar, tcp, mcp
- **Flow macro:** korisnici mogu prilagoditi redosled sakrivanja i veličine elemenata bez programiranja
- **Community teme:** stotine besplatnih tema na Stash (Reaper-ov community sajt)
- **Popularne teme:**
  - Default V6/V7
  - Reapertips (clean/modern)
  - iReaper (Logic-like)
  - Hydra (Cubase-like)

**FluxForge status:** N/A — Flutter UI ima sopstveni tema sistem. **Ali koncept duboke UI prilagodljivosti je relevantan.**

---

## 12. MIDI za Sound Design

### 12.1 MIDI Routing (128 Channels)

**Šta radi u Reaper-u:**
MIDI signal se može rutirati sa bilo kog traka na bilo koji drugi sa 128 kanala.

**Ključni detalji:**
- 128 MIDI buseva za interno rutiranje
- MIDI sends paralelno sa audio sends-a
- Per-channel filtering (propusti samo kanal 1, blokiraj ostale)
- MIDI → audio conversion (RS5K) na bilo kom traku
- ReaControlMIDI za 14-bit CC izlaz (viša rezolucija)

**FluxForge status:** ⚠️ Imamo MIDI sa piano roll i chord track. **128-channel MIDI routing treba proveriti.**

---

### 12.2 ReaLearn (Controller Mapping)

**Šta radi u Reaper-u:**
Napredni MIDI/OSC controller mapping sa feedback-om.

**Ključni detalji:**
- **Mapping:** bilo koji MIDI CC/note → bilo koji Reaper parametar
- **Feedback:** controller prima stanje iz Reapera (motorizovani faderi, LED rings)
- **Conditional mapping:** različita mapiranja zavisno od konteksta
- **Virtual control surfaces:** kreiranje custom control surface-a
- **OSC podrška:** Open Sound Control za mrežno upravljanje
- **Lua scripting:** programabilna mapiranja

**FluxForge status:** ⚠️ **Controller mapping sa feedback-om treba proveriti.**

---

## 13. Spectral Editing (Prošireno)

### 13.1 Spectral Peaks Display

**Šta radi u Reaper-u:**
Hibridni prikaz koji kombinuje klasične peaks sa frekvencijskim bojama.

**Ključni detalji:**
- Uveden u REAPER 5.32
- Waveform oblik + boja koja označava frekvencijski sadržaj
- Crvena/narandžasta = niske frekvencije
- Žuta/zelena = srednje frekvencije
- Plava/ljubičasta = visoke frekvencije
- Intenzitet boje = nivo tog frekvencijskog opsega
- "Curve" parametar kontroliše intenzitet prikaza boja

**Zašto je vredno za sound dizajnere:**
Na prvi pogled vidite frekvencijski sadržaj svakog zvuka na timelinu — bez otvaranja analizatora. Eksplozija (crvena/narandžasta), cymbal (plava), vokal (zelena) — instant vizuelna identifikacija.

**FluxForge status:** ⚠️ Imamo 11-level LOD waveform (superiorno Reaper-ovom 3-level). **Spectral peaks hybrid mode (frekvencijska boja na waveform-u) treba proveriti.**

---

## 14. Video Integracija

### 14.1 Video Playback & Sync

**Šta radi u Reaper-u:**
Direktna reprodukcija videa sinhronizovano sa audio timeline-om.

**Ključni detalji:**
- Video na timeline-u kao media item
- Sinhronizovani video prozor (floating ili docked)
- Podržani formati: MP4, AVI, MOV, MKV (via VLC/FFmpeg backend)
- Frame-accurate pozicioniranje
- Video thumbnails na timeline-u
- Trimming, cutting, splicing videa

**FluxForge status:** ✅ Imamo video track podršku. **Nivo implementacije treba proveriti.**

---

### 14.2 Video Processor FX

**Šta radi u Reaper-u:**
Built-in video processor koji koristi EEL skripte za vizuelne efekte.

**Ključni detalji:**
- Text overlay i animacije
- Audio-reaktivni vizuali (audiogrami za podkaste)
- FFT-bazirani frequency analysis prikaz
- Scrolling spektrogrami
- Hue/brightness prilagodbe
- Community video presets na ReaPack

**Zašto je vredno za sound dizajnere:**
Kreiranje video preview-a sa spektralnom vizualizacijom za klijente — bez eksternog video editing software-a.

**FluxForge status:** ❌ **Nemamo video processor FX. Imamo `rf-video` crate ali nivo implementacije je nepoznat.**

---

### 14.3 Timecode Sync

**Šta radi u Reaper-u:**
Sinhronizacija sa eksternim uređajima putem timecode protokola.

**Ključni detalji:**
- **MTC (MIDI Time Code):** primanje i slanje
- **LTC (Linear Time Code):** audio-bazirani timecode
- **SPP (Song Position Pointer):** MIDI beat clock
- **ASIO positioning protocol:** za low-latency sync
- **SMPTE generator:** ugrađen (Insert menu)
- **MMC (MIDI Machine Control):** transport kontrola eksternih uređaja

**FluxForge status:** ⚠️ **Timecode sync treba proveriti.**

---

## 15. Mrežna Saradnja

### 15.1 ReaStream

**Šta radi u Reaper-u:**
Plugin za streaming audio i MIDI između računara na LAN mreži.

**Ključni detalji:**
- Host-to-host streaming audio i/ili MIDI
- UDP broadcast za one-to-many streaming
- Radi kao VST — može se koristiti i van Reapera (ReaPlugs paket)
- Imenovanje kanala za identifikaciju
- Multi-channel podrška

**FluxForge status:** ❌ **Nemamo network audio streaming.**

---

### 15.2 NINJAM

**Šta radi u Reaper-u:**
Open-source platforma za remote jamming.

**Ključni detalji:**
- Rešava latency problem time-shift-om za jednu meru
- Čuva nekompresovani materijal za kasniji remix
- ReaNINJAM plugin ugrađen u Reaper
- Reaper nativno importuje NINJAM sesije

**FluxForge status:** ❌ **Nemamo remote collaboration. Nisko prioritetno za sound design workflow.**

---

## 16. Performanse & Efikasnost

### 16.1 Footprint & Startup

**Reaper:**
- Instalacija: ~100 MB (vs Pro Tools 4+ GB, Logic 72+ GB)
- Portable instalacija — ceo DAW na USB sticku
- Brz startup (sekunde, ne minuti)

**FluxForge status:** ✅ Flutter + Rust je lak. **Startup vreme treba optimizovati.**

---

### 16.2 CPU Optimizacija

**Reaper:**
- Anticipative FX Processing (multi-thread FX obrada)
- Media buffer size podešavanje
- Per-track FX tail length kontrola
- Efikasno disk streamovanje

**FluxForge status:** ✅ Imamo SIMD optimizaciju (avx512f/avx2/sse4.2/scalar), lock-free audio thread, pre-alocirani buferi.

---

## 17. Extensibility & Scripting

### 17.1 ReaPack (Package Manager)

**Šta radi u Reaper-u:**
Decentralizovani package manager za skripte, efekte, ekstenzije i teme.

**Ključni detalji:**
- 1,300+ paketa
- Kategorije: Scripts, Effects, Extensions, Themes, Language Packs, Templates
- Automatski update-i
- Custom repositories
- One-click install/uninstall

**FluxForge status:** ❌ **Nemamo plugin/extension marketplace. Dugoročno relevantan za ekosistem.**

---

### 17.2 Extensions SDK

**Šta radi u Reaper-u:**
Otvoreni SDK za C/C++ ekstenzije.

**Ključni detalji:**
- Pristup audio file read/write
- Audio hardware pristup
- Samplerate conversion API
- Pitch shifting / time stretch API
- UI integracija

**FluxForge status:** ⚠️ Imamo `rf-plugin` crate. **Otvoreni SDK za third-party development treba razmotriti dugoročno.**

---

## 18. File Management

### 18.1 Project Consolidation

**Šta radi u Reaper-u:**
Automatsko kopiranje svih korišćenih medija u folder projekta.

**Ključni detalji:**
- "Copy all media into project directory" pri Save As
- Automatski "Media" podfolder
- Provera nedostajućih fajlova (Project Bay — Cmd+B)
- Re-linking izgubljenih fajlova
- Uklanjanje nekorišćenih medija iz projekta

**FluxForge status:** ⚠️ **Project consolidation treba proveriti.**

---

### 18.2 Auto-Save & Backup

**Šta radi u Reaper-u:**
Konfigurabilan auto-save sa verzioniranim backup-ima.

**Ključni detalji:**
- Auto-save interval: konfigurabilni (svaki X minuta)
- Opcija "when not recording" — ne prekida snimanje
- Timestamped backup-i u backups folderu
- "Keep multiple versions" — više selektabilnih verzija
- Recall starijih verzija iz jednog fajla

**FluxForge status:** ✅ Imamo session persistence i auto-save. **Verzioniranje backup-a treba proveriti.**

---

## 19. Game Audio Integracija

### 19.1 ReaWwise (Official Audiokinetic Extension)

**Šta radi u Reaper-u:**
Direktan transfer audio asseta iz Reapera u Wwise.

**Ključni detalji:**
- Kreiranje object hierarchy-ja u Wwise-u bez napuštanja Reapera
- Kontrola naming konvencija za WAV i Wwise objekte
- Wildcard recipe za Object Path: `\Actor-Mixer Hierarchy\Default Work Unit\<Random Container>$project\<Sound SFX>SFX_$project_$regionnumber`
- Originals subfolder podrška

**FluxForge status:** ⚠️ Imamo SlotLab export (7 formata planirano: .ffpkg, Wwise, FMOD, Unity, raw stems, JSON manifest, compliance report). **Direktna Wwise API integracija treba proveriti.**

---

### 19.2 FMOD Integracija

**Šta radi u Reaper-u:**
Reaper kao external editor za FMOD projekte.

**Ključni detalji:**
- FMOD oficijelna dokumentacija za Reaper integraciju
- Reaper kao external audio editor
- Workflow: renderuj iz Reapera → FMOD automatski importuje iz rendered direktorijuma
- Shared folder monitoring

**FluxForge status:** ⚠️ FMOD export planiran u SlotLab. **Direktna integracija treba implementirati.**

---

### 19.3 UCS Naming (Universal Category System)

**Šta radi u Reaper-u:**
Standardizovane naming konvencije za game audio sa wildcard podrškom.

**Ključni detalji:**
- UCS Toolkit za Reaper
- Format: `CATsub_VENdor_ProjectName_DescriptorA-DescriptorB_####`
- Primer: `EXPLbomb_ACME_ProjectX_Close-Debris_0001.wav`
- Automatsko generisanje iz Reaper regiona/trakova
- Industrijski standard za game audio biblioteke

**FluxForge status:** ❌ **Nemamo UCS naming podršku. Relevatno za game audio pipeline.**

---

### 19.4 Batch Export za Game Assets

**Šta radi u Reaper-u:**
Renderovanje jednog ili hiljada fajlova odjednom sa punom kontrolom.

**Ključni detalji:**
- Kontrola: channel count, sample rate, bit depth, bit rate, encoding quality
- Wildcard naming: `$item`, `$region`, `$marker`, `$track`
- LKC Render Blocks za automatizovani asset export
- Multi-format rendering (WAV + OGG istovremeno)

**FluxForge status:** ⚠️ Imamo audio export. **Batch export sa wildcard-ima i multi-format rendering NIJE implementiran.**

---

## 20. Kreativni Sound Design Trikovi

### 20.1 ReaGranular

**Šta radi u Reaper-u:**
Ugrađeni granular synthesis plugin.

**Ključni detalji:**
- 4 nezavisna grain-a
- Kontrola min/max veličine grain-a
- Individualni panning i level po grain-u
- Random varijacije za organski zvuk
- Freeze mode (zaustavi poziciju, nastavi granulaciju)
- Može čitati ulazni audio u realnom vremenu ili iz buffera

**FluxForge status:** ❌ **Nemamo granular synthesis. Postoji kao koncept u `rf-dsp` ali nije expozovan kao plugin.**

---

### 20.2 Feedback Loops za Drone Generiranje

**Detalji:**
1. Trak A: reverb sa dugačkim tail-om
2. Send iz A u B (delay sa feedback-om)
3. Send iz B nazad u A
4. Limiter na oba traka
5. Kratki impuls → self-sustaining drone koji evolvira

**FluxForge status:** ⚠️ **Treba proveriti da li routing dozvoljava feedback loops.**

---

### 20.3 RS5K Drum Kit od Snimljenog Materijala

**Workflow:**
1. Snimi 30 sekundi udaraca po razlicitim površinama
2. Dynamic Split → automatski seče na udarce (30+ slice-ova)
3. Selektuj sve iteme → "Build multichannel instrument from items"
4. Svaki udarac na drugoj noti → instant drum kit
5. MIDI programiranje → custom perkusija
6. Per-note FX (jer je RS5K u FX chain-u)

**FluxForge status:** ❌ **Automatski "snimak → instrument" workflow NIJE implementiran.**

---

### 20.4 Subprojects za Iterativni Sound Design

**Workflow:**
1. Kreiraš sub-projekat `Wind_Layer.rpp` — 10 trakova sa wind zvukovima, procesiranje, mix
2. U master projektu: `Wind_Layer.rpp` je jedan item
3. Dupli klik → otvori sub-projekat, edituj, save
4. Master projekat automatski koristi renderovani rezultat
5. Rate/pitch automatizacija na sub-projektu itemu za kreativno warping-ovanje

**FluxForge status:** ❌ **Sub-project workflow NIJE implementiran.**

---

## 21. FluxForge vs Reaper — Gap Analiza

### Šta FluxForge VEĆ IMA a Reaper NEMA

| Feature | FluxForge | Reaper |
|---------|-----------|--------|
| 11-level LOD waveform | ✅ | ❌ (3-level) |
| AUREXIS psychoacoustic engine | ✅ | ❌ (ne postoji) |
| SlotLab middleware pipeline | ✅ | ❌ (ne postoji) |
| FabFilter-tier Ultimate procesori (6) | ✅ | ❌ (basic stock) |
| Spectral editor/repair | ✅ | ⚠️ (bazičan) |
| Spatial audio bus policy | ✅ | ❌ |
| Diagnostics & live monitoring | ✅ | ❌ |
| SIMD DSP (avx512/avx2/sse4.2) | ✅ | ⚠️ (delimično) |

### KRITIČNI GAP-ovi (Moramo implementirati)

| # | Feature | Status | Prioritet |
|---|---------|--------|-----------|
| 1 | Item-Level FX | ❌ | **P0 — CRITICAL** |
| 2 | Region Render Matrix | ❌ | **P0 — CRITICAL** |
| 3 | Wildcard Tokens za render | ❌ | **P0 — CRITICAL** |
| 4 | Per-item Pitch Envelope | ❌ | **P1 — HIGH** |
| 5 | Per-item Playrate Envelope | ❌ | **P1 — HIGH** |
| 6 | Automation Items (pooled) | ❌ | **P1 — HIGH** |
| 7 | Pin Connector | ❌ | **P1 — HIGH** |
| 8 | Parallel FX (inline) | ❌ | **P1 — HIGH** |
| 9 | FX Containers | ❌ | **P1 — HIGH** |
| 10 | Per-item Automation | ❌ | **P1 — HIGH** |

### ZNAČAJNI GAP-ovi (Treba implementirati)

| # | Feature | Status | Prioritet |
|---|---------|--------|-----------|
| 11 | Razor Edits | ❌ | **P2 — MEDIUM** |
| 12 | Mix Snapshots | ❌ | **P2 — MEDIUM** |
| 13 | Metadata Browser + Search | ❌ | **P2 — MEDIUM** |
| 14 | Screensets | ❌ | **P2 — MEDIUM** |
| 15 | Project Tabs | ❌ | **P2 — MEDIUM** |
| 16 | Sub-Projects | ❌ | **P2 — MEDIUM** |
| 17 | Command Palette/Console | ❌ | **P2 — MEDIUM** |
| 18 | Auto-Color Rules | ❌ | **P2 — MEDIUM** |
| 19 | Dynamic Split Workflow | ❌ | **P2 — MEDIUM** |
| 20 | UCS Naming System | ❌ | **P2 — MEDIUM** |

### NICE-TO-HAVE (Razmotriti)

| # | Feature | Status | Prioritet |
|---|---------|--------|-----------|
| 21 | Cycle Actions | ❌ | P3 |
| 22 | Region Playlist | ❌ | P3 |
| 23 | Marker Actions | ❌ | P3 |
| 24 | Granular Synthesis | ❌ | P3 |
| 25 | ReaStream (network audio) | ❌ | P3 |
| 26 | JSFX-style scripting | ❌ | P3 |
| 27 | Video Processor FX | ❌ | P3 |
| 28 | Host-level wet/dry per-FX | ⚠️ | P3 |
| 29 | Package Manager | ❌ | P4 |
| 30 | Extension SDK | ⚠️ | P4 |

---

## 22. Prioriteti Implementacije

### Faza 1: Sound Design Foundation (P0)

**Cilj:** Učiniti FluxForge konkurentnim sa Reaper-om za sound design workflow.

1. **Item-Level FX** — Arhitekturna promena u rf-engine za per-clip FX processing pipeline. UI za FX chain na clip nivou.
2. **Region Render Matrix** — UI panel za kreiranje regiona, matrix za trak/region mapping, batch render engine.
3. **Wildcard Token System** — Engine za parsiranje i zamenu tokena u render naming-u.

### Faza 2: Creative Tools (P1)

**Cilj:** Kreativni alati koji Reaper nema ili ima u bazičnom obliku.

4. **Per-item Pitch Envelope** — UI za crtanje pitch krivulje na clipu. Rust engine za real-time pitch processing per-item.
5. **Per-item Playrate Envelope** — Slično pitch envelope, ali za brzinu reprodukcije. Tape-style mode (pitch follows rate).
6. **Automation Items** — Kontejnerizovana automatizacija sa looping, pooling, stacking.
7. **Parallel FX + FX Containers** — Inline parallel mode i nestable kontejneri sa macro mappingom.
8. **Pin Connector** — 64-channel internal routing sa per-plugin channel control.

### Faza 3: Workflow Acceleration (P2)

**Cilj:** Profesionalni workflow alati za produktivnost.

9. **Razor Edits** — Marquee selekcija sa nezavisnom media/envelope selekcijom.
10. **Mix Snapshots** — Save/recall stanja miksa sa selektivnim kategorijama.
11. **Media Browser Upgrade** — Metadata čitanje/editovanje, BWF/iXML, Boolean pretraga.
12. **Screensets** — Save/recall kompletnog UI layout stanja.
13. **Project Tabs** — Multi-project sa drag-and-drop između tabova.
14. **Command Palette** — Quick-access komandna linija za sve akcije.
15. **Auto-Color Rules** — Regex-based automatsko bojenje trakova.
16. **Dynamic Split** — Transient detection + automatic split/stretch marker workflow.

### Faza 4: Game Audio Pipeline (P2-P3)

**Cilj:** Kompletan pipeline za game audio production.

17. **UCS Naming** — Universal Category System podrška u render i media browser.
18. **Sub-Projects** — Ugneždeni projekti sa automatskim renderovanjem.
19. **Wwise/FMOD Direct Integration** — API-based transfer asseta.

### Faza 5: Power User Features (P3-P4)

**Cilj:** Features za napredne korisnike i ekosistem.

20. **Cycle Actions** — Proširenje FluxMacro sistema sa cikličnim akcijama.
21. **Region Playlist** — Non-linearni playback.
22. **Granular Synthesis** — ReaGranular-style plugin.
23. **DSP Scripting** — JSFX-style user-scriptable audio effects.
24. **Package Manager** — Marketplace za skripte, efekte, teme.

---

## Izvori

### Routing & Signal Flow
- [The REAPER Routing Matrix Explained — Tim Inglis Audio](https://timinglis.com.au/the-reaper-routing-matrix-explained/)
- [Audio Routing Explained — The REAPER Blog](https://reaper.blog/2016/06/audio-routing-explained/)
- [Reaper: Using Tracks' Internal Channels — Sound On Sound](https://www.soundonsound.com/techniques/reaper-using-tracks-internal-channels)
- [How to Use Reaper's Routing Matrix Like a Pro — Breve Music Studios](https://brevemusicstudios.com/how-to-use-reapers-routing-matrix-like-a-pro/)

### Item/Media Handling
- [Reaper Item-Based Editing Guide — Audeobox](https://www.audeobox.com/learn/reaper/item-based-editing-guide/)
- [5 Advanced Ways to Edit in REAPER — ReaperTips](https://www.reapertips.com/post/5-advanced-ways-to-edit-in-reaper)
- [REAPER: An Exhaustive Review — ExtremRaym](https://www.extremraym.com/en/reaper-5-review/)

### Rendering & Export
- [Easily Create Stems with Stem Manager — ReaperTips](https://www.reapertips.com/post/easily-create-stems-with-stem-manager)
- [REAPER 101: File Names — The REAPER Blog](https://reaper.blog/2012/01/reaper-101-file-names/)

### FX & Processing
- [What's new in REAPER 7 — ReaperTips](https://www.reapertips.com/post/reaper-7)
- [Amplitude Split with REAPER 7 FX Containers — Jorchime](https://www.jorchime.com/blog/2023/november/amplitude-split-with-reaper-7-fx-containers/)
- [Things I Really Like About Reaper — AdmiralBumbleBee](https://www.admiralbumblebee.com/studio/2017/03/30/Things-that-I-really-like-about-Reaper_reader.html)

### Automation
- [A Guide to Automation Items in REAPER — ReaperTips](https://www.reapertips.com/post/a-guide-to-automation-items-in-reaper)
- [How to Use Reaper Automation and Envelopes — Envato Tuts+](https://music.tutsplus.com/how-to-use-reaper-automation-and-envelopes--cms-107723t)

### Custom Actions & Scripting
- [Automate Anything With Reaper's Custom Actions — Sound On Sound](https://www.soundonsound.com/techniques/automate-anything-reapers-custom-actions)
- [Reaper Custom Actions: Complete Guide — Audeobox](https://www.audeobox.com/learn/reaper/custom-actions-guide/)
- [REAPER ReaScript — Cockos](https://www.reaper.fm/sdk/reascript/reascript.php)

### SWS Extensions
- [SWS Snapshots — SWS Extension](https://sws-extension.org/snapshots.php)
- [Snapshots SWS Extensions Mixing — Sound On Sound](https://www.soundonsound.com/techniques/snapshots-sws-extensions-mixing)
- [SWS / S&M Extension](https://sws-extension.org/)
- [Top 5 SWS Extension Features — The REAPER Blog](https://reaper.blog/2020/08/5-sws-features/)

### Sound Design
- [Make the Most of REAPER as a Sound Design Tool — A Sound Effect](https://www.asoundeffect.com/reaper-sound-design-workflow/)
- [Tape Effects In Reaper — Sound On Sound](https://www.soundonsound.com/techniques/tape-effects-reaper)
- [Extreme Time Stretching — 7 REAPER Algorithms — The REAPER Blog](https://reaper.blog/2017/10/extreme-time-stretching/)
- [5 Reaper Features to Improve Your Sound Design Workflow — David Dumais Audio](https://www.daviddumaisaudio.com/reaper-features-to-improve-your-sound-design-workflow/)
- [Reaper vs Pro Tools for Sound Design — Stephen Schappler](https://www.stephenschappler.com/2024/07/12/reaper-vs-pro-tools-for-sound-design/)
- [My Reaper Environment for Sound Design — Stephen Schappler](https://www.stephenschappler.com/2024/09/12/my-reaper-environment-for-sound-design/)

### UI/UX
- [Custom Menus & Toolbars In Reaper — Sound On Sound](https://www.soundonsound.com/techniques/custom-menus-toolbars-reaper)
- [Toolbars and Docks in REAPER — The REAPER Blog](https://reaper.blog/2015/08/toolbars-and-docks-in-reaper/)
- [Customizing the Reaper Interface — Audeobox](https://www.audeobox.com/learn/reaper/customizing-reaper-interface/)
- [WALTER Theme Development — Cockos](https://www.reaper.fm/sdk/walter/walter.php)

### Media Explorer
- [Metadata and Reaper Media Explorer — Untidy Music](https://untidymusic.com/reaper-tutorials/metadata-and-reaper-media-explorer)
- [What's New In REAPER v6.16 — Media Explorer — The REAPER Blog](https://reaper.blog/2020/11/616_update/)

### Game Audio
- [ReaWwise — Audiokinetic Blog](https://blog.audiokinetic.com/reawwise-connecting-reaper-and-wwise/)
- [WAAPI Transfer — GitHub](https://github.com/karltechno/Reaper-Waapi-Transfer)
- [FMOD Reaper Integration — FMOD Docs](https://www.fmod.com/docs/2.02/studio/appendix-b-reaper-integration.html)
- [REAPER Tools for Game Audio — Christopher Bolte](https://bolttracks.com/reaper-tools/)
- [REAPER for Game Audio — A Sound Effect](https://www.asoundeffect.com/reaper-for-game-audio-getting-started-rendering/)
- [Reaper for Game Audio: Subprojects — A Sound Effect](https://www.asoundeffect.com/reaper-for-game-audio-project-scopes-subprojects/)

### Spectral Editing
- [Spectral Editing In Reaper — Sound On Sound](https://www.soundonsound.com/techniques/spectral-editing-reaper)
- [5 Ways to Display Audio in REAPER — ReaperTips](https://www.reapertips.com/post/5-ways-to-display-audio-in-reaper)
- [Spectral Peaks — REAPER 5.32 — The REAPER Blog](https://reaper.blog/2017/01/whats-new-in-reaper-5-32/)

### Samplers & MIDI
- [ReaSamplOmatic5000 Guide — Audeobox](https://www.audeobox.com/learn/reaper/reasamplomatic5000-guide/)
- [ReaSamplOmatic 5000 Basic Tutorial — The REAPER Blog](https://reaper.blog/2016/03/reasamplomatic-5000-basic-tutorial/)
- [ReaLearn — Helgoboss](https://www.helgoboss.org/projects/realearn)

### Network & Collaboration
- [NINJAM — Cockos](https://www.cockos.com/ninjam/)
- [ReaStream — KVR Audio](https://www.kvraudio.com/product/reastream_by_cockos)
- [ReaRoute and ReaStream Tutorial — The REAPER Blog](https://reaper.blog/2022/01/rearoute-reastream-tutorial/)

### File Management
- [The Proper Way to Save Projects in REAPER 7 — ReaperTips](https://www.reapertips.com/post/the-proper-way-to-save-projects-in-reaper-7)
- [REAPER 101 File Management — The REAPER Blog](https://reaper.blog/2013/07/reaper-101-file-management/)

### Extensions & Packages
- [ReaPack](https://reapack.com/)
- [SWS Extension — Auto Color](https://sws-extension.org/color.php)
- [SWS Marker Actions](https://sws-extension.org/markeractions.php)
