#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      05_system.sh
# Zweck:     Basissystem konfigurieren
#
# Aufgabe:
# - generiert und validiert fstab
# - setzt Hostname, Locale und Zeitzone
# - konfiguriert vconsole für TTY/initramfs
#
# Wichtig:
# - falsche fstab = Boot-Fail
# - fehlender EFI-Eintrag = Kernel-Update-Risiko
# - falsche Locale/Timezone = kaputte Systembasis
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. /mnt strikt validieren
# 3. fstab hart prüfen
# 4. Konfigurationsdateien deterministisch schreiben
# =========================================

# =========================================
# 🚀 Systemkonfiguration ausführen
# -----------------------------------------
# Schreibt fstab und Basiskonfiguration
# → macht Zielsystem boot- und nutzbar
# =========================================

run_system_config() {
  header "05 - Systemkonfiguration"

  pruefe_system_variablen
  zeige_system_plan
  validiere_mnt_konsistenz
  generiere_fstab
  ensure_efi_in_fstab
  validiere_fstab
  konfiguriere_hostname
  konfiguriere_locale
  konfiguriere_timezone
  konfiguriere_vconsole

  success "System konfiguriert."
}

# =========================================
# 🔒 Systemwerte prüfen
# -----------------------------------------
# Validiert Hostname, Timezone, LANG und Locales
# → stoppt vor defekter Systemkonfiguration
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
# 📋 Systemplan anzeigen
# -----------------------------------------
# Zeigt Hostname, Timezone und Locales
# → Sichtprüfung vor Schreiben ins Zielsystem
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
# Prüft BTRFS und Root-Subvolume
# → verhindert Konfiguration am falschen Ziel
# =========================================

validiere_mnt_konsistenz() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    return 0
  fi

  guard_mnt_mounted

  findmnt -n -o FSTYPE /mnt | grep -qx "btrfs" || {
    error "/mnt ist kein BTRFS → falscher Installationszustand"
    exit 1
  }

  local options
  options="$(findmnt -n -o OPTIONS /mnt)"

  [[ "$options" == *"subvol=@"* || "$options" == *"subvol=/@"* ]] || {
    error "/mnt ist nicht auf Subvolume @ gemountet"
    exit 1
  }
}

# =========================================
# 📄 fstab generieren
# -----------------------------------------
# Schreibt Mounttabelle aus aktuellen Mounts
# → Grundlage für Boot und Dateisystem-Mounts
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
# 🧷 EFI fstab absichern
# -----------------------------------------
# Erzwingt persistenten /boot-EFI-Eintrag
# → verhindert Boot-Probleme nach Updates
# =========================================

ensure_efi_in_fstab() {
  local fstab="/mnt/etc/fstab"
  local uuid

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde EFI-Eintrag in fstab sicherstellen"
    return 0
  fi

  guard_require_var EFI_PART
  guard_block_device "$EFI_PART"

  [[ -s "$fstab" ]] || {
    error "fstab fehlt oder leer"
    exit 1
  }

  grep -qE '[[:space:]]/boot[[:space:]]' "$fstab" && {
    log "EFI bereits in fstab"
    return 0
  }

  uuid="$(blkid -s UUID -o value "$EFI_PART")"

  [[ -n "$uuid" ]] || {
    error "EFI UUID fehlt"
    exit 1
  }

  printf 'UUID=%s  /boot  vfat  defaults  0 2\n' "$uuid" >> "$fstab"

  success "EFI fstab fix angewendet"
}

# =========================================
# 🔥 fstab validieren
# -----------------------------------------
# Prüft Root-Subvolume und EFI-Mount
# → falsche fstab macht System unbootbar
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
# -----------------------------------------
# Schreibt /etc/hostname
# → definiert lokalen Systemnamen
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
# -----------------------------------------
# Aktiviert Locales und schreibt locale.conf
# → fehlerhafte Locale bricht Systemtools
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
# -----------------------------------------
# Verlinkt /etc/localtime und setzt Hardware-Uhr
# → verhindert falsche Systemzeit
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
# -----------------------------------------
# Schreibt Keymap und Konsolenfont
# → wichtig für TTY und LUKS-Passworteingabe
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

