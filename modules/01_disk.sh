#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      01_disk.sh
# Zweck:     Laufwerksvorbereitung
#
# Aufgabe:
# - löscht vorhandene Daten
# - erstellt Partitionstabelle
# - erzeugt EFI + Root Partition
#
# Wichtig:
# - HOCH DESTRUKTIV
# - falsches Device = Datenverlust
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN zwingend für alle Aktionen
# 2. IMMER Bestätigung vor wipe
# 3. Nur validierte Blockdevices nutzen
# 4. Keine impliziten Device-Namen (/dev/sdX)
# =========================================

# =========================================
# 💣 Disk-Setup orchestrieren
# -----------------------------------------
# Führt alle Schritte zur sicheren
# Laufwerksvorbereitung aus
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

# =========================================
# 🔗 Stabile Device-Pfade ermitteln
# -----------------------------------------
# Findet persistenten /dev/disk/by-id Pfad
# zur Vermeidung von Device-Race-Conditions
# =========================================

disk_by_id_path() {
  local disk="$1"
  local candidate

  for candidate in /dev/disk/by-id/*; do
    [[ -e "$candidate" ]] || continue

    if [[ "$(readlink -f "$candidate")" == "$disk" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

# =========================================
# 🔒 Disk-Sicherheitsprüfungen durchführen
# -----------------------------------------
# Validiert Zielgerät, Profil und schützt
# vor laufenden oder gemounteten Devices
# =========================================

pruefe_disk_variablen() {
  guard_require_var DISK
  guard_require_var INSTALL_PROFILE

  DISK="$(readlink -f "$DISK")"
  export DISK

  guard_block_device "$DISK"
  guard_not_system_disk "$DISK"
  guard_not_mounted "$DISK"

  case "$INSTALL_PROFILE" in
    standard|luks)
      ;;
    *)
      error "Unbekanntes Installationsprofil: $INSTALL_PROFILE"
      exit 1
      ;;
  esac

  local disk_id
  disk_id="$(disk_by_id_path "$DISK" || true)"

  if [[ -n "$disk_id" ]]; then
    DISK_BY_ID="$disk_id"
    export DISK_BY_ID
    success "Stabiler Gerätepfad: $DISK_BY_ID"
  else
    warn "Kein stabiler /dev/disk/by-id Pfad gefunden für $DISK."
  fi
}

# =========================================
# 📋 Disk-Layout anzeigen
# -----------------------------------------
# Zeigt geplante Partitionierung und
# aktuellen Laufwerkszustand an
# =========================================

zeige_disk_plan() {
  header "Geplanter Laufwerksaufbau"

  echo -e "${CYAN}Ziellaufwerk:${NC} ${DISK}"
  [[ -n "${DISK_BY_ID:-}" ]] && echo -e "${CYAN}Stabiler Pfad:${NC} ${DISK_BY_ID}"
  echo -e "${CYAN}Profil:${NC} ${INSTALL_PROFILE}"
  echo
  echo "Geplant:"
  echo "  1. EFI  - ca. 1 GiB - FAT32 - später /boot"
  echo "  2. ROOT - Rest       - später BTRFS"
  echo

  warn "Dieses Modul ist destruktiv."
  warn "LUKS folgt in 02_encryption.sh."
  warn "BTRFS folgt in 03_btrfs.sh."
  echo

  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL "$DISK" || true
  echo
}

# =========================================
# ⚠️ Destruktive Disk-Aktion bestätigen
# -----------------------------------------
# Erzwingt explizite Bestätigung bevor
# Daten unwiderruflich gelöscht werden
# =========================================

bestaetige_disk_zerstoererisch() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] Keine Änderungen werden geschrieben."
    return 0
  fi

  echo -e "${RED}${BOLD}"
  echo "WARNUNG: ALLE DATEN AUF ${DISK} WERDEN GELÖSCHT!"
  [[ -n "${DISK_BY_ID:-}" ]] && echo "Stabiler Pfad: ${DISK_BY_ID}"
  echo "Dies kann NICHT rückgängig gemacht werden."
  echo -e "${NC}"

  local confirm_disk
  local confirm_phrase

  read -rp "$(echo -e "${BLUE}[INPUT]${NC} Tippe exakt '${DISK}' ein: ")" confirm_disk
  [[ "$confirm_disk" == "$DISK" ]] || {
    error "Device-Bestätigung falsch. Abbruch."
    exit 1
  }

  read -rp "$(echo -e "${BLUE}[INPUT]${NC} Tippe exakt 'ALLE DATEN LÖSCHEN': ")" confirm_phrase
  [[ "$confirm_phrase" == "ALLE DATEN LÖSCHEN" ]] || {
    error "Löschbestätigung falsch. Abbruch."
    exit 1
  }
}

# =========================================
# 💽 Disk partitionieren
# -----------------------------------------
# Erstellt GPT, EFI- und Root-Partition
# nach validiertem Installationsplan
# =========================================

partitioniere_disk() {
  header "Partitionierung"

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Partitionstabelle auf ${DISK} löschen"
    warn "[DRY-RUN] würde EFI-Partition erstellen: 1 GiB"
    warn "[DRY-RUN] würde ROOT-Partition erstellen: Rest des Laufwerks"
    return 0
  fi

  guard_block_device "$DISK"
  guard_not_system_disk "$DISK"
  guard_not_mounted "$DISK"

  local gpt_backup="/tmp/$(basename "$DISK").gpt.backup"

  log "Sichere vorhandene GPT, falls vorhanden..."
  sgdisk --backup="$gpt_backup" "$DISK" 2>/dev/null || warn "GPT-Backup nicht möglich oder nicht vorhanden."

  log "Lösche alte Signaturen auf ${DISK}..."
  run_cmd wipefs -af "$DISK"

  log "Erstelle neue GPT-Partitionstabelle..."
  run_cmd parted -s "$DISK" mklabel gpt

  log "Erstelle EFI-Partition..."
  run_cmd parted -s "$DISK" mkpart ESP fat32 1MiB 1025MiB
  run_cmd parted -s "$DISK" set 1 esp on
  run_cmd parted -s "$DISK" set 1 boot on

  log "Erstelle ROOT-Partition..."
  run_cmd parted -s "$DISK" mkpart ROOT 1025MiB 100%

  log "Informiere Kernel über neue Partitionen..."
  run_cmd partprobe "$DISK"
  run_cmd udevadm settle

  success "Partitionierung abgeschlossen."
}

# =========================================
# 🔍 Partitionen ermitteln
# -----------------------------------------
# Leitet EFI- und Root-Partition aus
# dem gewählten Zielgerät ab
# =========================================

ermittle_partitionen() {
  case "$DISK" in
    *nvme*|*mmcblk*)
      EFI_PART="${DISK}p1"
      ROOT_PART="${DISK}p2"
      ;;
    *)
      EFI_PART="${DISK}1"
      ROOT_PART="${DISK}2"
      ;;
  esac

  export EFI_PART ROOT_PART

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] EFI_PART wäre: ${EFI_PART}"
    warn "[DRY-RUN] ROOT_PART wäre: ${ROOT_PART}"
    return 0
  fi

  guard_block_device "$EFI_PART"
  guard_block_device "$ROOT_PART"

  success "EFI-Partition: ${EFI_PART}"
  success "ROOT-Partition: ${ROOT_PART}"
}

# =========================================
# 🧹 EFI-Partition formatieren
# -----------------------------------------
# Formatiert die EFI-Systempartition
# als FAT32 für UEFI-Boot
# =========================================

formatiere_efi() {
  header "EFI formatieren"

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde ${EFI_PART} als FAT32 formatieren"
    return 0
  fi

  guard_block_device "$EFI_PART"

  if blkid "$EFI_PART" | grep -qi 'TYPE="vfat"'; then
    warn "EFI-Partition ist bereits FAT32/vfat formatiert, überspringe."
    return 0
  fi

  run_cmd mkfs.fat -F32 -n EFI "$EFI_PART"

  success "EFI-Partition formatiert: ${EFI_PART}"
}
