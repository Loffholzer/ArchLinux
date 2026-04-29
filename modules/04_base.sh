#!/usr/bin/env bash

# =========================================
# 04_base.sh
# -----------------------------------------
# Aufgabe:
# - installiert das Basissystem nach /mnt
# - nutzt pacstrap
#
# Voraussetzung:
# - /mnt ist gemountet (aus 03_btrfs.sh)
# =========================================

# =========================
# 🚀 Basissystem Setup ausführen
# =========================

run_base_install() {
  header "04 - Basissystem"

  pruefe_base_variablen
  zeige_base_plan
  installiere_base

  success "Basissystem installiert."
}

# =========================
# 🔒 Checks
# =========================

pruefe_base_variablen() {
  if [[ "${DRY_RUN:-true}" != true ]]; then
    mountpoint -q /mnt || {
      error "/mnt ist nicht gemountet. Abbruch."
      exit 1
    }
  fi
}

# =========================
# 📋 Plan anzeigen
# =========================

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

# =========================
# 📦 Installation
# =========================

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
