#!/usr/bin/env bash
# Installs a Kata Containers static release under /opt/kata and makes KVM and
# vsock usable on a GitHub hosted Ubuntu runner.  Usage: setup_kata.sh VERSION
set -euxo pipefail
V="$1"
sudo apt-get update -qq && sudo apt-get install -y -qq zstd xz-utils jq >/dev/null
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
sudo udevadm control --reload-rules && sudo udevadm trigger --name-match=kvm || true
sudo modprobe vhost_vsock || true
sudo modprobe vhost_net || true
ls -l /dev/kvm /dev/vhost-vsock
mkdir -p /tmp/kata-dl
ASSET=$(gh release view "$V" -R kata-containers/kata-containers --json assets -q '.assets[].name' \
        | grep -E "^kata-static-${V}-amd64\.tar\.(zst|xz)$" | head -1)
echo "asset: $ASSET"
gh release download "$V" -R kata-containers/kata-containers -p "$ASSET" -D /tmp/kata-dl
sha256sum "/tmp/kata-dl/$ASSET" | tee /tmp/kata-dl/asset.sha256
case "$ASSET" in
  *.zst) sudo tar --zstd -xf "/tmp/kata-dl/$ASSET" -C / ;;
  *.xz)  sudo tar -xJf "/tmp/kata-dl/$ASSET" -C / ;;
esac
ls /opt/kata /opt/kata/bin /opt/kata/libexec /opt/kata/runtime-rs/bin 2>&1 || true
