# philfed
Fedora Everything → Minimal Install

Login to TTY

sudo setfont -d

sudo dnf install -y wget

wget https://raw.githubusercontent.com/philmcevatt/philfed/main/philfed.sh

or

wget https://tinyurl.com/philfedsh

chmod +x philfed.sh

sudo ./philfed.sh

reboot


# Recommended Fedora Everything partitioning:

/boot/efi    1GB        FAT32

/boot        2GB        ext4      boot flag

/            100GB      Btrfs

/home        150GB      Btrfs

/games       remainder  Btrfs

Unallocated  ~100GB free for distro testing
