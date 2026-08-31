# Flashing PrintUpkeep OS

PrintUpkeep OS is flashed exactly like any Raspberry Pi OS image, using
[Raspberry Pi Imager](https://www.raspberrypi.com/software/).

## Supported hardware

64-bit Raspberry Pi models only:

| Model | Notes |
| --- | --- |
| Raspberry Pi 5 / 500 | fastest option |
| Raspberry Pi 4 / 400 / CM4 | recommended |
| Raspberry Pi 3 / 3+ / CM3+ | works fine |
| Raspberry Pi Zero 2 W | works; Wi-Fi only, so use Imager's Wi-Fi customization |

Not supported: Pi 1, Pi 2, Zero / Zero W (32-bit only).

You need a microSD card of **8 GB or larger**.

## Step by step

1. Install Raspberry Pi Imager on your computer.
2. **Choose Device** — pick your Pi model.
3. **Choose OS** — *Use custom* and select the downloaded
   `printupkeep-os-<version>-arm64.img.xz` (no need to decompress it).
4. **Choose Storage** — your microSD card.
5. Click **Next**. When Imager asks *"Would you like to apply OS customisation
   settings?"* click **Edit Settings**. This dialog is fully supported by
   PrintUpkeep OS:
   - **Hostname**: the preset is `printupkeep` — keep it unless you run
     several devices (then e.g. `printupkeep2`).
   - **Username / password**: **set this** — the image ships with *no* user
     account, so this is how you get one (needed for SSH).
   - **Wireless LAN**: enter your Wi-Fi SSID + password (skip if using
     Ethernet).
   - **Locale**: your timezone and keyboard layout.
   - On the **Services** tab: enable **SSH** if you want shell access.
6. Flash, wait for verification, insert the card into the Pi, power it up.

First boot takes a couple of minutes (filesystem expansion + your
customization being applied). After that:

- The device appears on your network as **`http://printupkeep.local`** (or the
  hostname you chose).
- The PrintUpkeep connector service is already running; its web UI listens on
  port 80.
- Configuration lives in `/var/lib/printupkeep/connector.json`.

## Flashing without customization (Ethernet)

The image also boots without any Imager customization: connect Ethernet and it
comes up as `printupkeep.local` with the connector running. There is no user
account in that case — attach keyboard + screen and Raspberry Pi OS's normal
first-boot wizard will ask you to create one, or re-flash with Imager
customization instead.

## `printupkeep.local` troubleshooting

The `.local` name uses mDNS (Avahi/Bonjour):

- **Windows**: Windows 10/11 resolve `.local` out of the box. If it fails,
  install Apple's *Bonjour Print Services* (ships with iTunes) or just use the
  IP address — check your router's DHCP client list for a device named
  `printupkeep`.
- **Android**: many Android versions cannot resolve `.local` names in the
  browser. Use the device's IP address from your router, or an mDNS/network
  scanner app (e.g. "Service Browser") to find the `PrintUpkeep` `_http._tcp`
  service.
- **macOS / iOS / Linux**: works out of the box (Avahi/Bonjour built in).
- Everything else failing: the device advertises itself via mDNS as
  `PrintUpkeep` (HTTP on port 80), and your router's UI will list its IP.

## Security notes

- **Never port-forward the PrintUpkeep web UI (port 80) to the internet.** It
  is a LAN-only interface for a device that controls physical hardware. If you
  need remote access, use a VPN (WireGuard/Tailscale) into your LAN instead.
- The image ships with no default user account and no default password — a
  user only exists if you create one in the Imager dialog.
- SSH is enabled at the SSH-flag level (like OctoPi), but without a user
  account there is nothing to log into until you create one.
- The connector runs as an unprivileged system user (`printupkeep`) under a
  hardened systemd unit (`ProtectSystem=strict`, `NoNewPrivileges`), with a
  sudoers whitelist of exactly three commands (restart itself, trigger a
  self-update, read its own logs).
