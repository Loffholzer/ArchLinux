#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer - Main Controller
# -----------------------------------------
# Name:      install.sh
# Zweck:     Hauptsteuerung der Installation
#
# Aufgabe:
# - Lädt alle Module in der korrekten Reihenfolge
# - Verwaltet den globalen State (DRY_RUN)
#
# Wichtig:
# - Wird immer aus dem Root-Verzeichnis gestartet
# - SC2155: Deklaration und Zuweisung getrennt
# =========================================

# Pfade ermitteln (ohne Return-Values zu maskieren)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || { echo "Fehler bei der Pfadermittlung."; exit 1; }
readonly BASE_DIR

MOD_DIR="${BASE_DIR}/modules"
readonly MOD_DIR

# Setze DRY_RUN auf false für eine echte Installation!
export DRY_RUN=false

# =========================================
# 🔌 Funktion: load_module
# -----------------------------------------
# Zweck:    Sicheres Laden von Teilskripten
# Aufgabe:  Prüft Existenz und führt Hauptfunktion aus
# =========================================
load_module() {
    local mod_file
    local func_name

    mod_file="$1"
    func_name="$2"

    if [[ -f "${MOD_DIR}/${mod_file}" ]]; then
        # shellcheck disable=SC1090
        source "${MOD_DIR}/${mod_file}"
        "$func_name"
    else
        echo -e "\033[1;31m[FEHLER]\033[0m Modul ${mod_file} nicht gefunden. Abbruch."
        exit 1
    fi
}

# =========================================
# 🚀 Funktion: main
# -----------------------------------------
# Zweck:    Sequenzielle Abarbeitung
# Aufgabe:  Triggert alle Phasen (00 bis 99)
# =========================================
main() {
    # 1. Utils & Config
    load_module "01_utils.sh" "run_utils"
    load_module "00_config.sh" "run_config"

    # 2. Ausführung der Phasen
    load_module "02_prep.sh" "run_prep"
    load_module "03_disk.sh" "run_disk"
    load_module "04_base.sh" "run_base"
    load_module "05_env.sh" "run_env"
    load_module "06_users.sh" "run_users"
    load_module "07_services.sh" "run_services"

    # Platz für zukünftige Module (08-98)

    # 3. Abschluss
    load_module "99_cleanup.sh" "run_cleanup"
}

# =========================================
# 🏁 Start
# =========================================
main "$@"
