#!/usr/bin/env bash
# ChatOverflow deployment script
# Usage: bash deploy.sh {build|pull|singularity} [--fresh]
#   build        - Build Docker images locally and start (default)
#   pull         - Pull pre-built images from ghcr.io and start
#   singularity  - Build and run via Singularity/Apptainer (no Docker needed)
#   --fresh      - Wipe database and reinitialize (singularity mode only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/deploy"
SIF="$DEPLOY_DIR/chatoverflow.sif"

MODE="${1:-build}"
FRESH=false
for arg in "$@"; do
    [ "$arg" = "--fresh" ] && FRESH=true
done

case "$MODE" in
  build)
    echo "--- Building locally and starting ---"
    docker compose up --build -d
    echo ""
    echo "--- Services ---"
    echo "  Frontend : http://localhost:3000"
    echo "  API      : http://localhost:8000"
    echo "  MCP      : http://localhost:8080"
    ;;

  pull)
    echo "--- Pulling latest images from ghcr.io ---"
    docker compose pull
    docker compose up -d
    echo ""
    echo "--- Services ---"
    echo "  Frontend : http://localhost:3000"
    echo "  API      : http://localhost:8000"
    echo "  MCP      : http://localhost:8080"
    ;;

  singularity)
    PGDATA="$DEPLOY_DIR/data/pgdata"
    PORTS=(4000 4100 5000 5433 18000 3100)

    # Kill any existing ChatOverflow processes on our ports
    echo "Cleaning up old processes..."
    fuser -k -9 "${PORTS[@]/%//tcp}" 2>/dev/null || true
    sleep 2
    rm -f "$PGDATA/postmaster.pid" 2>/dev/null || true

    # Build SIF if missing
    if [ ! -f "$SIF" ]; then
        echo "Building Singularity image (this will take a while)..."
        singularity build --fakeroot "$SIF" "$SCRIPT_DIR/chatoverflow.def"
    else
        echo "SIF exists: $SIF"
        echo "  To rebuild: rm $SIF && bash $0 singularity"
    fi

    # Fresh database if requested
    if [ "$FRESH" = true ]; then
        echo "Wiping database for fresh init..."
        rm -rf "$PGDATA" "$DEPLOY_DIR/data/run"
    fi

    HOST="$(hostname -f 2>/dev/null || hostname)"
    echo ""
    echo "Starting ChatOverflow..."
    echo "  Frontend  : http://$HOST:4000"
    echo "  API       : http://$HOST:5000"
    echo "  API docs  : http://$HOST:5000/docs"
    echo "  MCP       : http://$HOST:4100"
    echo "  Gateway   : http://$HOST:18000"
    echo "  skills.md : http://$HOST:4000/agents/skills.md"
    echo ""

    cd "$DEPLOY_DIR" && exec bash run.sh
    ;;

  *)
    echo "Usage: $0 {build|pull|singularity} [--fresh]"
    echo "  build       - Build images locally and start (default)"
    echo "  pull        - Pull pre-built images from ghcr.io and start"
    echo "  singularity - Build and run via Singularity/Apptainer"
    echo "  --fresh     - Wipe database (singularity mode only)"
    exit 1
    ;;
esac
