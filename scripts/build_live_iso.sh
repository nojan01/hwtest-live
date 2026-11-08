#!/usr/bin/env bash
# Baut das Hardwaretest-Live-ISO (Repo HPE-Live-ISO) (Debian 13 "trixie", amd64, hybrid BIOS/UEFI) mit live-build.
#
#   sudo ./scripts/build_live_iso.sh [Optionen]
#
# Siehe --help bzw. README.md.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NVIDIA="${NVIDIA:-dcgm}"                    # dcgm (Standard) | driver | none
NVIDIA_KMOD="${NVIDIA_KMOD:-open}"          # open | proprietary
NVIDIA_VERSION="${NVIDIA_VERSION:-595.91.07}" # Treiberversion aus dem NVIDIA CUDA-Repo
HARDWARETEST="${HARDWARETEST:-latest}"      # latest | Pfad zu hardwaretest_*_amd64.deb
JSON_VIEWER="${JSON_VIEWER:-latest}"        # latest | Pfad zu *_amd64.deb
ILOREST="${ILOREST:-latest}"                # latest | none | Pfad zu ilorest-*.rpm oder *.deb
FREE="${FREE:-0}"                           # 1 = freie Variante
BTOP="${BTOP:-backport}"                     # backport | trixie | Pfad zu btop_*_amd64.deb
MEMTEST86="${MEMTEST86:-none}"              # none | Pfad zu memtest86-usb.img oder entpacktem Ordner (PassMark, UEFI)
VENDOR_TOOLS="${VENDOR_TOOLS:-none}"        # none | Ordner mit Hersteller-Paketen (.deb/.rpm: qaucli, hbacmd, MFT, ...) -> internes ISO
STRIP_KERNEL_MODULES="${STRIP_KERNEL_MODULES:-1}"
MIRROR="${MIRROR:-http://deb.debian.org/debian/}"
BUILD_ROOT="${BUILD_ROOT:-$REPO_DIR/build}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_DIR/dist}"
KEYBOARD="${KEYBOARD:-de}"
TIMEZONE="${TIMEZONE:-Europe/Berlin}"
LOCALE="${LOCALE:-de_DE.UTF-8}"             # UTF-8 nötig für Rahmen/Graphen in htop/btop

HARDWARETEST_REPO="nojan01/Ubuntu-Stresstest"
JSON_VIEWER_REPO="nojan01/json-viewer-editor"
ILOREST_REPO="HewlettPackard/python-redfish-utility"
# btop 1.3.2 aus trixie zeichnet bei vielen Threads (z. B. 2x16 Kerne mit HT)
# keine Einzelkerne, wenn der CPU-Kasten zu schmal für Kern-Graphen ist.
# Ab 1.4 behoben; das Paket aus sid läuft unverändert auf trixie.
BTOP_BACKPORT_DEB="btop_1.4.7-1_amd64.deb"
BTOP_BACKPORT_SHA256="f3e4f6c24220859b970ae937eed87d53ce2676a1a7dfdc5b90178bc111c69559"
BTOP_BACKPORT_URLS=(
    "https://deb.debian.org/debian/pool/main/b/btop/$BTOP_BACKPORT_DEB"
    "https://snapshot.debian.org/file/e147b7695101862d22b954457ecaeb5265f178df"
)

