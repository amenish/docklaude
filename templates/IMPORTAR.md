# Importar las memorias antiguas de un PC

Antes de docklaude con memoria colectiva, cada PC guardaba la memoria en su volumen
`claude-code-home`, mezclando todos los proyectos (todos se montaban en `/workspace`).
Ese volumen sigue montado en `/home/agent`, así que las memorias antiguas están en
`/home/agent/.claude/projects/*/memory/`.

El usuario lo pide con: «Importa las memorias antiguas siguiendo
~/.claude/memoria-colectiva/IMPORTAR.md». Se hace una vez en cada PC.

## Procedimiento (para Claude)

Sea `M=/home/agent/.claude/memoria-colectiva` y `PC=${DOCKLAUDE_HOST:-pc}`.

1. **Respaldo en bruto.** Copia cada `/home/agent/.claude/projects/<dir>/memory/`
   a `$M/inbox/$PC-<AAAAMMDD>/<dir>/`. Si no hay nada que copiar, dilo y termina.
2. **Clasifica** cada `.md` del respaldo (excepto `MEMORY.md`), aplicando la
   prueba de `CLAUDE.md`: «¿seguiría siendo cierto en otro proyecto?».
   - **Colectiva** → pásala a `$M/` con el formato de `CLAUDE.md` y añade su línea
     a `$M/MEMORIA.md`. Si ya existe una equivalente (de otro PC), fusiona las dos
     en una sola; manda la más reciente y precisa.
   - **Del proyecto abierto en `/workspace`** → incorpórala a `/workspace/.PROJECT.md`
     en la sección que corresponda, sin duplicar.
   - **De otro proyecto** → cópiala a `$M/inbox/proyectos/<nombre-del-proyecto>/`
     (nombre del repo o de su carpeta). Se incorporará sola la próxima vez que se
     abra ese proyecto.
   - **Dudosa** → déjala donde está y pregunta al usuario.
3. **Resumen final:** qué fue a la memoria colectiva, qué a `.PROJECT.md`, qué
   quedó en `inbox/proyectos/`, qué se fusionó y qué queda pendiente.
4. **Limpieza:** cuando el usuario confirme que todo está bien:
   - Borra `$M/inbox/$PC-<fecha>/`.
   - Las carpetas antiguas de `/home/agent/.claude/projects/*/memory/` solo se
     vacían si el usuario lo pide expresamente.

Al salir del contenedor, `run-claude.sh` sube los cambios al repo privado.
