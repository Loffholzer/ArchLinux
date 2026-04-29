# Arch Linux Installation

**1. Vorwort & Voraussetzungen**
* **Wichtiger Hinweis:** Die Nutzung erfolgt auf **eigene Gefahr**. Erstelle vorab ein Backup deiner Daten!

* **Voraussetzungen:** Du benötigst ein gebootetes Arch-Live-Medium im **UEFI-Modus**, eine Internetverbindung und eine leere (oder löschbare) Festplatte., 

* **Achtung:** Ein Neustart des Arch-Live-Mediums ist während dem Abarbeiten dieser Anleitung nicht zulässig, da die gesetzten Umgebungsvariablen nicht persistent sind und dadurch gelöscht würden.

* **Copy & Paste:** Alle Befehlsblöcke können **am Stück** kopiert und eingefügt werden. Das Skript gibt Rückmeldung, sobald ein Schritt fertig ist.

* **Tipp (SSH-Zugriff):** Für bequemes Kopieren vom Zweitgerät:
    1. Passwort setzen: `passwd`
    2. Verbinden: `ssh root@deine-ip-adresse`

---

**1. Daten sammeln für die Installation**
> In diesem Abschnitt legen wir die Grundsteine. Das Skript fragt deine Vorlieben ab (Tastatur, User, Hardware) und speichert diese in Variablen für den weiteren Verlauf.

> **SCHNELLDURCHGANG / MANUELLE EINGABE:**
> Wenn du die automatischen Abfragen (1.1 bis 1.8) überspringen willst oder die Hardware-Erkennung nicht nutzen möchtest, kannst du **direkt zu Punkt 1.9** springen. Dort kannst du alle Werte (User, Disk, Layout, etc.) in einem Menü manuell eingeben. Das Skript setzt dann Standardwerte ein, die du dort korrigieren kannst.

* **Optional: Schriftgröße im Live-System anpassen**
    ```bash
    setfont ter-132b
    ```

* **1.1 Tastatur-Konfiguration**
    ```bash
    clear; PS3=$'\n\033[1;33mWahl (Nr): \033[0m'; while true; do PRE=($(localectl list-keymaps | cut -d- -f1 | grep -E '^[a-z]{2}$' | sort -u)); printf "\n\033[1;34m--- TASTATUR-KONFIG ---\033[0m\n\n"; select p in "${PRE[@]}"; do if [ -n "$p" ]; then M=($(localectl list-keymaps | grep "^$p")); M+=("ZURUECK"); clear; printf "\n\033[1;34m--- $p ---\033[0m\n\n"; select o in "${M[@]}"; do if [ "$o" = "ZURUECK" ]; then clear; break; elif [ -n "$o" ]; then export MYKEYMAP="$o"; loadkeys "$o" 2>/dev/null; break 2; fi; done; break; fi; done; [ -n "$MYKEYMAP" ] && break; done; printf "\n\033[1;32m✓ Geladen: \033[1;36m$MYKEYMAP\033[0m\n"
    ```

* **1.2 System-Check & WLAN**
    ```bash
    clear; printf "\n\033[1;34m--- SYSTEM-CHECK ---\033[0m\n\n"; [ -d /sys/firmware/efi ] && printf "\033[1;32m✓ UEFI aktiv\033[0m\n" || printf "\033[1;31m✗ KEIN UEFI\033[0m\n"; if ping -c 1 archlinux.org >/dev/null 2>&1; then printf "\033[1;32m✓ Internet steht\033[0m\n"; else printf "\033[1;31m✗ Offline\033[0m\n"; read -p "$(printf "\033[1;33mWLAN einrichten? (j/n): \033[0m")" WYN; if [[ "$WYN" =~ ^[jy]$ ]]; then D=$(iwctl device list 2>/dev/null | grep "station" | awk '{print $2}' | head -n 1); [ -z "$D" ] && printf "\033[1;31mKein WLAN-Geraet\033[0m\n" || (printf "\033[1;36mScan...\033[0m\n"; iwctl station $D get-networks 2>/dev/null; read -p "$(printf "\033[1;33mSSID: \033[0m")" S; read -p "$(printf "\033[1;33mPasswort: \033[0m")" P; printf "\n\033[1;36mConnect...\033[0m\n"; iwctl --passphrase "$P" station $D connect "$S" 2>/dev/null && printf "\033[1;32m✓ Online\033[0m\n" || printf "\033[1;31m✗ Fehler\033[0m\n"); fi; fi
    ```

* **1.3 Zeitzone**
    ```bash
    clear; PS3=$'\n\033[1;33mWahl (Nr): \033[0m'; while true; do R=($(timedatectl list-timezones | cut -d/ -f1 | sort -u)); printf "\n\033[1;34m--- ZEITZONEN-AUSWAHL ---\033[0m\n\n"; select r in "${R[@]}"; do if [ -n "$r" ]; then if timedatectl list-timezones | grep -x "$r" >/dev/null; then export MYZONE="$r"; timedatectl set-timezone "$MYZONE" 2>/dev/null; break 2; fi; CI=($(timedatectl list-timezones | grep "^$r/")); CI+=("ZURUECK"); clear; printf "\n\033[1;34m--- $r ---\033[0m\n\n"; select i in "${CI[@]}"; do if [ "$i" = "ZURUECK" ]; then clear; break; elif [ -n "$i" ]; then export MYZONE="$i"; timedatectl set-timezone "$MYZONE" 2>/dev/null; break 2; fi; done; break; fi; done; [ -n "$MYZONE" ] && break; done; printf "\n\033[1;32m✓ Zeitzone: \033[1;36m$MYZONE\033[0m\n"
    ```

