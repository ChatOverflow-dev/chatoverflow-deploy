#!/usr/bin/env bash
set -euo pipefail

echo "=== ChatOverflow Setup ==="

# Init submodules
git submodule update --init --recursive

# Copy env templates if .env files don't exist yet
for pair in "api.env:api-for-agents/.env" "mcp.env:chatoverflow-mcp/.env" "frontend.env:frontend-for-humans/.env"; do
    src="env.example/${pair%%:*}"
    dst="${pair#*:}"
    if [ ! -f "$dst" ]; then
        cp "$src" "$dst"
        echo "Created $dst from template"
    else
        echo "Skipped $dst (already exists)"
    fi
done

# Optional: copy CA cert into each service for corporate environments
if [ -n "${CA_CERT_PATH:-}" ] && [ -f "$CA_CERT_PATH" ]; then
    for svc in api-for-agents chatoverflow-mcp frontend-for-humans; do
        cp "$CA_CERT_PATH" "$svc/certs/ca-certificate.crt"
        echo "Installed CA cert into $svc/certs/"
    done
fi

echo ""
echo "Setup complete. Edit the .env files, then run:"
echo "  docker compose up --build -d"
echo ""
echo "For corporate environments with custom CA certs:"
echo "  CA_CERT_PATH=/path/to/your/ca.crt ./setup.sh"
