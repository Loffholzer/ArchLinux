#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      05_system.sh
# Zweck:     Basis-Systemkonfiguration
#
# Aufgabe:
# - fstab generieren (kritisch für Boot)
# - Hostname setzen
# - Locale konfigurieren
# - Timezone setzen
# - vconsole konfigurieren
#
# Wichtig:
# - falsche fstab = Boot hängt
# - falsche Locale = System kaputt
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. /mnt MUSS validiert sein
# 2. fstab darf NICHT leer/kaputt sein
# 3. locale-gen MUSS erfolgreich sein
# 4. alle Dateien deterministisch schreiben
# =========================================


# =========================================
# 🚀 Systemkonfiguration orchestrieren
# =========================================

run_system_config() {
  header "05 - Systemkonfiguration"

  pruefe_system_variablen
  zeige_system_plan
  validiere_mnt_konsistenz
  generiere_fstab
  validiere_fstab
  konfiguriere_hostname
  konfiguriere_locale
  konfiguriere_timezone
  konfiguriere_vconsole

  success "System konfiguriert."
}


# =========================================
# 🔒 Variablen prüfen
# =========================================

pruefe_system_variablen() {
  guard_require_var HOSTNAME
  guard_require_var TIMEZONE
  guard_require_var LANG_DEFAULT

  [[ ${#LOCALES[@]} -gt 0 ]] || {
    error "LOCALES fehlt"
    exit 1
  }

  if [[ "${DRY_RUN:-true}" != true ]]; then
    guard_mnt_mounted
  fi
}


# =========================================
# 📋 Plan anzeigen
# =========================================

zeige_system_plan() {
  header "Geplante Systemkonfiguration"

  echo "Hostname:   $HOSTNAME"
  echo "Timezone:   $TIMEZONE"
  echo "Locales:    ${LOCALES[*]}"
  echo "LANG:       $LANG_DEFAULT"
  echo
}


# =========================================
# 🔍 /mnt Konsistenz prüfen
# -----------------------------------------
# Verhindert Installation auf falschem
# oder inkonsistentem Mount
# =========================================

validiere_mnt_konsistenz() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    return 0
  fi

  guard_mnt_mounted

  # Root muss BTRFS sein
  findmnt -n -o FSTYPE /mnt | grep -qx "btrfs" || {
    error "/mnt ist kein BTRFS → falscher Installationszustand"
    exit 1
  }

  # Subvol @ muss aktiv sein
  findmnt -n -o OPTIONS /mnt | grep -q "subvol=@" || {
    error "/mnt ist nicht auf Subvolume @ gemountet"
    exit 1
  }
}


# =========================================
# 📄 fstab generieren
# =========================================

generiere_fstab() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde fstab generieren"
    return 0
  fi

  log "Generiere fstab..."

  run_cmd genfstab -U /mnt > /mnt/etc/fstab
}


# =========================================
# 🔥 fstab validieren (CRITICAL)
# -----------------------------------------
# Verhindert Boot mit leerer oder falscher fstab
# =========================================

validiere_fstab() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    return 0
  fi

  local fstab="/mnt/etc/fstab"

  [[ -s "$fstab" ]] || {
    error "fstab ist leer → System nicht bootfähig"
    exit 1
  }

  grep -q "subvol=@" "$fstab" || {
    error "fstab enthält kein root subvol=@"
    exit 1
  }

  grep -q "/boot" "$fstab" || {
    warn "EFI Mount fehlt in fstab (kann später problematisch sein)"
  }

  success "fstab validiert."
}


# =========================================
# 🏷 Hostname setzen
# =========================================

konfiguriere_hostname() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Hostname setzen: $HOSTNAME"
    return 0
  fi

  echo "$HOSTNAME" > /mnt/etc/hostname
}


# =========================================
# 🌐 Locale konfigurieren
# =========================================

konfiguriere_locale() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Locales setzen"
    return 0
  fi

  local locale_gen="/mnt/etc/locale.gen"

  for loc in "${LOCALES[@]}"; do
    sed -i "s/^#${loc}/${loc}/" "$locale_gen"
  done

  run_cmd arch-chroot /mnt locale-gen

  [[ -f /mnt/etc/locale.conf ]] || touch /mnt/etc/locale.conf

  echo "LANG=${LANG_DEFAULT}" > /mnt/etc/locale.conf

  grep -q "LANG=${LANG_DEFAULT}" /mnt/etc/locale.conf || {
    error "LANG wurde nicht korrekt gesetzt"
    exit 1
  }
}


# =========================================
# 🕒 Timezone setzen
# =========================================

konfiguriere_timezone() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Timezone setzen: $TIMEZONE"
    return 0
  fi

  local zone_file="/usr/share/zoneinfo/${TIMEZONE}"

  [[ -f "$zone_file" ]] || {
    error "Timezone existiert nicht: $TIMEZONE"
    exit 1
  }

  ln -sf "$zone_file" /mnt/etc/localtime

  run_cmd arch-chroot /mnt hwclock --systohc
}


# =========================================
# 🖥️ vconsole konfigurieren
# =========================================

konfiguriere_vconsole() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde vconsole setzen"
    return 0
  fi

  guard_require_var KEYMAP

  cat > /mnt/etc/vconsole.conf <<EOF
KEYMAP=${KEYMAP}
FONT=${CONSOLE_FONT:-ter-v28n}
EOF
}
