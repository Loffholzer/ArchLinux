#!/usr/bin/env bash

# =========================================
# 📦 Guard & Runtime Helper Bibliothek
# -----------------------------------------
# Name:      guard.sh
# Zweck:     Sicherheits- und Ausführungs-Helper
#
# Aufgabe:
# - validiert Pflichtvariablen
# - prüft Blockdevices und Mountpoints
# - schützt kritische Operationen
# - kapselt sichere Befehlsausführung
#
# Wichtig:
# - KEINE destruktiven Aktionen direkt
# - nur Schutzlogik und zentrale Wrapper
# =========================================


# =========================================
# 🔒 Pflichtvariable prüfen
# -----------------------------------------
# Bricht ab wenn Variable fehlt oder leer ist
# =========================================

guard_require_var() {
  local name="$1"

  [[ -n "${!name:-}" ]] || {
    error "Pflichtvariable fehlt: $name"
    exit 1
  }
}


# =========================================
# 💽 Blockdevice validieren
# -----------------------------------------
# Stellt sicher, dass Device existiert
# =========================================

guard_block_device() {
  local dev="$1"

  [[ -b "$dev" ]] || {
    error "Kein gültiges Blockdevice: $dev"
    exit 1
  }
}


# =========================================
# ⚠️ Device darf nicht gemountet sein
# -----------------------------------------
# Verhindert Änderungen an aktiven Mounts
# =========================================

guard_not_mounted() {
  local dev="$1"

  if lsblk -no MOUNTPOINTS "$dev" | grep -q '/'; then
    error "Device oder Partition ist gemountet: $dev"
    exit 1
  fi
}


# =========================================
# 💣 Systemdisk schützen
# -----------------------------------------
# Verhindert Wipe des laufenden Systems
# =========================================

guard_not_system_disk() {
  local dev="$1"
  local root_source
  local root_parent

  root_source="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  [[ -n "$root_source" ]] || return 0

  root_parent="$(lsblk -no PKNAME "$root_source" 2>/dev/null | head -n1 || true)"
  [[ -n "$root_parent" ]] || return 0

  root_parent="/dev/${root_parent}"

  if [[ "$root_parent" == "$dev" ]]; then
    error "ABBRUCH: $dev enthält das laufende Root-System."
    exit 1
  fi
}


# =========================================
# ⚠️ /mnt muss gemountet sein
# -----------------------------------------
# Validiert Zielsystem-Mountpoint
# =========================================

guard_mnt_mounted() {
  mountpoint -q /mnt || {
    error "/mnt ist nicht gemountet."
    exit 1
  }
}


# =========================================
# 🔍 Mountpoint Quelle prüfen
# -----------------------------------------
# Verhindert falsches /mnt Target
# =========================================

guard_mountpoint_source() {
  local mountpoint_path="$1"
  local expected_source="$2"
  local actual_source

  mountpoint -q "$mountpoint_path" || {
    error "$mountpoint_path ist nicht gemountet."
    exit 1
  }

  actual_source="$(findmnt -n -o SOURCE "$mountpoint_path" 2>/dev/null || true)"

  [[ "$actual_source" == "$expected_source" ]] || {
    error "$mountpoint_path zeigt auf $actual_source statt $expected_source"
    exit 1
  }
}


# =========================================
# 🧪 Sicherer Command Runner
# -----------------------------------------
# Führt Befehle nur bei DRY_RUN=false aus
# =========================================

run_cmd() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] $*"
    return 0
  fi

  "$@" || {
    error "Befehl fehlgeschlagen: $*"
    exit 1
  }
}
