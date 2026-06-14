#!/bin/sh
# Build the mini, NON-bootable tools image: a small FAT filesystem holding just
# sfp-unlock and a statically-linked ethtool. Attach it via iLO/iDRAC virtual
# media (or mount -o loop on the host), then run ./sfp-unlock - no reboot, no deps.
#
# Usage: image/build-img.sh [OUTPUT_IMG]   (default: dist/sfp-unlocker-tools.img)

set -eu

ALPINE_VERSION="${ALPINE_VERSION:-3.21}"
ALPINE_IMAGE="${ALPINE_IMAGE:-alpine:${ALPINE_VERSION}}"
# Static ethtool is x86_64 (these NICs live in x86_64 servers). Build under amd64.
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"
ETHTOOL_VERSION="${ETHTOOL_VERSION:-6.11}"

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
out=${1:-dist/sfp-unlocker-tools.img}
case "$out" in
/*) out_abs=$out ;;
*) out_abs="$repo_root/$out" ;;
esac
mkdir -p "$(dirname -- "$out_abs")"

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
	echo "error: docker daemon not reachable - start Docker and retry" >&2
	exit 1
fi

echo ">> building mini tools image (static ethtool $ETHTOOL_VERSION)"

docker run --rm \
	--platform "$TARGET_PLATFORM" \
	-e OUT_NAME="$(basename -- "$out_abs")" \
	-e ETHTOOL_VERSION="$ETHTOOL_VERSION" \
	-v "$repo_root":/work \
	"$ALPINE_IMAGE" /bin/sh -eu /work/image/in-container-img.sh

echo ">> done: $out_abs"
ls -lh "$out_abs"
