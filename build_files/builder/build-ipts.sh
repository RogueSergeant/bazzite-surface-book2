#!/bin/bash
# Build and sign the IPTS kernel module for $KERNEL_VERSION.
#
# The signing key is read in place from /run/secrets (a build-secret mount that
# is never part of any image layer). It is not copied, echoed or written
# anywhere; only the signed .ko is placed in /out.

set -euo pipefail

: "${KERNEL_VERSION:?KERNEL_VERSION must be set}"

KEY=/run/secrets/mok_key
CERT=/run/secrets/mok_cert
test -s "$KEY"  || { echo "mok_key secret missing" >&2; exit 1; }
test -s "$CERT" || { echo "mok_cert secret missing" >&2; exit 1; }

dnf5 install -y gcc make kmod openssl elfutils-libelf-devel git-core /tmp/rpms/kernel-devel-*.rpm

KDIR="/usr/src/kernels/${KERNEL_VERSION}"
test -d "$KDIR"

cd /src/ipts/src
for p in ../patches/*.patch; do
    echo "Applying $p"
    git apply -p1 "$p"
done

make -C "$KDIR" M="$PWD" modules

"$KDIR/scripts/sign-file" sha256 "$KEY" "$CERT" ipts.ko

modinfo ipts.ko | grep -E '^(vermagic|signer|sig_key|sig_hashalgo)'
modinfo -F vermagic ipts.ko | grep -q "^${KERNEL_VERSION} " \
    || { echo "vermagic does not match ${KERNEL_VERSION}" >&2; exit 1; }

install -D -m 644 ipts.ko "/out/usr/lib/modules/${KERNEL_VERSION}/extra/ipts/ipts.ko"
