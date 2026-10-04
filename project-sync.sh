#!/usr/bin/env bash
# Helper genérico de git para el proyecto, al salir de Claude Code.
# Pregunta antes de hacer nada; nunca fuerza un push ni resuelve conflictos solo.
set -Eeuo pipefail

DIR="${1:?Uso: $0 DIRECTORIO}"

info() { echo "project-sync: $*" >&2; }

git_p() { git -C "$DIR" "$@"; }

has_upstream() { git_p rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; }

if ! git_p rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  info "$DIR no es un repo git; nada que sincronizar."
  exit 0
fi

if [[ -n "$(git_p status --porcelain)" ]]; then
  echo "--- Cambios en $(git_p rev-parse --show-toplevel) ---"
  git_p status --short
  git_p diff --stat
  echo "---"

  read -r -p "¿Hacer commit de los cambios del proyecto (y push si hay upstream)? [s/N] " ANSWER
  [[ "$ANSWER" =~ ^[SsYy]$ ]] || { info "Sin commit; los cambios quedan en el directorio."; exit 0; }

  DEFAULT_MSG="Cambios desde docklaude ($(uname -n), $(date '+%Y-%m-%d %H:%M'))"
  read -r -e -p "Mensaje de commit [$DEFAULT_MSG]: " MSG
  git_p add -A
  git_p commit -q -m "${MSG:-$DEFAULT_MSG}"
  info "Commit: $(git_p log -1 --format='%h %s')"
  has_upstream || { info "La rama no tiene upstream; commit solo en local."; exit 0; }
else
  # Árbol limpio: puede haber commits hechos durante la sesión sin subir.
  has_upstream || { info "Sin cambios en el proyecto."; exit 0; }
  AHEAD="$(git_p rev-list --count '@{u}..')"
  (( AHEAD > 0 )) || { info "Sin cambios en el proyecto."; exit 0; }
  echo "--- $AHEAD commit(s) sin subir en $(git_p rev-parse --show-toplevel) ---"
  git_p log --oneline '@{u}..'
  echo "---"
  read -r -p "¿Hacer push? [s/N] " ANSWER
  [[ "$ANSWER" =~ ^[SsYy]$ ]] || { info "Sin push; los commits quedan en local."; exit 0; }
fi

if ! git_p pull -q --rebase --autostash; then
  git_p diff --name-only --diff-filter=U >&2 || true
  info "Conflicto al integrar los cambios remotos. Resuélvelo en $DIR"
  info "(git status, git rebase --continue) y haz git push."
  exit 1
fi

git_p push -q
info "Push hecho."
