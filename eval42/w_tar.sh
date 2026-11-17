mkdir -p /shared/w/tar && tar -xpf /src/kata.tar -C /shared/w/tar; echo "WORKLOAD tar exit=$?"
echo "FILES $(find /shared/w/tar | wc -l) SYMLINKS $(find /shared/w/tar -type l | wc -l)"
