#!/usr/bin/env bash

# =========================================
# 10_snapshot_boot.sh
# -----------------------------------------
# Aufgabe:
# - bereitet spätere Snapshot-Boot-Integration vor
# - soll später Limine-Snapshot-Einträge generieren
# - aktuell sicherer Platzhalter
#
# Voraussetzung:
# - Snapper wurde in 07 vorbereitet
# - Limine wurde in 08 eingerichtet
# =========================================

# =========================
# 🚀 Snapshot-Boot Setup ausführen
# =========================

run_snapshot_boot_setup() {
  header "10 - Snapshot Boot"

  pruefe_snapshot_boot_variablen
  zeige_snapshot_boot_plan
  finde_snapper_snapshots
  aktualisiere_limine_snapshot_block
  installiere_snapshot_automatisierung

  success "Snapshot-Boot vorbereitet."
}

# =========================
# 🔒 Checks
# =========================

pruefe_snapshot_boot_variablen() {
  [[ -n "${ROOT_DEVICE:-}" ]] || { error "ROOT_DEVICE fehlt."; exit 1; }

  if [[ "${DRY_RUN:-true}" != true ]]; then
    mountpoint -q /mnt || {
      error "/mnt ist nicht gemountet."
      exit 1
    }

    [[ -f /mnt/boot/limine.conf ]] || {
      error "Limine-Konfiguration fehlt: /mnt/boot/limine.conf"
      exit 1
    }
  fi
}

# =========================
# 📋 Plan anzeigen
# =========================

zeige_snapshot_boot_plan() {
  header "Geplanter Snapshot-Boot"

  echo "Bootloader: Limine"
  echo "Quelle:     Snapper / BTRFS"
  echo "Ziel:       Snapshot-Einträge in limine.conf"
  echo
  echo "Aktueller Stand:"
  echo "  - Snapshot-Verzeichnis wird erkannt"
  echo "  - Boot-Einträge werden später daraus generiert"
  echo

  warn "Snapshot-Boot wird vorbereitet, aber noch nicht vollständig aktiviert."
  echo
}

# =========================
# 📝 Limine Snapshot-Block aktualisieren
# =========================

aktualisiere_limine_snapshot_block() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Snapshot-Block in /mnt/boot/limine.conf aktualisieren"
    warn "[DRY-RUN] würde Snapshot-Menüeinträge generieren"
    return 0
  fi

  local config="/mnt/boot/limine.conf"
  local tmp_config
  local tmp_entries

  [[ -f "$config" ]] || {
    error "Limine-Konfiguration fehlt: $config"
    exit 1
  }

  grep -q '^#+SNAPSHOT_ENTRIES_BEGIN$' "$config" || {
    error "Snapshot-Startmarker fehlt in limine.conf."
    exit 1
  }

  grep -q '^#+SNAPSHOT_ENTRIES_END$' "$config" || {
    error "Snapshot-Endmarker fehlt in limine.conf."
    exit 1
  }

  tmp_config="$(mktemp)" || {
    error "Temporäre Config-Datei konnte nicht erstellt werden."
    exit 1
  }

  tmp_entries="$(mktemp)" || {
    rm -f "$tmp_config"
    error "Temporäre Entry-Datei konnte nicht erstellt werden."
    exit 1
  }

  generiere_snapshot_entries > "$tmp_entries" || {
    rm -f "$tmp_config" "$tmp_entries"
    error "Snapshot-Einträge konnten nicht generiert werden."
    exit 1
  }

  awk -v entries_file="$tmp_entries" '
    /^#\+SNAPSHOT_ENTRIES_BEGIN$/ {
      print
      while ((getline line < entries_file) > 0) {
        print line
      }
      close(entries_file)
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
  ' "$config" > "$tmp_config" || {
    rm -f "$tmp_config" "$tmp_entries"
    error "Snapshot-Block konnte nicht aktualisiert werden."
    exit 1
  }

  cat "$tmp_config" > "$config" || {
    rm -f "$tmp_config" "$tmp_entries"
    error "limine.conf konnte nicht geschrieben werden."
    exit 1
  }

  rm -f "$tmp_config" "$tmp_entries"

  success "Limine Snapshot-Block aktualisiert."
}

# =========================
# 🔎 Snapper-Snapshots erkennen
# =========================

