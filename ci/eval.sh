#!/usr/bin/env bash
# Kata Containers 4.2.0 evaluation of the vfsd-filter decorator.
# Every section writes plain text into $R; nothing here is summarised by hand.
set -uo pipefail
R=${RESULTS:-$PWD/results}; mkdir -p "$R"
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=/opt/vfsd/virtiofsd-filtered
SHARE=/tmp/eval/share
SRC=/tmp/eval/src
ALPINE=mirror.gcr.io/library/alpine:3.20
BASH_IMG=docker.io/library/bash:5.2
NODE=mirror.gcr.io/library/node:22-alpine
PY=mirror.gcr.io/library/python:3.12-alpine
GIT=docker.io/alpine/git:v2.47.2
declare -A CFG=([katarsstock]=/etc/kata-eval/rs-stock.toml [katarsfilt]=/etc/kata-eval/rs-filt.toml [katagostock]=/etc/kata-eval/go-stock.toml)

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$R/progress.log"; }
policy() { sudo cp "$HERE/policies/$1.toml" /etc/kata-eval/policy.toml; echo "$1" > /tmp/eval/policy_name; }
fresh_share() { sudo rm -rf "$SHARE"; mkdir -p "$SHARE"; chmod 0777 "$SHARE"; }
drop_caches() { sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null; }
cid() { echo "c$(date +%s%N)"; }

# run_c RUNTIME IMAGE CMD...  (foreground, removed afterwards)
run_c() {
  local rt=$1 img=$2; shift 2
  sudo timeout 240 ctr run --rm \
    --runtime "io.containerd.$rt.v2" --runtime-config-path "${CFG[$rt]}" \
    --mount "type=bind,src=$SHARE,dst=/shared,options=rbind:rw" \
    --mount "type=bind,src=$SRC,dst=/src,options=rbind:rw" \
    "$img" "$(cid)" "$@"
}
# start_c RUNTIME ID : detached sleeping container
start_c() {
  sudo timeout 300 ctr run -d \
    --runtime "io.containerd.$1.v2" --runtime-config-path "${CFG[$1]}" \
    --mount "type=bind,src=$SHARE,dst=/shared,options=rbind:rw" \
    "$ALPINE" "$2" sleep 900 >/dev/null
  sleep 8
}
stop_c() { sudo timeout 30 ctr task kill -s SIGKILL "$1" 2>/dev/null; sleep 3; sudo timeout 30 ctr task rm -f "$1" 2>/dev/null; sudo timeout 30 ctr container rm "$1" 2>/dev/null; sleep 2; }
daemon_pids() { pgrep -f 'virtiofsd' | sort -n; }

audit_reset() { : | sudo tee /var/log/vfsd/audit.jsonl >/dev/null; }
audit_summary() { # label
  local f=/var/log/vfsd/audit.jsonl
  sleep 1
  python3 - "$f" "$1" <<'PY'
import json, sys, collections
f, label = sys.argv[1], sys.argv[2]
recs = []
other = 0
for line in open(f, errors="replace"):
    line = line.strip()
    if line.startswith('{"ts_wall'):
        try: recs.append(json.loads(line))
        except Exception: other += 1
    elif line: other += 1
dec = collections.Counter(r.get("decision") for r in recs)
deny_reason = collections.Counter(r.get("reason", "") for r in recs if r.get("decision") == "deny")
deny_op = collections.Counter(r.get("op") for r in recs if r.get("decision") == "deny")
dots = collections.Counter((r.get("op"), r.get("name"), r.get("decision")) for r in recs if r.get("name") in (".", ".."))
print(f"== audit {label}: records {len(recs)} allow {dec.get('allow',0)} deny {dec.get('deny',0)} non_json_lines {other}")
for k, v in deny_reason.most_common(): print(f"   deny reason {v:7d}  {k}")
for k, v in deny_op.most_common(): print(f"   deny op     {v:7d}  {k}")
for k, v in dots.most_common(): print(f"   dot name    {v:7d}  op={k[0]} name={k[1]} decision={k[2]}")
names = collections.Counter(r.get("name") for r in recs if r.get("decision") == "deny")
for k, v in names.most_common(25): print(f"   deny name   {v:7d}  {k}")
PY
}

sudo mkdir -p /tmp/eval && sudo chmod 0777 /tmp/eval
mkdir -p "$SRC"
WANT=" ${*:-E0 E1 E2 E3 E4 E5 E6} "
want() { case "$WANT" in *" $1 "*) return 0;; esac; return 1; }

