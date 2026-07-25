#!/usr/bin/env bash
set -euo pipefail

# PhilFed v4.8
# Fedora Everything -> Minimal Install -> TTY -> KDE Gaming Desktop
# Optimized for 9950X3D + RTX 4090
# Gemini version

LOGFILE="/var/log/philfed.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

############################################################
# TOGGLES
############################################################

INSTALL_NVIDIA=false
INSTALL_VIRT=true
INSTALL_MAXWELL_FIX=true
INSTALL_OPENRAZER=true
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

############################################################
# DNF 5 CONFIG (Pushed to start for max download speeds)
############################################################

section "Optimizing DNF 5"
mkdir -p /etc/dnf/libdnf5.conf.d
tee /etc/dnf/libdnf5.conf.d/80-local.conf >/dev/null <<'EOF'
[main]
max_parallel_downloads=10
fastestmirror=True
EOF

############################################################
# BASE SYSTEM
############################################################

section "Base update and core tools"
dnf -y upgrade --refresh
dnf -y install dnf-plugins-core curl wget git nano vim

############################################################
# RPM FUSION & REPOS
############################################################

section "Enable Repositories (RPM Fusion & Cisco)"
dnf -y install \
  "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
  "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"

dnf config-manager setopt fedora-cisco-openh264.enabled=1 || true
dnf -y upgrade --refresh

############################################################
# KDE CORE & LOGIN MANAGER
############################################################

section "KDE Core & Plasma Login Manager"
dnf -y install \
  plasma-desktop \
  plasma-login-manager \
  kcm-plasmalogin \
  plasma-discover \
  plasma-discover-flatpak \
  plasma-nm \
  plasma-pa

section "Enable Plasma Login Manager"
systemctl disable sddm gdm lightdm 2>/dev/null || true
systemctl enable --force plasmalogin.service
systemctl set-default graphical.target

############################################################
# KDE POLISH & APPLICATIONS
############################################################

section "KDE Integration and Applications"
dnf -y install \
  kwalletmanager5 pam-kwallet systemsettings plasma-systemmonitor kinfocenter kdialog \
  breeze-gtk kde-gtk-config kdegraphics-thumbnailers kirigami qqc2-desktop-style \
  qt6-qtdeclarative kio-admin dolphin kate kcalc kolourpaint konsole kscreen \
  kde-partitionmanager gwenview okular spectacle ark filelight

############################################################
# AUDIO, NETWORK, FIRMWARE
############################################################

section "Audio, Networking & Firmware"
dnf -y install \
  pipewire pipewire-pulseaudio wireplumber alsa-utils \
  NetworkManager NetworkManager-wifi wpa_supplicant bluedevil bluez bluez-tools \
  linux-firmware iwlwifi-dvm-firmware iwlwifi-mvm-firmware iwlwifi-mld-firmware

systemctl enable NetworkManager bluetooth

############################################################
# BROWSERS
############################################################

section "Browsers"
dnf -y install firefox chromium qbittorrent

# Brave
dnf -y config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
dnf -y install brave-origin || warn "Brave Origin install failed"

# Waterfox COPR
dnf -y copr enable deltacopy/waterfox
dnf -y install waterfox || warn "Waterfox install failed"

############################################################
# CODECS & MEDIA
############################################################

section "Multimedia and Codecs"
dnf -y swap ffmpeg-free ffmpeg --allowerasing || true
dnf -y group upgrade multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin || true
dnf -y install \
  ffmpeg-libs libva libva-utils gstreamer1-plugins-base gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly \
  gstreamer1-libav openh264 gstreamer1-plugin-openh264 mozilla-openh264 \
  vlc vlc-plugins-base vlc-plugins-freeworld

############################################################
# GAMING PLATFORM & GRAPHICS (9950X3D / 4090)
############################################################

section "Gaming platform & Drivers"
dnf -y install \
  steam lutris protontricks winetricks gamemode gamescope goverlay mangohud \
  mesa-dri-drivers mesa-vulkan-drivers vulkan-loader kernel-modules-extra

############################################################
# CONTENT CREATION & OFFICE (With Autocorrect Fix)
############################################################

section "Content Creation & Office"
dnf -y install \
  obs-studio kdenlive \
  libreoffice-writer libreoffice-calc libreoffice-langpack-en hunspell-en hunspell-en-GB autocorr-en

############################################################
# SYSTEM UTILITIES & FONTS
############################################################