usage() {
    cat <<EOF
Aufruf: sudo $0 [Optionen]

  --nvidia dcgm|driver|none     NVIDIA-Variante (Default: dcgm = einheitliches Image)
                                  dcgm   = Compute-Treiber + nvidia-smi + NVIDIA DCGM;
                                           nouveau/NVK als Bootmenü-Notlösung
                                  driver = nur Compute-Treiber + nvidia-smi
                                  none   = nur nouveau/NVK (ISO-Name -ohne-nvidia)
  --nvidia-kmod open|proprietary  Kernelmodul (Default: open, ab Turing/Ampere)
  --nvidia-version VERSION      Treiberversion aus dem NVIDIA CUDA-Repo
                                  (Default: $NVIDIA_VERSION)
  --hardwaretest latest|DATEI   Hardwaretest-.deb (Default: neuestes GitHub-Release)
  --json-viewer latest|DATEI    JSON-Viewer-.deb (Default: neuestes GitHub-Release)
  --ilorest latest|none|DATEI   iLOrest (.rpm von HPE oder .deb; Default: latest)
  --btop backport|trixie|DATEI btop-Version (Default: backport = 1.4.7 aus sid,
                                  zeigt auch bei vielen Kernen die Einzelkerne;
                                  trixie = Paket aus trixie, 1.3.2)
  --memtest86 none|DATEI|DIR   PassMark MemTest86 (UEFI) zusätzlich ins Bootmenü:
                                  memtest86-usb.img aus dem PassMark-ZIP oder ein
                                  Ordner mit BOOTX64.efi (bzw. EFI/BOOT/BOOTX64.efi).
                                  Proprietär, wird nicht mitgeliefert. Default: none
  --vendor-tools none|DIR       Hersteller-Werkzeuge (.deb/.rpm) aus DIR mitinstallieren, z. B.
                                  FC-HBA-Tools hp-qaucli/QConvergeConsoleCLI (QLogic/Marvell),
                                  hp-elxocmcore/elxocmcore (Emulex hbacmd), Mellanox MFT (mlxlink).
                                  Landen in der Basis-Schicht (in jedem Bootmodus verfügbar).
                                  EULA erlaubt keine Weitergabe -> ISO-Name mit -intern,
                                  nicht veröffentlichen. Default: none (externes ISO)
  --free                        Freie Variante: ISO-Name mit -free, bei NVIDIA mit libcuda
                                  für den GPU-Lasttest (Hintergründe wie intern)
  --no-strip-modules            Kernelmodule (Sound, WLAN, Media, ...) nicht entfernen
  --mirror URL                  Debian-Mirror (Default: $MIRROR)
  --output DIR                  Zielverzeichnis für das ISO (Default: dist/)
  -h, --help                    Diese Hilfe

Alle Optionen gehen auch als Umgebungsvariablen (NVIDIA=driver, ...).
GITHUB_TOKEN wird für API-Aufrufe verwendet, falls gesetzt.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --nvidia) NVIDIA="$2"; shift 2 ;;
        --nvidia-kmod) NVIDIA_KMOD="$2"; shift 2 ;;
        --nvidia-version) NVIDIA_VERSION="$2"; shift 2 ;;
        --hardwaretest) HARDWARETEST="$2"; shift 2 ;;
        --json-viewer) JSON_VIEWER="$2"; shift 2 ;;
        --ilorest) ILOREST="$2"; shift 2 ;;
        --memtest86) MEMTEST86="$2"; shift 2 ;;
        --vendor-tools) VENDOR_TOOLS="$2"; shift 2 ;;
        --btop) BTOP="$2"; shift 2 ;;
        --free) FREE=1; shift ;;
        --no-strip-modules) STRIP_KERNEL_MODULES=0; shift ;;
        --mirror) MIRROR="$2"; shift 2 ;;
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mFEHLER: %s\033[0m\n' "$*" >&2; exit 1; }

case "$NVIDIA" in
    dcgm)   SUFFIX="" ;;
    driver) SUFFIX="-nvidia" ;;
    none)   SUFFIX="-ohne-nvidia" ;;
    *) die "--nvidia muss none, driver oder dcgm sein (ist: $NVIDIA)" ;;
esac
case "$NVIDIA_KMOD" in
    open)        NVIDIA_KMOD_PACKAGE="nvidia-kernel-open-dkms" ;;
    proprietary) NVIDIA_KMOD_PACKAGE="nvidia-kernel-dkms" ;;
    *) die "--nvidia-kmod muss open oder proprietary sein" ;;
esac

[ "$(id -u)" -eq 0 ] || die "live-build braucht root-Rechte: sudo $0 ..."

need=(lb debootstrap curl python3 dpkg-deb xorriso)
case "$MEMTEST86" in
    none|"") MEMTEST86=none ;;
    *) [ -e "$MEMTEST86" ] || die "--memtest86: $MEMTEST86 nicht gefunden"
       MEMTEST86="$(readlink -f "$MEMTEST86")"
       [ -d "$MEMTEST86" ] || need+=(mcopy sfdisk) ;;
esac
[ "$ILOREST" = "none" ] || need+=(bsdtar)
VENDOR_PKGS=()
case "$VENDOR_TOOLS" in
    none|"") VENDOR_TOOLS=none ;;
    *) [ -d "$VENDOR_TOOLS" ] || die "--vendor-tools: Ordner $VENDOR_TOOLS nicht gefunden"
       VENDOR_TOOLS="$(readlink -f "$VENDOR_TOOLS")"
       while IFS= read -r f; do VENDOR_PKGS+=("$f"); done < <(find "$VENDOR_TOOLS" -maxdepth 1 -type f \( -name '*.deb' -o -name '*.rpm' \) | sort)
       [ ${#VENDOR_PKGS[@]} -gt 0 ] || die "--vendor-tools: keine .deb/.rpm in $VENDOR_TOOLS"
       for f in "${VENDOR_PKGS[@]}"; do case "$f" in *.rpm) need+=(bsdtar) ;; esac; done ;;
esac
[ "$NVIDIA" = "none" ] || need+=(rsync mksquashfs unsquashfs)
for c in "${need[@]}"; do
    command -v "$c" >/dev/null 2>&1 || die "'$c' fehlt. Installieren: apt install live-build debootstrap curl python3 xorriso isolinux libarchive-tools mtools fdisk rsync squashfs-tools"
done
ISOHDPFX=/usr/lib/ISOLINUX/isohdpfx.bin
[ -f "$ISOHDPFX" ] || die "$ISOHDPFX fehlt. Installieren: apt install isolinux"

mkdir -p "$BUILD_ROOT"
BUILD_ROOT="$(readlink -f "$BUILD_ROOT")"
LB_VERSION="$(lb --version 2>/dev/null | head -n1)"
case "$LB_VERSION" in
    2[0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) [ "${LB_VERSION%%[!0-9]*}" -ge 20250505 ] || die "live-build $LB_VERSION zu alt (mind. 20250505 aus Debian 13 nötig, siehe README)" ;;
    *) die "live-build '$LB_VERSION' zu alt (Ubuntu/Mint liefern 3.0~a57). Debian-13-Paket installieren, siehe README" ;;
esac

