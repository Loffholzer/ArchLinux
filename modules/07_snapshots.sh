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
# Validiert /.snapshots als korrektes BTRFS-Subvolume
# → akzeptiert subvol=@snapshots und subvol=/@snapshots
# → verhindert defektes Recovery-Layout
# =========================================

validiere_snapshot_struktur() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    return 0
  fi

  guard_require_var ROOT_DEVICE
  guard_mnt_valid_root

  [[ -d /mnt/.snapshots ]] || {
    error "/mnt/.snapshots existiert nicht"
    exit 1
  }

  mountpoint -q /mnt/.snapshots || {
    error "/mnt/.snapshots ist kein eigener Mountpoint"
    exit 1
  }

  local fstype
  local source
  local options

  fstype="$(findmnt -n -o FSTYPE /mnt/.snapshots 2>/dev/null || true)"
  source="$(findmnt -n -o SOURCE /mnt/.snapshots 2>/dev/null || true)"
  options="$(findmnt -n -o OPTIONS /mnt/.snapshots 2>/dev/null || true)"

  [[ "$fstype" == "btrfs" ]] || {
    error "/mnt/.snapshots ist kein BTRFS-Dateisystem"
    exit 1
  }

  [[ "$source" == "$ROOT_DEVICE" || "$source" == "$ROOT_DEVICE["* ]] || {
    error "/mnt/.snapshots zeigt auf falsche Quelle: $source statt $ROOT_DEVICE"
    exit 1
  }

  [[ "$options" == *"subvol=@snapshots"* || "$options" == *"subvol=/@snapshots"* ]] || {
    error "@snapshots Subvolume nicht korrekt gemountet"
    error "Aktuelle Mountoptionen: $options"
    exit 1
  }

  success "@snapshots korrekt gemountet."
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
# Schreibt Root-Snapshot-Konfiguration ohne DBus
# → funktioniert zuverlässig im arch-chroot
# → vermeidet snapper create-config Service-Fehler
# =========================================

konfiguriere_snapper() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde snapper ohne DBus konfigurieren"
    return 0
  fi

  local config_dir="/mnt/etc/snapper/configs"
  local config_file="${config_dir}/root"

  guard_mnt_valid_root

  install -d -m 755 "$config_dir"
  install -d -m 750 /mnt/.snapshots

  cat > "$config_file" <<'EOF'
SUBVOLUME="/"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS="wheel"
SYNC_ACL="yes"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="10"
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="10"
TIMELINE_LIMIT_DAILY="10"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="10"
TIMELINE_LIMIT_YEARLY="10"
EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="1800"
EOF

  chmod 640 "$config_file"

  install -d -m 755 /mnt/etc/conf.d
  echo 'SNAPPER_CONFIGS="root"' > /mnt/etc/conf.d/snapper
  chmod 644 /mnt/etc/conf.d/snapper

  arch-chroot /mnt chown root:wheel /.snapshots
  chmod 750 /mnt/.snapshots

  sync -f "$config_file" 2>/dev/null || sync
  sync -f /mnt/etc/conf.d/snapper 2>/dev/null || sync

  success "Snapper root-Konfiguration ohne DBus geschrieben."
}

# =========================================
# 🔥 Snapper validieren
# -----------------------------------------
# Prüft Config ohne DBus-Abhängigkeit
# → stoppt bei defekter Recovery-Konfiguration
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

  grep -q '^FSTYPE="btrfs"$' "$config" || {
    error "Snapper FSTYPE ist nicht korrekt"
    exit 1
  }

  grep -q '^ALLOW_GROUPS="wheel"$' "$config" || {
    error "Snapper ALLOW_GROUPS ist nicht korrekt"
    exit 1
  }

  [[ -d /mnt/.snapshots ]] || {
    error "/mnt/.snapshots fehlt"
    exit 1
  }

  [[ "$(stat -c '%a' /mnt/.snapshots)" == "750" ]] || {
    error "/mnt/.snapshots Rechte falsch"
    exit 1
  }

  success "Snapper validiert."
}
