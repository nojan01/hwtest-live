#!/usr/bin/env bash
# Baut das ISO in einem privilegierten Debian-13-Container (docker oder podman).
# Praktisch auf Nicht-Debian-Hosts (Ubuntu, Mint, Fedora, ...).
#
#   ./scripts/build_in_container.sh [Optionen von build_live_iso.sh]
#   z.B. ./scripts/build_in_container.sh --nvidia driver
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-docker.io/library/debian:trixie}"

if [ -n "${CONTAINER_ENGINE:-}" ]; then
    ENGINE="$CONTAINER_ENGINE"
elif command -v podman >/dev/null 2>&1; then
    ENGINE=podman
elif command -v docker >/dev/null 2>&1; then
    ENGINE=docker
else
    echo "Weder podman noch docker gefunden." >&2
    exit 1
fi

SUDO=()
# live-build braucht echte root-Rechte (mount, mknod) -> rootful Container.
[ "$(id -u)" -eq 0 ] || SUDO=(sudo)

env_args=()
for v in NVIDIA NVIDIA_KMOD HARDWARETEST JSON_VIEWER ILOREST STRIP_KERNEL_MODULES MIRROR GITHUB_TOKEN KEYBOARD TIMEZONE; do
    [ -n "${!v:-}" ] && env_args+=(-e "$v=${!v}")
done

exec "${SUDO[@]}" "$ENGINE" run --rm --privileged \
    -v "$REPO_DIR:/work" -w /work \
    -e SUDO_UID="$(id -u)" -e SUDO_GID="$(id -g)" \
    "${env_args[@]}" \
    "$IMAGE" bash -euc '
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
            live-build debootstrap curl ca-certificates python3 libarchive-tools \
            git xz-utils >/dev/null
        git config --global --add safe.directory /work
        exec ./scripts/build_live_iso.sh "$@"
    ' build "$@"