[ "$FREE" != 1 ] || SUFFIX="${SUFFIX}-free"
[ "$VENDOR_TOOLS" = none ] || SUFFIX="${SUFFIX}-intern"
VARIANT="trixie-amd64${SUFFIX}"
BUILD_DIR="$BUILD_ROOT/$VARIANT"
ARTIFACTS="$BUILD_ROOT/artifacts"
CACHE_DIR="$BUILD_ROOT/cache"
DATE="$(date +%Y%m%d)"
ISO_NAME="hwtest-live${SUFFIX}-${DATE}${ISO_TAG:+-$ISO_TAG}.iso"   # ISO_TAG=xyz für Testbuilds, überschreibt kein Release

mkdir -p "$ARTIFACTS" "$CACHE_DIR" "$OUTPUT_DIR"
OUTPUT_DIR="$(readlink -f "$OUTPUT_DIR")"

# ---------------------------------------------------------------- Artefakte --
gh_api() {
    local auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" "https://api.github.com/$1"
}

# fetch_latest_asset REPO REGEX -> Pfad der heruntergeladenen Datei
fetch_latest_asset() {
    local repo="$1" regex="$2" meta url name cached
    if ! meta="$(gh_api "repos/$repo/releases/latest")"; then
        # GitHub-Störung (5xx): zuletzt geladenes Artefakt weiterverwenden
        cached="$(ls -t "$ARTIFACTS" 2>/dev/null | grep -E "$regex" | head -n1 || true)"
        [ -n "$cached" ] || die "GitHub-API für $repo nicht erreichbar (kein lokales Artefakt)"
        echo "  WARNUNG: GitHub-API für $repo nicht erreichbar - verwende lokal $cached" >&2
        printf '%s\n' "$ARTIFACTS/$cached"
        return
    fi
    read -r name url < <(printf '%s' "$meta" | python3 -c '
import json, re, sys
rx = re.compile(sys.argv[1])
for a in json.load(sys.stdin).get("assets", []):
    if rx.search(a["name"]):
        print(a["name"], a["browser_download_url"]); break
' "$regex") || true
    [ -n "${url:-}" ] || die "Kein Release-Asset /$regex/ in $repo gefunden"
    if [ ! -s "$ARTIFACTS/$name" ]; then
        echo "  Lade $name ..." >&2
        curl -fL --retry 3 -o "$ARTIFACTS/$name.part" "$url"
        mv "$ARTIFACTS/$name.part" "$ARTIFACTS/$name"
    fi
    printf '%s\n' "$ARTIFACTS/$name"
}

resolve_deb() { # resolve_deb WERT REPO REGEX
    if [ "$1" = "latest" ]; then
        fetch_latest_asset "$2" "$3"
    else
        [ -f "$1" ] || die "Datei nicht gefunden: $1"
        readlink -f "$1"
    fi
}

# ilorest gibt es von HPE nur als RPM -> in ein .deb umpacken.
rpm_to_deb() {
    local rpm="$1" work ver deb
    ver="$(basename "$rpm" | sed -E 's/^ilorest-([0-9.]+)-.*/\1/')"
    deb="$ARTIFACTS/ilorest_${ver}_amd64.deb"
    if [ ! -s "$deb" ]; then
        work="$(mktemp -d)"
        mkdir -p "$work/root/DEBIAN"
        bsdtar -xf "$rpm" -C "$work/root"
        cat >"$work/root/DEBIAN/control" <<EOF
Package: ilorest
Version: ${ver}
Architecture: amd64
Maintainer: Hardwaretest Live ISO <noreply@localhost>
Section: non-free/admin
Priority: optional
Description: HPE RESTful Interface Tool (iLOrest), umgepackt aus ${rpm##*/}
 Kommandozeilenwerkzeug zur Verwaltung von HPE iLO / Redfish.
EOF
        [ -d "$work/root/etc" ] && (cd "$work/root" && find etc -type f | sed 's|^|/|') >"$work/root/DEBIAN/conffiles"
        [ -s "$work/root/DEBIAN/conffiles" ] || rm -f "$work/root/DEBIAN/conffiles"
        dpkg-deb --root-owner-group -Zxz -b "$work/root" "$deb" >/dev/null
        rm -rf "$work"
    fi
    printf '%s\n' "$deb"
}

# Hersteller-RPMs (QLogic qaucli, Emulex OneCommand, Mellanox MFT) generisch in
# ein .deb umpacken. Mit installiertem `alien` bleiben die RPM-Skripte erhalten
# (Symlinks, udev-Regeln); sonst reine Dateikopie wie bei ilorest.
vendor_rpm_to_deb() {
    local rpm="$1" base name ver deb work
    base="$(basename "$rpm" .rpm)"
    base="${base%.x86_64}"; base="${base%.noarch}"
    ver="$(printf '%s' "$base" | sed -E 's/^.*-([0-9][^-]*)-([^-]*)$/\1-\2/')"
    name="$(printf '%s' "$base" | sed -E 's/-[0-9][^-]*-[^-]*$//' | tr 'A-Z_' 'a-z-')"
    ver="$(printf '%s' "$ver" | tr -c 'A-Za-z0-9.+~-' .)"
    deb="$ARTIFACTS/vendor/${name}_${ver}_amd64.deb"
    mkdir -p "$ARTIFACTS/vendor"
    if [ ! -s "$deb" ]; then
        work="$(mktemp -d)"
        if command -v alien >/dev/null 2>&1; then
            (cd "$work" && alien --to-deb --scripts --keep-version "$rpm" >/dev/null 2>&1) \
                && mv "$work"/*.deb "$deb" 2>/dev/null || true
        fi
        if [ ! -s "$deb" ]; then
            mkdir -p "$work/root/DEBIAN"
            bsdtar -xf "$rpm" -C "$work/root"
            cat >"$work/root/DEBIAN/control" <<EOF
Package: ${name}
Version: ${ver}
Architecture: amd64
Maintainer: Hardwaretest Live ISO <noreply@localhost>
Section: non-free/admin
Priority: optional
Description: Hersteller-Werkzeug, umgepackt aus ${rpm##*/}
 Proprietaer, nur fuer den internen Gebrauch (siehe --vendor-tools).
EOF
            dpkg-deb --root-owner-group -Zxz -b "$work/root" "$deb" >/dev/null
        fi
        rm -rf "$work"
    fi
    printf '%s\n' "$deb"
}

log "Hole App-Artefakte"
HT_DEB="$(resolve_deb "$HARDWARETEST" "$HARDWARETEST_REPO" '^hardwaretest_.*_amd64\.deb$')"
JV_DEB="$(resolve_deb "$JSON_VIEWER" "$JSON_VIEWER_REPO" '^[Jj][Ss][Oo][Nn].*_amd64\.deb$')"
ILO_DEB=""
case "$ILOREST" in
    none) ;;
    latest) ILO_DEB="$(rpm_to_deb "$(fetch_latest_asset "$ILOREST_REPO" '^ilorest-.*\.x86_64\.rpm$')")" ;;
    *.rpm) [ -f "$ILOREST" ] || die "Datei nicht gefunden: $ILOREST"; ILO_DEB="$(rpm_to_deb "$(readlink -f "$ILOREST")")" ;;
    *) ILO_DEB="$(resolve_deb "$ILOREST" "" "")" ;;
