# Paketliste für das AlmaLinux-9-Live-Image (hwtest-live-alma).
# Kickstart-%packages-Syntax; Gegenstück zu live/package-lists/*.list.chroot.
# Alle Pakete wurden am 2026-11-05 mit alma/scripts/check_packages.sh gegen
# BaseOS/AppStream/CRB/EPEL/ELRepo/OpenZFS/HPE-SDR/NVIDIA-CUDA geprüft.
#
# Nicht paketiert (müssen wie beim Trixie-Image selbst gebaut/eingebunden werden):
#   vmfs-tools, vmfs6-tools   -> eigene RPMs: alma/scripts/build_vmfs_rpms.sh
#   opendcdiag                -> im Hardwaretest-RPM enthalten
#   surf, pcmanfm, feh        -> Ersatz: hpe-live-browser (eigenes Python/WebKitGTK-Skript
#                                in alma/live/usr/local/bin), thunar (EPEL),
#                                Hintergrund per xfdesktop/xsetroot aus xorg-x11-server-utils
#   lxpolkit                  -> polkit-gnome (EPEL)
#   hardwaretest             -> aktuelles lokales RPM aus Ubuntu-Stresstest

%packages --excludedocs --inst-langs=de:en

# --- 10-base -------------------------------------------------------------
@core
kernel
kernel-modules-extra
dracut-live
dracut-config-generic
ca-certificates
sudo
zip
unzip
less
nano
bash-completion
curl
kmod
glibc-langpack-de
glibc-langpack-en
kbd
NetworkManager
iproute
iputils
ethtool
mstflint
openssh-server
chrony
polkit
dbus

# --- 20-desktop (Openbox + tint2 wie im Trixie-Image) ---------------------
xorg-x11-server-Xorg
xorg-x11-drv-libinput
xorg-x11-drv-evdev
xorg-x11-drv-fbdev
xorg-x11-drv-vmware
xorg-x11-xinit
xorg-x11-server-utils
xorg-x11-xauth
setxkbmap
xkbcomp
xdotool
wmctrl
openbox
tint2
xterm
xfce4-terminal
# Berichtsbrowser hpe-live-browser (GTK3 + WebKitGTK, zeigt HTML und JSON als Baum)
webkit2gtk3
python3-gobject
gtk3
glib-networking
polkit-gnome
network-manager-applet
nm-connection-editor
dejavu-sans-fonts
dejavu-sans-mono-fonts
thunar
gvfs
udisks2
desktop-file-utils
xdg-utils

# --- 30-hwtools ----------------------------------------------------------
btop
htop
stress-ng
fio
fio-engine-libaio
iperf3
nvme-cli
libnvme
smartmontools
memtest86+
hdparm
sg3_utils
mdadm
lvm2
util-linux
e2fsprogs
lshw
pciutils
usbutils
dmidecode
lm_sensors
edac-utils
fastfetch
rasdaemon
ipmitool
jq
zfs
zfs-dkms
kernel-devel
kernel-headers
gcc
make
elfutils-libelf-devel
xfsprogs
btrfs-progs
dosfstools
squashfs-tools
ntfs-3g
exfatprogs
gdisk
testdisk
gparted

# --- 40-hpe (Repo hpe-mcp / hpe-ilorest) ---------------------------------
ssacli
ssaducli
hponcfg
storcli
storcli2
ilorest
amsd

# --- 50-firmware (ein Paket statt firmware-*) -----------------------------
linux-firmware

# --- 55-gpu --------------------------------------------------------------
mesa-dri-drivers
mesa-libGL
mesa-libEGL
mesa-vulkan-drivers
vulkan-loader
vulkan-tools
python3

# --- Hardwaretest-Laufzeit (Requires des RPM) -----------------------------
libxcb
xcb-util-cursor
xcb-util-wm
xcb-util-keysyms
xcb-util-renderutil
libxkbcommon-x11
libzstd
fuse
fuse-libs
fuse3

# --- nicht nötig im RAM-System ------------------------------------------
-plymouth*
-firewalld
-iwl*-firmware
-dnf-plugin-spacewalk
-rhn*
-cockpit*

%end

# Optionaler neuerer Kernel für aktuelle Consumer-GPUs (Radeon RX 7000/9000, Intel Arc
# Battlemage), Repo elrepo-kernel: statt kernel/kernel-modules-extra/kernel-devel/kernel-headers
#   kernel-ml  kernel-ml-modules-extra  kernel-ml-devel  kernel-ml-headers
# ZFS dann zwingend per zfs-dkms (kein kmod-zfs für kernel-ml), NVIDIA-Treiber per DKMS.

# Optionales NVIDIA-/DCGM-Profil (Repo cuda-rhel9-x86_64), Gegenstück zu live/optional/nvidia + dcgm:
#   nvidia-open  nvidia-driver-cuda  nvidia-persistenced  nvidia-modprobe
#   datacenter-gpu-manager-4-core  datacenter-gpu-manager-4-cuda13
