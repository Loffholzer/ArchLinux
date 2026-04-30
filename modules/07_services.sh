#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      07_services.sh
# Zweck:     Services, Maintenance & Snapper
#
# Aufgabe:
# - NetworkManager aktivieren
# - Reflector für automatische Mirror-Updates einrichten
# - BTRFS SSD/Scrub-Wartung aktivieren
# - Snapper + Limine-Hook für Rollbacks konfigurieren
# =========================================

# =========================================
# 🌐 Funktion: serv_network_mirrors
# -----------------------------------------
# Zweck:    Netzwerk und Paketquellen sichern
# Aufgabe:  NM aktivieren, Reflector konfigurieren
# =========================================
serv_network_mirrors() {
    phase_header "Zielsystem: Netzwerk & Reflector"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Network & Reflector übersprungen."
        return 0
    fi

    log "Aktiviere NetworkManager..."
    arch-chroot /mnt systemctl enable NetworkManager >/dev/null 2>&1

    log "Konfiguriere Reflector für wöchentliche Updates..."
    arch-chroot /mnt pacman -S --noconfirm reflector >/dev/null 2>&1

    mkdir -p /mnt/etc/xdg/reflector
    cat <<EOF > /mnt/etc/xdg/reflector/reflector.conf
--save /etc/pacman.d/mirrorlist
--protocol https
--latest 20
--sort rate
EOF

    arch-chroot /mnt systemctl enable reflector.timer >/dev/null 2>&1
    success "Netzwerk und automatische Mirror-Updates eingerichtet."
}

# =========================================
# 🗂️ Funktion: serv_btrfs_maintenance
# -----------------------------------------
# Zweck:    Dateisystem-Gesundheit garantieren
# Aufgabe:  Scrub (Integrität) und Trim (SSD)
# =========================================
serv_btrfs_maintenance() {
    phase_header "Zielsystem: BTRFS Maintenance"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] BTRFS Maintenance übersprungen."
        return 0
    fi

    log "Aktiviere monatlichen BTRFS Scrub..."
    arch-chroot /mnt systemctl enable btrfs-scrub@-.timer >/dev/null 2>&1

    # Nur aktivieren, wenn es eine SSD ist (Trim)
    local rota
    rota=$(lsblk -nd -o ROTA "$DISK" 2>/dev/null || echo "0")
    if [[ "$rota" == "0" ]]; then
        log "SSD erkannt: Aktiviere wöchentlichen fstrim..."
        arch-chroot /mnt systemctl enable fstrim.timer >/dev/null 2>&1
    fi

    success "BTRFS-Wartung konfiguriert."
}

# =========================================
# 📸 Funktion: serv_snapper
# -----------------------------------------
# Zweck:    System-Rollback Infrastruktur
# Aufgabe:  Snapper manuell konfigurieren (ohne DBus)
# =========================================
serv_snapper() {
    phase_header "Zielsystem: Snapper & Rollbacks"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Snapper-Setup übersprungen."
        return 0
    fi

    log "Installiere snapper und snap-pac..."
    arch-chroot /mnt pacman -S --noconfirm snapper snap-pac >/dev/null 2>&1

    # FIX: DBus Bypass. Config manuell kopieren und anlegen.
    log "Erstelle Snapper-Config manuell (Bypass für chroot DBus-Fehler)..."
    mkdir -p /mnt/etc/snapper/configs
    cp /mnt/usr/share/snapper/config-templates/default /mnt/etc/snapper/configs/root

    # Registriere die neue 'root'-Config im System
    mkdir -p /mnt/etc/conf.d
    echo 'SNAPPER_CONFIGS="root"' > /mnt/etc/conf.d/snapper

    # Setze BTRFS Subvolume-Referenz und erlaube der wheel-Gruppe den Zugriff
    sed -i 's/^SUBVOLUME=.*/SUBVOLUME="\/"/' /mnt/etc/snapper/configs/root
    sed -i 's/^ALLOW_GROUPS=.*/ALLOW_GROUPS="wheel"/' /mnt/etc/snapper/configs/root

    log "Passe Snapper-Retention (Speicherplatz) an..."
    sed -i 's/^TIMELINE_LIMIT_HOURLY.*/TIMELINE_LIMIT_HOURLY="5"/' /mnt/etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_DAILY.*/TIMELINE_LIMIT_DAILY="7"/' /mnt/etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_WEEKLY.*/TIMELINE_LIMIT_WEEKLY="0"/' /mnt/etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_MONTHLY.*/TIMELINE_LIMIT_MONTHLY="0"/' /mnt/etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_YEARLY.*/TIMELINE_LIMIT_YEARLY="0"/' /mnt/etc/snapper/configs/root

    arch-chroot /mnt systemctl enable snapper-timeline.timer >/dev/null 2>&1
    arch-chroot /mnt systemctl enable snapper-cleanup.timer >/dev/null 2>&1

    # Erstelle den Limine-Sync Hook
    _create_limine_hook

    success "Snapper erfolgreich manuell konfiguriert und integriert."
}

