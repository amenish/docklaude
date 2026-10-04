#!/usr/bin/env bash
set -Eeuo pipefail

VERBOSE=0
REBUILD=0
WORKSPACE_ARG=""

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
    -v|--verbose) VERBOSE=1 ;;
    -r|--rebuild) REBUILD=1 ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "Opción desconocida: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      [[ -z "$WORKSPACE_ARG" ]] || { echo "Solo se admite un directorio." >&2; exit 2; }
      WORKSPACE_ARG="$1"
      ;;
  esac
  shift
done

cd "$(dirname -- "$(realpath -- "$0")")"

run() {
  (( VERBOSE )) && printf '[verbose] Ejecutando: %s\n' "$*" >&2
  "$@"
}

choose_directory() {
  local selected="" start="$HOME"
  local gui="${DISPLAY:-}${WAYLAND_DISPLAY:-}"

  if [[ -n "$gui" ]] && command -v zenity >/dev/null 2>&1; then
    selected="$(zenity --file-selection --directory --filename="$start/" \
      --title='Selecciona el directorio de trabajo' 2>/dev/null || true)"
  fi

  if [[ -z "$selected" && -n "$gui" ]] && command -v kdialog >/dev/null 2>&1; then
    selected="$(kdialog --getexistingdirectory "$start" \
      --title 'Selecciona el directorio de trabajo' 2>/dev/null || true)"
  fi

  if [[ -z "$selected" ]] && command -v fzf >/dev/null 2>&1; then
    selected="$(find "$start" -type d -not -path '*/.git/*' 2>/dev/null |
      fzf --height=80% --layout=reverse --border --prompt='Directorio > ' \
        --header='Filtra, usa flechas y Enter' || true)"
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

[[ -d "$WORKSPACE_DIR" ]] || { echo "Directorio no válido: $WORKSPACE_DIR" >&2; exit 1; }

if [[ "$(stat -c '%u' -- "$WORKSPACE_DIR")" == 0 ]]; then
  echo "El directorio pertenece a root; no se ejecutará Claude como root:" >&2
  echo "  $WORKSPACE_DIR" >&2
  echo >&2
  echo "Si realmente debe pertenecer a tu usuario, puedes usar:" >&2
  echo "  sudo chown -R $(id -u):$(id -g) '$WORKSPACE_DIR'" >&2
  exit 1
fi

[[ -w "$WORKSPACE_DIR" ]] || { echo "No tienes permiso de escritura en: $WORKSPACE_DIR" >&2; exit 1; }

# Claude corre con el usuario que lanza el script (no con el dueño del
# directorio), así los archivos nuevos son suyos.
export WORKSPACE_DIR
export CONTAINER_UID="$(id -u)"
export CONTAINER_GID="$(id -g)"
export DOCKLAUDE_HOST="$(uname -n)"

# Grupos suplementarios del usuario, en un override que usan todos los
# comandos de docker compose a través de COMPOSE_FILE.
SUPPLEMENTARY_GIDS="$(id -G | tr ' ' '\n' | grep -vx "$CONTAINER_GID" | paste -sd, -)" || true
printf 'services:\n  claude:\n    group_add: [%s]\n' "$SUPPLEMENTARY_GIDS" > docker-compose.groups.yml
export COMPOSE_FILE=docker-compose.yml:docker-compose.groups.yml

if ! docker info >/dev/null 2>&1; then
  echo "Docker no está ejecutándose. Intentando iniciarlo..."
  sudo systemctl start docker
fi

# --- Memoria ---
# Colectiva: claude-memory/ (repo git privado, ignorado por docklaude), se
# sincroniza antes de arrancar y se monta en ~/.claude del contenedor.
# Del proyecto: .PROJECT.md en la raíz del workspace, fuera de su git.
PROJECT_MEMORY="$WORKSPACE_DIR/.PROJECT.md"

./memory-sync.sh init
./memory-sync.sh pull

[[ -e "$PROJECT_MEMORY" ]] || cp -- templates/PROJECT.md "$PROJECT_MEMORY"

if git -C "$WORKSPACE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
   ! git -C "$WORKSPACE_DIR" check-ignore -q -- .PROJECT.md; then
  GITIGNORE="$(git -C "$WORKSPACE_DIR" rev-parse --show-toplevel)/.gitignore"
  [[ ! -s "$GITIGNORE" || -z "$(tail -c1 -- "$GITIGNORE")" ]] || echo >> "$GITIGNORE"
  echo '.PROJECT.md' >> "$GITIGNORE"
  echo "Añadido .PROJECT.md a $GITIGNORE"
fi

if (( VERBOSE )); then
  echo "================ Claude Code / sandbox ================"
  printf 'Directorio host    : %s\n' "$WORKSPACE_DIR"
  printf 'Propietario/permisos: %s\n' "$(stat -c 'UID=%u GID=%g %A %a' -- "$WORKSPACE_DIR")"
  printf 'Usuario contenedor : UID=%s GID=%s\n' "$CONTAINER_UID" "$CONTAINER_GID"
  printf 'Grupos suplementarios: %s\n' "${SUPPLEMENTARY_GIDS:-(ninguno)}"
  printf 'Claude home        : claude-code-home -> /home/agent (login local de este PC)\n'
  printf 'Memoria colectiva  : %s -> ~/.claude/memoria-colectiva\n' "$PWD/claude-memory"
  printf 'Memoria proyecto   : %s\n' "$PROJECT_MEMORY"
  printf 'Seguridad          : read_only, cap_drop=ALL, no-new-privileges\n'
  echo "--- Configuración Compose resuelta ---"
  docker compose config
  echo "======================================================="
else
  docker compose config --quiet
fi

(( REBUILD )) && run docker compose build --pull

CLAUDE_RC=0
run docker compose run --rm claude || CLAUDE_RC=$?

# --- Al salir: 1) memoria colectiva, 2) git del proyecto ---
# La memoria va primero: no pregunta nada y queda a salvo aunque se corte
# después. Para el proyecto tiene prioridad el helper propio
# $SCRIPT_DIR/git_manager.sh si existe.
./memory-sync.sh push ||
  echo "Aviso: la memoria colectiva no se pudo subir; queda en local." >&2

if [[ -n "${SCRIPT_DIR:-}" && -f "$SCRIPT_DIR/git_manager.sh" ]]; then
  read -r -p "¿Ejecutar git_manager.sh en el workspace '$WORKSPACE_DIR'? [s/N] " ANSWER
  if [[ "$ANSWER" =~ ^[SsYy]$ ]]; then
    "$SCRIPT_DIR/git_manager.sh" "$WORKSPACE_DIR" ||
      echo "Aviso: git_manager.sh terminó con error." >&2
  fi
else
  ./project-sync.sh "$WORKSPACE_DIR" ||
    echo "Aviso: la sincronización git del proyecto no se completó." >&2
fi

exit "$CLAUDE_RC"
