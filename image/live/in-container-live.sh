#!/bin/sh
# Runs INSIDE a privileged Debian container (invoked by build-live.sh).
# Builds the live filesystem once and produces both outputs from it:
#   dist/sfp-unlocker.iso                              BIOS+UEFI hybrid ISO (USB-writable)
#   dist/pxe/{vmlinuz,initrd.img,filesystem.squashfs}  for HTTP/PXE netboot

set -eu

work=/work
build=/tmp/live

echo ">> installing live-build"
export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null
apt-get install -y --no-install-recommends live-build xorriso xz-utils zstd >/dev/null

echo ">> assembling config"
rm -rf "$build"
mkdir -p "$build"
cp -a "$work/image/live/auto" "$build/"
cp -a "$work/image/live/config" "$build/"
install -Dm0755 "$work/bin/sfp-unlock" "$build/config/includes.chroot/usr/local/sbin/sfp-unlock"
cd "$build"

echo ">> building (chroot + hybrid ISO)"
lb config
lb build

mkdir -p "$work/dist/pxe"
cp live-image-amd64.hybrid.iso "$work/dist/sfp-unlocker.iso"

# PXE reuses the kernel and initrd from the ISO's binary tree; the rootfs is the
# ISO itself (iPXE loads it and an init hook loop-mounts it), so the loose
# squashfs isn't needed.
cp "$(find binary/live -maxdepth 1 -name 'vmlinuz*' | sort | head -1)" "$work/dist/pxe/vmlinuz"
cp "$(find binary/live -maxdepth 1 -name 'initrd*' | sort | head -1)" "$work/dist/pxe/initrd.img"

echo ">> artefacts:"
ls -lh "$work/dist/sfp-unlocker.iso"
ls -lh "$work/dist/pxe"
