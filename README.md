# bazzite-surface-book2

[Bazzite](https://bazzite.gg) (KDE) with working touchscreen and pen on the **Microsoft Surface Book 2 13"**.

Built nightly from `ghcr.io/ublue-os/bazzite:stable` and published at `ghcr.io/roguesergeant/bazzite-surface-book2`.

## Why

Starting with Fedora 44, Bazzite ships the OGC gaming kernel, which does not carry the
[linux-surface](https://github.com/linux-surface/linux-surface) patches. On IPTS-based
Surface devices that means no touchscreen and no pen
([ublue-os/bazzite#5476](https://github.com/ublue-os/bazzite/issues/5476)).

## What this image adds

| | |
|---|---|
| `ipts` kernel module | Intel Precise Touch & Stylus driver, built out-of-tree against the exact kernel in each Bazzite release and signed for Secure Boot. Source vendored in [`ipts/src`](ipts/src) from linux-surface's 7.2 patch set ([commit](ipts/src/UPSTREAM_COMMIT)). |
| Linux 7.x fix | [`ipts/patches/0001-…`](ipts/patches): 7.x `hid-core` rejects the driver's raw touch frames as too short (`Event data for report 65 was too short (7487 vs 7484)`), so every touch fails with `-EINVAL`. The patch switches to `hid_safe_input_report()` with a padded buffer. |
| `iptsd` | Userspace touch/pen processing daemon from [linux-surface/iptsd](https://github.com/linux-surface/iptsd), built from source with its dependencies linked statically. Includes the Surface Book 2 presets. |
| Base USB fix | udev rule keeping the base's USB hubs out of autosuspend; the hinge connector otherwise causes the keyboard and touchpad to repeatedly disconnect. |

The driver and `iptsd` also support other IPTS devices (Surface Pro 4–7, Book 1–3,
Laptop 1–3), but this image is only tested on, and tuned for, the Surface Book 2 13".
Newer devices that use `ithc` (Pro 7+, Pro 8+, Laptop 4+, Laptop Studio) are not covered.

## Secure Boot and the signing key

The `ipts` module is signed with a Machine Owner Key belonging to the repository owner.
The private key exists only as the `MOK_KEY` GitHub Actions secret:

- It is mounted as a **build secret** into a throwaway builder stage. Build secrets are
  never written to image layers, and the builder stage is never pushed; the final image
  only receives the signed `.ko`.
- Before every push, [`assert-no-key-material.py`](.github/scripts/assert-no-key-material.py)
  exports the complete final filesystem and fails the build if any fragment of the key
  (PEM lines, DER slices, or the raw private exponent and primes) is present.

**If you are not the owner**, your firmware won't trust this key. Fork the repo, generate
your own key, set the `MOK_KEY`/`MOK_CERT` secrets and enroll it with `mokutil --import`,
or disable Secure Boot.

## Using it

```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/roguesergeant/bazzite-surface-book2:latest
```

If a new Bazzite kernel ever breaks the build, the nightly job fails, nothing is
published, and machines stay on the last working image.
