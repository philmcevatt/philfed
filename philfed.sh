#!/usr/bin/env bash
set -euo pipefail

# PhilFed v4.6
# Fedora Everything -> Minimal Install -> TTY -> KDE Gaming Desktop
#
# Run with:
#   sudo bash philfed.sh

LOGFILE="/var/log/philfed.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

############################################################
# TOGGLES
############################################################

INSTALL_NVIDIA=false
INSTALL_VIRT=true
INSTALL_MAXWELL_FIX=true
INSTALL_OPENRAZER=false
FIX_GAMES_PERMISSIONS=false
LABEL_BTRFS=true

############################################################
# COLOURS AND HELPERS
############################################################

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

section() { echo -e "\n${GREEN}==> $1${RESET}"; }
warn() { echo -e "${YELLOW}Warning:${RESET} $1"; }

############################################################
# SAFETY CHECKS
############################################################

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
echo "Install Maxwell Fix: ${INSTALL_MAXWELL_FIX}"
echo "Install OpenRazer: ${INSTALL_OPENRAZER}"
echo "Fix /games permissions: ${FIX_GAMES_PERMISSIONS}"
echo "Label Btrfs filesystems: ${LABEL_BTRFS}"

############################################################
# BASE SYSTEM
# Update the minimal Fedora install and add basic CLI tools.
############################################################

section "Base update and core tools"
dnf -y upgrade --refresh
dnf -y install dnf-plugins-core curl wget git nano vim

############################################################
# RPM FUSION
# Enables non-free/free repositories for NVIDIA, Steam, codecs, etc.
############################################################

section "Enable RPM Fusion"
dnf -y install \
  "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
  "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"

dnf -y upgrade --refresh

############################################################
# CISCO OPENH264
# Enables Fedora's Cisco OpenH264 repository.
############################################################

section "Enable Cisco OpenH264"
dnf config-manager setopt fedora-cisco-openh264.enabled=1 || true

############################################################
# DNF 5 local settings
# Allows more package max_parallel_downloads
# fastestmirror looks for nearby/low-latency mirrors
############################################################

mkdir -p /etc/dnf/libdnf5.conf.d

tee /etc/dnf/libdnf5.conf.d/80-local.conf >/dev/null <<'EOF'
[main]
max_parallel_downloads=10
fastestmirror=True
EOF

############################################################
# KDE CORE
# Core Plasma desktop, login manager, software centre,
# networking/audio applets and Flatpak integration.
############################################################

section "KDE Core"
dnf -y install \
  plasma-desktop \
  plasma-login-manager \
  kcm-plasmalogin \
  plasma-discover \
  plasma-discover-flatpak \
  plasma-nm \
  plasma-pa

############################################################
# KDE INTEGRATION AND POLISH
# KDE settings, admin tools, wallet integration,
# GTK theming, dialogs and thumbnail support.
############################################################

section "KDE Integration and polish"
dnf -y install \
  kwalletmanager5 \
  pam-kwallet \
  systemsettings \
  plasma-systemmonitor \
  kinfocenter \
  kdialog \
  breeze-gtk \
  kde-gtk-config \
  kdegraphics-thumbnailers \
  kirigami \
  qqc2-desktop-style \
  qt6-qtdeclarative \
  kio-admin

############################################################
# KDE APPLICATIONS
# Core KDE desktop apps.
############################################################

section "KDE Applications"
dnf -y install \
  dolphin \
  kate \
  kcalc \
  kolourpaint \
  konsole \
  kscreen \
  kde-partitionmanager \
  gwenview \
  okular \
  spectacle \
  ark \
  filelight

############################################################
# PLASMA LOGIN MANAGER
# Enables the Fedora 44 Plasma Login Manager and boots to GUI.
############################################################

section "Enable Plasma Login Manager"
systemctl disable sddm gdm lightdm 2>/dev/null || true
systemctl enable --force plasmalogin.service
systemctl set-default graphical.target

############################################################
# AUDIO STACK
# PipeWire, PulseAudio compatibility, WirePlumber and ALSA tools.
############################################################

section "Audio stack"
dnf -y install \
  pipewire \
  pipewire-pulseaudio \
  wireplumber \
  alsa-utils

############################################################
# NETWORKING AND BLUETOOTH
# WiFi, NetworkManager and Bluetooth support.
############################################################

section "Networking and Bluetooth"
dnf -y install \
  NetworkManager \
  NetworkManager-wifi \
  wpa_supplicant \
  bluedevil \
  bluez \
  bluez-tools

systemctl enable NetworkManager
systemctl enable bluetooth

############################################################
# FIRMWARE
# General firmware plus Intel WiFi firmware.
############################################################

section "Firmware"
dnf -y install \
  linux-firmware \
  iwlwifi-dvm-firmware \
  iwlwifi-mvm-firmware \
  iwlwifi-mld-firmware

