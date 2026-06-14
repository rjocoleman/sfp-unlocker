#!/bin/sh
# Runs INSIDE the Alpine build container (invoked by build-iso.sh).
# Builds the live ISO with Alpine's mkimage and copies it to /work/dist.

set -eu

ALPINE_VERSION="${ALPINE_VERSION:-3.21}"
OUT_NAME="${OUT_NAME:-sfp-unlocker.iso}"
BRANCH="v${ALPINE_VERSION}"           # apk repository branch (e.g. v3.21)
GIT_BRANCH="${ALPINE_VERSION}-stable" # aports git branch (e.g. 3.21-stable)
MIRROR="https://dl-cdn.alpinelinux.org/alpine"

echo ">> installing build dependencies"
# grub-bios (BIOS/i386-pc platform) lives in the community repo.
if ! grep -q "$BRANCH/community" /etc/apk/repositories 2>/dev/null; then
	echo "$MIRROR/$BRANCH/community" >>/etc/apk/repositories
fi
apk update >/dev/null
apk add --no-cache \
	alpine-sdk alpine-conf busybox \
	xorriso squashfs-tools \
	grub grub-bios grub-efi mtools dosfstools \
	git doas >/dev/null

# mkimage refuses to run as root; use an unprivileged build user.
if ! id build >/dev/null 2>&1; then
	adduser -D build
	addgroup build abuild
fi
echo 'permit nopass build' >/etc/doas.d/build.conf

work_src=/work
build_home=/home/build

echo ">> generating signing key and fetching aports ($GIT_BRANCH)"
su build -s /bin/sh -c "
  set -eu
  cd '$build_home'
  abuild-keygen -an >/dev/null 2>&1
  rm -rf aports
  git clone --depth=1 -b '$GIT_BRANCH' https://gitlab.alpinelinux.org/alpine/aports.git
  cp '$work_src/image/mkimg.sfp.sh' aports/scripts/
  cp '$work_src/image/genapkovl-sfp.sh' aports/scripts/
  chmod +x aports/scripts/genapkovl-sfp.sh
"

echo ">> running mkimage"
mkdir -p "$work_src/dist"
su build -s /bin/sh -c "
  set -eu
  cd '$build_home/aports/scripts'
  export SFP_BIN='$work_src/bin/sfp-unlock'
  export SFP_LOCALD='$work_src/image/overlay/etc/local.d/sfp.start'
  sh mkimage.sh \
    --tag '$ALPINE_VERSION' \
    --outdir '$build_home/out' \
    --arch x86_64 \
    --repository '$MIRROR/$BRANCH/main' \
    --repository '$MIRROR/$BRANCH/community' \
    --profile sfp
"

iso=$(find "$build_home/out" -name '*.iso' | head -n1)
[ -n "$iso" ] || {
	echo "error: mkimage produced no ISO" >&2
	exit 1
}
cp "$iso" "$work_src/dist/$OUT_NAME"
echo ">> copied $(basename "$iso") -> dist/$OUT_NAME"
