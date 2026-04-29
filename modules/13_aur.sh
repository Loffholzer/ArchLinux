#!/usr/bin/env bash

# =========================================
# 13_aur.sh
# -----------------------------------------
# Aufgabe:
# - installiert paru als AUR-Helper
#
# Voraussetzung:
# - Benutzer existiert
# - git/base-devel vorhanden oder installierbar
# =========================================

# =========================
# 🚀 AUR Setup ausführen
# =========================

run_aur_setup() {
  header "13 - AUR"

  pruefe_aur_variablen
  zeige_aur_plan
  installiere_paru

  success "AUR vorbereitet."
}

# =========================
# 🔒 Checks
# =========================

pruefe_aur_variablen() {
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

zeige_aur_plan() {
  header "Geplante AUR-Einrichtung"

  echo "AUR-Helper: paru"
  echo "Benutzer:   $USERNAME"
  echo

  warn "Dieses Modul installiert paru aus dem AUR."
  echo
}

# =========================
# 📦 Paru (AUR) installieren
# =========================

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

  log "Installiere Abhängigkeiten für paru..."
  arch-chroot /mnt pacman -S --noconfirm base-devel git sudo || {
    error "Abhängigkeiten für paru konnten nicht installiert werden."
    return 1
  }

  log "Baue und installiere paru als Benutzer $USERNAME..."
  arch-chroot /mnt sudo -u "$USERNAME" bash -c "
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
