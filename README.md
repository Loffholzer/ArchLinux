# 🛠 Arch Linux Installer (Modular, DRY-RUN Safe)

## ⚠️ Disclaimer

This is a personal hobby project and not an official Arch Linux installer.

While care has been taken during development, the use of this installer is at your own risk.
It performs potentially destructive operations such as disk partitioning.

The author assumes no liability for data loss or system damage.
<br>
<br>
 ## Ein modularer Arch Linux Installer mit Fokus auf:

- 🔒 Sicherheit (DRY-RUN Modus)
- 🧩 klare Struktur (Module 00–14)
- ⚡ schnelle Iteration (AUTO_MODE)
- 🧠 Wartbarkeit

---

## 🚀 Features

- Vollständig modularer Installer
- DRY-RUN Modus (keine Änderungen am System)
- AUTO_MODE für schnelles Testen
- BTRFS + Snapper Integration
- Optional: LUKS Verschlüsselung
- Limine Bootloader (geplant)
- Pacman Optimierung (Parallel, Color, Candy 😄)
- Fish + Starship Shell
- AUR Support (paru)

---

## 📂 Projektstruktur

    modules/
      00_config.sh
      01_disk.sh
      02_encryption.sh
      03_btrfs.sh
      04_base.sh
      05_system.sh
      06_perf.sh
      07_snapshots.sh
      08_bootloader.sh        # neu
      09_user.sh              # verschoben
      10_snapshot_boot.sh     # neu (Snapshots → Bootmenü)
      11_shell.sh
      12_tools.sh
      13_aur.sh
      14_editor.sh

    install.sh

---

## ⚙️ Nutzung

### 🔹 Standard (sicherer Testlauf)

    ./install.sh

→ läuft mit:
- DRY_RUN=true
- AUTO_MODE=true

---

### 🔹 Echter Installationslauf

    AUTO_MODE=false DRY_RUN=false ./install.sh

⚠️ **ACHTUNG:**
Alle Daten auf dem Ziel-Laufwerk werden gelöscht.

---

## 🧠 Architektur

### Ablauf

    00 → Config
    01 → Disk
    02 → Encryption
    03 → BTRFS
    04 → Base System
    05 → System Config
    06 → Performance
    07 → Snapshots
    08 → Bootloader (Limine)
    09 → User
    10 → Snapshot Boot Integration (optional)
    11 → Shell
    12 → Tools
    13 → AUR
    14 → Editor

---

## 📦 Paketstrategie

### Core (immer installiert)

    base
    linux
    linux-firmware
    sudo

→ installiert in `04_base.sh`

---

### Modul-spezifisch

    07 → snapper
    08 → limine
    11 → fish, starship
    12 → cli tools
    13 → base-devel, git, paru

👉 Jedes Modul installiert seine eigenen Pakete

---

## 🔥 Wichtige Designentscheidungen

### DRY-RUN

Jedes Modul prüft:

    if [[ "${DRY_RUN:-true}" == true ]]

→ Keine echten Änderungen im Testmodus

---

### AUTO_MODE

- Überspringt alle Eingaben
- Nutzt Default-Konfiguration
- Perfekt für Entwicklung

---

### ROOT_DEVICE Pipeline

    01 → setzt ROOT_PART
    02 → setzt ROOT_DEVICE
    03 → nutzt ROOT_DEVICE

---

### Modul-Prinzip

    Ein Modul = eine Aufgabe

→ verhindert große, unübersichtliche Dateien wie 00_config

---

### Bootloader & Snapshots

- Limine wird minimal in `08_bootloader.sh` eingerichtet
- Snapshot-Bootmenü erfolgt später in `10_snapshot_boot.sh`

👉 Trennung bewusst gewählt für Stabilität

---

## ⚠️ Bekannte Fixes / Lessons Learned

### 🔁 Doppelte Partition-Ausgabe

- Ursache: `ermittle_partitionen` mehrfach aufgerufen
- Fix: nur einmal aufrufen

---

### ❌ Unbound Variables

- Problem: fehlende Default-Werte
- Fix: alle Variablen in `set_default_config()` setzen + exportieren

---

### ⚠️ run_module Fehler

- Problem: fehlender Funktionsparameter
- Fix:

    run_module "01_disk.sh" "run_disk_setup"

---

### ⚠️ pacman Struktur

| Feature           | Modul |
|------------------|------|
| ParallelDownloads| 06   |
| Color            | 06   |
| ILoveCandy 😄    | 06   |
| Multilib         | 05   |

---

### ⚠️ Snapper & BTRFS

- `@snapshots` wird in 03 erstellt, aber nicht gemountet
- Snapper übernimmt Kontrolle über `/.snapshots`

---

### ⚠️ nano Unicode Problem

- Zeichen `·` kann Probleme machen
- Alternative:

    set whitespace "."

---

### ⚠️ VirtualBox / Clipboard

- TTY hat kein Clipboard
- Lösung: SSH nutzen

---

## 🧪 Testing Workflow

1. DRY-RUN ausführen
2. Output prüfen
3. VM Snapshot setzen
4. Änderungen machen
5. dann committen

---

## 💾 Git Workflow

    git add .
    git commit -m "Message"
    git push

👉 Nur committen wenn Zustand stabil ist

---

## 🔜 TODO

### 🔹 Wichtig

- [ ] 08_bootloader.sh implementieren (Limine)
- [ ] 10_snapshot_boot.sh (Snapshot Boot Menü)
- [ ] Netzwerk (NetworkManager)
- [ ] fstab doppelte Einträge verhindern

---

### 🔹 Optional

- [ ] man-pages-de optional nach Locale
- [ ] Snapper Cleanup
- [ ] Mirrorlist Optimierung
- [ ] zram / swap
- [ ] Logging verbessern

---

## 🧠 Philosophie

    erst funktional
    dann sauber
    dann schön

---

## 💪 Status

✔ Installer läuft vollständig im DRY-RUN
✔ Module 00–07 stabil
🚧 Bootloader in Planung

---

## 🚀 Nächste Schritte

- Bootloader (Limine) integrieren
- System bootfähig machen
- Snapshot Boot Menü

---

## 😄 Fazit

Du hast jetzt:

→ einen modularen Arch Installer
→ mit DRY-RUN Sicherheit
→ sauberer Architektur

👉 Das ist kein Anfängerprojekt mehr, mist xD
