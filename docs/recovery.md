# Recovery

What can go wrong, and how to get back. The short version: you took a backup, so you
can put it back.

## What "bricked" actually means here

For the ixgbe cards this tool writes to, a bad EEPROM almost always shows up as the
driver refusing to bring the card up (`probe failed`, `EEPROM checksum is not valid`),
not as dead silicon. It's recoverable. The two things that genuinely kill a card are
overwriting the MAC/PCI identity region or a botched firmware (NVM) flash - this tool
touches neither. It changes one byte at offset `0x58` and lets the driver recompute the
checksum.

## Restore from the backup this tool made

Every `--commit` writes a full EEPROM dump first and prints its path, e.g.:

```
backup: ./eeprom-enp1s0f0-90-e2-ba-xx-xx-xx-20260614T1030Z.bin
sha256: 4f3a...
```

To put it back:

```sh
sfp-unlock enp1s0f0 --restore ./eeprom-enp1s0f0-90-e2-ba-xx-xx-xx-20260614T1030Z.bin
```

Before writing, `--restore` checks the dump's sidecar `.meta` came from this card
(refuses a different device), snapshots the current EEPROM first so the restore is
itself reversible, and refuses a dump whose size doesn't match the card's EEPROM (so a
truncated file can't half-overwrite the MAC/config region). Then it asks you to confirm
and writes it back via `ethtool -E ... magic <derived>`. Cold power-cycle afterwards.

If you'd rather use ethtool directly:

```sh
# magic is deviceID<<16 | vendorID, e.g. 0x10fb8086 for an 82599
ethtool -E enp1s0f0 magic 0x10fb8086 < eeprom-...-.bin
```

Caveat: on some Intel cards an ethtool dump can be shorter than the real EEPROM. The
tool checks the dump isn't empty or all-identical before trusting it; if a restore
won't take, fall through to the Intel tools below.

## The card won't probe at all

If the NIC has dropped off the PCI bus or the driver refuses it so hard that `ethtool`
can't see it:

1. Try another machine. The same `--restore` from any Linux box with the card installed
   usually works.
2. Intel's own tools, when ethtool can't help:
   - `nvmupdate64e` from the Intel Ethernet NVM Update Package for your adapter family -
     reflashes known-good firmware.
   - `eeupdate` / `eeupdate64e` - Intel's low-level EEPROM editor (DOS/EFI, distributed
     through OEM channels). The classic fix for a bad checksum when the card won't come
     up under Linux.

   See the Intel Ethernet NVM Update Tool docs:
   <https://edc.intel.com/content/www/us/en/design/products/ethernet/adapters-and-devices-user-guide/intel-ethernet-nvm-update-tool/>

## Prevention checklist

- Keep the backup `.bin` files. Label them by host and card.
- Do the dry-run first and read the `0x<old> -> 0x<new>` line. It should only flip bit 0.
- If the tool refuses your card, don't reach for `--force-unknown` unless you're sure the
  card is ixgbe and you understand the risk.
