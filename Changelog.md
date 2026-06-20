# PhilFed Changelog

## v4.6

### Added
- DNF 5 performance configuration
  - max_parallel_downloads=10
  - fastestmirror=True

- Waterfox browser
  - Installed from COPR repository
  - Alternative browser option alongside Firefox and Brave

### Changed
- None

### Fixed
- None

### Notes
- Parallel downloads increased from Fedora default (3) to improve update speed.
- Waterfox added after positive testing on Fedora 44 KDE.



## v4.5

### Added
- Hostname selector with validation and fallback.
- KDE Partition Manager.
- google-noto-sans-math-fonts.

### Notes
- Math font package enables proper display of mathematical Unicode symbols.




# v4.6 - added
- sudo dnf install kde-partitionmanager

# v4.5 - Added:
- hostname selector with fallback in case disallowed names are used
- Math Unicode Symbol Support [google-noto-sans-math-fonts] (Enables Fancy characters)

# v4.4 - Added:
- qt6-qtdeclarative (it gets pulled in as a dependancy but just in case that changes)
- localsend firewall exceptions
- better filesystem naming (now includes / /home and /games)

# v4.3 - Added:
- flatpak update after Flatpak app installation
- Ensures NVIDIA Flatpak runtimes and GNOME runtimes are current
- Prevents GTK4 Flatpak applications (e.g. Flatseal, ProtonPlus)
- failing with DMA-BUF / Wayland errors after fresh installs
- Chromium and Brave-Origin browsers (as chrome based secondary choices)
- filesystem naming (/ and /games)