esac

fetch_btop_backport() {
    local deb="$ARTIFACTS/$BTOP_BACKPORT_DEB" url
    if ! printf '%s  %s\n' "$BTOP_BACKPORT_SHA256" "$deb" | sha256sum -c --status 2>/dev/null; then
        for url in "${BTOP_BACKPORT_URLS[@]}"; do
            echo "  Lade $BTOP_BACKPORT_DEB ($url) ..." >&2
            curl -fL --retry 3 -o "$deb.part" "$url" || continue
            if printf '%s  %s\n' "$BTOP_BACKPORT_SHA256" "$deb.part" | sha256sum -c --status; then
                mv "$deb.part" "$deb"; break
            fi
            echo "  Prüfsumme falsch, verworfen" >&2; rm -f "$deb.part"
        done
        [ -s "$deb" ] || die "$BTOP_BACKPORT_DEB nicht ladbar (oder --btop trixie verwenden)"
    fi
    printf '%s\n' "$deb"
}
BTOP_DEB=""
case "$BTOP" in
    trixie) ;;
    backport) BTOP_DEB="$(fetch_btop_backport)" ;;
    *) BTOP_DEB="$(resolve_deb "$BTOP" "" "")" ;;
esac

deb_field() { dpkg-deb -f "$1" "$2"; }
HT_VER="$(deb_field "$HT_DEB" Version)"
JV_VER="$(deb_field "$JV_DEB" Version)"
ILO_VER="${ILO_DEB:+$(deb_field "$ILO_DEB" Version)}"
echo "  Hardwaretest: $HT_DEB ($HT_VER)"
echo "  JSON Viewer:  $JV_DEB ($JV_VER)"
echo "  iLOrest:      ${ILO_DEB:-<keins>} ${ILO_VER}"
echo "  btop:         ${BTOP_DEB:-<trixie-Paket>} ${BTOP_DEB:+$(deb_field "$BTOP_DEB" Version)}"

# ------------------------------------------------------------ lb config ------
log "Bereite Build-Verzeichnis vor: $BUILD_DIR"
if [ -d "$BUILD_DIR" ]; then
    (cd "$BUILD_DIR" && lb clean --purge >/dev/null 2>&1) || true
    # Reste eines abgebrochenen Builds (proc/sys/dev im Chroot) aushängen,
    # bevor rm -rf darüber läuft.
    awk -v d="$BUILD_DIR/" 'index($2, d) == 1 {print $2}' /proc/mounts | sort -r \
        | while read -r m; do umount -l "$m"; done
    if awk -v d="$BUILD_DIR/" 'index($2, d) == 1' /proc/mounts | grep -q .; then
        die "Unter $BUILD_DIR ist noch etwas gemountet"
    fi
    rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
ln -s "$CACHE_DIR" "$BUILD_DIR/cache"
cd "$BUILD_DIR"

