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
    guard_mnt_valid_root
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
# Setzt firewalld idempotent auf public/DROP
# → erlaubt nur explizit freigegebene Dienste
# → akzeptiert bereits gesetzte Werte sauber
# =========================================

konfiguriere_firewalld() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Firewall konfigurieren"
    return 0
  fi

  log "Konfiguriere firewalld (secure defaults)..."

  arch-chroot /mnt firewall-offline-cmd --set-default-zone=public 2>/tmp/firewalld-default.err || {
    if grep -q "ZONE_ALREADY_SET" /tmp/firewalld-default.err; then
      warn "firewalld Default-Zone ist bereits public."
    else
      cat /tmp/firewalld-default.err >&2
      error "firewalld Default-Zone konnte nicht gesetzt werden"
      exit 1
    fi
  }

  arch-chroot /mnt firewall-offline-cmd --zone=public --set-target=DROP 2>/tmp/firewalld-target.err || {
    if grep -q "ALREADY_ENABLED\|ZONE_ALREADY_SET" /tmp/firewalld-target.err; then
      warn "firewalld public target ist bereits gesetzt."
    else
      cat /tmp/firewalld-target.err >&2
      error "firewalld Target konnte nicht gesetzt werden"
      exit 1
    fi
  }

  arch-chroot /mnt firewall-offline-cmd --zone=public --add-service=mdns 2>/tmp/firewalld-mdns.err || {
    if grep -q "ALREADY_ENABLED" /tmp/firewalld-mdns.err; then
      warn "firewalld mdns ist bereits erlaubt."
    else
      cat /tmp/firewalld-mdns.err >&2
      error "firewalld mdns konnte nicht erlaubt werden"
      exit 1
    fi
  }

  if [[ "${INSTALL_SSH:-no}" == "yes" ]]; then
    arch-chroot /mnt firewall-offline-cmd --zone=public --add-service=ssh 2>/tmp/firewalld-ssh.err || {
      if grep -q "ALREADY_ENABLED" /tmp/firewalld-ssh.err; then
        warn "firewalld ssh ist bereits erlaubt."
      else
        cat /tmp/firewalld-ssh.err >&2
        error "firewalld ssh konnte nicht erlaubt werden"
        exit 1
      fi
    }
  fi

  rm -f /tmp/firewalld-default.err /tmp/firewalld-target.err /tmp/firewalld-mdns.err /tmp/firewalld-ssh.err

  success "firewalld idempotent konfiguriert."
}

# =========================================
# 🔐 SSH härten
# -----------------------------------------
# Erzwingt sichere SSH-Defaults nur dann,
# wenn ein Public-Key vorhanden ist
# → verhindert SSH-Lockout nach Erstboot
# =========================================

konfiguriere_ssh() {
  [[ "${INSTALL_SSH:-no}" != "yes" ]] && return 0

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde SSH härten"
    return 0
  fi

  guard_require_var USERNAME

  local conf="/mnt/etc/ssh/sshd_config"
  local dropin_dir="/mnt/etc/ssh/sshd_config.d"
  local hardening_conf="${dropin_dir}/99-installer-hardening.conf"
  local user_home="/mnt/home/${USERNAME}"
  local ssh_dir="${user_home}/.ssh"
  local auth_keys="${ssh_dir}/authorized_keys"

  [[ -f "$conf" ]] || {
    error "sshd_config nicht gefunden: $conf"
    exit 1
  }

  install -d -m 755 "$dropin_dir"

  if [[ ! -s "$auth_keys" ]]; then
    warn "Kein SSH authorized_keys gefunden."
    warn "SSH wird installiert/aktiviert, aber Passwortlogin bleibt erlaubt, um Lockout zu verhindern."

    cat > "$hardening_conf" <<'EOF'
PermitRootLogin no
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
PermitTunnel no
EOF

    chmod 644 "$hardening_conf"

    arch-chroot /mnt sshd -t || {
      error "sshd_config ist ungültig"
      exit 1
    }

    success "SSH sicher konfiguriert: Root-Login aus, Passwortlogin bleibt als Fallback aktiv."
    return 0
  fi

  chmod 700 "$ssh_dir"
  chmod 600 "$auth_keys"
  arch-chroot /mnt chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.ssh"

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

  success "SSH gehärtet: Root aus, Pubkey-only aktiv."
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
