# FLUXFORGE SLOT LAB – UI MOCKUP SPEC

### "Claude brief" – kompletan opis izgleda (bez koda)

Tvoj zadatak je da napraviš **vizuelni mockup interfejsa** za profesionalni slot-audio middleware pod imenom **FluxForge Slot Lab**.
Dizajn mora izgledati kao hibrid **Wwise + FMOD + slot mašina**, ali 100% fokusiran na slot igre.

Stil:

* Dark, premium, "casino-grade" estetika
* Metalni paneli, brušeni čelik, stakleni slojevi
* Zlatni akcenti, amber glow, subtilni neon
* Vizuelni jezik: "high-end gaming console" + "pro audio workstation"
* Sve mora delovati kao ozbiljan profesionalni alat, ne kao igra za krajnjeg igrača

---

## GLOBALNI LAYOUT

Ceo ekran je podeljen u četiri glavne zone:

1. Gornja traka – "Slot Machine Header"
2. Leva kolona – Game Spec & Paytable
3. Centralni panel – Waveform + Stage View
4. Desna kolona – Event Trigger Matrix + Mixer
5. Donja traka – Stage Timeline + Status HUD

---

## 1) GORNJA ZONA – SLOT HEADER

Na vrhu je širok panel koji izgleda kao **reel window pravog slota**:

* Pet ili šest reel prozora sa klasičnim simbolima (7, BAR, Bell, Cherry, BONUS, WILD)
* Iznad njih stoji naslov:
  **FLUXFORGE SLOT LAB v1.0**
* Iza headera lete zlatni novčići u slow-motion
* Levo i desno su metalni nosači, kao kod pravog kabineta

Ovo je "emocionalni anchor" – odmah je jasno da je alat vezan za slot igre.

---

## 2) LEVA KOLONA – GAME SPEC / PAYTABLE

Panel izgleda kao tehnički slot servis panel:

### Paytable blok:

Tabela sa kolonama:

* Symbol
* Payout
* SFX
* Music
* Duck

Svaki red ima:

* Ikonicu simbola
* Numeričku vrednost isplate
* Male okrugle indikatore (kao LED lampice)

Ispod toga:

### Feature Rules blok:

* "3+ Scatters trigger 10–20 FS"
* "Big Win Tier 1: 50x"
* "Big Win Tier 2: 200x"
* "Big Win Tier 3: 900x"

Sve izgleda kao konfiguracioni panel industrijskog uređaja.

---

## 3) CENTRALNI PANEL – WAVEFORM VIEW

Ovo je srce sistema.

Umesto "kockica" ili heatmapa:

* Veliki waveform editor
* Višeslojni audio prikaz:

  * Rollup Loop
  * Big Win Stinger
  * Crowd Cheers
  * Low Brass Hits

Svaki sloj ima:

* Različitu boju (ljubičasta, narandžasta, crvena, žuta)
* Label sa imenom zvuka
* Vidljive tranzijente i dinamiku

Ispod waveform-a:

* Mali spektralni prikaz
* Timeline sa markerima

Ovo mora izgledati kao pravi audio alat – Cubase / Pro Tools nivo ozbiljnosti.

---

## 4) DESNA KOLONA – SLOT LOGIKA

### Volatility Panel (gore desno)

Veliki okrugli analogni "Volatility" dial:

* Skala: Casual → Medium → High → Insane
* Boje: zelena → žuta → narandžasta → crvena
* Trenutna vrednost osvetljena
* Izgleda kao high-end hi-fi potenciometar

Ispod:

### Heatmap / Scenario Panel

* Dugmad:

  * Force Win
  * Force Big Win
  * Force Free Spins
  * Near Miss
  * Batch Play

Sve kao industrijski kontrolni blok.

### Event Trigger Matrix

Tabela gde su redovi:

* SPIN START
* REEL STOP 1
* REEL STOP 2
* WIN PRESENT
* ROLLUP START
* BIG WIN TIER
* FEATURE ENTER

Kolone:

* SFX
* MUSIC
* DUCK

U ćelijama su male svetle tačke / LED indikatori.

Ovo mora izgledati kao "slot audio control board".

---

## 5) DONJA ZONA – STAGE TIMELINE

Široka traka koja izgleda kao DAW timeline:

Segmenti:

* SPIN START
* REEL STOP
* ANTIC
* WIN PRESENT
* ROLLUP START
* BIG WIN
* FEATURE ENTER
* SPIN END

Svaki segment ima:

* Boju
* Naziv
* Mali marker iznad

Ispod:

* HUD traka sa podacima:

  * TOTAL WIN
  * FREE SPINS
  * BALANCE
  * BET

U centru:

* Transport dugmad:

  * Play
  * Loop
  * Step

---

## OPŠTI UTISAK

Interfejs mora delovati kao:

> "Da je Wwise napravljen isključivo za slot igre."

Treba da se oseti:

* Profesionalnost
* Težina industrijskog alata
* Slot DNK u svakom detalju
* Audio je centralna tema, ne sporedna

Ovo nije "igra".
Ovo je **slot audio command center**.

Cilj mockupa je da, na prvi pogled, kaže:

> "Ovo je prvi middleware na svetu koji razume slot igre iznutra."
