#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      10_snapshot_boot.sh
# Zweck:     Snapshot-Boot in Limine integrieren
#
# Aufgabe:
# - erkennt valide Snapper-Snapshots
# - erzeugt Recovery-Boot-Einträge
# - aktualisiert Snapshot-Block in limine.conf
#
# Wichtig:
# - kaputte Snapshots dürfen nie gebootet werden
# - Haupt-Bootmenü muss immer intakt bleiben
# - falsche Snapshot-Cmdline = Recovery-Fail
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. DRY_RUN respektieren
# 2. Nur valide Snapshots eintragen
# 3. limine.conf atomar ersetzen
# 4. Ohne Snapshots weiterhin bootfähig bleiben
# =========================================

# =========================================
# 🚀 Snapshot-Boot ausführen
# -----------------------------------------
# Sammelt Snapshots und aktualisiert Limine
# → ergänzt Recovery-Einträge ohne Hauptboot zu brechen
# =========================================

run_snapshot_boot_setup() {
  header "10 - Snapshot Boot"

  pruefe_snapshot_boot_variablen
  zeige_snapshot_boot_plan
  sammle_valide_snapshots
  aktualisiere_limine_snapshot_block

  success "Snapshot-Boot vorbereitet."
}

# =========================================
# 🔒 Snapshot-Boot Eingaben prüfen
# -----------------------------------------
# Validiert ROOT_DEVICE, /mnt und limine.conf
# → stoppt vor defekter Bootmenü-Änderung
# =========================================

pruefe_snapshot_boot_variablen() {
  guard_require_var ROOT_DEVICE

  if [[ "${DRY_RUN:-true}" != true ]]; then
    guard_mnt_valid_root

    [[ -f /mnt/boot/limine.conf ]] || {
      error "limine.conf fehlt"
      exit 1
    }
  fi
}

# =========================================
# 📋 Snapshot-Boot Plan anzeigen
# -----------------------------------------
# Zeigt Quelle und Ziel der Integration
# → Sichtprüfung vor Bootmenü-Änderung
# =========================================

zeige_snapshot_boot_plan() {
  header "Geplanter Snapshot-Boot"

  echo "Quelle: Snapper"
  echo "Ziel: limine.conf"
  echo
}

# =========================================
# 🔎 Valide Snapshots sammeln (FINAL SAFE)
# -----------------------------------------
# Nur strukturell valide Snapshots
# → verhindert Boot von kaputten Snapshots
# =========================================

sammle_valide_snapshots() {
  VALID_SNAPSHOTS=()

  if [[ "${DRY_RUN:-true}" == true ]]; then
    return 0
  fi

  local base="/mnt/.snapshots"

  [[ -d "$base" ]] || return 0

  while IFS= read -r snap; do
    local id
    id="$(basename "$(dirname "$snap")")"

    [[ -f "$snap/etc/os-release" ]] || continue
    [[ -d "$snap/usr" ]] || continue

    VALID_SNAPSHOTS+=("$id")

  done < <(find "$base" -mindepth 2 -maxdepth 2 -type d -name snapshot | sort -Vr | head -n 5)

  export VALID_SNAPSHOTS
}

# =========================================
# 🧠 Snapshot-Cmdline bauen
# -----------------------------------------
# Erstellt Root-/LUKS-Parameter für Snapshot
# → falsche UUID/Subvol macht Recovery unbootbar
# =========================================

build_snapshot_cmdline() {
  local snapshot_id="$1"
  local subvol="@snapshots/${snapshot_id}/snapshot"
  local root_uuid

  [[ -n "$snapshot_id" ]] || {
    error "Snapshot-ID fehlt"
    return 1
  }

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    guard_require_var ROOT_BASE_DEVICE
    guard_require_var ROOT_MAPPER_NAME

    root_uuid="$(blkid -s UUID -o value "$ROOT_BASE_DEVICE")"

    [[ -n "$root_uuid" ]] || {
      error "LUKS UUID fehlt für Snapshot ${snapshot_id}"
      return 1
    }

    echo "cryptdevice=UUID=${root_uuid}:${ROOT_MAPPER_NAME} root=/dev/mapper/${ROOT_MAPPER_NAME} rootflags=subvol=${subvol} ro systemd.volatile=overlay"
  else
    guard_require_var ROOT_DEVICE

    root_uuid="$(blkid -s UUID -o value "$ROOT_DEVICE")"

    [[ -n "$root_uuid" ]] || {
      error "Root UUID fehlt für Snapshot ${snapshot_id}"
      return 1
    }

    echo "root=UUID=${root_uuid} rootflags=subvol=${subvol} ro systemd.volatile=overlay"
  fi
}

