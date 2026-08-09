#!/usr/bin/env bash
set -euo pipefail

# philfed.sh
#
# Purpose:
# To go from Fedora Everything Minimal Install
# Using curated comps groups and select packages
# To give Fedora everything reasonably needs
# As well as toggleable additions
# To end up with a stable KDE Gaming Desktop
#
# Philosophy:
# - Keep packages & groups deliberate and justified.
# - Prefer KDE defaults where practical.
# - Minimise unnecessary services and overlapping tools.
# - Keep every section understandable and replaceable.

############################################################
# VERSION
############################################################

PHILFED_VERSION="6.0.1"

############################################################
# TOGGLES
############################################################

INSTALL_NVIDIA=true
INSTALL_PROTONVPN=true
INSTALL_VIRT=true
FIX_GAMES_PERMISSIONS=true
LABEL_BTRFS=false
INSTALL_MAXWELL_FIX=true
INSTALL_OPENRAZER=true
INSTALL_COOLERCONTROL=false

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
# LOGGING
############################################################

LOG_DIRECTORY="${TARGET_HOME}/Desktop"
LOG_TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
LOGFILE="${LOG_DIRECTORY}/philfed-${PHILFED_VERSION}-${LOG_TIMESTAMP}.log"

mkdir -p "${LOG_DIRECTORY}"
chown "${TARGET_USER}:${TARGET_USER}" "${LOG_DIRECTORY}"
chmod 755 "${LOG_DIRECTORY}"

touch "${LOGFILE}"
chown "${TARGET_USER}:${TARGET_USER}" "${LOGFILE}"
chmod 644 "${LOGFILE}"

exec > >(tee -a "${LOGFILE}")
exec 2>&1

############################################################
# COLOURS AND HELPERS
############################################################

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

declare -a COMPLETED_SECTIONS=()
declare -a WARNINGS=()
declare -a NOTES=()
declare -a SKIPPED_SECTIONS=()

section() {
  echo -e "\n${GREEN}==> $1${RESET}"
}
complete_section() {
  COMPLETED_SECTIONS+=("$1")
}
warn() {
  local message="$1"

  echo -e "${YELLOW}Warning:${RESET} ${message}"
  WARNINGS+=("${message}")
}
note() {
  local message="$1"

  echo -e "${BLUE}Note:${RESET} ${message}"
  NOTES+=("${message}")
}
skip_section() {
  local message="$1"

  echo "Skipped: ${message}"
  SKIPPED_SECTIONS+=("${message}")
}

############################################################
# ENVIRONMENT
############################################################

section "Environment"
echo "PhilFed Version: ${PHILFED_VERSION}"
echo "Fedora Version: ${FEDORA_VERSION}"
echo "Target User: ${TARGET_USER}"
echo "Installation Log: ${LOGFILE}"
echo "Install NVIDIA: ${INSTALL_NVIDIA}"
echo "Install ProtonVPN: ${INSTALL_PROTONVPN}"
echo "Install Virt: ${INSTALL_VIRT}"
echo "Fix /games permissions: ${FIX_GAMES_PERMISSIONS}"
echo "Label Btrfs filesystems: ${LABEL_BTRFS}"
echo "Install Maxwell Fix: ${INSTALL_MAXWELL_FIX}"
echo "Install OpenRazer: ${INSTALL_OPENRAZER}"
echo "Install CoolerControl: ${INSTALL_COOLERCONTROL}"

############################################################
# DNF 5 LOCAL SETTINGS
# Allows up to 10 package downloads in parallel.
# Fedora's normal mirror selection is retained.
############################################################

section "Configure DNF"
mkdir -p /etc/dnf/libdnf5.conf.d
tee /etc/dnf/libdnf5.conf.d/80-local.conf >/dev/null <<'EOF'
[main]
max_parallel_downloads=10
fastestmirror=False
EOF
complete_section "Configure DNF"

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
complete_section "Base update and core tools"

############################################################
# RPM FUSION
# Enables non-free/free repositories for NVIDIA, Steam, codecs, etc.
############################################################

section "Enable RPM Fusion"
dnf -y install \
  "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
  "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
