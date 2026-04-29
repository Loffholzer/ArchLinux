#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Controller
# -----------------------------------------
# Name:      install.sh
# Zweck:     Installationspipeline steuern
#
# Aufgabe:
# - lädt Bibliotheken und Konfiguration
# - führt Module in fester Reihenfolge aus
# - schreibt State und Audit-Log
#
# Wichtig:
# - keine Installationslogik im Controller
# - Fehler müssen zentral abbrechen
# - Cleanup darf keine fremden Ressourcen zerstören
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN global respektieren
# 2. Module isoliert ausführen
# 3. State-Tracking bei jedem Modul
# 4. Cleanup defensiv halten
# 5. Keine destruktive Logik im Controller
# =========================================

set -euo pipefail

# =========================================
# ⚙️ Globale Flags setzen
# -----------------------------------------
# Definiert DRY_RUN, AUTO_MODE und ALLOW_EXEC
# → steuert Sicherheitsmodus aller Module
# =========================================

DRY_RUN=false
AUTO_MODE=false
ALLOW_EXEC=false

# =========================================
# 📁 Projektpfade bestimmen
# -----------------------------------------
# Ermittelt Script- und Modulverzeichnis
# → macht Aufrufpfad unabhängig
# =========================================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$SCRIPT_DIR/modules"

export DRY_RUN AUTO_MODE ALLOW_EXEC SCRIPT_DIR MODULE_DIR

# =========================================
# 📦 Bibliotheken laden
# -----------------------------------------
# Lädt UI- und Guard-Helfer
# → Voraussetzung für Logging und Checks
# =========================================

source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/guard.sh"

# =========================================
# 📦 Config-Modul laden
# -----------------------------------------
# Lädt Eingabe- und Hardware-Erkennung
# → stellt Konfigurationsfunktionen bereit
# =========================================

source "$MODULE_DIR/00_config.sh"

# =========================================
# 🧱 Runtime initialisieren
# -----------------------------------------
# Erstellt Run-, State- und Log-Dateien
# → Grundlage für Audit und Recovery
# =========================================

init_runtime() {
  RUN_DIR="/tmp/arch-installer"
  STATE_FILE="${RUN_DIR}/state"
  LOG_FILE="${RUN_DIR}/install.log"

  install -d -m 700 "$RUN_DIR"

  if [[ ! -f "$LOG_FILE" ]]; then
    install -m 600 /dev/null "$LOG_FILE"
  else
    chmod 600 "$LOG_FILE"
  fi

  export RUN_DIR STATE_FILE LOG_FILE
}

# =========================================
# 🧾 Audit-Log schreiben
# -----------------------------------------
# Schreibt Zeitstempel ins Logfile
# → ermöglicht Fehleranalyse nach Abbruch
# =========================================

log_to_file() {
  local msg="$1"

  [[ -n "${LOG_FILE:-}" ]] || return 0

  printf '[%s] %s\n' "$(date -Is)" "$msg" >> "$LOG_FILE"
}

# =========================================
# 🔁 State setzen
# -----------------------------------------
# Speichert aktuellen Installationsstatus
# → macht Fortschritt nachvollziehbar
# =========================================

set_state() {
  local state="$1"
  local tmp_state

  [[ -n "${STATE_FILE:-}" ]] || {
    error "STATE_FILE ist nicht gesetzt."
    exit 1
  }

  [[ -d "$(dirname "$STATE_FILE")" ]] || {
    error "State-Verzeichnis existiert nicht: $(dirname "$STATE_FILE")"
    exit 1
  }

  tmp_state="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"

  printf '%s\n' "$state" > "$tmp_state"
  chmod 600 "$tmp_state"
  mv -f "$tmp_state" "$STATE_FILE"

  log "Installationsstatus: $state"
  log_to_file "STATE ${state}"
}

# =========================================
# 🔎 State lesen
# -----------------------------------------
# Gibt zuletzt gespeicherten Status aus
# → Vorbereitung für spätere Resume-Logik
# =========================================

get_state() {
  [[ -f "${STATE_FILE:-}" ]] || return 0
  cat "$STATE_FILE"
}

# =========================================
# 🧹 Sicheres Unmount
# -----------------------------------------
# Unmountet nur Installer-eigene Mounts
# → verhindert Eingriff in fremde Systeme
# =========================================

