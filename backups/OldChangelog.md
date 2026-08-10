# PhilFed Changelog

## v4.6

### Added

- DNF 5 performance configuration.
  - max_parallel_downloads=10
  - fastestmirror=True
  - Increases parallel downloads from Fedora's default of 3.
  - Helps prevent large packages monopolising download slots during updates.

- Waterfox browser.
  - Installed from COPR repository.
  - Firefox-based alternative alongside Firefox, Brave and Chromium.
  - Added after positive testing on Fedora 44 KDE.
  - Supports streaming services that did not work correctly in Floorp.

### Changed

- None.

### Fixed

- None.


## v4.5

### Added

- Hostname selector with validation and fallback.
  - Allows user to select a hostname during installation.
  - Useful for consistent naming across systems (e.g. fed-d, fed-l).
  - Includes fallback handling for invalid or disallowed names.

- KDE Partition Manager.
  - GUI partition management tool.
  - Useful for dual-boot setups and Linux filesystem maintenance.

- google-noto-sans-math-fonts.
  - Enables proper display of mathematical Unicode symbols.
  - Added after LibreOffice failed to display certain Unicode maths characters correctly.

### Changed

- None.

### Fixed

- None.


## v4.4

### Added

- qt6-qtdeclarative.
  - Currently installed as a dependency.
  - Added explicitly in case dependency requirements change in future Fedora releases.

- LocalSend firewall exceptions.
  - Allows LocalSend device discovery and file transfers to function correctly through Fedora's firewall.

- Improved filesystem naming.
  - Added labels for:
    - /
    - /home
    - /games
  - Makes partition identification easier in KDE tools and installers.

### Changed

- None.

### Fixed

- None.


## v4.3

### Added

- Flatpak update after Flatpak application installation.
  - Ensures Flatpak runtimes are fully up to date immediately after installation.
  - Updates NVIDIA and GNOME runtimes commonly required by desktop applications.
  - Prevents GTK4 Flatpak applications such as Flatseal and ProtonPlus failing with DMA-BUF / Wayland errors after a fresh install.

- Chromium browser.
  - Added as a Chromium-based alternative browser.

- Brave Browser (Origin build).
  - Added as a Chromium-based alternative browser.

- Filesystem naming.
  - Added labels for:
    - /
    - /games
  - Improves partition identification and management.

### Changed

- None.

### Fixed

- None.