* **1.4 Sprache (Locale)**
    ```bash
    clear; while true; do printf "\n\033[1;34m--- SYSTEM-SPRACHE WAEHLEN ---\033[0m\n\n"; printf "\033[1;34mSuche (z.B. de, us): \033[0m"; read S; T=(${(f)"$(grep "\.UTF-8" /etc/locale.gen | sed 's/^#//g' | awk '{print $1}' | grep -iE "(^|_)$S" | sort -u)"}); if [ ${#T[@]} -eq 0 ]; then printf "\033[1;31mKein Treffer.\033[0m\n"; else PS3=$'\n\033[1;33mAuswahl: \033[0m'; select O in "${T[@]}" "Suche wiederholen"; do if [ "$O" = "Suche wiederholen" ]; then clear; break; elif [ -n "$O" ]; then export MYLOCALE="$O"; L_C=$(echo "$MYLOCALE" | cut -d'_' -f1); [[ " de fr it ja pl pt ro ru zh " =~ " $L_C " ]] && export MYMAN="man-pages-$L_C" || export MYMAN=""; break 2; fi; done; fi; done; printf "\n\033[1;32m✓ Sprache: \033[1;36m$MYLOCALE\033[0m | Manpages: \033[1;36m${MYMAN:-en (Standard)}\033[0m\n"
    ```

* **1.5 User- & Computername**
    ```bash
    clear; while true; do printf "\n\033[1;34m--- IDENTITAET ---\033[0m\n\n"; while true; do printf "\033[1;33mBenutzername: \033[0m"; read MYUSER; [[ "$MYUSER" =~ ^[a-z][a-z0-9_-]*$ ]] && [[ ! "$MYUSER" =~ ^(root|admin|guest|nobody|bin|daemon|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|gnats|systemd-.*|messagebus|avahi|polkitd|rtkit|arch|user|live|test)$ ]] && break || printf "\033[1;31mName reserviert oder ungueltig.\033[0m\n"; done; while true; do printf "\033[1;33mComputername: \033[0m"; read MYHOST; [[ "$MYHOST" =~ ^[a-z0-9-]+$ ]] && break || printf "\033[1;31mUngueltig (Nur klein, Zahlen und Bindestrich).\033[0m\n"; done; printf "\n\033[1;36m$MYUSER@$MYHOST\033[0m - Korrekt? (j/n): "; read c; [[ "$c" =~ ^[jy]$ ]] && export MYUSER MYHOST && break; clear; done; printf "\n\033[1;32m✓ Identitaet gespeichert.\033[0m\n"
    ```

* **1.6 Hardware-Erkennung**
    ```bash
    clear; printf "\n\033[1;34m--- HARDWARE-CHECK ---\033[0m\n\n"; [[ $(grep -m1 'vendor_id' /proc/cpuinfo) == *AuthenticAMD* ]] && export MYUCODE="amd-ucode" || export MYUCODE="intel-ucode"; GPU_V=$(lspci | grep -iE 'vga|3d' | tr '[:upper:]' '[:lower:]'); if [[ $GPU_V == *nvidia* ]]; then export MYGPU="nvidia"; elif [[ $GPU_V == *amd* ]]; then export MYGPU="amd"; elif [[ $GPU_V == *intel* ]]; then export MYGPU="intel"; else export MYGPU="generic"; fi; T_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}'); export MYRAM=$(( (T_KB + 1048576) / 1024 / 1024 )); printf "\033[1;32m✓ CPU:\033[0m \033[1;36m$MYUCODE\033[0m | \033[1;32mGPU:\033[0m \033[1;36m$MYGPU\033[0m | \033[1;32mRAM:\033[0m \033[1;36m${MYRAM}GB\033[0m\n"; sleep 2
    ```

