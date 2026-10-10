#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <backend-tag> <frontend-tag> <ml-tag>"
    exit 1
fi

BACKEND_TAG="$1"
FRONTEND_TAG="$2"
ML_TAG="$3"

export BACKEND_TAG FRONTEND_TAG ML_TAG

ENV_FILE="$ROOT_DIR/.env"
STATE_DIR="$ROOT_DIR/.deploy"
CURRENT_RELEASE_FILE="$STATE_DIR/current.env"
PREVIOUS_RELEASE_FILE="$STATE_DIR/previous.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: $ENV_FILE does not exist"
    exit 1
fi

validate_tag() {
    local tag="$1"

    if [[ ! "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
        echo "Error: invalid image tag: $tag"
        exit 1
    fi

    if [[ "$tag" == "latest" ]]; then
        echo "Error: 'latest' cannot be used for deploy/rollback"
        exit 1
    fi
}

wait_for_health() {
    local name="$1"
    shift

    for attempt in {1..30}; do
        if "$@" >/dev/null 2>&1; then
            echo "$name is healthy"
            return 0
        fi

        echo "Waiting for $name ($attempt/30)..."
        sleep 2
    done

    echo "Error: $name healthcheck failed"
    return 1
}

validate_tag "$BACKEND_TAG"
validate_tag "$FRONTEND_TAG"
validate_tag "$ML_TAG"

mkdir -p "$STATE_DIR"

COMPOSE=(
    docker compose
    --env-file "$ENV_FILE"
    --profile infra
    --profile app
    --profile ml
)

echo "Validating compose configuration..."
"${COMPOSE[@]}" config >/dev/null

echo "Pulling application images..."
"${COMPOSE[@]}" pull backend frontend ml

echo "Starting infrastructure..."
"${COMPOSE[@]}" up -d --wait postgres qdrant minio

echo "Initializing MinIO..."
"${COMPOSE[@]}" run --rm minio-init

if [[ -f "$CURRENT_RELEASE_FILE" ]]; then
    cp "$CURRENT_RELEASE_FILE" "$PREVIOUS_RELEASE_FILE"
fi

echo "Starting application..."
"${COMPOSE[@]}" up -d --no-deps backend frontend ml

echo "Checking application health..."

BACKEND_ADDRESS="$("${COMPOSE[@]}" port backend 8081)"

wait_for_health "backend" \
    curl -fsS --connect-timeout 2 --max-time 5 \
    "http://${BACKEND_ADDRESS}/health"

wait_for_health "ml" \
    "${COMPOSE[@]}" exec -T ml python -c \
    'import urllib.request; assert urllib.request.urlopen("http://127.0.0.1:8000/health", timeout=5).status == 200'

cat > "$CURRENT_RELEASE_FILE" <<EOF
BACKEND_TAG=$BACKEND_TAG
FRONTEND_TAG=$FRONTEND_TAG
ML_TAG=$ML_TAG
EOF

echo
echo "Deployment finished successfully."
"${COMPOSE[@]}" ps