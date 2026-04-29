#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      07_snapshots.sh
# Zweck:     BTRFS Snapshots (Snapper)
#
# Aufgabe:
# - installiert snapper
# - richtet root Snapshot-Konfiguration ein
# - validiert Subvolume Struktur
#
# Wichtig:
# - falsche Snapper Config = kein Recovery
# - falsche Rechte = Snapshots unbrauchbar
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. /mnt muss korrekt gemountet sein
# 2. @snapshots MUSS existieren
# 3. Snapper Config deterministisch
# 4. Rechte strikt setzen
# =========================================


# =========================================
# 🚀 Snapshot Setup orchestrieren
# =========================================

run_snapshot_setup() {
  header "07 - Snapshots"

  pruefe_snapshot_variablen
  zeige_snapshot_plan
  validiere_snapshot_struktur
  installiere_snapper
  konfiguriere_snapper
  validiere_snapper

  success "Snapshots vorbereitet."
}


# =========================================
# 🔒 Variablen prüfen
# =========================================

pruefe_snapshot_variablen() {
  guard_require_var ROOT_DEVICE

  if [[ "${DRY_RUN:-true}" != true ]]; then
    guard_mnt_mounted
  fi
}


# =========================================
# 📋 Plan anzeigen
# =========================================

zeige_snapshot_plan() {
  header "Geplanter Snapshot-Aufbau"

  echo "Tool: snapper"
  echo "Konfiguration: root → /"
  echo
}


# =========================================
# 🔍 Snapshot-Struktur validieren
# -----------------------------------------
# Stellt sicher, dass Subvolume korrekt
# gemountet und nutzbar ist
# =========================================

validiere_snapshot_struktur() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    return 0
  fi

  # .snapshots muss existieren
  [[ -d /mnt/.snapshots ]] || {
    error "/mnt/.snapshots existiert nicht"
    exit 1
  }

  # Muss BTRFS sein
  findmnt -n -o FSTYPE /mnt/.snapshots | grep -qx "btrfs" || {
    error "/mnt/.snapshots ist kein BTRFS"
    exit 1
  }

  # Muss korrektes Subvolume sein
  findmnt -n -o OPTIONS /mnt/.snapshots | grep -q "subvol=@snapshots" || {
    error "@snapshots Subvolume nicht korrekt gemountet"
    exit 1
  }
}


# =========================================
# 📦 Snapper installieren
# =========================================

installiere_snapper() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde snapper installieren"
    return 0
  fi

  run_cmd arch-chroot /mnt pacman -S --noconfirm snapper
}


# =========================================
# ⚙️ Snapper konfigurieren
# -----------------------------------------
# Erstellt saubere Root-Config
# =========================================

konfiguriere_snapper() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde snapper konfigurieren"
    return 0
  fi

  local config_dir="/mnt/etc/snapper/configs"
  local config_file="${config_dir}/root"

  mkdir -p "$config_dir"
  mkdir -p /mnt/.snapshots

  # Wenn bereits vorhanden → NICHT überschreiben
  if [[ -f "$config_file" ]]; then
    warn "Snapper Config existiert bereits"
  else
    cat > "$config_file" <<'EOF'
SUBVOLUME="/"
FSTYPE="btrfs"
ALLOW_USERS=""
ALLOW_GROUPS="wheel"
SYNC_ACL="yes"

TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"

NUMBER_CLEANUP="yes"

EMPTY_PRE_POST_CLEANUP="yes"
EOF
  fi

  # Snapper aktivieren
  mkdir -p /mnt/etc/conf.d
  echo 'SNAPPER_CONFIGS="root"' > /mnt/etc/conf.d/snapper

  # Rechte setzen (CRITICAL)
  arch-chroot /mnt chown root:wheel /.snapshots
  chmod 750 /mnt/.snapshots
}


# =========================================
# 🔥 Snapper Setup validieren
# -----------------------------------------
# Stellt sicher, dass Snapper korrekt
# funktioniert und nutzbar ist
# =========================================

validiere_snapper() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    return 0
  fi

  local config="/mnt/etc/snapper/configs/root"

  [[ -f "$config" ]] || {
    error "Snapper Config fehlt"
    exit 1
  }

  # Snapper Testlauf
  arch-chroot /mnt snapper -c root list >/dev/null 2>&1 || {
    error "Snapper funktioniert nicht korrekt"
    exit 1
  }

  success "Snapper validiert."
}