* **1.7 Laufwerk wählen**
    ```bash
    clear; export MYDISK=""; while [ -z "$MYDISK" ]; do O=(${(f)"$(lsblk -dno NAME,SIZE,MODEL,LABEL,ROTA | grep -vE 'zram|loop' | awk '{d=$1" | "$2" | "$3; r=$NF; l=""; for(i=4; i<NF; i++) l=(l==""?"":l" ")$i; if(l!="") d=d" ["l"]"; print d"|"r}')"}); printf "\n\033[1;34m--- LAUFWERK-AUSWAHL ---\033[0m\n\n"; i=1; for item in "${O[@]}"; do display_info=$(echo "$item" | rev | cut -d'|' -f2- | rev); printf "\033[1;33m%2d)\033[0m %s\n" "$i" "$display_info"; ((i++)); done; printf "\n\033[1;33mWahl (Nr): \033[0m"; read NR; if [[ "$NR" -ge 1 && "$NR" -le ${#O[@]} ]]; then X="${O[$NR]}"; DN=$(echo "$X" | cut -d' ' -f1); DR=$(echo "$X" | awk -F"|" '{print $NF}'); D_TMP="/dev/$DN"; BO="noatime,compress=zstd,space_cache=v2"; if [ "$DR" = "0" ]; then T_TMP="ssd"; M_TMP="$BO,ssd,discard=async"; else T_TMP="hdd"; M_TMP="$BO,autodefrag"; fi; printf "\n\033[1;31mWARNUNG: $D_TMP ($T_TMP) wird geloescht.\033[0m\n\033[1;36mProfil-Flags: $M_TMP\033[0m\n"; printf "\033[1;33mFortfahren? (j/y/z): \033[0m"; read C; if [[ "$C" =~ ^[jyz]$ ]]; then export MYDISK="$D_TMP" MYTYPE="$T_TMP" MYMOUNT="$M_TMP"; break; else clear; printf "\033[1;31mAbgebrochen.\033[0m\n"; fi; else printf "\033[1;31mUngueltige Wahl.\033[0m\n"; sleep 1; fi; done; printf "\n\033[1;32m✓ Ziel gespeichert: \033[1;36m$MYDISK\033[0m\n"
    ```

* **1.8 Spiegelserver optimieren**
    ```bash
    clear; printf "\n\033[1;34m--- SPIEGELSERVER-CHECK ---\033[0m\n\n"; while true; do printf "\033[1;33mLand-Kürzel (z.B. de, us, at): \033[0m"; read S; S=$(echo "$S" | tr '[:upper:]' '[:lower:]'); if reflector --list-countries | grep -i " $S " >/dev/null; then export MYCOUNTRY="$S"; printf "\n\033[1;32m✓ Land '$MYCOUNTRY' ist gültig.\033[0m\n"; break; else printf "\n\033[1;31m✗ Kürzel '$S' nicht gefunden.\033[0m\n\033[1;36mTipp: Nutze 'de', 'at', 'ch' oder 'us'.\033[0m\n\n"; fi; done; sleep 1
    ```

* **1.9 Zusammenfassung & Manuelle Korrektur**
    ```bash
    : "${MYKEYMAP:=de-latin1}"; : "${MYZONE:=Europe/Berlin}"; : "${MYLOCALE:=de_DE.UTF-8}"; : "${MYMAN:=man-pages-de}"; : "${MYUSER:=archuser}"; : "${MYHOST:=arch-pc}"; : "${MYTYPE:=ssd}"; : "${MYMOUNT:=noatime,compress=zstd,space_cache=v2,ssd,discard=async}"; : "${MYCOUNTRY:=de}"; : "${MYUCODE:=intel-ucode}"; : "${MYGPU:=intel}"; : "${MYRAM:=8}"; while true; do clear; printf "\n\033[1;34m--- 1.9 FINALE KONTROLLE ---\033[0m\n\033[1;31mHINWEIS: Enter ohne Eingabe behaelt den Wert.\033[0m\n\n"; printf " 1) Tastatur:  \033[1;36m$MYKEYMAP\033[0m\n 2) Zone:      \033[1;36m$MYZONE\033[0m\n 3) Sprache:   \033[1;36m$MYLOCALE\033[0m\n 4) User:      \033[1;36m$MYUSER\033[0m\n 5) Host:      \033[1;36m$MYHOST\033[0m\n 6) Laufwerk:  \033[1;36m${MYDISK:-KEIN LAUFWERK}\033[0m\n 7) Typ/Mount: \033[1;36m$MYTYPE ($MYMOUNT)\033[0m\n 8) Reflector: \033[1;36m$MYCOUNTRY\033[0m\n 9) Hardware:  \033[1;36m$MYUCODE | $MYGPU | RAM: ${MYRAM}GB\033[0m\n10) Manpages:  \033[1;36m${MYMAN:-en}\033[0m\n\n\033[1;32m 0) ALLES OK - Weiter zu Teil 2\033[0m\n"; printf "\n\033[1;33mAendern (Nr): \033[0m"; read SEL; case $SEL in 1) printf "Layout: "; read T; [ -n "$T" ] && MYKEYMAP="$T";; 2) printf "Zone: "; read T; [ -n "$T" ] && MYZONE="$T";; 3) printf "Sprache: "; read T; [ -n "$T" ] && { MYLOCALE="$T"; L_C=$(echo "$T"|cut -d'_' -f1); [[ " de fr it ja pl pt ro ru zh " =~ " $L_C " ]] && MYMAN="man-pages-$L_C" || MYMAN=""; };; 4) printf "User: "; read T; [ -n "$T" ] && MYUSER="$T";; 5) printf "Host: "; read T; [ -n "$T" ] && MYHOST="$T";; 6) printf "Laufwerk: "; read T; [ -n "$T" ] && MYDISK="$T";; 7) printf "Typ (ssd/hdd): "; read T; [ -n "$T" ] && { MYTYPE="$T"; [[ "$T" == "ssd" ]] && MYMOUNT="noatime,compress=zstd,space_cache=v2,ssd,discard=async" || MYMOUNT="noatime,compress=zstd,space_cache=v2,autodefrag"; };; 8) printf "Land: "; read T; [ -n "$T" ] && MYCOUNTRY="$T";; 9) printf "Ucode (intel/amd): "; read T; [ -n "$T" ] && MYUCODE="${T%-ucode}-ucode"; printf "GPU: "; read T; [ -n "$T" ] && MYGPU="$T"; printf "RAM GB: "; read T; [ -n "$T" ] && MYRAM="$T";; 10) printf "Manpages: "; read T; [ -n "$T" ] && MYMAN="$T";; 0) if [[ -z "$MYDISK" || "$MYDISK" == "/dev/" ]]; then printf "\n\033[1;31mFEHLER: Laufwerk fehlt\033[0m\n"; sleep 2; else [[ $MYDISK == *nvme* ]] && P="p" || P=""; export PART_BOOT="${MYDISK}${P}1" PART_ROOT="${MYDISK}${P}2"; clear; printf "\n\033[1;32m--- SYSTEM-KONFIGURATION GELADEN ---\033[0m\n\n"; printf "\033[1;37m%-15s %-30s\033[0m\n" "SYSTEM:" "$MYHOST (User: $MYUSER)"; printf "\033[1;37m%-15s %-30s\033[0m\n" "DISK:" "$MYDISK ($MYTYPE)"; printf "\033[1;37m%-15s %-30s\033[0m\n" "PARTITIONEN:" "Boot: $PART_BOOT, Root: $PART_ROOT"; printf "\033[1;37m%-15s %-30s\033[0m\n" "REGION:" "$MYZONE ($MYLOCALE)"; printf "\033[1;37m%-15s %-30s\033[0m\n" "HARDWARE:" "$MYUCODE, $MYGPU, ${MYRAM}GB RAM"; printf "\033[1;37m%-15s %-30s\033[0m\n" "MIRRORS:" "$MYCOUNTRY"; printf "\033[1;37m%-15s %-30s\033[0m\n" "MOUNT-OPTS:" "$MYMOUNT"; printf "\n\033[1;32mBereit für Teil 2 (Partitionierung)...\033[0m\n"; break; fi;; *) printf "\033[1;31mUngueltig\033[0m\n"; sleep 1;; esac; done
    ```

