# Raspberry Pi Imager sublist

`rpi-imager.json` is the OS sublist entry for adding PrintUpkeep OS to
Raspberry Pi Imager (via "Use custom repository" or an eventual submission to
the official list). The placeholder fields (`url`, hashes, sizes,
`release_date`) are filled per release — the values come from the
`checksums.txt` produced by `.github/workflows/build.yml` (see the
TODO(release) comment in that workflow).

Device tags, verified against the official
`os_list_imagingutility` device list:

- `pi5-64bit` — Raspberry Pi 5 / 500
- `pi4-64bit` — Raspberry Pi 4 / 400 / CM4
- `pi3-64bit` — Raspberry Pi 3 / 3+ **and Raspberry Pi Zero 2 W** (the Zero 2 W
  has no dedicated tag; it declares `pi3-64bit`/`pi3-32bit` in the official
  device list)

`init_format: "systemd"` declares that the image supports Imager's OS
customization (hostname / Wi-Fi / SSH / user) via raspberrypi-sys-mods, which
this image keeps fully intact (asserted at build time).
