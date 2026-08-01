#!/usr/bin/env bash
set -euo pipefail

# PhilFed v5.0
# Fedora Everything -> Minimal Install -> TTY -> KDE Gaming Desktop
#
# Purpose:
# Build my preferred Fedora KDE workstation from a minimal
# Fedora Everything installation.
#
# Philosophy:
# - Keep packages deliberate and justified.
# - Prefer KDE defaults where practical.
# - Minimise unnecessary services and overlapping tools.
# - Keep every section understandable and replaceable.
#
# Run with:
#   sudo ./philfed.sh

LOGFILE="/var/log/philfed.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

############################################################
# TOGGLES
############################################################

INSTALL_NVIDIA=true
INSTALL_VIRT=true
INSTALL_MAXWELL_FIX=true
INSTALL_OPENRAZER=true
INSTALL_COOLERCONTROL=true
INSTALL_PROTONVPN=true
INSTALL_PRINTING=true
INSTALL_REMOTE_DESKTOP=false
FIX_GAMES_PERMISSIONS=true
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

section "Environment"
echo "Fedora Version: ${FEDORA_VERSION}"
echo "Target User: ${TARGET_USER}"
echo "Install NVIDIA: ${INSTALL_NVIDIA}"
echo "Install Virt: ${INSTALL_VIRT}"
echo "Install Maxwell Fix: ${INSTALL_MAXWELL_FIX}"
echo "Install OpenRazer: ${INSTALL_OPENRAZER}"
echo "Install CoolerControl: ${INSTALL_COOLERCONTROL}"
echo "Install ProtonVPN: ${INSTALL_PROTONVPN}"
echo "Install printing: ${INSTALL_PRINTING}"
echo "Install remote desktop: ${INSTALL_REMOTE_DESKTOP}"
echo "Fix /games permissions: ${FIX_GAMES_PERMISSIONS}"
echo "Label Btrfs filesystems: ${LABEL_BTRFS}"

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
# BASE SYSTEM
# Update the minimal Fedora install and add basic CLI tools.
############################################################

section "Base update and core tools"
dnf -y upgrade --refresh
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
# KDE settings, portals, power management, wallet integration,
# GTK theming, browser integration and preview support.
############################################################

section "KDE Integration and polish"
dnf -y install \
  kwalletmanager5 \
  pam-kwallet \
  systemsettings \
  plasma-systemmonitor \
  kinfocenter \
  powerdevil \
  kdialog \
  breeze-gtk \
  kde-gtk-config \
  xdg-desktop-portal-kde \
  plasma-browser-integration \
  kdegraphics-thumbnailers \
  ffmpegthumbs \
  markdownpart \
  kirigami \
  qqc2-desktop-style \
  qt6-qtdeclarative \
  xorg-x11-server-Xwayland \
  wl-clipboard

############################################################
# DOLPHIN INTEGRATION
# Additional protocols, admin access, plugins and
# network-sharing controls for Dolphin.
############################################################

section "Dolphin integration"
dnf -y install \
  dolphin-plugins \
  kio-extras \
  kio-admin \
  kdenetwork-filesharing

############################################################
# KDE APPLICATIONS
# Core KDE desktop apps.
############################################################

section "KDE Applications"
dnf -y install \
  dolphin \
  kate \
  kcalc \
  kcolorchooser \
  kolourpaint \
  konsole \
  kscreen \
  kde-partitionmanager \
  gwenview \
  okular \
  spectacle \
  ark \
  filelight \
  kde-connect

############################################################
# PRINTING
# CUPS printing, KDE's native printer settings and
# driverless IPP-over-USB support.
############################################################

if [[ "${INSTALL_PRINTING}" == "true" ]]; then
  section "Printing support"

  dnf -y install \
    cups \
    plasma-print-manager \
    ipp-usb

  systemctl enable --now cups

  echo "Printing support installed."
else
  warn "Skipping printing because INSTALL_PRINTING=false"
fi

############################################################
# REMOTE DESKTOP
# Optional native KDE client and desktop-sharing server
# for RDP/VNC access.
############################################################

if [[ "${INSTALL_REMOTE_DESKTOP}" == "true" ]]; then
  section "KDE Remote Desktop"

  dnf -y install \
    krdc \
    krfb

  echo "KDE remote desktop tools installed."
else
  warn "Skipping KDE remote desktop because INSTALL_REMOTE_DESKTOP=false"
fi

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
  qbittorrent \
  keepassxc

############################################################
# BRAVE ORIGIN
# Optional stripped-down Brave browser from Brave's RPM repo.
############################################################

section "Brave Origin"

dnf -y install dnf-plugins-core

if [[ ! -f /etc/yum.repos.d/brave-browser.repo ]]; then
  dnf -y config-manager addrepo \
    --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
