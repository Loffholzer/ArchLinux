#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Controller
# -----------------------------------------
# Name:      install.sh
# Zweck:     Hauptsteuerung der Installation
#
# Aufgabe:
# - lädt Konfiguration
# - orchestriert alle Module
# - steuert Reihenfolge und Ablauf
#
# Wichtig:
# - enthält KEINE Installationslogik
# - ist deterministisch und reproduzierbar
# - zentrale Fehler- und Ablaufkontrolle
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY-RUN Pflicht für alle Module
# 2. Keine destruktive Logik im Controller
# 3. Module sind isoliert und austauschbar
# 4. Jeder Schritt muss reproduzierbar sein
# 5. Logging + State-Tracking verpflichtend
# =========================================

set -euo pipefail

# =========================================
# ⚙️ Globale Einstellungen
# -----------------------------------------
# Definiert Sicherheitsmodus und AUTO_MODE
# für den gesamten Installationslauf
# =========================================

DRY_RUN=false
AUTO_MODE=false
ALLOW_EXEC=false

# =========================================
# 📁 Pfade bestimmen
# -----------------------------------------
# Ermittelt Script- und Modulverzeichnis
# unabhängig vom aktuellen Arbeitsordner
# =========================================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$SCRIPT_DIR/modules"

export DRY_RUN AUTO_MODE ALLOW_EXEC SCRIPT_DIR MODULE_DIR

# =========================================
# 📦 Bibliotheken laden
# -----------------------------------------
# Lädt UI- und Guard-Funktionen vor
# allen Modulen
# =========================================

source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/guard.sh"

# =========================================
# 📦 Config-Modul laden
# -----------------------------------------
# Lädt Konfigurationslogik und initiale
# Hardware-Erkennung
# =========================================

source "$MODULE_DIR/00_config.sh"

# =========================================
# 🧱 Runtime-Verzeichnis initialisieren
# -----------------------------------------
# Erstellt temporäres Arbeitsverzeichnis
# für Logs und Installationsstatus
# =========================================

init_runtime() {
  RUN_DIR="/tmp/arch-installer"
  STATE_FILE="${RUN_DIR}/state"
  LOG_FILE="${RUN_DIR}/install.log"

  mkdir -p "$RUN_DIR"
  touch "$LOG_FILE"

  export RUN_DIR STATE_FILE LOG_FILE
}

# =========================================
# 🧾 Audit-Log schreiben
# -----------------------------------------
# Schreibt strukturierte Zeitstempel-Logs
# für Debugging und Post-Mortem Analyse
# =========================================

log_to_file() {
  local msg="$1"

  [[ -n "${LOG_FILE:-}" ]] || return 0

  printf '[%s] %s\n' "$(date -Is)" "$msg" >> "$LOG_FILE"
}

# =========================================
# 🔁 Installationsstatus setzen
# -----------------------------------------
# Speichert aktuellen Fortschritt für
# Resume / Recovery Szenarien
# =========================================

set_state() {
  local state="$1"

  [[ -n "${STATE_FILE:-}" ]] || {
    error "STATE_FILE ist nicht gesetzt."
    exit 1
  }

  echo "$state" > "$STATE_FILE"
  log "Installationsstatus: $state"
  log_to_file "STATE ${state}"
}

# =========================================
# 🔎 Installationsstatus lesen
# -----------------------------------------
# Liefert zuletzt gespeicherten Status
# für Wiederaufnahme der Installation
# =========================================

get_state() {
  [[ -f "${STATE_FILE:-}" ]] || return 0
  cat "$STATE_FILE"
}

# =========================================
# 🧹 Global Cleanup (Exit Trap)
# -----------------------------------------
# Räumt Mounts und LUKS-Mapper auf
# bei Fehler oder Abbruch
# =========================================

cleanup() {
  warn "Cleanup läuft..."
  log_to_file "CLEANUP start"

  if mountpoint -q /mnt; then
    umount -R /mnt || warn "Konnte /mnt nicht vollständig unmounten."
  fi

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    cryptsetup close "$ROOT_MAPPER_NAME" || warn "Konnte LUKS-Mapper nicht schließen: ${ROOT_MAPPER_NAME}"
  fi

  log_to_file "CLEANUP done"
}

trap cleanup EXIT

# =========================================
# ▶ Modul sicher ausführen
# -----------------------------------------
# Lädt Modul, validiert Funktion und
# trackt Status + Logging
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

  "$function_name"

  set_state "done:${module}"
  log_to_file "DONE module=${module}"
}

# =========================================
# 🚀 Installationspipeline ausführen
# -----------------------------------------
# Führt alle Module in definierter
# Reihenfolge deterministisch aus
# =========================================

run_install() {
  header "Installationsplan"

  run_module "01_disk.sh" "run_disk_setup"
  run_module "02_encryption.sh" "run_encryption_setup"
  run_module "03_btrfs.sh" "run_btrfs_setup"
  run_module "04_base.sh" "run_base_install"
  run_module "08_bootloader.sh" "run_bootloader_setup"
  run_module "05_system.sh" "run_system_config"
  run_module "06_perf.sh" "run_perf_setup"
  run_module "07_snapshots.sh" "run_snapshot_setup"
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
# 🔐 Finales System-Hardening
# -----------------------------------------
# Entfernt temporäre Rechte und
# bereinigt Installer-Artefakte
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
# 🧠 Hauptablauf steuern
# -----------------------------------------
# Einstiegspunkt: initialisiert Runtime,
# validiert Config und startet Installation
# =========================================

main() {
  init_runtime

  collect_config
  validate_config
  export_config
  confirm_config

  if [[ "${DRY_RUN:-true}" != true ]]; then
    ALLOW_EXEC=true
    export ALLOW_EXEC
  fi

  run_install

  set_state "done:install"
  success "Fertig."
}

main "$@"
