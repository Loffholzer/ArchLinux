#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      04_base.sh
# Zweck:     Bootstrapping des Grundsystems
#
# Aufgabe:
# - Mount-Layout für Limine+LUKS optimieren
# - Grundsystem, Kernel und Tools via pacstrap installieren
# - FSTAB generieren und für Snapper (BTRFS) patchen
#
# Wichtig:
# - Die ESP wird bei LUKS nach /boot gemountet
# - Entfernt zwingend subvolid aus der fstab
# =========================================

# =========================================
# 🔀 Funktion: base_boot_layout
# -----------------------------------------
# Zweck:    Sichert die Limine-Kompatibilität
# Aufgabe:  Mountet ESP nach /boot bei LUKS-Setups
# =========================================
base_boot_layout() {
    phase_header "Boot-Layout evaluieren"

    if [[ "$USE_LUKS" == "yes" ]]; then
        log "LUKS-Profil aktiv: Optimiere Mount-Point für Limine."

        if [[ "${DRY_RUN:-true}" == true ]]; then
            warn "[DRY-RUN] Remount ESP von /boot/efi nach /boot übersprungen."
        else
            log "Hänge ESP von /mnt/boot/efi aus..."
            umount /mnt/boot/efi 2>/dev/null || true

            log "Mounte ESP direkt nach /mnt/boot..."
            mkdir -p /mnt/boot
            mount "$PART_EFI" /mnt/boot
            success "ESP ist nun unter /mnt/boot gemountet (Kernel wird unverschlüsselt abgelegt)."
        fi
    else
        log "Standard-Profil aktiv: /mnt/boot/efi bleibt erhalten (Limine liest Kernel aus BTRFS)."
    fi
}

# =========================================
# 📥 Funktion: base_pacstrap
# -----------------------------------------
# Zweck:    Installation des Kernsystems
# Aufgabe:  Lädt Pakete in die chroot-Umgebung
# =========================================
base_pacstrap() {
    phase_header "Pacstrap: Grundsystem installieren"

    local base_pkgs=(
        base base-devel
        linux linux-headers linux-lts linux-lts-headers
        linux-firmware "$MICROCODE_PKG"
        btrfs-progs
        networkmanager
        sudo neovim git curl wget
        cryptsetup lvm2 # Zwingend für LUKS-Hooks
        terminus-font   # FIX: Wird zwingend für den consolefont-Hook im mkinitcpio benötigt
    )

    log "Installiere folgende Pakete:"
    echo -e "${CYAN}${base_pkgs[*]}${NC}\n"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] pacstrap wird übersprungen."
        return 0
    fi

    # FIX: Verhindere den 'vconsole.conf not found' Fehler beim automatischen mkinitcpio-Lauf
    log "Bereite Dummy-Configs für pacstrap-Hooks vor..."
    mkdir -p /mnt/etc
    touch /mnt/etc/vconsole.conf

    # pacstrap ausführen
    pacstrap -K /mnt "${base_pkgs[@]}" || {
        error "Pacstrap fehlgeschlagen. Netzwerkverbindung oder Mirrorlist prüfen."
        exit 1
    }

    success "Grundsystem erfolgreich installiert."
}

# =========================================
# 📝 Funktion: base_fstab
# -----------------------------------------
# Zweck:    Generiert die Dateisystem-Tabelle
# Aufgabe:  Nutzt UUIDs und patcht subvolid für Snapper
# =========================================
base_fstab() {
    phase_header "FSTAB generieren & patchen"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] genfstab wird übersprungen."
        return 0
    fi

    log "Generiere fstab (UUID-basiert)..."
    genfstab -U /mnt > /mnt/etc/fstab || {
        error "FSTAB konnte nicht generiert werden."
        exit 1
    }

    log "Optimiere fstab für BTRFS-Rollbacks (Entferne subvolid)..."
    sed -i 's/subvolid=[0-9]*,//g' /mnt/etc/fstab
    sed -i 's/,subvolid=[0-9]*//g' /mnt/etc/fstab

    # FSTAB-Ausgabe ins Log zur Validierung
    echo
    cat /mnt/etc/fstab
    echo

    success "FSTAB erfolgreich erstellt und gepatcht."
}

# =========================================
# ⚙️ Modul-Einstiegspunkt: run_base
# -----------------------------------------
# Zweck:    Sequenzielle Ausführung
# =========================================
run_base() {
    header "Phase 4: Base System (Pacstrap)"

    base_boot_layout
    base_pacstrap
    base_fstab
}