---

**2. Installation**
> Die nachstehenden Befehle sind als kopierfähige Einheiten aufbereitet. Die Aufteilung in einzelne Blöcke dient der Übersicht und dem Verständnis der jeweiligen Schritte.


* **2.1 Partitionierung**
    ```bash
    [[ $MYDISK == *nvme* ]] && P="p" || P=""; \
    export PART_BOOT="${MYDISK}${P}1"; \
    export PART_ROOT="${MYDISK}${P}2"; \
    printf "\n\033[1;33mPartitioniere $MYDISK...\033[0m\n"; \
    sgdisk --zap-all $MYDISK; \
    sgdisk --clear $MYDISK; \
    sgdisk --new=1:0:+2G --typecode=1:ef00 --change-name=1:"EFI System" $MYDISK; \
    sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:"Linux filesystem" $MYDISK; \
    sgdisk --attributes=1:set:2 $MYDISK; \
    partprobe $MYDISK && sleep 2; \
    printf "\n\033[1;32m✓ Partitionen erstellt: $PART_BOOT (EFI), $PART_ROOT (ROOT)\033[0m\n"
    ```

* **2.2 Btrfs Layout & Formatierung**
    ```bash
    mkfs.fat -F32 -n "BOOT" $PART_BOOT; \
    mkfs.btrfs -f -L "ARCH" $PART_ROOT; \
    mount $PART_ROOT /mnt; \
    btrfs subvolume create /mnt/@; \
    btrfs subvolume create /mnt/@home; \
    btrfs subvolume create /mnt/@log; \
    btrfs subvolume create /mnt/@pkg; \
    btrfs subvolume create /mnt/@snapshots; \
    umount /mnt
    ```

* **2.3 Mounten der Struktur**
    ```bash
    mount -o $MYMOUNT,subvol=@ $PART_ROOT /mnt; \
    mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots}; \
    mount -o $MYMOUNT,subvol=@home $PART_ROOT /mnt/home; \
    mount -o $MYMOUNT,subvol=@log $PART_ROOT /mnt/var/log; \
    mount -o $MYMOUNT,subvol=@pkg $PART_ROOT /mnt/var/cache/pacman/pkg; \
    mount -o $MYMOUNT,subvol=@snapshots $PART_ROOT /mnt/.snapshots; \
    mount $PART_BOOT /mnt/boot
    ```
    
