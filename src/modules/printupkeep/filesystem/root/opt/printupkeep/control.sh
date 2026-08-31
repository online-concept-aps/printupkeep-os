#!/usr/bin/env bash
# Root-side half of the web UI's Restart/Update buttons. The connector
# writes "<action> <timestamp>" to the control file; printupkeep-control.path
# starts this oneshot. Only two verbs exist — anything else is ignored.
set -euo pipefail

CONTROL="/var/lib/printupkeep/state/control"
[ -f "${CONTROL}" ] || exit 0

ACTION="$(awk '{print $1; exit}' "${CONTROL}" 2>/dev/null || true)"
rm -f "${CONTROL}"

case "${ACTION}" in
    restart)
        echo "[printupkeep-control] restart requested by web UI"
        systemctl restart printupkeep-connector.service
        ;;
    update)
        echo "[printupkeep-control] update requested by web UI"
        systemctl start printupkeep-update.service
        ;;
    *)
        echo "[printupkeep-control] ignoring unknown action '${ACTION}'"
        ;;
esac
