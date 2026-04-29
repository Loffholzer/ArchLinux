#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      99_finalize.sh
# Zweck:     Finalisierung
#
# Aufgabe:
# - finaler initramfs Build
# - Abschluss der Installation
#
# Wichtig:
# - letzter Schritt vor Reboot
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. Fehler hier = System nicht bootfähig
# 2. MUSS erfolgreich sein
# =========================================

# =========================================
# 🧱 Finalisierung durchführen
# -----------------------------------------
# Baut finale initramfs und stellt sicher,
# dass das System bootfähig ist
# =========================================

run_finalize() {
  header "99 - Finalisierung"

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde mkinitcpio -P ausführen"
    return 0
  fi

  log "Finaler initramfs Build..."

  # 🔥 doppelt für Sicherheit
  arch-chroot /mnt mkinitcpio -P || {
    warn "Retry mkinitcpio..."
    arch-chroot /mnt mkinitcpio -P || {
      error "mkinitcpio endgültig fehlgeschlagen."
      exit 1
    }
  }

  success "Initramfs final erstellt."
}
