# philfed
Fedora Everything → Minimal Install

Login to TTY

sudo setfont -d

sudo dnf install -y wget

wget https://raw.githubusercontent.com/philmcevatt/philfed/main/philfed.sh

chmod +x philfed.sh

sudo ./philfed.sh

reboot


Recommended Fedora Everything partitioning:

/boot/efi  1GB  FAT32
/boot      2GB  ext4
/           150GB Btrfs
/games      remainder Btrfs
