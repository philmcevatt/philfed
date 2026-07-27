#!/usr/bin/env bash
set -euo pipefail

# openSUSE Tumbleweed Bootstrap
# Start from openSUSE Tumbleweed minimal/server install (TTY),
# run once, then reboot into KDE Plasma.

# -----------------------------
# Colours
# -----------------------------
GREEN='\033[38;2;0;255;0m'
ORANGE='\033[38;2;255;153;0m'
RED='\033[38;2;255;68;68m'
WHITE='\033[38;2;249;249;249m'
RESET='\033[0m'
BOLD='\033[1m'

section() {
  printf "\n${BOLD}${GREEN}==> %s${RESET}\n" "$1"
}

info() {
  printf "${WHITE}%s${RESET}\n" "$1"
}

warn() {
  printf "${BOLD}${RED}Warning:${RESET} ${WHITE}%s${RESET}\n" "$1"
}

cmdhint() {
  printf "${ORANGE}%s${RESET}\n" "$1"
}

# -----------------------------
# Helpers
# -----------------------------
require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    warn "Run with sudo:"
    cmdhint "sudo bash $0"
    exit 1
  fi
}

get_target_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf "%s" "${SUDO_USER}"
  else
    printf "%s" "$(logname 2>/dev/null || echo root)"
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

zypper_refresh() {
  zypper -n --gpg-auto-import-keys refresh
}

try_install() {
  # Install packages one-by-one so a missing package does not kill the script.
  # Output is deliberately not suppressed so progress remains visible.
  local pkg

  for pkg in "$@"; do
    section "Installing: $pkg"

    if zypper -n in -y "$pkg"; then
      info "Installed: $pkg"
    else
      warn "Could not install: $pkg (skipping)"
    fi
  done
}

repo_exists() {
  local alias="$1"

  zypper lr -u |
    awk '{print $1}' |
    grep -qx "$alias"
}

add_repo_if_missing() {
  local alias="$1"
  local name="$2"
  local url="$3"
  local priority="${4:-99}"

  if repo_exists "$alias"; then
    info "Repo exists: $alias"
    return 0
  fi

  section "Adding repo: $name"

  if zypper -n ar -f -p "$priority" -n "$name" "$url" "$alias"; then
    info "Added repo: $alias"
  else
    warn "Failed to add repo: $alias (continuing)"
    return 1
  fi
}

# -----------------------------
# Detect Tumbleweed
# -----------------------------
detect_tumbleweed() {
  if [[ ! -r /etc/os-release ]]; then
    warn "Cannot read /etc/os-release"
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  OS_ID="${ID:-}"

  if [[ "$OS_ID" != "opensuse-tumbleweed" ]]; then
    warn "This script is intended for openSUSE Tumbleweed only."
    warn "Detected ID=${OS_ID:-unknown}"
    exit 1
  fi

  info "Detected: ${PRETTY_NAME:-openSUSE Tumbleweed}"
}

# -----------------------------
# Official repositories
# -----------------------------
setup_official_repos() {
  add_repo_if_missing \
    "repo-oss" \
    "openSUSE-Tumbleweed-Oss" \
    "https://download.opensuse.org/tumbleweed/repo/oss/" \
    99 || true

  add_repo_if_missing \
    "repo-non-oss" \
    "openSUSE-Tumbleweed-Non-Oss" \
    "https://download.opensuse.org/tumbleweed/repo/non-oss/" \
    99 || true

  add_repo_if_missing \
    "repo-update" \
    "openSUSE-Tumbleweed-Update" \
    "https://download.opensuse.org/update/tumbleweed/" \
    99 || true

  add_repo_if_missing \
    "repo-update-non-oss" \
    "openSUSE-Tumbleweed-Update-Non-Oss" \
    "https://download.opensuse.org/update/tumbleweed-non-oss/" \
    99 || true

  zypper_refresh
}

# -----------------------------
# Packman
# -----------------------------
setup_packman() {
  section "Add Packman and switch multimedia packages"

  add_repo_if_missing \
    "packman" \
    "Packman Repository" \
    "https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/" \
    90 || true

  zypper_refresh

  section "Vendor switch to Packman"

  zypper -n dup \
    --from packman \
    --allow-vendor-change \
    || warn "Packman vendor switch failed (continuing)"
}

# ============================================================
# Start
# ============================================================

printf "${BOLD}${GREEN}Phil's openSUSE Tumbleweed KDE Bootstrap${RESET}\n"

require_root

TARGET_USER="$(get_target_user)"
info "Target user: ${TARGET_USER}"

detect_tumbleweed


# -----------------------------
# Refresh repositories
# -----------------------------
section "Refresh repositories"

# No full Tumbleweed distro update here.
setup_official_repos


# -----------------------------
# Base tools
# -----------------------------
section "Base tools"

try_install \
  curl \
  wget \
  git \
  fastfetch \
  btop \
  htop \
  python3 \
  python3-pip \
  flatpak \
  distrobox


# -----------------------------
# Native desktop applications
# -----------------------------
section "Native applications"

try_install \
  vlc \
  libreoffice


# -----------------------------
# Packman + Multimedia
# -----------------------------
setup_packman

section "Multimedia - FFmpeg and GStreamer"

