#!/usr/bin/env python3
"""Prüft, ob alle Paketnamen aus live/**/package-lists in den konfigurierten
Repositories (Debian trixie, HPE MCP, NVIDIA CUDA) existieren.

Benötigt keine root-Rechte und kein live-build:  ./scripts/check_packages.py
"""
import gzip
import lzma
import pathlib
import re
import sys
import urllib.request

REPO = pathlib.Path(__file__).resolve().parent.parent
DEBIAN = "http://deb.debian.org/debian/dists"
INDICES = {
    "debian": [f"{DEBIAN}/{suite}/{comp}/binary-amd64/Packages.xz"
               for suite in ("trixie", "trixie-updates")
               for comp in ("main", "contrib", "non-free", "non-free-firmware")],
    "hpe": ["https://downloads.linux.hpe.com/SDR/repo/mcp/debian/dists/trixie/current/non-free/binary-amd64/Packages.gz"],
    "nvidia": ["https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/Packages.gz"],
}


def fetch(url):
    try:
        with urllib.request.urlopen(url, timeout=60) as r:
            data = r.read()
    except Exception as e:  # noqa: BLE001
        if "trixie-updates" in url:
            return ""
        raise SystemExit(f"Download fehlgeschlagen: {url}: {e}")
    if url.endswith(".xz"):
        data = lzma.decompress(data)
    elif url.endswith(".gz"):
        data = gzip.decompress(data)
    return data.decode("utf-8", "replace")


def names(text):
    out = set()
    for m in re.finditer(r"^(Package|Provides): (.+)$", text, re.M):
        if m.group(1) == "Package":
            out.add(m.group(2).strip())
        else:
            out.update(p.split("(")[0].strip() for p in m.group(2).split(","))
    return out


def main():
    avail = {k: set().union(*(names(fetch(u)) for u in v)) for k, v in INDICES.items()}
    lists = sorted((REPO / "live").rglob("package-lists/*.list.chroot"))
    missing = 0
    for f in lists:
        rel = f.relative_to(REPO)
        repos = ["debian", "hpe"] + (["nvidia"] if "optional" in str(rel) else [])
        pool = set().union(*(avail[r] for r in repos))
        for line in f.read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if not line or line.startswith("!"):
                continue
            for pkg in line.split():
                pkg = pkg.replace("@NVIDIA_KMOD_PACKAGE@", "nvidia-kernel-open-dkms")
                if pkg not in pool:
                    print(f"FEHLT  {rel}: {pkg}")
                    missing += 1
    print(f"{len(lists)} Listen geprüft, {missing} fehlende Pakete.")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
