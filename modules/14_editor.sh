#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      14_editor.sh
# Zweck:     Nano-Editor einrichten
#
# Aufgabe:
# - installiert nano
# - ergänzt sinnvolle Editor-Defaults
# - aktiviert Syntax-Highlighting
#
# Wichtig:
# - optional, nicht bootkritisch
# - Config darf nicht doppelt geschrieben werden
# - bestehende nanorc muss erhalten bleiben
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. /mnt vor Änderungen validieren
# 3. Config idempotent erweitern
# 4. Paketinstallation hart abbrechen
# =========================================

# =========================================
# 📝 Editor-Setup ausführen
# -----------------------------------------
# Installiert und konfiguriert nano
# → stellt brauchbaren Fallback-Editor bereit
# =========================================

run_editor_setup() {
  header "14 - Editor"

  pruefe_editor_variablen
  zeige_editor_plan
  installiere_nano
  konfiguriere_nano

  success "Editor eingerichtet."
}

# =========================================
# 🔒 Editor-Eingaben prüfen
# -----------------------------------------
# Validiert Zielsystem-Mount /mnt
# → verhindert Änderung am falschen System
# =========================================

pruefe_editor_variablen() {
  if [[ "${DRY_RUN:-true}" != true ]]; then
    mountpoint -q /mnt || {
      error "/mnt ist nicht gemountet."
      exit 1
    }
  fi
}

# =========================================
# 📋 Editor-Plan anzeigen
# -----------------------------------------
# Zeigt geplante Nano-Konfiguration
# → Sichtprüfung vor nanorc-Änderung
# =========================================

zeige_editor_plan() {
  header "Geplante Editor-Konfiguration"

  echo "Editor: nano"
  echo "Features:"
  echo "  - Syntax Highlighting"
  echo "  - Zeilennummern"
  echo "  - Softwrap"
  echo

  warn "Dieses Modul richtet nano ein."
  echo
}

# =========================================
# 📦 Nano installieren
# -----------------------------------------
# Installiert nano ins Zielsystem
# → Paketfehler bricht Editor-Setup ab
# =========================================

installiere_nano() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde nano installieren"
    return 0
  fi

  log "Installiere nano..."

  arch-chroot /mnt pacman -S --noconfirm nano
}

# =========================================
# ⚙️ Nano konfigurieren
# -----------------------------------------
# Ergänzt nanorc um Editor-Defaults
# → Marker verhindert doppelte Einträge
# =========================================

konfiguriere_nano() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde nanorc konfigurieren"
    return 0
  fi

  log "Konfiguriere nano..."

  if grep -q "^# === Custom Settings ===$" /mnt/etc/nanorc; then
    warn "Nano-Konfiguration existiert bereits, überspringe."
    return 0
  fi

  cat >> /mnt/etc/nanorc << 'EOF'

# === Custom Settings ===
set linenumbers
set softwrap
set constantshow
set tabsize 2
set tabstospaces
set autoindent
set mouse

# Syntax Highlighting
include "/usr/share/nano/*.nanorc"
EOF
}
