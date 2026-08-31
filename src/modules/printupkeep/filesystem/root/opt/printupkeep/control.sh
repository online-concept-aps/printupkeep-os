#!/usr/bin/env bash
# Root-side half of the web UI's System controls. The connector writes
# "<verb> [arg] <timestamp>" to the control file; printupkeep-control.path
# (PathExists=) starts this oneshot. Unknown verbs are ignored.
set -euo pipefail

CONTROL="/var/lib/printupkeep/state/control"

# Claim the request atomically: rename it out of the way, then read our own
# private copy exactly once. This closes the torn-read window where the
# connector could overwrite the file mid-parse (e.g. an ssh-off landing
# between two reads of an ssh-on, splicing a garbage password). If the file
# is already gone (a racing trigger claimed it), there is nothing to do.
RUN="${CONTROL}.run"
mv "${CONTROL}" "${RUN}" 2>/dev/null || exit 0
read -r ACTION ARG _REST < "${RUN}" || true
rm -f "${RUN}"

case "${ACTION}" in
    restart)
        echo "[printupkeep-control] restart requested by web UI"
        systemctl restart printupkeep-connector.service
        ;;
    update)
        echo "[printupkeep-control] update requested by web UI"
        systemctl start printupkeep-update.service
        ;;
    ssh-on)
        # ARG must be a sha512crypt hash ($6$…) made by the web UI — never a
        # plain password. Reject anything else so a spliced/garbage value can
        # never become the account password.
        case "${ARG}" in
            '$6$'*) : ;;
            *)
                echo "[printupkeep-control] ssh-on without a valid password hash — ignored"
                exit 0
                ;;
        esac
        echo "[printupkeep-control] ssh-on requested by web UI"
        # The Raspberry Pi OS base image ships a DISABLED "pi" account with a
        # nologin shell (a template Imager's userconf would normally finish).
        # Create it if absent, but ALWAYS force a real login shell and a home
        # dir — otherwise SSH authenticates and then refuses the session with
        # "This account is currently not available." (the nologin shell).
        if ! id -u pi >/dev/null 2>&1; then
            useradd -m -s /bin/bash pi
        fi
        usermod -s /bin/bash pi
        if [ ! -d /home/pi ]; then
            mkdir -p /home/pi
            cp -a /etc/skel/. /home/pi/ 2>/dev/null || true
        fi
        chown -R pi:pi /home/pi
        usermod -aG sudo pi
        usermod -p "${ARG}" pi
        # The image ships no host keys (never share keys across devices);
        # create this device's own set if sshd has none yet. Idempotent.
        ssh-keygen -A
        systemctl enable --now ssh
        ;;
    ssh-off)
        echo "[printupkeep-control] ssh-off requested by web UI"
        systemctl disable --now ssh
        ;;
    *)
        echo "[printupkeep-control] ignoring unknown action '${ACTION}'"
        ;;
esac
