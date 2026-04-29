#!/usr/bin/env bash

# =========================================
# 📦 Guard & Runtime Helper Bibliothek
# -----------------------------------------
# Name:      guard.sh
# Zweck:     Zentrale Sicherheitsprüfungen
#
# Aufgabe:
# - validiert Pflichtvariablen
# - prüft Blockdevices und Mountpoints
# - verhindert gefährliche Zielzustände
# - kapselt DRY_RUN-sichere Ausführung
#
# Wichtig:
# - keine destruktiven Aktionen direkt
# - Guard-Fehler müssen hart abbrechen
# - falsche Checks können Datenverlust erlauben
# =========================================

# =========================================
# 🔒 Pflichtvariable prüfen
# -----------------------------------------
# Bricht bei leerer Variable ab
# → verhindert undefinierte Modulzustände
# =========================================

guard_require_var() {
  local name="$1"

  [[ -n "${!name:-}" ]] || {
    error "Pflichtvariable fehlt: $name"
    exit 1
  }
}

# =========================================
# 💽 Blockdevice prüfen
# -----------------------------------------
# Validiert vorhandenes Blockgerät
# → stoppt vor falschem Device-Zugriff
# =========================================

guard_block_device() {
  local dev="$1"

  [[ -b "$dev" ]] || {
    error "Kein gültiges Blockdevice: $dev"
    exit 1
  }
}

# =========================================
# ⚠️ Mountstatus prüfen
# -----------------------------------------
# Verhindert Änderungen an gemounteten Devices
# → schützt aktive Dateisysteme
# =========================================

guard_not_mounted() {
  local dev="$1"

  guard_block_device "$dev"

  if findmnt -rn -S "$dev" >/dev/null 2>&1; then
    error "Device ist gemountet: $dev"
    exit 1
  fi

  if lsblk -rn -o NAME,MOUNTPOINTS "$dev" | awk '$2 != "" { found=1 } END { exit !found }'; then
    error "Device oder Partition ist gemountet: $dev"
    exit 1
  fi
}

# =========================================
# 💣 Systemdisk schützen
# -----------------------------------------
# Erkennt Laufwerk des Live-Root-Systems
# → verhindert Wipe des laufenden Systems
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
# ⚠️ /mnt prüfen
# -----------------------------------------
# Erzwingt gemountetes Zielsystem
# → verhindert Installation ins Live-System
# =========================================

guard_mnt_mounted() {
  mountpoint -q /mnt || {
    error "/mnt ist nicht gemountet."
    exit 1
  }
}

# =========================================
# 🔍 Mountquelle prüfen
# -----------------------------------------
# Vergleicht Mountpoint mit erwartetem Device
# → verhindert falsche Ziel-Mounts
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
# 🧪 Befehl sicher ausführen
# -----------------------------------------
# Respektiert DRY_RUN und bricht bei Fehler ab
# → zentraler Wrapper für kritische Commands
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
