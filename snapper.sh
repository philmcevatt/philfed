#!/usr/bin/env bash
#
# snapper-fedora-root-only.sh
# ----------------------------
# Root-only Snapper + grub-btrfs setup for Fedora 44 (DNF5/libdnf5).
# Adapted from https://github.com/SysGuides/sysguides-snapper-fedora
# (same author who suggested the multi-subvolume root layout).
#
# Differences from the upstream script:
# - No /home Snapper config: home stays on its own partition, untouched.
# - Root timeline snapshots OFF by default (only pre/post dnf transactions).
#   Set TIMELINE=yes below if you also want hourly/daily timeline snapshots
#   to catch changes made outside dnf (manual config edits, etc).
# - Everything else (DNF5 action hooks, WAL checkpoint fix, GUI package
#   description capture, grub-btrfs) kept as-is.
#
# Compatible with your multi-subvolume root layout: Snapper only ever
# snapshots the exact subvolume its config points at (here, "/"), so your
# separately-mounted /var/cache, /var/lib/containers, /var/lib/flatpak
# etc. subvolumes are automatically excluded from every snapshot.
#
# NOTE: full kernel/initramfs rollback via grub-btrfs requires /boot to
# also be on Btrfs. On a standard Fedora layout /boot is ext4, so
# snapshots still restore package/userspace state correctly, but booting
# into a snapshot won't roll back a bad kernel update. Check with:
#   findmnt /boot

set -e

TIMELINE=no   # change to "yes" for hourly/daily/weekly timeline snapshots too

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -eq 0 ]]; then
    echo "Please run this script as a normal user (it will sudo where needed):"
    echo "  ./snapper-fedora-root-only.sh"
    exit 1
fi

echo "[1/6] Installing required packages..."
sudo dnf install -y snapper libdnf5-plugin-actions btrfs-assistant

if ! findmnt -n -o FSTYPE / | grep -q btrfs; then
    echo "Error: Root filesystem is not Btrfs"
    exit 1
fi

echo "[2/6] Configuring Snapper for / only..."

[ -d /.snapshots ] || sudo snapper -c root create-config /
sudo restorecon -RFv /.snapshots

REAL_USER=${SUDO_USER:-$USER}
sudo snapper -c root set-config ALLOW_USERS="$REAL_USER" SYNC_ACL=yes
sudo snapper -c root set-config TIMELINE_CREATE="$TIMELINE"

echo "[3/6] Excluding .snapshots from updatedb (mlocate)..."

if command -v updatedb >/dev/null 2>&1 && [ -f /etc/updatedb.conf ]; then
    if grep -q '^PRUNENAMES' /etc/updatedb.conf; then
        grep -q '\.snapshots' /etc/updatedb.conf || \
        sudo sed -i 's|^PRUNENAMES *= *"|PRUNENAMES = ".snapshots |' /etc/updatedb.conf
    else
        echo 'PRUNENAMES = ".snapshots"' | sudo tee -a /etc/updatedb.conf
    fi
else
    echo "  (mlocate/updatedb not installed — skipping)"
fi

echo "[4/6] Installing grub-btrfs..."

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
cd "$tmpdir"

git clone --depth 1 https://github.com/Antynea/grub-btrfs
cd grub-btrfs

sed -i \
-e 's|^#GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS=.*|GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="rd.live.overlay.overlayfs=1"|' \
-e 's|^#GRUB_BTRFS_GRUB_DIRNAME=.*|GRUB_BTRFS_GRUB_DIRNAME="/boot/grub2"|' \
-e 's|^#GRUB_BTRFS_MKCONFIG=.*|GRUB_BTRFS_MKCONFIG=/usr/bin/grub2-mkconfig|' \
-e 's|^#GRUB_BTRFS_SCRIPT_CHECK=.*|GRUB_BTRFS_SCRIPT_CHECK=grub2-script-check|' \
config

sudo make install
sudo systemctl enable --now grub-btrfsd.service

echo "==> Updating GRUB configuration..."
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

echo "[5/6] Installing Snapper integration scripts..."

sudo mkdir -p /usr/local/bin

sudo tee /usr/local/bin/snapper-desc.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# Returns "GUI" for PackageKit/dnf5daemon-triggered transactions,
# otherwise the actual CLI command that triggered the transaction.
PID="$1"
cmd=$(ps -o command --no-headers -p "$PID" 2>/dev/null || echo "Unknown Task")
case "$cmd" in
    */dnf5daemon* | */packagekitd*) echo "GUI" ;;
    *) echo "$cmd" ;;
esac
EOF

