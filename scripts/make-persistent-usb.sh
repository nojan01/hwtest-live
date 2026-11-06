#!/bin/bash
# Schreibt das Hardwaretest-Live-ISO auf einen USB-Stick/USB-HDD und legt im freien
# Platz eine Persistenz-Partition (ext4, Label "persistence") an.
# Booten mit dem Menüeintrag "HPE Live: mit Persistenz".
#
# Aufruf: sudo bash scripts/make-persistent-usb.sh <iso> </dev/sdX> [größe]
#   größe: z. B. 32G (Standard: gesamter Restplatz)
set -euo pipefail

ISO="${1:-}"; DEV="${2:-}"; SIZE="${3:-}"
die() { echo "FEHLER: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "bitte mit sudo ausführen"
[ -f "$ISO" ] || die "ISO nicht gefunden: $ISO"
[ -b "$DEV" ] || die "kein Blockgerät: $DEV"
[ "$(lsblk -ndo TYPE "$DEV")" = disk ] || die "$DEV ist keine ganze Platte (z. B. /dev/sdb, nicht /dev/sdb1)"
for t in sfdisk mkfs.ext4 partprobe; do command -v "$t" >/dev/null || die "$t fehlt"; done

ROOTDEV="$(lsblk -ndo PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null || true)"
[ -n "$ROOTDEV" ] && [ "/dev/$ROOTDEV" = "$DEV" ] && die "$DEV ist die Systemplatte"
if lsblk -nro MOUNTPOINT "$DEV" | grep -q .; then
    die "$DEV hat eingehängte Partitionen – bitte zuerst aushängen"
fi

echo "Zielgerät:"
lsblk -o NAME,SIZE,MODEL,TRAN,LABEL "$DEV"
echo
read -r -p "ALLE Daten auf $DEV werden gelöscht. Zum Fortfahren 'JA' eingeben: " ok
[ "${ok^^}" = JA ] || die "abgebrochen"

echo "Schreibe ISO ..."
wipefs -aq "$DEV"
dd if="$ISO" of="$DEV" bs=4M conv=fsync oflag=direct status=progress
sync
partprobe "$DEV" 2>/dev/null || true; sleep 2

echo "Lege Persistenz-Partition an ..."
echo ",${SIZE},L" | sfdisk --append --no-reread "$DEV" >/dev/null
partprobe "$DEV" 2>/dev/null || true; udevadm settle; sleep 2
PART="/dev/$(lsblk -nlo NAME,TYPE "$DEV" | awk '$2=="part"{p=$1} END{print p}')"
[ -b "$PART" ] || die "neue Partition nicht gefunden"

mkfs.ext4 -q -F -L persistence "$PART"
MNT="$(mktemp -d)"
mount "$PART" "$MNT"
echo "/ union" >"$MNT/persistence.conf"
umount "$MNT"; rmdir "$MNT"
sync

echo
lsblk -o NAME,SIZE,FSTYPE,LABEL "$DEV"
echo "Fertig. Beim Booten 'HPE Live: mit Persistenz' wählen."
