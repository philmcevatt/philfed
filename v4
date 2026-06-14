#!/usr/bin/env bash
set -euo pipefail

# Phil's Fedora 44 KDE Minimal Bootstrap v4
# Start from Fedora Everything -> Minimal Install -> TTY
# Run with:
#   sudo bash philfed.sh

LOGFILE="/var/log/philfed.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

INSTALL_NVIDIA=true
INSTALL_VIRT=true
FIX_GAMES_PERMISSIONS=true
LABEL_BTRFS=true

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

section() { echo -e "\n${GREEN}==> $1${RESET}"; }
warn() { echo -e "${YELLOW}Warning:${RESET} $1"; }

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this with sudo:"
  echo "sudo bash $0"
  exit 1
fi

TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "")}"

if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
  echo "Could not detect the normal user account."
  echo "Run this as:"
  echo "sudo bash philfed.sh"
  exit 1
fi

FEDORA_VERSION="$(rpm -E %fedora)"

section "Environment"
echo "Fedora Version: ${FEDORA_VERSION}"
echo "Target User: ${TARGET_USER}"
echo "Install NVIDIA: ${INSTALL_NVIDIA}"
echo "Install Virt: ${INSTALL_VIRT}"
echo "Fix /games permissions: ${FIX_GAMES_PERMISSIONS}"
echo "Label Btrfs filesystems: ${LABEL_BTRFS}"

section "Base update and core tools"
dnf -y upgrade --refresh
dnf -y install dnf-plugins-core curl wget git nano vim

section "Enable RPM Fusion"
dnf -y install \
  "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
  "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"

dnf -y upgrade --refresh

section "Enable Cisco OpenH264"
dnf config-manager setopt fedora-cisco-openh264.enabled=1 || true

section "Install minimal KDE Plasma stack"
dnf -y install \
  plasma-desktop \
  plasma-login-manager \
  kcm-plasmalogin \
  kwalletmanager5 \
  pam-kwallet \
  plasma-discover \
  plasma-discover-flatpak \
  plasma-nm \
  plasma-pa \
  systemsettings \
  kinfocenter \
  kdialog \
  breeze-gtk \
  kde-gtk-config \
  kdegraphics-thumbnailers \
  kirigami \
  qqc2-desktop-style \
  dolphin \
  kate \
  kcalc \
  kolourpaint \
  konsole \
  kscreen

section "Enable Plasma Login Manager"
systemctl disable sddm gdm lightdm 2>/dev/null || true
systemctl enable --force plasmalogin.service
systemctl set-default graphical.target

section "Audio, networking, firmware, bluetooth"
dnf -y install \
  pipewire \
  pipewire-pulseaudio \
  wireplumber \
  alsa-utils \
  NetworkManager \
  NetworkManager-wifi \
  wpa_supplicant \
  linux-firmware \
  iwlwifi-dvm-firmware \
  iwlwifi-mvm-firmware \
  iwlwifi-mld-firmware \
  bluedevil \
  bluez \
  bluez-tools

systemctl enable NetworkManager
systemctl enable bluetooth

section "Must Have Software"
dnf -y install \
  ark \
  filelight \
  firefox \
  gwenview \
  okular \
  pinta \
  qbittorrent \
  spectacle

section "Multimedia and codecs"
dnf -y swap ffmpeg-free ffmpeg --allowerasing || true

dnf -y group upgrade multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin || true

dnf -y install \
  vlc \
  vlc-plugins-base \
  vlc-plugins-freeworld \
  ffmpeg-libs \
  libva \
  libva-utils \
  gstreamer1-plugins-base \
  gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free \
  gstreamer1-plugins-bad-freeworld \
  gstreamer1-plugins-ugly \
  gstreamer1-libav \
  openh264 \
  gstreamer1-plugin-openh264 \
  mozilla-openh264

section "Gaming and recording stack"
dnf -y install \
  steam \
  lutris \
  gamemode \
  gamescope \
  goverlay \
  mangohud \
  protontricks \
  wine \
  winetricks \
  obs-studio \
  kdenlive \
  mesa-dri-drivers \
  mesa-vulkan-drivers \
  vulkan-loader \
  kernel-modules-extra