############################################################
# WEB AND INTERNET
# Browsers and download tools.
############################################################

section "Web and internet"

dnf -y install \
  firefox \
  chromium \
  qbittorrent

############################################################
# BRAVE ORIGIN
# Optional stripped-down Brave browser from Brave's RPM repo.
############################################################

section "Brave Origin"

dnf -y install dnf-plugins-core

dnf -y config-manager addrepo \
  --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

dnf -y install brave-origin

############################################################
# Waterfox Browser
# Firefox-based browser via Fedora COPR.
# Less aggressive than LibreWolf, allows DRM content on win
############################################################

dnf -y copr enable deltacopy/waterfox
dnf -y install waterfox

############################################################
# MULTIMEDIA CODECS
# Replaces Fedora ffmpeg-free with RPM Fusion ffmpeg,
# then installs common codec support.
############################################################

section "Multimedia and codecs"
dnf -y swap ffmpeg-free ffmpeg --allowerasing || true

dnf -y group upgrade multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin || true

dnf -y install \
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

############################################################
# MEDIA PLAYBACK
# VLC and extra VLC plugin support.
############################################################

section "Media playback"
dnf -y install \
  vlc \
  vlc-plugins-base \
  vlc-plugins-freeworld

############################################################
# GAMING PLATFORM
# Steam, Lutris, Wine and Proton helper tools.
############################################################

section "Gaming platform"
dnf -y install \
  steam \
  lutris \
  protontricks \
  winetricks

############################################################
# GAMING PERFORMANCE AND GRAPHICS
# GameMode, Gamescope, MangoHud, Vulkan and Mesa drivers.
############################################################

section "Gaming performance and graphics"
dnf -y install \
  gamemode \
  gamescope \
  goverlay \
  mangohud \
  mesa-dri-drivers \
  mesa-vulkan-drivers \
  vulkan-loader \
  kernel-modules-extra

############################################################
# CONTENT CREATION
# Recording, streaming and video editing.
############################################################

section "Content creation"
dnf -y install \
  obs-studio \
  kdenlive

############################################################
# OFFICE
# Basic LibreOffice tools.
############################################################

section "Office"
dnf -y install \
  libreoffice-writer \
  libreoffice-calc

############################################################
# SYSTEM UTILITIES
# Monitoring, shell, storage tools, Btrfs tools and archives.
############################################################

section "System utilities"
dnf -y install \
  btop \
  nvtop \
  fastfetch \
  fish \
  gnome-disk-utility \
  btrfs-assistant \
  snapper \
  unzip \
  p7zip \
  p7zip-plugins \
  unrar

############################################################
# FLATPAK AND FLATHUB
# Enables Flatpak support and the Flathub remote.
############################################################

section "Flatpak and Flathub"
dnf -y install flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true

############################################################
# FLATPAK APPS
# Apps preferred from Flathub.
############################################################

section "Flatpak apps"
flatpak install -y flathub com.vysp3r.ProtonPlus || warn "ProtonPlus Flatpak failed"
flatpak install -y flathub dev.vencord.Vesktop || warn "Vesktop Flatpak failed"
flatpak install -y flathub org.localsend.localsend_app || warn "LocalSend Flatpak failed"
flatpak install -y flathub com.github.tchx84.Flatseal || warn "Flatseal Flatpak failed"
flatpak install -y flathub com.heroicgameslauncher.hgl || warn "Heroic Flatpak failed"
flatpak update -y || warn "Flatpak runtime update failed"

############################################################
# LOCALSEND FIREWALL
# Allows LocalSend discovery and transfers through firewalld.
############################################################

section "LocalSend firewall"

firewall-cmd --add-port=53317/tcp --permanent || warn "Failed to open LocalSend TCP port"
firewall-cmd --add-port=53317/udp --permanent || warn "Failed to open LocalSend UDP port"
firewall-cmd --reload || warn "Failed to reload firewall"

############################################################
# USER SHELL
# Sets fish as the default shell for the normal user.
############################################################

section "Set fish as shell for ${TARGET_USER}"
if [[ -x /usr/bin/fish ]]; then
  chsh -s /usr/bin/fish "${TARGET_USER}" || warn "Could not set fish shell for ${TARGET_USER}"
fi

############################################################
# FILESYSTEM CONFIGURATION
# Fixes /games ownership and labels Btrfs filesystems if present.
############################################################

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

  ROOT_FSTYPE=$(findmnt -no FSTYPE / 2>/dev/null)
  ROOT_UUID=$(findmnt -no UUID / 2>/dev/null)

  if [[ "$ROOT_FSTYPE" == "btrfs" ]]; then
    btrfs filesystem label / fedora || true
  else
    warn "/ is not Btrfs, skipping / label"
  fi

  if mountpoint -q /home; then
    HOME_FSTYPE=$(findmnt -no FSTYPE /home 2>/dev/null)
    HOME_UUID=$(findmnt -no UUID /home 2>/dev/null)

    if [[ "$HOME_FSTYPE" == "btrfs" ]]; then
      if [[ "$HOME_UUID" != "$ROOT_UUID" ]]; then
        btrfs filesystem label /home home || true
      else
        warn "/home is on the same Btrfs filesystem as /, skipping /home label"
      fi
    else
      warn "/home is not Btrfs, skipping /home label"
    fi
  else
    warn "/home not separately mounted, skipping /home label"
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

