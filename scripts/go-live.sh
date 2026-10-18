#!/usr/bin/env bash
# Puts Skittles online: the room server on this computer, reachable through a Cloudflare quick tunnel, and the website
# on Vercel pointing at it through config.json (the site and the downloaded apps both read it). Run it after a
# restart: the tunnel gets a new address each time, and this publishes it.
#
#   scripts/go-live.sh
#
# Starts the room server too if it is not running (port 3001, or SKITTLES_PORT). Needs cloudflared (brew install
# cloudflared) and the Vercel CLI logged in. The downloads it publishes sit in .deploy/site/download.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY="$ROOT/.deploy/site"
PORT="${SKITTLES_PORT:-3001}"
LOG="$ROOT/.deploy/tunnel.log"
mkdir -p "$DEPLOY/download"

# The server: start it in the background if it is not running (it keeps running after this script ends).
if ! curl -fsS -m 5 "http://localhost:$PORT/api/projects" >/dev/null 2>&1; then
  (cd "$ROOT/server" && PORT="$PORT" nohup node --env-file-if-exists=.env src/index.ts >"$ROOT/.deploy/server.log" 2>&1 &)
  for _ in $(seq 30); do
    curl -fsS -m 2 "http://localhost:$PORT/api/projects" >/dev/null 2>&1 && break
    sleep 1
  done
  curl -fsS -m 5 "http://localhost:$PORT/api/projects" >/dev/null 2>&1 || { echo "The server did not start; see .deploy/server.log"; exit 1; }
  echo "Started the server on port $PORT (log: .deploy/server.log)"
fi

# Reuse a working tunnel; otherwise start one that keeps running after this script (and this terminal) ends.
url=""
if [ -f "$LOG" ] && pgrep -f "cloudflared tunnel .*localhost:$PORT" >/dev/null; then
  url=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" | head -1 || true)
fi
if [ -z "$url" ] || ! curl -fsS -m 10 "$url/api/projects" >/dev/null 2>&1; then
  pkill -f "cloudflared tunnel .*localhost:$PORT" || true
  nohup cloudflared tunnel --no-autoupdate --url "http://localhost:$PORT" >"$LOG" 2>&1 &
  url=""
  for _ in $(seq 60); do
    url=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" | head -1 || true)
    [ -n "$url" ] && break
    sleep 1
  done
  [ -n "$url" ] || { echo "The tunnel did not start; see $LOG"; exit 1; }
  for _ in $(seq 60); do
    curl -fsS -m 5 "$url/api/projects" >/dev/null 2>&1 && break
    sleep 2
  done
fi
echo "Server: $url"

# The site, with the Windows button only once its download is there.
windows=""
[ -f "$DEPLOY/download/Skittles-windows.zip" ] && windows=1
(cd "$ROOT/web" && VITE_WINDOWS_READY="$windows" npm run build >/dev/null)
rsync -a --delete --exclude download --exclude .vercel --exclude vercel.json --exclude config.json "$ROOT/web/dist/" "$DEPLOY/"
printf '{"server": "%s"}\n' "$url" >"$DEPLOY/config.json"
printf '{ "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }] }\n' >"$DEPLOY/vercel.json"

(cd "$DEPLOY" && vercel deploy --prod --yes 2>&1) | grep -oE 'https://[a-z0-9.-]+\.vercel\.app' | sort -u
echo "Downloads: $(ls "$DEPLOY/download" | tr '\n' ' ')"
