#!/usr/bin/env bash

# =========================================
# 11_shell.sh
# -----------------------------------------
# Aufgabe:
# - installiert fish + starship
# - setzt fish als default shell
# - richtet einfache Aliase ein
#
# Voraussetzung:
# - User existiert (08)
# =========================================

run_shell_setup() {
  header "11 - Shell"

  pruefe_shell_variablen
  zeige_shell_plan
  installiere_shell_tools
  setze_default_shell
  konfiguriere_starship
  setze_aliases

  success "Shell eingerichtet."
}

# =========================
# 🔒 Checks
# =========================

pruefe_shell_variablen() {
  [[ -n "${USERNAME:-}" ]] || { error "USERNAME fehlt."; exit 1; }

  if [[ "${DRY_RUN:-true}" != true ]]; then
    mountpoint -q /mnt || {
      error "/mnt ist nicht gemountet."
      exit 1
    }
  fi
}

# =========================
# 📋 Plan anzeigen
# =========================

zeige_shell_plan() {
  header "Geplante Shell-Konfiguration"

  echo "User: $USERNAME"
  echo "Shell: fish"
  echo "Prompt: starship"
  echo "Fonts: Nerd Fonts (JetBrains Mono, Symbols)"
  echo

  warn "Dieses Modul richtet eine komfortable Shell ein."
  echo
}

# =========================
# 📦 Installation
# =========================

installiere_shell_tools() {
  local packages=(
    fish
    starship
    eza
    bat
    bottom
    ttf-jetbrains-mono-nerd
    ttf-nerd-fonts-symbols
  )

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Shell-Tools und Nerd Fonts installieren:"
    warn "  ${packages[*]}"
    return 0
  fi

  log "Installiere Shell-Tools und Nerd Fonts..."

  arch-chroot /mnt pacman -S --noconfirm "${packages[@]}" || {
    error "Shell-Tools konnten nicht installiert werden."
    exit 1
  }
}

# =========================
# 🐟 Default Shell setzen
# =========================

setze_default_shell() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde fish als Default-Shell setzen"
    return 0
  fi

  log "Setze fish als Default-Shell..."

  arch-chroot /mnt chsh -s /usr/bin/fish "$USERNAME"
}

# =========================
# ✨ Starship konfigurieren
# =========================

konfiguriere_starship() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde starship für fish aktivieren"
    return 0
  fi

  log "Konfiguriere starship..."

  # Verzeichnis sicher erstellen
  arch-chroot /mnt bash -c "
    install -d -o '${USERNAME}' -g '${USERNAME}' '/home/${USERNAME}/.config/fish'
  "

  # config.fish idempotent erweitern
  arch-chroot /mnt bash -c "
    FILE='/home/${USERNAME}/.config/fish/config.fish'
    grep -qxF 'starship init fish | source' \"\$FILE\" 2>/dev/null || \
    echo 'starship init fish | source' >> \"\$FILE\"
  "

  # Rechte sicherstellen
  arch-chroot /mnt chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.config/fish/config.fish"
}

# =========================
# ⚡ Aliase
# =========================

setze_aliases() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Aliase setzen (ls, ll, update, cat, top)"
    return 0
  fi

  log "Setze Aliase..."

  local fish_dir="/mnt/home/${USERNAME}/.config/fish"
  local config_file="${fish_dir}/config.fish"

  # Verzeichnisstruktur direkt über /mnt anlegen
  mkdir -p "$fish_dir"

  # Konfiguration schreiben (idempotent)
  if ! grep -qxF "alias ls='eza --icons --group-directories-first'" "$config_file" 2>/dev/null; then
    cat << 'EOF' >> "$config_file"

# Custom Aliases
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first'
alias cat='bat'
alias top='btm'
alias update='sudo pacman -Syu'
EOF
  fi

  # Berechtigungen sauber auf den Zielbenutzer übertragen
  arch-chroot /mnt chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.config"

  success "Aliase sicher gesetzt."
}