finde_snapper_snapshots() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde die letzten bootfähigen Snapper-Snapshots unter /mnt/.snapshots suchen"
    return 0
  fi

  local snapshot_dir="/mnt/.snapshots"
  local max_snapshots=5

  [[ -d "$snapshot_dir" ]] || {
    warn "Snapshot-Verzeichnis nicht gefunden: $snapshot_dir"
    return 0
  }

  find "$snapshot_dir" \
    -mindepth 2 \
    -maxdepth 2 \
    -type d \
    -name "snapshot" \
    | sort -Vr \
    | head -n "$max_snapshots"
}

# =========================
# 🧩 Snapshot-Menüeinträge generieren
# =========================

generiere_snapshot_entries() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    echo "/Snapshots"
    echo "    //Info"
    echo "        comment: Snapshot-Boot wird später dynamisch generiert."
    return 0
  fi

  local snapshot snapshot_id snapshot_date snapshot_cmdline
  local found=false
  local entries=""

  while IFS= read -r snapshot; do
    snapshot_id="$(basename "$(dirname "$snapshot")")"

    snapshot_date="Snapshot ${snapshot_id}"
    if [[ -f "/mnt/.snapshots/${snapshot_id}/info.xml" ]]; then
      snapshot_date="$(grep -oPm1 '(?<=<date>)[^<]+' "/mnt/.snapshots/${snapshot_id}/info.xml" 2>/dev/null || echo "Snapshot ${snapshot_id}")"
    fi

    snapshot_cmdline="$(baue_snapshot_cmdline "$snapshot_id")" || {
      warn "CMDLINE für Snapshot ${snapshot_id} fehlgeschlagen, überspringe."
      continue
    }

    found=true
    entries+=$(schreibe_snapshot_entry "$snapshot_date" "$snapshot_id" "$snapshot_cmdline")
    entries+=$'\n'
  done < <(finde_snapper_snapshots)

  echo "/Snapshots"
  if [[ "$found" == false ]]; then
    echo "    //Keine Snapshots"
    echo "        comment: Aktuell keine bootfähigen Snapshots vorhanden."
  else
    echo -e "$entries"
  fi
}

# =========================
# 🧠 Snapshot Kernel-CMDLINE bauen
# =========================

baue_snapshot_cmdline() {
  local snapshot_id="$1"
  local root_uuid
  local snapshot_subvol
  local cmdline

  root_uuid="$(blkid -s UUID -o value "$ROOT_DEVICE" 2>/dev/null || true)"

  [[ -n "$root_uuid" ]] || {
    error "UUID für ROOT_DEVICE konnte nicht ermittelt werden."
    return 1
  }

  snapshot_subvol="@snapshots/${snapshot_id}/snapshot"

  if [[ -n "${ROOT_MAPPER_NAME:-}" ]]; then
    local crypt_uuid

    [[ -n "${ROOT_BASE_DEVICE:-}" ]] || {
      error "ROOT_BASE_DEVICE fehlt für Snapshot-Boot."
      return 1
    }

    crypt_uuid="$(blkid -s UUID -o value "$ROOT_BASE_DEVICE" 2>/dev/null || true)"

    [[ -n "$crypt_uuid" ]] || {
      error "UUID für ROOT_BASE_DEVICE konnte nicht ermittelt werden."
      return 1
    }

    cmdline="cryptdevice=UUID=${crypt_uuid}:${ROOT_MAPPER_NAME} root=/dev/mapper/${ROOT_MAPPER_NAME} rootflags=subvol=${snapshot_subvol} ro"
  else
    cmdline="root=UUID=${root_uuid} rootflags=subvol=${snapshot_subvol} ro"
  fi

  echo "$cmdline"
}

# =========================
# 📝 Einzelnen Snapshot-Eintrag schreiben
# =========================

schreibe_snapshot_entry() {
  local snapshot_date="$1"
  local snapshot_id="$2"
  local snapshot_cmdline="$3"
  local ucode_name=""

  [[ "$MICROCODE_PKG" == "intel-ucode" ]] && ucode_name="intel-ucode.img"
  [[ "$MICROCODE_PKG" == "amd-ucode" ]] && ucode_name="amd-ucode.img"

  # Limine Syntax: // für Child-Nodes (Einträge im Untermenü)
  cat <<EOF
    //${snapshot_date} (ID: ${snapshot_id})
        protocol: linux
        kernel_path: boot():/vmlinuz-linux
EOF

  if [[ -n "$ucode_name" ]]; then
    echo "        module_path: boot():/${ucode_name}"
  fi

  cat <<EOF
        module_path: boot():/initramfs-linux.img
        cmdline: ${snapshot_cmdline}
EOF
}