try_install \
  ffmpeg \
  gstreamer \
  gstreamer-plugins-base \
  gstreamer-plugins-good \
  gstreamer-plugins-bad \
  gstreamer-plugins-ugly \
  gstreamer-plugins-libav


# -----------------------------
# KDE Plasma + SDDM
# -----------------------------
section "KDE Plasma and SDDM"

section "Installing pattern: kde_plasma"

if zypper -n in -y -t pattern kde_plasma; then
  info "Installed pattern: kde_plasma"
else
  warn "Pattern kde_plasma not available."
  warn "Installing core KDE packages instead."

  try_install \
    sddm \
    konsole \
    spectacle \
    ark \
    okular \
    gwenview \
    discover6
fi

# Ensure Discover is present even if the pattern did not include it.
try_install discover6


# -----------------------------
# Graphics, Vulkan and VA-API
# -----------------------------
section "Graphics, Vulkan and VA-API"

try_install \
  Mesa \
  Mesa-dri \
  libvulkan1 \
  vulkan-tools \
  libva2 \
  libva-utils \
  Mesa-libva


# -----------------------------
# Gaming tools
# -----------------------------
section "Gaming tools"

try_install \
  steam \
  mangohud


# -----------------------------
# Lutris
# Native first, Flatpak fallback
# -----------------------------
section "Lutris"

if zypper -n in -y lutris; then
  info "Installed native Lutris package"
else
  warn "Native Lutris installation failed"
  info "Will attempt Flatpak fallback later"

  LUTRIS_FLATPAK_FALLBACK=1
fi


# -----------------------------
# OBS Studio
# Native first, Flatpak fallback
# -----------------------------
section "OBS Studio"

if zypper -n in -y obs-studio; then
  info "Installed native OBS Studio package"
else
  warn "Native OBS Studio installation failed"
  info "Will attempt Flatpak fallback later"

  OBS_FLATPAK_FALLBACK=1
fi


# -----------------------------
# Flatpak apps
# -----------------------------
section "Flatpak apps"

if ! have_cmd flatpak; then

  warn "flatpak command not found"
  warn "Skipping Flatpak section"

else

  flatpak remote-add \
    --if-not-exists \
    flathub \
    https://flathub.org/repo/flathub.flatpakrepo \
    || true

  # ---------------------------
  # Flatseal
  # ---------------------------
  section "Flatpak: Flatseal"

  flatpak install -y \
    flathub \
    com.github.tchx84.Flatseal \
    || warn "Could not install Flatseal"


  # ---------------------------
  # ProtonPlus
  # ---------------------------
  section "Flatpak: ProtonPlus"

  flatpak install -y \
    flathub \
    com.vysp3r.ProtonPlus \
    || warn "Could not install ProtonPlus"


  # ---------------------------
  # Heroic Games Launcher
  # ---------------------------
  section "Flatpak: Heroic"

  flatpak install -y \
    flathub \
    com.heroicgameslauncher.hgl \
    || warn "Could not install Heroic"


  # ---------------------------
  # Lutris fallback
  # ---------------------------
  if [[ "${LUTRIS_FLATPAK_FALLBACK:-0}" == "1" ]]; then

    section "Flatpak fallback: Lutris"

    flatpak install -y \
      flathub \
      net.lutris.Lutris \
      || warn "Could not install Lutris Flatpak"

  fi


  # ---------------------------
  # OBS fallback
  # ---------------------------
  if [[ "${OBS_FLATPAK_FALLBACK:-0}" == "1" ]]; then

    section "Flatpak fallback: OBS Studio"

    flatpak install -y \
      flathub \
      com.obsproject.Studio \
      || warn "Could not install OBS Studio Flatpak"

  fi

fi


# -----------------------------
# Cockpit
# -----------------------------
section "Cockpit"

section "Installing pattern: cockpit"

if zypper -n in -y -t pattern cockpit; then
  info "Installed pattern: cockpit"
else
  warn "Could not install Cockpit pattern"
fi

section "Enable Cockpit socket"

if systemctl enable --now cockpit.socket; then
  info "Enabled cockpit.socket"
else
  warn "Could not enable cockpit.socket"
fi

try_install cockpit-client-launcher


# -----------------------------
# Virtualization
# -----------------------------
section "Virtualization"

try_install \
  virt-manager \
  qemu \
  qemu-kvm \
  libvirt \
  libvirt-client \
  virt-install \
  virt-viewer \
  ovmf \
  swtpm

section "Enable libvirt"

systemctl enable --now libvirtd \
  || warn "Could not enable libvirtd"

usermod -aG libvirt "${TARGET_USER}" 2>/dev/null \
  || warn "Could not add ${TARGET_USER} to libvirt group"

usermod -aG kvm "${TARGET_USER}" 2>/dev/null \
  || warn "Could not add ${TARGET_USER} to kvm group"


# -----------------------------
# Boot target
# -----------------------------
section "Boot configuration"

systemctl set-default graphical.target \
  || warn "Could not set graphical.target"

echo 'DISPLAYMANAGER="sddm"' > /etc/sysconfig/displaymanager

systemctl enable display-manager.service \
  || warn "Could not enable display-manager.service"


# -----------------------------
# Finish
# -----------------------------
section "Complete"

info "openSUSE Tumbleweed bootstrap finished"
info ""
info "Reboot to start KDE Plasma:"
cmdhint "reboot"
