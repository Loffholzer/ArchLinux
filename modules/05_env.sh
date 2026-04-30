#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      05_env.sh
# Zweck:     Chroot-Konfiguration & Bootloader
#
# Aufgabe:
# - Systemzeit, Locales, Hostname und Netzwerk setzen
# - mkinitcpio für LUKS und BTRFS konfigurieren
# - Limine (Bootloader) installieren und einrichten
#
# Wichtig:
# - Alle Systembefehle laufen via chroot im Zielsystem
# - Dynamische Limine-Pfadgenerierung je nach Profil
# =========================================

# =========================================
# 🏗️ Funktion: env_chroot_basics
# -----------------------------------------
# Zweck:    Grundkonfiguration des Zielsystems
# Aufgabe:  Timezone, HW-Clock, Locales, Hostname
# =========================================
env_chroot_basics() {
    phase_header "Chroot: Basics konfigurieren"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Chroot-Basis-Setup übersprungen."
        return 0
    fi

    log "Setze Timezone ($TIMEZONE) und Locales..."

    # Befehle werden via Here-Doc in die chroot gepumpt
    arch-chroot /mnt /bin/bash <<EOF
        # 1. Timezone
        ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
        hwclock --systohc

        # 2. Locales
        # Aktiviert alle gewählten Locales in locale.gen
        sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
        if [[ "$LANG_DEFAULT" != "en_US.UTF-8" ]]; then
            sed -i "s/^#\($LANG_DEFAULT UTF-8\)/\1/" /etc/locale.gen
        fi
        locale-gen >/dev/null

        # Setzt Standardsprache
        echo "LANG=$LANG_DEFAULT" > /etc/locale.conf

        # 3. vconsole (Tastaturlayout und Font in der TTY)
        echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
        echo "FONT=$CONSOLE_FONT" >> /etc/vconsole.conf

        # 4. Hostname
        echo "$HOSTNAME" > /etc/hostname

        # 5. Hosts-Datei
        cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS
EOF

    success "Basiskonfiguration im Zielsystem abgeschlossen."
}

# =========================================
# 🛠️ Funktion: env_initramfs
# -----------------------------------------
# Zweck:    Kernel-Images für den Boot generieren
# Aufgabe:  Hook-Reihenfolge in mkinitcpio.conf setzen
# =========================================
env_initramfs() {
    phase_header "Chroot: Initramfs (mkinitcpio)"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] mkinitcpio-Konfiguration übersprungen."
        return 0
    fi

    local hooks="base udev autodetect microcode modconf kms keyboard keymap consolefont block"

    if [[ "$USE_LUKS" == "yes" ]]; then
        log "LUKS-Profil: Füge 'encrypt' Hook hinzu."
        hooks="$hooks encrypt"
    fi

    # filesystems und fsck ans Ende
    hooks="$hooks filesystems fsck"
    log "Definierte Hooks: $hooks"

    arch-chroot /mnt /bin/bash <<EOF
        # Schreibe Hooks in die Config
        sed -i "s/^HOOKS=(.*/HOOKS=($hooks)/" /etc/mkinitcpio.conf

        # Initramfs generieren
        mkinitcpio -P >/dev/null
EOF

    success "Initramfs Images erfolgreich generiert."
}

# =========================================
# 🚀 Funktion: env_bootloader
# -----------------------------------------
# Zweck:    Limine Bootloader Setup
# Aufgabe:  Konfiguration schreiben und in ESP pushen
# =========================================
env_bootloader() {
    phase_header "Chroot: Limine Bootloader"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Limine-Setup übersprungen."
        return 0
    fi

    # Ermittle UUID der physikalischen Partition für den Kernel-Parameter
    local root_uuid
    root_uuid=$(blkid -s UUID -o value "$PART_ROOT")

    log "Installiere Limine Paket..."
    arch-chroot /mnt pacman -S --noconfirm limine >/dev/null

    log "Generiere limine.conf..."
    # Pfade und CMDLINE dynamisch je nach LUKS-Status anpassen
    local limine_conf="/mnt/boot/limine.conf"
    if [[ "$USE_LUKS" == "yes" ]]; then
        # LUKS: conf liegt in /boot (welches unsere ESP ist)
        # Kernel ist im Root der ESP
        cat <<EOF > "$limine_conf"
TIMEOUT=3
REMEMBER_LAST_ENTRY=yes
DEFAULT_ENTRY=1

:Arch Linux (Mainline)
    PROTOCOL=linux
    KERNEL_PATH=boot:///vmlinuz-linux
    MODULE_PATH=boot:///initramfs-linux.img
    CMDLINE=cryptdevice=UUID=${root_uuid}:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet splash

:Arch Linux (LTS)
    PROTOCOL=linux
    KERNEL_PATH=boot:///vmlinuz-linux-lts
    MODULE_PATH=boot:///initramfs-linux-lts.img
    CMDLINE=cryptdevice=UUID=${root_uuid}:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet splash
EOF
    else
        # Standard: conf liegt in /boot/efi (unsere ESP)
        # Kernel liegt auf BTRFS
        limine_conf="/mnt/boot/efi/limine.conf"
        cat <<EOF > "$limine_conf"
TIMEOUT=3
REMEMBER_LAST_ENTRY=yes
DEFAULT_ENTRY=1

:Arch Linux (Mainline)
    PROTOCOL=linux
    KERNEL_PATH=uuid://${root_uuid}/@/boot/vmlinuz-linux
    MODULE_PATH=uuid://${root_uuid}/@/boot/initramfs-linux.img
    CMDLINE=root=UUID=${root_uuid} rootflags=subvol=@ rw quiet splash

:Arch Linux (LTS)
    PROTOCOL=linux
    KERNEL_PATH=uuid://${root_uuid}/@/boot/vmlinuz-linux-lts
    MODULE_PATH=uuid://${root_uuid}/@/boot/initramfs-linux-lts.img
    CMDLINE=root=UUID=${root_uuid} rootflags=subvol=@ rw quiet splash
EOF
    fi

    log "Kopiere UEFI-Bootfiles..."
    arch-chroot /mnt /bin/bash <<EOF
        # Die ESP ist unter /boot (LUKS) oder /boot/efi (Standard) gemountet
        esp_path=\$(findmnt -n -o TARGET /dev/disk/by-uuid/\$(blkid -s UUID -o value "$PART_EFI"))

        mkdir -p "\$esp_path/EFI/BOOT"
        cp /usr/share/limine/BOOTX64.EFI "\$esp_path/EFI/BOOT/"

        # Wenn efibootmgr existiert, trage Limine ins UEFI ein
        if command -v efibootmgr >/dev/null; then
            efibootmgr --create --disk "$DISK" --part 1 --loader /EFI/BOOT/BOOTX64.EFI --label "Arch Linux (Limine)" >/dev/null 2>&1 || true
        fi
EOF

    success "Limine Bootloader erfolgreich installiert."
}

# =========================================
# ⚙️ Modul-Einstiegspunkt: run_env
# -----------------------------------------
# Zweck:    Sequenzielle Ausführung
# =========================================
run_env() {
    header "Phase 5: Zielsystem-Umgebung"

    env_chroot_basics
    env_initramfs
    env_bootloader
}