* **2.4 Spiegelserver-Optimierung** *
  ```bash
    mkdir -p /mnt/etc/pacman.d/; \
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.org; \
    printf "\n\033[1;34m--- SPIEGELSERVER-OPTIMIERUNG ---\033[0m\n"; \
    printf "\033[1;33mSuche die 10 schnellsten HTTPS-Server für Land: $MYCOUNTRY...\033[0m\n"; \
    printf "\033[1;36m(Dies kann je nach Verbindung einige Sekunden dauern)\033[0m\n\n"; \
    reflector --country "$MYCOUNTRY" --protocol https --latest 10 --sort rate --save /etc/pacman.d/mirrorlist; \
    cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist; \
    cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist.new; \
    grep "^Server" /mnt/etc/pacman.d/mirrorlist
    ```

* **2.5 Basis-Installation**  
    ```bash
    pacstrap /mnt base linux linux-headers linux-firmware
    ```
---

**3. System-Konfiguration**
> ** Die folgenden Schritte dienen der initialen Einrichtung sowie der Performance-Optimierung von dem neu installierten System.

* **3.1 Basis-Konfiguration**
    ```bash
    genfstab -U /mnt >> /mnt/etc/fstab && \
    ln -sf /usr/share/zoneinfo/$MYZONE /mnt/etc/localtime && \
    arch-chroot /mnt hwclock --systohc && \
    echo "$MYLOCALE UTF-8" > /mnt/etc/locale.gen && \
    echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen && \
    arch-chroot /mnt locale-gen && \
    echo "LANG=$MYLOCALE" > /mnt/etc/locale.conf && \
    echo "KEYMAP=$MYKEYMAP" > /mnt/etc/vconsole.conf && \
    echo "$MYHOST" > /mnt/etc/hostname && \
    printf "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t$MYHOST.localdomain\t$MYHOST\n" > /mnt/etc/hosts && \
    printf "\n\033[1;32m✓ Fstab generiert & Systemdaten gesetzt.\033[0m\n"
    ```

* **3.2 Pacman Optimierung**
    ```bash
    cp -f /mnt/etc/pacman.conf /mnt/etc/pacman.conf.org && \
    sed -i 's/^#Color/Color\nILoveCandy/' /mnt/etc/pacman.conf && \
    sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /mnt/etc/pacman.conf && \
    sed -i '/^#VerbosePkgLists/s/#//' /mnt/etc/pacman.conf && \
    sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf && \
    arch-chroot /mnt pacman -Sy && \
    printf "\n\033[1;32m✓ Pacman optimiert (Backup erstellt: /etc/pacman.conf.org).\033[0m\n"
    ```

* **3.3 Reflector Installation**
    ```bash
    arch-chroot /mnt pacman -S --needed --noconfirm reflector && \
    cp -f /mnt/etc/xdg/reflector/reflector.conf /mnt/etc/xdg/reflector/reflector.conf.org && \
    mkdir -p /mnt/etc/xdg/reflector && \
    cat << EOF > /mnt/etc/xdg/reflector/reflector.conf
    --save /etc/pacman.d/mirrorlist
    --protocol https
    --latest 10
    --sort rate
    --country $MYCOUNTRY
    EOF
    ```
* **3.4 Benutzer anlegen, sudo installation & root sperre**
    ```bash
    arch-chroot /mnt pacman -S --needed --noconfirm sudo && \
    arch-chroot /mnt useradd -m -G wheel $MYUSER && \
    echo "$MYUSER ALL=(ALL) ALL" > /mnt/etc/sudoers.d/$MYUSER && \
    printf "\n\033[1;33mPasswort fuer Benutzer '$MYUSER' setzen:\033[0m\n" && \
    arch-chroot /mnt passwd $MYUSER && \
    arch-chroot /mnt passwd -l root && \
    printf "\n\033[1;32m✓ Benutzer $MYUSER erstellt und Root-Login gesperrt.\033[0m\n"
    ```

* **3.5 Hardware-Treiber**
    ```bash
    # 3.6 Hardware-Treiber (Korrigiert für ZSH/Bash)
    arch-chroot /mnt pacman -S --needed --noconfirm "$MYUCODE" && \
    if [ "$MYGPU" = "nvidia" ]; then \
        arch-chroot /mnt pacman -S --needed --noconfirm nvidia-lts nvidia-utils; \
    elif [ "$MYGPU" = "amd" ]; then \
        arch-chroot /mnt pacman -S --needed --noconfirm mesa libva-mesa-driver mesa-vdpau vulkan-radeon; \
    elif [ "$MYGPU" = "intel" ]; then \
        arch-chroot /mnt pacman -S --needed --noconfirm mesa intel-media-driver; \
    else \
        arch-chroot /mnt pacman -S --needed --noconfirm mesa; \
    fi && \
    printf "\n\033[1;32m✓ Hardware-Pakete für $MYUCODE und $MYGPU installiert.\033[0m\n"
    ```

* **3.6 Software-Pakete & Tools**
    ```bash
    arch-chroot /mnt pacman -S --needed --noconfirm \
    man-db man-pages $MYMAN base-devel linux-lts linux-lts-headers \
    btrfs-progs btrfs-assistant efibootmgr networkmanager network-manager-applet \
    openssh git firewalld ipset acpid terminus-font bash-completion \
    nmap avahi fastfetch snapper snap-pac limine smartmontools pciutils usbutils \
    eza ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji ttf-dejavu \
    ttf-liberation duf nss-mdns p7zip unzip unrar gzip tar bzip2 lz4 \
    bat ripgrep fd earlyoom memtest86+-efi wget lynx zram-generator archlinux-wallpaper
    ```