BOOTAPPEND="boot=live components toram hostname=hwtest-live username=user"
BOOTAPPEND+=" keyboard-layouts=${KEYBOARD} timezone=${TIMEZONE} locales=${LOCALE}"
BOOTAPPEND+=" console=ttyS0,115200n8 console=tty0"
# iommu=pt: IOMMU bleibt aktiv, Host-DMA laeuft aber identity-mapped. Standard auf
# GPU-/HPC-Knoten; ohne das scheitert der DCGM-PCIe-P2P-Test bei aktivem VT-d/ACS
# mit "buffer mismatch". Haengen die GPUs hinter PCIe-Switches (Synergy-Grafikmodul),
# bleibt nur "P2P-Test ueberspringen" im Hardwaretest.
[ "$NVIDIA" = "none" ] || BOOTAPPEND+=" modprobe.blacklist=nouveau iommu=pt"

lb config noauto \
    --mode debian \
    --distribution trixie \
    --architectures amd64 \
    --linux-flavours amd64 \
    --archive-areas "main contrib non-free non-free-firmware" \
    --mirror-bootstrap "$MIRROR" \
    --mirror-chroot "$MIRROR" \
    --mirror-binary "http://deb.debian.org/debian/" \
    --security true \
    --updates true \
    --debootstrap-options "--include=ca-certificates" \
    --apt-recommends false \
    --apt-indices false \
    --firmware-chroot false \
    --firmware-binary false \
    --binary-images iso-hybrid \
    --bootloaders "syslinux grub-efi" \
    --uefi-secure-boot enable \
    --chroot-squashfs-compression-type xz \
    --memtest memtest86+ \
    --debian-installer none \
    --win32-loader false \
    --zsync false \
    --cache true \
    --iso-application "Hardwaretest Live" \
    --iso-publisher "intern" \
    --iso-volume "HWTEST-LIVE${SUFFIX^^}" \
    --bootappend-live "$BOOTAPPEND" \
    >/dev/null

log "Kopiere Konfiguration (Variante: NVIDIA=$NVIDIA)"
copy_tree() { [ -d "$1" ] && cp -a "$1/." "config/" ; return 0; }
copy_tree "$REPO_DIR/live"
rm -rf config/optional
# nouveau/NVK-Firmware immer: ohne proprietären Treiber Standard, sonst Notlösung im Bootmenü
echo firmware-nvidia-graphics >> config/package-lists/55-gpu.list.chroot
case "$NVIDIA" in
    dcgm)   copy_tree "$REPO_DIR/live/optional/nvidia"; copy_tree "$REPO_DIR/live/optional/dcgm" ;;
    driver) copy_tree "$REPO_DIR/live/optional/nvidia" ;;
esac
if [ "$NVIDIA" != none ]; then
    sed -i "s|@NVIDIA_KMOD_PACKAGE@|${NVIDIA_KMOD_PACKAGE}|" config/package-lists/60-nvidia.list.chroot
    sed -i "s|@NVIDIA_VERSION@|${NVIDIA_VERSION}|g" config/archives/nvidia-cuda.pref.chroot
    # DCGM braucht die CUDA-Runtime (libcuda, PTX-JIT)
    [ "$NVIDIA" != dcgm ] && [ "$FREE" != 1 ] || rm -f config/includes.chroot_before_packages/etc/dpkg/dpkg.cfg.d/hpe-live-nvidia-nocuda
    [ "$FREE" != 1 ] || printf "libcuda1\nlibnvidia-ptxjitcompiler1\n" >> config/package-lists/60-nvidia.list.chroot
fi

mkdir -p config/packages.chroot
cp "$HT_DEB" "config/packages.chroot/hardwaretest_${HT_VER}_amd64.deb"
cp "$JV_DEB" "config/packages.chroot/$(deb_field "$JV_DEB" Package)_${JV_VER}_amd64.deb"
[ -z "$ILO_DEB" ] || cp "$ILO_DEB" "config/packages.chroot/ilorest_${ILO_VER}_amd64.deb"
[ -z "$BTOP_DEB" ] || cp "$BTOP_DEB" "config/packages.chroot/btop_$(deb_field "$BTOP_DEB" Version)_amd64.deb"
if [ "$VENDOR_TOOLS" != none ]; then
    log "Hersteller-Werkzeuge (internes ISO): ${#VENDOR_PKGS[@]} Paket(e) aus $VENDOR_TOOLS"
    mkdir -p config/includes.chroot/var/lib/hpe-live
    : >config/includes.chroot/var/lib/hpe-live/vendor-tools
    for f in "${VENDOR_PKGS[@]}"; do
        case "$f" in
            *.rpm) f="$(vendor_rpm_to_deb "$f")" ;;
        esac
        cp "$f" "config/packages.chroot/vendor-$(basename "$f")"
        echo "  + $(deb_field "$f" Package) $(deb_field "$f" Version)"
        printf '%s %s\n' "$(deb_field "$f" Package)" "$(deb_field "$f" Version)" >>config/includes.chroot/var/lib/hpe-live/vendor-tools
    done
fi
# live-build installiert alle Pakete aus config/packages.chroot automatisch.