dnf -y upgrade --refresh
complete_section "Enable RPM Fusion"

############################################################
# CISCO OPENH264
# Enables Fedora's Cisco OpenH264 repository.
############################################################

section "Enable Cisco OpenH264"
dnf config-manager setopt fedora-cisco-openh264.enabled=1 || true
complete_section "Enable Cisco OpenH264"

############################################################
# KDE FOUNDATION: DEFAULT GROUPS
# "DEFAULT" groups are mandatory+default (dnf5's normal behaviour)
############################################################
section "KDE Foundation: DEFAULT Groups"
DEFAULT_GROUPS=(
  base-graphical
  core
  fonts
  hardware-support
  kde-desktop
  multimedia
  networkmanager-submodules
  standard
)
KDE_FOUNDATION_DEFAULT_READY=true
for group in "${DEFAULT_GROUPS[@]}"; do
  if ! dnf -y group install "${group}"; then
    warn "Group '${group}' could not be fully installed."
    KDE_FOUNDATION_DEFAULT_READY=false
  fi
done
if [[ "${KDE_FOUNDATION_DEFAULT_READY}" == "true" ]]; then
  complete_section "KDE Foundation: DEFAULT Groups"
else
  warn "One or more KDE Foundation DEFAULT Groups reported an issue. Review the log before continuing."
fi

############################################################
# KDE FOUNDATION: TRIM UNWANTED DEFAULTS
# akonadi is kde-desktop's PIM backend
# PIM is not installed so no need for akonadi
############################################################

section "KDE Foundation: trim unwanted defaults"

if rpm -q akonadi-server &>/dev/null; then
  if dnf -y remove akonadi-server akonadi-server-mysql; then
    complete_section "KDE Foundation: trim unwanted defaults"
  else
    warn "akonadi-server / akonadi-server-mysql could not be removed."
  fi
else
  note "akonadi-server was not present, nothing to trim."
fi

############################################################
# KDE FOUNDATION: CURATED PACKAGES
# Individually curated packages from comp groups i did not
# install and the groups they came from
############################################################

section "KDE Foundation: Curated Packages"

CURATED_PACKAGES=(
  # admin-tools
  gnome-disk-utility
  setroubleshoot
  # desktop-accessibility
  at-spi2-atk
  at-spi2-core
  # printing
  cups
  cups-filters
  ghostscript
  cups-browsed
  nss-mdns
  gutenprint
  hplip
  # kde-apps
  kcalc
  okular
  # kde-media
  gwenview
  kolourpaint
  # from 'firefox' comps group — GPU-accelerated WebRender/EGL support.
  # Needed by any Gecko-based browser (Firefox, Waterfox, LibreWolf, Zen, Floorp)
  # on Wayland/KDE, not just Firefox itself. See Fedora bug 1948010.
  libglvnd-gles
  # individually added — not in any comps group
  kate
  kcolorchooser
)

if dnf -y install "${CURATED_PACKAGES[@]}"; then
  complete_section "KDE Foundation: Curated Packages"
else
  warn "One or more KDE Foundation: Curated Packages could not be installed."
fi

############################################################
# KDE FOUNDATION: ENABLE PRINTING SERVICE
############################################################

section "KDE Foundation: enable printing service"
if systemctl enable --now cups; then
  complete_section "KDE Foundation: enable printing service"
else
  warn "CUPS could not be enabled."
fi

############################################################
# PLASMA LOGIN MANAGER
# Enables the Fedora 44 Plasma Login Manager and boots to GUI.
############################################################

section "Enable Plasma Login Manager"
systemctl disable sddm gdm lightdm 2>/dev/null || true
systemctl enable --force plasmalogin.service
systemctl set-default graphical.target
complete_section "Enable Plasma Login Manager"

############################################################
# NVIDIA
# Installs RPM Fusion NVIDIA drivers, warns about Secure Boot,
# builds akmods and regenerates initramfs.
############################################################

