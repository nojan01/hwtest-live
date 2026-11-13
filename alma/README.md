# hwtest-live für AlmaLinux 9

Ziel: das gleiche Werkzeug-Live-System wie `hwtest-live` (Debian Trixie), aber auf
AlmaLinux-9-Basis mit RPM-Paketen. Oberfläche bleibt **Openbox + tint2** (beides in EPEL).

## Stand (2026-11-11)

| Baustein | Status |
|---|---|
| Paketliste (`packages.ks`) | gemeinsame Diagnosewerkzeuge einschließlich gparted; Verfügbarkeit mit `scripts/check_packages.sh --nvidia` prüfen |
| Zusatz-Repos (`repos/`) | EPEL, CRB, ELRepo, OpenZFS, HPE SDR (MCP Alma 9 + ilorest), NVIDIA CUDA rhel9 |
| Hardwaretest | aktuelles RPM aus Release v0.3.14 (EL9-Container-Build), einschließlich ProLiant-Protokollverwaltung und verbesserter Netzwerkdiagnose |
| JSON Viewer | **entfällt** – Tauri läuft unter EL9 nicht; JSON-Reports zeigt `hpe-live-browser` als aufklappbaren Baum |
| vmfs-tools / vmfs6-tools | **fertig** – eigene RPMs aus den Debian-Quellen (`rpm/*.spec`, `scripts/build_vmfs_rpms.sh` → `rpm/out/`) |
| OpenDCDiag | **enthalten** – wird im Hardwaretest-RPM mitgeliefert (`/opt/hardwaretest/_internal/vendor/opendcdiag/`, EL9-Container-Build) |
| Image-Bau | **fertig** – 0.3.14 mit `scripts/build_alma_live.sh` (Container, ohne Anaconda); BIOS + UEFI in QEMU getestet, Systemcheck jeweils `rc=0` |
| MemTest86 (PassMark Free/Pro) | distributionsunabhängig: UEFI-Binary `BOOTX64.efi` + `mt86.cfg` per GRUB-`chainloader` ins Bootmenü, Extraktion aus `memtest86-pro-usb.img` wie in `scripts/build_live_iso.sh` (`--memtest86`); proprietär, nur zur Build-Zeit einbinden |
| Consumer-GPUs | AMD/Intel über Kernel + mesa-dri/vulkan-drivers + linux-firmware; GeForce ab Turing über `nvidia-open`; ältere GeForce brauchen `nvidia-driver` (Legacy); sehr neue Karten ggf. `kernel-ml` (ELRepo, in `packages.ks` vermerkt) |
| Aktuelle Live-Funktionen | gparted, `iomem=relaxed`, Sonderzeichen ohne AltGr (`hpe-live-keys`), bereinigte Programmstarter und deaktivierte Update-Prüfung im Live-System |
| Verkleinerung | gemeinsamer Slim-Hook: ungenutzte DCGM-/NVIDIA-Bibliotheken, WLAN-/Sound-/Media-Module, Firmware und Übersetzungen entfernen; Grafik-Abhängigkeiten einschließlich rc-core erhalten; Kernel-/Initramfs-Duplikate nicht in Squashfs aufnehmen |
| USB-Bootlayout | GPT mit eigenständiger EFI-Systempartition, wie beim aktuellen Debian-Image |

Gebaut wird eine **öffentliche Variante ohne zusätzliche proprietäre NIC-/HBA-Werkzeuge
und ohne MemTest86 Pro**. Die Hardwaretest-Netzwerkdiagnose nutzt die zusätzlichen
Herstellerprogramme nur, wenn der Administrator sie selbst nachinstalliert.

Das NVIDIA-Image mit Hardwaretest 0.3.14 ist **1.681.121.280 Byte (1,68 GB)** groß.
Gegenüber dem bisherigen Alma-Image 0.3.5 mit 2.231.369.728 Byte spart es
550.248.448 Byte, also **24,7 %**. CUDA, NVML, cuBLAS und die Standard-DCGM-Diagnoseplugins
bleiben enthalten; Kernel und Initramfs liegen weiterhin außerhalb des Squashfs.

## Paket-Entsprechungen Trixie → Alma

| Trixie | Alma 9 | Repo |
|---|---|---|
| surf (+ `firefox`-Wrapper) | `hpe-live-browser` (eigenes GTK3/WebKitGTK-Skript in `alma/live/usr/local/bin`, HTML + JSON-Baum; `firefox`-Wrapper zeigt darauf) | webkit2gtk3, python3-gobject (AppStream) |
| pcmanfm | thunar | EPEL |
| lxpolkit | polkit-gnome | EPEL |
| feh (Hintergrund) | `hpe-live-wallpaper` (ImageMagick `convert`/`display -window root`) | EPEL |
| firmware-* (6 Pakete) | linux-firmware | BaseOS |
| zfsutils-linux + zfs-dkms | zfs + kmod-zfs (kABI-tracking, Repo `zfs-kmod`; kein Compiler im Image) | OpenZFS |
| libnvme1t64 | libnvme | BaseOS |
| sg3-utils, lm-sensors | sg3_utils, lm_sensors | BaseOS/AppStream |
| memtest86+ | memtest86+ (nur BIOS-Boot) | AppStream |
| systemd-timesyncd | chrony | BaseOS |
| HPE MCP (Debian-Repo) | HPE MCP `mcp/Alma/9` | HPE SDR |
| ilorest (.deb in includes) | ilorest | HPE SDR `ilorest/rhel/9` |
| nvidia-driver-cuda (debian13-Repo) | nvidia-open + nvidia-driver-cuda | CUDA rhel9 |
| datacenter-gpu-manager-4-cuda13 | gleichnamig | CUDA rhel9 |
| xserver-xorg-video-vesa | entfällt (modesetting/fbdev) | – |

