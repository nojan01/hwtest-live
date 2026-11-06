#!/usr/bin/env bash
# Legt eine VirtualBox-VM zum Testen des ISOs an (bzw. aktualisiert sie) und startet sie.
#
#   ./scripts/test_iso_vbox.sh ISO [bios|uefi] [--no-start]
#
# Name der VM: HPE-Live-Test-BIOS bzw. HPE-Live-Test-UEFI. RAM über MEM=MB (Default 6144).
# Eine vorhandene VM behält ihre Einstellungen, nur das ISO wird getauscht.
# RESET=1 setzt die Standard-Einstellungen (RAM, CPU, Firmware, NIC, serielle Konsole) neu.
# Netzwerk: Bridged über die Schnittstelle der Default-Route (BRIDGE=IFACE überschreibt),
# damit SSH/Ping aus dem LAN funktionieren; ohne erkennbare Schnittstelle NAT.
set -euo pipefail

ISO="$(readlink -f "${1:?Aufruf: $0 ISO [bios|uefi] [--no-start]}")"
FW="${2:-bios}"
START=1
[ "${3:-}" = "--no-start" ] && START=0
MEM="${MEM:-6144}"
BRIDGE="${BRIDGE:-$(ip -o -4 route show default 2>/dev/null | awk '{print $5; exit}')}"
[ -f "$ISO" ] || { echo "ISO nicht gefunden: $ISO" >&2; exit 1; }
case "$FW" in bios|uefi) ;; *) echo "Firmware muss bios oder uefi sein" >&2; exit 2 ;; esac

VM="HPE-Live-Test-${FW^^}"
command -v VBoxManage >/dev/null || { echo "VirtualBox (VBoxManage) fehlt" >&2; exit 1; }

CONFIGURE="${RESET:-0}"
if ! VBoxManage showvminfo "$VM" >/dev/null 2>&1; then
    CONFIGURE=1
    VBoxManage createvm --name "$VM" --ostype Debian_64 --register >/dev/null
    VBoxManage storagectl "$VM" --name SATA --add sata --controller IntelAhci --portcount 2
fi
if VBoxManage showvminfo "$VM" --machinereadable | grep -q '^VMState="running"'; then
    echo "VM $VM läuft bereits - bitte erst ausschalten." >&2
    exit 1
fi

if [ "$CONFIGURE" = 1 ]; then
    VBoxManage modifyvm "$VM" \
        --memory "$MEM" --cpus 2 --vram 32 --graphicscontroller vmsvga \
        --firmware "$([ "$FW" = uefi ] && echo efi64 || echo bios)" \
        --boot1 dvd --boot2 none --boot3 none --boot4 none \
        --nictype1 82540EM \
        --audio-enabled off --usb-ohci on \
        --uart1 0x3F8 4 --uart-mode1 file "/tmp/${VM}-serial.log"
    if [ -n "$BRIDGE" ]; then
        VBoxManage modifyvm "$VM" --nic1 bridged --bridgeadapter1 "$BRIDGE"
    else
        VBoxManage modifyvm "$VM" --nic1 nat
    fi
    echo "VM $VM: Standard-Einstellungen gesetzt (${FW}, ${MEM} MB RAM, serielles Log /tmp/${VM}-serial.log, Netz: ${BRIDGE:+bridged $BRIDGE}${BRIDGE:-NAT})"
else
    echo "VM $VM: vorhandene Einstellungen bleiben unverändert, nur das ISO wird getauscht"
fi
VBoxManage storageattach "$VM" --storagectl SATA --port 0 --device 0 \
    --type dvddrive --medium "$ISO"

echo "VM $VM: $ISO"
if [ "$START" = 1 ]; then
    VBoxManage startvm "$VM" --type gui
fi