* **3.7 zRAM & Initramfs**
    ```bash
    Z_SIZE=${MYRAM:-8}; \
    Z_LIMIT=$((Z_SIZE / 2)); \
    [ "$Z_LIMIT" -gt 4 ] && Z_LIMIT=4; \
    cat << EOF > /mnt/etc/systemd/zram-generator.conf
    [zram0]
    zram-size = min(ram / 2, 4096)
    compression-algorithm = zstd
    swap-priority = 100
    fs-type = swap
    EOF
    sed -i 's/^MODULES=(/MODULES=(btrfs /' /mnt/etc/mkinitcpio.conf && \
    arch-chroot /mnt mkinitcpio -P && \
    printf "\n\033[1;32m✓ zRAM-Generator konfiguriert & Initramfs aktualisiert.\033[0m\n"
    ```

* **3.8 Snapper**
    ```bash
    mkdir -p /mnt/etc/snapper/configs && \
    cat << EOF > /mnt/etc/snapper/configs/root
    SUBVOLUME="/"
    FSTYPE="btrfs"
    ALLOW_GROUPS="wheel"
    ALLOW_USERS="$MYUSER"
    TIMELINE_CREATE="yes"
    TIMELINE_CLEANUP="yes"
    TIMELINE_MIN_AGE="1800"
    TIMELINE_LIMIT_HOURLY="5"
    TIMELINE_LIMIT_DAILY="5"
    TIMELINE_LIMIT_WEEKLY="0"
    TIMELINE_LIMIT_MONTHLY="0"
    TIMELINE_LIMIT_YEARLY="0"
    EMPTY_PRE_POST_CLEANUP="yes"
    EMPTY_PRE_POST_MIN_AGE="1800"
    EOF
    if [ -f /mnt/etc/conf.d/snapper ]; then
        sed -i 's/SNAPPER_CONFIGS=""/SNAPPER_CONFIGS="root"/' /mnt/etc/conf.d/snapper
    else
        mkdir -p /mnt/etc/conf.d
        echo 'SNAPPER_CONFIGS="root"' > /mnt/etc/conf.d/snapper
    fi && \
    mkdir -p /mnt/.snapshots && \
    mount -o $MYMOUNT,subvol=@snapshots $PART_ROOT /mnt/.snapshots 2>/dev/null || true && \
    printf '\n\033[1;32m✓ Snapper-Config erstellt!\033[0m\n'
    ```

* **3.9 Bootloader (LIMINE)**
    ```bash
    arch-chroot /mnt mkdir -p /boot/EFI/limine /boot/EFI/BOOT && \
    arch-chroot /mnt cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/ && \
    arch-chroot /mnt cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI && \
    arch-chroot /mnt efibootmgr --create --disk $MYDISK --part 1 --label "Limine Boot Manager" --loader '\EFI\BOOT\BOOTX64.EFI' --unicode && \
    printf '\n\033[1;32m✓ Limine EFI-Eintrag erfolgreich erstellt!\033[0m\n' && \
    cp /mnt/usr/share/backgrounds/archlinux/geolanes.png /mnt/boot/splash.png
    ```

