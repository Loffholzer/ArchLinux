#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      04_base.sh
# Zweck:     Basissystem installieren
#
# Aufgabe:
# - installiert minimales Arch-System
# - ergänzt BTRFS/LUKS-Basiswerkzeuge
# - bereitet Zielsystem für Boot-Konfiguration vor
#
# Wichtig:
# - /mnt muss korrekt gemountet sein
# - pacstrap-Fehler = unvollständiges System
# - fehlende Pakete können Boot/Recovery brechen
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. /mnt vor pacstrap validieren
# 3. Paketliste deterministisch halten
# 4. pacstrap-Fehler hart abbrechen
# =========================================

# =========================================
# 📦 Basissystem installieren
# -----------------------------------------
# Orchestriert Prüfung, Plan und pacstrap
# → erzeugt minimales Zielsystem unter /mnt
# =========================================

run_base_install() {
  header "04 - Basissystem"

  pruefe_base_variablen
  pruefe_pacstrap_netwerk
  zeige_base_plan
  installiere_base

  success "Basissystem installiert."
}

# =========================================
# 🔒 Base-Voraussetzungen prüfen
# -----------------------------------------
# Validiert Ziel-Mountpoint /mnt
# → verhindert Installation ins Live-System
# =========================================

pruefe_base_variablen() {
  if [[ "${DRY_RUN:-true}" != true ]]; then
    mountpoint -q /mnt || {
      error "/mnt ist nicht gemountet. Abbruch."
      exit 1
    }
  fi
}

# =========================================
# 📋 Base-Plan anzeigen
# -----------------------------------------
# Zeigt Basispakete für pacstrap
# → Sichtprüfung vor Systeminstallation
# =========================================

zeige_base_plan() {
  header "Geplante Installation"

  echo "Pakete:"
  echo "  base"
  echo "  base-devel"
  echo "  btrfs-progs"
  echo "  sudo"
  [[ "${USE_LUKS:-no}" == "yes" ]] && echo "  cryptsetup"
  echo

  warn "Dieses Modul installiert das Basissystem nach /mnt."
  warn "Kernel, Firmware, Limine und Memtest folgen im Bootloader-Modul."
  echo
}

# =========================================
# 🌐 Netzwerk vor pacstrap prüfen
# -----------------------------------------
# Prüft Arch-Repo-Erreichbarkeit
# → verhindert halbe Installation ohne Netzwerk
# =========================================

pruefe_pacstrap_netwerk() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Netzwerk vor pacstrap prüfen"
    return 0
  fi

  ping -c 1 -W 3 archlinux.org >/dev/null 2>&1 || {
    error "Kein Netzwerk oder archlinux.org nicht erreichbar."
    exit 1
  }
}

# =========================================
# 📦 Base-Pakete installieren
# -----------------------------------------
# Installiert Kernpakete nach /mnt
# → pacstrap-Fehler macht System unbrauchbar
# =========================================

installiere_base() {
  local packages=(
    base
    base-devel
    btrfs-progs
    sudo
  )

  if [[ "${USE_LUKS:-no}" == "yes" ]]; then
    packages+=(
      cryptsetup
    )
  fi

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde pacstrap ausführen:"
    warn "[DRY-RUN] pacstrap /mnt ${packages[*]}"
    return 0
  fi

  log "Installiere Basissystem..."

  pacstrap /mnt "${packages[@]}" || {
    error "pacstrap fehlgeschlagen."
    exit 1
  }
}
