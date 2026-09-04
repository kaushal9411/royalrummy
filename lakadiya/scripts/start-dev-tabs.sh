#!/usr/bin/env bash
# Frees the app ports, then opens ONE gnome-terminal window with 2 tabs:
# backend (:3001) and admin (:3000).
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO_ROOT/scripts"

echo "== Freeing ports 3000, 3001 =="
for port in 3000 3001; do
  pid=$(lsof -ti tcp:"$port" 2>/dev/null || true)
  if [ -n "$pid" ]; then
    echo "Killing PID $pid on port $port"
    kill -9 $pid 2>/dev/null || true
  fi
done

gnome-terminal \
  --tab --title="Backend :3001" --command="bash '$SCRIPTS/tab-backend.sh'" \
  --tab --title="Admin :3000" --command="bash '$SCRIPTS/tab-admin.sh'"
