#!/usr/bin/env bash

# =========================================
# 12_tools.sh
# -----------------------------------------
# Aufgabe:
# - installiert essenzielle und moderne CLI-Tools
# - ergänzt Such- und Analyse-Werkzeuge
#
# Voraussetzung:
# - Basissystem ist installiert
# =========================================

# =========================
# 🚀 Tools Setup ausführen
# =========================
run_tools_setup() {
  header "12 - CLI-Tools"

  zeige_tools_plan
  installiere_tools

  success "CLI-Tools vollständig installiert."
}

# =========================
# 📋 Plan anzeigen
# =========================
zeige_tools_plan() {
  header "Geplante CLI-Tools"

  echo "Netzwerk & Download:"
  echo "  - git, curl, wget, rsync"
  echo "Suche & Analyse:"
  echo "  - ripgrep (rg), fd, jq, fzf"
  echo "Archivierung:"
  echo "  - unzip, zip, p7zip"
  echo "Dokumentation:"
  echo "  - man-db, man-pages, tealdeer (tldr)"
  echo "System & Hilfe:"
  echo "  - bash-completion, neovim (als Fallback)"
  echo

  warn "Dieses Modul installiert professionelle Werkzeuge für die Konsole."
  echo
}

# =========================
# 📦 Installation
# =========================
installiere_tools() {
  # htop/fastfetch entfernt (in Modul 11)
  # Wichtig: fzf hinzugefügt (essentiell für Fish/Zoxide Integration)
  local packages=(
    git
    curl
    wget
    rsync
    ripgrep
    fd
    jq
    fzf
    unzip
    zip
    p7zip
    man-db
    man-pages
    tealdeer
    bash-completion
    neovim
  )

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde folgende CLI-Tools installieren:"
    warn "[DRY-RUN] pacman -S --noconfirm ${packages[*]}"
    return 0
  fi

  log "Installiere CLI-Toolset..."

  arch-chroot /mnt pacman -S --noconfirm "${packages[@]}" || {
    error "Einige Tools konnten nicht installiert werden."
    exit 1
  }

  # Tealdeer (tldr) Cache initial befüllen für sofortige Nutzbarkeit
  log "Initialisiere tldr-Datenbank..."
  arch-chroot /mnt tldr --update 2>/dev/null || warn "tldr-Update fehlgeschlagen (evtl. kein Internet)."
}
