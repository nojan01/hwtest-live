# Hardwaretest Live ISO

> Live-System zum Hardwaretest von Servern (Debian 13 „trixie“, amd64). Dateiname `hwtest-live-DATUM.iso`,
> Hostname `hwtest-live` (Prompt `user@hwtest-live`). Das Repository heißt aus historischen Gründen
> weiterhin HPE-Live-ISO; interne Skript- und Dienstnamen (`hpe-live-*`) sind unverändert.

Minimales Debian‑13‑Live‑System („trixie“, amd64) als **hybrides ISO (UEFI + Legacy‑BIOS)**.
Es lässt sich über **iLO Virtual Media** auf HPE‑ProLiant‑Servern mounten und booten.
Das System läuft komplett im RAM (`toram`), installiert nichts auf die Server‑Platten und enthält:

* **Hardwaretest** (PySide6/Qt6, `nojan01/Ubuntu-Stresstest`) – startet automatisch
* **JSON Viewer/Editor** (Tauri/WebKitGTK, `nojan01/json-viewer-editor`) – wird aus Hardwaretest geöffnet

> **Zwei Ausprägungen:** Das **externe ISO** (Standard‑Build) enthält nur frei weitergebbare
> Komponenten (HPE‑Pakete aus dem öffentlichen SDR, NVIDIA‑Treiber aus dem CUDA‑Repo) und wird
> als Release veröffentlicht. Das **interne ISO** (`--vendor-tools DIR`, Namenszusatz `-intern`)
> enthält zusätzlich Hersteller‑Werkzeuge für FC‑HBAs und Ethernet‑Adapter (QLogic/Marvell `qaucli`,
> `qlnxcli`, Emulex `hbacmd`, Mellanox/NVIDIA MFT, Broadcom `niccli`/`bnxtnvm`, Intel
> `nvmupdate64e`/`epct`, Solarflare/AMD `sfupdate`/`sfreport`) und ggf. MemTest86 Pro, deren EULA
> keine Weitergabe erlaubt – nur für den internen Gebrauch, nicht veröffentlichen.
> Lizenzen der Drittkomponenten: [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md)
> (im Image unter `/usr/local/share/doc/hpe-live/`).

## Inhalt

