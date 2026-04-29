#!/usr/bin/env bash

# =========================================
# 📦 UI & Logging Bibliothek
# -----------------------------------------
# Name:      ui.sh
# Zweck:     Ausgabe und Interaktion kapseln
#
# Aufgabe:
# - stellt Farb- und Logfunktionen bereit
# - formatiert Menüs, Listen und Header
# - zeigt Status- und Suchergebnisse
#
# Wichtig:
# - keine Systemlogik
# - keine destruktiven Aktionen
# - Ausgabe darf keine Secrets enthalten
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. Nur Darstellung
# 2. Keine Seiteneffekte
# 3. Keine Secrets ausgeben
# 4. Keine Installer-Logik einbauen
# =========================================

# =========================
# 🎨 Farben definieren
# =========================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =========================================
# ℹ️ Info ausgeben
# -----------------------------------------
# Formatiert normale Statusmeldungen
# → für nicht-kritische Ablaufinfos
# =========================================

log() {
  local msg="$1"
  echo -e "${BLUE}[INFO]${NC} $msg"

  if declare -F log_to_file >/dev/null; then
    log_to_file "$msg"
  fi
}

# =========================================
# ✅ Erfolg ausgeben
# -----------------------------------------
# Markiert erfolgreich abgeschlossene Schritte
# → visuelles Feedback für sichere Zustände
# =========================================

success() { echo -e "${GREEN}[OK]${NC} $1"; }

# =========================================
# ⚠️ Warnung ausgeben
# -----------------------------------------
# Markiert nicht-fatale Probleme
# → Benutzer muss mögliche Risiken sehen
# =========================================

warn() {
  local msg="$1"
  echo -e "${YELLOW}[WARN]${NC} $msg"

  if declare -F log_to_file >/dev/null; then
    log_to_file "WARN: $msg"
  fi
}

# =========================================
# ❌ Fehler ausgeben
# -----------------------------------------
# Markiert kritische Fehlerzustände
# → Aufrufer muss danach abbrechen
# =========================================

error() {
  local msg="$1"
  echo -e "${RED}[ERROR]${NC} $msg"

  if declare -F log_to_file >/dev/null; then
    log_to_file "ERROR: $msg"
  fi
}

# =========================================
# 📌 Header ausgeben
# -----------------------------------------
# Zeigt neuen Abschnitt im Ablauf
# → verbessert Orientierung im Installer
# =========================================

header() {
  echo
  echo -e "${BLUE}=== $1 ===${NC}"
}

# =========================================
# 🔢 Nummer formatieren
# -----------------------------------------
# Formatiert Menünummern farbig
# → konsistente Auswahloberfläche
# =========================================

num() {
  echo -e "${YELLOW}${BOLD}$1${NC}"
}

# =========================================
# 📋 Menüoption ausgeben
# -----------------------------------------
# Zeigt nummerierte Auswahloption
# → Standardformat für interaktive Menüs
# =========================================

print_option() {
  local number="$1"
  local text="$2"
  echo -e "$(num "[$number]") $text"
}

# =========================================
# 📊 Spalten ausgeben
# -----------------------------------------
# Formatiert Listen abhängig von Terminalbreite
# → bessere Lesbarkeit bei vielen Treffern
# =========================================

print_columns() {
  local -n items=$1

  local term_width
  term_width=$(tput cols 2>/dev/null || echo 80)

  local max_len=0
  local item

  for item in "${items[@]}"; do
    (( ${#item} > max_len )) && max_len=${#item}
  done

  local num_width=6
  local col_width=$(( max_len + 2 ))
  local cols=$(( term_width / (num_width + col_width) ))

  (( cols < 1 )) && cols=1
  (( cols > 3 )) && cols=3

  local count=${#items[@]}
  local rows=$(( (count + cols - 1) / cols ))

  for ((r=0; r<rows; r++)); do
    for ((c=0; c<cols; c++)); do
      local index=$(( c * rows + r ))

      if (( index < count )); then
        printf "%b %-${col_width}s" "$(num "$(printf "[%2d]" $((index+1)))")" "${items[index]}"
      fi
    done
    echo
  done

  echo
}

# =========================================
# 🔍 Suchergebnisse ausgeben
# -----------------------------------------
# Zeigt Suche, Trefferzahl und Ergebnisliste
# → konsistente Auswahl nach Suchvorgängen
# =========================================

print_search_results() {
  local title="$1"
  local search="$2"
  local -n results=$3

  clear

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] Testmodus aktiv"
    echo
  fi

  header "$title"

  echo -e "${CYAN}Suche:${NC} $search"
  echo -e "${CYAN}Treffer:${NC} ${#results[@]}"
  echo

  print_columns results
}

# =========================================
# 🌐 Locales formatieren
# -----------------------------------------
# Sortiert en_US.UTF-8 ans Ende
# → vermeidet verwirrende Locale-Anzeige
# =========================================

format_locales() {
  declare -p LOCALES >/dev/null 2>&1 || return 0

  if [[ ${#LOCALES[@]} -eq 0 ]]; then
    return 0
  fi

  local result=()
  local has_en_us=false
  local loc

  for loc in "${LOCALES[@]}"; do
    if [[ "$loc" == "en_US.UTF-8" ]]; then
      has_en_us=true
    else
      result+=("$loc")
    fi
  done

  if $has_en_us; then
    result+=("en_US.UTF-8")
  fi

  echo "${result[*]}"
}

# =========================================
# 📊 Statusblock ausgeben
# -----------------------------------------
# Zeigt gewählte Keymap, Timezone und Locales
# → Orientierung während der Konfiguration
# =========================================

print_info_block() {
  local has_info=false

  [[ -n "${KEYMAP:-}" ]] && has_info=true
  [[ -n "${TIMEZONE:-}" ]] && has_info=true
  declare -p LOCALES >/dev/null 2>&1 && [[ ${#LOCALES[@]} -gt 0 ]] && has_info=true

  [[ "$has_info" == false ]] && return 0

  header "Aktueller Status"

  [[ -n "${KEYMAP:-}" ]] && echo -e "${GREEN}✔${NC} ${CYAN}Keymap:${NC}   $KEYMAP"
  [[ -n "${TIMEZONE:-}" ]] && echo -e "${GREEN}✔${NC} ${CYAN}Timezone:${NC} $TIMEZONE"

  if declare -p LOCALES >/dev/null 2>&1 && [[ ${#LOCALES[@]} -gt 0 ]]; then
    echo -e "${GREEN}✔${NC} ${CYAN}Locales:${NC}  $(format_locales)"
  fi

  echo
}

# =========================================
# 🧭 Phasenheader ausgeben
# -----------------------------------------
# Räumt Bildschirm und zeigt Status + Abschnitt
# → sauberer Wechsel zwischen Eingabephasen
# =========================================

phase_header() {
  clear

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] Testmodus aktiv"
    echo
  fi

  print_info_block
  header "$1"
}
