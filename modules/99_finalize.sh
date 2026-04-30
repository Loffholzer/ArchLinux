#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      99_finalize.sh
# Zweck:     Installation finalisieren
#
# Aufgabe:
# - baut initramfs final neu
# - prüft letzten bootkritischen Schritt
# - schließt Installationspipeline ab
#
# Wichtig:
# - letzter Schritt vor Reboot
# - mkinitcpio-Fehler = System nicht bootfähig
# - Erfolg muss hart validierbar sein
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. mkinitcpio-Fehler hart behandeln
# 3. Keine stillen Fehler erlauben
# 4. Bootartefakte nach Build prüfen
# =========================================

# =========================================
# 🧱 Finalisierung ausführen
# -----------------------------------------
# Baut initramfs final neu und validiert
# bootkritische Artefakte
# → letzter Sicherheitscheck vor Reboot
# =========================================

run_finalize() {
  header "99 - Finalisierung"

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde final mkinitcpio -P ausführen"
    return 0
  fi

  guard_mnt_valid_root

  log "Finaler initramfs Build..."

  run_cmd arch-chroot /mnt mkinitcpio -P

  [[ -f /mnt/boot/vmlinuz-linux ]] || {
    error "Kernel fehlt → System nicht bootfähig"
    exit 1
  }

  [[ -f /mnt/boot/initramfs-linux.img ]] || {
    error "Finales initramfs-linux.img fehlt → System nicht bootfähig"
    exit 1
  }

  [[ -f /mnt/boot/vmlinuz-linux-lts ]] || {
    error "LTS Kernel fehlt"
    exit 1
  }

  [[ -f /mnt/boot/initramfs-linux-lts.img ]] || {
    error "Finales initramfs-linux-lts.img fehlt → LTS-Boot nicht möglich"
    exit 1
  }

  [[ -s /mnt/boot/initramfs-linux.img ]] || {
    error "Finales initramfs-linux.img ist leer"
    exit 1
  }

  [[ -s /mnt/boot/initramfs-linux-lts.img ]] || {
    error "Finales initramfs-linux-lts.img ist leer"
    exit 1
  }

  [[ -f /mnt/boot/limine.conf ]] || {
    error "limine.conf fehlt"
    exit 1
  }

  grep -q "rootflags=subvol=@" /mnt/boot/limine.conf || {
    error "limine.conf enthält kein rootflags=subvol=@"
    exit 1
  }

  success "Finalisierung abgeschlossen: Bootartefakte validiert."
}