| Bereich | Pakete / Werkzeuge |
|---|---|
| Oberfläche | Xorg (fbdev/vesa/modesetting, passt z. B. zu iLO‑Grafik `mgag200`), Openbox, tint2, xterm, lxpolkit, Dateimanager `pcmanfm` (Menü → *Dateimanager*, USB‑Laufwerke über udisks2/gvfs), Hintergrundbild „Tests are in progress—please do not touch!“ mit dezentem Hinweis unten rechts (© 2026 Norbert Jander; Hardwaretest und JSON Viewer: MIT‑Lizenz) (`/usr/share/backgrounds/hpe-live/testsystem.png`, gesetzt mit `feh` im Openbox‑Autostart; Bootmenü‑Hintergrund ohne Text, gleich in allen Varianten). Autologin `user` auf tty1, danach startet X mit Hardwaretest. Der JSON Viewer wird aus Hardwaretest geöffnet (Wrapper `/usr/local/bin/app`) oder über Menü/Taskleiste. HTML‑Reports öffnet `surf` (WebKitGTK, Wrapper `/usr/local/bin/firefox`, da Hardwaretest nach Firefox/Chrome sucht). Weil Hardwaretest (PyInstaller) `LD_LIBRARY_PATH=/opt/hardwaretest/_internal` an Kindprozesse vererbt und dessen Ubuntu‑Bibliotheken älter als Debian 13 sind, legt der Hook `0650-hpe-live-clean-wrappers` für alle dadurch brechenden Programme (z. B. `journalctl` für Kernel‑/MCE‑Log, `systemctl`, `fio`, `fdisk`) sowie für `xterm` Wrapper in `/usr/local/{bin,sbin}` an, die die Umgebung bereinigen. |
| Hardwaretest‑Tools | stress-ng, fio, iperf3, mprime (im Hardwaretest‑Paket enthalten), btop, htop, nvme-cli/libnvme, smartmontools, hdparm, sg3-utils, mdadm, lvm2, util-linux, e2fsprogs, xfsprogs, btrfs-progs, dosfstools, squashfs-tools, vmfs6-tools/vmfs-tools (VMFS lesend prüfen), ntfs-3g, exfatprogs, gdisk, testdisk (Reparaturwerkzeuge für den Administrator – Hardwaretest prüft nur lesend), lshw, pciutils, usbutils, dmidecode, lm-sensors, edac-utils, rasdaemon (`ras-mc-ctl`, MCE/EDAC; Nachfolger von `mcelog`), ipmitool, jq, fastfetch, memtest86+ (eigener Bootmenü‑Eintrag; Paket zusätzlich im Live‑System, damit „memtest86+ prüfen“ in Hardwaretest positiv meldet) |
| ZFS | zfsutils-linux, das Kernelmodul wird beim Build per DKMS für den Live‑Kernel gebaut |
| HPE (MCP‑Repo) | `ssacli`, `ssaducli`, `hponcfg`, `storcli` (`storcli64`), `storcli2`, `amsd` (Agentless Management Service für iLO), dazu `ilorest` (aus dem GitHub‑Release von HPE, RPM → DEB umgepackt) und das Kernelmodul `hpilo` |
| Firmware | bnx2, bnx2x, qlogic, netxen, intel-misc, misc-nonfree (Broadcom/QLogic/Intel/Mellanox‑NICs, HBAs) |
| Grafikkarten | AMD (`amdgpu`/`radeon`, `firmware-amd-graphics`), Intel (`i915`/`xe`, `firmware-intel-graphics`), NVIDIA über den proprietären Treiber oder – per Bootmenü „ohne NVIDIA‑Treiber (nouveau)“ bzw. in der Variante `none` – über `nouveau` (`firmware-nvidia-graphics`); Vulkan über Mesa (`mesa-vulkan-drivers`: RADV, ANV, NVK, llvmpipe) und `vulkaninfo` für den herstellerneutralen GPU‑Lasttest. Xorg nutzt dann automatisch `modesetting`. Die RAPL‑Energiezähler (`/sys/class/powercap/*/energy_uj`) macht eine udev‑Regel für alle lesbar, damit Hardwaretest als `user` die Leistung von CPU und Intel‑iGPU anzeigt. |
| NVIDIA | Enterprise‑Compute‑Treiber 595 (Consumer‑ und Rechenzentrumskarten ab Turing), `nvidia-smi`, CUDA‑Lasttest und NVIDIA DCGM 4 (`dcgmi diag`), siehe [Varianten](#varianten) |

Nicht enthalten: Desktop‑Environment, Doku, Manpages, Locales (außer `de`), Sound, WLAN, Bluetooth, Media
und `ssa` (GUI).

`amsd` (mit `ahslog`, `smad`, `cpq*`-MIB-Handlern) startet nur, wenn ein iLO vorhanden ist
(`ConditionPathExistsGlob=/dev/hpilo/*`), in VMs und auf Fremdhardware bleibt er inaktiv. Auf ProLiants
liefert er dem iLO die OS-Sicht; im Gegenzug sind in Hardwaretest → ProLiant‑Info → Sensoren deutlich mehr
Temperatursensoren und Lüfterwerte sichtbar als ohne Agent.

## ISO auf USB-Stick/USB-HDD schreiben

Das ISO hat ein GPT-Layout mit eigenständiger EFI-Systempartition (wie Ubuntu ≥ 20.10) und
bootet per UEFI (Secure Boot) und BIOS. Es kann 1:1 geschrieben werden, z.B. mit
**balenaEtcher**, **Rufus** (Windows), `dd` oder über iLO Virtual Media.

### Mit Persistenz unter Windows: Rufus

1. Rufus starten, Laufwerk und ISO wählen, Partitionsschema **GPT**, Zielsystem **UEFI (non CSM)**.
2. Regler **„Persistente Partitionsgröße“** aufziehen (z.B. 16–32 GB) und **Start** klicken;
   bei der Rückfrage **„Im ISO-Image-Modus schreiben“** belassen.
3. Beim Booten den Eintrag **„Hardwaretest Live: mit Persistenz“** wählen.

Alternativ **Ventoy**: ISO einfach auf den Ventoy-Stick kopieren (ohne Persistenz).

### Mit Persistenz unter Linux: Skript

```bash
sudo bash scripts/make-persistent-usb.sh dist/hwtest-live-YYYYMMDD.iso /dev/sdX [32G]
```

Das Skript legt auf dem Gerät eine GPT mit BIOS-Boot-Partition, einer FAT32-EFI-Systempartition
mit dem ISO-Inhalt (unter Windows lesbar) und einer ext4-Partition `persistence`
(`persistence.conf` = `/ union`) im Restplatz bzw. in der angegebenen Größe an. Beim Booten den Eintrag
**„Hardwaretest Live: mit Persistenz“** wählen: Änderungen (Reports, Einstellungen, nachinstallierte Pakete) bleiben
erhalten. Die anderen Einträge starten weiterhin ohne Persistenz. ISO-Updates: Skript erneut ausführen
(löscht auch die Persistenz). `--dd` schreibt stattdessen das ISO-Abbild 1:1 und hängt die
Persistenz-Partition an.

## Varianten

| `--nvidia` | ISO‑Name | Zusätzlich | Größe |
|---|---|---|---|
| `dcgm` (Standard, einheitliches Image) | `hwtest-live-DATUM.iso` | headless Compute‑Treiber 595.91.07 aus dem NVIDIA CUDA‑Repo (DKMS‑Modul `nvidia-kernel-open-dkms`), `nvidia-smi`, `libnvidia-ml1`, `nvidia-persistenced`, GSP‑Firmware, CUDA‑Runtime (`libcuda1`) und NVIDIA DCGM 4 für CUDA 13 (`dcgmi`, `nv-hostengine`); keine X/GL‑, OpenCL‑ oder Video‑Bibliotheken. **Groß** (DCGM zieht cuBLAS/NCCL usw.) | ca. 1,6–1,8 GB |
| `driver` | `hwtest-live-nvidia-DATUM.iso` | wie `dcgm`, aber ohne DCGM und ohne CUDA‑Runtime | ca. 0,7 GB |
| `none` | `hwtest-live-ohne-nvidia-DATUM.iso` | kein proprietärer NVIDIA‑Treiber, NVIDIA‑Karten nur über nouveau/NVK | ca. 0,6 GB |

Mit NVIDIA‑Treiber (`dcgm`, `driver`) ist nouveau per Kernel‑Parameter `modprobe.blacklist=nouveau` gesperrt. Der zusätzliche Bootmenü‑Eintrag **„Hardwaretest Live: ohne NVIDIA‑Treiber (nouveau, GPUs vor Turing, weniger RAM)“** sperrt stattdessen die nvidia‑Module (`module_blacklist=nvidia,…`, `hpe-live.nouveau`) und lässt nouveau/NVK zu – Notlösung für ältere NVIDIA‑Karten (Pascal/Volta und älter), bei Treiberproblemen oder mit aktivem Secure Boot, und die passende Wahl für Server ohne NVIDIA‑Karte.

**Zwei Squashfs‑Schichten:** Treiber, CUDA‑Runtime und DCGM liegen in diesen Varianten nicht in `live/filesystem.squashfs`, sondern in einem eigenen `live/nvidia.squashfs` (ca. 1,6 GB unkomprimiert). Die Standard‑Einträge hängen beide Schichten als Overlay ein und kopieren mit `toram` das ganze Medium in den RAM. Der nouveau‑Eintrag startet mit `toram=filesystem.squashfs`: live‑boot kopiert und mountet dann nur die Basis – das ISO über iLO Virtual Media lädt entsprechend schneller und belegt weniger RAM (NVIDIA‑Werkzeuge wie `nvidia-smi` fehlen in diesem Modus, `hpe-live-check` meldet das als Info). Die Aufteilung erledigen die Hooks in `live/optional/nvidia/hooks/live/` (`0800 … .chroot` ermittelt den Paketsatz samt nur dort benötigten Abhängigkeiten per `apt-get -s purge --auto-remove`, das Build‑Skript schließt die Dateien über `config/rootfs/excludes` aus der Basis aus, `0100 … .binary` packt `nvidia.squashfs`). Die `.packages`‑Liste nennt weiterhin alle Pakete des Images.

`--nvidia-kmod proprietary` verwendet statt des Open‑Kernel‑Moduls (ab Turing) das proprietäre `nvidia-kernel-dkms` (z. B. für Pascal/Volta).

Der Treiber kommt aus dem NVIDIA CUDA‑Repo für Debian 13, nicht aus Debian. Debians Treiber 550 lässt sich gegen den aktuellen Trixie‑Kernel (6.12.x) nicht mehr bauen (`pci_resize_resource`). Die Version ist per APT‑Pinning fest (`--nvidia-version`, Standard 595.91.07). Große, unnötige Treiberbibliotheken (OptiX, OpenCL, NVDEC; bei `driver` auch CUDA/PTX‑JIT) werden per `dpkg path-exclude` nicht installiert (`live/optional/nvidia/includes.chroot_before_packages/etc/dpkg/dpkg.cfg.d/`).
Compiler, Header und DKMS werden nach dem Modulbau wieder aus dem Image entfernt.

## Bauen

Benötigt: Internetzugang, ca. 30 GB freien Platz (`none`/`driver`: ca. 15 GB), root‑Rechte.

### Variante A: direkt auf Debian 13 / Ubuntu 24.04+ / Mint 22

```bash
sudo apt install live-build debootstrap curl python3 libarchive-tools
sudo ./scripts/build_live_iso.sh                    # Standard: NVIDIA-Treiber + DCGM
sudo ./scripts/build_live_iso.sh --nvidia driver    # nur NVIDIA-Treiber
sudo ./scripts/build_live_iso.sh --nvidia none      # ohne NVIDIA-Treiber (nouveau)
```

`live-build` muss mindestens Version 20250505 (Debian 13) sein. Ubuntu und Linux Mint liefern
die uralte Version 3.0~a57, die nicht funktioniert. Dort die Debian‑Pakete direkt installieren
(reine Shell‑/Daten‑Pakete, unbedenklich):

```bash
sudo apt install libarchive-tools distro-info wget cpio
cd /tmp
for p in l/live-build/live-build_20250505+deb13u1_all.deb \
         d/debootstrap/debootstrap_1.0.141_all.deb \
         d/debian-archive-keyring/debian-archive-keyring_2025.1_all.deb; do
  curl -fsSLO "http://deb.debian.org/debian/pool/main/$p"
done
sudo apt install ./live-build_*_all.deb ./debootstrap_*_all.deb ./debian-archive-keyring_*_all.deb
```

Alternativ Variante B verwenden.

### Variante B: im Container (docker oder podman)

```bash
./scripts/build_in_container.sh                     # nutzt sudo für einen --privileged-Container
./scripts/build_in_container.sh --nvidia driver
```

### Optionen

| Option / Umgebungsvariable | Bedeutung |
|---|---|
| `--nvidia dcgm\|driver\|none` / `NVIDIA` | NVIDIA-Variante (Standard: `dcgm`) |
| `--nvidia-kmod open\|proprietary` / `NVIDIA_KMOD` | Art des NVIDIA-Kernelmoduls |
| `--nvidia-version VERSION` / `NVIDIA_VERSION` | NVIDIA-Treiberversion aus dem CUDA-Repo (Standard: 595.91.07) |
| `--hardwaretest latest\|DATEI.deb` / `HARDWARETEST` | Standard: neuestes Release von `nojan01/Ubuntu-Stresstest` |
| `--json-viewer latest\|DATEI.deb` / `JSON_VIEWER` | Standard: neuestes Release von `nojan01/json-viewer-editor` |
| `--ilorest latest\|none\|DATEI.rpm\|DATEI.deb` / `ILOREST` | iLOrest von `HewlettPackard/python-redfish-utility` |
| `--btop backport\|trixie\|DATEI.deb` / `BTOP` | `backport` (Default): btop 1.4.7 aus Debian sid (SHA256-geprüft, läuft auf trixie). btop 1.3.2 aus trixie zeigt bei vielen Threads (z. B. 2×16 Kerne mit HT) keine Einzelkerne. `trixie` = Paket aus trixie |
| `--memtest86 none\|DATEI.img\|DIR` / `MEMTEST86` | PassMark MemTest86 (UEFI) zusätzlich ins Bootmenü. `memtest86-usb.img` bzw. `memtest86-pro-usb.img` aus dem PassMark‑ZIP (Free oder Pro) oder Ordner mit `BOOTX64.efi`; `mt86.cfg` u. a. werden mit übernommen. Proprietär, wird nicht im Repo abgelegt. Default `none` |
| `--vendor-tools none\|DIR` / `VENDOR_TOOLS` | Hersteller‑Werkzeuge aus `DIR` mitinstallieren → **internes ISO** (`-intern` im Namen). Akzeptiert `.deb`/`.rpm` (`.rpm` werden umgepackt: mit `alien` inkl. Skripte, sonst reine Dateikopie), außerdem Archive (`.tar.gz`/`.tgz`/`.tar.xz`/`.zip`) und lose ausführbare Binaries: Diese landen über das generierte Paket `vendor-tools-extra` unter `/opt/vendor-tools/<Archivname>/` bzw. `/opt/vendor-tools/bin/`; bekannte Kommandos (`niccli`, `bnxtnvm`, `qaucli`, `qlnxcli`, `nvmupdate64e`, `epct64e`, `mst`, `mlx*`, `flint`, `sfupdate`, `sfreport`, `sfboot`, `hbacmd`) werden nach `/usr/local/sbin` verlinkt (`nvmupdate64e` als Wrapper, der im Paketordner mit `nvmupdate.cfg` startet; bei mehreren Intel‑Paketen zusätzlich `nvmupdate64e-700series`, `nvmupdate64e-e810` …). In Archiven enthaltene `.deb`/`.rpm` (z. B. `mft-*-x86_64-deb.tgz`, `niccli-*_linux.zip`) werden als Pakete installiert – nur amd64, `.deb` vor `.rpm`, keine Quell‑/DKMS‑Pakete; Windows‑/ESXi‑/FreeBSD‑/ARM‑Ordner werden entfernt. Alles landet in der Basis‑Schicht `filesystem.squashfs` und ist damit in **jedem** Bootmodus (auch nouveau/`toram=filesystem.squashfs`) verfügbar. `hpe-live-check` listet die Werkzeuge; Hardwaretest (Tab Netzwerk → *Hersteller‑Diagnose*) nutzt sie automatisch. Default `none` |
| `--no-strip-modules` / `STRIP_KERNEL_MODULES=0` | Sound-, WLAN- und Media-Kernelmodule usw. behalten |
| `--mirror URL` / `MIRROR` | lokaler Debian-Mirror bzw. apt-cacher-ng |
| `GITHUB_TOKEN` | für GitHub-API-Rate-Limits oder private Repos |

Beispiel mit lokalen App‑Paketen:

```bash
sudo ./scripts/build_live_iso.sh \
  --hardwaretest ~/Vorlagen/Hardwaretest/hardwaretest_0.2.32_amd64.deb \
  --json-viewer ~/Downloads/JSON.Viewer_1.5.4_amd64.deb
```

Internes ISO mit Hersteller‑Werkzeugen (nicht veröffentlichen):

```bash
sudo ./scripts/build_live_iso.sh \
  --hardwaretest ~/Vorlagen/Hardwaretest/hardwaretest_0.2.65_amd64.deb \
  --vendor-tools ~/Downloads/vendor-tools \
  --memtest86 ~/Downloads/memtest86-pro-usb.img
```

Ergebnis: `dist/<name>.iso` mit `.sha256` und `.packages` (Paketliste).
Heruntergeladene Artefakte und der apt-/debootstrap-Cache liegen in `build/` und werden bei weiteren Builds wiederverwendet.

### Ablauf und Prüfungen

1. `lb config` mit `--apt-recommends false`, xz‑squashfs, `iso-hybrid`, syslinux + grub-efi (Secure‑Boot‑signierter Loader)
2. Pakete aus `live/package-lists/`, HPE‑ und (bei `driver`/`dcgm`) NVIDIA CUDA‑Repo aus `live/archives/` bzw. `live/optional/`
3. Hooks in `live/hooks/live/`:
   * `0500` DKMS‑Module (ZFS, NVIDIA) für den Live‑Kernel bauen, danach Toolchain und Header entfernen
   * `0600` Dienste (DHCP, Bootcheck) aktivieren, Unnötiges abschalten
   * `0700` Image verkleinern (Kernelmodule, Firmware, Caches)
   * `0800` (nur `driver`/`dcgm`, aus `live/optional/nvidia/hooks/`) Dateiliste für die NVIDIA‑Schicht; das Build‑Skript führt
     `lb bootstrap`/`lb chroot`/`lb binary` einzeln aus und erzeugt dazwischen `config/rootfs/excludes`; der Binary‑Hook `0100` baut `live/nvidia.squashfs`
   * `0900` `hpe-live-check --build`: Der Build bricht ab, wenn ein Tool oder Modul fehlt.

Paketnamen lassen sich ohne root gegen die Repositories prüfen:

```bash
./scripts/check_packages.py
```

### Boot‑Test in QEMU

```bash
sudo apt install qemu-system-x86 ovmf
./scripts/test_iso_qemu.sh dist/hwtest-live-*.iso both     # BIOS + UEFI, headless
GUI=1 ./scripts/test_iso_qemu.sh dist/hwtest-live-*.iso uefi
```

Beim Booten läuft `hpe-live-check` und meldet auf der seriellen Konsole `hpe-live: READY rc=0 …`.
Das Skript wartet auf diese Zeile (mit KVM ca. 1–2 min, ohne KVM deutlich länger).

### Test in VirtualBox

```bash
./scripts/test_iso_vbox.sh dist/hwtest-live-*.iso bios   # VM HPE-Live-Test-BIOS
./scripts/test_iso_vbox.sh dist/hwtest-live-*.iso uefi   # VM HPE-Live-Test-UEFI
```

Das Skript legt die VM bei Bedarf an (Debian 64-bit, 6 GB RAM über `MEM=`, keine Festplatte, VMSVGA, NAT),
legt das ISO ein und startet sie. Das serielle Log steht in `/tmp/HPE-Live-Test-*-serial.log`.
Eine vorhandene VM behält ihre Einstellungen (RAM, Netzwerk usw.), nur das ISO wird getauscht.
`RESET=1` setzt die Standard-Einstellungen neu.
In der VM fehlen `/dev/hpilo` und die RAID-Controller. HPE-Tools und `nvidia-smi` finden dort also nichts.
Das ist normal.

## Einsatz über iLO

1. ISO auf einen internen HTTP(S)‑Server legen (oder lokal im Browser bereithalten).
2. iLO‑Weboberfläche → **Remote Console & Media → Virtual Media → CD/DVD** → *Scripted Media URL*
   (z. B. `http://server/iso/hwtest-live-….iso`) → *Insert Media*, „Boot on next reset“ anhaken.
   Alternativ in der HTML5‑Konsole: *Virtual Drives → Image File CD/DVD‑ROM*.
3. Server neu starten (oder einmalig per F11 → *iLO Virtual CD‑ROM* booten).
4. Bootmenü (5 s Timeout):
   1. **Hardwaretest Live: mit NVIDIA‑Treiber und DCGM** – Standard: Desktop + Hardwaretest, alle Treiber
   2. **Hardwaretest Live: ohne NVIDIA‑Treiber (nouveau, GPUs vor Turing, weniger RAM)** – lädt nur die Basis‑Schicht
      (ohne `nvidia.squashfs`) in den RAM; für Server ohne NVIDIA‑Karte, alte NVIDIA‑GPUs oder Secure Boot
   3. **Hardwaretest Live: mit Persistenz (USB, alle Treiber)** – wie 1., Änderungen bleiben auf dem USB‑Stick erhalten
   4. **Utilities…** – memtest86+, PassMark MemTest86, UEFI‑Firmware‑Setup sowie die Notfall‑Einträge
      **Textmodus** (`hpe-live.nox`, nur Konsole, z. B. für reine `ssacli`/`storcli`‑Arbeiten) und
      **mit SSH‑Server** (`hpe-live.ssh`, Login `user` / `live`; auch ohne Neustart: Menü (Rechtsklick) →
      *SSH‑Server starten* bzw. `sudo hpe-live-ssh start` – zeigt IP‑Adressen und `scp`‑Befehl an).
      Desktop ohne Autostart der Apps: beliebigen Eintrag mit `e` bearbeiten und `hpe-live.noapps` anhängen.
   * **Memory Diagnostic Tool** – memtest86+ (BIOS und UEFI; unter UEFI nur mit ausgeschaltetem Secure Boot)
     Startet immer mit `noehci` (USB ohne EHCI) – nur so funktioniert die iLO‑Tastatur auf HPE ProLiant.
     PassMark MemTest86 nutzt dagegen die Tastatur-/Maustreiber der UEFI‑Firmware; die Maus hängt dort vom
     Firmware‑/iLO‑Zeigegerät ab, die Bedienung per Tastatur genügt.
   * **MemTest86 (PassMark, nur UEFI)** – unter *Utilities*, Hotkey `p`; nur wenn mit `--memtest86` gebaut.
     Microsoft‑signiert, läuft daher meist auch mit Secure Boot. Berichte können nicht aufs ISO gespeichert werden
     (read‑only); in der Free‑Version startet der Test automatisch. Lizenz (Free/Pro) beachten.
5. Durch `toram` wird das komplette System in den RAM kopiert.
   Danach kann das Virtual Media getrennt werden (benötigt zusätzlich RAM in ISO‑Größe).
   Der Eintrag „ohne NVIDIA‑Treiber (nouveau)“ kopiert nur die Basis (`filesystem.squashfs`, ohne `nvidia.squashfs`) –
   für Server ohne NVIDIA‑Karte die schnellere und RAM‑sparende Wahl.

Hinweise:

* **Standard im Einsatz: einheitliches Image (`dcgm`), Server im Boot‑Modus UEFI.** Wegen `toram` braucht der Server mindestens ca. 4 GB RAM.
  Legacy‑BIOS funktioniert ebenfalls (gleiches ISO), wird aber nur als Rückfalloption genutzt.
* **Secure Boot**: Das ISO bootet mit Secure Boot (signierter shim/GRUB/Kernel).
  Die per DKMS gebauten Module **ZFS und NVIDIA sind aber nicht signiert** und laden dann nicht.
  Wer ZFS oder den NVIDIA‑Treiber braucht, schaltet Secure Boot in RBSU/UEFI aus
  (NVIDIA‑Karten laufen sonst nur über den Bootmenü‑Eintrag „ohne NVIDIA‑Treiber (nouveau)“)
  (*System Configuration → BIOS/Platform Configuration → Server Security → Secure Boot Settings*).
  `hpe-live-check` warnt beim Booten, wenn Secure Boot aktiv ist.
* Benutzer `user`, Passwort `live`. `sudo` und `pkexec` fragen nicht nach dem Passwort.
  `user` ist in den Gruppen `adm` und `systemd-journal` (Kernel‑/MCE‑Logs ohne root).
* **Swap**: Die Server‑Platten werden nicht angefasst, daher gibt es Swap nur im RAM (zram, zstd,
  ¼ des RAM, max. 8 GiB, Eintrag in `/etc/fstab`, damit `swapon -a` aus Hardwaretest funktioniert).
  Abschalten mit dem Bootparameter `hpe-live.noswap`.
* Tastatur `de`, Zeitzone `Europe/Berlin`, Sprache `de_DE.UTF-8`. Beim Build änderbar über `KEYBOARD=us`,
  `TIMEZONE=…` und `LOCALE=en_US.UTF-8`, zur Laufzeit über die Bootparameter `keyboard-layouts=us` bzw.
  `locales=en_US.UTF-8`.
* NVIDIA‑Builds booten mit `iommu=pt` (IOMMU aktiv, Host‑DMA identity‑mapped – üblich auf GPU‑Knoten). Ohne
  diesen Parameter scheitert der DCGM‑PCIe‑Peer‑to‑Peer‑Test bei aktivem VT‑d/ACS mit „buffer mismatch“. Bei GPUs
  hinter PCIe‑Switches (Synergy‑Grafikmodul) hilft nur „PCIe‑P2P‑Test überspringen“ im Hardwaretest.
* Caps Lock ist im Desktop deaktiviert (`caps:none`): Die iLO‑HTML5‑Konsole gleicht den Caps‑Lock‑Zustand des
  Browsers per simuliertem Tastendruck ab, wodurch sonst der Lock‑Modifier hängen bleibt (alles groß).
  Falls doch nötig: Menü „Tastatur zurücksetzen“ bzw. `hpe-live-keyboard-reset`.
* iLO-Konsole (Matrox G200, 1024×768): xterm mit UTF-8 und 256 Farben, htop/btop öffnen maximiert
  (Openbox-Regel), btop zeichnet Graphen mit Blockzeichen statt Braille (die Schrift DejaVu Sans Mono
  hat keine Braille-Zeichen). btop startet ohne Prozessliste (CPU, MEM, NET), damit MEM mehr Platz hat;
  Taste `4` blendet die Prozessliste ein, `p` wechselt die Ansicht (mit Prozessliste / nur CPU / Standard).
  btop kommt in Version 1.4.7 (siehe `--btop`), damit auch Server mit 2 Sockeln und 64+ Threads alle
  Einzelkerne anzeigen.
* Netzwerk: NetworkManager, DHCP automatisch auf allen Ethernet‑Ports. Grafisch über das Tray‑Icon (nm-applet) bzw. Menü → *Netzwerk‑Verbindungen* (statische IP, VLAN, Bond …), in der Konsole `nmtui`/`nmcli`.
* Reports und Logs holen: Hardwaretest legt Reports in `/home/user/Downloads` ab.
  Menü → *Logs sammeln* (`sudo hpe-live-collect-logs`) packt Journal, dmesg, MCE/EDAC (rasdaemon),
  Systemcheck, dmidecode/lspci/lshw, ssacli/storcli, IPMI‑SEL u. a. als `logs-<Seriennr>-<Zeit>.tar.gz` dazu.
  Menü → *HPE-/RAID-Rohdaten sammeln* (`sudo hpe-live-collect-samples`) speichert die Rohausgaben von
  ssacli/storcli/ipmitool/ilorest als `hpe-samples-<Host>-<Zeit>.tar.gz` (jeder Aufruf max. 90 s, keine
  Eingabeaufforderungen; der langsame ssaducli-Diagnosebericht nur mit `SAMPLES_FULL=1`).
  Menü → *Berichte als Zip packen* (`hwtest-pack-reports`) fasst alle Dateien in `~/Downloads`
  (HTML-/JSON-/Textberichte, Log-Archive) zu `berichte-<Seriennr>-<Zeit>.zip` zusammen.
  Abholen per SSH: `scp -r user@<IP>:Downloads .` bzw. WinSCP (SFTP), Passwort `live`.
  Achtung: Alles liegt im RAM – vor dem Neustart sichern.
* Systemcheck jederzeit mit `sudo hpe-live-check`, das Boot‑Ergebnis steht in `/run/hpe-live-check.txt`.

### HPE‑Werkzeuge

| Befehl | Zweck |
|---|---|
| `sudo ssacli ctrl all show config` | Smart Array / SR‑Controller anzeigen und konfigurieren |
| `sudo ssaducli -f report.zip` | Diagnose‑Report der Smart‑Array‑Controller |
| `sudo storcli64 /call show` bzw. `sudo storcli2 /call show` | MegaRAID‑basierte HPE MR‑Controller (Gen10+/Gen11/Gen12) |
| `sudo hponcfg -w ilo.xml` | iLO‑Konfiguration lokal über den CHIF‑Treiber (`hpilo`) lesen/schreiben |
| `sudo ilorest login` (ohne Parameter = lokal) | Redfish/iLO‑Konfiguration, BIOS‑Einstellungen, Firmware‑Inventar |

Nur im **internen ISO** (`--vendor-tools`):

| Befehl | Zweck |
|---|---|
| `sudo qaucli -pr fc -g` / `-pr fc -i <hba>` | QLogic/Marvell FC‑HBAs: Übersicht, Port‑Details, Loopback‑/Diagnosetest, SFP‑Daten |
| `sudo hbacmd ListHBAs` / `hbacmd LoopBackTest <WWPN> …` / `hbacmd GetXcvrData <WWPN>` | Emulex/Broadcom FC‑HBAs: Übersicht, Loopback‑/Echo‑Test, Transceiver |
| `sudo mst start && sudo mlxlink -d <dev>` / `mlxcables` | Mellanox/NVIDIA Ethernet: Link‑Diagnose (BER, Eye), Kabel/Transceiver |
| `sudo mlxfwmanager --query` / `sudo mlxconfig -d <bdf> query` | Mellanox/NVIDIA: Firmware‑Inventar, Port‑/Konfigurationsabfrage |
| `sudo niccli --list` / `niccli -i <n> show` / `link -s` / `cable -m --show` / `linkdiag --loopback --show` | Broadcom NetXtreme‑E (`bnxt_en`): Adapterliste, Geräte‑/Firmware‑Info, Link‑Status, Transceiver, Loopback‑Status |
| `sudo bnxtnvm -dev=<if> device_info` | Broadcom NetXtreme‑E (älteres NVM‑Tool): Geräteinfo |
| `qlnxcli -i` | Marvell/QLogic FastLinQ (`qede`, `bnx2x`): Adapterübersicht (nicht im ISO enthalten; `qaucli` 3.x bedient **nur** FC‑HBAs, `-pr nic` wird abgelehnt) |
| `sudo nvmupdate64e -i` (700er: `nvmupdate64e-700series`, E810: `nvmupdate64e-e810`) / `sudo epct64e -devices` / `epct64e -nic=<n> -get` | Intel Ethernet (`i40e`, `ice`, `ixgbe`, `igb`): NVM‑/Firmware‑Inventar, Port‑Konfiguration |
| `sudo sfupdate` / `sudo sfboot` / `sudo sfreport` | Solarflare/Xilinx/AMD (`sfc`): Firmware‑Inventar, Boot‑/Adapterkonfiguration, HTML‑Diagnosebericht |

Hardwaretest (Tab Netzwerk → **Hersteller‑Diagnose**) erkennt diese Werkzeuge anhand des Treibers der gewählten Schnittstelle und führt nur lesende Inventar‑/Diagnosebefehle aus (Bericht als HTML). Die Werkzeuge selbst sind proprietär und müssen vom jeweiligen Hersteller geladen und in den `--vendor-tools`‑Ordner gelegt werden (Broadcom: *NetXtreme‑E niccli Utility – Linux* tar.gz; Intel: *NVM Update Package* bzw. *Ethernet Port Configuration Tool* tar.gz; NVIDIA: `mft-<ver>-x86_64-deb.tgz`; AMD/Solarflare: *Linux Utilities* rpm/tgz; Marvell: *QConvergeConsole CLI* `QConvergeConsoleCLI-<ver>.x86_64.rpm` – wird per `alien` zu `qconvergeconsolecli` umgepackt, `qaucli` liegt unter `/opt/QLogic_Corporation/QConvergeConsoleCLI/` mit Symlink `/usr/local/bin/qaucli`; braucht `libsysfs2`, das im ISO enthalten ist; Version 3.x unterstützt nur FC‑Adapter 2500–2800 – **nicht** das *QCC PowerKit* oder das *QLogic_Linux_Apps*‑Tarball, die nur den CIM/OMI‑Provider bzw. eine ältere CLI enthalten). Chelsio‑Werkzeuge werden bewusst nicht integriert.

Ohne diese Werkzeuge liefert Hardwaretest (Tab System → Fibre‑Channel‑HBAs, Tab Netzwerk → ethtool) die herstellerunabhängigen Daten aus sysfs und `ethtool`. Für Mellanox/NVIDIA‑Ethernet ist das **freie** `mstflint` (`mstlink`) in beiden ISO‑Ausprägungen enthalten; Hardwaretest bietet damit im Tab Netzwerk die Link‑Diagnose an.

## Struktur

```
live/                         live-build-Konfiguration (wird nach build/<variante>/config kopiert)
  archives/                   HPE MCP Repo + Schlüssel
  package-lists/              Paketlisten
  includes.chroot/            Dateien im Live-System (Autostart, Openbox, Checks)
  hooks/live/                 Build-Hooks (DKMS, System, Verkleinerung, Prüfung)
  optional/nvidia|dcgm/       Zusätze für die NVIDIA-Varianten
scripts/
  build_live_iso.sh           Build (als root)
  build_in_container.sh       Build im docker/podman-Container
  test_iso_qemu.sh            automatischer Boot-Test (BIOS/UEFI)
  test_iso_vbox.sh            Test-VM in VirtualBox anlegen und starten
  check_packages.py           Paketnamen gegen die Repositories prüfen
```

Weitere Pakete kommen in eine neue Datei `live/package-lists/NN-name.list.chroot`.
Zusätzliche lokale `.deb`‑Dateien können nach `live/packages.chroot/` gelegt werden
(Dateiname muss auf `_amd64.deb` oder `_all.deb` enden).
