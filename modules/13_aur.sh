#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      13_aur.sh
# Zweck:     AUR Integration
#
# Aufgabe:
# - installiert paru
#
# Wichtig:
# - temporäre sudo Rechte kritisch
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. sudo temporär und sicher entfernen
# 2. Build nicht als root
# =========================================

# =========================================
# 🏗️ AUR-Setup orchestrieren
# -----------------------------------------
# Steuert Installation und Konfiguration
# des AUR-Helpers paru
# =========================================

run_aur_setup() {
  header "13 - AUR"

  pruefe_aur_variablen
  zeige_aur_plan
  installiere_paru
  konfiguriere_paru

  success "AUR vorbereitet."
}

# =========================================
# 🔒 AUR-Voraussetzungen prüfen
# -----------------------------------------
# Validiert Benutzer und stellt sicher,
# dass Zielsystem gemountet ist
# =========================================

pruefe_aur_variablen() {
  [[ -n "${USERNAME:-}" ]] || { error "USERNAME fehlt."; exit 1; }

  if [[ "${DRY_RUN:-true}" != true ]]; then
    mountpoint -q /mnt || {
      error "/mnt ist nicht gemountet."
      exit 1
    }
  fi
}

# =========================================
# 📋 AUR-Setup anzeigen
# -----------------------------------------
# Zeigt geplante Installation von paru
# und Benutzerkontext
# =========================================

zeige_aur_plan() {
  header "Geplante AUR-Einrichtung"

  echo "AUR-Helper: paru"
  echo "Benutzer:   $USERNAME"
  echo

  warn "Dieses Modul installiert paru aus dem AUR."
  echo
}

# =========================================
# 📦 paru installieren
# -----------------------------------------
# Baut und installiert paru sicher
# mit temporären sudo-Rechten
# =========================================

installiere_paru() {
  local sudoers_file="/mnt/etc/sudoers.d/10-installer"

  cleanup_installer_sudo() {
    rm -f "$sudoers_file"
  }

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Sudo-Rechte anpassen und paru installieren"
    warn "[DRY-RUN] würde temporäre Sudo-Datei nach Abschluss entfernen: $sudoers_file"
    return 0
  fi

  log "Vorbereiten der Sudo-Rechte für den Build-Prozess..."

  mkdir -p /mnt/etc/sudoers.d
  echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > "$sudoers_file"
  chmod 440 "$sudoers_file"

  trap cleanup_installer_sudo RETURN

  arch-chroot /mnt visudo -c || {
    error "sudoers ist nach temporärer Datei ungültig."
    return 1
  }

  log "Installiere Abhängigkeiten für paru..."
  arch-chroot /mnt pacman -S --noconfirm base-devel git sudo || {
    error "Abhängigkeiten für paru konnten nicht installiert werden."
    return 1
  }

  log "Baue und installiere paru als Benutzer $USERNAME..."
  arch-chroot /mnt sudo -u "$USERNAME" bash -c "
    set -euo pipefail
    cd /tmp
    rm -rf paru
    git clone https://aur.archlinux.org/paru.git
    cd paru
    makepkg -si --noconfirm
  " || {
    error "paru konnte nicht gebaut werden."
    return 1
  }

  cleanup_installer_sudo
  trap - RETURN

  success "paru erfolgreich installiert."
}

# =========================================
# ⚙️ paru konfigurieren
# -----------------------------------------
# Setzt definierte Default-Optionen
# für reproduzierbares Verhalten
# =========================================

konfiguriere_paru() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde paru konfigurieren (BottomUp, Color, SudoLoop, RemoveMake)"
    return 0
  fi

  log "Konfiguriere paru Defaults für Benutzer $USERNAME..."

  local config_dir="/mnt/home/${USERNAME}/.config/paru"
  local config_file="${config_dir}/paru.conf"

  # Verzeichnis erstellen (idempotent)
  mkdir -p "$config_dir"

  # Config schreiben (überschreibt bewusst -> definierter Zustand)
  cat > "$config_file" <<'EOF'
[options]
BottomUp
Color
SudoLoop
RemoveMake
EOF

  # Rechte setzen
  arch-chroot /mnt chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.config"

  success "paru konfiguriert (optimierte Defaults aktiv)."
}
