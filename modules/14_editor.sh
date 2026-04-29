#!/usr/bin/env bash
# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      14_editor.sh
# Zweck:     Editor Setup
#
# Aufgabe:
# - installiert nano
# - setzt Defaults
#
# Wichtig:
# - optional
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. Config nicht doppelt schreiben
# =========================================


# =========================================
# 📝 Editor-Setup orchestrieren
# -----------------------------------------
# Steuert Installation und Konfiguration
# des Nano-Editors
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
# 🔒 Editor-Voraussetzungen prüfen
# -----------------------------------------
# Stellt sicher, dass das Zielsystem
# korrekt gemountet ist
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
# 📋 Editor-Konfiguration anzeigen
# -----------------------------------------
# Zeigt geplante Nano-Features
# und Einstellungen
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
# Installiert Nano im Zielsystem
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
# Ergänzt nanorc um sinnvolle Defaults
# und aktiviert Syntax-Highlighting
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
