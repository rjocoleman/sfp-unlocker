# Shown once on the auto-login console. Lists detected cards and the command to
# run - it never flashes anything by itself.
cat <<'BANNER'

  ============================================================
   SFP unlocker live image
  ============================================================
  Detected Intel NICs and their SFP lock status:

BANNER

sfp-unlock --list 2>&1 || true

cat <<'HELP'

  To unlock a card (example, interface eth0):

    sfp-unlock eth0            # dry-run, shows what would change
    sfp-unlock eth0 --commit   # backs up, then writes after you confirm

  A cold power-cycle is required after a successful write.
  See: sfp-unlock --help
  ============================================================

HELP
