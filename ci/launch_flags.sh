#!/usr/bin/env bash
# Records how a Kata release launches virtiofsd with its unmodified default
# configuration, for the runtime-rs shim and the Go shim.
set -uo pipefail
V="$1"; R=${RESULTS:-$PWD/results}; mkdir -p "$R"
IMG=mirror.gcr.io/library/alpine:3.20
for i in 1 2 3; do sudo ctr images pull -q "$IMG" >/dev/null && break || sleep 10; done
DEF=/opt/kata/share/defaults/kata-containers
RS=$(ls $DEF/runtime-rs/configuration-qemu-runtime-rs.toml 2>/dev/null || ls $DEF/runtime-rs/configuration*qemu*.toml 2>/dev/null | head -1)
GO=$DEF/configuration-qemu.toml
mk() { sudo tee /usr/local/bin/containerd-shim-$1-v2 >/dev/null <<W
#!/bin/sh
export KATA_CONF_FILE=$2
exec $3 "\$@"
W
sudo chmod 0755 /usr/local/bin/containerd-shim-$1-v2; }
mk katarsdef "$RS" /opt/kata/runtime-rs/bin/containerd-shim-kata-v2
mk katagodef "$GO" /opt/kata/bin/containerd-shim-kata-v2
{
echo "Kata $V"; cat /opt/kata/VERSION 2>/dev/null; cat /tmp/kata-dl/asset.sha256
for pair in "katarsdef $RS" "katagodef $GO"; do
  set -- $pair; shim=$1; cfg=$2
  echo "=================== $shim  config $cfg ==================="
  sha256sum "$cfg"
  grep -nE '^(shared_fs|virtio_fs_daemon|virtio_fs_extra_args|virtio_fs_cache|virtio_fs_is_dax)\b' "$cfg"
  id="lf$(date +%s%N)"
  sudo timeout 300 ctr run -d --runtime "io.containerd.$shim.v2" --runtime-config-path "$cfg" "$IMG" "$id" sleep 300 >/dev/null 2>"$R/ctr_err_$shim.txt"
  sleep 10
  echo "--- daemon processes"
  ps -eo pid,ppid,user,args | grep -E '[v]irtiofsd' || echo "no virtiofsd process"
  echo "--- guest virtiofs mounts"
  sudo ctr task exec --exec-id m "$id" cat /proc/mounts 2>&1 | grep -E 'virtiofs|kataShared' || true
  sudo ctr task kill -s SIGKILL "$id" 2>/dev/null; sleep 3; sudo ctr task rm -f "$id" 2>/dev/null; sudo ctr container rm "$id" 2>/dev/null
  cat "$R/ctr_err_$shim.txt"
done
} > "$R/launch_flags_$V.txt" 2>&1
cat "$R/launch_flags_$V.txt"
