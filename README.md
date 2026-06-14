# sfp-unlocker

Unlock non-Intel SFP/SFP+ modules on Intel ixgbe cards (X520/82599, X540, X550).

Intel's ixgbe driver refuses modules it doesn't recognise and logs `unsupported SFP
module`. The card carries a single EEPROM bit that says "allow any SFP". This tool
flips that bit safely: it backs up first, refuses cards it doesn't know, shows you
exactly what it will change, and reads back to confirm the write.

It's one POSIX shell script with no dependencies beyond `ethtool`. Run it straight
on the installed OS (e.g. Proxmox/Debian), or boot the live ISO / PXE image over iLO or
iDRAC virtual media when you'd rather not touch the host OS.

## Heads up

This writes your NIC's firmware EEPROM. Done right it's low risk, and the tool works hard
to keep it that way, but flashing hardware can always go wrong:

- You could brick the card. There's a backup and a `--restore`, but no guarantees.
- It may void your card or server vendor's warranty or support.
- **No warranty of any kind. You run this entirely at your own risk** (MIT licence).
- Not affiliated with or endorsed by Intel. "Intel", "X520", "X540" and "X550" are
  trademarks of Intel Corporation, used here only to say which cards this works on.

## Is my card supported?

| Driver | Cards | What the tool does |
|--------|-------|--------------------|
| `ixgbe` | X520/82599, X540, X550/X55x | Patches EEPROM byte `0x58` bit 0 |
| `igb` | i350, 82576, 82580 | Nothing - these have no SFP lock |
| `i40e` | X710, XL710, XXV710 | Refuses - NVM-based, real brick risk (see below) |

Check yours:

```sh
sfp-unlock --list
```

## Quick start (Proxmox / Debian)

```sh
apt-get install -y ethtool
git clone https://github.com/rjocoleman/sfp-unlocker
cd sfp-unlocker

./bin/sfp-unlock --list            # see your cards and lock status
./bin/sfp-unlock enp1s0f0          # dry-run: shows what would change, writes nothing
./bin/sfp-unlock enp1s0f0 --commit # backs up, asks you to confirm, writes, verifies
```

Then **fully power the host off and on** (a warm reboot is not enough - the driver
reads the bit at init). Your non-Intel module should now come up.

## Just the ethtool commands

If you have a single X520 and want to do it by hand, this is the whole thing:

```sh
ethtool -e enp1s0f0 offset 0x58 length 1                              # read, e.g. 0xfc
ethtool -E enp1s0f0 magic 0x10fb8086 offset 0x58 value 0xfd length 1  # set bit 0
ethtool -e enp1s0f0 offset 0x58 length 1                              # verify, 0xfd
```

There are already bash and python scripts floating around that wrap this. I wanted the
whole feature set in one place, so this does a bit more than three commands - on purpose,
not overcooked:

- works out the `magic` per card (it's `deviceID<<16 | vendorID`, so `0x10fb8086` is the
  82599 only and wrong on X540/X550)
- checks the card is one it recognises before touching it
- read-modify-write, so it only flips bit 0 and never clobbers the rest of the byte
- backs up the EEPROM first, dry-runs by default, and can `--restore`
- ships as a bootable ISO, a mini mount-and-run image, and PXE for boxes you can't run it
  on directly

If you just want the three lines, they're right there. If you want the guard rails and
the other delivery options, use the tool.

## Why it's unlikely to brick your card

- **Dry-run by default.** Writing needs `--commit`. You see the exact byte change first.
- **Mandatory backup.** Every `--commit` dumps the whole EEPROM first, checks the dump
  isn't empty or garbage, and records a sha256. Restore with `--restore FILE`.
- **It refuses what it doesn't know.** Only ixgbe cards on a built-in allow-list get
  written. igb is reported as "nothing to do". i40e is refused outright.
- **ethtool recomputes the checksum.** On ixgbe, `ethtool -E` rewrites the EEPROM
  checksum for you, which is the usual way these writes go wrong. We never hand-roll it.
