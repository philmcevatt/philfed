#!/usr/bin/env bash
set -euo pipefail

# postinstall.sh
#
# Purpose:
# To go from Fedora Everything Install...
# Just chooes KDE on the right
# ... to end up with a stable KDE Gaming Desktop

############################################################
# INITIAL SAFETY CHECKS
############################################################

# This script must be launched from a normal user account through sudo.
if [[ "${EUID}" -ne 0 ]]; then
  echo "This script must be run with sudo:"
  echo "  sudo ./philfed.sh"
  exit 1
fi
TARGET_USER="${SUDO_USER:-}"
if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
  echo "Could not detect the normal user account."
  echo "Do not run this from a root shell or with su."
  echo "Run it from your normal account with:"
  echo "  sudo ./philfed.sh"
  exit 1
fi
if ! id "${TARGET_USER}" &>/dev/null; then
  echo "Detected user '${TARGET_USER}' does not exist."
  exit 1
fi
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

if [[ -z "${TARGET_HOME}" || ! -d "${TARGET_HOME}" ]]; then
  echo "Could not determine the home directory for '${TARGET_USER}'."
  exit 1
fi
if [[ ! -r /etc/fedora-release ]]; then
  echo "This script is intended for Fedora Linux only."
  exit 1
fi
FEDORA_VERSION="$(rpm -E '%fedora')"

############################################################
# DNF 5 LOCAL SETTINGS
# Allows up to 10 package downloads in parallel.
# Fedora's normal mirror selection is retained.
############################################################
mkdir -p /etc/dnf/libdnf5.conf.d && tee /etc/dnf/libdnf5.conf.d/80-local.conf >/dev/null <<'EOF'
[main]
max_parallel_downloads=10
fastestmirror=False
EOF

############################################################
# BASE SYSTEM
# Update the minimal Fedora install and add basic CLI tools.
############################################################
dnf -y install \
  dnf-plugins-core \
  curl \
  wget \
  git \
  nano \
  vim

############################################################
# RPM FUSION
# Enables non-free/free repositories for NVIDIA, Steam, codecs, etc.
############################################################
dnf -y install \
https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf -y upgrade --refresh

############################################################
# CISCO OPENH264
# Enables Fedora's Cisco OpenH264 repository.
############################################################
dnf config-manager setopt fedora-cisco-openh264.enabled=1

############################################################
# CURATED PACKAGES
############################################################
dnf -y install \
cups \
cups-filters \
ghostscript \
cups-browsed \
nss-mdns \
gutenprint \
hplip \
kate \
kcalc \
okular \
gwenview \
kolourpaint \
kcolorchooser \
libglvnd-gles \
qbittorrent \
keepassxc

############################################################
# KDE FOUNDATION: ENABLE PRINTING SERVICE
############################################################
systemctl enable --now cups

############################################################
# NVIDIA
# Install the NVIDIA drivers and CUDA packages
############################################################
if dnf -y install akmod-nvidia xorg-x11-drv-nvidia-cuda; then
  akmods --force
  if modinfo nvidia &>/dev/null; then
    echo "NVIDIA driver installation and compilation successful."
  fi
fi

############################################################
# BRAVE ORIGIN
# add brave stuff back here
############################################################

############################################################
# PROTON VPN
############################################################
# Uses the FEDORA_VERSION variable calculated in your safety check
PROTONVPN_URL="https://protonvpn.com{FEDORA_VERSION}-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.4-1.noarch.rpm"

if dnf -y install "${PROTONVPN_URL}"; then
  dnf -y install proton-vpn-gnome-desktop || true
  echo "Proton VPN installed successfully."
fi

############################################################
# MULTIMEDIA CODECS
# add these to the Multimedia comp group added earlier
# maybe put comp group addition here and fonts with libre office stuff
############################################################
dnf -y group install multimedia
dnf -y swap ffmpeg-free ffmpeg --allowerasing
dnf -y install \
  ffmpeg-libs \
  libva \
  libva-utils \
  gstreamer1-plugins-base \
  gstreamer1-plugins-good-extras \
  lame \
  openh264 \
  mozilla-openh264

############################################################
# VLC
############################################################
dnf -y install \
  vlc \
  vlc-plugins-base \
  vlc-plugins-freeworld

