#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      09_user.sh
# Zweck:     Benutzer und Rechte einrichten
#
# Aufgabe:
# - erstellt normalen Benutzer
# - setzt Benutzerpasswort
# - aktiviert sudo für wheel
# - sperrt root optional
#
# Wichtig:
# - sicherheitskritisch
# - Passwort darf nie geloggt werden
# - falsche sudoers = kein Admin-Zugriff
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. Passwörter nie ausgeben
# 3. sudoers nach Änderung validieren
# 4. Root-Zugang bewusst behandeln
# =========================================

# =========================================
# 👤 Benutzer-Setup ausführen
# -----------------------------------------
# Erstellt User, Passwort und sudo-Rechte
# → stellt administrativen Zugriff sicher
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
# 🔒 Benutzer-Eingaben prüfen
# -----------------------------------------
# Validiert USERNAME, USER_PASSWORD und /mnt
# → stoppt vor defekter User-Anlage
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
# 📋 Benutzer-Plan anzeigen
# -----------------------------------------
# Zeigt Benutzer, sudo und Root-Status
# → Sichtprüfung vor Rechteänderungen
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
# Legt User mit Home und wheel-Gruppe an
# → Voraussetzung für Login und sudo
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
# 🔐 Passwort setzen
# -----------------------------------------
# Setzt Benutzerpasswort via chpasswd
# → Secret darf niemals geloggt werden
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
# Aktiviert wheel-Sudo und prüft sudoers
# → falsche sudoers sperrt Admin-Zugriff aus
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
# 🔒 Root optional sperren
# -----------------------------------------
# Sperrt root-Login bei DISABLE_ROOT=yes
# → reduziert Angriffsfläche
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
