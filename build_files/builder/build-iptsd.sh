#!/bin/bash
# Build iptsd (the IPTS userspace daemon) from source.
#
# Dependencies are bundled statically via meson wraps, so the binaries only
# need libc/libstdc++ from the base image and survive Fedora library bumps.

set -euo pipefail

IPTSD_VERSION=v3.1.0

dnf5 install -y gcc-c++ meson ninja-build git-core cmake "pkgconfig(systemd)" "pkgconfig(udev)"

git clone --depth 1 --branch "$IPTSD_VERSION" https://github.com/linux-surface/iptsd.git /src/iptsd
cd /src/iptsd

meson setup build \
    --prefix=/usr \
    --sysconfdir=/etc \
    --buildtype=release \
    --wrap-mode=forcefallback \
    -Ddefault_library=static \
    -Dwerror=false \
    -Ddebug_tools=calibrate,dump

meson compile -C build
# --skip-subprojects: install iptsd only, not the bundled libraries' headers
DESTDIR=/out meson install -C build --skip-subprojects

echo "iptsd runtime libraries:"
ldd /out/usr/bin/iptsd

# Fail the build if systemd/udev integration silently went missing
test -f /out/usr/lib/systemd/system/iptsd@.service
ls /out/usr/lib/udev/rules.d/*iptsd*.rules