* **3.10 Automatisierung (CachyOS-Style Menü & Snapshots)**
    ```bash
    cat << 'EOF_SKRIPT' > /mnt/usr/local/bin/update-limine.sh
    #!/bin/bash
    ROOT_UUID=$(findmnt -no UUID /)
    BOOT_UUID=$(blkid -s UUID -o value $(findmnt -no SOURCE /boot))
    UCODE=$(ls /boot/ | grep -E '(intel|amd)-ucode.img' | head -n 1)
    printf "timeout: 5\nremember_last_entry: no\n" > /boot/limine.conf
    printf "term_wallpaper: guid($BOOT_UUID):/splash.png\n" >> /boot/limine.conf
    printf "term_background: 80000000\n\n" >> /boot/limine.conf
    printf ":Arch Linux\n    protocol: linux\n    path: guid($BOOT_UUID):/vmlinuz-linux\n" >> /boot/limine.conf
    [ -n "$UCODE" ] && printf "    module_path: guid($BOOT_UUID):/$UCODE\n" >> /boot/limine.conf
    printf "    module_path: guid($BOOT_UUID):/initramfs-linux.img\n    cmdline: root=UUID=$ROOT_UUID rw rootflags=subvol=@ quiet splash\n\n" >> /boot/limine.conf
    printf ":Arch Linux LTS\n    protocol: linux\n    path: guid($BOOT_UUID):/vmlinuz-linux-lts\n" >> /boot/limine.conf
    [ -n "$UCODE" ] && printf "    module_path: guid($BOOT_UUID):/$UCODE\n" >> /boot/limine.conf
    printf "    module_path: guid($BOOT_UUID):/initramfs-linux-lts.img\n    cmdline: root=UUID=$ROOT_UUID rw rootflags=subvol=@ quiet splash\n\n" >> /boot/limine.conf
    if command -v snapper >/dev/null; then
        printf "+Snapshots\n" >> /boot/limine.conf
        snapper list | tail -n +3 | tac | head -n 10 | while read -r line; do
            id=$(echo "$line" | awk '{print $1}')
            [[ ! "$id" =~ ^[0-9]+$ ]] && continue
            date=$(echo "$line" | awk '{print $3}')
            desc=$(echo "$line" | cut -d '|' -f 6 | xargs)
            printf "  :Snapshot $id ($date - $desc)\n    protocol: linux\n    path: guid($BOOT_UUID):/vmlinuz-linux\n" >> /boot/limine.conf
            [ -n "$UCODE" ] && printf "    module_path: guid($BOOT_UUID):/$UCODE\n" >> /boot/limine.conf
            printf "    module_path: guid($BOOT_UUID):/initramfs-linux.img\n    cmdline: root=UUID=$ROOT_UUID rw rootflags=subvol=@snapshots/\$id/snapshot quiet\n" >> /boot/limine.conf
        done
    fi
    mkdir -p /boot/EFI/limine
    cp /boot/limine.conf /boot/EFI/limine/limine.conf
    sed -i 's/\xc2\xa0/ /g' /boot/limine.conf
    sed -i 's/\xc2\xa0/ /g' /boot/EFI/limine/limine.conf
    EOF_SKRIPT
    chmod +x /mnt/usr/local/bin/update-limine.sh && \
    mkdir -p /mnt/etc/pacman.d/hooks && \
    cat << 'EOF_HOOK' > /mnt/etc/pacman.d/hooks/update-limine.hook
    [Trigger]
    Operation = Install
    Operation = Upgrade
    Operation = Remove
    Type = Package
    Target = *
    [Action]
    Description = Aktualisiere Limine Boot-Menü...
    When = PostTransaction
    Exec = /usr/local/bin/update-limine.sh
    EOF_HOOK
    arch-chroot /mnt /usr/local/bin/update-limine.sh && \
    printf '\n\033[1;32m✓ Limine-Konfiguration generiert!\033[0m\n'
    ```

* **3.11  AVAHI konfigurieren (_mDNS/DNS-SD_)**
    ```bash
    arch-chroot /mnt sed -i '/^hosts:/ s/\(files\|mymachines\)/& mdns_minimal [NOTFOUND=return]/' /etc/nsswitch.conf && \
    printf "\n\033[1;32m✓ nsswitch.conf für mDNS optimiert.\033[0m\n"
    ```

* **3.12 Dienste & Firewall**
    ```bash
    arch-chroot /mnt systemctl enable NetworkManager.service && \
    arch-chroot /mnt systemctl enable systemd-resolved.service && \
    arch-chroot /mnt systemctl enable avahi-daemon.service 
    arch-chroot /mnt systemctl enable sshd.service && \
    arch-chroot /mnt systemctl enable firewalld.service && \
    arch-chroot /mnt systemctl enable earlyoom.service && \
    arch-chroot /mnt systemctl enable fstrim.timer && \
    arch-chroot /mnt systemctl enable snapper-timeline.timer && \
    arch-chroot /mnt systemctl enable snapper-cleanup.timer && \
    arch-chroot /mnt firewall-offline-cmd --set-default-zone=home && \
    arch-chroot /mnt firewall-offline-cmd --zone=home --add-service=ssh && \
    arch-chroot /mnt firewall-offline-cmd --zone=home --add-service=mdns && \
    rm -f /mnt/etc/resolv.conf && \
    ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
    ```
---

**4. Extras**
> **Optionale Erweiterungen** ***(Empfohlen):*** Zur Optimierung des Workflows installieren wir Nano, Fish und Paru. Die Konfiguration erfolgt automatisiert, sodass die Tools sofort einsatzbereit sind.

> Ohne die optionalen Pakete geht es direkt weiter bei **Punkt 5: Abschluss & Neustart**.

* **4.1 Nano-Optimierung**
    ```bash
    arch-chroot /mnt pacman -S --needed --noconfirm nano nano-syntax-highlighting && \
    cp -f /mnt/etc/nanorc /mnt/etc/nanorc.org && \
    sed -i 's/^# set linenumbers/set linenumbers/' /mnt/etc/nanorc && \
    sed -i 's/^# set softwrap/set softwrap/' /mnt/etc/nanorc && \
    sed -i 's/^# set mouse/set mouse/' /mnt/etc/nanorc && \
    sed -i 's/^# set indicator/set indicator/' /mnt/etc/nanorc && \
    sed -i 's/^# set tabsize 8/set tabsize 4/' /mnt/etc/nanorc && \
    sed -i 's/^# set tabstospaces/set tabstospaces/' /mnt/etc/nanorc && \
    sed -i 's/^# set emptyline/set emptyline/' /mnt/etc/nanorc && \
    sed -i 's|^#\s*include\s*"/usr/share/nano/\*\.nanorc"|include "/usr/share/nano/*.nanorc"|' /mnt/etc/nanorc && \
    sed -i 's|^#\s*include\s*"/usr/share/nano-syntax-highlighting/\*\.nanorc"|include "/usr/share/nano-syntax-highlighting/*.nanorc"|' /mnt/etc/nanorc && \
    grep -q "nano-syntax-highlighting" /mnt/etc/nanorc || echo 'include "/usr/share/nano-syntax-highlighting/*.nanorc"' >> /mnt/etc/nanorc && \
    printf "\n\033[1;32m✓ Nano Pro-Konfiguration aktiv.\033[0m\n"
    ```