else
  echo "Brave repository already configured."
fi

dnf -y install brave-origin

############################################################
# Waterfox Browser
# Firefox-based browser via Fedora COPR.
# Less aggressive than LibreWolf, allows DRM content on win
############################################################

dnf -y copr enable deltacopy/waterfox || warn "Waterfox COPR could not be enabled or is already configured."
dnf -y install waterfox

############################################################
# PROTON VPN
# Official Proton VPN Linux GUI via Proton's Fedora repo.
# Treated as non-critical so a Proton packaging/service issue
# does not abort the rest of the Fedora bootstrap.
############################################################

if [[ "${INSTALL_PROTONVPN}" == "true" ]]; then
  section "Proton VPN"

  PROTONVPN_RPM="protonvpn-stable-release-1.0.4-1.noarch.rpm"
  PROTONVPN_URL="https://repo.protonvpn.com/fedora-${FEDORA_VERSION}-stable/protonvpn-stable-release/${PROTONVPN_RPM}"
  PROTONVPN_TMP="/tmp/${PROTONVPN_RPM}"

  if ! wget -O "${PROTONVPN_TMP}" "${PROTONVPN_URL}"; then
    warn "Could not download the Proton VPN repository package. Continuing without Proton VPN."

  elif ! dnf -y install "${PROTONVPN_TMP}"; then
    warn "Could not install the Proton VPN repository package. Continuing without Proton VPN."

  else
    dnf -y check-update --refresh || true

    if ! dnf -y install proton-vpn-gnome-desktop; then
      warn "Proton VPN package installation reported an error."

      if rpm -q proton-vpn-gnome-desktop proton-vpn-daemon &>/dev/null; then
        warn "Proton VPN packages are installed despite the reported error. Continuing."
      else
        warn "Proton VPN installation did not complete. Continuing without Proton VPN."
      fi
    else
      echo "Proton VPN installed."
    fi
  fi

  rm -f "${PROTONVPN_TMP}"
else
  warn "Skipping Proton VPN because INSTALL_PROTONVPN=false"
fi

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
  gstreamer1-plugins-good-extras \
  gstreamer1-plugins-bad-free \
  gstreamer1-plugins-bad-freeworld \
  gstreamer1-plugin-openh264 \
  gstreamer1-plugins-ugly \
  gstreamer1-libav \
  lame \
  openh264 \
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
  kdenlive \
  pinta

############################################################
# FULL FONT INSTALL PACKAGE
# Ensures Browsers & Apps don't have tofu symbols
############################################################

dnf -y install \
  'google-noto-*-fonts' \
  'liberation-*-fonts' \
  'dejavu-*-fonts'

############################################################
# OFFICE
# Basic LibreOffice tools.
############################################################

section "Office"
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
flatpak install -y flathub io.github.vikdevelop.SaveDesktop || warn "SaveDesktop Flatpak failed"
flatpak install -y flathub org.freefilesync.FreeFileSync || warn "FreeFileSync Flatpak failed"

############################################################
# LOCALSEND FIREWALL
# Allows LocalSend discovery and transfers through firewalld.
############################################################

section "LocalSend firewall"

firewall-cmd --add-port=53317/tcp --permanent || warn "Failed to open LocalSend TCP port"
firewall-cmd --add-port=53317/udp --permanent || warn "Failed to open LocalSend UDP port"
firewall-cmd --reload || warn "Failed to reload firewall"

############################################################
# KDE CONNECT FIREWALL
# Allows KDE Connect discovery and communication through
# Fedora's public firewalld zone.
############################################################

section "KDE Connect firewall"

firewall-cmd --permanent \
  --zone=public \
  --add-service=kdeconnect \
  || warn "Failed to enable KDE Connect firewall service"

firewall-cmd --reload \
  || warn "Failed to reload firewall"

############################################################
# USER SHELL
# Sets Fish as the default shell for the normal user and
# creates standard DNF and Flatpak aliases.
############################################################

section "Set Fish as shell for ${TARGET_USER}"

if [[ -x /usr/bin/fish ]]; then
  chsh -s /usr/bin/fish "${TARGET_USER}" \
    || warn "Could not set Fish shell for ${TARGET_USER}"

  section "Configure Fish aliases"

  sudo -u "${TARGET_USER}" fish -c "
    alias --save dnfi='sudo dnf install'
    alias --save dnfr='sudo dnf remove'
    alias --save dnfs='dnf search'
    alias --save dnfu='sudo dnf upgrade --refresh'
    alias --save dnfc='sudo dnf clean all'
    alias --save dnfl='dnf list --installed'
    alias --save dnfq='dnf info'

    alias --save fp='flatpak'
    alias --save fpi='flatpak install'
    alias --save fpr='flatpak uninstall'
    alias --save fps='flatpak search'
    alias --save fpu='flatpak update'
  " || warn "Could not configure Fish aliases for ${TARGET_USER}"