section "System Utilities & Math Fonts"
dnf -y install \
  btop nvtop fastfetch fish gnome-disk-utility btrfs-assistant snapper \
  unzip p7zip p7zip-plugins unrar google-noto-sans-math-fonts

############################################################
# FLATPAK APPS
############################################################

section "Flatpak apps"
dnf -y install flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true

flatpak install -y flathub com.vysp3r.ProtonPlus || warn "ProtonPlus Flatpak failed"
flatpak install -y flathub dev.vencord.Vesktop || warn "Vesktop Flatpak failed"
flatpak install -y flathub org.localsend.localsend_app || warn "LocalSend Flatpak failed"
flatpak install -y flathub com.github.tchx84.Flatseal || warn "Flatseal Flatpak failed"
flatpak install -y flathub com.heroicgameslauncher.hgl || warn "Heroic Flatpak failed"

# LocalSend Firewall
firewall-cmd --add-port=53317/tcp --permanent || true
firewall-cmd --add-port=53317/udp --permanent || true
firewall-cmd --reload || true

############################################################
# USER SHELL
############################################################

section "Set fish shell for ${TARGET_USER}"
if [[ -x /usr/bin/fish ]]; then
  chsh -s /usr/bin/fish "${TARGET_USER}" || warn "Could not set fish shell for ${TARGET_USER}"
fi

############################################################
# FILESYSTEM CONFIGURATION
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
  fi

  if mountpoint -q /home; then
    HOME_FSTYPE=$(findmnt -no FSTYPE /home 2>/dev/null)
    HOME_UUID=$(findmnt -no UUID /home 2>/dev/null)
    if [[ "$HOME_FSTYPE" == "btrfs" && "$HOME_UUID" != "$ROOT_UUID" ]]; then
      btrfs filesystem label /home home || true
    fi
  fi

  if mountpoint -q /games; then
    if [[ "$(findmnt -no FSTYPE /games 2>/dev/null)" == "btrfs" ]]; then
      btrfs filesystem label /games games || true
    fi
  fi
fi

############################################################
# VIRTUALISATION
############################################################

if [[ "${INSTALL_VIRT}" == "true" ]]; then
  section "Virtualisation stack"
  dnf -y install virt-manager libvirt libvirt-daemon-config-network libvirt-daemon-kvm qemu-kvm virt-install virt-viewer edk2-ovmf swtpm || true
  systemctl enable --now libvirtd || true
  usermod -aG libvirt "${TARGET_USER}" || true
fi

############################################################
# HARDWARE FIXES (Audeze Maxwell & OpenRazer)
############################################################

if [[ "${INSTALL_MAXWELL_FIX}" == "true" ]]; then
  section "Audeze Maxwell USB dongle fix"
  dnf -y install usbutils
  if command -v usbreset &>/dev/null; then
    cat > /usr/local/bin/reset-maxwell.sh <<'EOF'
#!/usr/bin/env bash
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
  fi
fi

if [[ "${INSTALL_OPENRAZER}" == "true" ]]; then
  section "OpenRazer and Polychromatic"
  dnf -y install kernel-devel
  dnf config-manager addrepo --from-repofile=https://openrazer.github.io/hardware:razer.repo || true
  dnf -y install openrazer-meta polychromatic
  groupadd -f plugdev
  gpasswd -a "${TARGET_USER}" plugdev
fi

############################################################
# NVIDIA DRIVERS (RTX 4090)
############################################################

if [[ "${INSTALL_NVIDIA}" == "true" ]]; then
  section "NVIDIA drivers"
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
    sleep 5
  done

  dracut --force || warn "dracut reported an issue"
fi

############################################################
# BOOT TWEAKS & CLEANUP
############################################################

section "Boot tweaks and Cleanup"
systemctl disable NetworkManager-wait-online.service || true
dnf -y autoremove || true
dnf -y clean all || true

############################################################
# HOSTNAME
############################################################

section "Hostname setup"
CURRENT_HOSTNAME=$(hostname)
echo -e "\nCurrent hostname: $CURRENT_HOSTNAME\n"
read -rp "Enter new hostname (or press Enter to keep '$CURRENT_HOSTNAME'): " HOSTNAME

if [[ -n "$HOSTNAME" ]]; then
  if [[ "$HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
    hostnamectl set-hostname "$HOSTNAME"
    echo "Hostname updated to: $HOSTNAME"
  else
    warn "Invalid hostname format. Keeping $CURRENT_HOSTNAME"
  fi
fi

section "Complete"
echo "Bootstrap finished cleanly!"
echo "Reboot with: sudo reboot"
