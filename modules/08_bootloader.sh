#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      08_bootloader.sh
# Zweck:     Bootchain mit Limine einrichten
#
# Aufgabe:
# - installiert Kernel, Firmware und Boottools
# - baut initramfs für Standard/LUKS
# - installiert Limine auf EFI
# - schreibt bootfähige limine.conf
#
# Wichtig:
# - Fehler hier = System bootet nicht
# - falsche UUID/Cmdline = initramfs hängt
# - fehlende EFI-Dateien = kein UEFI-Start
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. EFI-Mount strikt validieren
# 3. UUIDs hart prüfen
# 4. Bootartefakte nach Erstellung validieren
# =========================================

# =========================================
# 🚀 Bootloader-Setup ausführen
# -----------------------------------------
# Installiert Kernel, initramfs und Limine
# → macht Zielsystem UEFI-bootfähig
# =========================================

run_bootloader_setup() {
  header "08 - Bootloader (Limine)"

  pruefe_bootloader_variablen
  zeige_bootloader_plan
  mounte_efi
  installiere_kernel_und_boottools
  konfiguriere_vconsole_fuer_initramfs
  konfiguriere_mkinitcpio
  baue_initramfs
  installiere_limine_efi
  pruefe_memtest
  erstelle_limine_config
  validiere_boot_setup

  success "Bootloader eingerichtet."
}

# =========================================
# 🔒 Bootloader-Eingaben prüfen
# -----------------------------------------
# Validiert EFI_PART, ROOT_DEVICE und /mnt
# → stoppt vor falscher Bootchain
# =========================================

pruefe_bootloader_variablen() {
  guard_require_var EFI_PART
  guard_require_var ROOT_DEVICE

  if [[ "${DRY_RUN:-true}" != true ]]; then
    guard_block_device "$EFI_PART"
    guard_block_device "$ROOT_DEVICE"
    guard_mnt_mounted
  fi
}

# =========================================
# 📋 Bootloader-Plan anzeigen
# -----------------------------------------
# Zeigt EFI, Root-Gerät und Bootloader
# → Sichtprüfung vor Boot-Setup
# =========================================

zeige_bootloader_plan() {
  header "Geplanter Bootloader"

  echo "Bootloader:    Limine"
  echo "EFI-Partition: $EFI_PART"
  echo "Root-Gerät:    $ROOT_DEVICE"
  echo "Mountpoint:    /boot"
  echo

  warn "Bootchain wird vollständig eingerichtet."
  echo
}

# =========================================
# 📂 EFI mounten
# -----------------------------------------
# Mountet EFI_PART nach /mnt/boot
# → falscher Mount macht System unbootbar
# =========================================

mounte_efi() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde EFI nach /mnt/boot mounten"
    return 0
  fi

  mkdir -p /mnt/boot

  if mountpoint -q /mnt/boot; then
    guard_mountpoint_source /mnt/boot "$EFI_PART"
    warn "/mnt/boot bereits korrekt gemountet."
    return 0
  fi

  run_cmd mount "$EFI_PART" /mnt/boot

  guard_mountpoint_source /mnt/boot "$EFI_PART"

  success "EFI gemountet."
}

# =========================================
# 📦 Kernel und Boottools installieren
# -----------------------------------------
# Installiert Kernel, Firmware, Limine, Memtest
# → Grundlage für Boot und Recovery
# =========================================

installiere_kernel_und_boottools() {
  local packages=(
    linux
    linux-lts
    linux-firmware
    limine
    memtest86+-efi
  )

  [[ -n "$MICROCODE_PKG" ]] && packages+=("$MICROCODE_PKG")

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde installieren: ${packages[*]}"
    return 0
  fi

  run_cmd arch-chroot /mnt pacman -S --noconfirm "${packages[@]}"
}

# =========================================
# ⚙️ vconsole für initramfs setzen
# -----------------------------------------
# Schreibt Keymap und Konsolenfont
# → wichtig für LUKS-Passworteingabe
# =========================================

konfiguriere_vconsole_fuer_initramfs() {
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

# =========================================
# ⚙️ mkinitcpio Hooks setzen
# -----------------------------------------
# Konfiguriert initramfs für Standard/LUKS
# → falsche Hooks verhindern Root-Mount
# =========================================

konfiguriere_mkinitcpio() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde mkinitcpio konfigurieren"
    return 0
  fi

  local conf="/mnt/etc/mkinitcpio.conf"

  guard_require_var ROOT_DEVICE

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard keymap consolefont encrypt filesystems fsck)/' "$conf"
  else
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard keymap consolefont filesystems fsck)/' "$conf"
  fi
}

# =========================================
# 💥 initramfs bauen
# -----------------------------------------
# Erstellt initramfs für installierte Kernel
# → fehlendes Image macht System unbootbar
# =========================================

