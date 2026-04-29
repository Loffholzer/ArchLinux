#!/usr/bin/env bash

# =========================================
# 07_snapshots.sh
# -----------------------------------------
# Aufgabe:
# - installiert snapper
# - initialisiert Snapshot-Konfiguration
# - setzt Basisstruktur für BTRFS Snapshots
#
# Voraussetzung:
# - BTRFS läuft (aus 03)
# =========================================

run_snapshot_setup() {
  header "07 - Snapshots"

  pruefe_snapshot_variablen
  zeige_snapshot_plan
  installiere_snapper
  konfiguriere_snapper

  success "Snapshots vorbereitet."
}

# =========================
# 🔒 Checks
# =========================

pruefe_snapshot_variablen() {
  [[ -n "${ROOT_DEVICE:-}" ]] || { error "ROOT_DEVICE fehlt."; exit 1; }

  if [[ "${DRY_RUN:-true}" != true ]]; then
    mountpoint -q /mnt || {
      error "/mnt ist nicht gemountet."
      exit 1
    }

    mountpoint -q /mnt/.snapshots || {
      error "/mnt/.snapshots ist nicht gemountet. BTRFS-Modul muss @snapshots mounten."
      exit 1
    }

    findmnt -n -o FSTYPE /mnt/.snapshots | grep -qx "btrfs" || {
      error "/mnt/.snapshots ist kein BTRFS-Mount."
      exit 1
    }
  fi
}

# =========================
# 📋 Plan anzeigen
# =========================

zeige_snapshot_plan() {
  header "Geplanter Snapshot-Aufbau"

  echo "Tool: snapper"
  echo "Konfiguration:"
  echo "  root → /"
  echo

  warn "Dieses Modul richtet Snapshots für BTRFS ein."
  echo
}

# =========================
# 📦 Installation
# =========================

installiere_snapper() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde snapper installieren"
    return 0
  fi

  log "Installiere snapper..."

  arch-chroot /mnt pacman -S --noconfirm snapper || {
    error "Snapper konnte nicht installiert werden."
    exit 1
  }
}

# =========================
# ⚙ Snapper konfigurieren
# =========================

konfiguriere_snapper() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde snapper root-Konfiguration manuell erstellen"
    warn "[DRY-RUN] würde vorhandenes @snapshots-Subvolume verwenden"
    warn "[DRY-RUN] würde Rechte für /mnt/.snapshots setzen"
    return 0
  fi

  log "Konfiguriere snapper manuell..."

  mkdir -p /mnt/etc/snapper/configs
  mkdir -p /mnt/.snapshots

  if [[ ! -f /mnt/etc/snapper/configs/root ]]; then
    cat > /mnt/etc/snapper/configs/root <<'EOF'
SUBVOLUME="/"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS="wheel"
SYNC_ACL="yes"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="50"
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="10"
TIMELINE_LIMIT_DAILY="10"
TIMELINE_LIMIT_WEEKLY="3"
TIMELINE_LIMIT_MONTHLY="10"
TIMELINE_LIMIT_YEARLY="10"
EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="1800"
EOF
  else
    warn "Snapper-Konfiguration root existiert bereits, überspringe."
  fi

  if [[ -f /mnt/etc/conf.d/snapper ]]; then
    sed -i 's/^SNAPPER_CONFIGS=.*/SNAPPER_CONFIGS="root"/' /mnt/etc/conf.d/snapper
  else
    mkdir -p /mnt/etc/conf.d
    echo 'SNAPPER_CONFIGS="root"' > /mnt/etc/conf.d/snapper
  fi

  # Gruppen-Rechte für wheel setzen, damit der User Snapshots lesen kann
  arch-chroot /mnt chown root:wheel /.snapshots
  chmod 750 /mnt/.snapshots || {
    error "Rechte für /mnt/.snapshots konnten nicht gesetzt werden."
    exit 1
  }

  success "Snapper konfiguriert."
}