section "Office and utilities"
dnf -y install \
  libreoffice-writer \
  libreoffice-calc \
  btop \
  nvtop \
  fastfetch \
  fish \
  gnome-disk-utility \
  btrfs-assistant \
  snapper \
  kio-admin \
  unzip \
  p7zip \
  p7zip-plugins \
  unrar

section "Flatpak and Flathub"
dnf -y install flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true

section "Flatpak apps"
flatpak install -y flathub com.vysp3r.ProtonPlus || warn "ProtonPlus Flatpak failed"
flatpak install -y flathub dev.vencord.Vesktop || warn "Vesktop Flatpak failed"
flatpak install -y flathub org.localsend.localsend_app || warn "LocalSend Flatpak failed"
flatpak install -y flathub com.github.tchx84.Flatseal || warn "Flatseal Flatpak failed"
flatpak install -y flathub com.heroicgameslauncher.hgl || warn "Heroic Flatpak failed"

section "Set fish as shell for ${TARGET_USER}"
if [[ -x /usr/bin/fish ]]; then
  chsh -s /usr/bin/fish "${TARGET_USER}" || warn "Could not set fish shell for ${TARGET_USER}"
fi

if [[ "${FIX_GAMES_PERMISSIONS}" == "true" ]]; then
  if mountpoint -q /games; then
    section "Configure /games"
    chown "${TARGET_USER}:${TARGET_USER}" /games
    chmod 755 /games
  else
    warn "/games not mounted, skipping permissions fix"
  fi
fi

if [[ "${LABEL_BTRFS}" == "true" ]]; then
  section "Set Btrfs labels"

  if [[ "$(findmnt -no FSTYPE / 2>/dev/null)" == "btrfs" ]]; then
    btrfs filesystem label / fedora || true
  else
    warn "/ is not Btrfs, skipping root label"
  fi

  if mountpoint -q /games; then
    if [[ "$(findmnt -no FSTYPE /games 2>/dev/null)" == "btrfs" ]]; then
      btrfs filesystem label /games games || true
    else
      warn "/games is not Btrfs, skipping /games label"
    fi
  else
    warn "/games not mounted, skipping /games label"
  fi
fi

if [[ "${INSTALL_VIRT}" == "true" ]]; then
  section "Virtualisation stack"
  dnf -y install \
    virt-manager \
    libvirt \
    libvirt-daemon-config-network \
    libvirt-daemon-kvm \
    qemu-kvm \
    virt-install \
    virt-viewer \
    edk2-ovmf \
    swtpm || true

  systemctl enable --now libvirtd || true
  usermod -aG libvirt "${TARGET_USER}" || true
fi

if [[ "${INSTALL_NVIDIA}" == "true" ]]; then
  section "NVIDIA drivers"

  if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
    warn "Secure Boot is enabled. NVIDIA may not load unless akmods signing/MOK enrolment is configured."
  fi

  dnf -y install akmod-nvidia xorg-x11-drv-nvidia-cuda

  section "Force NVIDIA akmod build"
  akmods --force || warn "akmods build reported an issue"

  section "Waiting for NVIDIA module"
  for i in {1..30}; do
    if modinfo nvidia &>/dev/null; then
      echo "NVIDIA module is available."
      break
    fi

    echo "Waiting for NVIDIA module build... ${i}/30"
    sleep 10
  done

  dracut --force || warn "dracut reported an issue"

  section "Checking NVIDIA module"
  modinfo -F version nvidia || warn "NVIDIA module still not ready. Wait a few minutes before rebooting."
else
  warn "Skipping NVIDIA because INSTALL_NVIDIA=false"
fi

section "Boot tweaks"
systemctl disable NetworkManager-wait-online.service || true

section "Cleanup"
dnf -y autoremove || true
dnf -y clean all || true

section "Complete"
echo "Bootstrap finished."
echo "Reboot with:"
echo "sudo reboot"