# =========================================
# 📝 Snapshot-Einträge erzeugen
# -----------------------------------------
# Baut Limine-Menüeinträge für valide Snapshots
# → leerer Fallback bleibt ungefährlich
# =========================================

generiere_snapshot_entries() {
  local microcode_path=""

  if [[ "${MICROCODE_PKG:-}" == "intel-ucode" ]]; then
    microcode_path="/intel-ucode.img"
  elif [[ "${MICROCODE_PKG:-}" == "amd-ucode" ]]; then
    microcode_path="/amd-ucode.img"
  fi

  echo "/Snapshots"

  if [[ "${#VALID_SNAPSHOTS[@]}" -eq 0 ]]; then
    echo "    //Keine Snapshots vorhanden"
    return 0
  fi

  local id

  for id in "${VALID_SNAPSHOTS[@]}"; do
    local cmdline

    cmdline="$(build_snapshot_cmdline "$id")" || continue

    cat <<EOF
    /Snapshot ${id} [Recovery]
        protocol: linux
        kernel_path: boot():/vmlinuz-linux
EOF

    if [[ -n "$microcode_path" ]]; then
      cat <<EOF
        module_path: boot():${microcode_path}
EOF
    fi

    cat <<EOF
        module_path: boot():/initramfs-linux.img
        cmdline: ${cmdline}

EOF
  done
}

# =========================================
# 🔄 Snapshot-Block ersetzen
# -----------------------------------------
# Ersetzt Snapshot-Bereich in limine.conf
# atomar, ohne Haupt-Bootentries anzufassen
# → Hauptboot bleibt auch bei Fehler intakt
# =========================================

aktualisiere_limine_snapshot_block() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde limine Snapshot Block aktualisieren"
    return 0
  fi

  local config="/mnt/boot/limine.conf"
  local tmp_config
  local tmp_entries

  [[ -f "$config" ]] || {
    error "limine.conf fehlt"
    exit 1
  }

  grep -q '^#+SNAPSHOT_ENTRIES_BEGIN$' "$config" || {
    error "Snapshot-Block BEGIN fehlt → breche ab"
    exit 1
  }

  grep -q '^#+SNAPSHOT_ENTRIES_END$' "$config" || {
    error "Snapshot-Block END fehlt → breche ab"
    exit 1
  }

  tmp_config="$(mktemp)"
  tmp_entries="$(mktemp)"

  generiere_snapshot_entries > "$tmp_entries"

  awk -v entries="$tmp_entries" '
    /^#\+SNAPSHOT_ENTRIES_BEGIN$/ {
      print
      while ((getline line < entries) > 0) print line
      close(entries)
      skip=1
      next
    }

    /^#\+SNAPSHOT_ENTRIES_END$/ {
      skip=0
      print
      next
    }

    skip != 1 {
      print
    }
  ' "$config" > "$tmp_config"

  grep -q "protocol: linux" "$tmp_config" || {
    rm -f "$tmp_config" "$tmp_entries"
    error "Neue limine.conf enthält keine Linux-Einträge → ersetze nicht"
    exit 1
  }

  grep -q '^#+SNAPSHOT_ENTRIES_BEGIN$' "$tmp_config" || {
    rm -f "$tmp_config" "$tmp_entries"
    error "Neue limine.conf enthält keinen Snapshot BEGIN Marker → ersetze nicht"
    exit 1
  }

  grep -q '^#+SNAPSHOT_ENTRIES_END$' "$tmp_config" || {
    rm -f "$tmp_config" "$tmp_entries"
    error "Neue limine.conf enthält keinen Snapshot END Marker → ersetze nicht"
    exit 1
  }

  run_cmd install -m 644 "$tmp_config" "$config"

  rm -f "$tmp_config" "$tmp_entries"

  success "Snapshot-Boot aktualisiert."
}