cat >config/hpe-live.conf <<EOF
STRIP_KERNEL_MODULES=${STRIP_KERNEL_MODULES}
HPE_LIVE_NVIDIA=${NVIDIA}
HPE_LIVE_LOCALE=${LOCALE}
EOF
mkdir -p config/includes.chroot/etc config/includes.chroot/usr/local/share/doc/hpe-live
cp "$REPO_DIR/THIRD-PARTY-LICENSES.md" config/includes.chroot/usr/local/share/doc/hpe-live/
cat >config/includes.chroot/etc/hpe-live-release <<EOF
HPE_LIVE_NAME="Hardwaretest Live"
HPE_LIVE_VARIANT=${VARIANT}
HPE_LIVE_NVIDIA=${NVIDIA}
HPE_LIVE_NVIDIA_KMOD=$([ "$NVIDIA" = none ] && echo none || echo "$NVIDIA_KMOD")
HPE_LIVE_NVIDIA_VERSION=$([ "$NVIDIA" = none ] && echo none || echo "$NVIDIA_VERSION")
HPE_LIVE_BUILD_DATE=${DATE}
HPE_LIVE_GIT=$(git -C "$REPO_DIR" describe --always --dirty 2>/dev/null || echo unknown)
HARDWARETEST_VERSION=${HT_VER}
JSON_VIEWER_VERSION=${JV_VER}
ILOREST_VERSION=${ILO_VER:-none}
MEMTEST86=$([ "$MEMTEST86" = none ] && echo none || echo passmark)
EOF

# Bootmenüs: Timeout 5 s (Standard wäre "warten"); eigene Einträge statt der
# live-build-Vorgaben ("Live system", fail-safe):
#   1. Hardwaretest Live (mit NVIDIA-Treiber/DCGM)          2. ohne NVIDIA-Treiber (nouveau, weniger RAM)
#   3. mit Persistenz (USB, alle Treiber)           4. Utilities (memtest, Textmodus, SSH, UEFI-Setup)
LB_SHARE=/usr/share/live/build/bootloaders
mkdir -p config/bootloaders/isolinux config/bootloaders/syslinux_common config/bootloaders/grub-pc
sed -e 's/^timeout .*/timeout 50/' "$LB_SHARE/isolinux/isolinux.cfg" >config/bootloaders/isolinux/isolinux.cfg
# nouveau-Eintrag: nvidia-Module sperren, nouveau zulassen; „toram=filesystem.squashfs“ kopiert und
# hängt nur die Basis ein – nvidia.squashfs (Treiber, CUDA, DCGM; eigene Schicht, siehe
# live/optional/nvidia/hooks) bleibt auf dem Medium und belegt keinen RAM.
NOUVEAU_APPEND=""
if [ "$NVIDIA" != none ]; then
    MAIN_LABEL="Hardwaretest Live: mit NVIDIA-Treiber$([ "$NVIDIA" = dcgm ] && echo " und DCGM")"
    NOUVEAU_APPEND="${BOOTAPPEND/modprobe.blacklist=nouveau/module_blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm,nvidia_peermem hpe-live.nouveau}"
    NOUVEAU_APPEND="${NOUVEAU_APPEND/ toram / toram=filesystem.squashfs }"
else
    MAIN_LABEL="Hardwaretest Live"
fi
cat >config/bootloaders/syslinux_common/live.cfg.in <<EOF
label live-@FLAVOUR@
	menu label ^${MAIN_LABEL}
	menu default
	linux @LINUX@
	initrd @INITRD@
	append @APPEND_LIVE@
EOF
[ -z "$NOUVEAU_APPEND" ] || cat >>config/bootloaders/syslinux_common/live.cfg.in <<EOF

label live-@FLAVOUR@-nouveau
	menu label Hardwaretest Live: ohne NVIDIA-Treiber (^nouveau, GPUs vor Turing, weniger RAM)
	linux @LINUX@
	initrd @INITRD@
	append ${NOUVEAU_APPEND}
EOF
cat >>config/bootloaders/syslinux_common/live.cfg.in <<'EOF'

label live-@FLAVOUR@-persistence
	menu label Hardwaretest Live: mit ^Persistenz (USB, alle Treiber)
	linux @LINUX@
	initrd @INITRD@
	append @APPEND_LIVE@ persistence
EOF
# Utilities-Untermenü (syslinux): HDT + memtest86+ (live-build) + Notfall-Einträge
cat >config/bootloaders/syslinux_common/utilities.cfg <<'EOF'
label hdt
	menu label ^Hardware Detection Tool (HDT)
	com32 hdt.c32

@OPTIONAL_MEMTEST_INCLUDE@

label live-text
	menu label Hardwaretest Live: ^Textmodus (ohne Grafik)
	linux /live/vmlinuz
	initrd /live/initrd.img
	append @APPEND_LIVE@ hpe-live.nox

label live-ssh
	menu label Hardwaretest Live: mit ^SSH-Server (user/live)
	linux /live/vmlinuz
	initrd /live/initrd.img
	append @APPEND_LIVE@ hpe-live.ssh
EOF
sed -e 's/^set default=0/set default=0\nset timeout=5/' "$LB_SHARE/grub-pc/config.cfg" >config/bootloaders/grub-pc/config.cfg
# Neutrale Boot-Hintergründe ohne Text (alle Varianten): isolinux 640x480, GRUB 1024x768.
SPLASH_DIR="$REPO_DIR/live/boot-splash"
cp "$SPLASH_DIR/isolinux.png" config/bootloaders/isolinux/splash.png
cp "$SPLASH_DIR/grub.png" config/bootloaders/grub-pc/splash.png
mkdir -p config/bootloaders/grub-pc/live-theme
sed -e 's|^title-text:.*|title-text: ""|' "$LB_SHARE/grub-pc/live-theme/theme.txt" >config/bootloaders/grub-pc/live-theme/theme.txt

