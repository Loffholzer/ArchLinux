#!/usr/bin/env bash

# =========================================
# 05_system.sh
# -----------------------------------------
# Aufgabe:
# - generiert fstab
# - setzt Hostname
# - konfiguriert Locale
# - setzt Timezone
#
# Voraussetzung:
# - /mnt existiert und ist gemountet
# =========================================

# =========================
# 🚀 Systemkonfiguration ausführen
# =========================

run_system_config() {
  header "05 - Systemkonfiguration"

  pruefe_system_variablen
  zeige_system_plan
  generiere_fstab
  konfiguriere_hostname
  konfiguriere_locale
  konfiguriere_timezone
  konfiguriere_vconsole
  installiere_systemdienste

  success "System konfiguriert."
}

# =========================
# 🔒 Checks
# =========================

pruefe_system_variablen() {
  [[ -n "${HOSTNAME:-}" ]] || { error "HOSTNAME fehlt."; exit 1; }
  [[ -n "${TIMEZONE:-}" ]] || { error "TIMEZONE fehlt."; exit 1; }
  [[ ${#LOCALES[@]} -gt 0 ]] || { error "LOCALES fehlt."; exit 1; }
  [[ -n "${LANG_DEFAULT:-}" ]] || { error "LANG_DEFAULT fehlt."; exit 1; }

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

zeige_system_plan() {
  header "Geplante Systemkonfiguration"

  echo "Hostname:   $HOSTNAME"
  echo "Timezone:   $TIMEZONE"
  echo "Locales:    ${LOCALES[*]}"
  echo "LANG:       $LANG_DEFAULT"
  echo

  warn "Dieses Modul konfiguriert das installierte System."
  echo
}

# =========================
# 📄 fstab
# =========================

generiere_fstab() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde fstab generieren (genfstab -U /mnt > /mnt/etc/fstab)"
    return 0
  fi

  log "Generiere fstab..."
  genfstab -U /mnt > /mnt/etc/fstab || {
    error "fstab konnte nicht erstellt werden."
    exit 1
  }
}

# =========================
# 🏷 Hostname
# =========================

konfiguriere_hostname() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Hostname setzen: $HOSTNAME"
    return 0
  fi

  log "Setze Hostname..."
  echo "$HOSTNAME" > /mnt/etc/hostname
}

# =========================
# 🌐 Locale
# =========================

konfiguriere_locale() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Locales aktivieren: ${LOCALES[*]}"
    warn "[DRY-RUN] würde LANG setzen: $LANG_DEFAULT"
    return 0
  fi

  log "Konfiguriere Locale..."

  for loc in "${LOCALES[@]}"; do
    sed -i "s/^#${loc}/${loc}/" /mnt/etc/locale.gen
  done

  arch-chroot /mnt locale-gen || {
    error "locale-gen fehlgeschlagen."
   exit 1
  }

  echo "LANG=${LANG_DEFAULT}" > /mnt/etc/locale.conf
}

# =========================
# 🕒 Timezone
# =========================

konfiguriere_timezone() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Timezone setzen: $TIMEZONE"
    return 0
  fi

  log "Setze Timezone..."

  ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /mnt/etc/localtime
  arch-chroot /mnt hwclock --systohc || {
    error "hwclock fehlgeschlagen."
    exit 1
  }
}

# =========================
# 🖥️ TTY / Konsolen-Font
# =========================

konfiguriere_vconsole() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde vconsole setzen: KEYMAP=${KEYMAP}, FONT=${CONSOLE_FONT:-standard}"
    return 0
  fi

  [[ -n "${KEYMAP:-}" ]] || {
    error "KEYMAP fehlt."
    exit 1
  }

  log "Setze vconsole..."

  cat > /mnt/etc/vconsole.conf <<EOF
KEYMAP=${KEYMAP}
FONT=${CONSOLE_FONT:-ter-v28n}
EOF
}

# =========================
# 📦 Systemdienste & Microcode installieren
# =========================

installiere_systemdienste() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] Netzwerkdienste werden im Netzwerk-Modul installiert"
    return 0
  fi

  log "Netzwerkdienste werden später im Netzwerk-Modul installiert."
}
