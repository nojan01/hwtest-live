#!/bin/bash
# Baut das AlmaLinux-9-Live-ISO "hwtest-live-alma" ohne Anaconda/lorax in einem
# privilegierten almalinux:9-Container:
#   dnf --installroot  ->  Konfiguration (Ersatz für live-config + Hooks)
#   -> flaches squashfs (LiveOS/squashfs.img)  ->  dracut dmsquash-live
#   -> hybrides ISO (BIOS: isolinux, UEFI: shim + GRUB, Secure Boot)
#
# Aufruf auf dem Host (im Repo-Verzeichnis):
#   bash alma/scripts/build_alma_live.sh [--rpms DIR] [--out DIR] [--memtest86 none|IMG|DIR]
#                                       [--version X.Y] [--nvidia] [--keep]
#   --rpms DIR      lokale RPMs (hardwaretest, JSON.Viewer, vmfs*-tools); Standard
#                   alma/rpm/out plus /tmp/alma-share, falls vorhanden
#   --out DIR       Ausgabe (ISO, .sha256, .packages); Standard alma/out
#   --memtest86     PassMark MemTest86 (UEFI) wie bei scripts/build_live_iso.sh
#   --nvidia        NVIDIA-Open-Treiber + DCGM aus dem CUDA-Repo einbauen
#   --keep          Arbeitsverzeichnis (alma/work) nicht löschen
# Braucht podman, ~20 GB Platz und Internet.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${ALMA_IMAGE:-docker.io/library/almalinux:9}"

RPM_DIRS=()
OUT_DIR="$HERE/alma/out"
WORK_DIR="$HERE/alma/work"
MEMTEST86=none
VERSION="${VERSION:-$(date +%Y.%m.%d)}"
NVIDIA="${NVIDIA:-0}"
KEEP=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rpms) RPM_DIRS+=("$(readlink -f "$2")"); shift 2 ;;
        --out) OUT_DIR="$(readlink -f "$2")"; shift 2 ;;
        --memtest86) MEMTEST86="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --nvidia) NVIDIA=1; shift ;;
        --keep) KEEP=1; shift ;;
        --in-container) shift; IN_CONTAINER=1 ;;
        *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    esac
done

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { echo "FEHLER: $*" >&2; exit 1; }

