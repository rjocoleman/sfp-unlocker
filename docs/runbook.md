# Runbook

Seven ways to run the unlock, from least to most setup. Pick one. All of them end the
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

## 2. Mini tools image (attach + mount, no reboot)

The lightest path that needs no reboot and nothing installed on the host. Build it once:

```sh
mise run build-img      # writes dist/sfp-unlocker-tools.img (needs Docker)
```

It is a small FAT image holding just `sfp-unlock` and a static `ethtool`. Attach it to
the running host and mount it:

- **iLO/iDRAC:** map `sfp-unlocker-tools.img` as virtual USB/removable media.
- **Proxmox / any Linux:** `mount -o loop,ro sfp-unlocker-tools.img /mnt` (or the device,
  e.g. `/dev/sdb`).

Then run it against the live OS:

```sh
sh /mnt/sfp-unlock --list
sh /mnt/sfp-unlock <iface>                               # dry-run
sh /mnt/sfp-unlock <iface> --commit --backup-dir /root   # image is read-only, write the backup elsewhere
```

Invoke via `sh /mnt/sfp-unlock` - FAT has no execute bit. The script uses the
`ethtool` next to it, so the host needs no packages. Cold power-cycle after a
write. x86_64 only.

---

## 3. HP iLO virtual media

1. iLO web UI -> Remote Console -> Virtual Media. Mount `dist/sfp-unlocker.iso` as a
   virtual CD/DVD (HTML5 console on iLO5, Java applet on older iLO4).
2. Boot the server and pick the virtual CD from the one-time boot menu (F11), or set it
   in BIOS. Connect the virtual media **before** power-on.
3. The image boots to a console, prints your Intel NICs and their lock status, and shows
   the exact command. Log in as `root` (no password).
4. Run `sfp-unlock <iface> --commit`, then cold power-cycle.

Tips:

- If the host is set to UEFI with Secure Boot, turn Secure Boot off for this maintenance
  window (the Alpine ISO is not signed), or use SystemRescue (section 5) which is signed.
- iLO virtual media can be flaky: connect it before reset, and if it doesn't appear,
  unmount and remount once. The image runs from RAM, so a dropped media link mid-session
  won't kill it once booted.

---

## 4. Dell iDRAC virtual media

1. iDRAC -> Configuration -> Virtual Media (or the Virtual Console "Connect Virtual
   Media"). Map `dist/sfp-unlocker.iso`.
2. Boot menu (F11) -> Virtual Optical Drive. Or set it as a one-time boot device in
   iDRAC -> Server -> Setup -> First Boot Device -> Virtual CD/DVD.
3. Same as above: it shows the cards, log in as `root`, run `sfp-unlock <iface> --commit`,
   cold power-cycle.

iDRAC9 usually boots UEFI with Secure Boot on. Disable Secure Boot for the maintenance
window, or use SystemRescue.

---

## 5. SystemRescue or plain Alpine (no custom image)

Any live Linux with `ethtool` works. SystemRescue already has `ethtool` and is
Secure-Boot signed, which makes it the easy choice over a BMC.

1. Boot SystemRescue (or Alpine: then `apk add ethtool`).
2. Copy the script across (USB, scp, or paste it).
3. `./sfp-unlock <iface> --commit`, then cold power-cycle.

---

## 6. Build and use the bootable ISO

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

## 7. PXE / netboot.xyz

```sh
mise run build          # ISO first
mise run build-pxe      # writes dist/pxe/{vmlinuz-lts,initramfs-lts,modloop-lts,*.apkovl.tar.gz,sfp.ipxe}
```

The generated `sfp.ipxe` defaults `base` to the GitHub release download URL
(`https://github.com/rjocoleman/sfp-unlocker/releases/latest/download`), so once a
release exists you can point iPXE straight at it - no hosting needed.

1. To self-host instead, serve `dist/pxe/` over HTTP and set `base` in `sfp.ipxe` to that
   URL.
2. Chain it from iPXE directly, or add the netboot.xyz entry: copy
   `image/netboot/netboot.xyz-custom.ipxe` into your netboot.xyz custom menu (it points
   `sfp_base` at the release by default).

From the netboot.xyz menu, pick "SFP unlocker (Intel ixgbe)". It boots the same live
environment as the ISO.

---

## Unattended / scripted

For config management or a one-shot remote run, skip the prompt with `--yes`. The
default (no `--commit`) is a read-only dry-run, so it is always safe to probe first.

```sh
sfp-unlock --list                                   # detect, read-only
sfp-unlock eth0                                      # dry-run, read-only
sfp-unlock eth0 --commit --yes --backup-dir /root   # backup + write + verify, no prompt
sfp-unlock eth0 --restore /root/eeprom-eth0-*.bin --yes   # revert
```

Gate on exit codes: `0` ok or no-op (already unlocked, or igb has no lock), `1` error,
`2` usage, `3` unsupported/unrecognised card. Example:

```sh
if sfp-unlock "$IFACE" --commit --yes --backup-dir /root; then
  echo "unlocked (reboot pending)"
else
  rc=$?; echo "sfp-unlock failed rc=$rc"; exit "$rc"
fi
```

## After any method

```sh
sfp-unlock --list        # the card should now read "unlocked"
```

If something went wrong, see [recovery.md](recovery.md).
