#!/bin/bash
# Prüft in einem AlmaLinux-9-Container, ob alle Pakete aus alma/packages.ks
# (und optional das NVIDIA-Profil) in den eingebundenen Repos verfügbar sind.
#
# Aufruf auf dem Host:  bash alma/scripts/check_packages.sh [--nvidia]
# Braucht podman oder docker und Internet.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${ALMA_IMAGE:-docker.io/library/almalinux:9}"

if [[ ! -f /run/.containerenv && ! -f /.dockerenv ]]; then
    ENGINE="$(command -v podman || command -v docker || true)"
    [[ -n "$ENGINE" ]] || { echo "FEHLER: podman oder docker fehlt" >&2; exit 1; }
    exec "$ENGINE" run --rm -v "$HERE:/alma:Z" "$IMAGE" bash /alma/scripts/check_packages.sh "$@"
fi

# --- im Container -------------------------------------------------------
WITH_NVIDIA=0
[[ "${1:-}" == "--nvidia" ]] && WITH_NVIDIA=1

dnf -q -y install epel-release dnf-plugins-core >/dev/null
dnf -q config-manager --set-enabled crb
dnf -q -y install https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm >/dev/null || true
dnf -q -y install "https://zfsonlinux.org/epel/zfs-release-2-3$(rpm --eval '%{dist}').noarch.rpm" >/dev/null || true
cp /alma/repos/hpe.repo /etc/yum.repos.d/
[[ $WITH_NVIDIA -eq 1 ]] && cp /alma/repos/nvidia-cuda.repo /etc/yum.repos.d/
dnf -q config-manager --save --setopt='*.skip_if_unavailable=1'
dnf -q makecache || true

mapfile -t PACKAGES < <(sed -n '/^%packages/,/^%end/p' /alma/packages.ks \
    | grep -v '^%\|^#\|^@\|^-\|^$')
if [[ $WITH_NVIDIA -eq 1 ]]; then
    PACKAGES+=(nvidia-open nvidia-driver-cuda nvidia-persistenced nvidia-modprobe
        datacenter-gpu-manager-4-core datacenter-gpu-manager-4-cuda13)
fi

missing=0
for p in "${PACKAGES[@]}"; do
    r="$(dnf -q repoquery --qf '%{repoid} %{version}' "$p" 2>/dev/null | tail -1 || true)"
    if [[ -n "$r" ]]; then
        printf 'OK     %-32s %s\n' "$p" "$r"
    else
        printf 'FEHLT  %s\n' "$p"
        missing=$((missing + 1))
    fi
done
echo
echo "Geprüft: ${#PACKAGES[@]} Pakete, fehlend: $missing"
[[ $missing -eq 0 ]]