## Image-Bau

```bash
bash alma/scripts/build_alma_live.sh --version 0.3.14 --nvidia \
  --rpms /pfad/zum/Hardwaretest-RPM-Verzeichnis --rpms alma/rpm/out
```

Das Hardwaretest-RPM muss die gewünschte aktuelle Version enthalten; `--version`
bezeichnet den ISO-Dateinamen und lädt selbst kein neueres Hardwaretest nach.
`--rpms` kann mehrfach angegeben werden. Ohne diese Option werden `alma/rpm/out`
und, falls vorhanden, `/tmp/alma-share` verwendet.

- **Memtest86+ (frei, GPL)**: wird beim Build automatisch von memtest.org geladen (`MT86P_VER`, Standard 9.00,
  SHA256-geprüft, Cache in `alma/work/memtest86plus`) und als „unified“ bzImage in BIOS- und UEFI-Menü
  eingetragen (Taste `m`; unter UEFI nur ohne Secure Boot). Liegt im Live-System als `/boot/memtest86+x64.bin`.
- **`--nvidia`**: nvidia-open + nvidia-driver-cuda + DCGM 4 aus dem CUDA-rhel9-Repo. Das Repo liefert nur ein
  DKMS-Kmod, daher wird das Modul im Chroot per `dkms autoinstall -k <KVER>` gebaut (kernel-devel/gcc werden
  danach wieder entfernt). ISO heißt `hwtest-live-alma-<VERSION>-nvidia.iso`; Modul ist unsigniert (kein Secure Boot).
- **`--keep`**: Arbeitsdateisystem und ISO-Baum für Inhaltsprüfung und Fehlersuche behalten.
- **`--memtest86`** bleibt für lokale Builds verfügbar; damit erhält die ISO-Datei den Zusatz
  `-intern` und darf nicht als öffentliches Image veröffentlicht werden.

Läuft in einem privilegierten `almalinux:9`-Container (rootless podman genügt), ohne
Anaconda/lorax – analog zu `scripts/build_live_iso.sh`:

1. `dnf --installroot` mit `packages.ks` (ZFS als `kmod-zfs`, Hardwaretest/vmfs-RPMs aus
   `rpm/out/` und `/tmp/alma-share` über ein lokales Repo)
2. Konfiguration als Ersatz für `live-config`: `live/includes.chroot` wird
   übernommen (Debian-Spezifika werden angepasst), Benutzer `user`/`live` mit sudo ohne
   Passwort, Autologin tty1 → `startx` → Openbox/tint2, Hostname `hwtest-live`,
   de_DE.UTF-8, Tastatur `de`, SELinux aus, Dienste `hpe-live-boot`/`hpe-live-zram`.
   Die gemeinsamen Hooks `0610`, `0650`, `0660` und `0700` laufen auch unter Alma.
   Fehlgeschlagene Hooks oder Systemchecks brechen den Build ab.
3. `dracut --no-hostonly --add "dmsquash-live livenet"` (Hook vergrößert `/run` auf 80 %,
   sonst schneidet systemds 20-%-Limit das RAM-Image ab)
4. flaches `LiveOS/squashfs.img` (xz), ohne Kernel-/Initramfs-Duplikate – dracut
   erkennt es und nutzt overlayfs. Anders als Debian nutzt Alma weiterhin eine
   gemeinsame Schicht für Basis und NVIDIA.
5. hybrides ISO per xorriso: BIOS isolinux, UEFI shim + signierter GRUB (Secure Boot),
   Label `HWTEST-ALMA`, eigenständige GPT-EFI-Partition

Bootparameter: `root=live:CDLABEL=HWTEST-ALMA rd.live.image rd.live.ram=1` (Gegenstück zu
`toram`), Menüeinträge wie beim Trixie-Image (`hpe-live.nox`, `hpe-live.ssh`, Memtest86+ BIOS,
optional PassMark MemTest86 UEFI). Ausgabe: `alma/out/hwtest-live-alma-<version>.iso`
(+ `.sha256`, `.packages`, `build-alma.log`).

Mindest-RAM für den RAM-Modus: ca. 2,5 GB. Persistenz (Eintrag „mit Persistenz“) nutzt
`rd.live.overlay=LABEL=persistence rd.live.overlay.overlayfs=1` und ist noch **ungetestet**;
`make-persistent-usb.sh` muss dafür angepasst werden.

## Dateien

- `packages.ks` – Kickstart-`%packages` (geprüft)
- `repos/hpe.repo`, `repos/nvidia-cuda.repo`, `repos/README.md`
- `scripts/check_packages.sh [--nvidia]` – Verfügbarkeitsprüfung im Container
- `rpm/vmfs-tools.spec`, `rpm/vmfs6-tools.spec`, `scripts/build_vmfs_rpms.sh` – eigene RPMs (Ausgabe `rpm/out/`, nicht versioniert)
- `scripts/build_alma_live.sh` – ISO-Build (Arbeitsverzeichnis `work/`, Ausgabe `out/`, beide nicht versioniert)
