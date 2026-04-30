#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      00_config.sh
# Zweck:     Benutzerkonfiguration erfassen
#
# Aufgabe:
# - sammelt Installationsparameter
# - validiert Eingaben vor destruktiven Schritten
# - exportiert Konfiguration für alle Module
#
# Wichtig:
# - keine Systemänderungen
# - AUTO_MODE nur im DRY_RUN zulässig
# - falsche Werte können Datenverlust/Boot-Fail auslösen
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. Keine destruktiven Aktionen
# 2. Eingaben immer validieren
# 3. Sichere Defaults erzwingen
# 4. Secrets nie ausgeben oder loggen
# =========================================

# =========================
# 🤖 Presets / AUTO-MODE
# =========================

AUTO_MODE="${AUTO_MODE:-false}"
declare -a LOCALES=()

CONSOLE_FONT="${CONSOLE_FONT:-ter-v28n}"

# =========================================
# 🤖 AUTO_MODE Defaults setzen
# -----------------------------------------
# Setzt Testwerte für nicht-interaktive Runs
# → nur mit DRY_RUN sicher zulässig
# =========================================

set_default_config() {
  header "AUTO-MODE"

  warn "Standardkonfiguration wird geladen"
  warn "Alle Eingaben werden übersprungen"
  echo

  HOSTNAME="archtest"
  USERNAME="user"
  USER_PASSWORD="password"
  LUKS_PASSWORD=""

  KEYMAP="de"
  TIMEZONE="Europe/Berlin"
  LOCALES=("en_US.UTF-8")
  LANG_DEFAULT="en_US.UTF-8"

  DISK="${DISK:-/dev/sda}"
  INSTALL_PROFILE="standard"
  USE_LUKS="no"

  DISABLE_ROOT="yes"
  ENABLE_MULTILIB="yes"

  INSTALL_SHELL="yes"
  INSTALL_TOOLS="yes"
  INSTALL_AUR="yes"
  INSTALL_EDITOR="yes"
  INSTALL_SSH="yes"

  CONSOLE_FONT="ter-v28n"
}

# =========================================
# 📤 Konfiguration exportieren
# -----------------------------------------
# Macht validierte Werte für Module verfügbar
# → verhindert implizite/fehlende Parameter
# =========================================

export_config() {
  export KEYMAP TIMEZONE LANG_DEFAULT
  export DISK INSTALL_PROFILE USE_LUKS
  export HOSTNAME USERNAME USER_PASSWORD LUKS_PASSWORD
  export DISABLE_ROOT ENABLE_MULTILIB MICROCODE_PKG
  export INSTALL_SHELL INSTALL_TOOLS INSTALL_AUR INSTALL_EDITOR
  export INSTALL_SSH
  export CONSOLE_FONT
}

# =========================================
# ❓ Ja/Nein Eingabe abfragen
# -----------------------------------------
# Normalisiert Benutzerantworten auf yes/no
# → verhindert mehrdeutige Entscheidungen
# =========================================

ask_yes_no() {
  local prompt="$1"
  local answer

  while true; do
    read -rp "$(echo -e "${BLUE}[INPUT]${NC} $prompt (j/n): ")" answer
    answer="${answer,,}"

    case "$answer" in
      j|ja|y|yes)
        echo "yes"
        return 0
        ;;
      n|nein|no)
        echo "no"
        return 0
        ;;
      *)
        warn "Bitte mit j/n oder y/n antworten."
        ;;
    esac
  done
}

# =========================================
# 🔒 Root-Rechte prüfen
# -----------------------------------------
# Erzwingt Ausführung als root
# → verhindert halbe Installation durch Rechtefehler
# =========================================

check_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    error "Bitte als root ausführen."
    exit 1
  fi

  return 0
}

# =========================================
# 🖥️ UEFI-Modus prüfen
# -----------------------------------------
# Bricht auf BIOS/Legacy-Systemen ab
# → Bootloader-Setup ist nur für UEFI gebaut
# =========================================

check_uefi() {
  if [[ ! -d /sys/firmware/efi ]]; then
    error "UEFI erforderlich."
    exit 1
  fi

  return 0
}

# =========================================
# 🔤 Hostname validieren
# -----------------------------------------
# Prüft Hostname auf sichere Zeichen
# → verhindert spätere Netzwerk-/Configfehler
# =========================================

