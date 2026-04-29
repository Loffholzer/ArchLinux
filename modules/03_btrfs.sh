#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      03_btrfs.sh
# Zweck:     BTRFS-Dateisystem vorbereiten
#
# Aufgabe:
# - erstellt BTRFS auf ROOT_DEVICE
# - legt Root/Home/Snapshot-Subvolumes an
# - mountet Zielstruktur nach /mnt
#
# Wichtig:
# - destruktiv bei mkfs
# - falscher Mount = Installation ins falsche Ziel
# - Subvolume-Fehler = Boot-/Recovery-Probleme
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. Mounts immer validieren
# 3. Subvolumes vor Nutzung prüfen
# 4. Keine stillen Mount-Abweichungen
# =========================================

# =========================================
# 🧩 BTRFS-Setup ausführen
# -----------------------------------------
# Erstellt Dateisystem, Subvolumes und Mounts
# → bereitet /mnt für pacstrap vor
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
# 🔒 BTRFS-Eingaben prüfen
# -----------------------------------------
# Validiert ROOT_DEVICE
# → stoppt vor falschem Dateisystemziel
# =========================================

pruefe_btrfs_variablen() {
  guard_require_var ROOT_DEVICE

  if [[ "${DRY_RUN:-true}" != true ]]; then
    guard_block_device "$ROOT_DEVICE"
  fi
}

# =========================================
# 💾 SSD erkennen
# -----------------------------------------
# Prüft Rotationsstatus des Zielgeräts
# → steuert SSD-spezifische Mountoptionen
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
# ⚙️ BTRFS-Optionen setzen
# -----------------------------------------
# Definiert deterministische Mountoptionen
# → optimiert Verhalten für SSD/HDD
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
# 📋 BTRFS-Plan anzeigen
# -----------------------------------------
# Zeigt Root-Gerät, Optionen und Subvolumes
# → Sichtprüfung vor mkfs/mount
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
# 💽 BTRFS erstellen
# -----------------------------------------
# Initialisiert ROOT_DEVICE als BTRFS
# → destruktiv bei nicht vorhandenem BTRFS
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
# 🧩 Subvolumes erstellen
# -----------------------------------------
# Legt @, @home und @snapshots an
# → Grundlage für Boot, Home und Recovery
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
# 🔍 Mount-Quelle prüfen
# -----------------------------------------
# Vergleicht Mountpoint mit erwartetem Device
# → verhindert Installation auf falschem Mount
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
# 🧩 Subvolume prüfen
# -----------------------------------------
# Prüft aktives BTRFS-Subvolume am Mountpoint
# → verhindert falsche Root-/Home-Zuordnung
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
# 📂 Subvolumes mounten
# -----------------------------------------
# Mountet @, @home und @snapshots nach /mnt
# → erstellt finale Zielstruktur
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
