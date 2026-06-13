# sfp-unlocker

Unlock non-Intel SFP/SFP+ modules on Intel ixgbe cards (X520/82599, X540, X550).

Intel's ixgbe driver refuses modules it doesn't recognise and logs `unsupported SFP
module`. The card carries a single EEPROM bit that says "allow any SFP". This tool
flips that bit safely: it backs up first, refuses cards it doesn't know, shows you
exactly what it will change, and reads back to confirm the write.

It's one POSIX shell script with no dependencies beyond `ethtool`. Run it straight
on the installed OS (Proxmox/Debian), or boot the live ISO / PXE image over iLO or
iDRAC virtual media when you'd rather not touch the host OS.

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

- **iLO / iDRAC virtual media:** boot the live ISO, it shows your cards and the command
  to type. See [docs/runbook.md](docs/runbook.md).
- **PXE / netboot.xyz:** `mise run build-pxe` produces kernel + initramfs + apkovl + an
  iPXE script. See the runbook.
- **SystemRescue / Alpine:** any live Linux with `ethtool` works - copy `bin/sfp-unlock`
  across and run it.

## i40e / X710 is not supported on purpose

X710/XL710 lock SFPs in firmware (NVM), not in a single EEPROM bit. The offsets vary by
NVM version, there's no checksum safety net, and getting it wrong is a real brick. This
tool refuses them. If you need it, use the dedicated
[xl710-unlocker](https://github.com/Nevinskas/xl710-unlocker) and read it carefully.

## Development

The toolchain is pinned with [mise](https://mise.jdx.dev):

```sh
mise install        # shellcheck, shfmt, bats, lefthook
mise run hooks      # install the git pre-commit hooks (lefthook)
mise run lint       # shellcheck + shfmt
mise run test       # bats - no hardware needed
mise run build      # build the live ISO (needs Docker)
mise run build-pxe  # build the PXE artefacts (needs Docker)
```

CI (GitHub Actions) runs lint, tests, the pre-commit hooks, and the ISO build on every push.

## Credits and references

Builds on the work documented by the community:
[cubesky/unlock_x520_sfp](https://github.com/cubesky/unlock_x520_sfp),
the [ixs gist](https://gist.github.com/ixs/dbaac42730dea9bd124f26cbd439c58e), the
[ServeTheHome thread](https://forums.servethehome.com/index.php?threads/patching-intel-x520-eeprom-to-unlock-all-sfp-transceivers.24634/),
and the Linux kernel ixgbe driver.

## Licence

MIT. No warranty. Flashing NIC firmware can damage hardware - you run this at your own risk.