else
  warn "Fish is not installed. Skipping shell configuration."
fi

############################################################
# GAMES MOUNT PERMISSIONS
# Fixes ownership of the /games mount point.
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

############################################################
# FILESYSTEM CONFIGURATION
# Checks and applies Btrfs labels, then refreshes udev so
# Dolphin and other desktop tools see them immediately.
############################################################

declare -A LABELLED_BTRFS_UUIDS=()

set_btrfs_label() {
  local mount_point="$1"
  local desired_label="$2"
  local filesystem_uuid
  local current_label

  if ! mountpoint -q "${mount_point}"; then
    warn "${mount_point} is not mounted, skipping label"
    return
  fi

  if [[ "$(findmnt -no FSTYPE "${mount_point}" 2>/dev/null)" != "btrfs" ]]; then
    warn "${mount_point} is not Btrfs, skipping label"
    return
  fi

  filesystem_uuid="$(findmnt -no UUID "${mount_point}" 2>/dev/null || true)"

  if [[ -z "${filesystem_uuid}" ]]; then
    warn "Could not determine the Btrfs UUID for ${mount_point}"
    return
  fi

  if [[ -n "${LABELLED_BTRFS_UUIDS[${filesystem_uuid}]:-}" ]]; then
    warn "${mount_point} shares a Btrfs filesystem with ${LABELLED_BTRFS_UUIDS[${filesystem_uuid}]}, skipping duplicate label"
    return
  fi

  LABELLED_BTRFS_UUIDS["${filesystem_uuid}"]="${mount_point}"
  current_label="$(btrfs filesystem label "${mount_point}" 2>/dev/null || true)"

  if [[ "${current_label}" == "${desired_label}" ]]; then
    echo "${mount_point} is already labelled '${desired_label}'."
  else
    echo "Labelling ${mount_point} as '${desired_label}'..."
    btrfs filesystem label "${mount_point}" "${desired_label}" \
      || warn "Could not label ${mount_point} as '${desired_label}'"
  fi
}

if [[ "${LABEL_BTRFS}" == "true" ]]; then
  section "Check Btrfs labels"

  set_btrfs_label / root
  set_btrfs_label /home home
  set_btrfs_label /games games

  echo "Refreshing device information..."
  udevadm trigger || warn "udevadm trigger reported an issue"
  udevadm settle || warn "udevadm settle reported an issue"
else
  warn "Skipping Btrfs labels because LABEL_BTRFS=false"
fi

############################################################
# VIRTUALISATION
# Virt-Manager, libvirt, QEMU/KVM, OVMF and TPM support.
# Only installed when INSTALL_VIRT=true, since this is host-side
# tooling for running VMs, not guest-side tooling.
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
# VM GUEST DETECTION
# Installs spice-vdagent only if this install is itself
# running as a VM guest (bare metal desktop/laptop skips this).
############################################################

section "VM guest detection"

VIRT_TYPE="$(systemd-detect-virt || true)"

if [[ "${VIRT_TYPE}" != "none" ]]; then
  echo "Detected VM guest environment: ${VIRT_TYPE}"
  section "Installing SPICE guest agent"

  dnf -y install spice-vdagent

  systemctl enable --now spice-vdagentd.service || warn "Could not enable spice-vdagentd.service"
else
  echo "Bare metal install detected. Skipping spice-vdagent."
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

  groupadd -f plugdev
  usermod -aG plugdev "${TARGET_USER}"

  sudo -u "${TARGET_USER}" systemctl --user enable openrazer-daemon.service || true

  echo "OpenRazer installed."
  echo "${TARGET_USER} added to the plugdev group."
  echo "Reboot or log out/in before using Polychromatic."
else
  warn "Skipping OpenRazer because INSTALL_OPENRAZER=false"
fi

############################################################
# HARDWARE SUPPORT
# CoolerControl -
# Fan, pump and cooling device monitoring/control.
############################################################

if [[ "${INSTALL_COOLERCONTROL}" == "true" ]]; then
  section "CoolerControl"

  # DNF5 COPR support
  dnf -y install 'dnf5-command(copr)'

  # CoolerControl COPR repository
  dnf -y copr enable codifryed/CoolerControl

  # CoolerControl application and daemon
  dnf -y install coolercontrol

  # Start now and automatically on boot
  systemctl enable --now coolercontrold

  echo "CoolerControl installed and daemon enabled."
else
  warn "Skipping CoolerControl because INSTALL_COOLERCONTROL=false"
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
# BOOT TWEAKS & CLEANUP
############################################################

section "Boot tweaks and Cleanup"
flatpak update -y || warn "Flatpak runtime update failed"
systemctl disable NetworkManager-wait-online.service || true
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
