#!/usr/bin/env bash

# =========================================
# 01_disk.sh
# -----------------------------------------
# Aufgabe:
# - Ziellaufwerk prüfen
# - Benutzer destruktiv bestätigen lassen
# - GPT-Partitionstabelle erstellen
# - EFI-Partition erstellen
# - ROOT-Partition erstellen
# - EFI formatieren
#
# Wichtig:
# - keine LUKS-Einrichtung
# - keine BTRFS-Subvolumes
# - keine Mounts
# =========================================

run_disk_setup() {
  header "01 - Laufwerk vorbereiten"

  pruefe_disk_variablen
  zeige_disk_plan
  bestaetige_disk_zerstoererisch
  partitioniere_disk
  ermittle_partitionen
  formatiere_efi

  success "Laufwerk vorbereitet."
}

# =========================
# 🔒 Checks
# =========================

pruefe_disk_variablen() {
  [[ -n "${DISK:-}" ]] || { error "DISK ist nicht gesetzt."; exit 1; }
  [[ -b "$DISK" ]] || { error "$DISK ist kein gültiges Blockdevice."; exit 1; }

  [[ -n "${INSTALL_PROFILE:-}" ]] || { error "INSTALL_PROFILE ist nicht gesetzt."; exit 1; }

  case "$INSTALL_PROFILE" in
    standard|luks) ;;
    *) error "Unbekanntes Installationsprofil: $INSTALL_PROFILE"; exit 1 ;;
  esac
}

# =========================
# 📋 Plan anzeigen
# =========================

zeige_disk_plan() {
  header "Geplanter Laufwerksaufbau"

  echo -e "${CYAN}Ziellaufwerk:${NC} ${DISK}"
  echo -e "${CYAN}Profil:${NC} ${INSTALL_PROFILE}"
  echo
  echo "Geplant:"
  echo "  1. EFI  - ca. 1 GiB - FAT32 - später /boot"
  echo "  2. ROOT - Rest       - später BTRFS"
  echo

  warn "Dieses Modul bereitet nur Partitionen vor."
  warn "LUKS folgt in 02_encryption.sh."
  warn "BTRFS folgt in 03_btrfs.sh."
  echo

  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$DISK" || true
  echo
}

# =========================
# ⚠️ Destruktive Bestätigung
# =========================

bestaetige_disk_zerstoererisch() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] Keine Änderungen werden geschrieben."
    return 0
  fi

  echo -e "${RED}${BOLD}"
  echo "WARNUNG: ALLE DATEN AUF ${DISK} WERDEN GELÖSCHT!"
  echo "Dies kann NICHT rückgängig gemacht werden."
  echo -e "${NC}"

  local eingabe_ja

  read -rp "$(echo -e "${BLUE}[INPUT]${NC} Tippe 'JA' zum endgültigen Fortfahren: ")" eingabe_ja

  [[ "$eingabe_ja" == "JA" ]] || {
    error "Bestätigung fehlt. Abbruch."
    exit 1
  }
}

# =========================
# 💽 Partitionierung
# =========================

partitioniere_disk() {
  header "Partitionierung"

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Partitionstabelle auf ${DISK} löschen"
    warn "[DRY-RUN] würde EFI-Partition erstellen: 1 GiB"
    warn "[DRY-RUN] würde ROOT-Partition erstellen: Rest des Laufwerks"
    return 0
  fi

  log "Lösche alte Signaturen auf ${DISK}..."
  wipefs -af "$DISK"

  log "Erstelle neue GPT-Partitionstabelle..."
  parted -s "$DISK" mklabel gpt

  log "Erstelle EFI-Partition..."
  parted -s "$DISK" mkpart ESP fat32 1MiB 1025MiB
  parted -s "$DISK" set 1 esp on
  parted -s "$DISK" set 1 boot on

  log "Erstelle ROOT-Partition..."
  parted -s "$DISK" mkpart ROOT 1025MiB 100%

  log "Informiere Kernel über neue Partitionen..."
  partprobe "$DISK"
  udevadm settle

  success "Partitionierung abgeschlossen."
}

# =========================
# 🔍 Partitionen ermitteln
# =========================

ermittle_partitionen() {
  if [[ "$DISK" =~ nvme|mmcblk ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
  else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
  fi

  export EFI_PART ROOT_PART

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] EFI_PART wäre: ${EFI_PART}"
    warn "[DRY-RUN] ROOT_PART wäre: ${ROOT_PART}"
    return 0
  fi

  [[ -b "$EFI_PART" ]] || { error "EFI-Partition nicht gefunden: $EFI_PART"; exit 1; }
  [[ -b "$ROOT_PART" ]] || { error "ROOT-Partition nicht gefunden: $ROOT_PART"; exit 1; }

  success "EFI-Partition: ${EFI_PART}"
  success "ROOT-Partition: ${ROOT_PART}"
}

# =========================
# 🧹 EFI formatieren
# =========================

formatiere_efi() {
  header "EFI formatieren"

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde ${EFI_PART} als FAT32 formatieren"
    return 0
  fi

  mkfs.fat -F32 -n EFI "$EFI_PART" || {
    error "EFI-Formatierung fehlgeschlagen."
    exit 1
  }

  success "EFI-Partition formatiert: ${EFI_PART}"
}