# memtest86+: Auf HPE ProLiant (iLO-Tastatur) funktioniert nur "USB ohne EHCI".
# Daher genau ein Eintrag mit noehci statt des Standardmenüs von live-build
# (GRUB für UEFI, syslinux/isolinux für Legacy-BIOS).
cat >config/bootloaders/syslinux_common/memtest.cfg <<'EOF'
label memtest
	menu label ^Memory Diagnostic Tool (@MEMTEST_VERSION@)
	linux @MEMTEST@
	append noehci
EOF
cat >config/bootloaders/grub-pc/memtest.cfg <<'EOF'
if [ "${grub_platform}" = "efi" ] -a [ -e @MEMTEST_DIR@/memtest.efi ]; then
	menuentry "Memory Diagnostic Tool (memtest86+)" --hotkey=m {
		linux @MEMTEST_DIR@/memtest.efi noehci
	}
elif [ "${grub_platform}" = "pc" ] -a [ -e @MEMTEST_DIR@/memtest.bin ]; then
	menuentry "Memory Diagnostic Tool (memtest86+)" --hotkey=m {
		linux @MEMTEST_DIR@/memtest.bin noehci
	}
elif [ "${grub_platform}" = "pc" ] -a [ -e @MEMTEST_DIR@/memtest ]; then
	menuentry "Memory Diagnostic Tool (memtest86+)" --hotkey=m {
		linux16 @MEMTEST_DIR@/memtest noehci
	}
fi
EOF

