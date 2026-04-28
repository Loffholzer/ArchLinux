#!/usr/bin/env bash

# =========================================
# 02_encryption.sh
# -----------------------------------------
# Aufgabe:
# - prüft ob LUKS aktiviert ist
# - verschlüsselt optional ROOT_PART
# - öffnet LUKS als /dev/mapper/cryptroot
# - setzt ROOT_DEVICE für BTRFS
#
# Wichtig:
# - kein BTRFS
# - keine Mounts
# =========================================

# =========================
# 🚀 Verschlüsselung Setup ausführen
# =========================

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

# =========================
# 🔒 Checks
# =========================

pruefe_encryption_variablen() {
  [[ -n "${ROOT_PART:-}" ]] || { error "ROOT_PART ist nicht gesetzt."; exit 1; }
  [[ -n "${USE_LUKS:-}" ]] || { error "USE_LUKS ist nicht gesetzt."; exit 1; }

  if [[ "${DRY_RUN:-true}" != true ]]; then
    [[ -b "$ROOT_PART" ]] || { error "$ROOT_PART ist kein gültiges Blockdevice."; exit 1; }
  fi
}

# =========================
# 📋 Plan anzeigen
# =========================

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

# =========================
# 🔐 LUKS einrichten
# =========================

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
  printf '%s' "$LUKS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" --batch-mode --key-file - || {
    error "LUKS-Formatierung fehlgeschlagen."
    exit 1
  }

  log "Öffne LUKS-Container als cryptroot..."
  printf '%s' "$LUKS_PASSWORD" | cryptsetup open "$ROOT_PART" cryptroot --key-file - || {
    error "LUKS konnte nicht geöffnet werden."
    exit 1
  }

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
