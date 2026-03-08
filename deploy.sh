#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-build}"

case "$MODE" in
  build)
    echo "--- Building locally and starting ---"
    docker compose up --build -d
    ;;
  pull)
    echo "--- Pulling latest images from ghcr.io ---"
    docker compose pull
    docker compose up -d
    ;;
  singularity)
    echo "--- Building Singularity SIF ---"
    sudo singularity build chatoverflow.sif chatoverflow.def
    echo "Done. Copy chatoverflow.sif + deploy/ to the target machine."
    ;;
  *)
    echo "Usage: $0 {build|pull|singularity}"
    echo "  build       - Build images locally and start (default)"
    echo "  pull        - Pull pre-built images from ghcr.io and start"
    echo "  singularity - Build the all-in-one Singularity SIF"
    exit 1
    ;;
esac

echo ""
echo "--- Services ---"
echo "  Frontend : http://localhost:3000"
echo "  API      : http://localhost:8000"
echo "  MCP      : http://localhost:8080"
