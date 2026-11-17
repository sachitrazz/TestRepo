#!/usr/bin/env bash
# Host side preparation: real workload inputs and container images.
set -euxo pipefail
SRC=/tmp/eval/src
sudo mkdir -p /tmp/eval && sudo chmod 0777 /tmp/eval && mkdir -p $SRC
git clone -q --bare --depth 1 --branch 4.2.0 https://github.com/kata-containers/kata-containers $SRC/kata.git
git clone -q --depth 1 --branch 4.2.0 https://github.com/kata-containers/kata-containers /tmp/eval/katasrc
tar -cpf $SRC/kata.tar -C /tmp/eval katasrc
mkdir -p $SRC/npmapp && cd $SRC/npmapp
cat > package.json <<'J'
{ "name": "fpcheck", "version": "1.0.0", "private": true,
  "dependencies": { "typescript": "5.6.3", "express": "4.21.1", "eslint": "9.14.0" } }
J
npm install --cache $SRC/npmcache --no-audit --no-fund --loglevel=error
rm -rf node_modules
cd /
chmod -R a+rwX $SRC
for img in mirror.gcr.io/library/alpine:3.20 mirror.gcr.io/library/bash:5.2 mirror.gcr.io/library/node:22-alpine \
           mirror.gcr.io/library/python:3.12-alpine docker.io/alpine/git:v2.47.2; do
  for i in 1 2 3; do sudo ctr images pull -q "$img" >/dev/null && break || sleep 10; done
done
sudo ctr images ls -q
du -sh $SRC/*
