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