if [[ "${INSTALL_NVIDIA}" == "true" ]]; then
  section "NVIDIA drivers"
  NVIDIA_READY=true
  if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
    warn "Secure Boot is enabled. NVIDIA may not load unless akmods signing/MOK enrolment is configured."
  fi
  if ! dnf -y install akmod-nvidia xorg-x11-drv-nvidia-cuda; then
    warn "NVIDIA driver packages could not be installed. Continuing so the final summary and log remain available."
    NVIDIA_READY=false
  fi
  if [[ "${NVIDIA_READY}" == "true" ]]; then
    section "Force NVIDIA akmod build"
    if ! akmods --force; then
      warn "NVIDIA akmod build reported an issue."
      NVIDIA_READY=false
    fi
  fi
  if [[ "${NVIDIA_READY}" == "true" ]]; then
    section "Waiting for NVIDIA module"
    NVIDIA_MODULE_READY=false
    for i in {1..30}; do
      if modinfo nvidia &>/dev/null; then
        echo "NVIDIA module is available."
        NVIDIA_MODULE_READY=true
        break
      fi
      echo "Waiting for NVIDIA module build... ${i}/30"
      sleep 10
    done
    if [[ "${NVIDIA_MODULE_READY}" != "true" ]]; then
      warn "NVIDIA module did not become available during the waiting period."
      NVIDIA_READY=false
    fi
  fi
  if [[ "${NVIDIA_READY}" == "true" ]]; then
    if ! dracut --force; then
      warn "dracut reported an issue while preparing the NVIDIA driver."
      NVIDIA_READY=false
    fi
  fi
  if [[ "${NVIDIA_READY}" == "true" ]]; then
    section "Checking NVIDIA module"
    if modinfo -F version nvidia; then
      complete_section "NVIDIA drivers"
    else
      warn "NVIDIA module still not ready. Wait a few minutes before rebooting."
    fi
  fi
else
  skip_section "NVIDIA drivers"
fi

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
complete_section "Web and internet"

############################################################
# BRAVE ORIGIN
# Optional stripped-down Brave browser from Brave's RPM repo.
# Repository setup and package installation are non-fatal.
############################################################

section "Brave Origin"
BRAVE_REPO_READY=false
if [[ -f /etc/yum.repos.d/brave-browser.repo ]]; then
  echo "Brave repository already configured."
  BRAVE_REPO_READY=true
elif dnf -y config-manager addrepo \
  --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo; then
  echo "Brave repository configured."
  BRAVE_REPO_READY=true
else
  warn "Brave repository could not be configured. Skipping Brave Origin."
fi
if [[ "${BRAVE_REPO_READY}" == "true" ]]; then
  if dnf -y install brave-origin; then
    complete_section "Brave Origin"
  else
    warn "Brave Origin installation failed. Continuing without it."
  fi
fi

############################################################
# WATERFOX
# Firefox-based browser via Fedora COPR.
# Less aggressive than LibreWolf and supports DRM content.
# Repository setup and package installation are non-fatal.
############################################################

section "Waterfox"
WATERFOX_REPO_READY=false
if dnf -y copr enable deltacopy/waterfox; then
  echo "Waterfox COPR enabled."
  WATERFOX_REPO_READY=true
else
  warn "Waterfox COPR could not be enabled. Skipping Waterfox."
fi
if [[ "${WATERFOX_REPO_READY}" == "true" ]]; then
  if dnf -y install waterfox; then
    complete_section "Waterfox"
  else
    warn "Waterfox installation failed. Continuing without it."
  fi
fi

############################################################
# PROTON VPN
# Official Proton VPN Linux GUI via Proton's Fedora repo.
# Treated as non-critical so a Proton packaging or service
# issue does not abort the rest of the Fedora bootstrap.
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
    if dnf -y install proton-vpn-gnome-desktop; then
      echo "Proton VPN installed."
      complete_section "Proton VPN"
    elif rpm -q proton-vpn-gnome-desktop proton-vpn-daemon &>/dev/null; then
      echo "Proton VPN packages are installed despite the reported installation error."
      complete_section "Proton VPN"
      note "Proton VPN reported a service setup error during installation. This may relate to split tunnelling, which is unavailable on the free Proton VPN plan. Check that the main VPN application works after rebooting."
    else
      warn "Proton VPN installation did not complete. Continuing without Proton VPN."
    fi
  fi
  rm -f "${PROTONVPN_TMP}"
