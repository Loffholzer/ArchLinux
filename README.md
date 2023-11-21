# ArchLinux

- loadkeys de-latin1
- setfont ter-118b
- check inet (ip a)
- pacman -Syy
- archinstall:
    Keyboard layout:      de-latin1-nodeadkeys
    Mirror region:        Germany
    Locale Language:      de_DE
    Locale Encoding:      UTF-8
    Drives:
      select Drive
      Wipe all best default partition layout
      btrfs (use defaults)
    Encrytion             set pw
    Bootloader:           systemd-boot
    Swap:                 true (Z-RAM)
    Hostname:             a name
    Root-Password:        none (dissable)
    Add user:             with sudo permissions
    Profile:              minimal
    Audio:                none
    Kernels:              linux
    Additional packages:  nano git terminus-font
    Network config..:     Copy ISO network configuration..
    Timezone:             Europe/Berlin
    Auto time sync:       true
    Optional Repo:        none
      Install
      chroot              yes
- check /etc/fstab        (SSD)
    .....btrfs      rw,ssd,noatime,compression=zstd,subvolid.....
- check /etc/mkinitcpio.conf HOOKS=.....encrypt filesystem..... (sequence)
- reboot
