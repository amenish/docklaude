#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname -- "$(realpath -- "$0")")"

read -r -e -p "Ruta de un proyecto para completar el login: " WORKSPACE_DIR

WORKSPACE_DIR="$(realpath -e -- "$WORKSPACE_DIR")"

[[ -d "$WORKSPACE_DIR" ]] || {
  echo "Directorio no válido: $WORKSPACE_DIR" >&2
  exit 1
}

[[ -w "$WORKSPACE_DIR" ]] || {
  echo "No tienes permiso de escritura en: $WORKSPACE_DIR" >&2
  exit 1
}

OWNER_UID="$(stat -c '%u' -- "$WORKSPACE_DIR")"

if [[ "$OWNER_UID" == 0 ]]; then
  echo "El directorio pertenece a root; no se ejecutará Claude como root:" >&2
  echo "  $WORKSPACE_DIR" >&2
  exit 1
fi

# Always run Claude as the user who launched this script. The selected
# workspace is bind-mounted RW, while authentication/configuration is
# persisted in the dedicated claude-code-home volume.
export WORKSPACE_DIR
export CONTAINER_UID="$(id -u)"
export CONTAINER_GID="$(id -g)"

docker compose config --quiet
docker compose run --rm claude claude