############################################################################
if want E0; then
log "E0 environment and hashes"
{
  date -u; uname -a; nproc; free -m; lscpu | grep -E 'Model name|Hypervisor|Virtualization'
  ls -l /dev/kvm /dev/vhost-vsock
  containerd --version; sudo ctr version | head -8
  echo "--- kata"; cat /opt/kata/VERSION 2>/dev/null
  /opt/kata/bin/kata-runtime --version 2>&1 | head -3
  /opt/kata/bin/qemu-system-x86_64 --version 2>&1 | head -1
  /opt/kata/libexec/virtiofsd --version 2>&1 | head -1
  $BIN --version 2>&1 | head -1
  grep -A3 -E '^\s+virtiofsd:|^\s+qemu:' /opt/kata/versions.yaml 2>/dev/null | head -20
  echo "--- sha256"
  sha256sum $BIN /opt/vfsd/vfsd-stock /opt/vfsd/vfsd-filt /etc/kata-eval/*.toml "$HERE"/policies/*.toml \
            /opt/kata/runtime-rs/bin/containerd-shim-kata-v2 /opt/kata/bin/containerd-shim-kata-v2 \
            /opt/kata/libexec/virtiofsd /tmp/kata-dl/kata-static-* 2>&1
  echo "--- runtime-rs config keys"
  grep -nE '^(shared_fs|virtio_fs_daemon|valid_virtio_fs_daemon_paths|virtio_fs_extra_args|virtio_fs_cache|virtio_fs_cache_size|virtio_fs_is_dax|default_memory|default_vcpus)\b' /etc/kata-eval/*.toml
} > "$R/E0_environment.txt" 2>&1

fi
############################################################################
if want E1; then
log "E1 kata facts: daemon command line, guest mounts, process maps"
policy listing2
{
RTS="katarsstock katarsfilt"; [ -x /usr/local/bin/containerd-shim-katagostock-v2 ] && RTS="$RTS katagostock"
echo "release ships Go shim: $([ -x /opt/kata/bin/containerd-shim-kata-v2 ] && echo yes || echo no)"
for rt in $RTS; do
  fresh_share
  before=$(daemon_pids | tr '\n' ' ')
  id=$(cid); start_c "$rt" "$id"
  echo "=================== $rt ==================="
  echo "--- daemon processes (pid ppid user args)"
  ps -eo pid,ppid,user,args | grep -E '[v]irtiofsd|[v]fsd-'
  echo "--- guest /proc/mounts (virtiofs)"
  sudo timeout 60 ctr task exec --exec-id m1 "$id" cat /proc/mounts | grep -E 'virtiofs|kataShared' || true
  echo "--- guest kernel"; sudo timeout 60 ctr task exec --exec-id m2 "$id" uname -a || true
  for p in $(daemon_pids); do
    case " $before " in *" $p "*) continue;; esac
    echo "--- pid $p"
    sudo cat /proc/$p/cmdline | tr '\0' ' '; echo
    sudo grep -E 'VmSize|VmRSS|Threads' /proc/$p/status
    sudo tr '\0' '\n' < /proc/$p/environ | grep -E '^VFSD_FILTER_CONFIG' || echo "VFSD_FILTER_CONFIG unset"
    sudo pmap -x $p > "$R/E1_pmap_${rt}_$p.txt" 2>&1
    tail -1 "$R/E1_pmap_${rt}_$p.txt"
  done
  stop_c "$id"
done
echo "--- filtered daemon stderr markers"; grep -h 'vfsd-filter:' /var/log/vfsd/audit.jsonl | sort | uniq -c
} > "$R/E1_kata_facts.txt" 2>&1

fi
############################################################################
if want E2; then
log "E2 smoke, symlink policy and ten target mutations, stock and filtered"
cat > $SRC/e2.sh <<'SH'
cd /shared
echo hi > normal.txt && echo NORMAL_WRITE=ALLOWED || echo NORMAL_WRITE=DENIED
if echo x > probe.filter-test 2>/tmp/e; then echo FILTERED_WRITE=ALLOWED; else echo "FILTERED_WRITE=DENIED $(cat /tmp/e)"; fi
echo target > target.txt
ln -s target.txt rel-link 2>/tmp/e && echo RELATIVE_SYMLINK=ALLOWED || echo "RELATIVE_SYMLINK=DENIED $(cat /tmp/e)"
ln -s /etc/passwd abs-link 2>/tmp/e && echo ABSOLUTE_SYMLINK=ALLOWED || echo "ABSOLUTE_SYMLINK=DENIED $(cat /tmp/e)"
ln -s ../outside dotdot-link 2>/tmp/e && echo DOTDOT_SYMLINK=ALLOWED || echo "DOTDOT_SYMLINK=DENIED $(cat /tmp/e)"
mkdir -p nested/deeper
ln -s target.txt control-direct && echo CONTROL_DIRECT=ALLOWED || echo CONTROL_DIRECT=DENIED
ln -s control-direct control-chain-1 && echo CONTROL_CHAIN_1=ALLOWED || echo CONTROL_CHAIN_1=DENIED
ln -s control-chain-1 control-chain-2 && echo CONTROL_CHAIN_2=ALLOWED || echo CONTROL_CHAIN_2=DENIED
[ "$(cat control-chain-2 2>/dev/null)" = target ] && echo CONTROL_CHAIN_READ=PASS || echo CONTROL_CHAIN_READ=FAIL
i=0
for t in ../outside-01 ../../outside-02 ../../../outside-03 nested/../../outside-04 nested/../../../outside-05 ./../outside-06 nested/deeper/../../../outside-07 /tmp/vfsd-filter-test-target-08 //tmp/vfsd-filter-test-target-09 /tmp/../tmp/vfsd-filter-test-target-10; do
  i=$((i+1)); n=$(printf 'mutation-%02d.link' $i)
  if ln -s "$t" "$n" 2>/tmp/e; then echo "$n ALLOWED $t"; else echo "$n DENIED $t $(cat /tmp/e)"; fi
done
SH
{
for rt in katarsstock katarsfilt; do
  fresh_share; audit_reset
  echo "=================== $rt (policy listing2) ==================="
  run_c "$rt" "$ALPINE" sh /src/e2.sh
  echo "--- host side"
  for f in normal.txt probe.filter-test rel-link abs-link dotdot-link control-direct control-chain-1 control-chain-2; do
    [ -e "$SHARE/$f" ] || [ -L "$SHARE/$f" ] && echo "HOST $f PRESENT" || echo "HOST $f ABSENT"
  done
  echo "HOST mutation links present: $(ls "$SHARE" | grep -c '^mutation-')"
  [ "$rt" = katarsfilt ] && audit_summary "E2 $rt"
done
} > "$R/E2_smoke_symlink_mutation.txt" 2>&1
cp $SRC/e2.sh "$R/E2_guest_script.sh"

fi
############################################################################
if want E3; then
log "E3 write discrepancy and bulk transfer, interleaved order, five trials"
cat > $SRC/e3.sh <<'SH'
TIMEFORMAT='%3R'
for mode in plain fsync; do
  flag=""; [ "$mode" = fsync ] && flag="conv=fsync"
  rm -f /shared/big; sync; echo 3 > /proc/sys/vm/drop_caches
  t=$( { time dd if=/dev/zero of=/shared/big bs=1M count=256 $flag 2>/tmp/dd; } 2>&1 )
  echo "WRITE mode=$mode time_real_s=$t dd_reported_s=$(grep -o '[0-9.]* seconds' /tmp/dd | cut -d' ' -f1)"
done
sync; echo 3 > /proc/sys/vm/drop_caches
t=$( { time dd if=/shared/big of=/dev/null bs=1M 2>/tmp/dd; } 2>&1 )
echo "READ cold time_real_s=$t dd_reported_s=$(grep -o '[0-9.]* seconds' /tmp/dd | cut -d' ' -f1)"
t=$( { time dd if=/shared/big of=/dev/null bs=1M 2>/tmp/dd; } 2>&1 )
echo "READ warm time_real_s=$t dd_reported_s=$(grep -o '[0-9.]* seconds' /tmp/dd | cut -d' ' -f1)"
rm -f /shared/big
SH
cp $SRC/e3.sh "$R/E3_guest_script.sh"
policy listing2
{
for t in 1 2 3 4 5; do
  for rt in $(printf 'katarsstock\nkatarsfilt\n' | shuf); do
    fresh_share; drop_caches
    run_c "$rt" "$BASH_IMG" bash /src/e3.sh | sed "s/^/trial=$t runtime=$rt /"
  done
done
} > "$R/E3_bulk_interleaved.txt" 2>&1

fi
############################################################################
if want E4; then
log "E4 metadata: one process per operation versus one process for all, interleaved"
cat > $SRC/e4.sh <<'SH'
N=1000; D=/shared/md; mkdir -p $D
now() { echo "$EPOCHREALTIME"; }
el() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.6f", b-a}'; }
# style A: the original workload shape, an external process per read and delete
s=$(now); for i in $(seq 1 $N); do echo x > $D/a$i; done; e=$(now); echo "A_create $(el $s $e)"
sync; echo 3 > /proc/sys/vm/drop_caches
s=$(now); for i in $(seq 1 $N); do cat $D/a$i > /dev/null; done; e=$(now); echo "A_read $(el $s $e)"
s=$(now); for i in $(seq 1 $N); do rm $D/a$i; done; e=$(now); echo "A_delete $(el $s $e)"
# style B: one process, shell builtins only, one find for the deletes
s=$(now); for i in $(seq 1 $N); do printf 'x\n' > $D/b$i; done; e=$(now); echo "B_create $(el $s $e)"
sync; echo 3 > /proc/sys/vm/drop_caches
s=$(now); for i in $(seq 1 $N); do read -r _ < $D/b$i; done; e=$(now); echo "B_read $(el $s $e)"
s=$(now); find $D -name 'b*' -type f -delete; e=$(now); echo "B_delete $(el $s $e)"
# style C: process start alone, no file system work
s=$(now); for i in $(seq 1 $N); do /bin/true; done; e=$(now); echo "C_spawn_only $(el $s $e)"
SH
cp $SRC/e4.sh "$R/E4_guest_script.sh"
policy listing2
{
for t in 1 2 3 4 5; do
  for rt in $(printf 'katarsstock\nkatarsfilt\n' | shuf); do
    fresh_share; drop_caches
    run_c "$rt" "$BASH_IMG" bash /src/e4.sh | sed "s/^/trial=$t runtime=$rt /"
  done
done
} > "$R/E4_metadata_interleaved.txt" 2>&1

fi
############################################################################
if want E5; then
log "E5 real guest workloads under three policies, audit level all"
cat > $SRC/w_tar.sh <<'SH'
mkdir -p /shared/w/tar && tar -xpf /src/kata.tar -C /shared/w/tar; echo "WORKLOAD tar exit=$?"
echo "FILES $(find /shared/w/tar | wc -l) SYMLINKS $(find /shared/w/tar -type l | wc -l)"
SH
cat > $SRC/w_git.sh <<'SH'
git clone -q /src/kata.git /shared/w/git; echo "WORKLOAD git exit=$?"
git -C /shared/w/git status --porcelain 2>&1 | wc -l | sed 's/^/GIT_STATUS_LINES /'
echo "FILES $(find /shared/w/git | wc -l) SYMLINKS $(find /shared/w/git -type l | wc -l)"
SH
cat > $SRC/w_npm.sh <<'SH'
mkdir -p /shared/w/npm && cp /src/npmapp/package.json /src/npmapp/package-lock.json /shared/w/npm/ && cd /shared/w/npm
npm ci --offline --cache /src/npmcache --no-audit --no-fund --loglevel=error > /tmp/npm.log 2>&1; echo "WORKLOAD npm exit=$?"
tail -5 /tmp/npm.log
echo "FILES $(find /shared/w/npm | wc -l) SYMLINKS $(find /shared/w/npm -type l | wc -l)"
./node_modules/.bin/tsc --version 2>&1 | head -1 | sed 's/^/TSC /'
SH
cat > $SRC/w_venv.sh <<'SH'
python -m venv /shared/w/venv > /tmp/v.log 2>&1; echo "WORKLOAD venv exit=$?"
tail -3 /tmp/v.log
/shared/w/venv/bin/python -c 'print("VENV_PYTHON_OK")' 2>&1 | tail -1
echo "FILES $(find /shared/w/venv | wc -l) SYMLINKS $(find /shared/w/venv -type l | wc -l)"
SH
{
for wl in tar git npm venv; do
  case $wl in tar) img=$ALPINE; cmd="sh /src/w_tar.sh";; git) img=$GIT; cmd="sh /src/w_git.sh";;
              npm) img=$NODE; cmd="sh /src/w_npm.sh";; venv) img=$PY; cmd="sh /src/w_venv.sh";; esac
  echo "=================== workload $wl, stock ==================="
  fresh_share; run_c katarsstock "$img" $cmd
  for pol in listing2_all dotdot_allowed_all chmod_denied_all; do
    echo "=================== workload $wl, filtered, policy $pol ==================="
    policy $pol; fresh_share; audit_reset
    run_c katarsfilt "$img" $cmd
    audit_summary "E5 $wl $pol"
    sudo cp /var/log/vfsd/audit.jsonl "$R/E5_audit_${wl}_${pol}.jsonl"
  done
done
} > "$R/E5_real_workloads.txt" 2>&1
cp $SRC/w_*.sh "$R/"
( cd "$R" && for f in E5_audit_*.jsonl; do gzip -9 "$f"; done )

fi
############################################################################
if want E6; then
log "E6 VSZ: process maps of the stock and filtered daemon, two runs each"
policy listing2
{
for rep in 1 2; do
for rt in katarsstock katarsfilt; do
  fresh_share
  before=$(daemon_pids | tr '\n' ' ')
  id=$(cid); start_c "$rt" "$id"
  for p in $(daemon_pids); do
    case " $before " in *" $p "*) continue;; esac
    echo "=== rep=$rep runtime=$rt pid=$p $(sudo grep -E 'VmSize' /proc/$p/status | tr -s ' ') $(sudo grep -E 'VmRSS' /proc/$p/status | tr -s ' ') $(sudo grep Threads /proc/$p/status | tr -s '\t' ' ')"
    sudo pmap -x $p | awk 'NR>2 && $2 ~ /^[0-9]+$/ {print}' | sort -k2 -n -r | head -12
  done
  stop_c "$id"
done
done
} > "$R/E6_vsz_maps.txt" 2>&1

fi
