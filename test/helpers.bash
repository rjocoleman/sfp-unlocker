# shellcheck shell=bash
# shared bats helpers

setup_script() {
	PROG_PATH="${BATS_TEST_DIRNAME}/../bin/sfp-unlock"
	# Source the tool without running main(); then relax the strict flags it sets
	# so they don't interfere with bats internals.
	# shellcheck disable=SC1090
	SFP_UNLOCK_SOURCED=1 . "$PROG_PATH"
	set +e +u
}

# Write a small EEPROM-like dump with varied bytes.
make_varied_dump() {
	printf 'The quick brown fox jumps 0123456789ABCDEF' >"$1"
}

# Write a dump that is all the same byte (0xff) - should be rejected.
make_allff_dump() {
	i=0
	: >"$1"
	while [ "$i" -lt 32 ]; do
		printf '\377' >>"$1"
		i=$((i + 1))
	done
}

# Build a fake sysfs NIC under $1 (root) for interface $2.
#   make_fake_nic ROOT IFACE VENDOR DEVICE DRIVER
make_fake_nic() {
	root=$1
	iface=$2
	vendor=$3
	device=$4
	driver=$5
	dev="$root/$iface/device"
	mkdir -p "$dev"
	printf '%s\n' "$vendor" >"$dev/vendor"
	printf '%s\n' "$device" >"$dev/device"
	printf '90:e2:ba:00:11:22\n' >"$root/$iface/address"
	ln -sf "/sys/bus/pci/drivers/$driver" "$dev/driver"
}

# Create stub `ethtool` and `id` in $1/bin. The stub keeps the current EEPROM byte
# in the file named by $SFP_STATE so reads/writes persist across invocations.
make_stubs() {
	bindir="$1/bin"
	mkdir -p "$bindir"

	cat >"$bindir/ethtool" <<'STUB'
#!/bin/sh
state="${SFP_STATE:?SFP_STATE unset}"
op=$1
shift
iface=$1
shift
case "$op" in
-e)
	if [ "${1:-}" = raw ]; then
		# A varied "backup" blob (validate_dump rejects empty/all-identical).
		printf 'EEPROM-BACKUP-%s-0123456789abcdef-end' "$iface"
		exit 0
	fi
	b=$(cat "$state" 2>/dev/null || echo fc)
	printf 'Offset\t\tValues\n0x0058:\t\t%s\n' "$b"
	;;
-E)
	v=
	while [ $# -gt 0 ]; do
		[ "$1" = value ] && v=$2
		shift
	done
	v=${v#0x}
	printf '%s' "$v" >"$state"
	;;
esac
STUB
	chmod +x "$bindir/ethtool"

	cat >"$bindir/id" <<'STUB'
#!/bin/sh
[ "$1" = -u ] && { echo 0; exit 0; }
exec /usr/bin/id "$@"
STUB
	chmod +x "$bindir/id"
}