# =========================================
# 🪝 Helper: _create_limine_hook
# -----------------------------------------
# Zweck:    Automatisches Boot-Menü Update
# Aufgabe:  Schreibt Sync-Skript und Pacman-Hook
# =========================================
_create_limine_hook() {
    log "Erstelle Limine-Snapper Sync Skript..."

    local sync_script="/mnt/usr/local/bin/limine-snapper-sync"
    cat <<'EOF' > "$sync_script"
#!/usr/bin/env bash
# Generiert dynamisch Boot-Einträge für die letzten 5 Snapper-Snapshots

LIMINE_CONF=$(find /boot -maxdepth 2 -name "limine.conf" | head -n 1)
[[ -z "$LIMINE_CONF" ]] && exit 0

# Finde den Main-Eintrag in limine.conf um Parameter dynamisch zu kopieren
CMDLINE=$(grep -A 5 "Arch Linux (Mainline)" "$LIMINE_CONF" | grep "CMDLINE" | head -n 1 | cut -d '=' -f 2-)
PROTOCOL=$(grep -A 5 "Arch Linux (Mainline)" "$LIMINE_CONF" | grep "PROTOCOL" | head -n 1 | cut -d '=' -f 2-)
KERNEL_PATH=$(grep -A 5 "Arch Linux (Mainline)" "$LIMINE_CONF" | grep "KERNEL_PATH" | head -n 1 | cut -d '=' -f 2-)
MODULE_PATH=$(grep -A 5 "Arch Linux (Mainline)" "$LIMINE_CONF" | grep "MODULE_PATH" | head -n 1 | cut -d '=' -f 2-)

# Entferne alte Snapshot-Einträge (alles nach der Trennlinie)
sed -i '/^# === SNAPSHOTS ===/,$d' "$LIMINE_CONF"

echo "# === SNAPSHOTS ===" >> "$LIMINE_CONF"

# Lese die letzten 5 Snapshots aus (ignoriere Header)
snapper -c root list | tail -n +3 | tail -n 5 | while read -r line; do
    # Extrahiere Snapshot Nummer und Datum
    snap_num=$(echo "$line" | awk '{print $1}' | tr -d '*')
    snap_date=$(echo "$line" | awk '{print $3, $4, $5, $6}')

    # FIX: Ersetze Pfade dynamisch (Limine Standard & LUKS Kompatibilität)
    SNAP_CMDLINE=$(echo "$CMDLINE" | sed "s|subvol=@|subvol=@snapshots/$snap_num/snapshot|")
    SNAP_KERNEL=$(echo "$KERNEL_PATH" | sed "s|/@/|/@snapshots/$snap_num/snapshot/|")
    SNAP_MODULE=$(echo "$MODULE_PATH" | sed "s|/@/|/@snapshots/$snap_num/snapshot/|")

    cat <<ENTRY >> "$LIMINE_CONF"

:Snapshot #$snap_num ($snap_date)
    PROTOCOL=$PROTOCOL
    KERNEL_PATH=$SNAP_KERNEL
    MODULE_PATH=$SNAP_MODULE
    CMDLINE=$SNAP_CMDLINE
ENTRY
done
EOF
    chmod +x "$sync_script"

    log "Erstelle Pacman-Hook für Limine-Sync..."
    mkdir -p /mnt/etc/pacman.d/hooks
    cat <<EOF > /mnt/etc/pacman.d/hooks/99-limine-snapper.hook
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Synchronisiere Limine mit Snapper Snapshots...
When = PostTransaction
Exec = /usr/local/bin/limine-snapper-sync
EOF
}

# =========================================
# ⚙️ Modul-Einstiegspunkt: run_services
# -----------------------------------------
# Zweck:    Sequenzielle Ausführung
# Aufgabe:  Aktiviert Netzwerk, Wartung und Snapshots
# =========================================
run_services() {
    header "Phase 7: Network & Services"

    serv_network_mirrors
    serv_btrfs_maintenance
    serv_snapper
}
