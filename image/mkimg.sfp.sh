#!/bin/sh
# Alpine mkimage profile for the SFP unlocker live ISO.
# Used by aports scripts/mkimage.sh:  mkimage.sh --profile sfp ...
# Produces a hybrid BIOS+UEFI ISO (boots legacy iLO4/iDRAC7-8 and UEFI iLO5/iDRAC9).
#
# These variables are consumed by the mkimage framework that sources this file,
# so shellcheck can't see their use.
# shellcheck disable=SC2034

profile_sfp() {
	profile_standard
	title="SFP unlocker"
	desc="Unlock non-Intel SFP modules on Intel ixgbe NICs"
	profile_abbrev="sfp"
	image_ext="iso"
	arch="x86_64"
	output_format="iso"
	# Mirror output to the serial console so BMC text consoles (iLO/iDRAC) work.
	kernel_cmdline="unionfs console=tty0 console=ttyS0,115200"
	syslinux_serial="0 115200"
	apks="$apks ethtool pciutils"
	apkovl="genapkovl-sfp.sh"
}
