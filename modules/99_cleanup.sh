#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      99_cleanup.sh
# Zweck:     Sicherer Systemabschluss
#
# Aufgabe:
# - System aushängen (umount)
# - LUKS-Container verschließen
# - Erfolgsmeldung und Reboot-Prompt
#
# Wichtig:
# - Verhindert Datenkorruption beim Neustart
# =========================================

# =========================================
# ⚙️ Modul-Einstiegspunkt: run_cleanup
# -----------------------------------------
# Zweck:    Zentraler Aufrufpunkt des Moduls
# Aufgabe:  Führt den finalen Cleanup-Prozess durch
# =========================================
run_cleanup() {
    header "Phase 99: Cleanup & Abschluss"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        success "DRY-RUN erfolgreich beendet."
        return 0
    fi

    log "Verlasse chroot und hänge Dateisysteme aus..."
    umount -R /mnt 2>/dev/null || true

    if [[ "$USE_LUKS" == "yes" ]]; then
        log "Schließe LUKS Container..."
        cryptsetup close cryptroot 2>/dev/null || true
    fi

    echo -e "\n${BOLD}${GREEN}=========================================${NC}"
    echo -e "${BOLD}${GREEN} 🎉 INSTALLATION ERFOLGREICH ABGESCHLOSSEN 🎉${NC}"
    echo -e "${BOLD}${GREEN}=========================================${NC}\n"

    echo -e "Die neue Arch Linux Umgebung (Virtuoso Edition) ist bereit."
    echo -e "Bitte entferne das Installationsmedium und starte das System neu.\n"

    local reboot_choice
    read -rp "$(echo -e "${BLUE}[INPUT]${NC} Jetzt neu starten? (j/n): ")" reboot_choice
    if [[ "${reboot_choice,,}" =~ ^(j|ja|y|yes)$ ]]; then
        reboot
    fi
}
