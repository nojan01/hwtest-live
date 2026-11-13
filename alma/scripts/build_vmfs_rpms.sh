#!/bin/bash
# Baut vmfs-tools und vmfs6-tools als RPM in einem AlmaLinux-9-Container
# (nicht in EPEL paketiert). Ergebnis: alma/rpm/out/*.rpm
#
# Aufruf auf dem Host:  bash alma/scripts/build_vmfs_rpms.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${ALMA_IMAGE:-docker.io/library/almalinux:9}"

if [[ ! -f /run/.containerenv && ! -f /.dockerenv ]]; then
    ENGINE="$(command -v podman || command -v docker || true)"
    [[ -n "$ENGINE" ]] || { echo "FEHLER: podman oder docker fehlt" >&2; exit 1; }
    mkdir -p "$HERE/rpm/out"
    exec "$ENGINE" run --rm -v "$HERE:/alma:Z" "$IMAGE" bash /alma/scripts/build_vmfs_rpms.sh
fi

# --- im Container -------------------------------------------------------
dnf -q -y install epel-release dnf-plugins-core >/dev/null
dnf -q config-manager --set-enabled crb
dnf -q -y install rpm-build rpmdevtools xz patch >/dev/null
rpmdev-setuptree
cp /alma/rpm/*.spec ~/rpmbuild/SPECS/
for spec in ~/rpmbuild/SPECS/*.spec; do
    spectool -g -R "$spec"
    dnf -q -y builddep "$spec" >/dev/null
    rpmbuild -bb "$spec"
done
cp ~/rpmbuild/RPMS/x86_64/*.rpm /alma/rpm/out/
chown -R --reference=/alma/rpm /alma/rpm/out 2>/dev/null || true
ls -la /alma/rpm/out/
