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

TLS_DOMAIN="dev.deja-view.ru"

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

ensure_tls_certificate() {
    if "${COMPOSE[@]}" run --rm --no-deps \
        --entrypoint /bin/sh certbot \
        -c "test -s /etc/letsencrypt/live/$TLS_DOMAIN/fullchain.pem && \
            test -s /etc/letsencrypt/live/$TLS_DOMAIN/privkey.pem" \
        >/dev/null 2>&1; then

        echo "TLS certificate already exists"
        return
    fi

    echo "TLS certificate not found. Starting bootstrap nginx..."

    "${COMPOSE[@]}" stop nginx certbot >/dev/null 2>&1 || true

    if ! "${COMPOSE[@]}" \
        --profile tls-bootstrap \
        up -d --wait nginx-bootstrap; then

        cleanup_tls_bootstrap
        echo "Error: failed to start bootstrap nginx"
        return 1
    fi

    trap cleanup_tls_bootstrap EXIT INT TERM

    echo "Requesting certificate from Let's Encrypt via webroot..."

    if ! "${COMPOSE[@]}" \
        --profile tls-bootstrap \
        run --rm --no-deps \
        --entrypoint certbot \
        certbot \
        certonly \
        --webroot \
        --webroot-path /var/www/certbot \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        -d "$TLS_DOMAIN"; then

        cleanup_tls_bootstrap
        trap - EXIT INT TERM

        echo "Error: failed to obtain TLS certificate"
        return 1
    fi

    cleanup_tls_bootstrap
    trap - EXIT INT TERM

    echo "TLS certificate obtained successfully"
}

cleanup_tls_bootstrap() {
    "${COMPOSE[@]}" \
        --profile tls-bootstrap \
        rm -sf nginx-bootstrap \
        >/dev/null 2>&1 || true
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
    --profile tls
)

echo "Validating compose configuration..."
"${COMPOSE[@]}" config >/dev/null

echo "Pulling application images..."
"${COMPOSE[@]}" pull backend frontend ml

echo "Starting infrastructure..."
"${COMPOSE[@]}" up -d --wait postgres qdrant minio

echo "Initializing MinIO..."
"${COMPOSE[@]}" run --rm minio-init

echo "Ensuring TLS certificate..."
ensure_tls_certificate

echo "Starting application..."
"${COMPOSE[@]}" up -d --no-deps backend frontend ml

if "${COMPOSE[@]}" ps --status running --services | grep -qx nginx; then
    echo "Restarting nginx..."
    "${COMPOSE[@]}" restart nginx
else
    echo "Starting nginx..."
    "${COMPOSE[@]}" up -d nginx
fi

echo "Starting certificate renewal..."
"${COMPOSE[@]}" up -d --no-deps certbot

echo "Checking application health..."

BACKEND_ADDRESS="$("${COMPOSE[@]}" port backend 8081)"

wait_for_health "backend" \
    curl -fsS --connect-timeout 2 --max-time 5 \
    "http://${BACKEND_ADDRESS}/health"

wait_for_health "ml" \
    "${COMPOSE[@]}" exec -T ml python -c \
    'import urllib.request; assert urllib.request.urlopen("http://127.0.0.1:8000/health", timeout=5).status == 200'

wait_for_health "frontend via HTTPS" \
    curl -fsS --connect-timeout 2 --max-time 5 \
    "https://${TLS_DOMAIN}/"

if [[ -f "$CURRENT_RELEASE_FILE" ]]; then
    cp "$CURRENT_RELEASE_FILE" "$PREVIOUS_RELEASE_FILE"
fi

cat > "$CURRENT_RELEASE_FILE" <<EOF
BACKEND_TAG=$BACKEND_TAG
FRONTEND_TAG=$FRONTEND_TAG
ML_TAG=$ML_TAG
EOF

echo
echo "Deployment finished successfully."
"${COMPOSE[@]}" ps