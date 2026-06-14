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

  # Linux (e.g. the Proxmox host): mount this image and run the script
  mount -o loop,ro /path/to/sfp-unlocker-tools.img /mnt   # or the device, e.g. /dev/sdb
  sh /mnt/sfp-unlock --list
  sh /mnt/sfp-unlock <iface>                       # dry-run
  sh /mnt/sfp-unlock <iface> --commit --backup-dir /root   # backup, confirm, write, verify

  Invoke via "sh /mnt/sfp-unlock" - FAT carries no execute bit, so the file may
  not be directly runnable. Backups need a writable location (the image is
  read-only), so pass --backup-dir to somewhere writable like /root.

The script automatically uses the ethtool sitting next to it, so the host does
not need ethtool installed. A cold power-cycle is required after a write.

Attach via iLO/iDRAC as Virtual USB/removable media, then mount as above.
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
