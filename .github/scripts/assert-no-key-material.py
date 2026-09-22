#!/usr/bin/env python3
"""Fail if any fragment of the module-signing private key is in a filesystem stream.

Usage: podman export <container> | assert-no-key-material.py

The private key (PEM) is read from the MOK_KEY environment variable. Needles are
derived from it in every form a leak could plausibly take:

  * each base64 line of the PEM body (a copied .priv/.pem file)
  * slices of the raw DER encoding (a binary copy, e.g. a .der key)
  * the private exponent and primes as big-endian bytes (the key embedded in
    some other container format)

Nothing about the key is ever printed; on a hit only the needle's kind and
index are reported.
"""

import base64
import os
import subprocess
import sys

CHUNK = 8 * 1024 * 1024
SLICE = 32  # bytes per binary needle; long enough to never match by chance


def pem_body(pem: str) -> list[str]:
    return [
        line.strip()
        for line in pem.splitlines()
        if line.strip() and not line.startswith("-----")
    ]


def key_numbers(pem: str) -> list[bytes]:
    """Private exponent and primes, via openssl, as big-endian bytes."""
    out = subprocess.run(
        ["openssl", "pkey", "-noout", "-text"],
        input=pem.encode(),
        capture_output=True,
        check=True,
    ).stdout.decode()
    numbers, current, name = [], [], None
    for line in out.splitlines():
        if line and not line.startswith(" "):
            if name in ("privateExponent", "prime1", "prime2") and current:
                numbers.append(bytes.fromhex("".join(current).replace(":", "")).lstrip(b"\0"))
            name, current = line.rstrip(":").strip(), []
        else:
            current.append(line.strip())
    if name in ("privateExponent", "prime1", "prime2") and current:
        numbers.append(bytes.fromhex("".join(current).replace(":", "")).lstrip(b"\0"))
    return numbers


def slices(blob: bytes) -> list[bytes]:
    step = max(SLICE, len(blob) // 16)
    return [blob[i : i + SLICE] for i in range(0, len(blob) - SLICE, step)]


def main() -> int:
    pem = os.environ.get("MOK_KEY", "")
    if "PRIVATE KEY" not in pem:
        print("MOK_KEY is not set or is not a PEM private key", file=sys.stderr)
        return 2

    lines = pem_body(pem)
    der = base64.b64decode("".join(lines))

    needles: list[tuple[str, bytes]] = []
    needles += [(f"pem-line-{i}", l.encode()) for i, l in enumerate(lines) if len(l) >= 32]
    needles += [(f"der-slice-{i}", s) for i, s in enumerate(slices(der))]
    for n, num in enumerate(key_numbers(pem)):
        needles += [(f"number{n}-slice-{i}", s) for i, s in enumerate(slices(num))]

    overlap = max(len(n) for _, n in needles) - 1
    tail = b""
    scanned = 0
    stream = sys.stdin.buffer
    while True:
        chunk = stream.read(CHUNK)
        if not chunk:
            break
        window = tail + chunk
        for kind, needle in needles:
            if needle in window:
                print(f"KEY MATERIAL FOUND in image ({kind}). Refusing to publish.", file=sys.stderr)
                return 1
        tail = window[-overlap:]
        scanned += len(chunk)

    if scanned < 100 * 1024 * 1024:
        print(f"Only {scanned} bytes scanned; the export looks truncated.", file=sys.stderr)
        return 2

    print(f"OK: scanned {scanned / 2**30:.2f} GiB, {len(needles)} key needles, no matches.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
