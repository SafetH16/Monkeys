# MechaKeys ⌨️🍌

![MechaKeys Cover](cover.png)

**MechaKeys** è un'app macOS menu bar che trasforma la tua tastiera in una tastiera meccanica virtuale. Ogni pressione di tasto produce un suono realistico di switch meccanico, con il suono che si **prolunga finché il tasto è premuto** e un click di rilascio quando lo si lascia.

## 📁 Struttura Progetto

```
.
├── MechaKeys.xcodeproj/      ← Progetto Xcode (se vuoi aprirlo in Xcode)
├── MechaKeys/
│   ├── main.swift           ← Entry point (nasconde l'icona dal dock)
│   ├── AppDelegate.swift    ← UI nella barra dei menu e gestione stato
│   ├── KeyboardMonitor.swift← Tap globale sugli eventi di input
│   ├── SoundEngine.swift    ← Motore audio polifonico (AVAudioEngine)
│   ├── SoundSynthesizer.swift← Sintesi programmabile delle onde audio
│   ├── KeySoundProfile.swift← Parametri per i profili Cherry MX (Blue, Brown, Red)
│   ├── Info.plist           ← Configurazione (LSUIElement=true)
│   └── MechaKeys.entitlements← Permessi dell'app
├── build.sh                 ← Script di compilazione autonomo
├── cover.png                ← Immagine di copertina (Nano Banana)
└── build/
    └── MechaKeys.app        ← Il pacchetto dell'applicazione compilata
```

## 🏗️ Architettura

| Componente | Descrizione |
|---|---|
| **KeyboardMonitor** | Utilizza `CGEvent.tapCreate` per intercettare gli eventi `keyDown`, `keyUp` e modificatori. Evita la ripetizione automatica e lavora in sicurezza sui thread tramite `NSLock`. |
| **SoundEngine** | Gestisce un pool circolare di **16 `AVAudioPlayerNode`** per supportare la polifonia e la pressione simultanea di più tasti. |
| **SoundSynthesizer** | Sintetizza dinamicamente in memoria a 44.1kHz mono i suoni: il click iniziale (sine + rumore), il loop durante la pressione (rumore filtrato) e il rilascio. |
| **KeySoundProfile** | Profili predefiniti: **Cherry MX Blue** (clicky), **Brown** (tattile), e **Red** (lineare). |

## 🔨 Come Compilare

Se apporti modifiche al codice sorgente, puoi ricompilare l'app al volo senza Xcode:
```bash
./build.sh
```

## 🚀 Come Avviare

Apri l'applicazione installata:
```bash
open /Applications/MechaKeys.app
```

## ⚠️ Permessi Necessari

Al primo avvio, l'app richiederà il permesso **Input Monitoring** (Accessibilità) per poter rilevare la pressione dei tasti mentre è in background:

1. macOS aprirà automaticamente la schermata delle **Impostazioni di Sistema**.
2. Vai in **Privacy e Sicurezza** → **Accessibilità**.
3. Abilita l'interruttore per **MechaKeys**.
4. Riavvia l'app per rendere attive le modifiche.

## 🎹 Scorciatoia Globale

Puoi attivare o disattivare rapidamente i suoni della tastiera in qualsiasi momento premendo la combinazione globale:
* **Control + Shift + K**

Questa combinazione viene intercettata dall'app ed evita la digitazione della lettera nel campo di testo attivo, funzionando da comodo interruttore "Mute".

## ⌫/↩️/⎵ Ritmo di Ripetizione Prolungata (Cancella, Invio e Spazio)

Per dare un riferimento ritmico ottimale durante la cancellazione veloce di testi, l'inserimento continuo di a capo o la pressione prolungata dello spazio:
* Quando i tasti **Backspace / Delete**, **Invio / Return** o la **Barra Spaziatrice** vengono **tenuti premuti a lungo**, macOS avvia l'auto-repeat rapido. In questa modalità, l'app conta gli eventi e riproduce un **click normale standard ogni 3 ripetizioni**.
* Le singole pressioni manuali (tocco singolo) dei tasti Cancella, Invio o Spazio riproducono invece il normale click singolo per ciascun tocco.
* Digitare qualsiasi altro tasto normale azzera il contatore.
