#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      02_prep.sh
# Zweck:     Vorbereitung der Live-Umgebung
#
# Aufgabe:
# - Systemzeit synchronisieren (NTP)
# - Pacman für parallele Downloads optimieren
# - Mirrorlist mit Reflector aktualisieren
#
# Wichtig:
# - Läuft auf dem Live-System (nicht in chroot)
# - Fehler hier verzögern/stören die Installation massiv
# =========================================

# =========================================
# 🕒 Funktion: prep_time
# -----------------------------------------
# Zweck:    Systemzeit via NTP abgleichen
# Aufgabe:  Verhindert SSL/TLS Zertifikatsfehler
# =========================================
prep_time() {
    phase_header "Systemzeit synchronisieren"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Systemzeit-Synchronisation (NTP) wird übersprungen."
        return 0
    fi

    log "Aktiviere systemd-timesyncd..."
    timedatectl set-ntp true

    # Kurzer Wait, um Sync zu erlauben
    sleep 2

    if timedatectl status | grep -q "System clock synchronized: yes"; then
        success "Zeit erfolgreich synchronisiert."
    else
        warn "Zeit-Sync nicht sofort bestätigt. Mache trotzdem weiter."
    fi
}

# =========================================
# 📦 Funktion: prep_pacman
# -----------------------------------------
# Zweck:    Download-Geschwindigkeit maximieren
# Aufgabe:  Aktiviert Color, ILoveCandy und 10 ParallelDownloads
# =========================================
prep_pacman() {
    phase_header "Pacman konfigurieren"
    local conf="/etc/pacman.conf"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Pacman-Optimierung in $conf wird übersprungen."
        return 0
    fi

    log "Optimiere $conf (Color, ParallelDownloads, ILoveCandy)..."

    # Color aktivieren
    sed -i 's/^#Color/Color/' "$conf"

    # ILoveCandy (Pac-Man Animation) hinzufügen, falls nicht vorhanden
    if ! grep -q "^ILoveCandy" "$conf"; then
        sed -i '/^Color/a ILoveCandy' "$conf"
    fi

    # Parallele Downloads auf 10 setzen
    sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' "$conf"
    if ! grep -q "^ParallelDownloads" "$conf"; then
        sed -i '/^#Misc options/a ParallelDownloads = 10' "$conf"
    fi

    success "Pacman erfolgreich optimiert."
}

# =========================================
# 🪞 Funktion: prep_mirrors
# -----------------------------------------
# Zweck:    Schnellste Download-Server finden
# Aufgabe:  Nutzt Reflector für HTTPS, Rate-Sorting
# Wichtig:  Kann je nach Netzwerk einige Sekunden dauern
# =========================================
prep_mirrors() {
    phase_header "Mirrorlist aktualisieren (Reflector)"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Reflector-Lauf wird übersprungen."
        return 0
    fi

    log "Prüfe, ob Reflector installiert ist..."
    if ! command -v reflector >/dev/null 2>&1; then
        warn "Reflector fehlt im Live-System. Installiere..."
        pacman -Sy --noconfirm reflector || {
            error "Konnte Reflector nicht installieren. Nutze Standard-Mirrors."
            return 1
        }
    fi

    log "Suche die schnellsten 10 HTTPS-Mirrors (Sortierung nach Downloadrate)..."

    # Ableitung des Landes aus der Zeitzone (z.B. Europe/Berlin -> Germany)
    local country=""
    if [[ "$TIMEZONE" == *"Berlin"* ]]; then country="Germany"; fi
    if [[ "$TIMEZONE" == *"Vienna"* ]]; then country="Austria"; fi
    if [[ "$TIMEZONE" == *"Zurich"* ]]; then country="Switzerland"; fi

    local reflector_cmd=(reflector --protocol https --latest 20 --sort rate --save /etc/pacman.d/mirrorlist)

    # Optionales Geo-Targeting, wenn das Land bekannt ist
    if [[ -n "$country" ]]; then
        log "Optimiere primär für Region: $country"
        reflector_cmd=(reflector --country "$country" --protocol https --latest 20 --sort rate --save /etc/pacman.d/mirrorlist)
    fi

    if "${reflector_cmd[@]}"; then
        success "Mirrorlist erfolgreich generiert und gespeichert."
    else
        error "Reflector fehlerhaft. Falle auf alte Mirrorlist zurück."
        return 1
    fi

    log "Aktualisiere Paketdatenbankbanken..."
    pacman -Syy || warn "Initiales pacman -Syy schlug fehl."
}

# =========================================
# ⚙️ Modul-Einstiegspunkt: run_prep
# -----------------------------------------
# Zweck:    Sequenzielle Ausführung des Moduls
# Aufgabe:  Ruft Sub-Funktionen in korrekter Ordnung auf
# =========================================
run_prep() {
    header "Phase 2: Live-System Vorbereitung"

    prep_time
    prep_pacman
    prep_mirrors

    success "Live-Umgebung ist bereit für die Installation."
}
