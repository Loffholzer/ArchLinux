#!/usr/bin/env bash

# =========================================
# 03_btrfs.sh
# -----------------------------------------
# Aufgabe:
# - erstellt BTRFS auf ROOT_DEVICE
# - legt Subvolumes an
# - mountet Struktur nach /mnt
#
# Wichtig:
# - nutzt ROOT_DEVICE (von 02)
# - erkennt SSD/HDD dynamisch für Mountoptionen
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

# =========================
# 🔒 Checks
# =========================

pruefe_btrfs_variablen() {
  [[ -n "${ROOT_DEVICE:-}" ]] || { error "ROOT_DEVICE fehlt."; exit 1; }

  if [[ "${DRY_RUN:-true}" != true ]]; then
    [[ -b "$ROOT_DEVICE" ]] || { error "$ROOT_DEVICE ist kein Blockdevice."; exit 1; }
  fi
}

# =========================
# ⚙️ Mountoptionen
# =========================

is_ssd() {
  local disk_name
  local rota

  [[ -n "${DISK:-}" ]] || return 1

  disk_name="$(basename "$DISK")"
  rota="$(lsblk -dn -o ROTA "/dev/$disk_name" 2>/dev/null || echo 1)"

  [[ "$rota" == "0" ]]
}

setze_btrfs_optionen() {
  BTRFS_OPTS="noatime,compress=zstd,space_cache=v2"

  if is_ssd; then
    BTRFS_OPTS+=",ssd"
  fi

  export BTRFS_OPTS
}

# =========================
# 📋 Plan anzeigen
# =========================

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

# =========================
# 💽 BTRFS erstellen
# =========================

erstelle_btrfs() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde BTRFS auf $ROOT_DEVICE erstellen"
    return 0
  fi

  log "Lösche alte Dateisystemsignaturen auf $ROOT_DEVICE..."
  wipefs -af "$ROOT_DEVICE" || true

  log "Erstelle BTRFS auf $ROOT_DEVICE..."
  mkfs.btrfs -f "$ROOT_DEVICE" || {
    error "BTRFS-Erstellung fehlgeschlagen."
    exit 1
  }
}

# =========================
# 🧩 Subvolumes
# =========================

erstelle_subvolumes() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Subvolumes @, @home, @snapshots erstellen"
    return 0
  fi

  local temp_mount="/mnt/.btrfs-root"

  log "Erstelle Subvolumes..."

  mkdir -p "$temp_mount"

  mount "$ROOT_DEVICE" "$temp_mount" || {
    error "Temporäres Mounten von $ROOT_DEVICE fehlgeschlagen."
    exit 1
  }

  for subvol in @ @home @snapshots; do
    if btrfs subvolume show "${temp_mount}/${subvol}" >/dev/null 2>&1; then
      warn "Subvolume ${subvol} existiert bereits, überspringe."
      continue
    fi

    btrfs subvolume create "${temp_mount}/${subvol}" || {
      error "Subvolume ${subvol} konnte nicht erstellt werden."
      umount "$temp_mount" || true
      exit 1
    }
  done

  umount "$temp_mount" || {
    error "Temporäres Unmounten von $temp_mount fehlgeschlagen."
    exit 1
  }

  rmdir "$temp_mount" 2>/dev/null || true
}

# =========================
# 📂 Mounts
# =========================

mounte_btrfs() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Subvolumes mounten"
    warn "[DRY-RUN] /mnt → @ mit Optionen: $BTRFS_OPTS"
    warn "[DRY-RUN] /mnt/home → @home mit Optionen: $BTRFS_OPTS"
    warn "[DRY-RUN] /mnt/.snapshots → @snapshots mit Optionen: $BTRFS_OPTS"
    return 0
  fi

  log "Mounte Subvolumes..."

  mkdir -p /mnt

  if mountpoint -q /mnt; then
    warn "/mnt ist bereits gemountet, überspringe Root-Mount."
  else
    mount -o "${BTRFS_OPTS},subvol=@" "$ROOT_DEVICE" /mnt || {
      error "Mount von @ nach /mnt fehlgeschlagen."
      exit 1
    }
  fi

  mkdir -p /mnt/home
  mkdir -p /mnt/.snapshots

  if mountpoint -q /mnt/home; then
    warn "/mnt/home ist bereits gemountet, überspringe."
  else
    mount -o "${BTRFS_OPTS},subvol=@home" "$ROOT_DEVICE" /mnt/home || {
      error "Mount von @home fehlgeschlagen."
      exit 1
    }
  fi

  if mountpoint -q /mnt/.snapshots; then
    warn "/mnt/.snapshots ist bereits gemountet, überspringe."
  else
    mount -o "${BTRFS_OPTS},subvol=@snapshots" "$ROOT_DEVICE" /mnt/.snapshots || {
      error "Mount von @snapshots fehlgeschlagen."
      exit 1
    }
  fi
}