# =========================
# 🔄 Snapshot-Automatisierung (Service & Script)
# =========================

installiere_snapshot_automatisierung() {
  if [[ "${DRY_RUN:-true}" == true ]]; then
    warn "[DRY-RUN] würde Snapshot-Automatisierung im Zielsystem installieren"
    return 0
  fi

  log "Installiere Snapshot-Update-Skript und Systemd-Trigger..."

  local update_script="/mnt/usr/local/bin/limine-snapper-update"

  # 1. Das Update-Skript im Zielsystem erstellen
  cat << 'EOF' > "$update_script"
#!/usr/bin/env bash
# Generiert Limine Snapshot-Einträge für die letzten 5 Snapshots

CONFIG="/boot/limine.conf"
SNAPSHOT_DIR="/.snapshots"
MAX_SNAPSHOTS=5

[[ -f "$CONFIG" ]] || exit 1

# Finde Microcode
UCODE=""
[[ -f "/boot/intel-ucode.img" ]] && UCODE="boot():/intel-ucode.img"
[[ -f "/boot/amd-ucode.img" ]] && UCODE="boot():/amd-ucode.img"

# Extrahiere aktuelle Root-CMDLINE (ohne subvol)
# Wir nehmen die CMDLINE vom Haupt-Arch-Eintrag und säubern sie
BASE_CMDLINE=$(grep -m1 "cmdline:" "$CONFIG" | sed 's/.*cmdline: //' | sed 's/rootflags=subvol=[^ ]*//g')

# Temporäre Datei für Einträge
TMP_ENTRIES=$(mktemp)

echo "/Snapshots" > "$TMP_ENTRIES"

found=false
for snap_dir in $(find "$SNAPSHOT_DIR" -maxdepth 1 -mindepth 1 -type d | sort -Vr | head -n "$MAX_SNAPSHOTS"); do
    id=$(basename "$snap_dir")
    [[ -f "$snap_dir/snapshot/etc/os-release" ]] || continue

    date="Snapshot $id"
    [[ -f "$snap_dir/info.xml" ]] && date=$(grep -oPm1 '(?<=<date>)[^<]+' "$snap_dir/info.xml")

    echo "    //${date} (ID: ${id})" >> "$TMP_ENTRIES"
    echo "        protocol: linux" >> "$TMP_ENTRIES"
    echo "        kernel_path: boot():/vmlinuz-linux" >> "$TMP_ENTRIES"
    [[ -n "$UCODE" ]] && echo "        module_path: ${UCODE}" >> "$TMP_ENTRIES"
    echo "        module_path: boot():/initramfs-linux.img" >> "$TMP_ENTRIES"
    echo "        cmdline: ${BASE_CMDLINE} rootflags=subvol=@snapshots/${id}/snapshot ro" >> "$TMP_ENTRIES"
    found=true
done

[[ "$found" == "false" ]] && echo "    //Keine Snapshots gefunden" >> "$TMP_ENTRIES"

# In limine.conf einfügen (Logik analog zum Installer)
awk -v entries_file="$TMP_ENTRIES" '
    /^#\+SNAPSHOT_ENTRIES_BEGIN$/ { print; while ((getline line < entries_file) > 0) { print line } close(entries_file); skip=1; next }
    /^#\+SNAPSHOT_ENTRIES_END$/ { skip=0; print; next }
    skip != 1 { print }
' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"

rm -f "$TMP_ENTRIES"
EOF

  chmod +x "$update_script"

  # 2. Systemd Service erstellen
  cat << EOF > /mnt/etc/systemd/system/limine-snapper-update.service
[Unit]
Description=Update Limine boot entries for Snapper snapshots
After=local-fs.target

[Service]
Type=oneshot
ExecStart=$update_script
EOF

  # 3. Systemd Path Unit erstellen (Überwacht den Snapshot-Ordner)
  cat << EOF > /mnt/etc/systemd/system/limine-snapper-update.path
[Unit]
Description=Monitor Snapper snapshots for Limine update

[Path]
PathChanged=/.snapshots
Unit=limine-snapper-update.service

[Install]
WantedBy=multi-user.target
EOF

  # 4. Trigger aktivieren
  arch-chroot /mnt systemctl enable limine-snapper-update.path
}
