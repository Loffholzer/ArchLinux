#!/usr/bin/env bash

# =========================================
# 08_bootloader.sh
# -----------------------------------------
# Aufgabe:
# - installiert Limine
# - richtet EFI Boot ein
# - erstellt minimale limine.conf
#
# Wichtig:
# - kein Snapshot-Bootmenü
# - Snapshot-Integration folgt später separat
# =========================================

# =========================
# 🚀 Bootloader Setup ausführen
# =========================

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
  erstelle_limine_config

  success "Bootloader eingerichtet."
}

# =========================
# 🔒 Checks
# =========================

pruefe_bootloader_variablen() {
  [[ -n "${EFI_PART:-}" ]] || { error "EFI_PART fehlt."; exit 1; }
  [[ -n "${ROOT_DEVICE:-}" ]] || { error "ROOT_DEVICE fehlt."; exit 1; }

  if [[ "${DRY_RUN:-true}" != true ]]; then
    [[ -b "$EFI_PART" ]] || { error "$EFI_PART ist kein Blockdevice."; exit 1; }
    [[ -b "$ROOT_DEVICE" ]] || { error "$ROOT_DEVICE ist kein Blockdevice."; exit 1; }
    mountpoint -q /mnt || { error "/mnt ist nicht gemountet."; exit 1; }
  fi
}

# =========================
# 📋 Plan anzeigen
# =========================

zeige_bootloader_plan() {
  header "Geplanter Bootloader"

  echo "Bootloader:    Limine"
  echo "EFI-Partition: $EFI_PART"
  echo "Root-Gerät:    $ROOT_DEVICE"
  echo "Mountpoint:    /boot"
  echo
  echo "Boot-Menü:"
  echo "  - Arch Linux"
  echo "  - Arch Linux LTS"
  echo "  - Memtest86+"
  echo "  - Snapshots (Platzhalter)"
  echo
  echo "Design:"
  echo "  - Hintergrundbild später: /boot/limine/background.png"
  echo

  warn "Dieses Modul richtet die vollständige Bootchain ein."
  warn "Snapshot-Boot-Einträge werden später durch Modul 10 generiert."
  echo
}

# =========================
# 📂 EFI Mounten
# =========================

mounte_efi() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde EFI nach /mnt/boot mounten"
    return 0
  fi

  if mountpoint -q /mnt/boot; then
    log "/mnt/boot ist bereits gemountet, überspringe."
    return 0
  fi

  log "Mounte EFI-Partition..."

  mkdir -p /mnt/boot

  mount "$EFI_PART" /mnt/boot || {
    error "EFI-Partition konnte nicht gemountet werden."
    exit 1
  }

  success "EFI gemountet: /mnt/boot"
}

# =========================
# 💾 Limine EFI-Dateien installieren
# =========================

installiere_limine_efi() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Limine EFI-Dateien installieren (inkl. Fallback BOOTX64.EFI)"
    warn "[DRY-RUN] würde splash.jpg nach /mnt/boot/limine/ kopieren"
    return 0
  fi

  log "Installiere Limine EFI-Dateien..."

  local boot_dir="/mnt/boot/EFI/BOOT"
  local limine_dir="/mnt/boot/limine"
  local limine_src="/mnt/usr/share/limine/BOOTX64.EFI"
  local splash_src="${SCRIPT_DIR}/splash.jpg"

  [[ -f "$limine_src" ]] || {
    error "Limine EFI-Datei nicht gefunden: $limine_src"
    exit 1
  }

  mkdir -p "$boot_dir"
  mkdir -p "$limine_dir"

  cp "$limine_src" "${boot_dir}/BOOTX64.EFI" || {
    error "Limine BOOTX64.EFI konnte nicht kopiert werden."
    exit 1
  }

  # Splash-Bild kopieren
  if [[ -f "$splash_src" ]]; then
    cp "$splash_src" "${limine_dir}/splash.jpg" || warn "Konnte splash.jpg nicht kopieren."
    success "Limine Splash-Image installiert."
  else
    warn "splash.jpg nicht gefunden in: $splash_src"
  fi

  success "Limine EFI installiert: /boot/EFI/BOOT/BOOTX64.EFI"
}

