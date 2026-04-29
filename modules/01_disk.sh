#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      01_disk.sh
# Zweck:     Laufwerk vorbereiten
#
# Aufgabe:
# - validiert Zielgerät
# - löscht alte Signaturen
# - erstellt GPT + EFI + Root-Partition
#
# Wichtig:
# - destruktiv
# - falsches Device = Datenverlust
# - Device muss vor jedem Wipe erneut geprüft werden
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. Explizite Löschbestätigung erzwingen
# 3. Nur validierte Blockdevices ändern
# 4. Keine impliziten Device-Annahmen
# =========================================

# =========================================
# 💣 Disk-Setup ausführen
# -----------------------------------------
# Orchestriert Prüfung, Bestätigung,
# Partitionierung und EFI-Formatierung
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
# 🧬 Disk erneut verifizieren
# -----------------------------------------
# Prüft vor destruktiven Aktionen,
# dass DISK unverändert ist
# =========================================

verify_disk_identity() {
  local current

  guard_require_var DISK

  current="$(readlink -f "$DISK")"

  [[ -b "$current" ]] || {
    error "Zielgerät existiert nicht mehr: $DISK"
    exit 1
  }

  [[ "$current" == "$DISK" ]] || {
    error "Device-Pfad hat sich geändert: $DISK → $current"
    exit 1
  }

  if [[ -n "${DISK_BY_ID:-}" ]]; then
    [[ -e "$DISK_BY_ID" ]] || {
      error "Stabiler Device-Pfad existiert nicht mehr: $DISK_BY_ID"
      exit 1
    }

    [[ "$(readlink -f "$DISK_BY_ID")" == "$DISK" ]] || {
      error "Device-Identität stimmt nicht mehr mit DISK_BY_ID überein"
      exit 1
    }
  fi
}

# =========================================
# 🔗 Stabilen Device-Pfad finden
# -----------------------------------------
# Ermittelt /dev/disk/by-id für DISK
# → reduziert Risiko durch Device-Renaming
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
# 🔒 Disk-Eingaben prüfen
# -----------------------------------------
# Validiert Zielgerät, Profil und Mountstatus
# → stoppt bei Systemdisk oder aktivem Mount
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
# 📋 Disk-Plan anzeigen
# -----------------------------------------
# Zeigt Zielgerät und geplantes Layout
# → letzte Sichtprüfung vor Datenverlust
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
# ⚠️ Datenlöschung bestätigen
# -----------------------------------------
# Erzwingt exakte Device- und Löschphrase
# → schützt vor versehentlichem Wipe
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

  read -rp "$(echo -e "${BLUE}[INPUT]${NC} Tippe exakt '${DISK}' ein: ")" confirm_disk
  [[ "$confirm_disk" == "$DISK" ]] || {
    error "Device-Bestätigung falsch. Abbruch."
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
  verify_disk_identity
  run_cmd wipefs -af "$DISK"

  log "Erstelle neue GPT-Partitionstabelle..."
  verify_disk_identity
  run_cmd parted -s "$DISK" mklabel gpt

  log "Erstelle EFI-Partition..."
  verify_disk_identity
  run_cmd parted -s "$DISK" mkpart ESP fat32 1MiB 1025MiB
  verify_disk_identity
  run_cmd parted -s "$DISK" set 1 esp on
  verify_disk_identity
  run_cmd parted -s "$DISK" set 1 boot on

  log "Erstelle ROOT-Partition..."
  verify_disk_identity
  run_cmd parted -s "$DISK" mkpart ROOT 1025MiB 100%

  log "Informiere Kernel über neue Partitionen..."
  verify_disk_identity
  run_cmd partprobe "$DISK"
  verify_disk_identity
  run_cmd udevadm settle

  success "Partitionierung abgeschlossen."
}

# =========================================
# 🔍 Partitionen ableiten
# -----------------------------------------
# Bestimmt EFI_PART und ROOT_PART aus DISK
# → berücksichtigt NVMe/mmcblk Namensschema
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
# 🧹 EFI formatieren
# -----------------------------------------
# Erstellt FAT32-Dateisystem auf EFI_PART
# → Voraussetzung für UEFI-Boot
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