baue_initramfs() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde mkinitcpio -P ausführen"
    return 0
  fi

  log "Baue initramfs..."

  run_cmd arch-chroot /mnt mkinitcpio -P

  [[ -f /mnt/boot/initramfs-linux.img ]] || {
    error "initramfs fehlt → System nicht bootfähig"
    exit 1
  }

  success "initramfs erstellt."
}

# =========================================
# 💾 Limine EFI installieren
# -----------------------------------------
# Kopiert BOOTX64.EFI auf die EFI-Partition
# → Voraussetzung für UEFI-Fallback-Boot
# =========================================

installiere_limine_efi() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Limine installieren"
    return 0
  fi

  local src="/mnt/usr/share/limine/BOOTX64.EFI"
  local target="/mnt/boot/EFI/BOOT/BOOTX64.EFI"

  [[ -f "$src" ]] || {
    error "Limine EFI nicht gefunden"
    exit 1
  }

  mkdir -p "$(dirname "$target")"

  run_cmd cp "$src" "$target"
}

# =========================================
# 🔍 Memtest erkennen
# -----------------------------------------
# Sucht installierte Memtest-EFI-Datei
# → optionaler Recovery-/Diagnose-Eintrag
# =========================================

pruefe_memtest() {
  MEMTEST_PATH=""

  local found
  found="$(find /mnt -iname "memtest*.efi" 2>/dev/null | head -n1 || true)"

  [[ -n "$found" ]] && MEMTEST_PATH="${found#/mnt}"

  export MEMTEST_PATH
}

# =========================================
# 🔎 Root UUID ermitteln
# -----------------------------------------
# Nutzt bei LUKS die Basispartition,
# sonst das Root-Dateisystem
# =========================================

get_root_uuid() {
  local uuid=""

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    guard_require_var ROOT_BASE_DEVICE
    uuid="$(blkid -s UUID -o value "$ROOT_BASE_DEVICE")"
  else
    guard_require_var ROOT_DEVICE
    uuid="$(blkid -s UUID -o value "$ROOT_DEVICE")"
  fi

  [[ -n "$uuid" ]] || {
    error "Root UUID fehlt"
    exit 1
  }

  echo "$uuid"
}

# =========================================
# 🧠 Kernel-Cmdline bauen
# -----------------------------------------
# Erstellt Root-/LUKS-Bootparameter
# → falsche Cmdline verhindert Boot
# =========================================

build_cmdline() {
  local root_uuid
  root_uuid="$(get_root_uuid)"

  [[ -n "$root_uuid" ]] || {
    error "ROOT UUID fehlt"
    exit 1
  }

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    local crypt_uuid
    crypt_uuid="$(blkid -s UUID -o value "$ROOT_BASE_DEVICE")"

    echo "cryptdevice=UUID=${crypt_uuid}:${ROOT_MAPPER_NAME} root=/dev/mapper/${ROOT_MAPPER_NAME} rootflags=subvol=@ rw"
  else
    echo "root=UUID=${root_uuid} rootflags=subvol=@ rw"
  fi
}

# =========================================
# 📝 Limine-Konfiguration schreiben
# -----------------------------------------
# Erstellt Bootmenü für Linux, LTS und Memtest
# → zentrale Boot-Konfiguration
# =========================================

erstelle_limine_config() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde limine.conf erstellen"
    return 0
  fi

  local cmdline
  cmdline="$(build_cmdline)"

  mkdir -p /mnt/boot/limine

  cat > /mnt/boot/limine.conf <<EOF
timeout: 5

/Arch Linux
    protocol: linux
    kernel_path: boot():/vmlinuz-linux
    module_path: boot():/initramfs-linux.img
    cmdline: ${cmdline}

/Arch Linux LTS
    protocol: linux
    kernel_path: boot():/vmlinuz-linux-lts
    module_path: boot():/initramfs-linux-lts.img
    cmdline: ${cmdline}
EOF

  if [[ -n "$MEMTEST_PATH" ]]; then
    cat >> /mnt/boot/limine.conf <<EOF

/Memtest86+
    protocol: efi
    path: boot():${MEMTEST_PATH}
EOF
  fi
}

# =========================================
# 🔥 Boot-Setup validieren
# -----------------------------------------
# Prüft Kernel, initramfs und EFI-Bootloader
# → letzter Stop vor unbootbarem System
# =========================================

validiere_boot_setup() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    return 0
  fi

  [[ -f /mnt/boot/vmlinuz-linux ]] || {
    error "Kernel fehlt → System nicht bootfähig"
    exit 1
  }

  [[ -f /mnt/boot/initramfs-linux.img ]] || {
    error "initramfs fehlt → System nicht bootfähig"
    exit 1
  }

  [[ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ]] || {
    error "EFI Bootloader fehlt"
    exit 1
  }

  success "Boot validiert."
}
