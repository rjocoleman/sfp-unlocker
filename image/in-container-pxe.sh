#!/bin/sh
# Runs INSIDE the Alpine container (invoked by build-pxe.sh).
# Fetches Alpine's netboot kernel/initramfs/modloop and builds the apkovl into
# OUTDIR. The netboot initramfs includes DHCP and HTTPS, which are needed to pull
# the modloop and apkovl over the network; the ISO's initramfs does not.

set -eu

ALPINE_VERSION="${ALPINE_VERSION:-3.21}"
OUTDIR="${OUTDIR:-dist/pxe}"
BRANCH="v${ALPINE_VERSION}"
NETBOOT="https://dl-cdn.alpinelinux.org/alpine/${BRANCH}/releases/x86_64/netboot"
work=/work
dst="$work/$OUTDIR"

apk add --no-cache curl >/dev/null

mkdir -p "$dst"
echo ">> downloading official Alpine netboot files ($BRANCH)"
for f in vmlinuz-lts initramfs-lts modloop-lts; do
	rm -f "$dst/$f" # a stale read-only copy would block curl -o
	curl -fsSL "$NETBOOT/$f" -o "$dst/$f"
	echo "   $f"
done

echo ">> building apkovl"
SFP_BIN="$work/bin/sfp-unlock" \
	SFP_LOCALD="$work/image/overlay/etc/local.d/sfp.start" \
	sh "$work/image/genapkovl-sfp.sh" sfp-unlocker
mv sfp-unlocker.apkovl.tar.gz "$dst/"

echo ">> netboot files ready in $OUTDIR"
