#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIF="$SCRIPT_DIR/chatoverflow.sif"
CONFIG_DIR="$SCRIPT_DIR/config"
DATA_DIR="$SCRIPT_DIR/data"
PGDATA="$DATA_DIR/pgdata"
LOG_DIR="$DATA_DIR/logs"
RUN_DIR="$DATA_DIR/run"
SQL_DIR="$SCRIPT_DIR/../supabase/docker-entrypoint-initdb.d"

if [ ! -f "$SIF" ]; then
    echo "Error: $SIF not found."
    echo "Build it with:  singularity build --fakeroot deploy/chatoverflow.sif chatoverflow.def"
    exit 1
fi

if [ ! -d "$CONFIG_DIR" ]; then
    echo "Error: $CONFIG_DIR directory not found."
    exit 1
fi

mkdir -p "$PGDATA" "$LOG_DIR/nginx" "$RUN_DIR"

# Generate PostgREST config with unix socket connection
cat > "$CONFIG_DIR/postgrest.conf" << EOF
db-uri = "postgres:///chatoverflow?host=$RUN_DIR&port=5433"
db-schemas = "public"
db-anon-role = "anon"
jwt-secret = "super-secret-jwt-token-with-at-least-32-characters-long"
server-port = 3100
EOF

# Common singularity options
SING_OPTS=(
    --writable-tmpfs
    --bind "$CONFIG_DIR:/config"
    --bind "$PGDATA:$PGDATA"
    --bind "$LOG_DIR:/var/log"
    --bind "$RUN_DIR:/run/postgresql"
    --bind "$CONFIG_DIR/supervisord.conf:/etc/supervisor/conf.d/chatoverflow.conf"
    --bind "$CONFIG_DIR/postgrest.conf:/etc/postgrest.conf"
    --bind "$SQL_DIR:/docker-entrypoint-initdb.d"
    --env "PGDATA=$PGDATA"
    --env "PGPORT=5433"
)

# Initialize PostgreSQL if needed — all in one singularity exec to avoid fuse-overlayfs timeout
if [ ! -f "$PGDATA/PG_VERSION" ]; then
    echo "==> Initializing PostgreSQL (all-in-one)..."
    singularity exec "${SING_OPTS[@]}" "$SIF" bash -c "
        set -e
        echo '  initdb...'
        /usr/lib/postgresql/17/bin/initdb -D \"$PGDATA\" --locale=C

        echo '  starting temporary server...'
        /usr/lib/postgresql/17/bin/pg_ctl -D \"$PGDATA\" \
            -o \"-p 5433 -c listen_addresses=127.0.0.1 -c unix_socket_directories=$RUN_DIR\" \
            -l \"$LOG_DIR/pg_init.log\" start -w

        echo '  creating database and extensions...'
        psql -h \"$RUN_DIR\" -p 5433 -d postgres -c 'CREATE DATABASE chatoverflow;'
        psql -h \"$RUN_DIR\" -p 5433 -d chatoverflow -c 'CREATE SCHEMA IF NOT EXISTS extensions;'
        psql -h \"$RUN_DIR\" -p 5433 -d chatoverflow -c 'CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\" WITH SCHEMA extensions;'
        psql -h \"$RUN_DIR\" -p 5433 -d chatoverflow -c 'CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;'

        echo '  running init SQL files...'
        for f in /docker-entrypoint-initdb.d/*.sql; do
            if [ -f \"\$f\" ]; then
                echo \"    \$(basename \$f)\"
                psql -h \"$RUN_DIR\" -p 5433 -d chatoverflow -f \"\$f\"
            fi
        done

        echo '  stopping temporary server...'
        /usr/lib/postgresql/17/bin/pg_ctl -D \"$PGDATA\" stop -w
        echo '==> PostgreSQL initialized.'
    "
    echo ""
fi

# Source env files for export
for f in "$CONFIG_DIR"/api.env "$CONFIG_DIR"/mcp.env "$CONFIG_DIR"/frontend.env; do
    if [ -f "$f" ]; then
        set -a; . "$f"; set +a
    fi
done

echo "Starting ChatOverflow..."
echo "  Config : $CONFIG_DIR"
echo "  Data   : $DATA_DIR"
echo "  Ports  : Frontend=4000  API=5000  MCP=4100  Gateway=18000"
echo ""

exec singularity exec \
    "${SING_OPTS[@]}" \
    --env "SUPABASE_URL=${SUPABASE_URL:-http://localhost:18000}" \
    --env "SUPABASE_SERVICE_KEY=${SUPABASE_SERVICE_KEY:-}" \
    --env "LLM_API_KEY=${LLM_API_KEY:-}" \
    --env "LLM_BASE_URL=${LLM_BASE_URL:-}" \
    --env "LLM_API_VERSION=${LLM_API_VERSION:-}" \
    --env "LLM_DEFAULT_HEADERS=${LLM_DEFAULT_HEADERS:-}" \
    --env "EMBEDDING_MODEL=${EMBEDDING_MODEL:-text-embedding-3-small}" \
    --env "CHATOVERFLOW_API_BASE=${CHATOVERFLOW_API_BASE:-http://localhost:5000}" \
    --env "NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL:-http://localhost:5000}" \
    --env "PORT=${PORT:-4100}" \
    "$SIF" \
    supervisord -c /etc/supervisor/conf.d/chatoverflow.conf
