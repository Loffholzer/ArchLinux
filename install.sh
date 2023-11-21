#!/bin/bash
##-----------------------------------------------------------------------------------
## author:       Loffholzer
## project:      https://github.com/Loffholzer/ArchLinux/install.sh
## version:      0.0.1
## licence:      MIT
## date:         2023-11-23
##-----------------------------------------------------------------------------------


##---------------------------------------------------------------------------------------
## Edit /etc/pacman.conf
##---------------------------------------------------------------------------------------
cp -f /etc/pacman.conf /etc/pacman.conf.org
echo -e "### --- modified by Loffholzer install.sh\n" >/etc/pacman.conf
echo -e "### --- Date: $(date "+%Y-%m-%d | %R")\n" >>/etc/pacman.conf
echo -e "### --- (Original-Backup: /etc/pacman.conf.org)\n" >>/etc/pacman.conf
echo -e "###\n" >>/etc/pacman.conf
cat /etc/pacman.conf.org >>/etc/pacman.conf
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sed -i '/^#VerbosePkgLists/s/#//' /etc/pacman.conf
sed -i '/^#Color/s/#//' /etc/pacman.conf
sed -i '/Color/s//&\nILoveCandy/' /etc/pacman.conf

##---------------------------------------------------------------------------------------
## Edit /etc/pacman.d/mirrorlist
##---------------------------------------------------------------------------------------
cp -f /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.org
pacman -Sy
pacman -S --noconfirm --needed reflector
reflector -a 24 -f 10 -c de -p https --sort rate --save /etc/pacman.d/mirrorlist --verbose
cp -f /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.tmp
echo -e "### --- modified by Loffholzer install.sh\n" >/etc/pacman.d/mirrorlist
echo -e "### --- Date: $(date "+%Y-%m-%d | %R")\n" >>/etc/pacman.d/mirrorlist
echo -e "### --- (Original-Backup: /etc/pacman.d/mirrorlist.org)\n" >>/etc/pacman.d/mirrorlist
echo -e "###\n" >>/etc/pacman.d/mirrorlist
cat /etc/pacman.d/mirrorlist.tmp >>/etc/pacman.d/mirrorlist
rm -rf /etc/pacman.d/mirrorlist.tmp

##---------------------------------------------------------------------------------------
## Edit /etc/nanorc
##---------------------------------------------------------------------------------------
pacman -S --noconfirm --needed nano nano-syntax-highlighting
cp -f /etc/nanorc /etc/nanorc.org
echo -e "### --- modified by Loffholzer install.sh\n" >/etc/nanorc
echo -e "### --- Date: $(date "+%Y-%m-%d | %R")\n" >>/etc/nanorc
echo -e "### --- (Original-Backup: /etc/nanorc.org)\n" >>/etc/nanorc
echo -e "###\n" >>/etc/nanorc
cat /etc/nanorc.org >>/etc/nanorc
sed -i '/#.set.linenumbers/s/^#.//' /etc/nanorc || return 1
sed -i '/#.set.softwrap/s/^#.//' /etc/nanorc
sed -i '/nano\/\*\.nanorc/s/^#.//' /etc/nanorc

##---------------------------------------------------------------------------------------
## Install
##---------------------------------------------------------------------------------------
pacman -S --needed - <basis.txt
pacman -S --needed - <basis.txt
pacman -S --needed - <basis.txt
pacman -S --needed - <basis.txt

##---------------------------------------------------------------------------------------
## enable services
##---------------------------------------------------------------------------------------
