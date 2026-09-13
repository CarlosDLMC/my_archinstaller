# Custom firmware boot logo (any motherboard)

The very first picture at power-on is drawn by the motherboard firmware, before any
bootloader. This directory replaces it with `LOGO.JPG` so the whole boot - firmware,
Limine, Plymouth, ly - shows the same logo. It is meant to be driven by Claude on a
freshly installed machine: `detect`, look up the vendor bits below, `build`, `usb`,
then the user presses the button.

This is a firmware modification. It is recoverable on every board that has a
button-driven recovery flasher (see the vendor table), and that is the only kind of
board this should be attempted on. The script never flashes anything itself.

## The procedure

```bash
bios-logo/mod-bios-logo.sh detect                      # board, vendor, BIOS version, current logo
# 1. download the latest stock firmware for that board (vendor table below), unzip it
bios-logo/mod-bios-logo.sh build --image <stock file>  # -> ~/Downloads/bios-mod-<board>/modded/<NAME>
bios-logo/mod-bios-logo.sh usb --device /dev/sdX --file ~/Downloads/bios-mod-<board>/modded/<NAME>
# 2. the user flashes with the vendor's button procedure (table below)
```

`build` does the vendor-independent work and is safe to run as often as you like:

1. Parses the image with UEFIExtract and finds the boot-logo FFS file. On every AMI
   Aptio V board this is the EDK2 Logo file, GUID `7BB28B99-61BB-11D5-9A5D-0090273FC14D`;
   it falls back to any file named Logo/Splash/BootLogo.
2. Extracts the stored picture and reads its real format, dimensions and depth. Do not
   trust the size the firmware reports through ACPI (BGRT): that is the picture *after*
   the firmware scaled it to the screen. On the TUF B650M the stored logo is 672x378
   while BGRT says 1024x576.
3. Builds a replacement in the same container, same dimensions, same depth, logo
   centred on black at 80 % of the height. If the section is compressed (it usually is,
   LZMA), the *compressed* size must fit the volume's free space, so the picture is
   colour-reduced (128 colours by default, stepping down to 16) until it fits with 20 %
   margin. A cartoon at 128 colours is indistinguishable at boot and compresses to a
   few tens of KB; full colour from a JPEG source is 4-5x larger. If the section is
   uncompressed, same dimensions and depth give the identical byte size, which is what
   the volume expects.
4. Replaces the section with `uefireplace` (UEFITool 0.28), which recompresses and
   fixes the FFS checksums, and leaves everything else - including a vendor capsule
   header - untouched.
5. Verifies: the image still parses, the parse tree is identical item for item, the
   file length is unchanged, the byte differences are confined to one range, the first
   2 KiB are identical, and the logo read back out of the new image is byte-identical
   to what went in. Any failure says "do NOT flash".
   Expected noise from UEFIReplace: "Aptio capsule signature may become invalid after
   image modifications" (true, and exactly why only a button flasher can write it) and
   "one of volumes inside overlaps the end of data" (the old parser on padding). The
   line that matters is "File replaced".
6. Writes `modded/<NAME>` and `stock/<NAME>` (same name on purpose - the recovery file
   must have the flasher's name too, and a stick can only carry one), a preview PNG,
   and SHA256SUMS.

`usb` refuses non-USB devices and whole-disk-less paths, shows what is on the stick and
asks you to type `WIPE`, then makes one FAT32 partition on an MBR table with **no
label** (the button flashers are picky about this), copies the file, verifies the
checksum, unmounts.

The build is deterministic: the same stock file, logo and options give a byte-identical
result, so a rebuild can be checked against a SHA256 that is known to have flashed.

## Vendor table - the parts the script cannot know

| Vendor | Recovery flasher | File name it wants | Stock file | Modified files accepted? |
|---|---|---|---|---|
| ASUS | USB BIOS FlashBack: PC off, PSU on, stick in the port marked BIOS, hold the button ~3 s until the LED blinks 3x, wait until dark | Board-specific 8.3 name, e.g. `TG650MPW.CAP` - shown in the BIOS release notes and set by the `BIOSRenamer.exe` in the ZIP (it only renames) | `.CAP` capsule from `https://dlcdnets.asus.com/pub/ASUS/mb/BIOS/<MODEL-WITH-DASHES>-ASUS-<ver>.zip` (newer releases `.ZIP` - probe both) | **Yes on TUF GAMING B650M-PLUS WIFI, verified 2026-09-13.** EZ Flash inside the BIOS setup always rejects them. Other ASUS boards: reported working on Z390/Z790; treat as likely, not certain |
| Gigabyte | Q-Flash Plus: PC off, PSU on, stick in the marked port, press the Q-Flash Plus button | `GIGABYTE.BIN` | `.F<n>` file inside the ZIP, a raw 16/32 MiB image with no capsule header | Widely reported to accept modified images; **unverified here** - check recent reports for the exact board before promising |
| MSI | Flash BIOS Button: PC off, PSU on, stick in the marked port, press the button | `MSI.ROM` | `E<board>IMS.<ver>` inside the ZIP, raw image | Widely reported to accept modified images; **unverified here** |
| ASRock | BIOS Flashback button | `CREATIVE.ROM` | `.ROM` raw image | Reported both ways; **unverified here** |
| Lenovo ThinkPad | Not needed: the official BIOS update utility embeds a custom logo (`LOGO.GIF`/`.JPG`/`.BMP` dropped next to the updater, size limits in its readme) and signs it | - | - | Supported by the vendor. This is how the laptop got its logo |

Boards without a button flasher (most laptops, many budget desktop boards) are out:
their only flash path verifies the signature, and there is no way back from a bad
image short of soldering a programmer to the chip.

Before the user flashes, remind them: BIOS settings reset (note fan curves, memory
profile, boot order); Windows BitLocker must be suspended first (the TPM measurements
change); on AMD the vendor may mark a version as an irreversible PSP update, after
which older versions cannot be flashed. A rejected file is harmless: the LED stops
after a few seconds and nothing is written. Recovery from a bad flash is the same
button with `stock/<NAME>` on the stick.

## New board

1. `detect`, then find the download page and the exact flash file name for the board.
   The name is in the BIOS release notes ("rename to ...") or in the renamer tool in
   the ZIP.
2. `build --image <stock> --name <that name>`. Read what it prints about the logo file:
   if it is not the EDK2 GUID, or the picture is JPEG/PNG rather than BMP, that is
   handled, but note it in `boards.conf`.
3. Only after the user confirms the flash worked and the logo shows, add a line to
   `boards.conf` with the download template, the name and "accepted, <date>". The
   registry is the record of which flashers accept modified images; do not add a board
   on hope.

## Boards seen so far

See `boards.conf`. Format: board name as in `/sys/class/dmi/id/board_name` | vendor |
flash file name | download URL with `VER` placeholder | logo spec seen | status.
