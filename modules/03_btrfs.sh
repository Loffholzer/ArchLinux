#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      03_btrfs.sh
# Zweck:     Dateisystem + Subvolumes
#
# Aufgabe:
# - erstellt BTRFS
# - legt Subvolumes an
# - mountet Struktur
#
# Wichtig:
# - falsches Mount = Datenkorruption
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. Mounts IMMER validieren
# 2. Subvolumes prüfen bevor erstellen
# 3. Optionen deterministisch setzen
# 4. Kein stilles Überschreiben
# =========================================

# =========================================
# 🧩 BTRFS-Setup orchestrieren
# -----------------------------------------
# Erstellt Dateisystem, Subvolumes und
# mountet Struktur nach /mnt
# =========================================

run_btrfs_setup() {
  header "03 - BTRFS"

  pruefe_btrfs_variablen
  setze_btrfs_optionen
  zeige_btrfs_plan
  erstelle_btrfs
  erstelle_subvolumes
  mounte_btrfs

  success "BTRFS vorbereitet."
}

# =========================================
# 🔒 BTRFS-Variablen prüfen
# -----------------------------------------
# Validiert Root-Device bevor
# Dateisystemoperationen starten
# =========================================

pruefe_btrfs_variablen() {
  guard_require_var ROOT_DEVICE

  if [[ "${DRY_RUN:-true}" != true ]]; then
    guard_block_device "$ROOT_DEVICE"
  fi
}

# =========================================
# 💾 SSD-Erkennung durchführen
# -----------------------------------------
# Erkennt Rotationsstatus zur Anpassung
# optimaler BTRFS Mount-Optionen
# =========================================

is_ssd() {
  local disk_name
  local rota

  guard_require_var DISK

  disk_name="$(basename "$DISK")"
  rota="$(lsblk -dn -o ROTA "/dev/$disk_name" 2>/dev/null || echo 1)"

  [[ "$rota" == "0" ]]
}

# =========================================
# ⚙️ BTRFS Mount-Optionen setzen
# -----------------------------------------
# Definiert performante und sichere
# Optionen abhängig vom Datenträger
# =========================================

setze_btrfs_optionen() {
  BTRFS_OPTS="noatime,compress=zstd,space_cache=v2"

  if is_ssd; then
    BTRFS_OPTS+=",ssd,discard=async"
    log "SSD erkannt. BTRFS-Optionen auf SSD-Performance optimiert."
  else
    log "HDD erkannt oder ROTA-Check fehlgeschlagen. Nutze Standard-Optionen."
  fi

  export BTRFS_OPTS
}

# =========================================
# 📋 BTRFS-Layout anzeigen
# -----------------------------------------
# Zeigt Subvolume-Struktur und geplante
# Mountpoints für Transparenz
# =========================================

zeige_btrfs_plan() {
  header "Geplanter BTRFS-Aufbau"

  echo -e "${CYAN}Root-Gerät:${NC} $ROOT_DEVICE"
  echo -e "${CYAN}Mountoptionen:${NC} $BTRFS_OPTS"
  echo
  echo "Subvolumes:"
  echo "  @           → /"
  echo "  @home       → /home"
  echo "  @snapshots  → /.snapshots"
  echo
  echo "Mountpunkte:"
  echo "  /mnt              → @"
  echo "  /mnt/home         → @home"
  echo "  /mnt/.snapshots   → @snapshots"
  echo

  warn "Dieses Modul erstellt das Dateisystem und mountet es."
  echo
}

# =========================================
# 💽 BTRFS-Dateisystem erstellen
# -----------------------------------------
# Initialisiert BTRFS auf Root-Device
# nach vorheriger Signaturprüfung
# =========================================

erstelle_btrfs() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde BTRFS auf $ROOT_DEVICE erstellen"
    return 0
  fi

  guard_block_device "$ROOT_DEVICE"

  if blkid "$ROOT_DEVICE" | grep -qi 'TYPE="btrfs"'; then
    warn "BTRFS ist bereits vorhanden, überspringe mkfs."
    return 0
  fi

  log "Lösche alte Dateisystemsignaturen auf $ROOT_DEVICE..."
  run_cmd wipefs -af "$ROOT_DEVICE"

  log "Erstelle BTRFS auf $ROOT_DEVICE..."
  run_cmd mkfs.btrfs -f "$ROOT_DEVICE"
}