############################################################
# VIRTUALISATION
# Virt-Manager, libvirt, QEMU/KVM, OVMF and TPM support.
############################################################

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
else
  warn "Skipping virtualisation because INSTALL_VIRT=false"
fi

############################################################
# HARDWARE SUPPORT
# Audeze Maxwell USB Dongle Fix.
############################################################

if [[ "${INSTALL_MAXWELL_FIX}" == "true" ]]; then
  section "Audeze Maxwell USB dongle reset fix"

  dnf -y install usbutils

  if command -v usbreset &>/dev/null; then
    cat > /usr/local/bin/reset-maxwell.sh <<'EOF'
#!/usr/bin/env bash
# Reset Audeze Maxwell USB dongle before shutdown/reboot.
# This helps Windows detect the dongle cleanly after switching from Linux.

sleep 2
/usr/bin/usbreset 3329:4B19 || true
EOF

    chmod +x /usr/local/bin/reset-maxwell.sh

    cat > /etc/systemd/system/maxwell-reset.service <<'EOF'
[Unit]
Description=Reset Audeze Maxwell Dongle before shutdown/reboot
DefaultDependencies=no
Before=poweroff.target reboot.target halt.target
Conflicts=shutdown.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/reset-maxwell.sh
TimeoutStartSec=5

[Install]
WantedBy=poweroff.target reboot.target halt.target
EOF

    systemctl daemon-reload
    systemctl enable maxwell-reset.service

    echo "Audeze Maxwell reset service installed and enabled."
  else
    warn "usbreset not found even after installing usbutils. Skipping Maxwell reset service."
  fi
else
  warn "Skipping Audeze Maxwell fix because INSTALL_MAXWELL_FIX=false"
fi

############################################################
# HARDWARE SUPPORT
# Openrazer.
############################################################

if [[ "${INSTALL_OPENRAZER}" == "true" ]]; then
  section "OpenRazer and Polychromatic"

  dnf -y install kernel-devel

  dnf config-manager addrepo \
    --from-repofile=https://openrazer.github.io/hardware:razer.repo || true

  dnf -y install \
    openrazer-meta \
    polychromatic

  systemctl daemon-reload || true

  groupadd -f plugdev
  gpasswd -a "${TARGET_USER}" plugdev

  sudo -u "${TARGET_USER}" systemctl --user enable openrazer-daemon.service || true

  echo "OpenRazer installed."
  echo "User added to plugdev group."
  echo "Reboot or log out/in before using Polychromatic."
else
  warn "Skipping OpenRazer because INSTALL_OPENRAZER=false"
fi

############################################################
# NVIDIA
# Installs RPM Fusion NVIDIA drivers, warns about Secure Boot,
# builds akmods and regenerates initramfs.
############################################################

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

############################################################
# MATH UNICODE SYMBOL SUPPORT
# Enables Fancy characters
############################################################

 dnf -y install \
    google-noto-sans-math-fonts

############################################################
# BOOT TWEAKS
# Stops NetworkManager wait-online from delaying boot.
############################################################

section "Boot tweaks"
systemctl disable NetworkManager-wait-online.service || true

############################################################
# CLEANUP
# Removes unused packages and clears package cache.
############################################################

section "Cleanup"
dnf -y autoremove || true
dnf -y clean all || true

############################################################
# HOSTNAME
# Optionally set a custom hostname.
############################################################

section "Hostname"

CURRENT_HOSTNAME=$(hostname)

echo
echo "Current name of this computer: $CURRENT_HOSTNAME"
echo
echo "Please choose a name for your computer and press Enter."
echo "Or just press Enter to keep '$CURRENT_HOSTNAME'."
echo
echo "Names may contain letters, numbers and hyphens (-)."
echo "Spaces are not allowed."
echo

while true; do
    read -rp "Computer name: " HOSTNAME

    # Blank input keeps current hostname
    [[ -z "$HOSTNAME" ]] && break

    if [[ "$HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        hostnamectl set-hostname "$HOSTNAME" || warn "Failed to set hostname"
        echo "Computer name set to: $HOSTNAME"
        break
    else
        warn "Invalid hostname. Use only letters, numbers, hyphens and no spaces."
        echo "Please try again."
    fi
done

############################################################
# COMPLETE
############################################################

section "Complete"
echo "Bootstrap finished."
echo "Reboot with:"
echo "sudo reboot"
