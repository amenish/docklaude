#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /workspace /tmp /run /home/agent/.claude
chmod 700 /home/agent/.claude 2>/dev/null || true
cd /workspace
exec "$@"
