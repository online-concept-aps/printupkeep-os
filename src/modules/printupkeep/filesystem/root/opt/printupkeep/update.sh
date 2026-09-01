#!/usr/bin/env bash
# PrintUpkeep connector self-update.
#
# Runs as root via printupkeep-update.service (oneshot). Fetches the newest
# connector-v* release of online-concept-aps/printupkeep-os, verifies its
# sha256, unpacks it side-by-side under /opt/printupkeep/versions/<ver>,
# health-checks it, atomically flips /opt/printupkeep/current, restarts the
# connector service (rolling back if it fails to come up), and prunes old
# versions keeping the last 2.
#
# NOTE: connector tarballs temporarily live on the printupkeep-os repo's
# releases. While that repo is private, a GitHub token with read access must
# be placed in /etc/printupkeep/github-token for updates to work; once the
# repo is public no token is needed.
set -euo pipefail

REPO="online-concept-aps/printupkeep-os"
API="https://api.github.com/repos/${REPO}"
BASE_DIR="/opt/printupkeep"
VERSIONS_DIR="${BASE_DIR}/versions"
CURRENT_LINK="${BASE_DIR}/current"
SERVICE="printupkeep-connector"
NODE_BIN="/usr/local/bin/node"
TOKEN_FILE="/etc/printupkeep/github-token"
KEEP=2

log() { echo "[printupkeep-update] $*"; }
fail() { log "ERROR: $*"; exit 1; }

TMP_DIR="$(mktemp -d /tmp/printupkeep-update.XXXXXX)"
STAGING=""
cleanup() {
    # Preserve the real exit status: an EXIT trap whose last command returns
    # non-zero (the [ -n "$STAGING" ] test when STAGING is empty) would
    # otherwise mask exit 0 as a failure, so a "nothing to do" run showed up
    # as systemd status=1/FAILURE.
    rc=$?
    rm -rf "${TMP_DIR}"
    [ -n "${STAGING}" ] && rm -rf "${STAGING}"
    return $rc
}
trap cleanup EXIT

AUTH_ARGS=()
if [ -f "${TOKEN_FILE}" ]; then
    AUTH_ARGS=(-H "Authorization: Bearer $(tr -d '[:space:]' < "${TOKEN_FILE}")")
    log "Using GitHub token from ${TOKEN_FILE}"
fi

api() {
    curl -fsSL --retry 3 "${AUTH_ARGS[@]}" -H "Accept: application/vnd.github+json" "$@"
}

log "Looking up the latest connector release on ${REPO}"
RELEASES_JSON="$(api "${API}/releases?per_page=50")" \
    || fail "could not reach the GitHub API (offline, or private repo without a token in ${TOKEN_FILE}?)"

LATEST_JSON="$(jq -c '[.[] | select(.tag_name | startswith("connector-v"))
                          | select(.draft == false) | select(.prerelease == false)]
                      | sort_by(.created_at) | last // empty' <<<"${RELEASES_JSON}")"
[ -n "${LATEST_JSON}" ] || fail "no connector-v* release found on ${REPO}"

TAG="$(jq -r '.tag_name' <<<"${LATEST_JSON}")"
VERSION="${TAG#connector-v}"
TARBALL="printupkeep-connector-${VERSION}.tgz"
NEW_DIR="${VERSIONS_DIR}/${VERSION}"
log "Latest release: ${TAG} (version ${VERSION})"

if [ "$(readlink -f "${CURRENT_LINK}" || true)" = "${NEW_DIR}" ] && [ -f "${NEW_DIR}/dist/cli.js" ]; then
    log "Already running ${VERSION} — nothing to do."
    exit 0
fi

asset_url() {
    jq -r --arg name "$1" '.assets[] | select(.name == $name) | .url' <<<"${LATEST_JSON}"
}
TARBALL_URL="$(asset_url "${TARBALL}")"
SHA_URL="$(asset_url "${TARBALL}.sha256")"
[ -n "${TARBALL_URL}" ] || fail "release ${TAG} has no asset ${TARBALL}"
[ -n "${SHA_URL}" ] || fail "release ${TAG} has no asset ${TARBALL}.sha256"

log "Downloading ${TARBALL}"
# The asset API URL + octet-stream Accept header works for both public and
# private repositories (browser_download_url does not work while private).
curl -fSL --retry 3 "${AUTH_ARGS[@]}" -H "Accept: application/octet-stream" \
    -o "${TMP_DIR}/${TARBALL}" "${TARBALL_URL}"
curl -fsSL --retry 3 "${AUTH_ARGS[@]}" -H "Accept: application/octet-stream" \
    -o "${TMP_DIR}/${TARBALL}.sha256" "${SHA_URL}"

log "Verifying sha256"
(cd "${TMP_DIR}" && sha256sum -c "${TARBALL}.sha256") || fail "sha256 mismatch for ${TARBALL}"

log "Unpacking to ${NEW_DIR}"
STAGING="${VERSIONS_DIR}/.staging-${VERSION}.$$"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
tar -xzf "${TMP_DIR}/${TARBALL}" -C "${STAGING}"

log "Health-checking the new version"
# --version once the connector supports it; --help exercises the same
# ESM bundle + node_modules import graph either way.
"${NODE_BIN}" "${STAGING}/dist/cli.js" --version >/dev/null 2>&1 \
    || "${NODE_BIN}" "${STAGING}/dist/cli.js" --help >/dev/null \
    || fail "new version failed its health check — leaving current version in place"

PREVIOUS_TARGET="$(readlink -f "${CURRENT_LINK}" || true)"
rm -rf "${NEW_DIR}"
mv "${STAGING}" "${NEW_DIR}"
STAGING=""
chown -R root:root "${NEW_DIR}"

log "Switching ${CURRENT_LINK} -> ${NEW_DIR}"
ln -sfn "${NEW_DIR}" "${CURRENT_LINK}"

log "Restarting ${SERVICE}"
systemctl restart "${SERVICE}" || true
sleep 5
if ! systemctl is-active --quiet "${SERVICE}"; then
    log "Service failed to start on ${VERSION} — rolling back"
    if [ -n "${PREVIOUS_TARGET}" ] && [ -d "${PREVIOUS_TARGET}" ] && [ "${PREVIOUS_TARGET}" != "${NEW_DIR}" ]; then
        ln -sfn "${PREVIOUS_TARGET}" "${CURRENT_LINK}"
        systemctl restart "${SERVICE}" || true
        fail "rolled back to $(basename "${PREVIOUS_TARGET}")"
    fi
    fail "no previous version to roll back to"
fi

log "Pruning old versions (keeping newest ${KEEP} + whatever 'current' points at)"
CURRENT_TARGET="$(readlink -f "${CURRENT_LINK}")"
# shellcheck disable=SC2012
ls -1 "${VERSIONS_DIR}" | grep -v '^\.' | sort -V | head -n -${KEEP} | while read -r old; do
    if [ "${VERSIONS_DIR}/${old}" != "${CURRENT_TARGET}" ]; then
        log "Removing old version ${old}"
        rm -rf "${VERSIONS_DIR:?}/${old}"
    fi
done

log "Update to ${VERSION} complete."
