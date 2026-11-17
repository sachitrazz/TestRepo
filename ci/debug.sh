#!/usr/bin/env bash
set -x
IMG=mirror.gcr.io/library/alpine:3.20
sudo ctr images pull "$IMG" >/dev/null
/opt/vfsd/virtiofsd-filtered --version
ldd /opt/vfsd/virtiofsd-filtered | head
sudo cp ci/policies/listing2.toml /etc/kata-eval/policy.toml
for rt in katarsstock katarsfilt; do
  id="d$(date +%s%N)"
  sudo timeout 120 ctr run --rm --runtime io.containerd.$rt.v2 --runtime-config-path /etc/kata-eval/rs-${rt#katars}.toml \
       "$IMG" "$id" sh -c 'echo GUEST_OK; uname -r; cat /proc/mounts | head -5'
  echo "exit $?"
  ps -eo pid,ppid,args | grep -E '[v]irtiofsd|[q]emu|[s]him' | cut -c1-250
  sudo tail -30 /var/log/vfsd/stock-stderr.log /var/log/vfsd/audit.jsonl 2>&1
  sudo journalctl --since "-3min" --no-pager | grep -iE 'kata|virtiofs|shim|qemu' | tail -60 | cut -c1-300
  sudo pkill -f "$id" 2>/dev/null
done
