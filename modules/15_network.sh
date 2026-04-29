#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      15_network.sh
# Zweck:     Netzwerk + Security Setup
#
# Aufgabe:
# - installiert Netzwerk-Stack
# - aktiviert sichere Defaults
# - konfiguriert Firewall + SSH
#
# Wichtig:
# - kein offenes System nach Installation
# - SSH sicher konfiguriert
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. Firewall IMMER aktiv
# 2. SSH niemals unsicher
# 3. Dienste nur wenn nötig aktivieren
# =========================================


# =========================================
# 🚀 Netzwerk Setup orchestrieren
# =========================================

run_network_setup() {
  header "15 - Netzwerk"

  pruefe_network_variablen
  zeige_network_plan
  installiere_network_pakete
  konfiguriere_mdns
  konfiguriere_firewalld
  konfiguriere_ssh
  aktiviere_network_services
  validiere_network_setup

  success "Netzwerk sicher eingerichtet."
}


# =========================================
# 🔒 Checks
# =========================================

pruefe_network_variablen() {
  if [[ "${DRY_RUN:-true}" != true ]]; then
    guard_mnt_mounted
  fi
}


# =========================================
# 📋 Plan anzeigen
# =========================================

zeige_network_plan() {
  header "Geplante Netzwerk-Konfiguration"

  echo "Netzwerk: NetworkManager"
  echo "Firewall: firewalld (default deny)"
  echo "mDNS:     Avahi"
  [[ "${INSTALL_SSH:-no}" == "yes" ]] && echo "SSH:      aktiviert (gehärtet)"
  echo
}


# =========================================
# 📦 Pakete installieren
# =========================================

installiere_network_pakete() {
  local packages=(
    networkmanager
    avahi
    nss-mdns
    firewalld
  )

  [[ "${INSTALL_SSH:-no}" == "yes" ]] && packages+=(openssh)

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Netzwerk-Pakete installieren: ${packages[*]}"
    return 0
  fi

  run_cmd arch-chroot /mnt pacman -S --noconfirm "${packages[@]}"
}


# =========================================
# 🌐 mDNS konfigurieren
# =========================================

konfiguriere_mdns() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde mDNS konfigurieren"
    return 0
  fi

  local conf="/mnt/etc/nsswitch.conf"

  grep -q "mdns_minimal" "$conf" && return 0

  sed -i 's/^hosts:.*/hosts: files mymachines mdns_minimal [NOTFOUND=return] resolve dns myhostname/' "$conf"
}


# =========================================
# 🔥 Firewall konfigurieren (SECURE DEFAULT)
# =========================================

konfiguriere_firewalld() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Firewall konfigurieren"
    return 0
  fi

  log "Konfiguriere firewalld (secure defaults)..."

  # Default Zone = public (strenger als home)
  arch-chroot /mnt firewall-offline-cmd --set-default-zone=public

  # Alles blockieren außer explizit erlaubt
  arch-chroot /mnt firewall-offline-cmd --set-target=DROP

  # mDNS erlauben (optional aber sinnvoll)
  arch-chroot /mnt firewall-offline-cmd --add-service=mdns

  # SSH nur wenn aktiviert
  if [[ "${INSTALL_SSH:-no}" == "yes" ]]; then
    arch-chroot /mnt firewall-offline-cmd --add-service=ssh
  fi
}


# =========================================
# 🔐 SSH HARDENING
# =========================================

konfiguriere_ssh() {
  [[ "${INSTALL_SSH:-no}" != "yes" ]] && return 0

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde SSH härten"
    return 0
  fi

  local conf="/mnt/etc/ssh/sshd_config"

  [[ -f "$conf" ]] || return 0

  log "Härte SSH-Konfiguration..."

  # Root Login deaktivieren
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$conf"

  # Passwort Login aktiv lassen (für Installer usability)
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$conf"

  # zusätzliche Härtung
  grep -q "^MaxAuthTries" "$conf" || echo "MaxAuthTries 3" >> "$conf"
  grep -q "^LoginGraceTime" "$conf" || echo "LoginGraceTime 30" >> "$conf"
  grep -q "^X11Forwarding" "$conf" || echo "X11Forwarding no" >> "$conf"
}


# =========================================
# 🔌 Dienste aktivieren
# =========================================

aktiviere_network_services() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Netzwerkdienste aktivieren"
    return 0
  fi

  arch-chroot /mnt systemctl enable NetworkManager
  arch-chroot /mnt systemctl enable firewalld
  arch-chroot /mnt systemctl enable avahi-daemon

  [[ "${INSTALL_SSH:-no}" == "yes" ]] && \
    arch-chroot /mnt systemctl enable sshd
}


# =========================================
# 🧪 Validierung
# =========================================

validiere_network_setup() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    return 0
  fi

  log "Validiere Netzwerk-Setup..."

  arch-chroot /mnt systemctl is-enabled NetworkManager >/dev/null || {
    error "NetworkManager nicht aktiviert"
    exit 1
  }

  arch-chroot /mnt systemctl is-enabled firewalld >/dev/null || {
    error "firewalld nicht aktiviert"
    exit 1
  }

  success "Netzwerk validiert."
}
