mkdir -p /shared/w/npm && cp /src/npmapp/package.json /src/npmapp/package-lock.json /shared/w/npm/ && cd /shared/w/npm
npm ci --offline --cache /src/npmcache --no-audit --no-fund --loglevel=error > /tmp/npm.log 2>&1; echo "WORKLOAD npm exit=$?"
tail -5 /tmp/npm.log
echo "FILES $(find /shared/w/npm | wc -l) SYMLINKS $(find /shared/w/npm -type l | wc -l)"
./node_modules/.bin/tsc --version 2>&1 | head -1 | sed 's/^/TSC /'
