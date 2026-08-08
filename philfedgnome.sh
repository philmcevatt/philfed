(...)  # Script header and initial setup

# System Upgrade
color_echo "blue" "Performing system upgrade... This may take a while..."
dnf upgrade -y > /dev/null 2>&1


# System Config
# Set the system hostname to uniquely identify the machine on the network
color_echo "yellow" "Setting hostname..."
hostnamectl set-hostname fedgnome > /dev/null 2>&1

# Optimize DNF package manager for faster downloads and efficient updates
color_echo "yellow" "Configuring DNF Package Manager..."
backup_file "/etc/dnf/dnf.conf" > /dev/null 2>&1
dnf -y install dnf-plugins-core > /dev/null 2>&1
# Max Parallel Downloads
echo "max_parallel_downloads=10" | tee -a /etc/dnf/dnf.conf > /dev/null
# Default Yes
echo "defaultyes=True" | tee -a /etc/dnf/dnf.conf > /dev/null

# Enable and configure automatic system updates to enhance security and stability
color_echo "yellow" "Enabling DNF autoupdate..."
dnf install dnf-automatic -y > /dev/null 2>&1
sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf > /dev/null 2>&1
systemctl enable --now dnf-automatic.timer > /dev/null 2>&1

# Replace Fedora Flatpak Repo with Flathub for better package management and apps stability
color_echo "yellow" "Replacing Fedora Flatpak Repo with Flathub..."
dnf install -y flatpak > /dev/null 2>&1
flatpak remote-delete fedora --force || true > /dev/null 2>&1
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo > /dev/null 2>&1
sudo flatpak repair > /dev/null 2>&1
flatpak update > /dev/null 2>&1

# Check and apply firmware updates to improve hardware compatibility and performance
color_echo "yellow" "Checking for firmware updates..."
fwupdmgr refresh --force > /dev/null 2>&1
fwupdmgr get-updates > /dev/null 2>&1
fwupdmgr update -y > /dev/null 2>&1

# Enable RPM Fusion repositories to access additional software packages and codecs
color_echo "yellow" "Enabling RPM Fusion repositories..."
dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm > /dev/null 2>&1
dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm > /dev/null 2>&1
dnf update @core -y

# Install multimedia codecs to enhance multimedia capabilities
color_echo "yellow" "Installing multimedia codecs..."
dnf swap ffmpeg-free ffmpeg --allowerasing -y > /dev/null 2>&1
dnf update @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin -y
dnf update @sound-and-video -y

# Install Hardware Accelerated Codecs for Intel integrated GPUs. This improves video playback and encoding performance on systems with Intel graphics.
color_echo "yellow" "Installing Intel Hardware Accelerated Codecs..."
dnf -y install intel-media-driver > /dev/null 2>&1

# Install Hardware Accelerated Codecs for AMD GPUs. This improves video playback and encoding performance on systems with AMD graphics.
color_echo "yellow" "Installing AMD Hardware Accelerated Codecs..."
dnf swap mesa-va-drivers mesa-va-drivers-freeworld -y > /dev/null 2>&1
dnf swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld -y > /dev/null 2>&1

# Install virtualization tools to enable virtual machines and containerization
color_echo "yellow" "Installing virtualization tools..."
dnf install -y @virtualization > /dev/null 2>&1

# Configure power settings to prevent system sleep and hibernation
color_echo "yellow" "Configuring power settings..."
sudo -u $ACTUAL_USER gsettings set org.gnome.desktop.session idle-delay 0 > /dev/null 2>&1
sudo -u $ACTUAL_USER gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' > /dev/null 2>&1
sudo -u $ACTUAL_USER gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' > /dev/null 2>&1
sudo -u $ACTUAL_USER gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0 > /dev/null 2>&1
sudo -u $ACTUAL_USER gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0 > /dev/null 2>&1
sudo -u $ACTUAL_USER gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'suspend' > /dev/null 2>&1


# App Install
# Install essential applications
color_echo "yellow" "Installing essential applications..."
dnf install -y btop rsync fastfetch unzip unrar wget curl gnome-tweaks > /dev/null 2>&1
color_echo "green" "Essential applications installed successfully."

# Install Internet & Communication applications
color_echo "yellow" "Installing Firefox..."
dnf install -y firefox > /dev/null 2>&1
color_echo "green" "Firefox installed successfully."
color_echo "yellow" "Installing Chromium..."
dnf install -y chromium > /dev/null 2>&1
color_echo "green" "Chromium installed successfully."
color_echo "yellow" "Installing Discord..."
dnf install -y discord > /dev/null 2>&1
color_echo "green" "Discord installed successfully."

