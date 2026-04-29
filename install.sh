#!/usr/bin/env bash
set -euo pipefail

# =========================================
# install.sh
# -----------------------------------------
# Haupt-Controller des Installationssystems
#
# Aufgabe:
# - steuert den gesamten Ablauf
# - lädt Konfiguration (00_config.sh)
# - führt Module in definierter Reihenfolge aus
#
# Wichtige Eigenschaften:
# - enthält keine Installationslogik
# - respektiert DRY-RUN
# - zentrale Steuerung aller Module
# =========================================

# =========================
# ⚙️ Globale Einstellungen
# =========================

DRY_RUN=false    # Sicherheitsmodus: keine echten Änderungen
AUTO_MODE=false  # Überspringt die Abfragen und setzt default werte

# Script-Pfade sauber bestimmen (egal von wo gestartet)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$SCRIPT_DIR/modules"
export DRY_RUN AUTO_MODE SCRIPT_DIR MODULE_DIR

# =========================
# 📦 Bibliotheken laden
# =========================

source "$SCRIPT_DIR/lib/ui.sh"

# =========================
# 📦 Config-Modul laden
# =========================

source "$MODULE_DIR/00_config.sh"

# =========================
# ▶ Modul-Ausführung
# =========================

run_module() {
  local module="$1"
  local function_name="$2"
  local path="${MODULE_DIR}/${module}"

  header "Modul: ${module}"

  if [[ ! -f "$path" ]]; then
    error "Modul nicht gefunden: ${module}"
    exit 1
  fi

  unset -f "$function_name" 2>/dev/null || true

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] Modul wird im Testmodus ausgeführt: ${module}"
  fi

  source "$path"

  if ! declare -F "$function_name" >/dev/null; then
    error "Funktion nicht gefunden: ${function_name}"
    exit 1
  fi

  "$function_name"
}

# =========================
# 🚀 Installationsablauf
# =========================

run_install() {
  header "Installationsplan"

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

  # Sicherheit nach Abschluss aller Module finalisieren
  run_final_hardening
}

# =========================
# 🧠 Main Ablauf
# =========================

main() {
  collect_config
  validate_config
  export_config
  confirm_config
  run_install

  success "Fertig."
}

main "$@"

# =========================
# 🧹 Finales Hardening
# =========================

run_final_hardening() {
  header "Sicherheit finalisieren"
  if [[ -f "/mnt/etc/sudoers.d/10-installer" ]]; then
    rm -f "/mnt/etc/sudoers.d/10-installer"
    success "Temporäre Sudo-Rechte entfernt."
  fi
}
