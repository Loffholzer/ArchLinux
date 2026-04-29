#!/usr/bin/env bash

# =========================================
# 12_tools.sh
# -----------------------------------------
# Aufgabe:
# - installiert sinnvolle CLI-Tools
#
# Voraussetzung:
# - Basissystem ist installiert
# =========================================

run_tools_setup() {
  header "12 - CLI-Tools"

  zeige_tools_plan
  installiere_tools

  success "CLI-Tools installiert."
}

# =========================
# 📋 Plan anzeigen
# =========================

zeige_tools_plan() {
  header "Geplante CLI-Tools"

  echo "Pakete:"
  echo "  git"
  echo "  curl"
  echo "  wget"
  echo "  htop"
  echo "  fastfetch"
  echo "  unzip"
  echo "  zip"
  echo "  man-db"
  echo "  man-pages"
  echo "  bash-completion"
  echo

  warn "Dieses Modul installiert praktische Werkzeuge."
  echo
}

# =========================
# 📦 Installation
# =========================

installiere_tools() {
  local packages=(
    git
    curl
    wget
    htop
    fastfetch
    unzip
    zip
    man-db
    man-pages
    bash-completion
  )

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde CLI-Tools installieren:"
    warn "[DRY-RUN] pacman -S --noconfirm ${packages[*]}"
    return 0
  fi

  log "Installiere CLI-Tools..."

  arch-chroot /mnt pacman -S --noconfirm "${packages[@]}"
}