validate_hostname_value() {
  [[ "$1" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]
}

# =========================================
# 👤 Benutzername validieren
# -----------------------------------------
# Prüft Linux-kompatiblen Usernamen
# → verhindert fehlerhafte User-Erstellung
# =========================================

validate_username_value() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]]
}

# =========================================
# ⌨️ Tastaturlayout auswählen
# -----------------------------------------
# Setzt gültige Keymap für Live-System
# → verhindert falsche Passworteingaben
# =========================================

select_keyboard() {
  local choice
  local detected=""
  local search selected

  [[ "${LANG:-}" =~ de ]] && detected="de"
  [[ "${LANG:-}" =~ en ]] && detected="us"

  phase_header "Tastaturlayout auswählen"

  if [[ -n "$detected" ]]; then
    print_option 1 "$detected (automatisch erkannt)"
  else
    print_option 1 "de (Deutsch)"
  fi

  print_option 2 "us (US / Standard)"
  print_option 3 "manuell suchen"

  while true; do
    read -rp "$(echo -e "${BLUE}[INPUT]${NC} Auswahl [1-3]: ")" choice

    case "$choice" in
      1)
        KEYMAP="${detected:-de}"
        break
        ;;
      2)
        KEYMAP="us"
        break
        ;;
      3)
        while true; do
          read -rp "$(echo -e "${BLUE}[INPUT]${NC} Keymap-Suche, z. B. de, us, fr: ")" search

          mapfile -t KEYMAP_RESULTS < <(
            localectl list-keymaps | grep -i "$search" | sort -u
          )

          if [[ ${#KEYMAP_RESULTS[@]} -eq 0 ]]; then
            warn "Keine Keymap gefunden."
            if [[ "$(ask_yes_no "Erneut suchen?")" == "yes" ]]; then
              continue
            else
              break
            fi
          fi

          if (( ${#KEYMAP_RESULTS[@]} > 40 )); then
            clear
            header "Keymap Suche"

            echo -e "${CYAN}Suche:${NC} $search"
            echo -e "${CYAN}Treffer:${NC} ${#KEYMAP_RESULTS[@]}"
            echo

            warn "Zu viele Treffer. Bitte Suche verfeinern."
            echo
            continue
            fi

            print_search_results "Keymap Treffer" "$search" KEYMAP_RESULTS

          while true; do
            read -rp "$(echo -e "${BLUE}[INPUT]${NC} Keymap wählen [1-${#KEYMAP_RESULTS[@]}] oder 0 für neue Suche: ")" selected

            [[ "$selected" == "0" ]] && break

            if [[ "$selected" =~ ^[0-9]+$ ]] && (( selected >= 1 && selected <= ${#KEYMAP_RESULTS[@]} )); then
              KEYMAP="${KEYMAP_RESULTS[$((selected-1))]}"
              choice="done"
              break 2
            fi

            warn "Ungültige Auswahl."
          done
        done

        [[ "$choice" == "done" ]] && break
        ;;
      *)
        warn "Ungültige Auswahl."
        ;;
    esac
  done

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Tastaturlayout setzen: $KEYMAP"
  else
    loadkeys "$KEYMAP" 2>/dev/null || warn "Konnte Tastaturlayout nicht setzen."
  fi
}

# =========================================
# 🌍 Zeitzone erkennen
# -----------------------------------------
# Erkennt Timezone optional per IP-Service
# → Fallback bleibt manuelle Auswahl
# =========================================

detect_timezone() {
  command -v curl >/dev/null 2>&1 || return 0

  local tz
  tz="$(curl -fs --max-time 3 https://ipapi.co/timezone 2>/dev/null || true)"

  if [[ -n "$tz" && -f "/usr/share/zoneinfo/$tz" ]]; then
    echo "$tz"
  fi

  return 0
}

# =========================================
# 🔍 Zeitzone manuell suchen
# -----------------------------------------
# Sucht gültige systemd-Timezones
# → verhindert ungültige /etc/localtime Ziele
# =========================================

select_timezone_manual() {
 local search choice
 local max_results=20

 while true; do
  clear
  header "Zeitzone suchen"

  read -rp "$(echo -e "${BLUE}[INPUT]${NC} Suche eingeben, z. B. berlin, new, tokyo: ")" search

  if [[ -z "$search" ]]; then
   warn "Bitte Suchbegriff eingeben."
   continue
  fi

  mapfile -t TZ_RESULTS < <(
   timedatectl list-timezones | grep -i "$search" | sort
  )

  if [[ ${#TZ_RESULTS[@]} -eq 0 ]]; then
   warn "Keine Treffer für: $search"
   echo
   continue
  fi

  if (( ${#TZ_RESULTS[@]} > max_results )); then
   warn "Zu viele Treffer: ${#TZ_RESULTS[@]}"
   warn "Bitte Suche verfeinern, z. B. 'berlin' statt 'ber' oder 'new_york' statt 'new'."
   echo
   read -rp "$(echo -e "${BLUE}[INPUT]${NC} Weiter mit Enter...")"
   continue
  fi

  print_search_results "Zeitzone Treffer" "$search" TZ_RESULTS

  while true; do
   read -rp "$(echo -e "${BLUE}[INPUT]${NC} Zeitzone wählen [1-${#TZ_RESULTS[@]}] oder 0 für neue Suche: ")" choice

   [[ "$choice" == "0" ]] && break

   if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#TZ_RESULTS[@]} )); then
    TIMEZONE="${TZ_RESULTS[$((choice-1))]}"
    success "Zeitzone gewählt: $TIMEZONE"
    return 0
   fi

   warn "Ungültige Auswahl."
  done
 done
}

# =========================================
# 🌍 Zeitzone auswählen
# -----------------------------------------
# Kombiniert Auto-Erkennung und Suche
# → setzt validierte System-Zeitzone
# =========================================

select_timezone() {
  local detected
  local choice

  phase_header "Zeitzone auswählen"

  detected="$(detect_timezone)"

  if [[ -n "$detected" ]]; then
    log "Automatisch erkannt: $detected"

    print_option 1 "erkannte Zeitzone verwenden ($detected)"
    print_option 2 "manuell auswählen"

    while true; do
      read -rp "$(echo -e "${BLUE}[INPUT]${NC} Auswahl [1-2]: ")" choice

      case "$choice" in
        1)
          TIMEZONE="$detected"
          return 0
          ;;
        2)
          select_timezone_manual
          return 0
          ;;
        *)
          warn "Ungültige Auswahl."
          ;;
      esac
    done
  fi

  log "Automatische Zeitzone konnte nicht erkannt werden (kein Internet?)."
  echo -e "${CYAN}Hinweis:${NC} Bitte wähle deine Zeitzone manuell aus."
  echo

  print_option 1 "manuell suchen"

  while true; do
    read -rp "$(echo -e "${BLUE}[INPUT]${NC} Auswahl [1]: ")" choice

    case "$choice" in
      1)
        select_timezone_manual
        return 0
        ;;
      *)
        warn "Ungültige Auswahl."
        ;;
    esac
  done
}

# =========================================
# 🌐 Locale auswählen
# -----------------------------------------
# Wählt Systemsprache mit en_US Fallback
# → verhindert kaputte Locale-Konfiguration
# =========================================

select_locale() {
  local detected=""
  local choice

  phase_header "Locale auswählen"

  LOCALES=("en_US.UTF-8")
  LANG_DEFAULT="en_US.UTF-8"

  echo -e "${CYAN}Standard:${NC} en_US.UTF-8 ist immer aktiv."
  echo

  [[ "${LANG:-}" =~ de ]] && detected="de_DE.UTF-8"

  print_option 1 "${detected:-de_DE.UTF-8} hinzufügen (Vorschlag)"
  print_option 2 "manuell auswählen"
  print_option 3 "keine zusätzliche Locale"

  while true; do
    read -rp "$(echo -e "${BLUE}[INPUT]${NC} Auswahl [1-3]: ")" choice

    case "$choice" in
      1)
        if [[ -n "$detected" ]]; then
          LOCALES=("$detected" "en_US.UTF-8")
          LANG_DEFAULT="$detected"
        else
          LOCALES=("de_DE.UTF-8" "en_US.UTF-8")
          LANG_DEFAULT="de_DE.UTF-8"
        fi
        return 0
        ;;
      2)
        select_locale_manual
        return 0
        ;;
      3)
        LOCALES=("en_US.UTF-8")
        LANG_DEFAULT="en_US.UTF-8"
        return 0
        ;;
      *)
        warn "Ungültige Auswahl."
        ;;
    esac
  done
}

# =========================================
# 🔍 Locale manuell suchen
# -----------------------------------------
# Durchsucht locale.gen und ermöglicht
# gezielte Auswahl verfügbarer Locales
# =========================================

select_locale_manual() {
  local search choice selected
  local max_results=20

  while true; do
    read -rp "$(echo -e "${BLUE}[INPUT]${NC} Locale-Suche eingeben, z. B. de, fr, es: ")" search

    mapfile -t LOCALE_RESULTS < <(
      grep -E "^#?[a-z]{2}_[A-Z]{2}\.UTF-8 UTF-8" /etc/locale.gen \
        | sed 's/^#//' \
        | awk '{print $1}' \
        | grep -i "$search" \
        | sort -u
    )

    if [[ ${#LOCALE_RESULTS[@]} -eq 0 ]]; then
      clear
      header "Locale Suche"
      echo -e "${CYAN}Suche:${NC} $search"
      echo -e "${CYAN}Treffer:${NC} 0"
      echo

      warn "Keine Locale gefunden."
      continue
    fi

    if (( ${#LOCALE_RESULTS[@]} > max_results )); then
      clear
      header "Locale Suche"
      echo -e "${CYAN}Suche:${NC} $search"
      echo -e "${CYAN}Treffer:${NC} ${#LOCALE_RESULTS[@]}"
      echo

      warn "Zu viele Treffer. Bitte Suche verfeinern."
      continue
    fi

    print_search_results "Locale Treffer" "$search" LOCALE_RESULTS

    while true; do
      read -rp "$(echo -e "${BLUE}[INPUT]${NC} Locale wählen [1-${#LOCALE_RESULTS[@]}] oder 0 für neue Suche: ")" choice

      [[ "$choice" == "0" ]] && break

      if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#LOCALE_RESULTS[@]} )); then
        selected="${LOCALE_RESULTS[$((choice-1))]}"

        if [[ "$selected" == "en_US.UTF-8" ]]; then
          LOCALES=("en_US.UTF-8")
          LANG_DEFAULT="en_US.UTF-8"
        else
          LOCALES=("$selected" "en_US.UTF-8")
          LANG_DEFAULT="$selected"
        fi

        success "Locale gesetzt: ${LOCALES[*]}"
        return 0
      fi

      warn "Ungültige Auswahl."
    done
  done
}

# =========================================
# 💽 Sichere Laufwerksauswahl (FINAL)
# -----------------------------------------
# Filtert Systemdisk + zeigt alle realen Targets
# → verhindert Selbstzerstörung + erlaubt USB
# =========================================

select_disk() {
  local choice entry root_parent

  phase_header "Ziellaufwerk auswählen"

  root_parent="$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -n1)"
  root_parent="/dev/${root_parent}"

  mapfile -t DISKS < <(
    lsblk -dn -o NAME,SIZE,TYPE,MODEL | awk '$3=="disk"{print "/dev/"$1" | "$2" | "$4}'
  )

  local filtered=()
  for entry in "${DISKS[@]}"; do
    local dev="${entry%% | *}"
    [[ "$dev" == "$root_parent" ]] && continue
    filtered+=("$entry")
  done

  [[ ${#filtered[@]} -eq 0 ]] && {
    error "Keine geeigneten Laufwerke gefunden."
    exit 1
  }

  local i=1
  for entry in "${filtered[@]}"; do
    print_option "$i" "$entry"
    ((i++))
  done

  while true; do
    read -rp "$(echo -e "${BLUE}[INPUT]${NC} Auswahl: ")" choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#filtered[@]} )); then
      DISK="${filtered[$((choice-1))]%% | *}"
      success "Gewählt: $DISK"
      return 0
    fi

    warn "Ungültig."
  done
}

# =========================================
# 🧩 Installationsprofil auswählen
# -----------------------------------------
# Setzt Standard- oder LUKS-Layout
# → steuert spätere Disk-/Bootlogik
# =========================================

select_install_profile() {
  local choice

  phase_header "Disk-Setup auswählen"

  print_option 1 "standard | EFI + BTRFS"
  print_option 2 "luks     | EFI + LUKS + BTRFS"

  while true; do
    read -rp "$(echo -e "${BLUE}[INPUT]${NC} Auswahl [1-2]: ")" choice

    case "$choice" in
      1)
        INSTALL_PROFILE="standard"
        USE_LUKS="no"
        return 0
        ;;
      2)
        INSTALL_PROFILE="luks"
        USE_LUKS="yes"
        return 0
        ;;
      *)
        warn "Ungültige Auswahl."
        ;;
    esac
  done
}

# =========================================
# 🔐 Passwörter abfragen
# -----------------------------------------
# Erfasst User- und optional LUKS-Passwort
# → Secrets niemals ausgeben oder loggen
# =========================================

ask_passwords() {
  while true; do
    read -rsp "$(echo -e "${BLUE}[INPUT]${NC} Benutzer-Passwort: ")" USER_PASSWORD
    echo
    read -rsp "$(echo -e "${BLUE}[INPUT]${NC} Benutzer-Passwort wiederholen: ")" USER_PASSWORD_CONFIRM
    echo

    if [[ -n "$USER_PASSWORD" && "$USER_PASSWORD" == "$USER_PASSWORD_CONFIRM" ]]; then
      break
    fi

    error "Passwörter stimmen nicht überein oder sind leer."
  done

  if [[ "$USE_LUKS" == "yes" ]]; then
    while true; do
      read -rsp "$(echo -e "${BLUE}[INPUT]${NC} LUKS-Passwort: ")" LUKS_PASSWORD
      echo
      read -rsp "$(echo -e "${BLUE}[INPUT]${NC} LUKS-Passwort wiederholen: ")" LUKS_PASSWORD_CONFIRM
      echo

      if [[ -n "$LUKS_PASSWORD" && "$LUKS_PASSWORD" == "$LUKS_PASSWORD_CONFIRM" ]]; then
        break
      fi

      error "LUKS-Passwörter stimmen nicht überein oder sind leer."
    done
  else
    LUKS_PASSWORD=""
  fi
}

# =========================================
# 🧠 Konfiguration sammeln
# -----------------------------------------
# Führt alle interaktiven Eingaben aus
# → Grundlage für destruktive Module
# =========================================

collect_config() {
  if [[ "$AUTO_MODE" == true ]]; then
    if [[ "${DRY_RUN:-true}" != true ]]; then
      error "AUTO_MODE darf nicht mit DRY_RUN=false laufen."
      error "Grund: AUTO_MODE nutzt Standardwerte wie DISK=/dev/sda und ein Standardpasswort."
      exit 1
    fi

    warn "[AUTO-MODE] Verwende Standardkonfiguration"
    set_default_config
    return
  fi

  clear
  header "Arch Install Config"

  check_root
  check_uefi

  select_keyboard
  select_timezone
  select_locale
  select_disk
  select_install_profile

  phase_header "System-Konfiguration"

  while true; do
    read -rp "$(echo -e "${BLUE}[INPUT]${NC} Hostname (Computername im Netzwerk, z. B. arch-pc): ")" HOSTNAME
    validate_hostname_value "$HOSTNAME" && break
    error "Ungültiger Hostname. Erlaubt: a-z, 0-9 und '-'. Nicht mit '-' beginnen/enden."
  done

  while true; do
    read -rp "$(echo -e "${BLUE}[INPUT]${NC} Benutzername (Login-Name, z. B. max): ")" USERNAME
    validate_username_value "$USERNAME" && break
    error "Ungültiger Benutzername. Muss mit Buchstabe/_ beginnen. Erlaubt: a-z, 0-9, _, -."
  done

  ask_passwords

  echo -e "${CYAN}Hinweis:${NC} Root-Login deaktivieren ist sicherer. Anmeldung erfolgt über sudo."
  DISABLE_ROOT="$(ask_yes_no "Root-Login deaktivieren?")"
  ENABLE_MULTILIB="$(ask_yes_no "Multilib aktivieren?")"

  INSTALL_SHELL="$(ask_yes_no "Fish + Starship + Aliase installieren?")"
  INSTALL_TOOLS="$(ask_yes_no "CLI-Tools installieren?")"
  INSTALL_AUR="$(ask_yes_no "Paru installieren?")"
  INSTALL_EDITOR="$(ask_yes_no "Nano-Setup installieren?")"

  echo
  INSTALL_SSH="$(ask_yes_no "SSH (OpenSSH) installieren und aktivieren?")"
}

# =========================================
# ✔ Konfiguration validieren
# -----------------------------------------
# Prüft Pflichtwerte und Zielgerät
# → stoppt vor gefährlichen Operationen
# =========================================

validate_config() {
  header "Validierung"

  [[ -n "${KEYMAP:-}" ]] || { error "Keymap fehlt."; exit 1; }
  [[ -n "${TIMEZONE:-}" ]] || { error "Zeitzone fehlt."; exit 1; }
  [[ -n "${DISK:-}" ]] || { error "DISK fehlt."; exit 1; }

  if [[ "${DRY_RUN:-true}" != true ]]; then
    [[ -b "$DISK" ]] || { error "$DISK ist kein gültiges Blockdevice."; exit 1; }
  else
    warn "[DRY-RUN] Blockdevice-Prüfung für $DISK wird übersprungen."
  fi

  validate_hostname_value "$HOSTNAME" || { error "Hostname ungültig."; exit 1; }
  validate_username_value "$USERNAME" || { error "Benutzername ungültig."; exit 1; }

  success "Konfiguration gültig."
}

# =========================================
# 📋 Konfiguration bestätigen
# -----------------------------------------
# Zeigt finalen Installationsplan
# → letzte Sperre vor Datenverlust
# =========================================

confirm_config() {
  if [[ "${AUTO_MODE:-false}" == true ]]; then
    warn "[AUTO-MODE] Bestätigung wird übersprungen."
    return 0
  fi

  while true; do
    clear
    header "Zusammenfassung"

    echo -e "${CYAN}System:${NC}     ${USERNAME}@${HOSTNAME}"
    echo -e "${CYAN}Keyboard:${NC}   $KEYMAP"
    echo -e "${CYAN}Timezone:${NC}   $TIMEZONE"
    echo -e "${CYAN}Locales:${NC}    $(format_locales)"
    echo -e "${CYAN}LANG:${NC}       $LANG_DEFAULT"
    echo
    echo -e "${CYAN}Disk:${NC}       $DISK"
    echo -e "${CYAN}Profil:${NC}     $INSTALL_PROFILE"
    echo -e "${CYAN}LUKS:${NC}       $USE_LUKS"
    echo
    echo -e "${CYAN}Root sperren:${NC} $DISABLE_ROOT"
    echo -e "${CYAN}Multilib:${NC}     $ENABLE_MULTILIB"
    echo
    echo -e "${CYAN}Optionale Module:${NC}"
    echo "  Fish/Shell: $INSTALL_SHELL"
    echo "  CLI-Tools:  $INSTALL_TOOLS"
    echo "  Paru:       $INSTALL_AUR"
    echo "  Nano:       $INSTALL_EDITOR"
    echo "  SSH:        ${INSTALL_SSH:-no}"
    echo

    if [[ "${DRY_RUN:-true}" == true ]]; then
      warn "DRY-RUN aktiv: Module laufen im Testmodus und schreiben keine Änderungen."
      echo
    fi

    warn "Achtung: Alle Daten auf $DISK können gelöscht werden."
    echo

    if [[ "$(ask_yes_no "Sind diese Angaben korrekt?")" == "yes" ]]; then
      return 0
    fi

    collect_config
    validate_config
    export_config
  done
}

# =========================================
# 🔍 CPU-Microcode erkennen
# -----------------------------------------
# Wählt Intel-/AMD-Microcodepaket
# → verbessert Boot-Stabilität und CPU-Fixes
# =========================================

bestimme_microcode_paket() {
  local cpu_vendor
  cpu_vendor=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')

  case "$cpu_vendor" in
    GenuineIntel)
      MICROCODE_PKG="intel-ucode"
      log "Hardware: Intel CPU erkannt ($MICROCODE_PKG)."
      ;;
    AuthenticAMD)
      MICROCODE_PKG="amd-ucode"
      log "Hardware: AMD CPU erkannt ($MICROCODE_PKG)."
      ;;
    *)
      MICROCODE_PKG=""
      warn "Hardware: Unbekannte CPU. Kein Microcode-Paket gewählt."
      ;;
  esac
  export MICROCODE_PKG
}

# Initialer Aufruf zur Befüllung der Variable
bestimme_microcode_paket
