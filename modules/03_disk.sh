#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      03_disk.sh
# Zweck:     Partitionierung, LUKS & Dateisysteme
#
# Aufgabe:
# - Laufwerk bereinigen und layouten (sgdisk)
# - LUKS2-Container erstellen (falls Profil = luks)
# - BTRFS formatieren und Subvolumes anlegen
# - Mount-Point-Struktur unter /mnt aufbauen
#
# Wichtig:
# - Zerstört unwiderruflich Daten auf $DISK
# - Setzt SSD/HDD-spezifische BTRFS Mount-Optionen
# =========================================

# =========================================
# 🧮 Funktion: get_partitions
# -----------------------------------------
# Zweck:    Dynamische Partitionsnamen ermitteln
# Aufgabe:  Unterscheidet NVMe/MMC ("p1") und SATA ("1")
# =========================================
get_partitions() {
    local suffix=""
    if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* || "$DISK" == *loop* ]]; then
        suffix="p"
    fi

    PART_EFI="${DISK}${suffix}1"
    PART_ROOT="${DISK}${suffix}2"

    export PART_EFI PART_ROOT
}

# =========================================
# 🧹 Funktion: disk_unmount_all
# -----------------------------------------
# Zweck:    Vorherige Installationen freigeben
# Aufgabe:  Unmountet /mnt rekursiv und schließt LUKS
# =========================================
disk_unmount_all() {
    phase_header "Laufwerk freigeben"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Unmount-Schritte übersprungen."
        return 0
    fi

    log "Hänge eventuell gemountete Dateisysteme unter /mnt aus..."
    umount -R /mnt 2>/dev/null || true

    log "Schließe eventuell offene LUKS-Container (cryptroot)..."
    cryptsetup close cryptroot 2>/dev/null || true

    success "Laufwerk ist bereit für den Zugriff."
}

# =========================================
# 🔪 Funktion: disk_partition
# -----------------------------------------
# Zweck:    Partitionstabelle neu schreiben
# Aufgabe:  Löscht Laufwerk, erstellt EFI (1GB) & Root (Rest)
# =========================================
disk_partition() {
    phase_header "Partitionierung ($DISK)"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Wipe & sgdisk auf $DISK übersprungen."
        return 0
    fi

    log "Lösche alte Dateisystem-Signaturen..."
    wipefs -a "$DISK" >/dev/null 2>&1 || warn "wipefs lieferte einen Fehler, setze fort."

    log "Schreibe neue GPT und Partitionen..."
    sgdisk -Z "$DISK" >/dev/null
    sgdisk -a 2048 -o "$DISK" >/dev/null

    # Partition 1: 1GB EFI System Partition (Hex: ef00)
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI" "$DISK" >/dev/null

    # Partition 2: Rest des Speichers für Root/LUKS (Hex: 8304)
    sgdisk -n 2:0:0 -t 2:8304 -c 2:"ROOT" "$DISK" >/dev/null

    partprobe "$DISK"
    sleep 2

    success "Partitionierung erfolgreich abgeschlossen."
}

# =========================================
# 🔐 Funktion: disk_luks
# -----------------------------------------
# Zweck:    Laufwerksverschlüsselung aufbauen
# Aufgabe:  Erstellt LUKS2 mit AES-256-XTS und öffnet Gerät
# =========================================
disk_luks() {
    if [[ "$USE_LUKS" != "yes" ]]; then
        log "Profil 'standard' aktiv: LUKS wird übersprungen."
        TARGET_ROOT="$PART_ROOT"
        export TARGET_ROOT
        return 0
    fi

    phase_header "LUKS Verschlüsselung ($PART_ROOT)"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] cryptsetup übersprungen."
        TARGET_ROOT="/dev/mapper/cryptroot"
        export TARGET_ROOT
        return 0
    fi

    log "Formatiere $PART_ROOT (LUKS2, AES-256-XTS)..."
    # echo -n piped das PW sicher in cryptsetup ohne interaktiven Prompt
    echo -n "$LUKS_PASSWORD" | cryptsetup -q -v \
        --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha256 \
        --iter-time 2000 \
        --use-random \
        luksFormat "$PART_ROOT" - || {
            error "LUKS Formatierung fehlgeschlagen."
            exit 1
        }

    log "Öffne LUKS-Container als 'cryptroot'..."
    echo -n "$LUKS_PASSWORD" | cryptsetup open "$PART_ROOT" cryptroot - || {
        error "Konnte LUKS-Container nicht öffnen."
        exit 1
    }

    success "LUKS-Container erstellt und geöffnet."
    TARGET_ROOT="/dev/mapper/cryptroot"
    export TARGET_ROOT
}

