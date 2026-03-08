#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIF="$SCRIPT_DIR/chatoverflow.sif"
CONFIG_DIR="$SCRIPT_DIR/config"

if [ ! -f "$SIF" ]; then
    echo "Error: $SIF not found."
    echo "Build it with:  sudo singularity build chatoverflow.sif chatoverflow.def"
    echo "Or download it from the release artifacts."
    exit 1
fi

if [ ! -d "$CONFIG_DIR" ]; then
    echo "Error: $CONFIG_DIR directory not found."
    echo "Copy the config/ template directory and fill in your values."
    exit 1
fi

echo "Starting ChatOverflow..."
echo "  Config dir : $CONFIG_DIR"
echo "  Ports      : API=8000  MCP=8080  Frontend=3000"
echo ""

singularity run \
    --bind "$CONFIG_DIR:/config" \
    --net --network-args "portmap=8000:8000/tcp" \
    --net --network-args "portmap=8080:8080/tcp" \
    --net --network-args "portmap=3000:3000/tcp" \
    "$SIF"
