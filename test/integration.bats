#!/usr/bin/env bats
# End-to-end flow against a fake sysfs and a stubbed ethtool. No real hardware.

load helpers

setup() {
	PROG_PATH="${BATS_TEST_DIRNAME}/../bin/sfp-unlock"
	FAKE_SYS="$BATS_TEST_TMPDIR/sys"
	mkdir -p "$FAKE_SYS"
	make_stubs "$BATS_TEST_TMPDIR"
	export SFP_SYSFS_NET="$FAKE_SYS"
	export SFP_STATE="$BATS_TEST_TMPDIR/eeprom-byte"
	export SFP_WRITELOG="$BATS_TEST_TMPDIR/writelog"
	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
	export NO_COLOR=1
	echo fc >"$SFP_STATE" # start locked
}

run_tool() { run "$PROG_PATH" "$@"; }

@test "dry-run on a locked X520 shows the change and writes nothing" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x10fb ixgbe
	run_tool eth9
	[ "$status" -eq 0 ]
	[[ "$output" == *"0xfc -> 0xfd"* ]]
	[[ "$output" == *"dry-run"* ]]
	[ "$(cat "$SFP_STATE")" = "fc" ] # unchanged
}

@test "--commit --yes backs up, writes, and verifies" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x10fb ixgbe
	run_tool eth9 --commit --yes --backup-dir "$BATS_TEST_TMPDIR"
	[ "$status" -eq 0 ]
	[[ "$output" == *"verified"* ]]
	[ "$(cat "$SFP_STATE")" = "fd" ] # bit 0 now set
	ls "$BATS_TEST_TMPDIR"/eeprom-eth9-*.bin >/dev/null
}

@test "the write uses the right offset, magic, value and length" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x10fb ixgbe
	run_tool eth9 --commit --yes --backup-dir "$BATS_TEST_TMPDIR"
	[ "$status" -eq 0 ]
	line=$(cat "$SFP_WRITELOG")
	[[ "$line" == *"offset 0x58"* ]]
	[[ "$line" == *"length 1"* ]]
	[[ "$line" == *"magic 0x10fb8086"* ]] # deviceID<<16 | vendorID
	[[ "$line" == *"value 0xfd"* ]]       # fc | 0x01
}

@test "magic tracks the card model (Dell X520 0x154d)" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x154d ixgbe
	run_tool eth9 --commit --yes --backup-dir "$BATS_TEST_TMPDIR"
	[[ "$(cat "$SFP_WRITELOG")" == *"magic 0x154d8086"* ]]
}

@test "verify failure is detected and points at the backup" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x10fb ixgbe
	export SFP_STUB_IGNORE_WRITE=1
	run_tool eth9 --commit --yes --backup-dir "$BATS_TEST_TMPDIR"
	unset SFP_STUB_IGNORE_WRITE
	[ "$status" -ne 0 ]
	[[ "$output" == *"verify failed"* ]]
	[[ "$output" == *"--restore"* ]]
}

@test "commit works from a read-only cwd (auto-falls-back, not fatal)" {
	# Reproduces the dash 'special builtin redirection is fatal' bug on a
	# read-only mount: with no --backup-dir and a read-only PWD it must fall
	# back to a writable dir, not abort.
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x10fb ixgbe
	ro="$BATS_TEST_TMPDIR/ro"
	mkdir -p "$ro"
	chmod 555 "$ro"
	cd "$ro"
	run "$PROG_PATH" eth9 --commit --yes
	chmod 755 "$ro"
	[ "$status" -eq 0 ]
	[[ "$output" == *"verified"* ]]
	bk=$(printf '%s\n' "$output" | sed -n 's/^backup: \(.*\) (.*/\1/p' | head -1)
	[ -n "$bk" ] && rm -f "$bk" "$bk.meta"
}

@test "an unwritable --backup-dir is refused" {
	[ "$(/usr/bin/id -u)" = 0 ] && skip "root bypasses directory permissions"
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x10fb ixgbe
	ro="$BATS_TEST_TMPDIR/robd"
	mkdir -p "$ro"
	chmod 555 "$ro"
	run_tool eth9 --commit --yes --backup-dir "$ro"
	chmod 755 "$ro"
	[ "$status" -ne 0 ]
	[[ "$output" == *"not writable"* ]]
}