# =========================
# 📝 Limine-Konfiguration erstellen
# =========================

erstelle_limine_config() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde limine.conf mit Arch, Arch LTS, Memtest und Snapshot-Block erstellen"
    return 0
  fi

  local root_uuid
  local cmdline

  root_uuid="$(blkid -s UUID -o value "$ROOT_DEVICE" 2>/dev/null || true)"

  [[ -n "$root_uuid" ]] || {
    error "UUID für ROOT_DEVICE konnte nicht ermittelt werden."
    exit 1
  }

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    local crypt_uuid

    [[ -n "${ROOT_BASE_DEVICE:-}" ]] || {
      error "ROOT_BASE_DEVICE fehlt für LUKS-Boot."
      exit 1
    }

    crypt_uuid="$(blkid -s UUID -o value "$ROOT_BASE_DEVICE" 2>/dev/null || true)"

    [[ -n "$crypt_uuid" ]] || {
      error "UUID für ROOT_BASE_DEVICE konnte nicht ermittelt werden."
      exit 1
    }

    cmdline="cryptdevice=UUID=${crypt_uuid}:${ROOT_MAPPER_NAME} root=/dev/mapper/${ROOT_MAPPER_NAME} rootflags=subvol=@ rw"
  else
    cmdline="root=UUID=${root_uuid} rootflags=subvol=@ rw"
  fi

  [[ -f /mnt/boot/vmlinuz-linux ]] || {
    error "Kernel fehlt: /mnt/boot/vmlinuz-linux"
    exit 1
  }

  [[ -f /mnt/boot/initramfs-linux.img ]] || {
    error "Initramfs fehlt: /mnt/boot/initramfs-linux.img"
    exit 1
  }

  [[ -f /mnt/boot/vmlinuz-linux-lts ]] || {
    error "LTS-Kernel fehlt: /mnt/boot/vmlinuz-linux-lts"
    exit 1
  }

  [[ -f /mnt/boot/initramfs-linux-lts.img ]] || {
    error "LTS-Initramfs fehlt: /mnt/boot/initramfs-linux-lts.img"
    exit 1
  }

  pruefe_memtest

  log "Erstelle limine.conf..."

  mkdir -p /mnt/boot/limine

  schreibe_limine_config_datei "$cmdline"

  success "limine.conf erstellt."
}

# =========================
# 📦 Kernel & Boottools installieren
# =========================

installiere_kernel_und_boottools() {
  local packages=(
    linux
    linux-lts
    linux-firmware
    memtest86+-efi
    limine
    terminus-font
  )

  [[ -n "$MICROCODE_PKG" ]] && packages+=("$MICROCODE_PKG")

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Kernel, Boottools und Konsolen-Font installieren:"
    warn "  ${packages[*]}"
    return 0
  fi

  log "Installiere Kernel, Boottools, Konsolen-Font und Microcode ($MICROCODE_PKG)..."

  arch-chroot /mnt pacman -S --noconfirm "${packages[@]}" || {
      error "Kernel/Boottools konnten nicht installiert werden."
      exit 1
  }

  success "Kernel, Boottools und Konsolen-Font installiert."
}

# =========================
# ⚙️ initramfs erstellen
# =========================

baue_initramfs() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde mkinitcpio -P ausführen"
    return 0
  fi

  log "Erstelle initramfs..."

  arch-chroot /mnt mkinitcpio -P || {
    error "mkinitcpio fehlgeschlagen."
    exit 1
  }

  success "initramfs erstellt."
}

# =========================
# 🖥️ TTY / Konsolen-Font (initramfs)
# =========================

konfiguriere_vconsole_fuer_initramfs() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde vconsole vor initramfs setzen: KEYMAP=${KEYMAP}, FONT=${CONSOLE_FONT:-standard}"
    return 0
  fi

  [[ -n "${KEYMAP:-}" ]] || {
    error "KEYMAP fehlt."
    exit 1
  }

  log "Setze vconsole vor initramfs-Erstellung..."

  cat > /mnt/etc/vconsole.conf <<EOF
KEYMAP=${KEYMAP}
FONT=${CONSOLE_FONT:-ter-v32n}
EOF
}

