#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      11_shell.sh
# Zweck:     Shell Setup
#
# Aufgabe:
# - installiert fish + tools
# - konfiguriert Benutzerumgebung
#
# Wichtig:
# - rein kosmetisch / UX
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. idempotent konfigurieren
# 2. keine bestehenden configs zerstören
# =========================================

# =========================================
# 🐚 Shell-Setup orchestrieren
# -----------------------------------------
# Steuert Installation und Konfiguration
# von fish, starship und Shell-Umgebung
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

# =========================================
# 🔒 Shell-Voraussetzungen prüfen
# -----------------------------------------
# Validiert Username und stellt sicher,
# dass das Zielsystem gemountet ist
# =========================================

pruefe_shell_variablen() {
  [[ -n "${USERNAME:-}" ]] || { error "USERNAME fehlt."; exit 1; }

  if [[ "${DRY_RUN:-true}" != true ]]; then
    mountpoint -q /mnt || {
      error "/mnt ist nicht gemountet."
      exit 1
    }
  fi
}

# =========================================
# 📋 Shell-Konfiguration anzeigen
# -----------------------------------------
# Zeigt geplante Shell, Tools und
# Anpassungen vor Installation
# =========================================

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

# =========================================
# 📦 Shell-Tools installieren
# -----------------------------------------
# Installiert fish, starship und
# unterstützende CLI-Utilities
# =========================================

installiere_shell_tools() {
  # Vollständige Liste aller in der config.fish genutzten Tools
  local packages=(
    fish
    starship
    eza
    bat
    btop
    fastfetch
    zoxide
    ttf-jetbrains-mono-nerd
  )

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Shell-Tools installieren: ${packages[*]}"
    return 0
  fi

  log "Installiere Shell-Tools, Zoxide und Fonts..."

  arch-chroot /mnt pacman -S --noconfirm "${packages[@]}" || {
    error "Shell-Tools konnten nicht vollständig installiert werden."
    exit 1
  }
}

# =========================================
# 🔄 Default-Shell setzen
# -----------------------------------------
# Setzt fish als Login-Shell für
# Benutzer und optional root
# =========================================

setze_default_shell() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde fish als Default-Shell für $USERNAME und root setzen"
    return 0
  fi

  log "Setze fish als Default-Shell für User und Root..."

  arch-chroot /mnt chsh -s /usr/bin/fish "$USERNAME"
  arch-chroot /mnt chsh -s /usr/bin/fish root
}

# =========================================
# ✨ Starship konfigurieren
# -----------------------------------------
# Aktiviert starship im fish-Setup
# und stellt idempotente Konfiguration sicher
# =========================================

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

# =========================================
# ⚡ Shell-Aliase konfigurieren
# -----------------------------------------
# Erstellt zentrale config.fish mit
# Aliases und Tool-Initialisierung
# =========================================

setze_aliases() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde config.fish für User und Root generieren"
    return 0
  fi

  log "Generiere zentrale config.fish für User und Root..."

  local fish_dir_user="/mnt/home/${USERNAME}/.config/fish"
  local fish_dir_root="/mnt/root/.config/fish"
  local config_file_user="${fish_dir_user}/config.fish"
  local config_file_root="${fish_dir_root}/config.fish"

  mkdir -p "$fish_dir_user" "$fish_dir_root"

  # Erstellung der Config mit Prüfung, ob Tools existieren (verhindert Fehlermeldungen)
  cat << 'EOF' > "$config_file_user"
# --- System Init ---
set -g fish_greeting

# Starte fastfetch nur, wenn es installiert ist
if type -q fastfetch
    fastfetch
end

# --- Prompt & Navigation ---
# Starship Initialisierung
if type -q starship
    starship init fish | source
end

# Zoxide (Smart cd) Initialisierung
if type -q zoxide
    zoxide init fish | source
end

# --- Professional Aliases ---
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first'
alias la='eza -laa --icons --group-directories-first'
alias cat='bat --theme="Monokai Extended"'
alias top='btop'
alias cd='z'
alias update='sudo pacman -Syu'
EOF

  # Konfiguration auf Root spiegeln
  cp "$config_file_user" "$config_file_root"

  # Rechte setzen
  arch-chroot /mnt chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.config"
  arch-chroot /mnt chown -R "root:root" "/root/.config"

  success "Shell-Environment (inkl. Zoxide & Fastfetch) korrigiert."
}
