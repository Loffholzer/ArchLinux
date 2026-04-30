#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      07_snapshots.sh
# Zweck:     Snapper-Recovery vorbereiten
#
# Aufgabe:
# - installiert Snapper
# - konfiguriert Root-Snapshots
# - validiert @snapshots-Struktur
#
# Wichtig:
# - falsche Config = kein Recovery
# - falsche Rechte = unbrauchbare Snapshots
# - fehlendes @snapshots bricht Snapshot-Boot
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. /mnt und @snapshots validieren
# 3. Snapper deterministisch konfigurieren
# 4. Rechte strikt setzen
# =========================================

# =========================================
# 🚀 Snapshot-Setup ausführen
# -----------------------------------------
# Installiert, konfiguriert und validiert Snapper
# → Grundlage für Recovery und Snapshot-Boot
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
# 🔒 Snapshot-Eingaben prüfen
# -----------------------------------------
# Validiert ROOT_DEVICE und /mnt
# → stoppt vor falschem Snapshot-Ziel
# =========================================

pruefe_snapshot_variablen() {
  guard_require_var ROOT_DEVICE

  if [[ "${DRY_RUN:-true}" != true ]]; then
    guard_mnt_valid_root
  fi
}

# =========================================
# 📋 Snapshot-Plan anzeigen
# -----------------------------------------
# Zeigt geplante Snapper-Konfiguration
# → Sichtprüfung vor Recovery-Setup
# =========================================

zeige_snapshot_plan() {
  header "Geplanter Snapshot-Aufbau"

  echo "Tool: snapper"
  echo "Konfiguration: root → /"
  echo
}

# =========================================
# 🔍 Snapshot-Struktur prüfen
# -----------------------------------------
# Validiert /.snapshots als BTRFS-Subvolume
# → verhindert defektes Recovery-Layout
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
# -----------------------------------------
# Installiert Snapshot-Werkzeug ins Zielsystem
# → Voraussetzung für Recovery-Snapshots
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
# Schreibt Root-Snapshot-Konfiguration
# → falsche Config macht Recovery nutzlos
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

  if [[ ! -f "$config_file" ]]; then
    run_cmd arch-chroot /mnt snapper -c root create-config /
  fi

  [[ -f "$config_file" ]] || {
    error "Snapper Config konnte nicht erstellt werden"
    exit 1
  }

  sed -i 's/^ALLOW_GROUPS=.*/ALLOW_GROUPS="wheel"/' "$config_file"
  sed -i 's/^SYNC_ACL=.*/SYNC_ACL="yes"/' "$config_file"
  sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/' "$config_file"
  sed -i 's/^TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="yes"/' "$config_file"
  sed -i 's/^NUMBER_CLEANUP=.*/NUMBER_CLEANUP="yes"/' "$config_file"
  sed -i 's/^EMPTY_PRE_POST_CLEANUP=.*/EMPTY_PRE_POST_CLEANUP="yes"/' "$config_file"

  mkdir -p /mnt/etc/conf.d
  echo 'SNAPPER_CONFIGS="root"' > /mnt/etc/conf.d/snapper

  arch-chroot /mnt chown root:wheel /.snapshots
  chmod 750 /mnt/.snapshots
}

# =========================================
# 🔥 Snapper validieren
# -----------------------------------------
# Prüft Config und Snapper-Ausführbarkeit
# → stoppt bei defektem Recovery-Setup
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

  grep -q '^SUBVOLUME="/"$' "$config" || {
    error "Snapper SUBVOLUME ist nicht korrekt"
    exit 1
  }

  grep -q '^ALLOW_GROUPS="wheel"$' "$config" || {
    error "Snapper ALLOW_GROUPS ist nicht korrekt"
    exit 1
  }

  arch-chroot /mnt snapper -c root list >/dev/null 2>&1 || {
    error "Snapper funktioniert nicht korrekt"
    exit 1
  }

  success "Snapper validiert."
}
