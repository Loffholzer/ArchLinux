#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      15_network.sh
# Zweck:     Netzwerk und Firewall einrichten
#
# Aufgabe:
# - installiert NetworkManager, Avahi und firewalld
# - konfiguriert mDNS und Firewall-Defaults
# - installiert und härtet SSH optional
#
# Wichtig:
# - Firewall muss aktiv sein
# - SSH darf nicht offen/unsicher bleiben
# - falsche Dienste erhöhen Angriffsfläche
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. Firewall immer aktivieren
# 3. SSH nur optional aktivieren
# 4. Netzwerkdienste nach Setup validieren
# =========================================

# =========================================
# 🚀 Netzwerk-Setup ausführen
# -----------------------------------------
# Installiert Pakete, Firewall und Dienste
# → stellt Netzwerk mit sicheren Defaults bereit
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
# 🔒 Netzwerk-Eingaben prüfen
# -----------------------------------------
# Validiert Zielsystem-Mount /mnt
# → verhindert Konfiguration am falschen System
# =========================================

pruefe_network_variablen() {
  if [[ "${DRY_RUN:-true}" != true ]]; then
    guard_mnt_mounted
  fi
}

# =========================================
# 📋 Netzwerk-Plan anzeigen
# -----------------------------------------
# Zeigt Netzwerkstack, Firewall und SSH-Status
# → Sichtprüfung vor Security-Änderungen
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
# 📦 Netzwerk-Pakete installieren
# -----------------------------------------
# Installiert NetworkManager, mDNS und Firewall
# → SSH nur bei aktivierter Option
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
# -----------------------------------------
# Aktiviert mdns_minimal in nsswitch.conf
# → ermöglicht lokale Hostnamenauflösung
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
# 🔥 Firewall konfigurieren
# -----------------------------------------
# Setzt firewalld auf public/DROP
# → erlaubt nur explizit freigegebene Dienste
# =========================================

konfiguriere_firewalld() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Firewall konfigurieren"
    return 0
  fi

  log "Konfiguriere firewalld (secure defaults)..."

  run_cmd arch-chroot /mnt firewall-offline-cmd --set-default-zone=public
  run_cmd arch-chroot /mnt firewall-offline-cmd --zone=public --set-target=DROP
  run_cmd arch-chroot /mnt firewall-offline-cmd --zone=public --add-service=mdns

  if [[ "${INSTALL_SSH:-no}" == "yes" ]]; then
    run_cmd arch-chroot /mnt firewall-offline-cmd --zone=public --add-service=ssh
  fi
}

# =========================================
# 🔐 SSH härten
# -----------------------------------------
# Erzwingt Pubkey-only SSH ohne Root-Login
# → verhindert Passwort-Bruteforce nach Erstboot
# =========================================

konfiguriere_ssh() {
  [[ "${INSTALL_SSH:-no}" != "yes" ]] && return 0

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde SSH härten"
    return 0
  fi

  local conf="/mnt/etc/ssh/sshd_config"
  local dropin_dir="/mnt/etc/ssh/sshd_config.d"
  local hardening_conf="${dropin_dir}/99-installer-hardening.conf"

  [[ -f "$conf" ]] || {
    error "sshd_config nicht gefunden: $conf"
    exit 1
  }

  install -d -m 755 "$dropin_dir"

  cat > "$hardening_conf" <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowTcpForwarding no
PermitTunnel no
EOF

  chmod 644 "$hardening_conf"

  arch-chroot /mnt sshd -t || {
    error "sshd_config ist ungültig"
    exit 1
  }

  success "SSH gehärtet: Root aus, Passwortlogin aus, Pubkey-only."
}

# =========================================
# 🔌 Dienste aktivieren
# -----------------------------------------
# Aktiviert Netzwerk-, Firewall- und mDNS-Dienste
# → SSH nur bei INSTALL_SSH=yes
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
# 🧪 Netzwerk validieren
# -----------------------------------------
# Prüft aktivierte Netzwerk- und Firewall-Dienste
# → stoppt bei unsicherem Zielsystem
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
