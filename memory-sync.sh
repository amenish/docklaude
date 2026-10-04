#!/usr/bin/env bash
# Sincroniza la memoria colectiva (docklaude/claude-memory/) con su repo git privado.
# Se ejecuta siempre en el host: las credenciales de git nunca entran en el contenedor.
set -Eeuo pipefail

SELF_DIR="$(dirname -- "$(realpath -- "$0")")"
TEMPLATES_DIR="$SELF_DIR/templates"
REPO="$SELF_DIR/claude-memory"
INDEX="$REPO/MEMORIA.md"

usage() {
  cat <<EOF
Uso: $0 <comando>

Opera sobre $REPO (clon de tu repo privado de memoria).

Comandos:
  init   Crea la estructura base si falta (idempotente).
  pull   Trae los cambios del remote antes de arrancar el contenedor.
  push   Hace commit y push de los cambios al salir.
EOF
}

info() { echo "memory-sync: $*" >&2; }
die() { info "$*"; exit 1; }

git_repo() { git -C "$REPO" "$@"; }

has_upstream() { git_repo rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; }

copy_if_missing() {
  [[ -e "$2" ]] || cp -- "$1" "$2"
}

# Deja una sola línea de índice por archivo enlazado (tras merge=union).
dedupe_index() {
  local tmp
  [[ -f "$INDEX" ]] || return 0
  tmp="$(mktemp)"
  awk '
    match($0, /\]\([^)]+\)/) {
      key = substr($0, RSTART, RLENGTH)
      if (seen[key]++) next
    }
    { print }
  ' "$INDEX" > "$tmp"
  if cmp -s "$tmp" "$INDEX"; then rm -f "$tmp"; else mv "$tmp" "$INDEX"; fi
}

cmd_init() {
  mkdir -p "$REPO/inbox"
  if ! git_repo rev-parse --git-dir >/dev/null 2>&1; then
    git init -q "$REPO"
    info "Creado un repo local en $REPO."
    info "Para compartirlo entre PCs, añade tu repo privado:"
    info "  git -C '$REPO' remote add origin <url-privada> && git -C '$REPO' push -u origin HEAD"
  fi

  copy_if_missing "$TEMPLATES_DIR/CLAUDE.md" "$REPO/CLAUDE.md"
  copy_if_missing "$TEMPLATES_DIR/IMPORTAR.md" "$REPO/IMPORTAR.md"
  [[ -e "$INDEX" ]] || printf '# Memoria colectiva\n\n' > "$INDEX"
  [[ -e "$REPO/inbox/.gitkeep" ]] || : > "$REPO/inbox/.gitkeep"
  grep -qsxF 'MEMORIA.md merge=union' "$REPO/.gitattributes" ||
    echo 'MEMORIA.md merge=union' >> "$REPO/.gitattributes"

  git_repo add -A
  git_repo diff --cached --quiet || git_repo commit -q -m "memoria: estructura base"
}

cmd_pull() {
  git_repo rev-parse --git-dir >/dev/null 2>&1 || die "$REPO no es un repo git; ejecuta: $0 init"
  if has_upstream && ! git_repo pull -q --rebase --autostash 2>/dev/null; then
    git_repo rebase --abort >/dev/null 2>&1 || true
    info "No se pudieron traer cambios (¿sin red o conflicto?); se usa la copia local."
  fi
  dedupe_index
}

cmd_push() {
  git_repo rev-parse --git-dir >/dev/null 2>&1 || die "$REPO no es un repo git; ejecuta: $0 init"
  dedupe_index
  git_repo add -A
  git_repo diff --cached --quiet || git_repo commit -q -m "memoria colectiva desde $(hostname)"

  has_upstream || { info "Sin remote configurado; cambios guardados solo en local."; return 0; }
  [[ -n "$(git_repo log '@{u}..' --oneline)" ]] || return 0

  if ! git_repo push -q; then
    info "Push rechazado; integrando cambios remotos y reintentando."
    if ! git_repo pull -q --rebase; then
      git_repo diff --name-only --diff-filter=U >&2 || true
      die "Conflicto en $REPO. Resuélvelo (git status) y vuelve a ejecutar: $0 push"
    fi
    dedupe_index
    git_repo add -A
    git_repo diff --cached --quiet || git_repo commit -q -m "memoria: deduplicar índice"
    git_repo push -q || die "El push volvió a fallar; revisa $REPO."
  fi
}

case "${1:-}" in
  init) cmd_init ;;
  pull) cmd_pull ;;
  push) cmd_push ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
