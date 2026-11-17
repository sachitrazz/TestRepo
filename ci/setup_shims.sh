#!/usr/bin/env bash
# Registers three containerd shims through wrapper scripts:
#   katarsstock : runtime-rs, QEMU, virtiofsd v1.14.0 built from this tree, no filter
#   katarsfilt  : runtime-rs, QEMU, the same binary with the filter enabled
#   katagostock : Go runtime, QEMU, Kata's own virtiofsd, configuration unmodified
set -euxo pipefail
BIN=/opt/vfsd/virtiofsd-filtered
DEF=/opt/kata/share/defaults/kata-containers
RS_DEF=$(ls $DEF/runtime-rs/configuration-qemu-runtime-rs.toml 2>/dev/null || ls $DEF/runtime-rs/configuration*qemu*.toml | head -1)
GO_DEF=$DEF/configuration-qemu.toml
sudo mkdir -p /etc/kata-eval /var/log/vfsd
sudo chmod 0777 /var/log/vfsd
sudo tee /opt/vfsd/vfsd-stock >/dev/null <<W
#!/bin/sh
exec 2>>/var/log/vfsd/stock-stderr.log
exec $BIN "\$@"
W
sudo tee /opt/vfsd/vfsd-filt >/dev/null <<W
#!/bin/sh
export VFSD_FILTER_CONFIG=/etc/kata-eval/policy.toml
exec 2>>/var/log/vfsd/audit.jsonl
exec $BIN "\$@"
W
sudo chmod 0755 /opt/vfsd/vfsd-stock /opt/vfsd/vfsd-filt
VALID='["/opt/vfsd/vfsd-stock","/opt/vfsd/vfsd-filt","/opt/kata/libexec/virtiofsd"]'
for v in stock filt; do
  sudo sed -E "s|^virtio_fs_daemon = .*|virtio_fs_daemon = \"/opt/vfsd/vfsd-$v\"|; s|^valid_virtio_fs_daemon_paths = .*|valid_virtio_fs_daemon_paths = $VALID|" \
    "$RS_DEF" | sudo tee /etc/kata-eval/rs-$v.toml >/dev/null
done
[ -f "$GO_DEF" ] && sudo cp "$GO_DEF" /etc/kata-eval/go-stock.toml
mk_shim() { # name config real_shim
  sudo tee /usr/local/bin/containerd-shim-$1-v2 >/dev/null <<W
#!/bin/sh
export KATA_CONF_FILE=$2
exec $3 "\$@"
W
  sudo chmod 0755 /usr/local/bin/containerd-shim-$1-v2
}
mk_shim katarsstock /etc/kata-eval/rs-stock.toml /opt/kata/runtime-rs/bin/containerd-shim-kata-v2
mk_shim katarsfilt  /etc/kata-eval/rs-filt.toml  /opt/kata/runtime-rs/bin/containerd-shim-kata-v2
if [ -x /opt/kata/bin/containerd-shim-kata-v2 ] && [ -f "$GO_DEF" ]; then
  mk_shim katagostock /etc/kata-eval/go-stock.toml /opt/kata/bin/containerd-shim-kata-v2
else
  echo "no Go runtime shim in this release"
fi
echo "runtime-rs default config: $RS_DEF"
grep -nE '^(shared_fs|virtio_fs_daemon|valid_virtio_fs_daemon_paths|virtio_fs_extra_args|virtio_fs_cache|virtio_fs_cache_size|virtio_fs_is_dax|kernel|image|default_memory|default_vcpus)\b' /etc/kata-eval/rs-filt.toml /etc/kata-eval/go-stock.toml || true