############################################################
# GAMING PLATFORM
# Steam, Lutris, Wine and Proton helper tools.
############################################################
dnf -y install \
  steam \
  lutris \
  protontricks \
  winetricks \
  gamemode \
  gamescope \
  goverlay \
  mangohud \
  vulkan-loader \
  kernel-modules-extra

############################################################
# CONTENT CREATION
# Recording, streaming and video editing.
############################################################
dnf -y install \
  obs-studio \
  kdenlive \
  pinta

############################################################
# LIBERATION FONTS
# Installs Liberation fonts that LibreOffice uses.
# maybe add Fonts comp group here too
############################################################
dnf -y group install fonts
dnf -y install liberation-fonts

############################################################
# OFFICE
# Basic LibreOffice tools i use, not full suite
############################################################
dnf -y install \
  libreoffice-writer \
  libreoffice-calc \
  libreoffice-langpack-en \
  hunspell-en \
  autocorr-en

############################################################
# SYSTEM UTILITIES
# Monitoring, shell, storage tools, Btrfs tools and archives.
############################################################
dnf -y install \
  btop \
  nvtop \
  fastfetch \
  fish \
  btrfs-assistant \
  snapper \
  p7zip \
  p7zip-plugins \
  unrar

############################################################
# VIRTUALISATION
# put simpler virt-manager stuff here
############################################################
dnf -y install \
    virt-manager \
    libvirt \
    libvirt-daemon-config-network \
    libvirt-daemon-kvm \
    qemu-kvm \
    virt-install \
    virt-viewer \
    edk2-ovmf \
    swtpm
systemctl enable --now libvirtd
usermod -aG libvirt "${TARGET_USER}"

############################################################
# VM GUEST Additions
# put simpler guest addons here
############################################################
if [[ "$(systemd-detect-virt || true)" != "none" ]]; then
  dnf5 -y install spice-vdagent
  systemctl start spice-vdagentd.service
fi

############################################################
# FLATPAK AND FLATHUB
# flatpak is part of the comp group kde-desktop's Defaults
# Flathub is not auto-registered so it's added here.
############################################################
dnf install -y flatpak plasma-discover-flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

############################################################
# FLATPAK APPS
# Apps preferred from Flathub.
############################################################
flatpak install -y flathub com.vysp3r.ProtonPlus
flatpak install -y flathub dev.vencord.Vesktop
flatpak install -y flathub org.localsend.localsend_app
flatpak install -y flathub com.github.tchx84.Flatseal
flatpak install -y flathub com.heroicgameslauncher.hgl
flatpak install -y flathub org.freefilesync.FreeFileSync
flatpak install -y flathub net.waterfox.waterfox

############################################################
# KDE CONNECT FIREWALL
# Allows KDE Connect discovery and communication through
# Fedora's public firewalld zone.
############################################################
firewall-cmd --permanent --add-service=kdeconnect
firewall-cmd --reload

############################################################
# LOCALSEND FIREWALL
# Allows LocalSend through firewall
# Also opens the libvirt zone, so VM guests can reach LocalSend
############################################################
firewall-cmd --zone=public --add-port=53317/tcp --permanent
firewall-cmd --zone=public --add-port=53317/udp --permanent
firewall-cmd --zone=libvirt --add-port=53317/tcp --permanent
firewall-cmd --zone=libvirt --add-port=53317/udp --permanent

############################################################
# USER SHELL
# try and implement this
############################################################

############################################################
# GAMES MOUNT PERMISSIONS
# Fixes ownership of the /games mount point.
############################################################
chown "${TARGET_USER}":"${TARGET_USER}" /games
chmod 755 /games

############################################################
# FILESYSTEM CONFIGURATION
# Checks and applies Btrfs labels, then refreshes udev so
# Dolphin and other desktop tools see them immediately.
############################################################

############################################################
# HARDWARE SUPPORT
# Audeze Maxwell USB Dongle Fix.
############################################################

############################################################
# HARDWARE SUPPORT — RAZER PERIPHERALS
# OpenRazer and Polychromatic.
############################################################


############################################################
# HARDWARE SUPPORT — COOLERCONTROL
############################################################

############################################################
# BOOT TWEAKS AND CLEANUP
# Disables unnecessary boot waiting, previews packages DNF
# considers removable without removing them, then clears
# cached DNF data.
############################################################
systemctl disable NetworkManager-wait-online.service

############################################################
# AUTOREMOVE PREVIEW
############################################################

############################################################
# DNF CACHE CLEANUP
############################################################
dnf -y clean all
