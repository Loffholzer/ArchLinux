#!/usr/bin/env bash

run_finalize() {
  header "99 - Finalisierung"

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde final mkinitcpio -P ausführen"
    return 0
  fi

  log "Führe final mkinitcpio Build aus..."

  arch-chroot /mnt mkinitcpio -P || {
    error "Finaler mkinitcpio Build fehlgeschlagen."
    exit 1
  }

  success "Initramfs final erstellt."
}
