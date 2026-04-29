#!/usr/bin/env bash

# =========================================
# 09_user.sh
# -----------------------------------------
# Aufgabe:
# - erstellt Benutzer
# - setzt Passwort
# - konfiguriert sudo
# - optional: Root sperren
#
# Voraussetzung:
# - System ist installiert (/mnt)
# =========================================

run_user_setup() {
  header "09 - Benutzer"

  pruefe_user_variablen
  zeige_user_plan
  erstelle_user
  setze_passwoerter
  konfiguriere_sudo
  sperre_root_optional

  success "Benutzer eingerichtet."
}

# =========================
# 🔒 Checks
# =========================

pruefe_user_variablen() {
  [[ -n "${USERNAME:-}" ]] || { error "USERNAME fehlt."; exit 1; }
  [[ -n "${USER_PASSWORD:-}" ]] || { error "USER_PASSWORD fehlt."; exit 1; }

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

zeige_user_plan() {
  header "Geplante Benutzerkonfiguration"

  echo "Benutzer: $USERNAME"
  echo "Sudo:     aktiviert"
  echo "Root:     ${DISABLE_ROOT}"
  echo

  warn "Dieses Modul richtet Benutzer und Rechte ein."
  echo
}

# =========================
# 👤 User erstellen
# =========================

erstelle_user() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Benutzer erstellen: $USERNAME"
    return 0
  fi

  log "Erstelle Benutzer..."

  arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USERNAME"
}

# =========================
# 🔐 Passwörter
# =========================

setze_passwoerter() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Passwort für $USERNAME setzen"
    return 0
  fi

  log "Setze Benutzer-Passwort..."

  echo "${USERNAME}:${USER_PASSWORD}" | arch-chroot /mnt chpasswd
}

# =========================
# 🛡 Sudo
# =========================

konfiguriere_sudo() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde sudo (wheel) aktivieren"
    return 0
  fi

  log "Aktiviere sudo für wheel..."

  sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers
}

# =========================
# 🔒 Root sperren
# =========================

sperre_root_optional() {
  if [[ "$DISABLE_ROOT" != "yes" ]]; then
    log "Root bleibt aktiv."
    return 0
  fi

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde root account sperren"
    return 0
  fi

  log "Sperre root account..."

  arch-chroot /mnt passwd -l root
}
