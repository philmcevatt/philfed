#!/usr/bin/env bash
set -euo pipefail

# PhilFed v6.0.0
# Fedora Everything -> Minimal Install -> TTY -> KDE Desktop

############################################################
# VERSION
############################################################

PHILFED_VERSION="6.0.0"

############################################################
# TOGGLES
############################################################

INSTALL_VIRT=true

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
echo "Install Virt: ${INSTALL_VIRT}"

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
# KDE FOUNDATION
# Builds a curated KDE Plasma desktop from Fedora 44's
# kde-desktop-environment comps groups. MOST groups are taken
# at mandatory+default (dnf5's normal behaviour). SOME groups
# contribute individually curated packages only. See the
# philfed group audit notes for the full reasoning per group.
############################################################

section "KDE Foundation: MOST groups (mandatory + default)"

MOST_GROUPS=(
  base-graphical
  core
  fonts
  hardware-support
  kde-desktop
  multimedia
  networkmanager-submodules
  standard
  firefox
)

KDE_FOUNDATION_MOST_READY=true

for group in "${MOST_GROUPS[@]}"; do
  if ! dnf -y group install "${group}"; then
    warn "Group '${group}' could not be fully installed."
    KDE_FOUNDATION_MOST_READY=false
  fi
done

if [[ "${KDE_FOUNDATION_MOST_READY}" == "true" ]]; then
  complete_section "KDE Foundation: MOST groups (mandatory + default)"
else
  warn "One or more KDE Foundation MOST groups reported an issue. Review the log before continuing."
fi

############################################################
# KDE FOUNDATION: TRIM UNWANTED DEFAULTS
# akonadi is kde-desktop's PIM backend, pulled in via its
# Default tier. Not wanted without kde-pim installed alongside it.
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
# KDE FOUNDATION: SOME groups (curated packages)
# Individually selected packages from groups where only part
# of the Default or Mandatory tier is wanted.
############################################################

section "KDE Foundation: SOME groups (curated packages)"

SOME_PACKAGES=(
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
  pinta
)

if dnf -y install "${SOME_PACKAGES[@]}"; then
  complete_section "KDE Foundation: SOME groups (curated packages)"
else
  warn "One or more curated KDE Foundation packages could not be installed."
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
# MULTIMEDIA CODECS
# Installs Fedora and RPM Fusion multimedia framework support,
# replaces ffmpeg-free with RPM Fusion ffmpeg, then installs
# the explicit codec packages PhilFed expects.
############################################################

section "Multimedia and codecs"

dnf -y group install multimedia
dnf -y swap ffmpeg-free ffmpeg --allowerasing

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

complete_section "Multimedia and codecs"

############################################################
# MEDIA PLAYBACK
# VLC and extra VLC plugin support.
############################################################

section "Media playback"
dnf -y install \
  vlc \
  vlc-plugins-base \
  vlc-plugins-freeworld

complete_section "Media playback"

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
  gnome-disk-utility \
  btrfs-assistant \
  snapper \
  unzip \
  p7zip \
  p7zip-plugins \
  unrar

complete_section "System utilities"

############################################################
# USER SHELL
# Sets Fish as the default shell for the normal user and
# creates standard DNF and Flatpak aliases.
############################################################

section "Set Fish as shell for ${TARGET_USER}"

FISH_READY=true

if [[ -x /usr/bin/fish ]]; then
  if ! chsh -s /usr/bin/fish "${TARGET_USER}"; then
    warn "Could not set Fish shell for ${TARGET_USER}"
    FISH_READY=false
  fi

  section "Configure Fish aliases"

  if [[ "${FISH_READY}" == "true" ]]; then
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
      complete_section "Fish shell and aliases"
    else
      warn "Could not configure Fish aliases for ${TARGET_USER}"
    fi
  fi
else
  warn "Fish is not installed. Skipping shell configuration."
fi

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
# BOOT TWEAKS AND CLEANUP
# Updates Flatpak runtimes, disables unnecessary boot waiting,
# previews packages DNF considers removable without removing
# them, then clears cached DNF data.
############################################################

section "Boot tweaks and cleanup"

if flatpak update -y; then
  echo "Flatpak applications and runtimes updated."
else
  warn "Flatpak application or runtime update failed."
fi

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
  read -rp "Computer name: " NEW_HOSTNAME

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
