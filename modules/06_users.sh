#!/usr/bin/env bash

# =========================================
# 📦 Arch Installer Modul
# -----------------------------------------
# Name:      06_users.sh
# Zweck:     Users, Environment & Security
#
# Aufgabe:
# - User erstellen, Sudo-Rechte vergeben, Root locken
# - ZRAM und Firewalld konfigurieren
# - Fish, Starship, Zoxide & Aliase systemweit einrichten
# - Nano "VSCode-Style" konfigurieren
# - Paru (AUR-Helper) kompilieren
#
# Wichtig:
# - AUR-Build muss zwingend als Non-Root laufen
# - Firewalld-Zonen-Setup via sed (kein DBus in chroot)
# =========================================

# =========================================
# 👤 Funktion: users_accounts
# -----------------------------------------
# Zweck:    System-Identitäten einrichten
# Aufgabe:  User anlegen, Passwörter setzen, Wheel-Group
# =========================================
users_accounts() {
    phase_header "Chroot: Benutzer & Berechtigungen"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] User-Erstellung übersprungen."
        return 0
    fi

    log "Erstelle Benutzer '$USERNAME'..."
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USERNAME"

    log "Setze Passwörter..."
    echo "$USERNAME:$USER_PASSWORD" | arch-chroot /mnt chpasswd

    if [[ "$DISABLE_ROOT" == "yes" ]]; then
        log "Sichere Root-Account (Passwort-Login deaktiviert)..."
        arch-chroot /mnt passwd -l root >/dev/null
    else
        log "Setze Root-Passwort identisch zum User..."
        echo "root:$USER_PASSWORD" | arch-chroot /mnt chpasswd
    fi

    log "Konfiguriere Sudo (Wheel-Group)..."
    echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel

    success "Benutzerverwaltung abgeschlossen."
}

# =========================================
# 🛡️ Funktion: users_security
# -----------------------------------------
# Zweck:    System-Härtung und Performance
# Aufgabe:  ZRAM (RAM/2) und Firewalld (Home Zone)
# =========================================
users_security() {
    phase_header "Chroot: Security & ZRAM"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Security-Setup übersprungen."
        return 0
    fi

    log "Installiere ZRAM und Firewalld..."
    arch-chroot /mnt pacman -S --noconfirm zram-generator firewalld >/dev/null

    # 1. ZRAM (Dynamische Swap-Erstellung basierend auf RAM-Größe)
    log "Konfiguriere ZRAM (ram / 2)..."
    cat <<EOF > /mnt/etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF

    # 2. Firewalld (Standard auf Home-Profil setzen via Config)
    log "Konfiguriere Firewalld (DefaultZone = home)..."
    sed -i 's/^DefaultZone=.*/DefaultZone=home/' /mnt/etc/firewalld/firewalld.conf
    arch-chroot /mnt systemctl enable firewalld >/dev/null 2>&1

    # 3. SSH (falls gewünscht)
    if [[ "$INSTALL_SSH" == "yes" ]]; then
        log "Installiere und aktiviere OpenSSH..."
        arch-chroot /mnt pacman -S --noconfirm openssh >/dev/null
        arch-chroot /mnt systemctl enable sshd >/dev/null 2>&1
        # Hardening: Root-Login via SSH verbieten
        sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /mnt/etc/ssh/sshd_config
    fi

    success "Security-Module (ZRAM, Firewall, SSH) konfiguriert."
}

# =========================================
# 🍬 Funktion: users_pacman_target
# -----------------------------------------
# Zweck:    Pacman im Zielsystem optimieren
# Aufgabe:  Color, ILoveCandy und 10 Downloads setzen
# =========================================
users_pacman_target() {
    phase_header "Chroot: Pacman-Optimierung"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Pacman-Config für Zielsystem übersprungen."
        return 0
    fi

    local target_conf="/mnt/etc/pacman.conf"
    log "Optimiere $target_conf (Color, ILoveCandy, ParallelDownloads=10)..."

    # Color aktivieren
    sed -i 's/^#Color/Color/' "$target_conf"

    # ILoveCandy (Pac-Man Animation) direkt unter Color einfügen
    if ! grep -q "^ILoveCandy" "$target_conf"; then
        sed -i '/^Color/a ILoveCandy' "$target_conf"
    fi

    # Parallele Downloads auf 10 setzen
    sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' "$target_conf"
    if ! grep -q "^ParallelDownloads" "$target_conf"; then
        sed -i '/^#Misc options/a ParallelDownloads = 10' "$target_conf"
    fi

    success "Pacman im Zielsystem nach Vorgabe konfiguriert."
}

