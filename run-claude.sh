#!/usr/bin/env bash
set -Eeuo pipefail

VERBOSE=0
REBUILD=0
WORKSPACE_ARG=""
# Optional: export SCRIPT_DIR=/path/to/scripts before running
SCRIPT_DIR="${SCRIPT_DIR:-}"

usage() {
  cat <<EOF
Uso: $0 [opciones] [DIRECTORIO]

Opciones:
  -v, --verbose   Mostrar la configuración resuelta.
  -r, --rebuild   Reconstruir la imagen antes de arrancar.
  -h, --help      Mostrar esta ayuda.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)
      VERBOSE=1
      shift
      ;;
    -r|--rebuild)
      REBUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Opción desconocida: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      [[ -z "$WORKSPACE_ARG" ]] || {
        echo "Solo se admite un directorio." >&2
        exit 2
      }
      WORKSPACE_ARG="$1"
      shift
      ;;
  esac
done

cd "$(dirname -- "$(realpath -- "$0")")"

log() {
  if (( VERBOSE )); then
    printf '[verbose] %s\n' "$*" >&2
  fi
}

run() {
  log "Ejecutando: $*"
  "$@"
}

choose_directory() {
  local selected="" start="$HOME"

  if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    selected="$(
      zenity         --file-selection         --directory         --filename="${start}/"         --title='Selecciona el directorio de trabajo'         2>/dev/null || true
    )"
  fi

  if [[ -z "$selected" ]] &&
     command -v kdialog >/dev/null 2>&1 &&
     [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    selected="$(
      kdialog         --getexistingdirectory "$start"         --title 'Selecciona el directorio de trabajo'         2>/dev/null || true
    )"
  fi

  if [[ -z "$selected" ]] && command -v fzf >/dev/null 2>&1; then
    selected="$(
      find "$start"         -type d         -not -path '*/.git/*'         -print 2>/dev/null |
      fzf         --height=80%         --layout=reverse         --border         --prompt='Directorio > '         --header='Filtra, usa flechas y Enter' ||
      true
    )"
  fi

  [[ -n "$selected" ]] || {
    echo 'Instala zenity, kdialog o fzf para navegar interactivamente.' >&2
    exit 1
  }

  realpath -e -- "${selected/#\~/$HOME}"
}

if [[ -n "$WORKSPACE_ARG" ]]; then
  WORKSPACE_DIR="$(realpath -e -- "$WORKSPACE_ARG")"
else
  WORKSPACE_DIR="$(choose_directory)"
fi

[[ -d "$WORKSPACE_DIR" ]] || {
  echo "Directorio no válido: $WORKSPACE_DIR" >&2
  exit 1
}

# Claude should run as the host user, not merely as the current owner
# of the selected directory. This keeps newly-created files owned by
# the user launching the sandbox.
export CONTAINER_UID="$(id -u)"
export CONTAINER_GID="$(id -g)"
export HOST_UID="$CONTAINER_UID"
export HOST_GID="$CONTAINER_GID"
export WORKSPACE_DIR

OWNER_UID="$(stat -c '%u' -- "$WORKSPACE_DIR")"
OWNER_GID="$(stat -c '%g' -- "$WORKSPACE_DIR")"
MODE="$(stat -c '%A %a' -- "$WORKSPACE_DIR")"

if [[ "$OWNER_UID" == 0 ]]; then
  echo "El directorio pertenece a root; no se ejecutará Claude como root:" >&2
  echo "  $WORKSPACE_DIR" >&2
  echo >&2
  echo "Si realmente debe pertenecer a tu usuario, puedes usar:" >&2
  echo "  sudo chown -R $(id -u):$(id -g) '$WORKSPACE_DIR'" >&2
  exit 1
fi

[[ -w "$WORKSPACE_DIR" ]] || {
  echo "No tienes permiso de escritura en: $WORKSPACE_DIR" >&2
  exit 1
}

if (( VERBOSE )); then
  echo "================ Claude Code / sandbox ================"
  printf 'Script             : %s\n' "$0"
  printf 'Directorio host    : %s\n' "$WORKSPACE_DIR"
  printf 'Propietario actual : UID=%s GID=%s\n' "$OWNER_UID" "$OWNER_GID"
  printf 'Permisos directorio: %s\n' "$MODE"
  printf 'Usuario host       : UID=%s GID=%s\n' "$HOST_UID" "$HOST_GID"
  printf 'Usuario contenedor : UID=%s GID=%s\n' "$CONTAINER_UID" "$CONTAINER_GID"
  printf 'Montaje workspace  : %s:/workspace:rw\n' "$WORKSPACE_DIR"
  printf 'Claude home        : claude-code-home -> /home/agent\n'
  printf 'Red                : habilitada\n'
  printf 'Seguridad          : read_only, cap_drop=ALL, no-new-privileges\n'
  echo "======================================================="
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker no está ejecutándose. Intentando iniciarlo..."
  sudo systemctl start docker
fi

run docker compose config --quiet

if (( VERBOSE )); then
  echo '--- Configuración Compose resuelta ---'
  docker compose config
  echo '--- Fin configuración Compose ---'
fi

if (( REBUILD )); then
  run docker compose build --pull
fi

if (( VERBOSE )); then
  echo '--- Arranque ---'
  echo 'docker compose run --rm claude'
  echo '--- Fin arranque ---'
fi

docker compose run --rm claude

if [[ -n "${SCRIPT_DIR:-}" && -f "$SCRIPT_DIR/git_manager.sh" ]]; then
    read -r -p "¿Ejecutar git_manager.sh en el workspace '$WORKSPACE_DIR'? [y/N] " RUN_GIT_MANAGER
    if [[ "$RUN_GIT_MANAGER" =~ ^[Yy]$ ]]; then
        "$SCRIPT_DIR/git_manager.sh" "$WORKSPACE_DIR"
    fi
fi
