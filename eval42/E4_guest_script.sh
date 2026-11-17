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