# =========================================
# 🎨 Funktion: users_shell_ux
# -----------------------------------------
# Zweck:    Professional Terminal Environment
# Aufgabe:  Fish, Starship, Nerd-Fonts und CLI-Tools
# =========================================
users_shell_ux() {
    if [[ "$INSTALL_SHELL" != "yes" ]]; then
        log "Erweiterte Shell-UX abgewählt. Überspringe."
        return 0
    fi

    phase_header "Chroot: Shell & UX (Fish + Starship)"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Shell-Setup übersprungen."
        return 0
    fi

    log "Installiere UX-Pakete..."
    # terminus-font für TTY, ttf-jetbrains-mono-nerd für GUI
    arch-chroot /mnt pacman -S --noconfirm \
        fish starship zoxide fastfetch eza bat btop \
        ttf-jetbrains-mono-nerd terminus-font >/dev/null

    log "Setze Fish als Standard-Shell für User und Root..."
    arch-chroot /mnt chsh -s /usr/bin/fish "$USERNAME"
    arch-chroot /mnt chsh -s /usr/bin/fish root

    log "Schreibe systemweite Fish-Config..."
    mkdir -p /mnt/etc/fish
    cat <<'EOF' > /mnt/etc/fish/config.fish
# --- System Init ---
set -g fish_greeting

# Starte fastfetch nur, wenn es installiert ist und wir interaktiv sind
if status is-interactive
    if type -q fastfetch
        fastfetch
    end
end

# --- Prompt & Navigation ---
# Starship Initialisierung
if type -q starship
    starship init fish | source
end

# Zoxide (Smart cd) Initialisierung
if type -q zoxide
    zoxide init fish | source
end

# --- Professional Aliases ---
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first'
alias la='eza -laa --icons --group-directories-first'
alias cat='bat --theme="Monokai Extended"'
alias top='btop'
alias cd='z'
alias update='sudo pacman -Syu'
EOF

    success "Shell-UX (Fish) erfolgreich eingerichtet."
}

# =========================================
# 📝 Funktion: users_editor
# -----------------------------------------
# Zweck:    Nano Virtuoso Setup
# Aufgabe:  Line-Numbers, Mouse, Syntax, Auto-Indent
# =========================================
users_editor() {
    if [[ "$INSTALL_EDITOR" != "yes" ]]; then
        return 0
    fi

    phase_header "Chroot: Editor (Nano)"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Nano-Config übersprungen."
        return 0
    fi

    log "Installiere Nano..."
    arch-chroot /mnt pacman -S --noconfirm nano syntax-highlighting >/dev/null 2>&1 || true

    log "Konfiguriere /etc/nanorc..."
    cat <<EOF >> /mnt/etc/nanorc

# ========================
# Custom Virtuoso Config
# ========================
set linenumbers
set mouse
set autoindent
set tabsize 4
set tabstospaces
set softwrap
set indicator
set minibar

# Syntax Highlighting aktivieren
include "/usr/share/nano/*.nanorc"
EOF

    success "Nano konfiguriert (Virtuoso-Modus)."
}

# =========================================
# 📦 Funktion: users_aur
# -----------------------------------------
# Zweck:    AUR Helper installieren
# Aufgabe:  Baut paru-bin als unprivilegierter User
# =========================================
users_aur() {
    if [[ "$INSTALL_AUR" != "yes" ]]; then
        return 0
    fi

    phase_header "Chroot: AUR Helper (Paru)"

    if [[ "${DRY_RUN:-true}" == true ]]; then
        warn "[DRY-RUN] Paru-Build übersprungen."
        return 0
    fi

    log "Lade und baue paru-bin via makepkg (als User $USERNAME)..."

    # Der Build-Prozess darf nicht als root laufen. Wir wechseln per sudo -u.
    arch-chroot /mnt sudo -u "$USERNAME" bash -c '
        cd ~
        git clone https://aur.archlinux.org/paru-bin.git
        cd paru-bin
        makepkg -si --noconfirm
        cd ..
        rm -rf paru-bin
    ' >/dev/null 2>&1 || warn "Paru Build fehlgeschlagen (eventuell Netzwerk?)."

    success "Paru-bin erfolgreich installiert."
}

# =========================================
# ⚙️ Modul-Einstiegspunkt: run_users
# -----------------------------------------
# Zweck:    Sequenzielle Ausführung
# =========================================
run_users() {
    header "Phase 6: Users, Environment & Security"

    users_accounts
    users_security
    users_shell_ux
    users_editor
    users_aur
}
