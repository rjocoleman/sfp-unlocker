#!/bin/sh
# Build the SFP unlocker live ISO inside an Alpine Docker container.
# Usage: image/build-iso.sh [OUTPUT_ISO]   (default: dist/sfp-unlocker.iso)
#
# The build runs in a pinned Alpine container so it is identical on macOS and CI.
# The EEPROM tooling itself only ever runs on the target hardware, never here.

set -eu

ALPINE_VERSION="${ALPINE_VERSION:-3.21}"
ALPINE_IMAGE="${ALPINE_IMAGE:-alpine:${ALPINE_VERSION}}"
# The ISO targets x86_64 servers. On an arm64 host (Apple Silicon) Docker emulates
# this, which works but is slow; native amd64 (CI) is fast.
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
out=${1:-dist/sfp-unlocker.iso}
case "$out" in
/*) out_abs=$out ;;
*) out_abs="$repo_root/$out" ;;
esac
mkdir -p "$(dirname -- "$out_abs")"

command -v docker >/dev/null 2>&1 || {
	echo "error: docker not found - the ISO build needs Docker (or run in CI)" >&2
	exit 1
}
docker info >/dev/null 2>&1 || {
	echo "error: docker daemon not reachable - start Docker and retry" >&2
	exit 1
}

echo ">> building ISO with $ALPINE_IMAGE (Alpine $ALPINE_VERSION aports)"

docker run --rm \
	--platform "$TARGET_PLATFORM" \
	-e ALPINE_VERSION="$ALPINE_VERSION" \
	-e OUT_NAME="$(basename -- "$out_abs")" \
	-v "$repo_root":/work \
	"$ALPINE_IMAGE" /bin/sh -eu /work/image/in-container-build.sh

echo ">> done: $out_abs"
ls -lh "$out_abs"