# =========================
# ⚙️ mkinitcpio konfigurieren
# =========================

konfiguriere_mkinitcpio() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde mkinitcpio HOOKS konfigurieren"

    if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
      warn "[DRY-RUN] LUKS erkannt: HOOKS mit encrypt und consolefont"
    else
      warn "[DRY-RUN] Kein LUKS erkannt: HOOKS mit consolefont"
    fi

    return 0
  fi

  local conf="/mnt/etc/mkinitcpio.conf"

  [[ -f "$conf" ]] || {
    error "mkinitcpio.conf nicht gefunden: $conf"
    exit 1
  }

  log "Konfiguriere mkinitcpio HOOKS..."

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard keymap consolefont encrypt filesystems fsck)/' "$conf" || {
      error "mkinitcpio HOOKS konnten nicht gesetzt werden."
      exit 1
    }
  else
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard keymap consolefont filesystems fsck)/' "$conf" || {
      error "mkinitcpio HOOKS konnten nicht gesetzt werden."
      exit 1
    }
  fi

  success "mkinitcpio HOOKS konfiguriert."
}

# =========================
# 🧠 Memtest prüfen
# =========================

pruefe_memtest() {
  MEMTEST_PATH=""

  local paths=(
    "/mnt/boot/memtest86+/memtest.efi"
    "/mnt/boot/EFI/memtest86+/memtest.efi"
    "/mnt/usr/lib/memtest86+/memtest.efi"
    "/mnt/usr/share/memtest86+/memtest.efi"
  )

  local path

  for path in "${paths[@]}"; do
    if [[ -f "$path" ]]; then
      MEMTEST_PATH="${path#/mnt}"
      export MEMTEST_PATH
      success "Memtest gefunden: ${MEMTEST_PATH}"
      return 0
    fi
  done

  warn "Memtest nicht gefunden. Memtest-Eintrag wird übersprungen."
  export MEMTEST_PATH
  return 0
}

# =========================
# 📝 Limine-Konfiguration schreiben
# =========================

schreibe_limine_config_datei() {
  local cmdline="$1"
  local ucode_img=""

  # Bestimme das passende Image basierend auf der CPU-Erkennung aus Modul 00
  [[ "$MICROCODE_PKG" == "intel-ucode" ]] && ucode_img="boot():/intel-ucode.img"
  [[ "$MICROCODE_PKG" == "amd-ucode" ]] && ucode_img="boot():/amd-ucode.img"

  cat > /mnt/boot/limine.conf <<EOF

timeout: 5
remember_last_entry: yes
graphics: yes
wallpaper: boot():/limine/splash.jpg
wallpaper_style: stretched
TERM_FOREGROUND=ccffffff
TERM_FOREGROUND_BRIGHT=ffffcc00
TERM_BACKGROUND=00000000
interface_branding: Arch Linux

/Arch Linux
    protocol: linux
    kernel_path: boot():/vmlinuz-linux
EOF

  # Microcode-Modul nur hinzufügen, wenn erkannt
  [[ -n "$ucode_img" ]] && echo "    module_path: ${ucode_img}" >> /mnt/boot/limine.conf

  cat >> /mnt/boot/limine.conf <<EOF
    module_path: boot():/initramfs-linux.img
    cmdline: ${cmdline}

/Arch Linux LTS
    protocol: linux
    kernel_path: boot():/vmlinuz-linux-lts
EOF

  [[ -n "$ucode_img" ]] && echo "    module_path: ${ucode_img}" >> /mnt/boot/limine.conf

  cat >> /mnt/boot/limine.conf <<EOF
    module_path: boot():/initramfs-linux-lts.img
    cmdline: ${cmdline}
EOF

  if [[ -n "${MEMTEST_PATH:-}" ]]; then
    cat >> /mnt/boot/limine.conf <<EOF

/Memtest86+
    protocol: efi
    path: boot():${MEMTEST_PATH}
EOF
  fi

  cat >> /mnt/boot/limine.conf <<EOF

#+SNAPSHOT_ENTRIES_BEGIN
/Snapshots
    comment: Bootfähige Snapshots werden später von 10_snapshot_boot.sh generiert.
#+SNAPSHOT_ENTRIES_END
EOF
}
