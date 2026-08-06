# philfed
Fedora Everything → Minimal Install
Login to TTY
sudo setfont -d

sudo dnf install -y wget

wget https://raw.githubusercontent.com/philmcevatt/philfed/main/philfed.sh

chmod +x philfed.sh

sudo ./philfed.sh

reboot


or


wget https://tinyurl.com/philfedsh

chmod +x philfedsh

sudo ./philfedsh

reboot


# Recommended Fedora Everything partitioning:
using blivet custom partition manager

1gb /boot/efi
4gb /boot
50gb btrfs partition containing btrfs subvolume labled as root and mounted at /
50gb btrfs partition containing btrfs subvolume labled as home and mounted at /home
45gb btrfs partition containing btrfs subvolume labled as games and mounted at /games