* **4.2 Shell-Konfiguration (Fish & Starship)**
    ```bash
    arch-chroot /mnt pacman -S --needed --noconfirm fish starship fzf fastfetch eza bat ripgrep && \
    arch-chroot /mnt chsh -s /usr/bin/fish root && \
    arch-chroot /mnt chsh -s /usr/bin/fish $MYUSER && \
    mkdir -p /mnt/root/.config/fish/conf.d /mnt/home/$MYUSER/.config/fish/conf.d && \
    cat << 'EOF_CONFIG' > /tmp/config.fish
    if status is-interactive
        fastfetch
        set -g fish_greeting ""
        starship init fish | source
        fish_default_key_bindings
        fzf_key_bindings
        # START_AUTO
        if test -f ~/setup.fish
            source ~/setup.fish
        end
        # END_AUTO
    end
    set -gx EDITOR nano
    set -gx VISUAL nano
    set -gx FZF_DEFAULT_OPTS "--height 40% --layout=reverse --border --color=dark"
    EOF_CONFIG
    cat << 'EOF_STARSHIP' > /tmp/starship.toml
    add_newline = false
    [directory]
    truncation_length = 3
    style = "bold cyan"
    [hostname]
    ssh_only = true
    style = "bold dimmed white"
    [username]
    show_always = true
    style_user = "bold blue"
    style_root = "bold red"
    format = "[$user]($style) "
    [character]
    success_symbol = "[➜](bold green)"
    error_symbol = "[➜](bold red)"
    [cmd_duration]
    min_time = 2000
    format = "🕒 [$duration]($style) "
    EOF_STARSHIP
    cat << 'EOF_ALIASES' > /tmp/aliases.fish
    alias ls='eza --color=always --icons --group-directories-first'
    alias ll='eza -l --color=always --icons --group-directories-first --git'
    alias la='eza -la --color=always --icons --group-directories-first --git'
    alias cat='bat --style=plain --paging=never'
    alias batl='bat --style=numbers,changes,header'
    alias fp="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"
    alias fe='nano (fzf)'
    alias p='paru'
    alias update='paru -Syu'
    alias install='paru -S'
    alias search='paru -Ss'
    alias remove='paru -Rns'
    alias ff='fastfetch'
    alias grep='rg'
    alias ..='cd ..'
    alias ...='cd ../..'
    EOF_ALIASES
    cp /tmp/config.fish /mnt/root/.config/fish/config.fish && \
    cp /tmp/config.fish /mnt/home/$MYUSER/.config/fish/config.fish && \
    cp /tmp/starship.toml /mnt/root/.config/starship.toml && \
    cp /tmp/starship.toml /mnt/home/$MYUSER/.config/starship.toml && \
    cp /tmp/aliases.fish /mnt/root/.config/fish/conf.d/aliases.fish && \
    cp /tmp/aliases.fish /mnt/home/$MYUSER/.config/fish/conf.d/aliases.fish && \
    arch-chroot /mnt chown -R $MYUSER:$MYUSER /home/$MYUSER/.config && \
    echo "Fertig! Shell-Setup abgeschlossen."
    ```

* **4.3 AUR-Helper (PARU) Vorbereitung**
    ```bash
    arch-chroot /mnt sudo -u $MYUSER bash -c "cd ~ && rm -rf paru-bin && git clone [https://aur.archlinux.org/paru-bin.git](https://aur.archlinux.org/paru-bin.git)" && \
    cat << 'EOF_SETUP' > /mnt/home/$MYUSER/setup.fish
    #!/usr/bin/fish
    echo " "
    echo "🚀 STARTE FINALES SYSTEM-SETUP..."
    echo "----------------------------------"
    if test -d ~/paru-bin
        echo "📦 Baue und installiere Paru (AUR Helper)..."
        cd ~/paru-bin
        makepkg -si --noconfirm
        cd ~
        rm -rf ~/paru-bin
    end
    sed -i '/# START_AUTO/,/# END_AUTO/d' ~/.config/fish/config.fish
    rm ~/setup.fish
    echo "----------------------------------"
    echo "✅ System bereinigt und bereit!"
    EOF_SETUP
    chmod +x /mnt/home/$MYUSER/setup.fish && \
    arch-chroot /mnt chown $MYUSER:$MYUSER /home/$MYUSER/setup.fish
    ```

* **5. Abschluss & Neustart**
    ```bash
    umount -R /mnt && reboot
    ```