@test "second --commit is idempotent (already unlocked)" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x10fb ixgbe
	echo fd >"$SFP_STATE"
	run_tool eth9 --commit --yes
	[ "$status" -eq 0 ]
	[[ "$output" == *"already unlocked"* ]]
}

@test "igb card reports no lock and exits 0 without writing" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x1521 igb
	run_tool eth9 --commit --yes
	[ "$status" -eq 0 ]
	[[ "$output" == *"nothing to do"* ]]
	[ "$(cat "$SFP_STATE")" = "fc" ]
}

@test "i40e card is refused (exit 3)" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x1572 i40e
	run_tool eth9 --commit --yes
	[ "$status" -eq 3 ]
	[[ "$output" == *"xl710-unlocker"* ]]
}

@test "unlisted ixgbe id is refused without --force-unknown" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0xdead ixgbe
	run_tool eth9
	[ "$status" -eq 3 ]
}

@test "unlisted ixgbe id proceeds (dry-run) with --force-unknown" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0xdead ixgbe
	run_tool eth9 --force-unknown
	[ "$status" -eq 0 ]
	[[ "$output" == *"0xfc -> 0xfd"* ]]
}

@test "--list shows the card and its locked status" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x10fb ixgbe
	run_tool --list
	[ "$status" -eq 0 ]
	[[ "$output" == *eth9* ]]
	[[ "$output" == *"locked (0xfc)"* ]]
}

@test "no such interface fails clearly" {
	run_tool eth404
	[ "$status" -ne 0 ]
	[[ "$output" == *"no such interface"* ]]
}

@test "prefers a sibling ethtool (self-contained image behaviour)" {
	tools="$BATS_TEST_TMPDIR/tools"
	mkdir -p "$tools"
	cp "$PROG_PATH" "$tools/sfp-unlock"
	# A sibling ethtool that drops a marker so we can prove it was used in
	# preference to the one on PATH.
	{
		echo '#!/bin/sh'
		echo "echo used-sibling >'$BATS_TEST_TMPDIR/marker'"
		echo 'printf "Offset\t\tValues\n0x0058:\t\tfc\n"'
	} >"$tools/ethtool"
	chmod +x "$tools/ethtool"
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x10fb ixgbe
	run "$tools/sfp-unlock" eth9
	[ "$status" -eq 0 ]
	[ -f "$BATS_TEST_TMPDIR/marker" ]
	[[ "$output" == *"0xfc -> 0xfd"* ]]
}

@test "restore accepts a backup this tool produced (size + identity match)" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x10fb ixgbe
	run_tool eth9 --commit --yes --backup-dir "$BATS_TEST_TMPDIR"
	[ "$status" -eq 0 ]
	backup=$(ls "$BATS_TEST_TMPDIR"/eeprom-eth9-*.bin | head -1)
	[ -r "$backup.meta" ] # sidecar written
	run_tool eth9 --restore "$backup" --yes --backup-dir "$BATS_TEST_TMPDIR"
	[ "$status" -eq 0 ]
	[[ "$output" == *restored* ]]
}

@test "restore refuses a truncated/wrong-size dump" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x10fb ixgbe
	short="$BATS_TEST_TMPDIR/short.bin"
	printf 'abcd' >"$short" # varied but far too short
	run_tool eth9 --restore "$short" --yes --backup-dir "$BATS_TEST_TMPDIR"
	[ "$status" -ne 0 ]
	[[ "$output" == *"bytes but"* ]]
}

@test "restore refuses a dump from a different card (metadata mismatch)" {
	make_fake_nic "$FAKE_SYS" eth9 0x8086 0x10fb ixgbe
	foreign="$BATS_TEST_TMPDIR/foreign.bin"
	make_varied_dump "$foreign"
	printf 'device=0xbeef\n' >"$foreign.meta"
	run_tool eth9 --restore "$foreign" --yes --backup-dir "$BATS_TEST_TMPDIR"
	[ "$status" -ne 0 ]
	[[ "$output" == *"wrong card"* ]]
}
