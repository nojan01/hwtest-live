#!/bin/bash
# Schreibt das Hardwaretest-Live-ISO auf einen USB-Stick/USB-HDD und legt
# eine Persistenz-Partition (ext4, Label "persistence") an.
# Booten mit dem Menüeintrag "Hardwaretest Live: mit Persistenz".
#
# Aufruf: sudo bash make-persistent-usb.sh <iso> </dev/sdX> [größe] [--dd]
#   größe: z. B. 32G (Standard: gesamter Restplatz)
#
# Standard (GPT): GPT mit echter EFI-Systempartition (FAT32, enthält den
#   kompletten ISO-Inhalt), BIOS-Boot-Partition mit GRUB (falls grub-pc-bin
#   vorhanden) und Persistenz-Partition. Wird von jeder UEFI-Firmware als
#   bootfähig erkannt – auch von solchen (z. B. Lenovo), die das Hybrid-ISO
#   (MBR mit verschachtelter EFI-Partition) nicht in die Bootliste aufnehmen.
#   Die FAT32-Partition ist auch unter Windows lesbar (Reports kopieren).
# --dd: altes Verfahren – ISO 1:1 schreiben (isohybrid), Persistenz dahinter.
set -euo pipefail

ISO=""; DEV=""; SIZE=""; MODE=gpt
for a in "$@"; do
    case "$a" in
        --dd) MODE=dd ;;
        --gpt) MODE=gpt ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) if [ -z "$ISO" ]; then ISO="$a"; elif [ -z "$DEV" ]; then DEV="$a"; else SIZE="$a"; fi ;;
    esac
done
die() { echo "FEHLER: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "bitte mit sudo ausführen"
[ -n "$ISO" ] && [ -n "$DEV" ] || die "Aufruf: sudo bash $0 <iso> </dev/sdX> [größe] [--dd]"
[ -f "$ISO" ] || die "ISO nicht gefunden: $ISO"
[ -b "$DEV" ] || die "kein Blockgerät: $DEV"
[ "$(lsblk -ndo TYPE "$DEV")" = disk ] || die "$DEV ist keine ganze Platte (z. B. /dev/sdb, nicht /dev/sdb1)"
TOOLS=(sfdisk mkfs.ext4 partprobe wipefs)
[ "$MODE" = gpt ] && TOOLS+=(mkfs.vfat rsync)
for t in "${TOOLS[@]}"; do command -v "$t" >/dev/null || die "$t fehlt"; done

ROOTDEV="$(lsblk -ndo PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null || true)"
[ -n "$ROOTDEV" ] && [ "/dev/$ROOTDEV" = "$DEV" ] && die "$DEV ist die Systemplatte"
if lsblk -nro MOUNTPOINT "$DEV" | grep -q .; then
    die "$DEV hat eingehängte Partitionen – bitte zuerst aushängen"
fi

echo "Zielgerät:"
lsblk -o NAME,SIZE,MODEL,TRAN,LABEL "$DEV"
echo "Verfahren: $MODE"
echo
read -r -p "ALLE Daten auf $DEV werden gelöscht. Zum Fortfahren 'JA' eingeben: " ok
[ "${ok^^}" = JA ] || die "abgebrochen"

partdev() {  # partdev N -> /dev/sdXN bzw. /dev/nvme0n1pN
    case "$DEV" in *[0-9]) echo "${DEV}p$1" ;; *) echo "${DEV}$1" ;; esac
}
settle() { partprobe "$DEV" 2>/dev/null || true; udevadm settle; sleep 2; }
MNT_ISO=""; MNT_USB=""; MNT_P=""
cleanup() {
    for m in "$MNT_P" "$MNT_USB" "$MNT_ISO"; do
        [ -n "$m" ] && mountpoint -q "$m" && umount "$m" && rmdir "$m" || true
    done
}
trap cleanup EXIT

make_persistence() {  # make_persistence /dev/sdXN
    mkfs.ext4 -q -F -L persistence "$1"
    MNT_P="$(mktemp -d)"
    mount "$1" "$MNT_P"
    echo "/ union" >"$MNT_P/persistence.conf"
    umount "$MNT_P"; rmdir "$MNT_P"; MNT_P=""
}

