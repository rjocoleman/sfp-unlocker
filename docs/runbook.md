# Runbook

Six ways to run the unlock, from least to most setup. Pick one. All of them end the
same way: a dry-run, then `--commit`, then a **cold power-cycle**.

Before you start:

- Know which interface is the card you want (`sfp-unlock --list`).
- `--commit` writes a full EEPROM backup to the current directory (or `/tmp`). Keep it.
- A warm reboot does not apply the change. The host must go fully off and back on.

---

## 1. Proxmox / Debian, straight on the host

This is the simplest path and the one most people want.

```sh
apt-get install -y ethtool
./bin/sfp-unlock --list
./bin/sfp-unlock enp1s0f0            # dry-run
./bin/sfp-unlock enp1s0f0 --commit   # backup -> confirm -> write -> verify
```

Then power-cycle the host. After it's back:

```sh
ethtool -e enp1s0f0 offset 0x58 length 1   # bit 0 should be set, e.g. 0xfd
dmesg | grep -i sfp                        # should no longer say "unsupported"
```

Proxmox note: if the NIC is in a bridge (`vmbr0`) the underlying interface is still the
one you target (e.g. `enp1s0f0`), not the bridge.

---

## 2. HP iLO virtual media

1. iLO web UI -> Remote Console -> Virtual Media. Mount `dist/sfp-unlocker.iso` as a
   virtual CD/DVD (HTML5 console on iLO5, Java applet on older iLO4).
2. Boot the server and pick the virtual CD from the one-time boot menu (F11), or set it
   in BIOS. Connect the virtual media **before** power-on.
3. The image boots to a console, prints your Intel NICs and their lock status, and shows
   the exact command. Log in as `root` (no password).
4. Run `sfp-unlock <iface> --commit`, then cold power-cycle.

Tips:

- If the host is set to UEFI with Secure Boot, turn Secure Boot off for this maintenance
  window (the Alpine ISO is not signed), or use SystemRescue (section 4) which is signed.
- iLO virtual media can be flaky: connect it before reset, and if it doesn't appear,
  unmount and remount once. The image runs from RAM, so a dropped media link mid-session
  won't kill it once booted.

---

## 3. Dell iDRAC virtual media

1. iDRAC -> Configuration -> Virtual Media (or the Virtual Console "Connect Virtual
   Media"). Map `dist/sfp-unlocker.iso`.
2. Boot menu (F11) -> Virtual Optical Drive. Or set it as a one-time boot device in
   iDRAC -> Server -> Setup -> First Boot Device -> Virtual CD/DVD.
3. Same as above: it shows the cards, log in as `root`, run `sfp-unlock <iface> --commit`,
   cold power-cycle.

iDRAC9 usually boots UEFI with Secure Boot on. Disable Secure Boot for the maintenance
window, or use SystemRescue.

---

## 4. SystemRescue or plain Alpine (no custom image)

Any live Linux with `ethtool` works. SystemRescue already has `ethtool` and is
Secure-Boot signed, which makes it the easy choice over a BMC.

1. Boot SystemRescue (or Alpine: then `apk add ethtool`).
2. Copy the script across (USB, scp, or paste it).
3. `./sfp-unlock <iface> --commit`, then cold power-cycle.

---

## 5. Build and use the bootable ISO

```sh
mise run build          # writes dist/sfp-unlocker.iso (needs Docker)
```

The ISO is a minimal Alpine live image with `ethtool`, `pciutils` and `sfp-unlock`
baked in. It is hybrid BIOS + UEFI so it boots both old (iLO4/iDRAC7-8, legacy BIOS)
and new (iLO5/iDRAC9, UEFI) servers. It mirrors its console to serial (`ttyS0`,
115200) so BMC text consoles work. It never flashes anything on its own - it only shows
status and waits for you.

On Apple Silicon the build runs under amd64 emulation (slow but works). On x86_64 (CI,
most Linux boxes) it's native and quick.

---

## 6. PXE / netboot.xyz

```sh
mise run build          # ISO first
mise run build-pxe      # writes dist/pxe/{vmlinuz-lts,initramfs-lts,modloop-lts,*.apkovl.tar.gz,sfp.ipxe}
```

1. Serve `dist/pxe/` over HTTP from somewhere your servers can reach.
2. Edit `dist/pxe/sfp.ipxe` and set `base` to that URL.
3. Chain it from iPXE directly, or add the netboot.xyz entry: copy
   `image/netboot/netboot.xyz-custom.ipxe` into your netboot.xyz custom menu and point
   `sfp_base` at the same URL.

From the netboot.xyz menu, pick "SFP unlocker (Intel ixgbe)". It boots the same live
environment as the ISO.

---

## After any method

```sh
sfp-unlock --list        # the card should now read "unlocked"
```

If something went wrong, see [recovery.md](recovery.md).