# Install Office Productivity applications
color_echo "yellow" "Installing LibreOffice..."
dnf remove -y libreoffice* > /dev/null 2>&1
flatpak install -y flathub org.libreoffice.LibreOffice > /dev/null 2>&1
flatpak install -y --reinstall org.freedesktop.Platform.Locale/x86_64/24.08 > /dev/null 2>&1
flatpak install -y --reinstall org.libreoffice.LibreOffice.Locale > /dev/null 2>&1
color_echo "green" "LibreOffice installed successfully."
color_echo "yellow" "Installing Obsidian..."
flatpak install -y flathub md.obsidian.Obsidian > /dev/null 2>&1
color_echo "green" "Obsidian installed successfully."
color_echo "yellow" "Installing KeePassXC..."
dnf install -y keepassxc > /dev/null 2>&1
color_echo "green" "KeePassXC installed successfully."

# Install Media & Graphics applications
color_echo "yellow" "Installing VLC..."
dnf install -y vlc > /dev/null 2>&1
color_echo "green" "VLC installed successfully."
color_echo "yellow" "Installing OBS Studio..."
dnf install -y obs-studio > /dev/null 2>&1
color_echo "green" "OBS Studio installed successfully."
color_echo "yellow" "Installing Kdenlive..."
dnf install -y kdenlive > /dev/null 2>&1
color_echo "green" "Kdenlive installed successfully."

# Install Gaming & Emulation applications
color_echo "yellow" "Installing Steam..."
dnf install -y steam > /dev/null 2>&1
color_echo "green" "Steam installed successfully."
color_echo "yellow" "Installing Lutris..."
dnf install -y lutris > /dev/null 2>&1
color_echo "green" "Lutris installed successfully."
color_echo "yellow" "Installing Heroic Games Launcher..."
flatpak install -y flathub com.heroicgameslauncher.hgl > /dev/null 2>&1
color_echo "green" "Heroic Games Launcher installed successfully."

# Install File Sharing & Download applications
color_echo "yellow" "Installing qBittorrent..."
dnf install -y qbittorrent > /dev/null 2>&1
color_echo "green" "qBittorrent installed successfully."
color_echo "yellow" "Installing Video Downloader..."
flatpak install -y flathub com.github.unrud.VideoDownloader > /dev/null 2>&1
color_echo "green" "Video Downloader installed successfully."

# Install System Tools applications
color_echo "yellow" "Installing Mission Center..."
flatpak install -y flathub io.missioncenter.MissionCenter > /dev/null 2>&1
color_echo "green" "Mission Center installed successfully."
color_echo "yellow" "Installing Flatseal..."
flatpak install -y flathub com.github.tchx84.Flatseal > /dev/null 2>&1
color_echo "green" "Flatseal installed successfully."
color_echo "yellow" "Installing Extension Manager..."
flatpak install -y flathub com.mattjakeman.ExtensionManager > /dev/null 2>&1
color_echo "green" "Extension Manager installed successfully."
color_echo "yellow" "Installing PeaZip..."
flatpak install -y flathub io.github.peazip.PeaZip > /dev/null 2>&1
color_echo "green" "PeaZip installed successfully."


# Customization
# Install Microsoft Windows fonts (core)
color_echo "yellow" "Installing Microsoft Fonts (core)..."
dnf install -y curl cabextract xorg-x11-font-utils fontconfig > /dev/null 2>&1
rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm > /dev/null 2>&1
color_echo "green" "Microsoft Fonts (core) installed successfully."

# Install Google fonts collection
color_echo "yellow" "Installing Google Fonts..."
wget -O /tmp/google-fonts.zip https://github.com/google/fonts/archive/main.zip > /dev/null 2>&1
mkdir -p $ACTUAL_HOME/.local/share/fonts/google > /dev/null 2>&1
unzip /tmp/google-fonts.zip -d $ACTUAL_HOME/.local/share/fonts/google > /dev/null 2>&1
rm -f /tmp/google-fonts.zip > /dev/null 2>&1
fc-cache -fv > /dev/null 2>&1
color_echo "green" "Google Fonts installed successfully."

# A flat colorful design icon theme for linux desktops
color_echo "yellow" "Installing Papirus Icon Theme..."
dnf install -y papirus-icon-theme > /dev/null 2>&1
sudo -u $ACTUAL_USER gsettings set org.gnome.desktop.interface icon-theme "Papirus" > /dev/null 2>&1
color_echo "green" "Papirus Icon Theme installed successfully."


# Custom Script
# Custom user-defined commands
echo "Created with ❤️ for Open Source"


(...)  # Script footer