else
  skip_section "Proton VPN"
fi

############################################################
# MULTIMEDIA CODECS
# Codec/framework packages not covered by the KDE Foundation
# 'multimedia' group, plus the ffmpeg-free -> ffmpeg swap.
############################################################
section "Multimedia and codecs"
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
complete_section "Multimedia and codecs"

############################################################
# MEDIA PLAYBACK
# VLC (only Optional in kde-desktop, so not covered by
# KDE Foundation FULL) and its freeworld plugin set.
############################################################
section "Media playback"
dnf -y install \
  vlc \
  vlc-plugins-base \
  vlc-plugins-freeworld
complete_section "Media playback"

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
complete_section "Gaming platform"

############################################################
# GameMode, Gamescope, MangoHud, Vulkan loader and kernel extras.
# Mesa drivers themselves come from base-graphical (KDE Foundation).
############################################################

section "Gaming performance and graphics"
dnf -y install \
  gamemode \
  gamescope \
  goverlay \
  mangohud \
  vulkan-loader \
  kernel-modules-extra
complete_section "Gaming performance and graphics"

############################################################
# CONTENT CREATION
# Recording, streaming and video editing.
############################################################

section "Content creation"
dnf -y install \
  obs-studio \
  kdenlive \
  pinta
complete_section "Content creation"

############################################################
# LIBERATION FONTS
# Installs Liberation fonts that LibreOffice uses.
# Other fonts are installed in KDE Foundation section
############################################################

section "Fonts"
dnf -y install liberation-fonts
complete_section "Fonts"

############################################################
# OFFICE
# Basic LibreOffice tools i use, not full suite
############################################################

section "Office"
dnf -y install \
  libreoffice-writer \
  libreoffice-calc \
  libreoffice-langpack-en \
  hunspell-en \
  autocorr-en
complete_section "Office"

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
  btrfs-assistant \
  snapper \
  p7zip \
  p7zip-plugins \
  unrar
complete_section "System utilities"

############################################################
# VIRTUALISATION
# Virt-Manager, libvirt, QEMU/KVM, OVMF and TPM support.
# Only installed when INSTALL_VIRT=true, since this is host-side
# tooling for running VMs, not guest-side tooling.
############################################################

if [[ "${INSTALL_VIRT}" == "true" ]]; then
  section "Virtualisation stack"

  if dnf -y install \
    virt-manager \
    libvirt \
    libvirt-daemon-config-network \
    libvirt-daemon-kvm \
    qemu-kvm \
    virt-install \
    virt-viewer \
    edk2-ovmf \
    swtpm; then

    VIRTUALISATION_READY=true
  else
    VIRTUALISATION_READY=false
    warn "Virtualisation packages could not be installed completely. Continuing without a confirmed virtualisation stack."
  fi
  if [[ "${VIRTUALISATION_READY}" == "true" ]]; then
    if systemctl enable --now libvirtd; then
      echo "libvirtd enabled and started."
    else
      warn "Virtualisation packages installed, but libvirtd could not be enabled."
      VIRTUALISATION_READY=false
    fi
  fi
  if [[ "${VIRTUALISATION_READY}" == "true" ]]; then
    if usermod -aG libvirt "${TARGET_USER}"; then
      echo "${TARGET_USER} added to the libvirt group."
      complete_section "Virtualisation stack"
    else
      warn "Virtualisation packages installed, but ${TARGET_USER} could not be added to the libvirt group."
    fi
  fi
else
  skip_section "Virtualisation stack"
fi

############################################################
# VM GUEST DETECTION
# Installs spice-vdagent only if this install is itself
# running as a VM guest.
############################################################

section "VM guest detection"

VIRT_TYPE="$(systemd-detect-virt || true)"

if [[ "${VIRT_TYPE}" != "none" ]]; then
  echo "Detected VM guest environment: ${VIRT_TYPE}"

  if dnf -y install spice-vdagent; then
    if systemctl enable --now spice-vdagentd.service; then
      complete_section "SPICE guest agent"
    else
      warn "SPICE guest agent installed, but its service could not be enabled."
    fi
  else
    warn "SPICE guest agent could not be installed."
  fi