# =========================================
# 🧩 BTRFS-Subvolumes erstellen
# -----------------------------------------
# Erstellt strukturierte Subvolumes
# für Root, Home und Snapshots
# =========================================

erstelle_subvolumes() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Subvolumes @, @home, @snapshots erstellen"
    return 0
  fi

  guard_block_device "$ROOT_DEVICE"

  local temp_mount="/mnt/.btrfs-root"

  if mountpoint -q "$temp_mount"; then
    error "Temporärer BTRFS-Mount ist bereits aktiv: $temp_mount"
    exit 1
  fi

  mkdir -p "$temp_mount"

  run_cmd mount "$ROOT_DEVICE" "$temp_mount"

  for subvol in @ @home @snapshots; do
    if btrfs subvolume show "${temp_mount}/${subvol}" >/dev/null 2>&1; then
      warn "Subvolume ${subvol} existiert bereits, überspringe."
      continue
    fi

    run_cmd btrfs subvolume create "${temp_mount}/${subvol}"
  done

  run_cmd umount "$temp_mount"
  rmdir "$temp_mount" 2>/dev/null || true
}

# =========================================
# 🔍 Mount-Quelle validieren
# -----------------------------------------
# Prüft ob Mountpoint vom erwarteten
# Blockdevice stammt (Fehlmontage-Schutz)
# =========================================

validate_mount_source() {
  local mountpoint_path="$1"
  local expected_source="$2"

  mountpoint -q "$mountpoint_path" || {
    error "$mountpoint_path ist nicht gemountet."
    exit 1
  }

  local actual_source
  actual_source="$(findmnt -n -o SOURCE "$mountpoint_path")"

  [[ "$actual_source" == "$expected_source" ]] || {
    error "$mountpoint_path ist falsch gemountet: $actual_source statt $expected_source"
    exit 1
  }
}

# =========================================
# 🧩 BTRFS Subvolume validieren
# -----------------------------------------
# Stellt sicher, dass korrektes Subvolume
# am Mountpoint aktiv ist
# =========================================

validate_btrfs_subvol() {
  local mountpoint_path="$1"
  local expected_subvol="$2"

  local options
  options="$(findmnt -n -o OPTIONS "$mountpoint_path")"

  [[ "$options" == *"subvol=${expected_subvol}"* ]] || {
    error "$mountpoint_path ist nicht mit subvol=${expected_subvol} gemountet."
    exit 1
  }
}

# =========================================
# 📂 BTRFS-Subvolumes mounten
# -----------------------------------------
# Mountet Root, Home und Snapshots mit
# validierten Optionen nach /mnt
# =========================================

mounte_btrfs() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Subvolumes mounten"
    warn "[DRY-RUN] /mnt → @ mit Optionen: $BTRFS_OPTS"
    warn "[DRY-RUN] /mnt/home → @home mit Optionen: $BTRFS_OPTS"
    warn "[DRY-RUN] /mnt/.snapshots → @snapshots mit Optionen: $BTRFS_OPTS"
    return 0
  fi

  guard_block_device "$ROOT_DEVICE"

  log "Mounte Subvolumes..."

  mkdir -p /mnt

  if mountpoint -q /mnt; then
    validate_mount_source /mnt "$ROOT_DEVICE"
    validate_btrfs_subvol /mnt "@"
    warn "/mnt ist bereits korrekt gemountet."
  else
    run_cmd mount -o "${BTRFS_OPTS},subvol=@" "$ROOT_DEVICE" /mnt
  fi

  mkdir -p /mnt/home
  mkdir -p /mnt/.snapshots

  if mountpoint -q /mnt/home; then
    validate_mount_source /mnt/home "$ROOT_DEVICE"
    validate_btrfs_subvol /mnt/home "@home"
    warn "/mnt/home ist bereits korrekt gemountet."
  else
    run_cmd mount -o "${BTRFS_OPTS},subvol=@home" "$ROOT_DEVICE" /mnt/home
  fi

  if mountpoint -q /mnt/.snapshots; then
    validate_mount_source /mnt/.snapshots "$ROOT_DEVICE"
    validate_btrfs_subvol /mnt/.snapshots "@snapshots"
    warn "/mnt/.snapshots ist bereits korrekt gemountet."
  else
    run_cmd mount -o "${BTRFS_OPTS},subvol=@snapshots" "$ROOT_DEVICE" /mnt/.snapshots
  fi
}