sudo tee /usr/local/bin/snapper-gui-pkg.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# Records the first package name/action of a GUI (Discover) transaction
# so the snapshot description reads e.g. "GUI install firefox".
PID="$1"; ACTION="$2"; NAME="$3"
STATE_DIR="/run/snapper-actions"
DESC_FILE="$STATE_DIR/snapper_desc_${PID}"
PKG_FILE="$STATE_DIR/snapper_gui_${PID}"
desc=$(cat "$DESC_FILE" 2>/dev/null || echo "")
[[ "$desc" != "GUI" ]] && exit 0
[[ -f "$PKG_FILE" ]] && exit 0
case "$ACTION" in
    I|U|D|R) echo "GUI install ${NAME}" > "$PKG_FILE" ;;
    E|O)     echo "GUI remove ${NAME}" > "$PKG_FILE" ;;
esac
EOF

sudo tee /usr/local/bin/snapper-wal-checkpoint.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# Forces an SQLite WAL checkpoint on libdnf5's rpmdb before the POST
# snapshot is taken, so a "snapper undochange" doesn't leave the rpm
# database out of sync with the reverted filesystem state.
python3 - <<'PYEOF'
import sqlite3, time, sys
DB = "/usr/lib/sysimage/rpm/rpmdb.sqlite"
for i in range(10):
    try:
        conn = sqlite3.connect(DB, timeout=3)
        conn.execute("PRAGMA busy_timeout=3000")
        result = conn.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        conn.close()
        if result and result[1] == 0:
            sys.exit(0)
    except sqlite3.OperationalError:
        pass
    time.sleep(0.5)
sys.exit(1)
PYEOF
EOF

sudo tee /usr/local/bin/snapper-pre.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -e
# Creates the PRE snapshot before a DNF5 transaction begins.
PID="$1"
STATE_DIR="/run/snapper-actions"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

# Workaround: on a fresh setup, DNF5 can fail with "cannot copy:
# packages.toml" if this directory is missing, leaving an orphaned
# PRE snapshot with no matching POST.
if [[ ! -d /usr/lib/sysimage/libdnf5 ]]; then
    mkdir -p /usr/lib/sysimage/libdnf5
    restorecon -q /usr/lib/sysimage/libdnf5 2>/dev/null || true
fi

desc=$(/usr/local/bin/snapper-desc.sh "$PID")
echo "$desc" > "$STATE_DIR/snapper_desc_${PID}"

pre=$(snapper -c root create -c number -t pre -p -d "$desc") || exit 1
echo "$pre" > "$STATE_DIR/snapper_pre_${PID}"
EOF

sudo tee /usr/local/bin/snapper-post.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# Creates the POST snapshot after a DNF5 transaction completes,
# linked to the matching PRE snapshot, with WAL-checkpoint fix applied
# first and the GUI package name folded into the description if present.
PID="$1"
STATE_DIR="/run/snapper-actions"
DESC_FILE="$STATE_DIR/snapper_desc_${PID}"
PRE_FILE="$STATE_DIR/snapper_pre_${PID}"
GUI_FILE="$STATE_DIR/snapper_gui_${PID}"

desc=$(cat "$DESC_FILE" 2>/dev/null || echo "")
pre=$(cat "$PRE_FILE" 2>/dev/null || echo "")
gui_pkg=$(cat "$GUI_FILE" 2>/dev/null || echo "")

[[ -z "$pre" ]] && exit 0

if [[ -n "$gui_pkg" ]]; then
    desc="$gui_pkg"
    snapper -c root modify -d "$desc" "$pre" || true
fi

/usr/local/bin/snapper-wal-checkpoint.sh || true

snapper -c root create -c number -t post --pre-number "$pre" -d "$desc"

rm -f "$DESC_FILE" "$PRE_FILE" "$GUI_FILE"
EOF

sudo chmod 755 /usr/local/bin/snapper-desc.sh /usr/local/bin/snapper-gui-pkg.sh \
    /usr/local/bin/snapper-wal-checkpoint.sh /usr/local/bin/snapper-pre.sh \
    /usr/local/bin/snapper-post.sh
sudo restorecon -v /usr/local/bin/snapper-*.sh

sudo mkdir -p /etc/dnf/libdnf5-plugins/actions.d/
sudo tee /etc/dnf/libdnf5-plugins/actions.d/snapper.actions >/dev/null <<'EOF'
# Snapper integration with libdnf5 (DNF5 transactions) — root only.
pre_transaction::::/usr/local/bin/snapper-pre.sh ${pid}
pre_transaction:*:in::/usr/local/bin/snapper-gui-pkg.sh ${pid} ${pkg.action} ${pkg.name}
pre_transaction:*:out::/usr/local/bin/snapper-gui-pkg.sh ${pid} ${pkg.action} ${pkg.name}
post_transaction::::/usr/local/bin/snapper-post.sh ${pid}
EOF

echo "[6/6] Enabling Snapper cleanup timer..."
sudo systemctl enable --now snapper-cleanup.timer
if [[ "$TIMELINE" == "yes" ]]; then
    sudo systemctl enable --now snapper-timeline.timer
fi

echo ""
echo "Done. Try it:"
echo "  sudo dnf install htop"
echo "  snapper -c root ls"
echo "  snapper -c root status <pre>..<post>"
echo "  sudo snapper -c root undochange <pre>..<post>"