# ============================================================== Host ======
if [[ -z "${IN_CONTAINER:-}" ]]; then
    command -v podman >/dev/null || die "podman fehlt"
    [[ ${#RPM_DIRS[@]} -gt 0 ]] || {
        [[ -d "$HERE/alma/rpm/out" ]] && RPM_DIRS+=("$HERE/alma/rpm/out")
        [[ -d /tmp/alma-share ]] && RPM_DIRS+=(/tmp/alma-share)
    }
    mkdir -p "$OUT_DIR" "$WORK_DIR/rpms"
    rm -f "$WORK_DIR"/rpms/*.rpm
    for d in "${RPM_DIRS[@]}"; do
        find "$d" -maxdepth 1 -name '*.rpm' ! -name '*debuginfo*' ! -name '*debugsource*' \
            -exec cp --update=none {} "$WORK_DIR/rpms/" \;
    done
    ls "$WORK_DIR"/rpms/hardwaretest-*.rpm >/dev/null 2>&1 || die "hardwaretest-*.rpm nicht gefunden (--rpms DIR)"
    MT_ARGS=()
    if [[ "$MEMTEST86" != none ]]; then
        [[ -e "$MEMTEST86" ]] || die "--memtest86: $MEMTEST86 nicht gefunden"
        rm -rf "$WORK_DIR/memtest86"; mkdir -p "$WORK_DIR/memtest86"
        if [[ -d "$MEMTEST86" ]]; then cp -a "$MEMTEST86/." "$WORK_DIR/memtest86/"; MT_ARGS=(--memtest86 /work/memtest86)
        else cp "$MEMTEST86" "$WORK_DIR/memtest86/image.img"; MT_ARGS=(--memtest86 /work/memtest86/image.img); fi
    fi
    log "Starte Container-Build ($IMAGE), Log: $OUT_DIR/build-alma.log"
    set +e
    podman run --rm --privileged \
        -v "$HERE:/repo:Z" -v "$WORK_DIR:/work:Z" -v "$OUT_DIR:/out:Z" \
        -e VERSION="$VERSION" -e NVIDIA="$NVIDIA" \
        "$IMAGE" bash /repo/alma/scripts/build_alma_live.sh --in-container "${MT_ARGS[@]}" 2>&1 | tee "$OUT_DIR/build-alma.log"
    rc=${PIPESTATUS[0]}
    set -e
    [[ $KEEP -eq 1 ]] || podman unshare rm -rf "$WORK_DIR/rootfs" "$WORK_DIR/iso" 2>/dev/null || true
    [[ $rc -eq 0 ]] || die "Build fehlgeschlagen (rc=$rc)"
    log "Fertig:"; ls -lh "$OUT_DIR"/*.iso*
    exit 0
fi

# ========================================================== Container =====
export LC_ALL=C.UTF-8
ROOT=/work/rootfs
ISO=/work/iso
LABEL=HWTEST-ALMA
ISO_NAME="hwtest-live-alma-${VERSION}$([[ "$NVIDIA" == 1 ]] && echo -nvidia).iso"
[[ "$MEMTEST86" == none ]] || ISO_NAME="${ISO_NAME%.iso}-intern.iso"
LIVE_SRC=/repo/live/includes.chroot

log "Build-Werkzeuge im Container"
dnf -q -y install epel-release dnf-plugins-core >/dev/null
dnf -q config-manager --set-enabled crb
dnf -q -y install squashfs-tools xorriso syslinux syslinux-nonlinux dosfstools mtools \
    createrepo_c python3 util-linux file unzip >/dev/null

log "Repos (EPEL, ELRepo, OpenZFS, HPE, lokal)"
dnf -q -y install https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm >/dev/null
dnf -q -y install "https://zfsonlinux.org/epel/zfs-release-2-3$(rpm --eval '%{dist}').noarch.rpm" >/dev/null
dnf -q config-manager --set-disabled zfs && dnf -q config-manager --set-enabled zfs-kmod   # kABI-kmod statt DKMS
cp /repo/alma/repos/hpe.repo /etc/yum.repos.d/
[[ "$NVIDIA" == 1 ]] && cp /repo/alma/repos/nvidia-cuda.repo /etc/yum.repos.d/
createrepo_c -q /work/rpms
cat >/etc/yum.repos.d/hwtest-local.repo <<'EOF'
[hwtest-local]
name=Hardwaretest lokale RPMs
baseurl=file:///work/rpms
enabled=1
gpgcheck=0
EOF
dnf -q config-manager --save --setopt='*.skip_if_unavailable=1'

# -------------------------------------------------------------- Pakete ----
mapfile -t PACKAGES < <(sed -n '/^%packages/,/^%end/p' /repo/alma/packages.ks | grep -v '^%\|^#\|^-\|^$')
# Excludes aus packages.ks; iwl*-firmware bleibt (Abhängigkeit von linux-firmware)
EXCLUDES=$(sed -n '/^%packages/,/^%end/p' /repo/alma/packages.ks | grep '^-' | sed 's/^-//' | grep -v '^iwl' | tr '\n' ',' | sed 's/,$//')
# DKMS-Pfad aus der Liste nehmen: ZFS kommt als kmod-zfs (kABI-tracking)
PACKAGES=("${PACKAGES[@]/zfs-dkms/}"); PACKAGES=("${PACKAGES[@]/kernel-devel/}")
PACKAGES=("${PACKAGES[@]/kernel-headers/}"); PACKAGES=("${PACKAGES[@]/gcc/}")
PACKAGES=("${PACKAGES[@]/make/}"); PACKAGES=("${PACKAGES[@]/elfutils-libelf-devel/}")
ZFS_RELEASE="https://zfsonlinux.org/epel/zfs-release-2-3$(rpm --eval '%{dist}').noarch.rpm"
PACKAGES+=(zfs kmod-zfs hardwaretest vmfs-tools vmfs6-tools
    epel-release elrepo-release "$ZFS_RELEASE" shim-x64 grub2-efi-x64 grub2-tools efibootmgr
    ImageMagick)
# NVIDIA: das CUDA-rhel9-Repo liefert fuer nvidia-open nur ein DKMS-Kmod, daher
# Build-Werkzeuge mitinstallieren (werden nach dem Modulbau wieder entfernt).
NVIDIA_BUILD_DEPS=(kernel-devel kernel-headers gcc make dkms elfutils-libelf-devel)
[[ "$NVIDIA" == 1 ]] && PACKAGES+=(nvidia-open nvidia-driver-cuda nvidia-persistenced nvidia-modprobe
    datacenter-gpu-manager-4-core datacenter-gpu-manager-4-cuda13 "${NVIDIA_BUILD_DEPS[@]}")

log "Basissystem nach $ROOT installieren (${#PACKAGES[@]} Pakete)"
rm -rf "$ROOT" "$ISO"; mkdir -p "$ROOT"/{dev,proc,sys,run,etc/rpm}
echo '%_install_langs de:en' >"$ROOT/etc/rpm/macros.image-language-conf"
mount --bind /dev "$ROOT/dev"; mount -t proc proc "$ROOT/proc"; mount -t sysfs sys "$ROOT/sys"
trap 'umount -l "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" 2>/dev/null || true' EXIT
DNF_ROOT=(dnf -y --installroot="$ROOT" --releasever=9 --setopt=reposdir=/etc/yum.repos.d
    --setopt=install_weak_deps=False --setopt=tsflags=nodocs --nogpgcheck
    --setopt=cachedir=/work/dnf-cache --exclude="$EXCLUDES")
mapfile -t PACKAGES < <(printf '%s\n' "${PACKAGES[@]}" | grep -v '^$')
# Erst das Dateisystem-Geruest (/bin -> usr/bin) anlegen: Pakete mit Datei-Abhaengigkeit
# auf /bin/sh (z. B. nvidia-open) scheitern sonst im leeren Installroot an
# "transaction check vs depsolve".
"${DNF_ROOT[@]}" install filesystem bash coreutils >/dev/null
"${DNF_ROOT[@]}" install "${PACKAGES[@]}"
KVER=$(ls "$ROOT/lib/modules" | sort -V | tail -n1)
echo "Live-Kernel: $KVER"
[[ -f "$ROOT/lib/modules/$KVER/extra/zfs/zfs.ko" || -n "$(find "$ROOT/lib/modules/$KVER" -name 'zfs.ko*' | head -1)" ]] \
    || die "kmod-zfs passt nicht zu Kernel $KVER"

if [[ "$NVIDIA" == 1 ]]; then
    log "NVIDIA-Kernelmodul per DKMS fuer $KVER bauen"
    [[ -d "$ROOT/usr/src/kernels/$KVER" ]] || die "kernel-devel passt nicht zu Kernel $KVER"
    chroot "$ROOT" dkms autoinstall -k "$KVER" || die "DKMS-Bau des NVIDIA-Moduls fehlgeschlagen"
    find "$ROOT/lib/modules/$KVER" -name 'nvidia.ko*' | grep -q . || die "nvidia.ko fehlt nach DKMS-Bau"
    echo "NVIDIA-Modul: $(chroot "$ROOT" dkms status | grep -i nvidia | head -n1)"
    log "Build-Werkzeuge wieder entfernen"
    # Nicht per dnf: kmod-nvidia-open-dkms haengt von gcc/make/kernel-devel ab, dnf wuerde
    # die gesamte NVIDIA-Kette (inkl. nvidia-smi und Modul) mit entfernen.
    for p in kernel-devel-matched kernel-devel kernel-headers gcc-c++ gcc cpp glibc-devel glibc-headers \
             make elfutils-libelf-devel libxcrypt-devel; do
        rpm --root="$ROOT" -q "$p" >/dev/null 2>&1 && rpm --root="$ROOT" -e --nodeps "$p"
    done
    find "$ROOT/lib/modules/$KVER" -name 'nvidia.ko*' | grep -q . || die "nvidia.ko nach Aufraeumen verschwunden"
    [[ -x "$ROOT/usr/bin/nvidia-smi" ]] || die "nvidia-smi fehlt"
    rm -rf "$ROOT/var/lib/dkms/nvidia-open"/*/build "$ROOT/usr/src/kernels"
fi

# ---------------------------------------------------- Konfiguration ----
log "Live-Konfiguration (Ersatz für live-config und Hooks)"
cp -a "$LIVE_SRC/." "$ROOT/"
rm -rf "$ROOT/etc/live"
chmod +x "$ROOT"/usr/local/bin/* "$ROOT"/usr/local/sbin/* "$ROOT"/usr/local/lib/hpe-live/clean-exec

# Debian-Spezifika anpassen
# Alma-eigene Dateien (hpe-live-browser: GTK3/WebKitGTK-Berichtsbrowser statt Firefox)
cp -a /repo/alma/live/. "$ROOT/"
chmod +x "$ROOT"/usr/local/bin/*
# Hardwaretest sucht fuer HTML- und JSON-Berichte nach "firefox": Wrapper auf den
# kleinen Browser, der JSON-Dateien als Baum darstellt (wie die Firefox-JSON-Ansicht).
cat >"$ROOT/usr/local/bin/firefox" <<'EOF'
#!/bin/sh
# Aus Hardwaretest (PyInstaller-Bundle) gestartet: Bibliothekspfade bereinigen.
. /usr/local/lib/hpe-live/clean-env.sh
exec /usr/local/bin/hpe-live-browser "$@"
EOF
sed -i 's/^Name=.*/Name=Webbrowser (WebKitGTK)/' "$ROOT/usr/share/applications/hpe-browser.desktop"
# Kein JSON Viewer (Tauri laeuft unter EL9 nicht): JSON-Reports zeigt hpe-live-browser.
rm -f "$ROOT"/usr/local/bin/app "$ROOT"/usr/local/bin/hpe-live-json-viewer \
    "$ROOT"/usr/share/applications/hpe-json-viewer.desktop "$ROOT"/usr/local/share/applications/hpe-json-viewer.desktop
sed -i '/hpe-live-json-viewer\|JSON Viewer/d' "$ROOT/etc/skel/.config/openbox/menu.xml"
sed -i '/hpe-json-viewer.desktop/d' "$ROOT/etc/skel/.config/tint2/tint2rc"
# Debian-Alias x-terminal-emulator (Openbox-Menue, tint2-Starter, Hardwaretest):
# Wrapper fuer xfce4-terminal, der die xterm-Optionen -T/-hold/-e uebersetzt.
cat >"$ROOT/usr/local/bin/x-terminal-emulator" <<'EOF'
#!/bin/bash
# x-terminal-emulator -> xfce4-terminal: -T TITEL, -hold, -e BEFEHL [ARG...]
. /usr/local/lib/hpe-live/clean-env.sh
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -T|-title|--title) args+=("--title=$2"); shift 2 ;;
        -hold|--hold|-H) args+=(--hold); shift ;;
        -e|-x)
            shift
            # ein einzelnes Argument ist eine komplette Befehlszeile (xterm -e "cmd arg"),
            # mehrere Argumente sind Befehl + Parameter.
            if [[ $# -eq 1 ]]; then
                exec /usr/bin/xfce4-terminal "${args[@]}" -e "$1"
            fi
            exec /usr/bin/xfce4-terminal "${args[@]}" -x "$@"
            ;;
        *) args+=("$1"); shift ;;
    esac
done
exec /usr/bin/xfce4-terminal "${args[@]}"
EOF
chmod +x "$ROOT/usr/local/bin/x-terminal-emulator"
sed -i 's|<command>pcmanfm</command>|<command>thunar</command>|' "$ROOT/etc/skel/.config/openbox/menu.xml"
sed -i 's/^Icon=xterm$/Icon=org.xfce.terminal/' "$ROOT/usr/local/share/applications/hpe-terminal.desktop"
sed -i 's/ssh\.service/sshd.service/g; s/ssh\.socket/sshd.socket/g' "$ROOT/usr/local/sbin/hpe-live-ssh"
sed -i 's/subject.isInGroup("sudo")/subject.isInGroup("wheel")/' "$ROOT/etc/polkit-1/rules.d/49-hpe-live-nopasswd.rules"
sed -i 's|^feh .*|/usr/local/bin/hpe-live-wallpaper \&|; s|^lxpolkit .*|/usr/libexec/polkit-gnome-authentication-agent-1 \&|' \
    "$ROOT/etc/skel/.config/openbox/autostart"
cat >"$ROOT/usr/local/bin/hpe-live-wallpaper" <<'EOF'
#!/bin/sh
# Hintergrundbild passend zur Bildschirmgroesse (Ersatz fuer feh --bg-max)
IMG=/usr/share/backgrounds/hpe-live/testsystem.png
GEOM=$(xrandr --current 2>/dev/null | sed -n 's/.*current \([0-9]*\) x \([0-9]*\).*/\1x\2/p' | head -n1)
[ -n "$GEOM" ] || GEOM=1024x768
OUT=/tmp/hpe-live-wallpaper-$GEOM.png
[ -f "$OUT" ] || convert "$IMG" -resize "$GEOM" -background '#1f2a36' -gravity center -extent "$GEOM" "$OUT" 2>/dev/null || OUT=$IMG
display -window root "$OUT" 2>/dev/null || true
EOF
chmod +x "$ROOT/usr/local/bin/hpe-live-wallpaper"
sed -i 's/^SELINUX=.*/SELINUX=disabled/' "$ROOT/etc/selinux/config" 2>/dev/null || true

# StorCLI liegt unter /opt/MegaRAID - in den PATH verlinken (wie Hook 0600)
for f in /opt/MegaRAID/storcli/storcli64 /opt/MegaRAID/storcli2/storcli2; do
    [[ -x "$ROOT$f" ]] && ln -sf "$f" "$ROOT/usr/local/sbin/$(basename "$f")"
done
rm -f "$ROOT"/opt/MegaRAID/storcli/storcli "$ROOT"/opt/MegaRAID/storcli/install.log

cat >"$ROOT/etc/hpe-live-release" <<EOF
HPE_LIVE_DISTRO=almalinux9
HPE_LIVE_VERSION=$VERSION
HPE_LIVE_KERNEL=$KVER
HPE_LIVE_NVIDIA=$([[ "$NVIDIA" == 1 ]] && echo dcgm || echo none)
EOF

# Hostname, Sprache, Tastatur, Zeitzone
echo hwtest-live >"$ROOT/etc/hostname"
echo 'LANG=de_DE.UTF-8' >"$ROOT/etc/locale.conf"
printf 'KEYMAP=de\nFONT=eurlatgr\n' >"$ROOT/etc/vconsole.conf"
mkdir -p "$ROOT/etc/X11/xorg.conf.d"
cat >"$ROOT/etc/X11/xorg.conf.d/00-keyboard.conf" <<'EOF'
Section "InputClass"
	Identifier "system-keyboard"
	MatchIsKeyboard "on"
	Option "XkbLayout" "de"
	Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF
ln -sf ../usr/share/zoneinfo/Europe/Berlin "$ROOT/etc/localtime"
# Xorg auch ohne KMS (iLO/Matrox, fbdev) als root starten dürfen
cat >"$ROOT/etc/X11/Xwrapper.config" <<'EOF'
allowed_users = anybody
needs_root_rights = yes
EOF

# btop/htop maximiert (iLO 1024x768), wie Hook 0600
if [[ -f "$ROOT/etc/xdg/openbox/rc.xml" ]] && ! grep -q 'title="btop"' "$ROOT/etc/xdg/openbox/rc.xml"; then
    sed -i 's|</applications>|  <application class="XTerm" title="btop"><maximized>yes</maximized></application>\n  <application class="XTerm" title="htop"><maximized>yes</maximized></application>\n</applications>|' \
        "$ROOT/etc/xdg/openbox/rc.xml"
fi

# Live-Benutzer user/live (wie live-config), sudo ohne Passwort, Autologin tty1
chroot "$ROOT" useradd -m -s /bin/bash -G wheel,adm,systemd-journal,audio,video,dialout,disk user
echo 'user:live' | chroot "$ROOT" chpasswd
echo 'root:live' | chroot "$ROOT" chpasswd
echo 'user ALL=(ALL) NOPASSWD: ALL' >"$ROOT/etc/sudoers.d/live-user"; chmod 440 "$ROOT/etc/sudoers.d/live-user"
# EL-sudo kennt /usr/local/{sbin,bin} nicht: "sudo hpe-live-check" usw. aus dem Menue
printf 'Defaults secure_path = /usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\n' \
    >"$ROOT/etc/sudoers.d/hpe-live-secure-path"; chmod 440 "$ROOT/etc/sudoers.d/hpe-live-secure-path"
touch "$ROOT/etc/fstab"
mkdir -p "$ROOT/etc/systemd/system/getty@tty1.service.d"
cat >"$ROOT/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin user --noclear %I $TERM
EOF
mkdir -p "$ROOT/home/user/Downloads"; chroot "$ROOT" chown -R user:user /home/user

# Dienste
chroot "$ROOT" systemctl set-default multi-user.target
chroot "$ROOT" systemctl enable NetworkManager chronyd hpe-live-boot.service hpe-live-zram.service >/dev/null 2>&1
chroot "$ROOT" systemctl disable sshd firewalld >/dev/null 2>&1 || true
chroot "$ROOT" systemctl mask systemd-remount-fs.service >/dev/null 2>&1 || true
chroot "$ROOT" systemctl enable rasdaemon amsd >/dev/null 2>&1 || true
# ZFS: Pool-Import nicht automatisch (Live-System fasst Platten nicht an)
chroot "$ROOT" systemctl disable zfs-import-cache zfs-import-scan zfs-mount zfs-share zfs-zed >/dev/null 2>&1 || true

for hook in 0610-hpe-live-keys 0650-hpe-live-clean-wrappers \
            0660-hardwaretest-no-update 0700-hpe-live-slim; do
    log "Gemeinsamer Hook: $hook"
    cp "/repo/live/hooks/live/$hook.hook.chroot" "$ROOT/tmp/hook"
    chroot "$ROOT" sh /tmp/hook || die "Hook $hook fehlgeschlagen"
    rm -f "$ROOT/tmp/hook"
done

chroot "$ROOT" gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
chroot "$ROOT" update-desktop-database -q 2>/dev/null || true
chroot "$ROOT" update-mime-database /usr/share/mime >/dev/null 2>&1 || true
chroot "$ROOT" depmod -a "$KVER"

# --------------------------------------------------------- Initramfs ----
log "dracut Live-Initramfs"
# systemd begrenzt /run im Initramfs auf 20 % des RAM; rd.live.ram kopiert das
# squashfs aber nach /run/initramfs -> vorher vergroessern (sonst abgeschnitten).
cat >"$ROOT/tmp/hpe-live-run-size.sh" <<'EOF'
#!/bin/sh
mount -o remount,size=80% /run 2>/dev/null || true
EOF
chmod +x "$ROOT/tmp/hpe-live-run-size.sh"
chroot "$ROOT" dracut --force --no-hostonly --xz --nomdadmconf --nolvmconf \
    --add "dmsquash-live livenet" --omit "plymouth" \
    --add-drivers "squashfs overlay loop" \
    --include /tmp/hpe-live-run-size.sh /lib/dracut/hooks/cmdline/05-hpe-live-run-size.sh \
    /boot/initramfs-live.img "$KVER"
rm -f "$ROOT/tmp/hpe-live-run-size.sh"
VMLINUZ="$ROOT/boot/vmlinuz-$KVER"
[[ -f "$VMLINUZ" ]] || VMLINUZ="$ROOT/lib/modules/$KVER/vmlinuz"

# ----------------------------------------------------------- Aufräumen ----
log "Image verschlanken"
"${DNF_ROOT[@]}" clean all >/dev/null 2>&1 || true
rm -rf "$ROOT"/var/cache/dnf/* "$ROOT"/var/lib/dnf/history* "$ROOT"/var/log/*.log "$ROOT"/tmp/* \
    "$ROOT"/boot/initramfs-"$KVER".img "$ROOT"/boot/initramfs-0-rescue-* "$ROOT"/boot/vmlinuz-0-rescue-* \
    "$ROOT"/usr/share/doc "$ROOT"/usr/share/man "$ROOT"/usr/share/info
# Firmware: nur, was Server und Consumer-GPUs brauchen (spart ~600 MB)
for d in qcom mediatek ti-connectivity brcm/*.txt liquidio netronome mrvl/prestera cypress ath10k ath11k ath12k \
         wfx mellanox/mlxsw_spectrum* dvb* v4l* ti-keystone imx moxa ueagle-atm meson cnm cirrus; do
    rm -rf "$ROOT"/usr/lib/firmware/$d 2>/dev/null || true
done
rpm --root="$ROOT" -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n' | sort >"/out/${ISO_NAME%.iso}.packages"

# ---------------------------------------------------- Memtest86+ (frei) ----
# Memtest86+ ab 6.x/9.x ist ein "unified" bzImage: bootet per isolinux (BIOS) und
# GRUB linuxefi (UEFI). EL9 liefert nur das alte 5.31 (BIOS-only), daher Download
# der GPL-Binaries von memtest.org (im Work-Verzeichnis gecacht).
MT86P_VER="${MT86P_VER:-9.00}"
MT86P_SHA256="${MT86P_SHA256:-7b2e294c5f30ddc8a01bbfce0dba7370765a867b745e0494ff811de4463eeb5d}"
MT86P_DIR=/work/memtest86plus
MT86P_BIN="$MT86P_DIR/mt86p_${MT86P_VER//./}_x86_64"
if [[ ! -f "$MT86P_BIN" ]]; then
    log "Memtest86+ $MT86P_VER herunterladen"
    mkdir -p "$MT86P_DIR"
    curl -fsSL -o "$MT86P_DIR/mt86plus.zip" "https://www.memtest.org/download/v${MT86P_VER}/mt86plus_${MT86P_VER}.binaries.zip" \
        || die "Memtest86+ Download fehlgeschlagen"
    echo "$MT86P_SHA256  $MT86P_DIR/mt86plus.zip" | sha256sum -c --quiet - || die "Memtest86+ ZIP: SHA256 stimmt nicht"
    (cd "$MT86P_DIR" && unzip -o -q mt86plus.zip)
    [[ -f "$MT86P_BIN" ]] || die "Memtest86+ Binary $MT86P_BIN fehlt im ZIP"
fi
# Im Live-System ablegen (Hardwaretest prueft /boot/memtest86+x64.bin)
install -m 0644 "$MT86P_BIN" "$ROOT/boot/memtest86+x64.bin"
ln -sf memtest86+x64.bin "$ROOT/boot/memtest86+x64.efi"

log "Systemcheck und Hardwaretest-Selbsttest"
chroot "$ROOT" /usr/local/sbin/hpe-live-check --build || die "Systemcheck fehlgeschlagen"
chroot "$ROOT" /opt/hardwaretest/hardwaretest --self-check || die "Hardwaretest-Selbsttest fehlgeschlagen"
umount -l "$ROOT/dev" "$ROOT/proc" "$ROOT/sys"; trap - EXIT
echo "Image-Größe: $(du -sh "$ROOT" | cut -f1)"

# ---------------------------------------------------------------- ISO ----
log "ISO-Baum und Bootloader"
mkdir -p "$ISO"/{LiveOS,isolinux,EFI/BOOT,images,boot/grub2}
cp "$VMLINUZ" "$ISO/isolinux/vmlinuz"
cp "$ROOT/boot/initramfs-live.img" "$ISO/isolinux/initrd.img"
cp "$ROOT/boot/memtest86+x64.bin" "$ISO/isolinux/memtest"

APPEND="root=live:CDLABEL=$LABEL rd.live.image rd.live.ram=1 rd.live.overlay.overlayfs=1 selinux=0 console=ttyS0,115200n8 console=tty0 iomem=relaxed"
[[ "$NVIDIA" == 1 ]] && APPEND+=" modprobe.blacklist=nouveau iommu=pt"
# Persistenz: Overlay auf Partition mit Label "persistence" (overlayfs, Verzeichnis)
PERSIST="root=live:CDLABEL=$LABEL rd.live.image rd.live.overlay=LABEL=persistence rd.live.overlay.overlayfs=1 selinux=0 console=ttyS0,115200n8 console=tty0 iomem=relaxed"
[[ "$NVIDIA" == 1 ]] && PERSIST+=" modprobe.blacklist=nouveau iommu=pt"

# --- BIOS: isolinux
cp /usr/share/syslinux/{isolinux.bin,ldlinux.c32,libcom32.c32,libutil.c32,vesamenu.c32,menu.c32} "$ISO/isolinux/"
cat >"$ISO/isolinux/isolinux.cfg" <<EOF
default vesamenu.c32
timeout 100
menu title Hardwaretest Live (AlmaLinux 9) $VERSION
label live
  menu label ^Hardwaretest Live (RAM, alle Treiber)
  menu default
  kernel vmlinuz
  append initrd=initrd.img $APPEND
label persist
  menu label Hardwaretest Live: mit ^Persistenz (USB)
  kernel vmlinuz
  append initrd=initrd.img $PERSIST
label text
  menu label Hardwaretest Live: ^Textmodus (ohne Grafik)
  kernel vmlinuz
  append initrd=initrd.img $APPEND hpe-live.nox
label ssh
  menu label Hardwaretest Live: mit ^SSH-Server (user/live)
  kernel vmlinuz
  append initrd=initrd.img $APPEND hpe-live.ssh
EOF
cat >>"$ISO/isolinux/isolinux.cfg" <<EOF
label memtest
  menu label ^Memtest86+ $MT86P_VER (frei)
  kernel memtest
EOF

# --- UEFI: shim + GRUB (signiert), grub.cfg in EFI/BOOT
cp "$ROOT/boot/efi/EFI/almalinux/shimx64.efi" "$ISO/EFI/BOOT/BOOTX64.EFI"
cp "$ROOT/boot/efi/EFI/almalinux/grubx64.efi" "$ISO/EFI/BOOT/grubx64.efi"
cp "$ROOT/boot/efi/EFI/almalinux/mmx64.efi" "$ISO/EFI/BOOT/" 2>/dev/null || true
cat >"$ISO/EFI/BOOT/grub.cfg" <<EOF
set default=0
set timeout=10
search --no-floppy --set=root -l '$LABEL'
menuentry 'Hardwaretest Live (RAM, alle Treiber)' --class almalinux --hotkey=l {
	linuxefi /isolinux/vmlinuz $APPEND
	initrdefi /isolinux/initrd.img
}
menuentry 'Hardwaretest Live: mit Persistenz (USB)' --hotkey=p {
	linuxefi /isolinux/vmlinuz $PERSIST
	initrdefi /isolinux/initrd.img
}
menuentry 'Hardwaretest Live: Textmodus (ohne Grafik)' --hotkey=t {
	linuxefi /isolinux/vmlinuz $APPEND hpe-live.nox
	initrdefi /isolinux/initrd.img
}
menuentry 'Hardwaretest Live: mit SSH-Server (user/live)' --hotkey=s {
	linuxefi /isolinux/vmlinuz $APPEND hpe-live.ssh
	initrdefi /isolinux/initrd.img
}
EOF
cat >>"$ISO/EFI/BOOT/grub.cfg" <<EOF
menuentry 'Memtest86+ $MT86P_VER (frei, ohne Secure Boot)' --hotkey=m {
	linuxefi /isolinux/memtest
}
EOF
# PassMark MemTest86 (UEFI) optional, wie Trixie-Build
MT86="$MEMTEST86"
if [[ "$MT86" != none ]]; then
    log "PassMark MemTest86 einbinden: $MT86"
    mkdir -p "$ISO/memtest86"
    if [[ -d "$MT86" ]]; then
        src="$MT86"; [[ -f "$src/BOOTX64.efi" ]] || src="$MT86/EFI/BOOT"
        cp -a "$src/." "$ISO/memtest86/"
    else
        start=$(sfdisk -J "$MT86" | python3 -c 'import json,sys
for p in json.load(sys.stdin)["partitiontable"]["partitions"]:
    if p["type"].upper() in ("C12A7328-F81F-11D2-BA4B-00A0C93EC93B","EF"): print(p["start"]); break')
        [[ -n "$start" ]] || die "--memtest86: keine EFI-Partition"
        MTOOLS_SKIP_CHECK=1 mcopy -s -n -i "$MT86@@$((start * 512))" "::/EFI/BOOT/*" "$ISO/memtest86/"
    fi
    find "$ISO/memtest86" -maxdepth 1 \( -iname 'bootia32.efi' -o -iname 'bootaa64.efi' \) -delete
    [[ -f "$ISO/memtest86/BOOTX64.efi" ]] || die "--memtest86: BOOTX64.efi fehlt"
    cat >>"$ISO/EFI/BOOT/grub.cfg" <<'EOF'
menuentry 'MemTest86 (PassMark, nur UEFI)' --hotkey=k {
	chainloader /memtest86/BOOTX64.efi
}
EOF
fi
cat >>"$ISO/EFI/BOOT/grub.cfg" <<'EOF'
menuentry 'UEFI Firmware-Setup' --hotkey=f {
	fwsetup
}
EOF
# efiboot.img (FAT) für El Torito
EFI_SIZE_KB=$(( ($(du -sk "$ISO/EFI" | cut -f1) + 2048) ))
rm -f "$ISO/images/efiboot.img"
mkfs.vfat -C -n EFIBOOT "$ISO/images/efiboot.img" "$EFI_SIZE_KB" >/dev/null
mmd -i "$ISO/images/efiboot.img" ::/EFI ::/EFI/BOOT
mcopy -i "$ISO/images/efiboot.img" "$ISO"/EFI/BOOT/* ::/EFI/BOOT/

# --- squashfs (flach, dracut dmsquash-live erkennt es und nutzt overlayfs)
log "squashfs erzeugen"
mksquashfs "$ROOT" "$ISO/LiveOS/squashfs.img" -comp xz -b 1M -Xbcj x86 -noappend -quiet -no-progress \
    -wildcards -e 'boot/initramfs-*' 'boot/vmlinuz-*' 'usr/lib/modules/*/vmlinuz' \
    boot/efi 'var/cache/dnf/*'

log "ISO schreiben: $ISO_NAME"
xorriso -as mkisofs -quiet -o "/out/$ISO_NAME" -V "$LABEL" -J -R -joliet-long \
    -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin -partition_offset 16 --mbr-force-bootable \
    -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot -e '--interval:appended_partition_2:all::' -no-emul-boot \
    -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "$ISO/images/efiboot.img" \
    -appended_part_as_gpt \
    "$ISO"
(cd /out && sha256sum "$ISO_NAME" >"$ISO_NAME.sha256")
ls -lh "/out/$ISO_NAME"
