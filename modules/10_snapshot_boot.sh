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
    guard_mnt_mounted

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
# 🔎 Valide Snapshots sammeln
# -----------------------------------------
# Filtert Snapshots auf bootfähige Struktur
# → verhindert kaputte Recovery-Einträge
# =========================================

sammle_valide_snapshots() {
  VALID_SNAPSHOTS=()

  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Snapshots analysieren"
    return 0
  fi

  local base="/mnt/.snapshots"

  [[ -d "$base" ]] || return 0

  while IFS= read -r snap; do
    local id
    id="$(basename "$(dirname "$snap")")"

    [[ -f "$snap/etc/os-release" ]] || continue

    if [[ ! -f /mnt/boot/vmlinuz-linux ]]; then
      continue
    fi

    if [[ ! -f /mnt/boot/initramfs-linux.img ]]; then
      continue
    fi

    if [[ ! -d "$snap/usr/lib/modules" ]]; then
      continue
    fi

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

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    guard_require_var ROOT_BASE_DEVICE
    guard_require_var ROOT_MAPPER_NAME

    root_uuid="$(blkid -s UUID -o value "$ROOT_BASE_DEVICE")"

    [[ -n "$root_uuid" ]] || return 1

    echo "cryptdevice=UUID=${root_uuid}:${ROOT_MAPPER_NAME} root=/dev/mapper/${ROOT_MAPPER_NAME} rootflags=subvol=${subvol} ro systemd.volatile=overlay"
  else
    guard_require_var ROOT_DEVICE

    root_uuid="$(blkid -s UUID -o value "$ROOT_DEVICE")"

    [[ -n "$root_uuid" ]] || return 1

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
  if [[ "${#VALID_SNAPSHOTS[@]}" -eq 0 ]]; then
    echo "/Snapshots"
    echo "    //Keine Snapshots vorhanden"
    return 0
  fi

  echo "/Snapshots"

  local id
  for id in "${VALID_SNAPSHOTS[@]}"; do
    local cmdline
    cmdline="$(build_snapshot_cmdline "$id")" || continue

    cat <<EOF
    //Snapshot ${id} [Recovery]
        protocol: linux
        kernel_path: boot():/vmlinuz-linux
        module_path: boot():/initramfs-linux.img
        cmdline: ${cmdline}

EOF
  done
}

# =========================================
# 🔄 Snapshot-Block ersetzen
# -----------------------------------------
# Ersetzt Snapshot-Bereich in limine.conf
# → atomar, ohne Haupt-Bootentries anzufassen
# =========================================

aktualisiere_limine_snapshot_block() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde limine Snapshot Block aktualisieren"
    return 0
  fi

  local config="/mnt/boot/limine.conf"

  grep -q '^#+SNAPSHOT_ENTRIES_BEGIN$' "$config" || {
    warn "Kein Snapshot-Block vorhanden → überspringe"
    return 0
  }

  local tmp_config
  local tmp_entries

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
    skip != 1 { print }
  ' "$config" > "$tmp_config"

  run_cmd install -m 644 "$tmp_config" "$config"

  rm -f "$tmp_config" "$tmp_entries"

  success "Snapshot-Boot aktualisiert."
}
