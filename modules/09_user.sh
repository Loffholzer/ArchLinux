#!/usr/bin/env bash
# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      09_user.sh
# Zweck:     Benutzerverwaltung
#
# Aufgabe:
# - erstellt User
# - setzt Passwort
# - konfiguriert sudo
#
# Wichtig:
# - sicherheitskritisch
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. Passwörter nie loggen
# 2. sudo sauber konfigurieren
# 3. root optional sperren
# =========================================


# =========================================
# 👤 Benutzer-Setup orchestrieren
# -----------------------------------------
# Steuert Erstellung des Users,
# Passwort und Rechtekonfiguration
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

# =========================================
# 🔒 Benutzer-Variablen prüfen
# -----------------------------------------
# Validiert Username, Passwort und
# gemountetes Zielsystem
# =========================================
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

# =========================================
# 📋 Benutzerkonfiguration anzeigen
# -----------------------------------------
# Zeigt geplanten User, sudo und
# Root-Status vor Anwendung
# =========================================
zeige_user_plan() {
  header "Geplante Benutzerkonfiguration"

  echo "Benutzer: $USERNAME"
  echo "Sudo:     aktiviert"
  echo "Root:     ${DISABLE_ROOT}"
  echo

  warn "Dieses Modul richtet Benutzer und Rechte ein."
  echo
}

# =========================================
# 👤 Benutzer erstellen
# -----------------------------------------
# Legt neuen User mit Home-Verzeichnis
# und Gruppenmitgliedschaft an
# =========================================
erstelle_user() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Benutzer erstellen: $USERNAME"
    return 0
  fi

  if arch-chroot /mnt id "$USERNAME" &>/dev/null; then
    warn "Benutzer existiert bereits, überspringe."
    return 0
  fi

  arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USERNAME" || {
    error "User konnte nicht erstellt werden."
    exit 1
  }
}

# =========================================
# 🔐 Benutzer-Passwort setzen
# -----------------------------------------
# Setzt Passwort im Zielsystem
# via chpasswd
# =========================================
setze_passwoerter() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Passwort für $USERNAME setzen"
    return 0
  fi

  log "Setze Benutzer-Passwort..."

  echo "${USERNAME}:${USER_PASSWORD}" | arch-chroot /mnt chpasswd
}

# =========================================
# 🛡️ Sudo konfigurieren
# -----------------------------------------
# Aktiviert sudo für wheel-Gruppe
# im Zielsystem
# =========================================
konfiguriere_sudo() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde sudo konfigurieren"
    return 0
  fi

  local sudoers="/mnt/etc/sudoers"

  sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "$sudoers"

  # ❗ Validierung
  arch-chroot /mnt visudo -c || {
    error "sudoers ist ungültig!"
    exit 1
  }
}

# =========================================
# 🔒 Root-Zugang optional sperren
# -----------------------------------------
# Deaktiviert Root-Login für
# erhöhte Systemsicherheit
# =========================================
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
