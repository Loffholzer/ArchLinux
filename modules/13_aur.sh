#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      13_aur.sh
# Zweck:     AUR-Helper einrichten
#
# Aufgabe:
# - installiert paru aus dem AUR
# - baut Paket als normaler Benutzer
# - schreibt definierte paru-Konfiguration
#
# Wichtig:
# - temporäre NOPASSWD-Rechte sind kritisch
# - Build darf niemals als root laufen
# - sudoers muss nach Fehlern bereinigt werden
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. Build nur als Benutzer ausführen
# 3. Temporäre sudoers-Datei validieren
# 4. Temporäre Rechte immer entfernen
# =========================================

# =========================================
# 🏗️ AUR-Setup ausführen
# -----------------------------------------
# Installiert und konfiguriert paru
# → ermöglicht AUR-Nutzung für den Benutzer
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
# 🔒 AUR-Eingaben prüfen
# -----------------------------------------
# Validiert USERNAME und Zielsystem-Mount
# → verhindert Build im falschen Kontext
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
# 📋 AUR-Plan anzeigen
# -----------------------------------------
# Zeigt Helper und Build-Benutzer
# → Sichtprüfung vor temporären sudo-Rechten
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
# Baut paru als Benutzer mit temporärem sudo
# → Rechte müssen danach entfernt werden
# =========================================

installiere_paru() {
  local sudoers_file="/mnt/etc/sudoers.d/10-installer"

  cleanup_installer_sudo() {
    rm -f "$sudoers_file"
  }

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde temporäre Sudo-Rechte setzen und paru installieren"
    warn "[DRY-RUN] würde temporäre Sudo-Datei entfernen: $sudoers_file"
    return 0
  fi

  log "Vorbereiten temporärer Sudo-Rechte für paru..."

  mkdir -p /mnt/etc/sudoers.d

  cat > "$sudoers_file" <<EOF
${USERNAME} ALL=(ALL:ALL) NOPASSWD: /usr/bin/pacman, /usr/bin/makepkg
EOF

  chmod 440 "$sudoers_file"

  trap cleanup_installer_sudo RETURN

  arch-chroot /mnt visudo -c || {
    error "sudoers ist nach temporärer Datei ungültig."
    return 1
  }

  log "Installiere paru-Abhängigkeiten..."

  run_cmd arch-chroot /mnt pacman -S --noconfirm base-devel git sudo

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
# Schreibt definierte paru-Defaults
# → reproduzierbares AUR-Verhalten
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