else
  note "Bare-metal installation detected. SPICE guest agent was not required."
fi

############################################################
# FLATPAK AND FLATHUB
# flatpak is part of the comp group kde-desktop's Defaults
# Flathub is not auto-registered so it's added here.
############################################################
section "Flatpak and Flathub"
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
complete_section "Flatpak and Flathub"

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
if flatpak update -y; then
  echo "Flatpak applications and runtimes updated."
else
  warn "Flatpak application or runtime update failed."
fi
complete_section "Flatpak apps"

############################################################
# KDE CONNECT FIREWALL
# Allows KDE Connect discovery and communication through
# Fedora's public firewalld zone.
############################################################

section "KDE Connect firewall"
KDECONNECT_FIREWALL_READY=true
if ! firewall-cmd --permanent \
  --zone=public \
  --add-service=kdeconnect; then
  warn "Failed to enable KDE Connect firewall service"
  KDECONNECT_FIREWALL_READY=false
fi
if ! firewall-cmd --reload; then
  warn "Failed to reload firewall"
  KDECONNECT_FIREWALL_READY=false
fi
if [[ "${KDECONNECT_FIREWALL_READY}" == "true" ]]; then
  complete_section "KDE Connect firewall"
fi

############################################################
# LOCALSEND FIREWALL
# Allows LocalSend discovery and transfers through firewalld.
# Also opens the libvirt zone, so VM guests can reach LocalSend
# on the host (needed for guest-to-host transfers, e.g. sending
# install logs out of a test VM). The libvirt zone is created
# by libvirt itself, so it may not exist yet if Virtualisation
# hasn't run, or is disabled — skipped gracefully if so.
############################################################

section "LocalSend firewall"
LOCALSEND_FIREWALL_READY=true
if ! firewall-cmd --add-port=53317/tcp --permanent; then
  warn "Failed to open LocalSend TCP port (public zone)"
  LOCALSEND_FIREWALL_READY=false
fi
if ! firewall-cmd --add-port=53317/udp --permanent; then
  warn "Failed to open LocalSend UDP port (public zone)"
  LOCALSEND_FIREWALL_READY=false
fi
if firewall-cmd --get-zones | grep -qw libvirt; then
  if ! firewall-cmd --zone=libvirt --add-port=53317/tcp --permanent; then
    warn "Failed to open LocalSend TCP port (libvirt zone)"
    LOCALSEND_FIREWALL_READY=false
  fi
  if ! firewall-cmd --zone=libvirt --add-port=53317/udp --permanent; then
    warn "Failed to open LocalSend UDP port (libvirt zone)"
    LOCALSEND_FIREWALL_READY=false
  fi
else
  note "libvirt firewalld zone not present, skipping VM guest access for LocalSend."
fi
if ! firewall-cmd --reload; then
  warn "Failed to reload firewall"
  LOCALSEND_FIREWALL_READY=false
fi
if [[ "${LOCALSEND_FIREWALL_READY}" == "true" ]]; then
  complete_section "LocalSend firewall"
fi

