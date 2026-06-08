#!/usr/bin/env bash
# Set up a shared Stremio cache server in Docker.
# Idempotent: re-running just no-ops on existing pieces.

set -euo pipefail

CACHE_DIR="${CACHE_DIR:-/mnt/media/stremio}"
CACHE_SIZE_BYTES="${CACHE_SIZE_BYTES:-53687091200}"   # 50 GB
SERVER_URL="${SERVER_URL:-http://10.42.0.1:11470/}"
IMAGE="tsaridas/stremio-docker:latest"
CONTAINER="stremio-server"

need_root() {
  if [[ $EUID -ne 0 ]]; then
    exec sudo --preserve-env=CACHE_DIR,CACHE_SIZE_BYTES,SERVER_URL "$0" "$@"
  fi
}
need_root "$@"

echo ">> ensure docker"
systemctl is-active --quiet docker || systemctl enable --now docker

echo ">> ensure cache dir: $CACHE_DIR"
mkdir -p "$CACHE_DIR"
chown -R "${SUDO_USER:-root}:${SUDO_USER:-root}" "$CACHE_DIR"

echo ">> pull image"
docker pull "$IMAGE"

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo ">> remove existing container"
  docker rm -f "$CONTAINER"
fi

echo ">> run container"
docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  -p 11470:11470 \
  -p 12470:12470 \
  -v "$CACHE_DIR:/root/.stremio-server" \
  -e NO_CORS=1 \
  -e SERVER_URL="$SERVER_URL" \
  "$IMAGE"

echo ">> wait for HTTP"
for _ in {1..20}; do
  if curl -fsS -o /dev/null --max-time 2 http://127.0.0.1:11470/settings; then
    break
  fi
  sleep 1
done

echo ">> set cache size to ${CACHE_SIZE_BYTES} bytes"
curl -fsS -X POST -H 'Content-Type: application/json' \
  -d "{\"cacheSize\":${CACHE_SIZE_BYTES}}" \
  http://127.0.0.1:11470/settings >/dev/null

echo ">> done. server reachable at http://127.0.0.1:11470/"
echo "   point Stremio clients at:  $SERVER_URL"
