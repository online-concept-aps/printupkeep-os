# Updating the connector

PrintUpkeep OS separates the **OS image** (this repo's `v*` releases — flashed
once) from the **connector** (the `connector-v*` releases — self-updates in
place). You should rarely need to re-flash.

## Layout

```
/opt/node/                    Node.js runtime (pinned at image build)
/opt/printupkeep/
├── current -> versions/0.1.0    <- atomic switch point (symlink)
├── versions/
│   ├── 0.1.0/                   <- dist/ + production node_modules
│   └── 0.2.0/
└── update.sh                    <- the self-updater (runs as root)
/var/lib/printupkeep/         connector.json + journal (the only writable dir
                              the service sees; survives updates untouched)
```

The systemd service always starts
`/usr/local/bin/node /opt/printupkeep/current/dist/cli.js`, so an update is
just: install a new `versions/<ver>` next to the old one, flip the `current`
symlink, restart.

## How a self-update runs

Trigger it as root (`sudo systemctl start printupkeep-update.service`) — or
the connector itself can trigger it, since the `printupkeep` user's sudoers
whitelist includes exactly that command. The updater
(`/opt/printupkeep/update.sh`) then:

1. Asks the GitHub API for the newest non-draft, non-prerelease
   `connector-v*` release of `online-concept-aps/printupkeep-os`.
2. Exits early if `current` already points at that version.
3. Downloads `printupkeep-connector-<ver>.tgz` + its `.sha256` and **verifies
   the checksum** — a corrupt or tampered download never gets installed.
4. Unpacks into a hidden staging directory, then **health-checks** the new
   build (`node dist/cli.js --version`, falling back to `--help` until the
   CLI grows a `--version`). A build that cannot even load its bundle is
   discarded before anything changes.
5. Moves staging to `versions/<ver>` and atomically flips the `current`
   symlink (`ln -sfn`).
6. Restarts `printupkeep-connector` and waits 5 seconds.

Follow along with `journalctl -u printupkeep-update.service`.

## Rollback

- **Automatic**: if the service is not active after the restart, the updater
  flips `current` back to the previous version, restarts again, and exits
  with an error. The device keeps running the old, working connector.
- **Manual**: the last 2 versions are kept on disk, so
  `sudo ln -sfn /opt/printupkeep/versions/<old-ver> /opt/printupkeep/current
  && sudo systemctl restart printupkeep-connector` returns to the previous
  version at any time.

Old versions beyond the newest 2 are pruned after a successful update (the
version `current` points at is never pruned).

## While the repos are private (temporary)

Connector tarballs are currently attached to `connector-v*` releases **on this
repo** so that the image build's CI can fetch them with its own workflow
token. A device in the field can only reach those releases if you put a GitHub
token with read access into `/etc/printupkeep/github-token` (file readable by
root only). Once the repos go public, updates work with no token, and the
release home moves to the main `printupkeep` repo (see
`docs/main-repo-connector-release.yml`).

## Updating the OS itself

OS-level updates are ordinary Debian updates: `sudo apt update && sudo apt
full-upgrade`. A new PrintUpkeep OS image release (`v*`) is only needed for
structural changes (new Node major, partition changes, etc.).
