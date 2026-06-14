#!/usr/bin/env bats

load helpers

setup() {
	setup_script
}

# --- compute_magic -------------------------------------------------------

@test "compute_magic builds deviceID<<16 | vendorID for 82599" {
	run compute_magic 0x8086 0x10fb
	[ "$status" -eq 0 ]
	[ "$output" = "0x10fb8086" ]
}

@test "compute_magic for Dell X520 variant 0x154d" {
	run compute_magic 0x8086 0x154d
	[ "$output" = "0x154d8086" ]
}

# --- parse_byte ----------------------------------------------------------

@test "parse_byte extracts the data byte from ethtool -e output" {
	out=$(printf 'Offset\t\tValues\n------\t\t------\n0x0058:\t\tfc\n' | parse_byte)
	[ "$out" = "fc" ]
}

@test "parse_byte lowercases and takes the first byte" {
	out=$(printf '0x0058:   FD AA BB\n' | parse_byte)
	[ "$out" = "fd" ]
}

# --- desired_value (read-modify-write, never hardcoded) ------------------

@test "desired_value sets bit 0: fc -> fd" {
	run desired_value fc
	[ "$output" = "fd" ]
}

@test "desired_value on 00 -> 01" {
	run desired_value 00
	[ "$output" = "01" ]
}

@test "desired_value is a no-op when already set: fd -> fd" {
	run desired_value fd
	[ "$output" = "fd" ]
}

# --- is_unlocked ---------------------------------------------------------

@test "is_unlocked true when bit 0 set" {
	run is_unlocked fd
	[ "$status" -eq 0 ]
}

@test "is_unlocked false when bit 0 clear" {
	run is_unlocked fc
	[ "$status" -ne 0 ]
}

# --- classify_card -------------------------------------------------------

@test "classify_card accepts a listed ixgbe id (82599)" {
	run classify_card ixgbe 0x8086 0x10fb
	[ "$status" -eq 0 ]
	[[ "$output" == *supported* ]]
}

@test "classify_card accepts X550 id 0x1563" {
	run classify_card ixgbe 0x8086 0x1563
	[ "$status" -eq 0 ]
}

@test "classify_card refuses an unlisted ixgbe id by default" {
	run classify_card ixgbe 0x8086 0xdead
	[ "$status" -eq 3 ]
	[[ "$output" == *force-unknown* ]]
}

@test "classify_card allows unlisted ixgbe id with --force-unknown" {
	run classify_card ixgbe 0x8086 0xdead --force-unknown
	[ "$status" -eq 0 ]
	[[ "$output" == *forced* ]]
}

@test "classify_card reports igb as no-lock (rc 4)" {
	run classify_card igb 0x8086 0x1521
	[ "$status" -eq 4 ]
	[[ "$output" == *"no SFP lock"* ]]
}

@test "classify_card refuses i40e (rc 3, points to xl710-unlocker)" {
	run classify_card i40e 0x8086 0x1572
	[ "$status" -eq 3 ]
	[[ "$output" == *xl710-unlocker* ]]
}

@test "classify_card refuses non-Intel vendor" {
	run classify_card ixgbe 0x15b3 0x1015
	[ "$status" -eq 3 ]
	[[ "$output" == *non-Intel* ]]
}

# --- validate_dump -------------------------------------------------------

@test "validate_dump accepts a varied dump" {
	f="$BATS_TEST_TMPDIR/varied.bin"
	make_varied_dump "$f"
	run validate_dump "$f"
	[ "$status" -eq 0 ]
}

@test "validate_dump rejects an empty dump" {
	f="$BATS_TEST_TMPDIR/empty.bin"
	: >"$f"
	run validate_dump "$f"
	[ "$status" -ne 0 ]
}

@test "validate_dump rejects an all-identical dump" {
	f="$BATS_TEST_TMPDIR/allff.bin"
	make_allff_dump "$f"
	run validate_dump "$f"
	[ "$status" -ne 0 ]
}

# --- CLI surface ---------------------------------------------------------

@test "no args prints usage and exits 2" {
	run "$PROG_PATH"
	[ "$status" -eq 2 ]
	[[ "$output" == *Usage:* ]]
}

@test "--version prints the version" {
	run "$PROG_PATH" --version
	[ "$status" -eq 0 ]
	[[ "$output" == *"sfp-unlock "* ]]
}

@test "--help exits 0" {
	run "$PROG_PATH" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"unlock non-Intel SFP"* ]]
}

@test "unknown option exits 1" {
	run "$PROG_PATH" --bogus
	[ "$status" -eq 1 ]
}

@test "--list runs without a NIC and reports none" {
	run "$PROG_PATH" --list
	[ "$status" -eq 0 ]
}