if [ "$MODE" = dd ]; then
    echo "Schreibe ISO ..."
    wipefs -aq "$DEV"
    dd if="$ISO" of="$DEV" bs=4M conv=fsync oflag=direct status=progress
    sync; settle
    echo "Lege Persistenz-Partition an ..."
    echo ",${SIZE},L" | sfdisk --append --no-reread "$DEV" >/dev/null
    settle
    PART="/dev/$(lsblk -nlo NAME,TYPE "$DEV" | awk '$2=="part"{p=$1} END{print p}')"
    [ -b "$PART" ] || die "neue Partition nicht gefunden"
    make_persistence "$PART"
else
    BIOS=0
    if command -v grub-install >/dev/null && [ -d /usr/lib/grub/i386-pc ]; then BIOS=1; fi
    # Volume-Label des ISO übernehmen: Debian live-boot und dracut (root=live:CDLABEL=...)
    # finden das Live-System darüber; FAT32-Label max. 11 Zeichen.
    LABEL="$(blkid -o value -s LABEL "$ISO" 2>/dev/null | cut -c1-11)"; LABEL="${LABEL:-HWTEST-LIVE}"
    ISO_MB=$(( ($(stat -c %s "$ISO") + 1048575) / 1048576 ))
    LIVE_MB=$(( ISO_MB + 256 ))
    echo "Partitioniere (GPT) ..."
    wipefs -aq "$DEV"
    {
        echo "label: gpt"
        [ "$BIOS" = 1 ] && echo "size=1MiB, type=21686148-6449-6E6F-744E-656564454649, name=bios-boot"
        echo "size=${LIVE_MB}MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=$LABEL"
        echo "${SIZE:+size=$SIZE,} type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=persistence"
    } | sfdisk -q --no-reread "$DEV" >/dev/null
    settle
    if [ "$BIOS" = 1 ]; then P_LIVE="$(partdev 2)"; P_PERS="$(partdev 3)"; else P_LIVE="$(partdev 1)"; P_PERS="$(partdev 2)"; fi
    [ -b "$P_LIVE" ] && [ -b "$P_PERS" ] || die "Partitionen nicht gefunden"

    echo "Kopiere ISO-Inhalt nach $P_LIVE (FAT32) ..."
    mkfs.vfat -F 32 -n "$LABEL" "$P_LIVE" >/dev/null
    MNT_ISO="$(mktemp -d)"; MNT_USB="$(mktemp -d)"
    mount -o loop,ro "$ISO" "$MNT_ISO"
    mount "$P_LIVE" "$MNT_USB"
    rsync -rt --no-perms --no-owner --no-group --no-links --info=progress2 "$MNT_ISO/" "$MNT_USB/"
    # GRUB (UEFI) sucht /.disk/info und lädt /boot/grub/grub.cfg – beides ist
    # im ISO-Inhalt enthalten; EFI/boot/bootx64.efi (Shim) + grubx64.efi ebenso.
    [ -f "$MNT_USB/EFI/boot/bootx64.efi" ] || die "EFI/boot/bootx64.efi fehlt im ISO"
    # AlmaLinux-ISO: GRUB-Konfiguration liegt nur unter EFI/BOOT; für grub-pc nach boot/grub spiegeln
    if [ ! -f "$MNT_USB/boot/grub/grub.cfg" ] && [ -f "$MNT_USB/EFI/BOOT/grub.cfg" ]; then
        mkdir -p "$MNT_USB/boot/grub"
        sed 's/\blinuxefi\b/linux/; s/\binitrdefi\b/initrd/' "$MNT_USB/EFI/BOOT/grub.cfg" >"$MNT_USB/boot/grub/grub.cfg"
    fi
    if [ "$BIOS" = 1 ]; then
        echo "Installiere GRUB für BIOS-Boot ..."
        grub-install --target=i386-pc --boot-directory="$MNT_USB/boot" --recheck "$DEV" >/dev/null 2>&1 \
            || echo "WARNUNG: grub-install (BIOS) fehlgeschlagen – nur UEFI-Boot möglich"
    else
        echo "Hinweis: grub-pc-bin fehlt – Stick bootet nur per UEFI"
    fi
    sync
    umount "$MNT_USB" "$MNT_ISO"; rmdir "$MNT_USB" "$MNT_ISO"; MNT_USB=""; MNT_ISO=""

    echo "Lege Persistenz-Partition an ..."
    make_persistence "$P_PERS"
fi
sync

echo
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME "$DEV"
echo "Fertig. Beim Booten 'Hardwaretest Live: mit Persistenz' wählen."
