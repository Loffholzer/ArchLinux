#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      06_perf.sh
# Zweck:     Optionale Performance-Tweaks
#
# Aufgabe:
# - optimiert pacman-Konfiguration
# - installiert und konfiguriert ZRAM
#
# Wichtig:
# - nicht bootkritisch
# - Fehler dürfen Basissystem nicht gefährden
# - Änderungen müssen idempotent bleiben
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. Nur optionale Optimierungen durchführen
# 3. Keine Systeminstabilität riskieren
# 4. Bestehende Konfigurationen nicht beschädigen
# =========================================

# =========================================
# ⚡ Performance-Setup ausführen
# -----------------------------------------
# Wendet Pacman- und ZRAM-Tweaks an
# → verbessert Nutzung ohne Bootkritikalität
# =========================================

run_perf_setup() {
  header "06 - Performance"

  zeige_perf_plan
  optimiere_pacman
  installiere_zram

  success "Performance-Optimierungen angewendet."
}

# =========================================
# 📋 Performance-Plan anzeigen
# -----------------------------------------
# Zeigt geplante optionale Optimierungen
# → Sichtprüfung vor Konfigurationsänderungen
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
# ⚙️ Pacman optimieren
# -----------------------------------------
# Aktiviert Downloads, Farbe und UX-Optionen
# → beschleunigt und verbessert Paketverwaltung
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

  sed -i -E 's/^[[:space:]]*#?[[:space:]]*ParallelDownloads[[:space:]]*=.*/ParallelDownloads = 10/' "$pacman_conf"
  grep -qE '^ParallelDownloads[[:space:]]*=' "$pacman_conf" || echo "ParallelDownloads = 10" >> "$pacman_conf"

  sed -i -E 's/^[[:space:]]*#?[[:space:]]*Color[[:space:]]*$/Color/' "$pacman_conf"
  grep -qE '^Color$' "$pacman_conf" || echo "Color" >> "$pacman_conf"

  grep -qE '^ILoveCandy$' "$pacman_conf" || echo "ILoveCandy" >> "$pacman_conf"

  success "Pacman optimiert."
}

# =========================================
# 💾 ZRAM konfigurieren
# -----------------------------------------
# Richtet komprimierten RAM-Swap ein
# → verbessert Verhalten bei Speicherdruck
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
