# Drittanbieter-Komponenten und Lizenzen

Das Live-ISO bündelt Software Dritter. Die Lizenzen der Debian-Pakete stehen im Image
unter `/usr/share/doc/<paket>/copyright` (der Slim-Hook entfernt Dokumentation, behält
aber diese Dateien). Diese Übersicht liegt im Image unter
`/usr/local/share/doc/hpe-live/THIRD-PARTY-LICENSES.md`.

## Freie Software (Auswahl)

| Komponente | Lizenz |
|---|---|
| Debian GNU/Linux 13 (trixie), Linux-Kernel | überwiegend GPL-2.0 u. a., je Paket siehe `copyright` |
| Firmware (`firmware-amd-graphics`, `firmware-intel-graphics`, `firmware-nvidia-graphics`, …) | weitergebbare Herstellerlizenzen, je Paket siehe `copyright` |
| Mesa (`mesa-vulkan-drivers`: RADV, ANV, NVK, llvmpipe) | MIT |
| Vulkan-Loader und `vulkan-tools` | Apache-2.0 |
| OpenZFS (DKMS-Modul) | CDDL-1.0 |
| memtest86+ | GPL-2.0 |
| stress-ng, fio, iperf3, smartmontools, nvme-cli, rasdaemon, ipmitool, btop, htop | GPL-2.0 bzw. BSD/MIT, je Paket siehe `copyright` |
| iLOrest (`HewlettPackard/python-redfish-utility`) | Apache-2.0 |
| NVIDIA DCGM | Apache-2.0 |
| NVIDIA Open GPU Kernel Modules (`nvidia-kernel-open-dkms`) | MIT / GPL-2.0 (dual) |

## Hardwaretest (`nojan01/Ubuntu-Stresstest`)

MIT. Enthält bzw. nutzt u. a. Qt/PySide6 (LGPL-3.0), OpenDCDiag (Apache-2.0),
Prime95/mprime (Freeware von Mersenne Research, GIMPS-Bedingungen) und den
PyInstaller-Bootloader (GPL-2.0 mit Ausnahme). Lizenztexte unter
`/opt/hardwaretest/_internal/` (`LICENSE`, `vendor/opendcdiag/LICENSE*`,
`vendor/prime95/license.txt`).

## Proprietäre Software

Nur mit Zustimmung zu den jeweiligen Lizenzbedingungen verwenden und weitergeben.

| Komponente | Lizenz |
|---|---|
| NVIDIA-Treiber-Userspace (`nvidia-smi`, `libnvidia-ml1`, `libcuda1`, GSP-Firmware, `nvidia-persistenced`) | NVIDIA Software License |
| CUDA-Bibliotheken, die DCGM mitbringt (cuBLAS, NCCL u. a.) | NVIDIA CUDA Toolkit EULA |
| HPE `ssacli`, `ssaducli`, `hponcfg` (HPE MCP-Repo) | HPE-Softwarelizenz |
| Broadcom `storcli64`, `storcli2` (HPE MCP-Repo) | Broadcom-Lizenz |
| PassMark MemTest86 (nur mit `--memtest86`, nicht im Repo) | PassMark-Lizenz (Free/Pro) |
