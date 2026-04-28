#!/usr/bin/env bash

# =========================================
# 14_editor.sh
# -----------------------------------------
# Aufgabe:
# - installiert nano (falls gewünscht)
# - setzt sinnvolle nanorc Defaults
#
# Voraussetzung:
# - System installiert (/mnt)
# =========================================

# =========================
# 🚀 Editor Setup ausführen
# =========================

run_editor_setup() {
  header "14 - Editor"

  pruefe_editor_variablen
  zeige_editor_plan
  installiere_nano
  konfiguriere_nano

  success "Editor eingerichtet."
}

# =========================
# 🔒 Checks
# =========================

pruefe_editor_variablen() {
  if [[ "${DRY_RUN:-true}" != true ]]; then
    mountpoint -q /mnt || {
      error "/mnt ist nicht gemountet."
      exit 1
    }
  fi
}

# =========================
# 📋 Plan anzeigen
# =========================

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

# =========================
# 📦 Installation
# =========================

installiere_nano() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde nano installieren"
    return 0
  fi

  log "Installiere nano..."

  arch-chroot /mnt pacman -S --noconfirm nano
}

# =========================
# ⚙ Nano konfigurieren
# =========================

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
