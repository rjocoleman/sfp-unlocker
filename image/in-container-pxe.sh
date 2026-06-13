#!/bin/sh
# Runs INSIDE the Alpine container (invoked by build-pxe.sh).
# Extracts boot files from the ISO and builds the apkovl into OUTDIR.

set -eu

OUTDIR="${OUTDIR:-dist/pxe}"
work=/work
dst="$work/$OUTDIR"

apk add --no-cache xorriso >/dev/null

mkdir -p "$dst"
echo ">> extracting kernel/initramfs/modloop from ISO"
xorriso -osirrox on -indev "$work/dist/sfp-unlocker.iso" \
	-extract /boot/vmlinuz-lts "$dst/vmlinuz-lts" \
	-extract /boot/initramfs-lts "$dst/initramfs-lts" \
	-extract /boot/modloop-lts "$dst/modloop-lts"

echo ">> building apkovl"
SFP_BIN="$work/bin/sfp-unlock" \
	SFP_LOCALD="$work/image/overlay/etc/local.d/sfp.start" \
	sh "$work/image/genapkovl-sfp.sh" sfp-unlocker
mv sfp-unlocker.apkovl.tar.gz "$dst/"

echo ">> extracted to $OUTDIR"