# PassMark MemTest86 (nur UEFI, per GRUB chainloader) – optional
if [ "$MEMTEST86" != none ]; then
    log "Binde PassMark MemTest86 ein: $MEMTEST86"
    MT86_DST=config/includes.binary/memtest86
    rm -rf "$MT86_DST"; mkdir -p "$MT86_DST"
    if [ -d "$MEMTEST86" ]; then
        MT86_SRC="$MEMTEST86"
        [ -f "$MT86_SRC/BOOTX64.efi" ] || MT86_SRC="$MEMTEST86/EFI/BOOT"
        [ -f "$MT86_SRC/BOOTX64.efi" ] || die "--memtest86: BOOTX64.efi nicht gefunden in $MEMTEST86"
        cp -a "$MT86_SRC/." "$MT86_DST/"
    elif [ -f "$MEMTEST86" ]; then
        # EFI-Systempartition des USB-Images finden und ohne Mount auslesen
        start=$(sfdisk -J "$MEMTEST86" | python3 -c 'import json,sys
for p in json.load(sys.stdin)["partitiontable"]["partitions"]:
    if p["type"].upper() in ("C12A7328-F81F-11D2-BA4B-00A0C93EC93B","EF"): print(p["start"]); break')
        [ -n "$start" ] || die "--memtest86: keine EFI-Partition in $MEMTEST86"
        MTOOLS_SKIP_CHECK=1 mcopy -s -n -i "$MEMTEST86@@$((start * 512))" "::/EFI/BOOT/*" "$MT86_DST/" \
            || die "--memtest86: EFI/BOOT nicht lesbar in $MEMTEST86"
        MTOOLS_SKIP_CHECK=1 mcopy -n -i "$MEMTEST86@@$((start * 512))" ::/license.rtf "$MT86_DST/" 2>/dev/null || true
    else
        die "--memtest86: $MEMTEST86 nicht gefunden"
    fi
    # nur x86_64 wird gebraucht
    find "$MT86_DST" -maxdepth 1 \( -iname 'bootia32.efi' -o -iname 'bootaa64.efi' \) -delete
    [ -f "$MT86_DST/BOOTX64.efi" ] || die "--memtest86: BOOTX64.efi fehlt"
    cat >>config/bootloaders/grub-pc/memtest.cfg <<'EOF'
if [ "${grub_platform}" = "efi" ] -a [ -e /memtest86/BOOTX64.efi ]; then
	menuentry "MemTest86 (PassMark, nur UEFI)" --hotkey=p {
		chainloader /memtest86/BOOTX64.efi
	}
fi
EOF
fi
python3 - "$LB_SHARE/grub-pc/grub.cfg" config/bootloaders/grub-pc/grub.cfg "$MAIN_LABEL" "$NOUVEAU_APPEND" <<'EOF'
import sys
src, dst, main_label, nouveau = sys.argv[1:]
def entry(label, append, hotkey=""):
    hk = f" --hotkey={hotkey}" if hotkey else ""
    return f'menuentry "{label}"{hk} {{\n\tlinux @KERNEL_LIVE@ {append}\n\tinitrd @INITRD_LIVE@\n}}\n'
main = entry(main_label, "@APPEND_LIVE@", "l")
if nouveau:
    main += entry("Hardwaretest Live: ohne NVIDIA-Treiber (nouveau, GPUs vor Turing, weniger RAM)", nouveau, "n")
main += entry("Hardwaretest Live: mit Persistenz (USB, alle Treiber)", "@APPEND_LIVE@ persistence", "p")
utils = entry("Hardwaretest Live: Textmodus (ohne Grafik)", "@APPEND_LIVE@ hpe-live.nox", "t")
utils += entry("Hardwaretest Live: mit SSH-Server (user/live)", "@APPEND_LIVE@ hpe-live.ssh", "s")
text = open(src).read()
# eigene Einträge statt der live-build-Vorgaben ("Live system", fail-safe)
assert "@LINUX_LIVE@\n" in text
text = text.replace("@LINUX_LIVE@\n", main, 1)
marker = "\t# Firmware setup (UEFI)\n"
assert marker in text
text = text.replace(marker, "".join("\t" + l + "\n" for l in utils.rstrip("\n").split("\n")) + "\n" + marker, 1)
open(dst, "w").write(text)
EOF

# --------------------------------------------------------------- lb build ----
# Stufenweise statt „lb build“: Zwischen „lb chroot“ und „lb binary“ wird aus der
# Dateiliste des Chroot-Hooks 0800-hpe-live-nvidia-layer das Exclude-File für die
# Basis (config/rootfs/excludes) erzeugt; der Binary-Hook 0100 packt nvidia.squashfs.
log "Starte lb build (Log: $BUILD_DIR/build.log)"
set +e
{
    lb bootstrap && lb chroot && {
        NV_FILES="$BUILD_DIR/chroot/var/lib/hpe-live/nvidia-layer/files"
        if [ "$NVIDIA" != none ] && [ -s "$NV_FILES" ]; then
            mkdir -p config/rootfs
            # mksquashfs -wildcards: Pfade relativ zum chroot, Sonderzeichen maskieren
            sed -e 's|^/*||' -e '/^$/d' -e 's/[][*?\\]/\\&/g' "$NV_FILES" >config/rootfs/excludes
            echo "hpe-live: $(wc -l <config/rootfs/excludes) Dateien werden aus filesystem.squashfs ausgeschlossen (-> nvidia.squashfs)"
        elif [ "$NVIDIA" != none ]; then
            echo "hpe-live: FEHLER - $NV_FILES fehlt (Chroot-Hook 0800 nicht gelaufen?)" >&2
            false
        fi
    } && lb installer && lb binary
} 2>&1 | tee build.log
rc=${PIPESTATUS[0]}
set -e
ISO_SRC="$(ls -1 "$BUILD_DIR"/*.hybrid.iso 2>/dev/null | head -n1 || true)"
[ "$rc" -eq 0 ] && [ -n "$ISO_SRC" ] || die "lb build fehlgeschlagen (rc=$rc), siehe $BUILD_DIR/build.log"

# ------------------------------------------------- GPT-Layout (Ubuntu-Stil) ----
# live-build erzeugt ein klassisches isohybrid: MBR-Partition Typ 0x00 ab Sektor 0 mit
# darin verschachtelter EFI-Partition. Manche UEFI-Firmware (z.B. Lenovo 339C) zeigt
# so einen USB-Stick gar nicht erst im Bootmenü. Daher wird der binary-Baum mit xorriso
# neu gepackt wie Ubuntu ≥ 20.10: Schutz-MBR (0xEE) + GPT, Partition 1 = ISO9660
# (ab Sektor 64, mountbar), Partition 2 = eigenständige EFI-Systempartition.
# BIOS-Boot über isohdpfx/isolinux bleibt erhalten; dd/Etcher/Rufus/iLO funktionieren.
# Benötigt auf dem Host: xorriso, isolinux (isohdpfx.bin).
if [ -f binary/boot/grub/efi.img ] && [ -f binary/isolinux/isolinux.bin ]; then
    log "Packe ISO mit GPT-Layout neu (xorriso)"
    xorriso -as mkisofs -quiet -R -r -J -joliet-long -l -iso-level 3 \
        -V "HWTEST-LIVE${SUFFIX^^}" -A "Hardwaretest Live" -publisher "intern" \
        -isohybrid-mbr "$ISOHDPFX" -partition_offset 16 --mbr-force-bootable \
        -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e '--interval:appended_partition_2:all::' -no-emul-boot \
        -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B binary/boot/grub/efi.img \
        -appended_part_as_gpt \
        -o "$ISO_SRC.gpt" binary || die "xorriso-Repack (GPT-Layout) fehlgeschlagen"
    mv "$ISO_SRC.gpt" "$ISO_SRC"
fi

mv "$ISO_SRC" "$OUTPUT_DIR/$ISO_NAME"
# live-build schreibt die Paketliste als live-image-amd64.packages (ohne ".hybrid")
PKG_LIST="${ISO_SRC%.hybrid.iso}.packages"
[ -f "$PKG_LIST" ] || PKG_LIST="$BUILD_DIR/chroot.packages.live"
[ -f "$PKG_LIST" ] && cp "$PKG_LIST" "$OUTPUT_DIR/${ISO_NAME%.iso}.packages"
(cd "$OUTPUT_DIR" && sha256sum "$ISO_NAME" >"$ISO_NAME.sha256")
if [ -n "${SUDO_UID:-}" ]; then
    chown "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$OUTPUT_DIR" "$OUTPUT_DIR/${ISO_NAME%.iso}".* || true
fi

log "Fertig: $OUTPUT_DIR/$ISO_NAME ($(du -h "$OUTPUT_DIR/$ISO_NAME" | cut -f1), $(stat -c %s "$OUTPUT_DIR/$ISO_NAME") Bytes)"