# =========================================
# 🗂️ Funktion: disk_format_and_subvols
# -----------------------------------------
# Zweck:    BTRFS formatieren und Struktur anlegen
# Aufgabe:  Subvolumes: @, @home, @snapshots, @var_log, @var_cache
# =========================================
disk_format_and_subvols() {
    phase_header "Dateisysteme & BTRFS-Subvolumes"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] mkfs und btrfs subvolume create übersprungen."
        return 0
    fi

    log "Formatiere EFI ($PART_EFI) mit FAT32..."
    # FIX: Korrekter Parameter für FAT32 ist '-F 32', nicht '-F3'
    mkfs.fat -F 32 -n ESP "$PART_EFI" >/dev/null || { error "FAT32 Formatierung fehlgeschlagen."; exit 1; }

    log "Formatiere ROOT ($TARGET_ROOT) mit BTRFS..."
    mkfs.btrfs -L ROOT -f "$TARGET_ROOT" >/dev/null || { error "BTRFS Formatierung fehlgeschlagen."; exit 1; }

    log "Erstelle temporären Mountpoint zur Subvolume-Erstellung..."
    mount "$TARGET_ROOT" /mnt

    log "Erstelle BTRFS Subvolumes..."
    btrfs subvolume create /mnt/@ >/dev/null
    btrfs subvolume create /mnt/@home >/dev/null
    btrfs subvolume create /mnt/@snapshots >/dev/null
    btrfs subvolume create /mnt/@var_log >/dev/null
    btrfs subvolume create /mnt/@var_cache >/dev/null

    umount /mnt
    success "Dateisysteme und Subvolumes erfolgreich erstellt."
}

# =========================================
# 🔗 Funktion: disk_mount
# -----------------------------------------
# Zweck:    Zielsystemstruktur unter /mnt aufbauen
# Aufgabe:  Ermittelt ROTA-Status und setzt Mount-Flags
# =========================================
disk_mount() {
    phase_header "Dateisysteme mounten (/mnt)"

    # Ermittle Speichertyp (0 = SSD/NVMe, 1 = HDD)
    local rota
    rota=$(lsblk -nd -o ROTA "$DISK" 2>/dev/null || echo "0")

    local mount_opts="rw,noatime,compress=zstd:3,space_cache=v2"

    if [[ "$rota" == "0" ]]; then
        log "SSD erkannt: Ergänze 'discard=async'."
        mount_opts="${mount_opts},ssd,discard=async"
    else
        log "HDD erkannt: Ergänze 'autodefrag'."
        mount_opts="${mount_opts},autodefrag"
    fi

    log "Verwendete BTRFS Mount-Optionen: $mount_opts"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Mounts unter /mnt übersprungen."
        return 0
    fi

    log "Mounte Root-Subvolume (@) nach /mnt..."
    mount -o "${mount_opts},subvol=@" "$TARGET_ROOT" /mnt

    log "Erstelle Verzeichnisstruktur für Subvolumes und Boot..."
    mkdir -p /mnt/{home,.snapshots,var/log,var/cache,boot/efi}

    log "Mounte weitere BTRFS-Subvolumes..."
    mount -o "${mount_opts},subvol=@home" "$TARGET_ROOT" /mnt/home
    mount -o "${mount_opts},subvol=@snapshots" "$TARGET_ROOT" /mnt/.snapshots
    mount -o "${mount_opts},subvol=@var_log" "$TARGET_ROOT" /mnt/var/log
    mount -o "${mount_opts},subvol=@var_cache" "$TARGET_ROOT" /mnt/var/cache

    log "Mounte EFI-Partition..."
    mount "$PART_EFI" /mnt/boot/efi

    success "Alle Dateisysteme erfolgreich gemountet."
}

# =========================================
# ⚙️ Modul-Einstiegspunkt: run_disk
# -----------------------------------------
# Zweck:    Sequenzielle Ausführung des Disk-Setups
# Aufgabe:  Sichert die logische Reihenfolge der Disk-Ops
# =========================================
run_disk() {
    header "Phase 3: Laufwerksvorbereitung"

    get_partitions
    disk_unmount_all
    disk_partition
    disk_luks
    disk_format_and_subvols
    disk_mount
}
