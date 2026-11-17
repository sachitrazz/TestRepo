git clone -q /src/kata.git /shared/w/git; echo "WORKLOAD git exit=$?"
git -C /shared/w/git status --porcelain 2>&1 | wc -l | sed 's/^/GIT_STATUS_LINES /'
echo "FILES $(find /shared/w/git | wc -l) SYMLINKS $(find /shared/w/git -type l | wc -l)"
