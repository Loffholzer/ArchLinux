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
    guard_mnt_valid_root
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
# und Konsolenfont für initramfs
# → verhindert consolefont/sd-vconsole Fehler
# =========================================

installiere_kernel_und_boottools() {
  local packages=(
    terminus-font
    linux
    linux-lts
    linux-firmware
    limine
    memtest86+-efi
  )

  [[ -n "${MICROCODE_PKG:-}" ]] && packages+=("$MICROCODE_PKG")

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde installieren: ${packages[*]}"
    return 0
  fi

  run_cmd arch-chroot /mnt pacman -S --noconfirm "${packages[@]}"

  [[ -f /mnt/usr/share/kbd/consolefonts/ter-v28n.psf.gz ]] || {
    error "Konsolenfont ter-v28n fehlt trotz terminus-font Installation"
    exit 1
  }
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
# Konfiguriert initramfs für Standard/LUKS,
# Tastatur und BTRFS
# → falsche Hooks verhindern den Boot
# =========================================

konfiguriere_mkinitcpio() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde mkinitcpio konfigurieren"
    return 0
  fi

  local conf="/mnt/etc/mkinitcpio.conf"

  guard_require_var ROOT_DEVICE

  [[ -f "$conf" ]] || {
    error "mkinitcpio.conf fehlt: $conf"
    exit 1
  }

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' "$conf"
  else
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)/' "$conf"
  fi

  grep -q '^HOOKS=' "$conf" || {
    error "HOOKS wurden nicht in mkinitcpio.conf gesetzt"
    exit 1
  }

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    grep -q 'encrypt' "$conf" || {
      error "mkinitcpio HOOKS enthalten kein encrypt für LUKS"
      exit 1
    }
  fi

  grep -q 'keyboard' "$conf" || {
    error "mkinitcpio HOOKS enthalten kein keyboard"
    exit 1
  }

  grep -q 'filesystems' "$conf" || {
    error "mkinitcpio HOOKS enthalten kein filesystems"
    exit 1
  }

  success "mkinitcpio Hooks gesetzt."
}

# =========================================
# 💥 initramfs bauen
# -----------------------------------------
# Erstellt initramfs für alle installierten
# Kernel und validiert die Bootartefakte
# → fehlende Images machen das System unbootbar
# =========================================

baue_initramfs() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde mkinitcpio -P ausführen"
    return 0
  fi

  guard_mnt_valid_root

  log "Baue initramfs..."

  run_cmd arch-chroot /mnt mkinitcpio -P

  [[ -f /mnt/boot/initramfs-linux.img ]] || {
    error "initramfs-linux.img fehlt → System nicht bootfähig"
    exit 1
  }

  [[ -f /mnt/boot/initramfs-linux-lts.img ]] || {
    error "initramfs-linux-lts.img fehlt → LTS-Boot nicht möglich"
    exit 1
  }

  [[ -s /mnt/boot/initramfs-linux.img ]] || {
    error "initramfs-linux.img ist leer → System nicht bootfähig"
    exit 1
  }

  [[ -s /mnt/boot/initramfs-linux-lts.img ]] || {
    error "initramfs-linux-lts.img ist leer → LTS-Boot nicht möglich"
    exit 1
  }

  success "initramfs erstellt und validiert."
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
# Baut Root-/LUKS-Parameter strikt validiert
# → verhindert Boot-Fail durch falsche UUID
# =========================================

build_cmdline() {
  local root_uuid

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    guard_require_var ROOT_BASE_DEVICE
    guard_require_var ROOT_MAPPER_NAME

    root_uuid="$(blkid -s UUID -o value "$ROOT_BASE_DEVICE")"

    [[ -n "$root_uuid" ]] || {
      error "LUKS UUID fehlt"
      exit 1
    }

    echo "cryptdevice=UUID=${root_uuid}:${ROOT_MAPPER_NAME} root=/dev/mapper/${ROOT_MAPPER_NAME} rootflags=subvol=@ rw"
  else
    guard_require_var ROOT_DEVICE

    root_uuid="$(blkid -s UUID -o value "$ROOT_DEVICE")"

    [[ -n "$root_uuid" ]] || {
      error "Root UUID fehlt"
      exit 1
    }

    echo "root=UUID=${root_uuid} rootflags=subvol=@ rw"
  fi
}

