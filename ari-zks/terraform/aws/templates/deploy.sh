#!/bin/bash
# Pull de l'image et (re)démarrage des instances Private et Public.
#
# Usage (root) :
#   /opt/ari-zks/deploy.sh            # re-pull de l'image configurée
#   /opt/ari-zks/deploy.sh <image>    # change d'image puis déploie
set -euo pipefail

APP_DIR=/opt/ari-zks

param() {
  cat "$APP_DIR/config/$1"
}

if [ -n "${1:-}" ]; then
  printf '%s' "$1" > "$APP_DIR/config/container_image"
fi

IMAGE=$(param container_image)
param registry_password | docker login "${IMAGE%%/*}" -u "$(param registry_username)" --password-stdin
docker pull "$IMAGE"

umask 077
cat > $APP_DIR/app.env <<EOF
ENV=aws
ENCRYPTION_KEY=$(param encryption_key)
REVOLV_SHARED_SECRET=$(param revolv_shared_secret)
DATABASE_URL=sqlite:////app/data/data.db
PORT=8000
EOF

# run <instance_id> <port local> <allow_private_access>
run() {
  docker rm -f "$1" 2>/dev/null || true
  docker run -d --name "$1" --restart unless-stopped \
    --env-file $APP_DIR/app.env \
    -e INSTANCE_ID="$1" \
    -e ALLOW_PRIVATE_ACCESS="$3" \
    -v $APP_DIR/volume/app:/app/data \
    -p 127.0.0.1:"$2":8000 \
    --log-opt max-size=10m --log-opt max-file=3 \
    "$IMAGE"
}

run private 8001 true
run public 8002 false

docker image prune -f
