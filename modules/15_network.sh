#!/usr/bin/env bash

# =========================================
# 15_network.sh
# -----------------------------------------
# Aufgabe:
# - installiert mDNS / Avahi
# - installiert und aktiviert firewalld
# - passt nsswitch.conf für .local-Auflösung an
#
# Voraussetzung:
# - Basissystem ist installiert
# =========================================

# =========================
# 🚀 Netzwerk Setup ausführen
# =========================

run_network_setup() {
  header "15 - Netzwerk"

  pruefe_network_variablen
  zeige_network_plan
  installiere_network_pakete
  konfiguriere_mdns
  setze_firewalld_zone
  konfiguriere_firewalld
  aktiviere_network_services

  success "Netzwerk eingerichtet."
}

# =========================
# 🔒 Checks
# =========================

pruefe_network_variablen() {
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

zeige_network_plan() {
  header "Geplante Netzwerk-Konfiguration"

  echo "Pflichtmodul: ja"
  echo
  echo "Pakete:"
  echo "  networkmanager"
  echo "  avahi"
  echo "  nss-mdns"
  echo "  firewalld"
  echo
  echo "Services:"
  echo "  NetworkManager"
  echo "  avahi-daemon"
  echo "  firewalld"
  echo
}

# =========================
# 📦 Netzwerk-Pakete installieren
# =========================

installiere_network_pakete() {
  local packages=(
    networkmanager
    avahi
    nss-mdns
    firewalld
  )

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Netzwerk-Pakete installieren:"
    warn "[DRY-RUN] pacman -S --noconfirm ${packages[*]}"
    return 0
  fi

  log "Installiere Netzwerk-Pakete..."

  arch-chroot /mnt pacman -S --noconfirm "${packages[@]}" || {
    error "Netzwerk-Pakete konnten nicht installiert werden."
    exit 1
  }
}

# =========================
# 🌐 mDNS konfigurieren
# =========================

konfiguriere_mdns() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde /etc/nsswitch.conf für mDNS konfigurieren"
    return 0
  fi

  local conf="/mnt/etc/nsswitch.conf"
  local hosts_line="hosts: files mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] dns myhostname"

  [[ -f "$conf" ]] || {
    error "nsswitch.conf nicht gefunden: $conf"
    exit 1
  }

  if grep -Eq '^hosts:.*mdns_minimal' "$conf"; then
    warn "mDNS ist bereits konfiguriert."
    return 0
  fi

  log "Konfiguriere mDNS..."

  if grep -Eq '^hosts:' "$conf"; then
    sed -i "s/^hosts:.*/${hosts_line}/" "$conf" || {
      error "nsswitch.conf konnte nicht angepasst werden."
      exit 1
    }
  else
    echo "$hosts_line" >> "$conf" || {
      error "hosts-Zeile konnte nicht in nsswitch.conf geschrieben werden."
      exit 1
    }
  fi

  success "mDNS konfiguriert."
}

# =========================
# 🔥 Netzwerk-Services aktivieren
# =========================

aktiviere_network_services() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde NetworkManager, avahi-daemon und firewalld aktivieren"
    return 0
  fi

  log "Aktiviere Netzwerk-Services..."

  arch-chroot /mnt systemctl enable NetworkManager.service || {
    error "NetworkManager konnte nicht aktiviert werden."
    exit 1
  }

  arch-chroot /mnt systemctl enable avahi-daemon.service || {
    error "avahi-daemon konnte nicht aktiviert werden."
    exit 1
  }

  arch-chroot /mnt systemctl enable firewalld.service || {
    error "firewalld konnte nicht aktiviert werden."
    exit 1
  }

  success "NetworkManager, avahi-daemon und firewalld aktiviert."
}

# =========================
# 🔥 Firewall-Regeln setzen
# =========================

konfiguriere_firewalld() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde mDNS in firewalld erlauben"
    return 0
  fi

  log "Konfiguriere firewalld..."

  arch-chroot /mnt firewall-offline-cmd --add-service=mdns || {
    error "mDNS konnte in firewalld nicht freigegeben werden."
    exit 1
  }

  success "firewalld mDNS-Regel gesetzt."
}

# =========================
# 🔥 Firewall Default-Zone setzen
# =========================

setze_firewalld_zone() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde firewalld Default-Zone auf home setzen"
    return 0
  fi

  log "Setze firewalld Default-Zone auf home..."

  arch-chroot /mnt firewall-offline-cmd --set-default-zone=home || {
    error "Default-Zone konnte nicht gesetzt werden."
    exit 1
  }

  success "firewalld Default-Zone gesetzt: home"
}

