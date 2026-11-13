Zusätzliche Repositories für das AlmaLinux-Live-Image (alle per Release-RPM
bzw. .repo-Datei einbindbar):

| Repo | Einbindung | Liefert |
|---|---|---|
| EPEL | `dnf install epel-release` | openbox, tint2, btop, fastfetch, edac-utils, xdotool, thunar, dillo, xfce4-terminal, polkit-gnome, lightdm |
| CRB | `dnf config-manager --set-enabled crb` | gvfs, Build-Abhängigkeiten |
| ELRepo | `dnf install https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm` | zusätzliche Treiber (kmod-*) |
| OpenZFS | `dnf install https://zfsonlinux.org/epel/zfs-release-2-3.el9.noarch.rpm` | zfs, zfs-dkms (Repo `zfs`), alternativ `zfs-kmod` |
| HPE SDR | `hpe.repo` | ssacli, ssaducli, hponcfg, storcli, storcli2, amsd, ilorest |
| NVIDIA CUDA | `nvidia-cuda.repo` | nvidia-open, nvidia-driver-cuda, nvidia-persistenced, datacenter-gpu-manager-4-* |