- **Read-modify-verify.** It reads the current byte, ORs in bit 0 (never a hardcoded
  value), writes, then reads back and confirms before declaring success.
- **Idempotent.** Already unlocked? It says so and does nothing.

If a write ever fails, the tool prints the backup path and the exact `--restore`
command. See [docs/recovery.md](docs/recovery.md).

## Other ways to run it

- **Mini tools image (no reboot):** `dist/sfp-unlocker-tools.img` is a tiny FAT image
  holding just `sfp-unlock` and a static `ethtool`. Attach it via iLO/iDRAC virtual media
  (or `mount -o loop` on the host), then run it against the *running* OS - no reboot, and
  the host needs nothing installed. Build with `mise run build-img`.
- **iLO / iDRAC virtual media (bootable):** boot the live ISO, it shows your cards and the
  command to type. See [docs/runbook.md](docs/runbook.md).
- **PXE / netboot.xyz:** `mise run build-pxe` produces kernel + initramfs + apkovl + an
  iPXE script that pulls from the GitHub release. See the runbook.
- **SystemRescue / Alpine:** any live Linux with `ethtool` works - copy `bin/sfp-unlock`
  across and run it.

## Downloads

Tagged releases publish the artefacts on the
[releases page](https://github.com/rjocoleman/sfp-unlocker/releases): the bootable
`sfp-unlocker.iso`, the mini `sfp-unlocker-tools.img`, the PXE files (and a
`sfp-unlocker-pxe.tar.gz`), plus `SHA256SUMS`. The script itself is just
[`bin/sfp-unlock`](bin/sfp-unlock) if you only want the one file.

## Unattended / scripted use

Everything is scriptable. Dry-run (the safe default) and `--list` make no changes;
`--commit --yes` runs the whole backup → write → verify with no prompts.

```sh
sfp-unlock --list                                  # detect (read-only)
sfp-unlock eth0                                     # dry-run (read-only)
sfp-unlock eth0 --commit --yes --backup-dir /root  # unattended write + backup
sfp-unlock eth0 --restore /root/eeprom-eth0-*.bin  # revert from a backup
```

Exit codes: `0` success or no-op (already unlocked / igb has no lock), `1` error,
`2` usage, `3` unsupported or unrecognised card. Use these to gate automation.

## i40e / X710 is not supported on purpose

X710/XL710 lock SFPs in firmware (NVM), not in a single EEPROM bit. The offsets vary by
NVM version, there's no checksum safety net, and getting it wrong is a real brick. This
tool refuses them. If you need it, use the dedicated
[xl710-unlocker](https://github.com/Nevinskas/xl710-unlocker) and read it carefully.

## Development

The toolchain is pinned with [mise](https://mise.jdx.dev):

```sh
mise install        # shellcheck, shfmt, bats, lefthook, zizmor
mise run hooks      # install the git pre-commit hooks (lefthook)
mise run lint       # shellcheck + shfmt
mise run test       # bats - no hardware needed
mise run zizmor     # security-scan the GitHub Actions workflows
mise run ci         # lint + test + zizmor
mise run build      # build the live ISO       (needs Docker)
mise run build-pxe  # build the PXE artefacts  (needs Docker)
mise run build-img  # build the mini tools img (needs Docker)
```

CI (GitHub Actions) runs lint, tests, zizmor, the pre-commit hooks, and the image
builds on every push, with concurrency cancellation. Pushing a `v*` tag runs the
release workflow, which builds everything and publishes it to a GitHub release.
Workflows are SHA-pinned and zizmor-clean.

## Credits and references

Builds on the work documented by the community:
[cubesky/unlock_x520_sfp](https://github.com/cubesky/unlock_x520_sfp),
the [ixs gist](https://gist.github.com/ixs/dbaac42730dea9bd124f26cbd439c58e), the
[ServeTheHome thread](https://forums.servethehome.com/index.php?threads/patching-intel-x520-eeprom-to-unlock-all-sfp-transceivers.24634/),
and the Linux kernel ixgbe driver.

## Licence

MIT. No warranty. Flashing NIC firmware can damage hardware - you run this at your own risk.
