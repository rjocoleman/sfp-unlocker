#!/bin/sh
# Produce netboot.xyz/iPXE artefacts.
# Usage: image/build-pxe.sh [OUTDIR]   (default: dist/pxe)
#
# Fetches Alpine's official netboot kernel/initramfs/modloop (the netboot
# initramfs has DHCP + HTTPS; the ISO one does not), builds our apkovl, and
# writes a filled-in sfp.ipxe. Serve OUTDIR over HTTP/HTTPS, or upload to a
# release, and point your iPXE/netboot.xyz at sfp.ipxe.

set -eu

ALPINE_VERSION="${ALPINE_VERSION:-3.21}"
ALPINE_IMAGE="${ALPINE_IMAGE:-alpine:${ALPINE_VERSION}}"
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
outdir=${1:-dist/pxe}

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
	echo "error: docker daemon not reachable - start Docker and retry" >&2
	exit 1
fi

mkdir -p "$repo_root/$outdir"

docker run --rm \
	--platform "$TARGET_PLATFORM" \
	-e ALPINE_VERSION="$ALPINE_VERSION" \
	-e OUTDIR="$outdir" \
	-v "$repo_root":/work \
	"$ALPINE_IMAGE" /bin/sh -eu /work/image/in-container-pxe.sh

# Write the iPXE script with the pinned branch substituted in.
sed "s/^set branch .*/set branch v${ALPINE_VERSION}/" \
	"$repo_root/image/netboot/sfp.ipxe" >"$repo_root/$outdir/sfp.ipxe"
cp "$repo_root/image/netboot/netboot.xyz-custom.ipxe" "$repo_root/$outdir/"

echo ">> PXE artefacts in $outdir:"
ls -lh "$repo_root/$outdir"
echo ">> edit ${outdir}/sfp.ipxe and set 'base' to your HTTP server URL."
