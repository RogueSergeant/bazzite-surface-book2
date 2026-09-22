#!/bin/bash

set -ouex pipefail

: "${KERNEL_VERSION:?KERNEL_VERSION must be set}"

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

# The IPTS module was copied in from the builder stage; register it so it
# autoloads (it matches the touch controller's MEI client UUID).
test -f "/usr/lib/modules/${KERNEL_VERSION}/extra/ipts/ipts.ko"
depmod -a "${KERNEL_VERSION}"
modinfo -k "${KERNEL_VERSION}" ipts | grep -E '^(filename|signer|alias)'

# Trust this image's own cosign key, so updates are verified like Bazzite's.
python3 - <<'EOF'
import json
path = "/etc/containers/policy.json"
with open(path) as f:
    policy = json.load(f)
policy["transports"]["docker"]["ghcr.io/roguesergeant/bazzite-surface-book2"] = [{
    "type": "sigstoreSigned",
    "keyPath": "/etc/pki/containers/bazzite-surface-book2.pub",
    "signedIdentity": {"type": "matchRepository"},
}]
with open(path, "w") as f:
    json.dump(policy, f, indent=4)
EOF

# iptsd is started per-device by its udev rule; make sure both landed.
test -x /usr/bin/iptsd
ls /usr/lib/udev/rules.d/*iptsd* /usr/lib/systemd/system/iptsd@.service