# =========================================
# 📝 Limine-Konfiguration schreiben
# -----------------------------------------
# Erstellt Bootmenü inkl. Microcode und
# Snapshot-Marker
# → Hauptboot bleibt stabil und erweiterbar
# =========================================

erstelle_limine_config() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde limine.conf erstellen"
    return 0
  fi

  local cmdline
  local microcode_path=""

  cmdline="$(build_cmdline)"

  if [[ "${MICROCODE_PKG:-}" == "intel-ucode" ]]; then
    microcode_path="/intel-ucode.img"
  elif [[ "${MICROCODE_PKG:-}" == "amd-ucode" ]]; then
    microcode_path="/amd-ucode.img"
  fi

  mkdir -p /mnt/boot/limine

  cat > /mnt/boot/limine.conf <<EOF
timeout: 5

/Arch Linux
    protocol: linux
    kernel_path: boot():/vmlinuz-linux
EOF

  if [[ -n "$microcode_path" ]]; then
    cat >> /mnt/boot/limine.conf <<EOF
    module_path: boot():${microcode_path}
EOF
  fi

  cat >> /mnt/boot/limine.conf <<EOF
    module_path: boot():/initramfs-linux.img
    cmdline: ${cmdline}

/Arch Linux LTS
    protocol: linux
    kernel_path: boot():/vmlinuz-linux-lts
EOF

  if [[ -n "$microcode_path" ]]; then
    cat >> /mnt/boot/limine.conf <<EOF
    module_path: boot():${microcode_path}
EOF
  fi

  cat >> /mnt/boot/limine.conf <<EOF
    module_path: boot():/initramfs-linux-lts.img
    cmdline: ${cmdline}

#+SNAPSHOT_ENTRIES_BEGIN
/Snapshots
    //Keine Snapshots vorhanden
#+SNAPSHOT_ENTRIES_END
EOF

  if [[ -n "${MEMTEST_PATH:-}" ]]; then
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
# Prüft Kernel, initramfs, EFI, Microcode
# und Limine-Konfiguration
# → verhindert unbootbares System
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

  [[ -f /mnt/boot/vmlinuz-linux-lts ]] || {
    error "LTS Kernel fehlt"
    exit 1
  }

  [[ -f /mnt/boot/initramfs-linux-lts.img ]] || {
    error "LTS initramfs fehlt"
    exit 1
  }

  if [[ "${MICROCODE_PKG:-}" == "intel-ucode" ]]; then
    [[ -f /mnt/boot/intel-ucode.img ]] || {
      error "Intel Microcode fehlt in /boot"
      exit 1
    }
  elif [[ "${MICROCODE_PKG:-}" == "amd-ucode" ]]; then
    [[ -f /mnt/boot/amd-ucode.img ]] || {
      error "AMD Microcode fehlt in /boot"
      exit 1
    }
  fi

  [[ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ]] || {
    error "EFI Bootloader fehlt"
    exit 1
  }

  [[ -f /mnt/boot/limine.conf ]] || {
    error "limine.conf fehlt"
    exit 1
  }

  grep -q "protocol: linux" /mnt/boot/limine.conf || {
    error "limine.conf enthält keine Linux-Einträge"
    exit 1
  }

  grep -q "rootflags=subvol=@" /mnt/boot/limine.conf || {
    error "limine.conf enthält kein rootflags=subvol=@"
    exit 1
  }

  grep -q '^#+SNAPSHOT_ENTRIES_BEGIN$' /mnt/boot/limine.conf || {
    error "Snapshot-Block BEGIN fehlt in limine.conf"
    exit 1
  }

  grep -q '^#+SNAPSHOT_ENTRIES_END$' /mnt/boot/limine.conf || {
    error "Snapshot-Block END fehlt in limine.conf"
    exit 1
  }

  success "Boot validiert."
}
