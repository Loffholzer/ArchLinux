#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      04_base.sh
# Zweck:     Basissystem installieren
#
# Aufgabe:
# - installiert base System via pacstrap
#
# Wichtig:
# - benötigt korrekt gemountetes /mnt
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. /mnt MUSS validiert sein
# 2. pacstrap darf nicht silent failen
# 3. Paketliste deterministisch halten
# =========================================

# =========================================
# 📦 Basissystem-Installation orchestrieren
# -----------------------------------------
# Steuert Installation des minimalen
# Arch-Systems nach /mnt
# =========================================

run_base_install() {
  header "04 - Basissystem"

  pruefe_base_variablen
  zeige_base_plan
  installiere_base

  success "Basissystem installiert."
}

# =========================================
# 🔒 Basis-System Voraussetzungen prüfen
# -----------------------------------------
# Stellt sicher, dass /mnt korrekt
# gemountet ist vor pacstrap
# =========================================

pruefe_base_variablen() {
  if [[ "${DRY_RUN:-true}" != true ]]; then
    mountpoint -q /mnt || {
      error "/mnt ist nicht gemountet. Abbruch."
      exit 1
    }
  fi
}

# =========================================
# 📋 Basis-Pakete anzeigen
# -----------------------------------------
# Zeigt geplante Pakete für das
# minimale Arch-Grundsystem
# =========================================

zeige_base_plan() {
  header "Geplante Installation"

  echo "Pakete:"
  echo "  base"
  echo "  base-devel"
  echo "  btrfs-progs"
  echo "  sudo"
  [[ "${USE_LUKS:-no}" == "yes" ]] && echo "  cryptsetup"
  echo

  warn "Dieses Modul installiert das Basissystem nach /mnt."
  warn "Kernel, Firmware, Limine und Memtest folgen im Bootloader-Modul."
  echo
}

# =========================================
# 📦 Basissystem installieren
# -----------------------------------------
# Führt pacstrap aus und installiert
# Kernpakete ins Zielsystem
# =========================================

installiere_base() {
  local packages=(
    base
    base-devel
    btrfs-progs
    sudo
  )

  if [[ "${USE_LUKS:-no}" == "yes" ]]; then
    packages+=(
      cryptsetup
    )
  fi

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde pacstrap ausführen:"
    warn "[DRY-RUN] pacstrap /mnt ${packages[*]}"
    return 0
  fi

  log "Installiere Basissystem..."

  pacstrap /mnt "${packages[@]}" || {
    error "pacstrap fehlgeschlagen."
    exit 1
  }
}