safe_umount() {
  local target="$1"
  local actual_source
  local expected_sources=()

  mountpoint -q "$target" || return 0

  actual_source="$(findmnt -n -o SOURCE "$target" 2>/dev/null || true)"

  [[ -n "$actual_source" ]] || {
    warn "Mountquelle unbekannt: $target"
    return 0
  }

  [[ -n "${ROOT_DEVICE:-}" ]] && expected_sources+=("$ROOT_DEVICE")
  [[ -n "${EFI_PART:-}" ]] && expected_sources+=("$EFI_PART")

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    expected_sources+=("/dev/mapper/${ROOT_MAPPER_NAME}")
  fi

  local expected
  for expected in "${expected_sources[@]}"; do
    if [[ "$actual_source" == "$expected" || "$actual_source" == "$expected["* ]]; then
      umount "$target" || warn "Konnte $target nicht unmounten."
      return 0
    fi
  done

  warn "Überspringe fremden Mount: $target ($actual_source)"
}

# =========================================
# 🧹 Cleanup ausführen
# -----------------------------------------
# Räumt /mnt und cryptroot defensiv auf
# → verhindert hängende Mounts/Mapper
# =========================================

cleanup() {
  warn "Cleanup läuft..."
  log_to_file "CLEANUP start"

  safe_umount /mnt/.snapshots
  safe_umount /mnt/home
  safe_umount /mnt/boot
  safe_umount /mnt

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    if cryptsetup status "$ROOT_MAPPER_NAME" >/dev/null 2>&1; then
      cryptsetup close "$ROOT_MAPPER_NAME" || warn "Konnte LUKS-Mapper nicht schließen: ${ROOT_MAPPER_NAME}"
    fi
  fi

  log_to_file "CLEANUP done"
}

trap cleanup EXIT

# =========================================
# 🔎 Modulstatus prüfen
# -----------------------------------------
# Prüft persistente Done-Marker pro Modul
# → verhindert gefährliches erneutes Ausführen
# =========================================

module_done() {
  local module="$1"
  local marker="${RUN_DIR}/modules/${module}.done"

  [[ -f "$marker" ]]
}

# =========================================
# ✅ Modul als erledigt markieren
# -----------------------------------------
# Schreibt atomaren Done-Marker pro Modul
# → ermöglicht sicheres Resume ohne Re-Run
# =========================================

mark_module_done() {
  local module="$1"
  local marker_dir="${RUN_DIR}/modules"
  local marker="${marker_dir}/${module}.done"
  local tmp_marker

  install -d -m 700 "$marker_dir"

  tmp_marker="$(mktemp "${marker}.tmp.XXXXXX")"
  printf '%s\n' "$(date -Is)" > "$tmp_marker"
  chmod 600 "$tmp_marker"
  mv -f "$tmp_marker" "$marker"
}

# =========================================
# ▶ Modul ausführen
# -----------------------------------------
# Lädt Modul, prüft Funktion und trackt State
# → verhindert Re-Run bereits erledigter Module
# =========================================

run_module() {
  local module="$1"
  local function_name="$2"
  local path="${MODULE_DIR}/${module}"

  header "Modul: ${module}"
  log_to_file "START module=${module} function=${function_name}"

  if [[ ! -f "$path" ]]; then
    error "Modul nicht gefunden: ${module}"
    log_to_file "ERROR module missing: ${module}"
    exit 1
  fi

  if module_done "$module"; then
    success "Überspringe ${module} (bereits erledigt)"
    log_to_file "SKIP module=${module}"
    return 0
  fi

  unset -f "$function_name" 2>/dev/null || true

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] Modul wird im Testmodus ausgeführt: ${module}"
  fi

  source "$path"

  if ! declare -F "$function_name" >/dev/null; then
    error "Funktion nicht gefunden: ${function_name}"
    log_to_file "ERROR function missing: ${function_name}"
    exit 1
  fi

  set_state "running:${module}"

  if ! "$function_name"; then
    set_state "failed:${module}"
    log_to_file "FAILED module=${module}"
    error "Modul fehlgeschlagen: ${module}"
    exit 1
  fi

  mark_module_done "$module"
  set_state "done:${module}"
  log_to_file "DONE module=${module}"
}

# =========================================
# 🚀 Installationspipeline ausführen
# -----------------------------------------
# Führt Module in definierter Reihenfolge aus
# → bestimmt reproduzierbaren Installationsablauf
# =========================================

