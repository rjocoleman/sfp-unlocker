#!/bin/sh
# Runs INSIDE the Alpine container (invoked by build-img.sh).
# Builds a static ethtool and packs it with sfp-unlock into a FAT image.

set -eu

ETHTOOL_VERSION="${ETHTOOL_VERSION:-6.11}"
OUT_NAME="${OUT_NAME:-sfp-unlocker-tools.img}"
work=/work
img="$work/dist/$OUT_NAME"

echo ">> installing build tools"
apk add --no-cache build-base linux-headers curl xz dosfstools mtools file >/dev/null

echo ">> building static ethtool $ETHTOOL_VERSION"
cd /tmp
curl -fsSLO "https://mirrors.edge.kernel.org/pub/software/network/ethtool/ethtool-${ETHTOOL_VERSION}.tar.xz"
tar xf "ethtool-${ETHTOOL_VERSION}.tar.xz"
cd "ethtool-${ETHTOOL_VERSION}"
# --disable-netlink drops the libmnl dependency; EEPROM read/write uses the
# ioctl path, which is exactly what we need and links cleanly as static musl.
./configure --disable-netlink LDFLAGS="-static" >/dev/null
make -j"$(nproc)" >/dev/null
strip ethtool

echo ">> verifying it is static and runs"
file ethtool | grep -q "statically linked" || {
	echo "error: ethtool is not statically linked" >&2
	exit 1
}
./ethtool --version

echo ">> assembling FAT image"
cat >/tmp/README.txt <<'EOF'
sfp-unlocker - mini tools image (non-bootable)

This image holds just two things:
  sfp-unlock   the unlock script (POSIX sh)
  ethtool      a statically-linked x86_64 ethtool (no host install needed)

Run it on the CURRENTLY RUNNING OS - no reboot:

  # From the image file (e.g. on the Proxmox host):
  mount -o loop,ro /path/to/sfp-unlocker-tools.img /mnt

  # Over iLO/iDRAC virtual media it shows up as a block device, not a file:
  lsblk                          # find the new ~8M removable device, e.g. sdi
  mount -o ro /dev/sdi /mnt      # whole device - there is no partition table

  sh /mnt/sfp-unlock --list
  sh /mnt/sfp-unlock <iface>            # dry-run
  sh /mnt/sfp-unlock <iface> --commit   # backup auto-lands in /root

Invoke via "sh /mnt/sfp-unlock" - FAT carries no execute bit, so the file may
not be directly runnable. The mount is read-only, so the backup cannot sit next
to the image; the tool falls back to a writable dir (/root, then /var/tmp, then
/tmp) and prints where it went. Use --backup-dir DIR to choose.

The script automatically uses the ethtool sitting next to it, so the host does
not need ethtool installed. A cold power-cycle is required after a write.
x86_64 only. See the project README and docs/ for details.
EOF

mkdir -p "$work/dist"
rm -f "$img"
# 8 MiB is plenty for a ~1 MiB static ethtool plus the script.
dd if=/dev/zero of="$img" bs=1M count=8 status=none
mkfs.fat -n SFPUNLOCK "$img" >/dev/null
mcopy -i "$img" "$work/bin/sfp-unlock" ::sfp-unlock
mcopy -i "$img" ethtool ::ethtool
mcopy -i "$img" /tmp/README.txt ::README.txt

echo ">> image contents:"
mdir -i "$img" ::
