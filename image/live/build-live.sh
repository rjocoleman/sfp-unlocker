#!/bin/sh
# Build the live image(s) with Debian live-build inside a privileged container.
# Produces dist/sfp-unlocker.iso and dist/pxe/{vmlinuz,initrd.img,filesystem.squashfs}.

set -eu

DEBIAN_IMAGE="${DEBIAN_IMAGE:-debian:bookworm-slim}"
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
	echo "error: docker daemon not reachable - start Docker and retry" >&2
	exit 1
fi

echo ">> building live image with ${DEBIAN_IMAGE} (live-build)"
# live-build needs real mounts/loop devices, so the container is privileged.
docker run --rm --privileged \
	--platform "$TARGET_PLATFORM" \
	-v "$repo_root":/work \
	"$DEBIAN_IMAGE" /bin/sh -eu /work/image/live/in-container-live.sh

echo ">> done"
ls -lh "$repo_root/dist/sfp-unlocker.iso" "$repo_root/dist/pxe" 2>/dev/null || true
