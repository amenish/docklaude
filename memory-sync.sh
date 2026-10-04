#!/usr/bin/env bash
# Sincroniza la memoria colectiva (docklaude/claude-memory/) con su repo git privado.
# Se ejecuta siempre en el host: las credenciales de git nunca entran en el contenedor.
# Solo se sincroniza la memoria; el login y el resto de ~/.claude quedan en cada PC.
set -Eeuo pipefail

SELF_DIR="$(dirname -- "$(realpath -- "$0")")"
REPO="$SELF_DIR/claude-memory"
REMOTE="${DOCKLAUDE_MEMORY_REMOTE:-}"
INDEX="$REPO/MEMORIA.md"

# Nunca deben acabar en el repo de memoria.
FORBIDDEN=(.credentials.json .claude.json '*.jsonl')

usage() {
  cat <<EOF
Uso: $0 <comando>

Opera sobre $REPO (clon de tu repo privado de memoria).

Comandos:
  init   Clona o crea el repo y la estructura base si falta (idempotente).
         Con DOCKLAUDE_MEMORY_REMOTE=<url> clona ese repo si aún no existe.
  pull   Trae los cambios del remote antes de arrancar el contenedor.
  push   Hace commit y push de los cambios al salir.
EOF
}

info() { echo "memory-sync: $*" >&2; }
die() { info "$*"; exit 1; }

git_repo() { git -C "$REPO" "$@"; }

is_repo() { [[ -e "$REPO/.git" ]]; }
has_origin() { git_repo remote get-url origin >/dev/null 2>&1; }
has_commits() { git_repo rev-parse -q --verify HEAD >/dev/null 2>&1; }
has_upstream() { git_repo rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; }
current_branch() { git_repo symbolic-ref --short HEAD; }

ensure_line() {
  grep -qsxF -- "$2" "$1" || echo "$2" >> "$1"
}

# Rama por defecto del remote (vacío si el remote no tiene ramas).
remote_default_branch() {
  git_repo remote set-head origin -a >/dev/null 2>&1 || return 0
  git_repo symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##'
}

# Enlaza el repo local con origin cuando falta el upstream:
# - repo sin commits (p. ej. `git init` + `remote add`): adopta la rama remota;
# - repo con commits: fija el upstream si existe la misma rama en origin.
link_upstream() {
  local branch
  has_origin && ! has_upstream || return 0
  git_repo fetch -q origin 2>/dev/null || { info "No se pudo contactar con origin."; return 0; }

  if ! has_commits; then
    branch="$(remote_default_branch)"
    [[ -n "$branch" ]] || return 0   # remote vacío: el primer push fijará el upstream
    git_repo checkout -q -B "$branch" --track "origin/$branch" ||
      die "No se pudo traer origin/$branch a $REPO; ¿hay archivos locales que lo impiden?"
    info "Repo enlazado con origin/$branch."
  elif git_repo rev-parse -q --verify "refs/remotes/origin/$(current_branch)" >/dev/null; then
    git_repo branch -q -u "origin/$(current_branch)"
  fi
}

check_forbidden() {
  local tracked
  tracked="$(git_repo ls-files -- "${FORBIDDEN[@]}")"
  [[ -z "$tracked" ]] || die "Archivos sensibles en $REPO, no se sube nada: $tracked"
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
  if ! is_repo; then
    if [[ -n "$REMOTE" ]] && [[ -z "$(ls -A -- "$REPO" 2>/dev/null)" ]]; then
      git clone -q -- "$REMOTE" "$REPO"
      info "Clonado $REMOTE en $REPO."
    else
      git init -q "$REPO"
      info "Creado un repo local en $REPO."
      info "Para compartirlo entre PCs, añade tu repo privado (se subirá al salir):"
      info "  git -C '$REPO' remote add origin <url-privada>"
    fi
  fi
  link_upstream

  [[ -e "$REPO/CLAUDE.md" ]] || cp -- "$SELF_DIR/templates/CLAUDE.md" "$REPO/CLAUDE.md"
  [[ -e "$INDEX" ]] || printf '# Memoria colectiva\n\n' > "$INDEX"
  ensure_line "$REPO/.gitattributes" 'MEMORIA.md merge=union'
  local pattern
  for pattern in "${FORBIDDEN[@]}"; do ensure_line "$REPO/.gitignore" "$pattern"; done

  git_repo add -A
  check_forbidden
  git_repo diff --cached --quiet || git_repo commit -q -m "memoria: estructura base"
}

cmd_pull() {
  is_repo || die "$REPO no es un repo git; ejecuta: $0 init"
  link_upstream
  if has_upstream && ! git_repo pull -q --rebase --autostash; then
    git_repo rebase --abort >/dev/null 2>&1 || true
    info "AVISO: no se pudieron traer los cambios de la memoria colectiva."
    info "Se usa la copia local; revisa $REPO (git status, git pull) cuando puedas."
  fi
  dedupe_index
}

cmd_push() {
  is_repo || die "$REPO no es un repo git; ejecuta: $0 init"
  dedupe_index
  git_repo add -A
  check_forbidden
  git_repo diff --cached --quiet || git_repo commit -q -m "memoria colectiva desde $(uname -n)"

  has_origin || { info "Sin remote configurado; cambios guardados solo en local."; return 0; }
  link_upstream
  if ! has_upstream; then
    git_repo push -q -u origin HEAD || die "No se pudo hacer el primer push a origin."
    info "Upstream fijado en origin/$(current_branch)."
    return 0
  fi
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
