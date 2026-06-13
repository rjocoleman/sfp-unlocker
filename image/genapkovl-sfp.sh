#!/bin/sh -e
# Alpine apkovl generator for the SFP unlocker live image.
# Called by mkimage.sh as: genapkovl-sfp.sh <hostname>
# Produces <hostname>.apkovl.tar.gz in the current directory.
#
# Inputs via env (set by build-iso.sh):
#   SFP_BIN      path to bin/sfp-unlock
#   SFP_LOCALD   path to image/overlay/etc/local.d/sfp.start

HOSTNAME="${1:-sfp-unlocker}"
: "${SFP_BIN:?SFP_BIN must point at bin/sfp-unlock}"
: "${SFP_LOCALD:?SFP_LOCALD must point at the local.d start script}"

cleanup() { rm -rf "$tmp"; }
tmp="$(mktemp -d)"
trap cleanup EXIT

makefile() {
	OWNER="$1"
	PERMS="$2"
	FILENAME="$3"
	cat >"$FILENAME"
	chown "$OWNER" "$FILENAME"
	chmod "$PERMS" "$FILENAME"
}

rc_add() {
	mkdir -p "$tmp/etc/runlevels/$2"
	ln -sf "/etc/init.d/$1" "$tmp/etc/runlevels/$2/$1"
}

mkdir -p "$tmp/etc"
makefile root:root 0644 "$tmp/etc/hostname" <<EOF
$HOSTNAME
EOF

mkdir -p "$tmp/etc/apk"
makefile root:root 0644 "$tmp/etc/apk/world" <<EOF
alpine-base
ethtool
pciutils
EOF

# Loopback only, so the networking service starts cleanly. The unlock works
# offline; for DHCP run 'setup-interfaces' then 'rc-service networking restart'.
mkdir -p "$tmp/etc/network"
makefile root:root 0644 "$tmp/etc/network/interfaces" <<EOF
auto lo
iface lo inet loopback
EOF

# The unlock tool.
mkdir -p "$tmp/usr/local/sbin"
install -m 0755 "$SFP_BIN" "$tmp/usr/local/sbin/sfp-unlock"

# Boot-time banner (runs via the openrc 'local' service).
mkdir -p "$tmp/etc/local.d"
install -m 0755 "$SFP_LOCALD" "$tmp/etc/local.d/sfp.start"

# Services: standard live bring-up plus networking and local.d.
rc_add devfs sysinit
rc_add dmesg sysinit
rc_add mdev sysinit
rc_add hwdrivers sysinit
rc_add modloop sysinit

rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot
rc_add networking boot
rc_add local boot

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

tar -c -C "$tmp" etc usr | gzip -9n >"$HOSTNAME.apkovl.tar.gz"
