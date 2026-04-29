#!/usr/bin/env bash

# =========================================
# 📦 UI & Logging Bibliothek
# -----------------------------------------
# Name:      ui.sh
# Zweck:     Ausgabe & Interaktion
#
# Aufgabe:
# - Logging (info, warn, error)
# - UI-Komponenten
# - Formatierung
#
# Wichtig:
# - KEINE Systemlogik
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. nur Darstellung
# 2. keine Seiteneffekte
# =========================================

# =========================
# 🎨 Farben & Logging
# =========================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =========================================
# ℹ️ Info-Log ausgeben
# -----------------------------------------
# Gibt formatierte Informationsmeldungen
# für normalen Ablauf aus
# =========================================

log()     { echo -e "${BLUE}[INFO]${NC} $1"; }

# =========================================
# ✅ Erfolgsmeldung ausgeben
# -----------------------------------------
# Signalisiert erfolgreich abgeschlossene
# Schritte im Installationsprozess
# =========================================

success() { echo -e "${GREEN}[OK]${NC} $1"; }

# =========================================
# ⚠️ Warnung ausgeben
# -----------------------------------------
# Zeigt nicht-kritische Probleme oder
# Hinweise für den Benutzer an
# =========================================

warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }

# =========================================
# ❌ Fehlermeldung ausgeben
# -----------------------------------------
# Signalisiert kritische Fehlerzustände
# im Installationsprozess
# =========================================

error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# =========================================
# 📌 Abschnitts-Header anzeigen
# -----------------------------------------
# Hebt neue Installationsphasen visuell hervor
# =========================================

header() {
  echo
  echo -e "${BLUE}=== $1 ===${NC}"
}

# =========================================
# 🔢 Nummer formatieren
# -----------------------------------------
# Formatiert Zahlen für konsistente
# Anzeige in Menüs
# =========================================

num() {
  echo -e "${YELLOW}${BOLD}$1${NC}"
}

# =========================================
# 📋 Menüoption anzeigen
# -----------------------------------------
# Gibt nummerierte Auswahloptionen
# für Benutzerinteraktion aus
# =========================================

print_option() {
  local number="$1"
  local text="$2"
  echo -e "$(num "[$number]") $text"
}

# =========================================
# 📊 Spaltenlayout anzeigen
# -----------------------------------------
# Formatiert Listen dynamisch in
# mehrere Spalten je nach Terminalbreite
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
# 🔍 Suchergebnisse anzeigen
# -----------------------------------------
# Zeigt gefilterte Ergebnisse mit
# Kontext und Navigation an
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
# Ordnet Locales und stellt sicher,
# dass en_US.UTF-8 zuletzt steht
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
# 📊 Statusübersicht anzeigen
# -----------------------------------------
# Zeigt aktuellen Fortschritt von
# Keymap, Timezone und Locales
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
# 🧭 Phasen-Header anzeigen
# -----------------------------------------
# Kombiniert Statusanzeige mit neuem
# Abschnitt für bessere Orientierung
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
