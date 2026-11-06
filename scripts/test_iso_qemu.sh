#!/usr/bin/env bash
# Bootet ein ISO automatisiert in QEMU (BIOS und/oder UEFI) und wartet auf den
# Marker "hpe-live: READY" auf der seriellen Konsole.
#
#   ./scripts/test_iso_qemu.sh dist/hwtest-live-YYYYMMDD.iso [bios|uefi|both]
#
# Interaktiv (mit Fenster):  GUI=1 ./scripts/test_iso_qemu.sh ISO uefi
# Voraussetzungen: qemu-system-x86, ovmf (für UEFI); /dev/kvm empfohlen.
# Optional: QEMU=/pfad/qemu-system-x86_64, OVMF_CODE=/pfad/OVMF_CODE_4M.fd
set -euo pipefail

ISO="${1:?Aufruf: $0 ISO [bios|uefi|both]}"
MODE="${2:-both}"
MEM="${MEM:-6144}"
QEMU="${QEMU:-qemu-system-x86_64}"
TIMEOUT="${TIMEOUT:-}"
OUT_DIR="${OUT_DIR:-$(dirname "$(readlink -f "$ISO")")/qemu-test}"
mkdir -p "$OUT_DIR"

ACCEL=(-accel tcg)
if [ -w /dev/kvm ]; then
    ACCEL=(-accel kvm -cpu host)
    : "${TIMEOUT:=300}"
else
    echo "Hinweis: kein /dev/kvm -> TCG-Emulation (langsam)." >&2
    ACCEL=(-accel tcg,thread=multi -cpu max)
    : "${TIMEOUT:=1800}"
fi

find_ovmf() {
    [ -n "${OVMF_CODE:-}" ] && { echo "$OVMF_CODE"; return 0; }
    for f in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/qemu/OVMF.fd; do
        [ -r "$f" ] && { echo "$f"; return 0; }
    done
    return 1
}

run_one() {
    local fw="$1" log="$OUT_DIR/serial-$1.log" fwargs=() display=(-display none) rc=0
    if [ "$fw" = uefi ]; then
        local code
        code="$(find_ovmf)" || { echo "OVMF nicht gefunden (apt install ovmf)" >&2; return 1; }
        local vars="$OUT_DIR/OVMF_VARS.fd"
        cp "$(dirname "$code")/$(basename "$code" | sed 's/CODE/VARS/')" "$vars" 2>/dev/null || truncate -s 4M "$vars"
        fwargs=(-drive "if=pflash,format=raw,readonly=on,file=$code" -drive "if=pflash,format=raw,file=$vars")
    fi
    [ "${GUI:-0}" = 1 ] && display=(-display gtk)
    : >"$log"
    echo "==> $fw-Boot von $ISO (Timeout ${TIMEOUT}s, Log: $log)"
    local start=$SECONDS
    "$QEMU" "${ACCEL[@]}" -machine q35 -m "$MEM" -smp 2 \
        "${fwargs[@]}" \
        -cdrom "$ISO" -boot d \
        -vga std "${display[@]}" \
        -netdev user,id=n0 -device e1000,netdev=n0 \
        -serial "file:$log" -no-reboot &
    local pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if grep -aq 'hpe-live: READY' "$log"; then break; fi
        if [ $((SECONDS - start)) -ge "$TIMEOUT" ]; then rc=2; break; fi
        sleep 5
    done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    local line
    line="$(grep -a 'hpe-live: READY' "$log" | tail -n1 || true)"
    if [ -n "$line" ]; then
        echo "    $line (nach $((SECONDS - start))s)"
        case "$line" in *"rc=0"*) return 0 ;; *) echo "    -> Systemcheck meldet fehlende Teile" >&2; return 3 ;; esac
    fi
    echo "    KEIN READY-Marker (rc=$rc). Letzte Zeilen:" >&2
    tail -n 20 "$log" >&2
    return 1
}

fail=0
case "$MODE" in
    bios) run_one bios || fail=1 ;;
    uefi) run_one uefi || fail=1 ;;
    both) run_one bios || fail=1; run_one uefi || fail=1 ;;
    *) echo "Modus muss bios, uefi oder both sein" >&2; exit 2 ;;
esac
[ "$fail" -eq 0 ] && echo "OK: Boot-Test bestanden." || echo "FEHLER: Boot-Test fehlgeschlagen." >&2
exit "$fail"
