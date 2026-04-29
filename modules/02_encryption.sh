#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      02_encryption.sh
# Zweck:     Root-Verschlüsselung vorbereiten
#
# Aufgabe:
# - aktiviert optional LUKS2
# - öffnet cryptroot
# - setzt ROOT_DEVICE für Folgemodule
#
# Wichtig:
# - destruktiv bei LUKS-Formatierung
# - Secrets niemals ausgeben oder loggen
# - falscher Mapper = Boot-Fail
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. Passwörter nie loggen
# 3. LUKS-Header nach Formatierung prüfen
# 4. Mapper nach Öffnen validieren
# =========================================


# =========================================
# 🔐 Verschlüsselung ausführen
# -----------------------------------------
# Setzt unverschlüsseltes oder LUKS-Root
# → definiert ROOT_DEVICE für BTRFS/Boot
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
# 🔒 LUKS-Eingaben prüfen
# -----------------------------------------
# Validiert ROOT_PART und USE_LUKS
# → stoppt vor falschem Root-Device
# =========================================

pruefe_encryption_variablen() {
  [[ -n "${ROOT_PART:-}" ]] || { error "ROOT_PART ist nicht gesetzt."; exit 1; }
  [[ -n "${USE_LUKS:-}" ]] || { error "USE_LUKS ist nicht gesetzt."; exit 1; }

  if [[ "${DRY_RUN:-true}" != true ]]; then
    [[ -b "$ROOT_PART" ]] || { error "$ROOT_PART ist kein gültiges Blockdevice."; exit 1; }
  fi
}

# =========================================
# 📋 LUKS-Plan anzeigen
# -----------------------------------------
# Zeigt Root-Partition und Mapper-Ziel
# → Sichtprüfung vor Verschlüsselung
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
# 🔐 LUKS2 einrichten
# -----------------------------------------
# Formatiert ROOT_PART und öffnet cryptroot
# → destruktiv, bootkritisch, secret-sensibel
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

  printf '%s' "$LUKS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --iter-time 2000 \
    --pbkdf argon2id \
    --batch-mode \
    --key-file - || {
      error "LUKS-Formatierung fehlgeschlagen."
      unset LUKS_PASSWORD
      exit 1
  }

  log "Öffne LUKS-Container als cryptroot..."

  printf '%s' "$LUKS_PASSWORD" | cryptsetup open "$ROOT_PART" cryptroot --key-file - || {
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
