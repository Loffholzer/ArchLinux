#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      01_utils.sh
# Zweck:     Globale Hilfsfunktionen und UI
#
# Aufgabe:
# - Bereitstellung von Farben und Formatting
# - Standardisiertes Logging (log, warn, error)
# - UI-Elemente für Config-Auswahlen
#
# Wichtig:
# - Muss als erstes Modul geladen werden
# - Keine Systemzustandsänderungen
# =========================================

# =========================================
# 🎨 Farbdefinitionen
# -----------------------------------------
# Zweck:    Konsistente Konsolenausgabe
# Aufgabe:  Exportiert ANSI-Farbcodes
# Wichtig:  NC (No Color) immer zum Zurücksetzen nutzen
# =========================================
export RED='\033[1;31m'
export GREEN='\033[1;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[1;34m'
export CYAN='\033[1;36m'
export BOLD='\033[1m'
export NC='\033[0m'

# =========================================
# 📝 UI-Funktion: header
# -----------------------------------------
# Zweck:    Visuelle Trennung von Hauptphasen
# Aufgabe:  Gibt eine formatierte Box aus
# Wichtig:  Löscht nicht zwingend den Screen
# =========================================
header() {
    local text="$1"
    echo -e "\n${BLUE}=========================================${NC}"
    echo -e "${BOLD}${CYAN} 🚀 ${text}${NC}"
    echo -e "${BLUE}=========================================${NC}\n"
}

# =========================================
# 📝 UI-Funktion: phase_header
# -----------------------------------------
# Zweck:    Visuelle Trennung von Sub-Schritten
# Aufgabe:  Gibt einen leichten Header aus
# =========================================
phase_header() {
    local text="$1"
    echo -e "\n${BOLD}${BLUE}--- ${text} ---${NC}\n"
}

# =========================================
# 📝 Logging: log
# -----------------------------------------
# Zweck:    Standard-Informationsausgabe
# Aufgabe:  Prefix [INFO] mit Text
# =========================================
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# =========================================
# 📝 Logging: success
# -----------------------------------------
# Zweck:    Bestätigung erfolgreicher Aktionen
# Aufgabe:  Prefix [OK] in Grün mit Text
# =========================================
success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# =========================================
# 📝 Logging: warn
# -----------------------------------------
# Zweck:    Warnungen (nicht-kritische Fehler)
# Aufgabe:  Prefix [WARN] in Gelb mit Text
# =========================================
warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

# =========================================
# 📝 Logging: error
# -----------------------------------------
# Zweck:    Kritische Fehler
# Aufgabe:  Prefix [ERROR] in Rot mit Text
# Wichtig:  Beendet Skript nicht (Passiert explizit)
# =========================================
error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# =========================================
# 📝 UI-Funktion: print_option
# -----------------------------------------
# Zweck:    Darstellung von Auswahlmöglichkeiten
# Aufgabe:  Formatiert Nummer und Beschreibung
# =========================================
print_option() {
    local num="$1"
    local desc="$2"
    echo -e "  ${CYAN}[${num}]${NC} ${desc}"
}

# =========================================
# 📝 UI-Funktion: print_search_results
# -----------------------------------------
# Zweck:    Ausgabe von Array-Suchergebnissen
# Aufgabe:  Iteriert über übergebenes Array
# Wichtig:  Nutzt nameref für Array-Referenz
# =========================================
print_search_results() {
    local title="$1"
    local search="$2"
    local -n arr_ref="$3"
    local i=1

    phase_header "${title} (Suche: ${search})"

    for item in "${arr_ref[@]}"; do
        print_option "$i" "$item"
        ((i++))
    done
    echo
}

# =========================================
# 📝 Helper: format_locales
# -----------------------------------------
# Zweck:    Formatierung des Locale-Arrays
# Aufgabe:  Verbindet Array-Elemente zu String
# Wichtig:  Wird von confirm_config erwartet
# =========================================
format_locales() {
    if [[ -n "${LOCALES[*]:-}" ]]; then
        echo "${LOCALES[*]}"
    else
        echo "en_US.UTF-8"
    fi
}

# =========================================
# ⚙️ Modul-Einstiegspunkt: run_utils
# -----------------------------------------
# Zweck:    Zentraler Aufrufpunkt des Moduls
# Aufgabe:  Initialisiert Umgebung (Konsolen-Reset)
# Wichtig:  Entspricht den Architekturvorgaben
# =========================================
run_utils() {
    # Setzt die Konsole zurück für eine saubere Ausgabe
    tput reset 2>/dev/null || clear
    log "Utilities geladen. (Terminal initialisiert)"
}
