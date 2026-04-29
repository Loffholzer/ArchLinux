#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      10_snapshot_boot.sh
# Zweck:     Snapshot-Boot Integration
#
# Aufgabe:
# - erkennt Snapper Snapshots
# - generiert sichere Boot-Einträge
# - aktualisiert limine.conf
#
# Wichtig:
# - NIEMALS kaputte Snapshots eintragen
# - Boot muss IMMER funktionieren
# =========================================
# ⚙️ Coding-Guidelines
# -----------------------------------------
# 1. Nur valide Snapshots verwenden
# 2. limine.conf atomar schreiben
# 3. Fallback: keine Snapshots → trotzdem bootbar
# =========================================


# =========================================
# 🚀 Snapshot-Boot orchestrieren
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
# 🔒 Variablen prüfen
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
# 📋 Plan anzeigen
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
# Nur Snapshots die wirklich bootfähig sind
# werden berücksichtigt
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

    # KRITISCH: Snapshot muss ein funktionierendes System enthalten
    if [[ ! -f "$snap/etc/os-release" ]]; then
      continue
    fi

    if [[ ! -f "$snap/boot/vmlinuz-linux" && ! -f /mnt/boot/vmlinuz-linux ]]; then
      continue
    fi

    VALID_SNAPSHOTS+=("$id")

  done < <(find "$base" -mindepth 2 -maxdepth 2 -type d -name snapshot | sort -Vr | head -n 5)

  export VALID_SNAPSHOTS
}


# =========================================
# 🧠 Snapshot CMDLINE bauen
# =========================================

build_snapshot_cmdline() {
  local snapshot_id="$1"

  local root_uuid
  root_uuid="$(blkid -s UUID -o value "$ROOT_DEVICE")"

  [[ -n "$root_uuid" ]] || return 1

  local subvol="@snapshots/${snapshot_id}/snapshot"

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    local crypt_uuid
    crypt_uuid="$(blkid -s UUID -o value "$ROOT_BASE_DEVICE")"

    echo "cryptdevice=UUID=${crypt_uuid}:${ROOT_MAPPER_NAME} root=/dev/mapper/${ROOT_MAPPER_NAME} rootflags=subvol=${subvol} ro systemd.volatile=overlay"
  else
    echo "root=UUID=${root_uuid} rootflags=subvol=${subvol} ro systemd.volatile=overlay"
  fi
}


# =========================================
# 📝 Snapshot-Einträge erzeugen
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
# 🔄 limine.conf Snapshot Block ersetzen
# -----------------------------------------
# Atomare Aktualisierung ohne Risiko
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
