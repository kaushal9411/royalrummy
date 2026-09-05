#!/usr/bin/env bash
# "Option B" — git-based redeploy. Sibling to 06-redeploy-code.sh: pulls the
# latest main directly on the server instead of rsync-ing a local checkout.
# Useful when deploying from a machine that doesn't have a local clone of
# this repo, just SSH access — this script only needs the SSH key.
#
# One-time setup required on the server before the first run (this repo's
# git root is royalrummy/, one level above lakadiya/ — the whole repo gets
# cloned there, same as it exists locally):
#   ssh -i ./<key>.pem ubuntu@<ip>
#   git clone <your-royalrummy-repo-url> ~/royalrummy
#   # or, if the remote isn't set up yet: git init ~/royalrummy && cd
#   # ~/royalrummy && git remote add origin <url> && git fetch origin main
#   # && git reset --hard origin/main
#
# Same tail as 06 otherwise (install/migrate/build/restart), domain/SSL
# config untouched.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# shellcheck source=config.env
source ./config.env
# shellcheck source=credentials.txt
source ./credentials.txt

SSH_KEY="./${KEY_NAME}.pem"
REMOTE="ubuntu@${PUBLIC_IP}"

echo "Pulling latest main directly on ${REMOTE}..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$REMOTE" bash -s <<'REMOTE_SCRIPT'
set -euo pipefail
cd ~/royalrummy
export NODE_OPTIONS="--max-old-space-size=1536"

echo "-- git fetch + reset --hard origin/main --"
git fetch origin main
git reset --hard origin/main

echo "-- backend: npm install --"
cd ~/royalrummy/lakadiya/backend
npm install

echo "-- migrate (no-op if nothing changed) --"
npm run migrate

echo "-- admin: npm install + build --"
cd ~/royalrummy/lakadiya/admin
npm install
npm run build

echo "-- restarting via pm2 --"
pm2 restart lakadiya-backend lakadiya-admin
pm2 save
REMOTE_SCRIPT

echo ""
echo "== Redeploy done (via git) — domain/SSL config untouched =="