############################################################
# USER SHELL
# Sets Fish as the default shell for the normal user and
# creates standard DNF and Flatpak aliases.
############################################################
section "Set Fish as shell for ${TARGET_USER}"
FISH_READY=true
if [[ -x /usr/bin/fish ]]; then
  if chsh -s /usr/bin/fish "${TARGET_USER}"; then
    complete_section "Fish default shell"
  else
    warn "Could not set Fish shell for ${TARGET_USER}"
    FISH_READY=false
  fi
  if [[ "${FISH_READY}" == "true" ]]; then
    section "Configure Fish aliases"
    if sudo -u "${TARGET_USER}" fish -c "
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
    "; then
      complete_section "Fish aliases"
    else
      warn "Could not configure Fish aliases for ${TARGET_USER}"
    fi
  fi
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
    GAMES_PERMISSIONS_READY=true
    if ! chown "${TARGET_USER}:${TARGET_USER}" /games; then
      warn "Could not set ownership of /games"
      GAMES_PERMISSIONS_READY=false
    fi
    if ! chmod 755 /games; then
      warn "Could not set permissions on /games"
      GAMES_PERMISSIONS_READY=false
    fi
    if [[ "${GAMES_PERMISSIONS_READY}" == "true" ]]; then
      complete_section "Configure /games"
    fi
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
    return 1
  fi
  if [[ "$(findmnt -no FSTYPE "${mount_point}" 2>/dev/null)" != "btrfs" ]]; then
    warn "${mount_point} is not Btrfs, skipping label"
    return 1
  fi
  filesystem_uuid="$(findmnt -no UUID "${mount_point}" 2>/dev/null || true)"
  if [[ -z "${filesystem_uuid}" ]]; then
    warn "Could not determine the Btrfs UUID for ${mount_point}"
    return 1
  fi
  if [[ -n "${LABELLED_BTRFS_UUIDS[${filesystem_uuid}]:-}" ]]; then
    warn "${mount_point} shares a Btrfs filesystem with ${LABELLED_BTRFS_UUIDS[${filesystem_uuid}]}, skipping duplicate label"
    return 0
  fi
  LABELLED_BTRFS_UUIDS["${filesystem_uuid}"]="${mount_point}"
  current_label="$(btrfs filesystem label "${mount_point}" 2>/dev/null || true)"
  if [[ "${current_label}" == "${desired_label}" ]]; then
    echo "${mount_point} is already labelled '${desired_label}'."
  else
    echo "Labelling ${mount_point} as '${desired_label}'..."
    btrfs filesystem label "${mount_point}" "${desired_label}" \
      || { warn "Could not label ${mount_point} as '${desired_label}'"; return 1; }
  fi
}
if [[ "${LABEL_BTRFS}" == "true" ]]; then
  section "Check Btrfs labels"
  BTRFS_LABELS_READY=true
  set_btrfs_label / root || BTRFS_LABELS_READY=false
  set_btrfs_label /home home || BTRFS_LABELS_READY=false
  set_btrfs_label /games games || BTRFS_LABELS_READY=false
  echo "Refreshing device information..."
  udevadm trigger || warn "udevadm trigger reported an issue"
  udevadm settle || warn "udevadm settle reported an issue"
  if [[ "${BTRFS_LABELS_READY}" == "true" ]]; then
    complete_section "Check Btrfs labels"
  fi
else
  skip_section "Check Btrfs labels"
fi

############################################################
# HARDWARE SUPPORT
# Audeze Maxwell USB Dongle Fix.
############################################################
if [[ "${INSTALL_MAXWELL_FIX}" == "true" ]]; then
  section "Audeze Maxwell USB dongle reset fix"
  MAXWELL_READY=false
  if ! dnf -y install usbutils; then
    warn "usbutils could not be installed. Skipping Maxwell reset fix."
  elif ! command -v usbreset &>/dev/null; then
    warn "usbreset not found even after installing usbutils. Skipping Maxwell reset service."
  elif ! cat > /usr/local/bin/reset-maxwell.sh <<'EOF'
#!/usr/bin/env bash
# Reset Audeze Maxwell USB dongle before shutdown/reboot.
# This helps Windows detect the dongle cleanly after switching from Linux.
sleep 2
/usr/bin/usbreset 3329:4B19 || true
EOF
  then
    warn "Could not write reset-maxwell.sh. Skipping Maxwell reset service."
  elif ! chmod +x /usr/local/bin/reset-maxwell.sh; then
    warn "Could not make reset-maxwell.sh executable. Skipping Maxwell reset service."
  elif ! cat > /etc/systemd/system/maxwell-reset.service <<'EOF'
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
  then
    warn "Could not write maxwell-reset.service. Skipping Maxwell reset service."
  elif ! systemctl daemon-reload; then
    warn "systemd daemon-reload failed. Skipping Maxwell reset service."
  elif ! systemctl enable maxwell-reset.service; then
    warn "maxwell-reset.service could not be enabled."
  else
    MAXWELL_READY=true
  fi
  if [[ "${MAXWELL_READY}" == "true" ]]; then
    echo "Audeze Maxwell reset service installed and enabled."
    complete_section "Audeze Maxwell USB dongle reset fix"
  fi
