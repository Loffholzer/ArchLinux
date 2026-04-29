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

  mkdir -p "$RUN_DIR"
  touch "$LOG_FILE"

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

  [[ -n "${STATE_FILE:-}" ]] || {
    error "STATE_FILE ist nicht gesetzt."
    exit 1
  }

  echo "$state" > "$STATE_FILE"
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
# 🧹 Cleanup ausführen
# -----------------------------------------
# Räumt /mnt und cryptroot defensiv auf
# → verhindert hängende Mounts/Mapper
# =========================================

cleanup() {
  warn "Cleanup läuft..."
  log_to_file "CLEANUP start"

  if mountpoint -q /mnt/.snapshots; then
    umount /mnt/.snapshots || warn "Konnte /mnt/.snapshots nicht unmounten."
  fi

  if mountpoint -q /mnt/home; then
    umount /mnt/home || warn "Konnte /mnt/home nicht unmounten."
  fi

  if mountpoint -q /mnt/boot; then
    umount /mnt/boot || warn "Konnte /mnt/boot nicht unmounten."
  fi

  if mountpoint -q /mnt; then
    umount /mnt || warn "Konnte /mnt nicht unmounten."
  fi

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    if cryptsetup status "$ROOT_MAPPER_NAME" >/dev/null 2>&1; then
      cryptsetup close "$ROOT_MAPPER_NAME" || warn "Konnte LUKS-Mapper nicht schließen: ${ROOT_MAPPER_NAME}"
    fi
  fi

  log_to_file "CLEANUP done"
}

trap cleanup EXIT

# =========================================
# ▶ Modul ausführen
# -----------------------------------------
# Lädt Modul, prüft Funktion und trackt State
# → kapselt Modulstart deterministisch
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

  local last_state
  last_state="$(get_state)"

  # 🔥 Resume-Logik
  if [[ "$last_state" == done:${module} ]]; then
    success "Überspringe ${module} (bereits erledigt)"
    return 0
  fi

  set_state "running:${module}"

  "$function_name"

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
# 🧠 Einstiegspunkt ausführen
# -----------------------------------------
# Initialisiert Runtime, Config und Pipeline
# → startet kontrollierte Installation
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
