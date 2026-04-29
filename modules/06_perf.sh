#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      06_perf.sh
# Zweck:     Performance-Tuning
#
# Aufgabe:
# - optimiert pacman
# - optional ZRAM konfigurieren
#
# Wichtig:
# - keine kritischen Systemeingriffe
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. Nur optionale Optimierungen
# 2. Keine Systeminstabilität riskieren
# 3. idempotent bleiben
# =========================================

# =========================================
# ⚡ Performance-Setup orchestrieren
# -----------------------------------------
# Steuert Pacman-Optimierungen und
# optionale ZRAM-Konfiguration
# =========================================

run_perf_setup() {
  header "06 - Performance"

  zeige_perf_plan
  optimiere_pacman
  installiere_zram

  success "Performance-Optimierungen angewendet."
}

# =========================================
# 📋 Performance-Optimierungen anzeigen
# -----------------------------------------
# Zeigt geplante Pacman- und
# System-Tweaks vor Anwendung
# =========================================

zeige_perf_plan() {
  header "Geplante Optimierungen"

  echo "Pacman:"
  echo "  - ParallelDownloads aktivieren"
  echo "  - Color aktivieren"
  echo "  - ILoveCandy aktivieren"
  echo

  warn "Dieses Modul optimiert das System leicht."
  echo
}

# =========================================
# ⚙️ Pacman konfigurieren
# -----------------------------------------
# Aktiviert ParallelDownloads, Farbe
# und zusätzliche Pacman-UX-Optionen
# =========================================

optimiere_pacman() {
  local pacman_conf="/mnt/etc/pacman.conf"

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde pacman optimieren:"
    warn "  - ParallelDownloads aktivieren"
    warn "  - Color aktivieren"
    warn "  - ILoveCandy aktivieren"
    return 0
  fi

  [[ -f "$pacman_conf" ]] || {
    error "pacman.conf nicht gefunden: $pacman_conf"
    exit 1
  }

  log "Optimiere pacman..."

  sed -i 's/^#ParallelDownloads/ParallelDownloads/' "$pacman_conf" || {
    error "ParallelDownloads konnte nicht aktiviert werden."
    exit 1
  }

  sed -i 's/^#Color/Color/' "$pacman_conf" || {
    error "Color konnte nicht aktiviert werden."
    exit 1
  }

  grep -q "^ILoveCandy" "$pacman_conf" || \
    sed -i '/^#VerbosePkgLists/a ILoveCandy' "$pacman_conf" || {
      error "ILoveCandy konnte nicht gesetzt werden."
      exit 1
    }

  success "Pacman jetzt hübsch ✨"
}

# =========================================
# 💾 ZRAM konfigurieren
# -----------------------------------------
# Installiert zram-generator und richtet
# komprimierten RAM-Swap ein
# =========================================

installiere_zram() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde zram-generator installieren und konfigurieren"
    return 0
  fi

  log "Installiere und konfiguriere ZRAM (Swap im RAM)..."

  arch-chroot /mnt pacman -S --noconfirm zram-generator || {
    warn "Konnte zram-generator nicht installieren."
    return 0
  }

  # Konfiguriert ZRAM auf max 50% des RAMs mit zstd Kompression
  cat > /mnt/etc/systemd/zram-generator.conf << 'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF

  success "ZRAM konfiguriert (aktiviert sich automatisch beim Boot)."
}