else
  skip_section "Audeze Maxwell USB dongle reset fix"
fi

############################################################
# HARDWARE SUPPORT — RAZER PERIPHERALS
# OpenRazer and Polychromatic.
# Repository setup and package installation are non-fatal.
# The user service may not be accessible from the TTY installer,
# so its enablement result is reported without treating it as
# an installation failure.
############################################################

if [[ "${INSTALL_OPENRAZER}" == "true" ]]; then
  section "OpenRazer and Polychromatic"
  OPENRAZER_READY=false
  if ! dnf -y install kernel-devel; then
    warn "Kernel development packages could not be installed. Skipping OpenRazer."
  elif ! dnf -y config-manager addrepo \
    --from-repofile=https://openrazer.github.io/hardware:razer.repo; then
    warn "OpenRazer repository could not be configured. Skipping OpenRazer."
  elif ! dnf -y install \
    openrazer-meta \
    polychromatic; then
    warn "OpenRazer or Polychromatic could not be installed. Continuing without confirmed Razer support."
  else
    OPENRAZER_READY=true
  fi
  if [[ "${OPENRAZER_READY}" == "true" ]]; then
    if groupadd -f plugdev; then
      echo "plugdev group is available."
    else
      warn "OpenRazer installed, but the plugdev group could not be created."
      OPENRAZER_READY=false
    fi
  fi
  if [[ "${OPENRAZER_READY}" == "true" ]]; then
    if usermod -aG plugdev "${TARGET_USER}"; then
      echo "${TARGET_USER} added to the plugdev group."
    else
      warn "OpenRazer installed, but ${TARGET_USER} could not be added to the plugdev group."
      OPENRAZER_READY=false
    fi
  fi
  if [[ "${OPENRAZER_READY}" == "true" ]]; then
    if sudo -u "${TARGET_USER}" \
      systemctl --user enable openrazer-daemon.service; then
      echo "OpenRazer user service enabled."
    else
      note "OpenRazer could not enable its user service from the TTY installer. This has not prevented OpenRazer from working on previous PhilFed installations. Check Polychromatic after logging into Plasma."
    fi
    echo "OpenRazer and Polychromatic installed."
    echo "Reboot or log out and back in before using Polychromatic."

    complete_section "OpenRazer and Polychromatic"
  fi
else
  skip_section "OpenRazer and Polychromatic"
fi

############################################################
# HARDWARE SUPPORT — COOLERCONTROL
# Fan, pump and cooling-device monitoring and control.
# Disabled by default while ASUS ROG Strix sensor support and
# required BIOS settings are still being investigated.
# Repository setup, package installation and daemon enablement
# are all non-fatal.
############################################################

if [[ "${INSTALL_COOLERCONTROL}" == "true" ]]; then
  section "CoolerControl"
  COOLERCONTROL_READY=false
  if ! dnf -y install 'dnf5-command(copr)'; then
    warn "DNF COPR support could not be installed. Skipping CoolerControl."
  elif ! dnf -y copr enable codifryed/CoolerControl; then
    warn "CoolerControl COPR could not be enabled. Skipping CoolerControl."
  elif ! dnf -y install coolercontrol; then
    warn "CoolerControl could not be installed. Continuing without it."
  elif ! systemctl enable --now coolercontrold; then
    warn "CoolerControl installed, but its daemon could not be enabled."
  else
    COOLERCONTROL_READY=true
  fi
  if [[ "${COOLERCONTROL_READY}" == "true" ]]; then
    echo "CoolerControl installed and daemon enabled."
    complete_section "CoolerControl"

    note "Some ASUS ROG Strix motherboards may require additional sensor-driver support and BIOS configuration for all readings and controls to work."
  fi
else
  skip_section "CoolerControl"
fi

############################################################
# BOOT TWEAKS AND CLEANUP
# Disables unnecessary boot waiting, previews packages DNF
# considers removable without removing them, then clears
# cached DNF data.
############################################################
section "Boot tweaks and cleanup"
if systemctl disable NetworkManager-wait-online.service; then
  echo "NetworkManager wait-online service disabled."