run_install() {
  run_module "01_disk.sh" "run_disk_setup"
  run_module "02_encryption.sh" "run_encryption_setup"
  run_module "03_btrfs.sh" "run_btrfs_setup"
  run_module "04_base.sh" "run_base_install"
  run_module "05_system.sh" "run_system_config"
  run_module "06_perf.sh" "run_perf_setup"
  run_module "07_snapshots.sh" "run_snapshot_setup"
  run_module "08_bootloader.sh" "run_bootloader_setup"

  run_module "09_user.sh" "run_user_setup"
  run_module "10_snapshot_boot.sh" "run_snapshot_boot_setup"
  run_module "15_network.sh" "run_network_setup"

  [[ "$INSTALL_SHELL" == "yes" ]]  && run_module "11_shell.sh" "run_shell_setup"
  [[ "$INSTALL_TOOLS" == "yes" ]]  && run_module "12_tools.sh" "run_tools_setup"
  [[ "$INSTALL_AUR" == "yes" ]]    && run_module "13_aur.sh" "run_aur_setup"
  [[ "$INSTALL_EDITOR" == "yes" ]] && run_module "14_editor.sh" "run_editor_setup"

  run_module "99_finalize.sh" "run_finalize"

  run_final_hardening
}

# =========================================
# 🔐 Finales Hardening ausführen
# -----------------------------------------
# Entfernt temporäre Installer-Sudo-Rechte
# → verhindert dauerhaftes NOPASSWD-Sudo
# =========================================

run_final_hardening() {
  header "Sicherheit finalisieren"

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde temporäre Sudo-Rechte entfernen: /mnt/etc/sudoers.d/10-installer"
    return 0
  fi

  if [[ -f "/mnt/etc/sudoers.d/10-installer" ]]; then
    rm -f "/mnt/etc/sudoers.d/10-installer"
    success "Temporäre Sudo-Rechte entfernt."
  else
    log "Keine temporären Sudo-Rechte gefunden."
  fi
}

# =========================================
# 🔒 Installer-Lock setzen
# -----------------------------------------
# Verhindert parallele Installer-Läufe
# → schützt vor Race Conditions und State-Korruption
# =========================================

acquire_lock() {
  LOCK_FILE="/tmp/arch-installer.lock"

  exec 9>"$LOCK_FILE" || {
    error "Lock-Datei konnte nicht geöffnet werden: $LOCK_FILE"
    exit 1
  }

  if ! flock -n 9; then
    error "Installer läuft bereits. Parallelbetrieb ist unsicher."
    exit 1
  fi

  export LOCK_FILE
}

# =========================================
# 🧪 Preflight Checks
# -----------------------------------------
# Prüft kritische Voraussetzungen vor Start
# → verhindert halbfertige Installationen
# =========================================

preflight_checks() {
  log "Preflight Checks..."

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] überspringe Preflight Checks"
    return 0
  fi

  # Internet prüfen
  ping -c 1 -W 3 archlinux.org >/dev/null 2>&1 || {
    error "Kein Internet oder archlinux.org nicht erreichbar."
    exit 1
  }

  # Zeit synchronisieren (wichtig für pacman + TLS)
  timedatectl set-ntp true >/dev/null 2>&1 || {
    warn "Konnte NTP nicht aktivieren."
  }

  # Pacman Keyring aktualisieren
  pacman -Sy --noconfirm archlinux-keyring >/dev/null 2>&1 || {
    error "Keyring konnte nicht aktualisiert werden."
    exit 1
  }

  success "Preflight Checks bestanden."
}

# =========================================
# ⚙️ Runtime-Modus setzen
# -----------------------------------------
# Nutzt DRY_RUN aus install.sh als feste Vorgabe
# → finaler Installer läuft ohne Parameter produktiv
# =========================================

parse_runtime_flags() {
  AUTO_MODE=false

  if [[ "$#" -gt 0 ]]; then
    error "Parameter werden nicht unterstützt."
    error "DRY_RUN wird direkt in install.sh gesetzt."
    exit 1
  fi

  if [[ "${DRY_RUN:-false}" == true ]]; then
    ALLOW_EXEC=false
  else
    ALLOW_EXEC=true
  fi

  export DRY_RUN AUTO_MODE ALLOW_EXEC
}

# =========================================
# 🧠 Einstiegspunkt ausführen
# -----------------------------------------
# Initialisiert Runtime, Config und Pipeline
# → startet kontrollierte Installation
# =========================================

main() {
  parse_runtime_flags "$@"
  acquire_lock
  init_runtime

  preflight_checks

  collect_config
  validate_config
  export_config
  confirm_config

  run_install

  set_state "done:install"
  success "Fertig."
}

main "$@"
