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
