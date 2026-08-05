#!/usr/bin/env bash
set -euo pipefail

# Linux Gamer Life Arch Bootstrap (TTY friendly)
# Goal: Start from Arch minimal (TTY), run once, reboot into KDE Plasma.

# -----------------------------
# Colours (LGL style)
# -----------------------------
GREEN='\033[38;2;0;255;0m'
ORANGE='\033[38;2;255;153;0m'
RED='\033[38;2;255;68;68m'
WHITE='\033[38;2;249;249;249m'
RESET='\033[0m'
BOLD='\033[1m'

section() { printf "\n${BOLD}${GREEN}==> %s${RESET}\n" "$1"; }
info() { printf "${WHITE}%s${RESET}\n" "$1"; }
warn() { printf "${BOLD}${RED}Warning:${RESET} ${WHITE}%s${RESET}\n" "$1"; }
cmdhint() { printf "${ORANGE}%s${RESET}\n" "$1"; }

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

printf "${BOLD}${GREEN}Linux Gamer Life Arch KDE Bootstrap${RESET}\n"
require_root

TARGET_USER="$(get_target_user)"
info "Target user: ${TARGET_USER}"

# -----------------------------
# 1) Update system and core tools
# -----------------------------
section "Base update and core tools"

pacman -Syu --noconfirm

pacman -S --noconfirm \
  curl wget git base-devel fastfetch btop \
  vlc \
  qbittorrent
  
# Full FFmpeg codec support
pacman -S --noconfirm ffmpeg \
  x264 x265 libvpx dav1d svt-av1 libaom \
  opus lame libvorbis libwebp libass || true

# -----------------------------
# Enable multilib
# -----------------------------
echo "Enabling multilib..."

if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "multilib repo section missing from pacman.conf"
fi

sed -i '/^\#\[multilib\]/,/^\#Include/s/^#//' /etc/pacman.conf

pacman -Syy


# -----------------------------
# KDE Plasma (minimal)
# -----------------------------
echo "Installing KDE Plasma (minimal)..."

pacman -S --noconfirm \
  plasma-desktop \
  plasma-workspace \
  kde-system-meta \
  sddm \
  konsole \
  spectacle \
  ark \
  okular \
  gwenview \
  kate \
  kcalc \
  kolourpaint \
  discover

# -----------------------------
# 4) Multimedia and AMD stack
# -----------------------------
section "Multimedia and AMD drivers"

pacman -S --noconfirm \
  mesa \
  libva-mesa-driver \
  vulkan-icd-loader \
  gst-plugins-base \
  gst-plugins-good \
  gst-plugins-bad \
  gst-plugins-ugly \
  gst-libav

# -----------------------------
# 5) Gaming tools
# -----------------------------
section "Gaming tools"

pacman -S --noconfirm \
  steam \
  lutris \
  mangohud \
  obs-studio

# -----------------------------
# 6) Flatpak apps
# -----------------------------
section "Flatpak apps"

flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

flatpak install -y flathub com.github.tchx84.Flatseal
flatpak install -y flathub net.davidotek.pupgui2
flatpak install -y flathub com.vysp3r.ProtonPlus
flatpak install -y flathub com.heroicgameslauncher.hgl
flatpak update -y

# -----------------------------
# 7) Virtualization
# -----------------------------
section "Virtualization"

pacman -S --noconfirm \
  virt-manager \
  qemu-full \
  libvirt \
  virt-install \
  virt-viewer \
  edk2-ovmf \
  swtpm

systemctl enable --now libvirtd

usermod -aG libvirt "${TARGET_USER}"

# -----------------------------
# 8) Boot target
# -----------------------------
section "Boot configuration"

systemctl set-default graphical.target
systemctl enable sddm

# -----------------------------
# Finish
# -----------------------------
section "Complete"

info "Bootstrap finished"
info "Reboot to start KDE Plasma:"
cmdhint "reboot"