else
  note "NetworkManager wait-online service was already disabled or could not be changed."
fi
complete_section "Boot tweaks and cleanup"

############################################################
# AUTOREMOVE PREVIEW
# Shows packages DNF considers removable.
# No packages are automatically removed by PhilFed.
############################################################

section "Autoremove preview"

echo "Checking for packages DNF considers removable."
echo "Nothing will be removed automatically."
echo

dnf autoremove --assumeno || true

echo
echo "Autoremove preview complete."
echo "No packages were automatically removed."

complete_section "Autoremove preview"

############################################################
# DNF CACHE CLEANUP
############################################################

section "DNF cache cleanup"
if dnf -y clean all; then
  echo "DNF cache cleared."
  complete_section "DNF cache cleanup"
else
  warn "DNF cache cleanup failed."
fi

############################################################
# HOSTNAME
# Optionally sets a custom hostname.
############################################################

section "Hostname"
CURRENT_HOSTNAME="$(hostname)"
FINAL_HOSTNAME="${CURRENT_HOSTNAME}"
HOSTNAME_READY=true
echo
echo "Current name of this computer: ${CURRENT_HOSTNAME}"
echo
echo "Please choose a name for your computer and press Enter."
echo "Or just press Enter to keep '${CURRENT_HOSTNAME}'."
echo
echo "Names may contain letters, numbers and hyphens (-)."
echo "Spaces are not allowed."
echo

while true; do
  if ! read -rp "Computer name: " NEW_HOSTNAME; then
    echo
    echo "No input received. Computer name left unchanged: ${CURRENT_HOSTNAME}"
    break
  fi
  if [[ -z "${NEW_HOSTNAME}" ]]; then
    echo "Computer name left unchanged: ${CURRENT_HOSTNAME}"
    break
  fi
  if [[ "${NEW_HOSTNAME}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
    if hostnamectl set-hostname "${NEW_HOSTNAME}"; then
      FINAL_HOSTNAME="${NEW_HOSTNAME}"
      echo "Computer name set to: ${NEW_HOSTNAME}"
    else
      warn "Failed to set the computer name. Keeping '${CURRENT_HOSTNAME}'."
      HOSTNAME_READY=false
    fi
    break
  else
    echo -e "${YELLOW}Invalid hostname:${RESET} Use only letters, numbers, hyphens and no spaces."
    echo "Please try again."
  fi
done

if [[ "${HOSTNAME_READY}" == "true" ]]; then
  complete_section "Hostname"
fi

############################################################
# INSTALLATION SUMMARY
# Printed to the TTY and written to the end of the Desktop log.
############################################################

section "Installation summary"
echo
echo "============================================================"
echo
echo "PhilFed ${PHILFED_VERSION} installation complete."
echo
echo "Computer name:"
echo "  ${FINAL_HOSTNAME}"
echo
echo "Installed:"

if (( ${#COMPLETED_SECTIONS[@]} == 0 )); then
  echo "  None recorded."
else
  for completed_section in "${COMPLETED_SECTIONS[@]}"; do
    echo "  ✓ ${completed_section}"
  done
fi

echo
echo "Skipped:"

if (( ${#SKIPPED_SECTIONS[@]} == 0 )); then
  echo "  None"
else
  for skipped_section in "${SKIPPED_SECTIONS[@]}"; do
    echo "  – ${skipped_section}"
  done
fi

echo
echo "Warnings:"

if (( ${#WARNINGS[@]} == 0 )); then
  echo "  None"
else
  for warning_message in "${WARNINGS[@]}"; do
    echo "  • ${warning_message}"
  done
fi

echo
echo "Notes:"

if (( ${#NOTES[@]} == 0 )); then
  echo "  None"
else
  for note_message in "${NOTES[@]}"; do
    echo "  • ${note_message}"
  done
fi

echo
echo "Installation log:"
echo "  ${LOGFILE}"
echo
echo "Reboot when ready:"
echo
echo "    sudo reboot"
echo
echo "------------------------------------------------------------"
echo
echo "No penguins were harmed during this installation."
echo
echo "============================================================"
