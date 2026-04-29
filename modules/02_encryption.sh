#!/usr/bin/env bash
# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      02_encryption.sh
# Zweck:     LUKS-Verschlüsselung
#
# Aufgabe:
# - optional LUKS einrichten
# - Container öffnen
# - Root-Device definieren
#
# Wichtig:
# - Passwort sensibel behandeln
# - kein Logging von Secrets
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. KEINE Passwort-Ausgabe
# 2. Fehler sofort abbrechen
# 3. Device nach Öffnen validieren
# 4. Mapper sauber schließen bei Abbruch
# =========================================


# =========================================
# 🔐 Verschlüsselung orchestrieren
# -----------------------------------------
# Steuert optionales LUKS-Setup und setzt
# korrektes Root-Device für Folgemodule
# =========================================
run_encryption_setup() {
  header "02 - Verschlüsselung"

  pruefe_encryption_variablen

  if [[ "${USE_LUKS:-no}" != "yes" ]]; then
    log "LUKS nicht aktiviert. Root-Gerät bleibt unverschlüsselt."

    ROOT_DEVICE="$ROOT_PART"
    ROOT_BASE_DEVICE="$ROOT_PART"
    ROOT_MAPPER_NAME=""

    export ROOT_DEVICE ROOT_BASE_DEVICE ROOT_MAPPER_NAME

    success "Root-Gerät: ${ROOT_DEVICE}"
    return 0
  fi

  zeige_luks_plan
  richte_luks_ein

  success "Verschlüsselung vorbereitet."
}

# =========================================
# 🔒 Verschlüsselungs-Variablen prüfen
# -----------------------------------------
# Validiert Root-Partition und stellt
# sichere Voraussetzungen für LUKS sicher
# =========================================
pruefe_encryption_variablen() {
  [[ -n "${ROOT_PART:-}" ]] || { error "ROOT_PART ist nicht gesetzt."; exit 1; }
  [[ -n "${USE_LUKS:-}" ]] || { error "USE_LUKS ist nicht gesetzt."; exit 1; }

  if [[ "${DRY_RUN:-true}" != true ]]; then
    [[ -b "$ROOT_PART" ]] || { error "$ROOT_PART ist kein gültiges Blockdevice."; exit 1; }
  fi
}

# =========================================
# 📋 LUKS-Setup anzeigen
# -----------------------------------------
# Zeigt geplante Verschlüsselung und
# Mapping-Struktur für Transparenz
# =========================================
zeige_luks_plan() {
  header "Geplanter LUKS-Aufbau"

  echo -e "${CYAN}Root-Partition:${NC} ${ROOT_PART}"
  echo -e "${CYAN}Mapper-Name:${NC}    cryptroot"
  echo -e "${CYAN}Root-Gerät:${NC}     /dev/mapper/cryptroot"
  echo

  warn "Dieses Modul richtet nur LUKS ein."
  warn "BTRFS folgt in 03_btrfs.sh."
  echo
}

# =========================================
# 🔐 LUKS sicher einrichten
# -----------------------------------------
# Formatiert und öffnet verschlüsseltes
# Root-Device mit sicherer Übergabe
# =========================================
richte_luks_ein() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde ${ROOT_PART} mit LUKS formatieren"
    warn "[DRY-RUN] würde ${ROOT_PART} als cryptroot öffnen"

    ROOT_DEVICE="/dev/mapper/cryptroot"
    ROOT_BASE_DEVICE="$ROOT_PART"
    ROOT_MAPPER_NAME="cryptroot"

    export ROOT_DEVICE ROOT_BASE_DEVICE ROOT_MAPPER_NAME

    warn "[DRY-RUN] ROOT_DEVICE wäre: ${ROOT_DEVICE}"
    return 0
  fi

  [[ -n "${LUKS_PASSWORD:-}" ]] || {
    error "LUKS_PASSWORD ist leer oder nicht gesetzt."
    exit 1
  }

  log "Formatiere ${ROOT_PART} mit LUKS..."
  cryptsetup luksFormat "$ROOT_PART" --batch-mode --key-file <(printf '%s' "$LUKS_PASSWORD") || {
    error "LUKS-Formatierung fehlgeschlagen."
    unset LUKS_PASSWORD
    exit 1
  }

  log "Öffne LUKS-Container als cryptroot..."
  cryptsetup open "$ROOT_PART" cryptroot --key-file <(printf '%s' "$LUKS_PASSWORD") || {
    error "LUKS konnte nicht geöffnet werden."
    unset LUKS_PASSWORD
    exit 1
  }

  unset LUKS_PASSWORD

  ROOT_DEVICE="/dev/mapper/cryptroot"
  ROOT_BASE_DEVICE="$ROOT_PART"
  ROOT_MAPPER_NAME="cryptroot"

  export ROOT_DEVICE ROOT_BASE_DEVICE ROOT_MAPPER_NAME

  [[ -b "$ROOT_DEVICE" ]] || {
    error "LUKS-Gerät wurde nicht geöffnet: ${ROOT_DEVICE}"
    exit 1
  }

  success "LUKS geöffnet: ${ROOT_DEVICE}"
}
